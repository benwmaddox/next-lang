#!/usr/bin/env python3
"""Exercise the core output hooks against redirected streams and a pseudo-terminal."""

from __future__ import annotations

import os
from pathlib import Path
import pty
import re
import select
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
NLC = Path.home() / ".cache/next-lang/target/debug/nlc"
FAILURE = b"<source>:0:0: standard output write failed\n"


def run(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, **kwargs)


def build(package: str, stem: str, runtime: str, *, test: bool = False) -> tuple[Path, Path]:
    ir = ROOT / f"{package}/{stem}-{runtime}.ll"
    executable = ROOT / f"{package}/{stem}-{runtime}"
    command = [str(NLC), "run", "selfhost", "--", "build", package, "-o", ir.relative_to(ROOT).as_posix()]
    if test:
        command.append("--test")
    command.append(f"--runtime={runtime}")
    compiled = run(command, timeout=90)
    if compiled.returncode != 0:
        raise RuntimeError(f"build failed: {compiled.stderr.decode(errors='replace')}")
    linked = run([str(NLC), "link-ir", str(ir), "-o", str(executable)], timeout=90)
    if linked.returncode != 0:
        raise RuntimeError(f"link failed: {linked.stderr.decode(errors='replace')}")
    return ir, executable


def assert_failure(executable: Path, *, test_mode: bool = False) -> None:
    environment = os.environ.copy()
    if test_mode:
        environment["NLC_TEST_INDEX"] = "0"
    with open("/dev/full", "wb") as full:
        result = subprocess.run([str(executable)], cwd=ROOT, env=environment, stdout=full, stderr=subprocess.PIPE, check=False)
    expected = 70 if test_mode else 1
    if result.returncode != expected or result.stderr != FAILURE:
        raise RuntimeError(
            f"/dev/full mismatch for {executable.name}: status={result.returncode}, stderr={result.stderr!r}"
        )

    read_end, write_end = os.pipe()
    os.close(read_end)
    try:
        process = subprocess.Popen([str(executable)], cwd=ROOT, env=environment, stdout=write_end, stderr=subprocess.PIPE)
    finally:
        os.close(write_end)
    _, stderr = process.communicate(timeout=10)
    if process.returncode != expected or stderr != FAILURE:
        raise RuntimeError(
            f"closed-pipe mismatch for {executable.name}: status={process.returncode}, stderr={stderr!r}"
        )


def assert_line_buffered(executable: Path) -> bytes:
    master, slave = pty.openpty()
    process = subprocess.Popen([str(executable)], cwd=ROOT, stdout=slave, stderr=slave)
    os.close(slave)
    data = bytearray()
    deadline = time.monotonic() + 10
    line_seen_while_running = False
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.05)
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if not chunk:
                    break
                data.extend(chunk)
                if b"7\r\n" in data and process.poll() is None:
                    line_seen_while_running = True
                    break
            if process.poll() is not None:
                break
        if not line_seen_while_running:
            raise RuntimeError(f"{executable.name} did not flush its first line before exit")
        while process.poll() is None:
            ready, _, _ = select.select([master], [], [], 0.05)
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    break
                if chunk:
                    data.extend(chunk)
    finally:
        os.close(master)
    status = process.wait(timeout=10)
    if status != 0:
        raise RuntimeError(f"pseudo-terminal program exited with status {status}")
    return bytes(data)


