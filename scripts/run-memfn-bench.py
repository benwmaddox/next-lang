#!/usr/bin/env python3
"""Build and run the core-versus-glibc memory-function benchmark."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
NLC = Path.home() / ".cache/next-lang/target/debug/nlc"


def run(command: list[str], *, timeout: int, **kwargs: object) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False, **kwargs)
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"{result.stderr.decode(errors='replace')}"
        )
    return result


def patch_module(ir: Path) -> None:
    source = ir.read_text()
    main = re.compile(r"^define i32 @main\(i32 %argc, ptr %argv, ptr %envp\) \{\n.*?^\}\n", re.MULTILINE | re.DOTALL)
    replacement = '''declare void @bench_run()

define i32 @main(i32 %argc, ptr %argv, ptr %envp) {
entry:
  call void @nl_core_init(i32 %argc, ptr %argv, ptr %envp)
  call void @bench_run()
  ret i32 0
}
'''
    source, count = main.subn(replacement, source, count=1)
    if count != 1:
        raise RuntimeError("could not find core-mode main in benchmark IR")
    additions = '''
define ptr @bench_core_memcpy(ptr %dst, ptr %src, i64 %count) noinline {
entry:
  %result = call ptr @memcpy(ptr %dst, ptr %src, i64 %count)
  ret ptr %result
}

define ptr @bench_core_memset(ptr %dst, i32 %value, i64 %count) noinline {
entry:
  %result = call ptr @memset(ptr %dst, i32 %value, i64 %count)
  ret ptr %result
}
'''
    marker = "; nlc-link-ir end"
    if marker not in source:
        raise RuntimeError("benchmark IR has no link-ir end marker")
    source = source.replace(marker, additions + "\n" + marker, 1)
    ir.write_text(source)


def cpu_description() -> str:
    cpuinfo = Path("/proc/cpuinfo").read_text(errors="replace")
    for line in cpuinfo.splitlines():
        if line.lower().startswith("model name"):
            return line.split(":", 1)[1].strip()
    return os.uname().machine


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--opt-level", choices=("1", "3"), required=True)
    parser.add_argument("--quick", action="store_true", help="sample threshold and representative sizes")
    args = parser.parse_args()
    if not NLC.is_file():
        raise RuntimeError(f"nlc is missing: {NLC}; run cargo build first")

    work = Path(tempfile.mkdtemp(prefix=".memfn-bench-", dir=ROOT))
    try:
        relative = work.relative_to(ROOT).as_posix()
        ir = work / "memfn.ll"
        executable = work / "memfn"
        shim_object = work / "shim.o"
        build = run(
            [str(NLC), "run", "selfhost", "--", "build", "bench/memfn", "-o", f"{relative}/memfn.ll"],
            timeout=300,
        )
        if build.stdout or build.stderr:
            print(build.stdout.decode(errors="replace"), end="")
            print(build.stderr.decode(errors="replace"), end="", file=__import__("sys").stderr)
        patch_module(ir)

        clang = shutil.which("clang")
        if not clang:
            raise RuntimeError("clang is not on PATH")
        quick_flags = ["-DBENCH_QUICK=1"] if args.quick else []
        run(
            [clang, "-O2", "-fno-builtin-memcpy", "-fno-builtin-memset", "-fno-stack-protector", "-fno-pie", *quick_flags, "-c", "bench/memfn/shim.c", "-o", str(shim_object)],
            timeout=120,
        )
        run(
            [clang, f"-O{args.opt_level}", "-nostartfiles", "-no-pie", "-Wl,-e,_start", "-Wl,--build-id=none", str(ir), str(shim_object), "-o", str(executable)],
            timeout=180,
        )

        affinity = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else []
        command = [str(executable)]
        taskset = shutil.which("taskset")
        if taskset and affinity:
            command = [taskset, "-c", str(affinity[0]), *command]
        print(f"cpu={cpu_description()}")
        version = run([clang, "--version"], timeout=10)
        print(version.stdout.decode(errors="replace").splitlines()[0])
        print(f"optimization=O{args.opt_level} quick={args.quick} binary_bytes={executable.stat().st_size}")
        measured = run(command, timeout=1800)
        print(measured.stdout.decode(errors="replace"), end="")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=__import__("sys").stderr)
        raise SystemExit(1)
