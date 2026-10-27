#!/usr/bin/env python3
"""Measure E3a2 loop fixtures with Rust and self-hosted code generation."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
PACKAGES = (
    ("empty", "bench/e3a2/empty", 3),
    ("list_loop", "bench/e3a2/list_loop", 3),
    ("soa_loop", "bench/e3a2/soa_loop", 3),
    ("write_call_loop", "bench/e3a2/write_call_loop", 3),
    ("e2_aggregate", "bench/e2c/aggregate", 1),
)
SAMPLES = 5


def invoke(command: list[str], env: dict[str, str], timeout: int = 300) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"stdout={result.stdout[:500]!r}\nstderr={result.stderr[:1000]!r}"
        )
    return result


def compiler_executable(
    name: str,
    package: str,
    rust_nlc: Path,
    selfhost: Path,
    work: Path,
    env: dict[str, str],
) -> tuple[Path, Path]:
    package_path = ROOT / package
    package_arg = package_path.relative_to(ROOT).as_posix()
    rust_exe = work / f"{name}-rust"
    selfhost_exe = work / f"{name}-selfhost"
    ir = work / f"{name}.ll"
    relative_ir = ir.relative_to(ROOT).as_posix()
    invoke(
        [str(rust_nlc), "--frontend=rust", "build", str(package_path), "-o", str(rust_exe)],
        env,
    )
    invoke(
        [str(selfhost), "build", package_arg, "-o", relative_ir],
        env,
    )
    invoke([str(rust_nlc), "link-ir", relative_ir, "-o", str(selfhost_exe)], env)
    return rust_exe, selfhost_exe


def measure(executable: Path, label: str, work: Path, cpu: int, env: dict[str, str]) -> tuple[list[float], bytes]:
    durations: list[float] = []
    expected: bytes | None = None
    for sample in range(SAMPLES):
        output_path = work / f"{label}-{sample}.out"
        started = time.perf_counter_ns()
        result = subprocess.run(
            ["taskset", "-c", str(cpu), str(executable)],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
            check=False,
        )
        elapsed = (time.perf_counter_ns() - started) / 1_000_000_000
        if result.returncode != 0:
            raise RuntimeError(f"{label} run failed ({result.returncode}): {result.stderr[:500]!r}")
        output_path.write_bytes(result.stdout)
        if expected is None:
            expected = result.stdout
        elif result.stdout != expected:
            raise RuntimeError(f"{label} checksum/output changed between samples")
        durations.append(elapsed)
    assert expected is not None
    return sorted(durations), expected


def report_times(values: list[float]) -> str:
    return "/".join(f"{value:.6f}" for value in (values[0], values[len(values) // 2], values[-1]))


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True, type=Path, help="self-hosted compiler built from this checkout")
    parser.add_argument("--nlc", required=True, type=Path, help="stage-zero Rust compiler")
    args = parser.parse_args()
    selfhost = args.compiler.resolve()
    rust_nlc = args.nlc.resolve()
    for path, label in ((selfhost, "self-hosted compiler"), (rust_nlc, "Rust compiler")):
        if not path.is_file() or not os.access(path, os.X_OK):
            raise RuntimeError(f"{label} is not executable: {path}")
    allowed = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else [0]
    cpu = int(os.environ.get("BENCH_CPU", str(allowed[0])))
    if cpu not in allowed:
        raise RuntimeError(f"BENCH_CPU={cpu} is outside the allowed CPU set {allowed}")

    work = Path(tempfile.mkdtemp(prefix=".bench-e3a2-", dir=ROOT))
    env = os.environ.copy()
    env["NLC_FRONTEND"] = "rust"
    env["NLC_OPT_LEVEL"] = "3"
    env.setdefault("CARGO_TARGET_DIR", str(Path.home() / ".cache/next-lang/target"))
    try:
        print("program,checksum,rust_best_median_worst_s,selfhost_best_median_worst_s,rust_min_run_s,selfhost_min_run_s")
        for label, package, level in PACKAGES:
            package_env = env.copy()
            package_env["NLC_OPT_LEVEL"] = str(level)
            rust_exe, selfhost_exe = compiler_executable(
                label, package, rust_nlc, selfhost, work, package_env
            )
            rust_times, rust_output = measure(rust_exe, f"{label}-rust", work, cpu, env)
            self_times, self_output = measure(selfhost_exe, f"{label}-selfhost", work, cpu, env)
            if rust_output != self_output:
                raise RuntimeError(
                    f"{label} output differs: Rust={rust_output!r}, selfhost={self_output!r}"
                )
            if label != "empty" and (rust_times[0] < 1.0 or self_times[0] < 1.0):
                raise RuntimeError(
                    f"{label} completed in under one second; increase its iteration count"
                )
            checksum = rust_output.decode("ascii").strip() or "(empty)"
            print(
                f"{label},{checksum},{report_times(rust_times)},"
                f"{report_times(self_times)},{rust_times[0]:.6f},{self_times[0]:.6f}"
            )
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=__import__("sys").stderr)
        raise SystemExit(1)