def add_partial_write_probe(ir_path: Path) -> None:
    source = ir_path.read_text()
    main = re.compile(r"^define i32 @main\(i32 %argc, ptr %argv, ptr %envp\) \{\n.*?^\}\n", re.MULTILINE | re.DOTALL)
    replacement = '''define i32 @main(i32 %argc, ptr %argv, ptr %envp) {
entry:
  call void @nl_core_init(i32 %argc, ptr %argv, ptr %envp)
  call void @nl_set_test_mode()
  call void @nl_core_nl_test_configure_write_fault_sequence(i32 1, i64 2, i32 2, i64 5)
  %bytes = getelementptr [6 x i8], ptr @.nl.output.probe, i64 0, i64 0
  %queued = call i1 @nl_core_nl_core_output_write(i32 1, ptr %bytes, i64 6)
  br i1 %queued, label %check.flush, label %fail.91
check.flush:
  %first_flush = call i1 @nl_core_nl_core_flush_all()
  %flush_failed = xor i1 %first_flush, true
  br i1 %flush_failed, label %check.tail, label %fail.92
check.tail:
  %length_ptr = getelementptr [147456 x i8], ptr @nl.core.state, i64 0, i64 131072
  %length = load i64, ptr %length_ptr, align 1
  %b0p = getelementptr [147456 x i8], ptr @nl.core.state, i64 0, i64 0
  %b1p = getelementptr i8, ptr %b0p, i64 1
  %b2p = getelementptr i8, ptr %b0p, i64 2
  %b3p = getelementptr i8, ptr %b0p, i64 3
  %b0 = load i8, ptr %b0p, align 1
  %b1 = load i8, ptr %b1p, align 1
  %b2 = load i8, ptr %b2p, align 1
  %b3 = load i8, ptr %b3p, align 1
  %length_ok = icmp eq i64 %length, 4
  %c0 = icmp eq i8 %b0, 99
  %c1 = icmp eq i8 %b1, 100
  %c2 = icmp eq i8 %b2, 101
  %c3 = icmp eq i8 %b3, 102
  %tail01 = and i1 %c0, %c1
  %tail23 = and i1 %c2, %c3
  %tail_ok = and i1 %tail01, %tail23
  %tail_and_length = and i1 %tail_ok, %length_ok
  br i1 %tail_and_length, label %retry, label %fail.93
retry:
  call void @nl_core_nl_test_clear_write_fault()
  %retry_ok = call i1 @nl_core_nl_core_flush_all()
  br i1 %retry_ok, label %pass, label %fail.94
pass:
  ret i32 0
fail.91:
  ret i32 91
fail.92:
  ret i32 92
fail.93:
  ret i32 93
fail.94:
  ret i32 94
}
'''
    result, count = main.subn(replacement, source, count=1)
    if count != 1:
        raise RuntimeError("could not locate the core-mode main function for the injected-write probe")
    result = result.replace(
        'source_filename = "next-lang"\n',
        'source_filename = "next-lang"\n@.nl.output.probe = private unnamed_addr constant [6 x i8] c"abcdef", align 1\n',
        1,
    )
    ir_path.write_text(result)


def add_eintr_probe(ir_path: Path) -> None:
    source = ir_path.read_text()
    main = re.compile(r"^define i32 @main\(i32 %argc, ptr %argv, ptr %envp\) \{\n.*?^\}\n", re.MULTILINE | re.DOTALL)
    replacement = '''define i32 @main(i32 %argc, ptr %argv, ptr %envp) {
entry:
  call void @nl_core_init(i32 %argc, ptr %argv, ptr %envp)
  call void @nl_set_test_mode()
  call void @nl_core_nl_test_configure_write_fault(i64 1, i32 2, i64 4)
  %bytes = getelementptr [3 x i8], ptr @.nl.output.probe, i64 0, i64 0
  %queued = call i1 @nl_core_nl_core_output_write(i32 1, ptr %bytes, i64 3)
  %flushed = call i1 @nl_core_nl_core_flush_all()
  %ok = and i1 %queued, %flushed
  br i1 %ok, label %pass, label %fail
pass:
  ret i32 0
fail:
  ret i32 98
}
'''
    result, count = main.subn(replacement, source, count=1)
    if count != 1:
        raise RuntimeError("could not locate main for the EINTR probe")
    result = result.replace(
        'source_filename = "next-lang"\n',
        'source_filename = "next-lang"\n@.nl.output.probe = private unnamed_addr constant [3 x i8] c"xyz", align 1\n',
        1,
    )
    ir_path.write_text(result)


def add_shared_terminal_probe(ir_path: Path) -> None:
    source = ir_path.read_text()
    main = re.compile(r"^define i32 @main\(i32 %argc, ptr %argv, ptr %envp\) \{\n.*?^\}\n", re.MULTILINE | re.DOTALL)
    replacement = '''define i32 @main(i32 %argc, ptr %argv, ptr %envp) {
entry:
  call void @nl_core_init(i32 %argc, ptr %argv, ptr %envp)
  %out = getelementptr [1 x i8], ptr @.nl.output.out, i64 0, i64 0
  %err = getelementptr [1 x i8], ptr @.nl.output.err, i64 0, i64 0
  %out_ok = call i1 @nl_core_nl_core_output_write(i32 1, ptr %out, i64 1)
  %err_ok = call i1 @nl_core_nl_core_output_write(i32 2, ptr %err, i64 1)
  %flush_ok = call i1 @nl_core_nl_core_flush_all()
  %both = and i1 %out_ok, %err_ok
  %ok = and i1 %both, %flush_ok
  %status = select i1 %ok, i32 0, i32 95
  ret i32 %status
}
'''
    result, count = main.subn(replacement, source, count=1)
    if count != 1:
        raise RuntimeError("could not locate main for the shared-terminal probe")
    result = result.replace(
        'source_filename = "next-lang"\n',
        'source_filename = "next-lang"\n@.nl.output.out = private unnamed_addr constant [1 x i8] c"A", align 1\n@.nl.output.err = private unnamed_addr constant [1 x i8] c"B", align 1\n',
        1,
    )
    ir_path.write_text(result)


