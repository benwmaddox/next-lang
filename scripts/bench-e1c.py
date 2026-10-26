#!/usr/bin/env python3
"""Measure E1 package compile/link/run and trivial startup for C and core."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
TARGET = Path.home() / ".cache/next-lang/target"
NLC_RELEASE = TARGET / "release/nlc"
NLC = NLC_RELEASE if NLC_RELEASE.is_file() else TARGET / "debug/nlc"


def command(
    args: list[str], *, timeout: int, env: dict[str, str] | None = None
) -> tuple[subprocess.CompletedProcess[bytes], int]:
    started = time.perf_counter_ns()
    result = subprocess.run(
        args,
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    elapsed = time.perf_counter_ns() - started
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(args)}\n"
            f"{result.stderr.decode(errors='replace')}"
        )
    return result, elapsed


def compiler_command(selfhost: Path, package: str, output: str, runtime: str) -> list[str]:
    return [
        str(selfhost),
        "build",
        package,
        "-o",
        output,
        f"--runtime={runtime}",
    ]


def timed_build(
    selfhost: Path, package: str, output: str, runtime: str, env: dict[str, str]
) -> int:
    _, elapsed = command(compiler_command(selfhost, package, output, runtime), timeout=900, env=env)
    return elapsed


def link_ir(ir: str, binary: str, env: dict[str, str]) -> int:
    _, elapsed = command([str(NLC), "link-ir", ir, "-o", binary], timeout=300, env=env)
    return elapsed


def main() -> int:
    if not NLC.is_file():
        raise RuntimeError(f"nlc is missing: {NLC}; run cargo build first")
    if not shutil.which("clang"):
        raise RuntimeError("clang is not on PATH")

    environment = os.environ.copy()
    environment["NLC_FRONTEND"] = "rust"
    environment["NLC_OPT_LEVEL"] = "1"
    environment["CARGO_TARGET_DIR"] = str(Path.home() / ".cache/next-lang/target")

    allowed_cpus = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else []
    cpu = allowed_cpus[0] if allowed_cpus else None
    if cpu is not None:
        os.sched_setaffinity(0, {cpu})

    clang_version = subprocess.run(
        [shutil.which("clang") or "clang", "--version"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
        text=True,
    ).stdout.splitlines()[0]
    cpu_model = "unknown"
    for line in Path("/proc/cpuinfo").read_text(errors="replace").splitlines():
        if line.lower().startswith("model name"):
            cpu_model = line.split(":", 1)[1].strip()
            break

    work = Path(tempfile.mkdtemp(prefix=".e1c-bench-", dir=ROOT))
    try:
        package = work / "package"
        source_generator = ROOT / "scripts/gen-selfhost-bench.py"
        generator = subprocess.run(
            ["python3", str(source_generator), str(package), "--functions", "10000"],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
            check=False,
        )
        if generator.returncode != 0:
            raise RuntimeError(generator.stderr.decode(errors="replace"))
        source_size = (package / "main.nl").stat().st_size
        package_rel = package.relative_to(ROOT).as_posix()
        work_rel = work.relative_to(ROOT).as_posix()

        # Build the stage-zero executable once, then time only its own package compiler.
        selfhost = work / "selfhost"
        selfhost_rel = selfhost.relative_to(ROOT).as_posix()
        _, bootstrap_ns = command(
            [str(NLC), "build", "selfhost", "-o", selfhost_rel],
            timeout=900,
            env=environment,
        )

        # Warm the compiler process and any one-time runtime setup before timing.
        warm_ir = f"{work_rel}/warm.ll"
        command(compiler_command(selfhost, "bench/memfn", warm_ir, "c"), timeout=900, env=environment)

        build_times: dict[str, list[int]] = {"c": [], "core": []}
        final_irs: dict[str, str] = {}
        for runtime in ("c", "core"):
            for sample in range(7):
                ir = f"{work_rel}/{runtime}-{sample}.ll"
                build_times[runtime].append(timed_build(selfhost, package_rel, ir, runtime, environment))
                if sample == 6:
                    final_irs[runtime] = ir

        binaries: dict[str, Path] = {}
        link_times: dict[str, int] = {}
        for runtime in ("c", "core"):
            binary = work / f"e1-{runtime}"
            link_times[runtime] = link_ir(final_irs[runtime], binary.relative_to(ROOT).as_posix(), environment)
            binaries[runtime] = binary
            result = subprocess.run(
                [str(binary)],
                cwd=ROOT,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
                check=False,
            )
            if result.returncode != 0 or result.stdout != b"4\n" or result.stderr:
                raise RuntimeError(
                    f"E1 {runtime} run differed: status={result.returncode}, "
                    f"stdout={result.stdout!r}, stderr={result.stderr!r}"
                )

        trivial = package / "trivial"
        trivial.mkdir()
        (trivial / "main.nl").write_text("fn main() {}\n")
        trivial_rel = trivial.relative_to(ROOT).as_posix()
        trivial_bins: dict[str, Path] = {}
        trivial_link_ns: dict[str, int] = {}
        for runtime in ("c", "core"):
            ir = f"{work_rel}/trivial-{runtime}.ll"
            timed_build(selfhost, trivial_rel, ir, runtime, environment)
            binary = work / f"trivial-{runtime}"
            trivial_link_ns[runtime] = link_ir(ir, binary.relative_to(ROOT).as_posix(), environment)
            trivial_bins[runtime] = binary
            check = subprocess.run([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=False)
            if check.returncode != 0 or check.stdout or check.stderr:
                raise RuntimeError(f"trivial {runtime} program did not exit cleanly")

        startup: dict[str, list[float]] = {"c": [], "core": []}
        for runtime, binary in trivial_bins.items():
            for _batch in range(3):
                started = time.perf_counter_ns()
                for _ in range(100):
                    result = subprocess.run(
                        [str(binary)],
                        cwd=ROOT,
                        env=environment,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=10,
                        check=False,
                    )
                    if result.returncode != 0:
                        raise RuntimeError(f"trivial {runtime} startup returned {result.returncode}")
                startup[runtime].append((time.perf_counter_ns() - started) / 100 / 1000)

        print(f"cpu={cpu_model}")
        print(f"clang={clang_version}")
        print(f"cpu_pinned={cpu if cpu is not None else 'unavailable'} samples=7")
        print(f"benchmark_source_bytes={source_size}")
        print(f"stage0_build_ms={bootstrap_ns / 1_000_000:.3f}")
        for runtime in ("c", "core"):
            compiler_ms = statistics.median(build_times[runtime]) / 1_000_000
            print(
                f"e1_{runtime}: compile_ms={compiler_ms:.3f} "
                f"compile_samples_ms={[round(value / 1_000_000, 3) for value in build_times[runtime]]} "
                f"link_ms={link_times[runtime] / 1_000_000:.3f} "
                f"binary_bytes={binaries[runtime].stat().st_size} run_output=4"
            )
        core_overhead_ms = (
            statistics.median(build_times["core"]) - statistics.median(build_times["c"])
        ) / 1_000_000
        print(f"embedded_core_compile_overhead_ms={core_overhead_ms:.3f}")
        for runtime in ("c", "core"):
            print(
                f"trivial_{runtime}: binary_bytes={trivial_bins[runtime].stat().st_size} "
                f"link_ms={trivial_link_ns[runtime] / 1_000_000:.3f} "
                f"startup_median_us={statistics.median(startup[runtime]):.3f} "
                f"startup_batches_us={[round(value, 3) for value in startup[runtime]]}"
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