def run_pty_streams(executable: Path, shared: bool) -> tuple[bytes, bytes]:
    out_master, out_slave = pty.openpty()
    if shared:
        err_master, err_slave = out_master, out_slave
    else:
        err_master, err_slave = pty.openpty()
    process = subprocess.Popen([str(executable)], cwd=ROOT, stdout=out_slave, stderr=err_slave)
    os.close(out_slave)
    if not shared:
        os.close(err_slave)
    status = process.wait(timeout=10)

    def drain(master: int) -> bytes:
        result = bytearray()
        while True:
            ready, _, _ = select.select([master], [], [], 0.05)
            if not ready:
                break
            try:
                chunk = os.read(master, 4096)
            except OSError:
                break
            if not chunk:
                break
            result.extend(chunk)
        return bytes(result)

    out = drain(out_master)
    if shared:
        os.close(out_master)
        err = out
    else:
        err = drain(err_master)
        os.close(err_master)
        os.close(out_master)
    if status != 0:
        raise RuntimeError(f"terminal-order probe exited with status {status}")
    return out, err


def main() -> int:
    with tempfile.TemporaryDirectory(prefix=".core-output-test-", dir=ROOT) as temporary:
        root = Path(temporary)
        fault_package = root / "fault"
        eintr_package = root / "eintr"
        shared_package = root / "shared"
        output_package = root / "output"
        test_package = root / "test"
        for package in (fault_package, eintr_package, shared_package, output_package, test_package):
            package.mkdir()
        (fault_package / "main.nl").write_text("fn main() {}\n")
        (eintr_package / "main.nl").write_text("fn main() {}\n")
        (shared_package / "main.nl").write_text("fn main() {}\n")
        (output_package / "main.nl").write_text(
            "fn main() {\n    print(7)\n    var sum = 0L\n"
            "    for index in 0L..20000000L { sum += index % 7L }\n"
            "    print(sum)\n}\n"
        )
        (test_package / "tests.nl").write_text('test "buffered output" { print(7) }\n')

        fault_rel = fault_package.relative_to(ROOT).as_posix()
        fault_ir, fault_exe = build(fault_rel, "fault", "core")
        add_partial_write_probe(fault_ir)
        linked = run([str(NLC), "link-ir", str(fault_ir), "-o", str(fault_exe)], timeout=90)
        if linked.returncode != 0:
            raise RuntimeError(f"fault-probe link failed: {linked.stderr.decode(errors='replace')}")
        fault = subprocess.run([str(fault_exe)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if fault.returncode != 0 or fault.stdout != b"abcdef" or fault.stderr:
            raise RuntimeError(f"partial-write probe mismatch: {fault!r}")

        eintr_rel = eintr_package.relative_to(ROOT).as_posix()
        eintr_ir, eintr_exe = build(eintr_rel, "eintr", "core")
        add_eintr_probe(eintr_ir)
        linked = run([str(NLC), "link-ir", str(eintr_ir), "-o", str(eintr_exe)], timeout=90)
        if linked.returncode != 0:
            raise RuntimeError(f"EINTR-probe link failed: {linked.stderr.decode(errors='replace')}")
        retried = subprocess.run([str(eintr_exe)], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if retried.returncode != 0 or retried.stdout != b"xyz" or retried.stderr:
            raise RuntimeError(f"EINTR retry probe mismatch: {retried!r}")

        shared_rel = shared_package.relative_to(ROOT).as_posix()
        shared_ir, shared_exe = build(shared_rel, "shared", "core")
        add_shared_terminal_probe(shared_ir)
        linked = run([str(NLC), "link-ir", str(shared_ir), "-o", str(shared_exe)], timeout=90)
        if linked.returncode != 0:
            raise RuntimeError(f"shared-terminal probe link failed: {linked.stderr.decode(errors='replace')}")
        same_terminal = run_pty_streams(shared_exe, True)
        separate_terminals = run_pty_streams(shared_exe, False)
        if same_terminal != (b"AB", b"AB") or separate_terminals != (b"A", b"B"):
            raise RuntimeError(
                f"terminal ordering mismatch: shared={same_terminal!r}, separate={separate_terminals!r}"
            )

        for runtime in ("core", "c"):
            output_rel = output_package.relative_to(ROOT).as_posix()
            _, program = build(output_rel, "output", runtime)
            assert_failure(program)
            test_rel = test_package.relative_to(ROOT).as_posix()
            _, test_program = build(test_rel, "test", runtime, test=True)
            assert_failure(test_program, test_mode=True)

        pty_bytes = {}
        for runtime in ("core", "c"):
            output_rel = output_package.relative_to(ROOT).as_posix()
            _, program = build(output_rel, "output", runtime)
            pty_bytes[runtime] = assert_line_buffered(program)
        if pty_bytes["core"] != pty_bytes["c"]:
            raise RuntimeError("pseudo-terminal bytes differ between core and C runtime")
        print("core output checks passed: partial writes, EINTR retries, pipes, /dev/full, line buffering, shared and separate terminals")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
