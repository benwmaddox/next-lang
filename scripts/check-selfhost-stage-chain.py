#!/usr/bin/env python3
"""Build stage 2 from the frozen seed, then build and compare stage 3.

This checks stage-2/stage-3 identity with the C runtime only. It does not
validate the compiler corpus. The seed is built through the existing
source-keyed helper; after that, both compiler invocations emit LLVM IR which
is linked directly by clang with runtime/nl_runtime.c.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import time
from typing import Any


COMMAND_TIMEOUT_SECONDS = 600
TOOL_TIMEOUT_SECONDS = 30
C_RUNTIME_HEADER = re.compile(rb"(?m)^; nlc\.runtime c$")
OFFSET_STACK_HEADER = re.compile(rb"(?m)^; nlc\.stack offset$")


class ChainFailure(RuntimeError):
    pass


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def source_hash(root: Path) -> str:
    digest = hashlib.sha256()
    for directory in (root / "selfhost", root / "core"):
        if not directory.is_dir():
            raise ChainFailure(f"source directory is missing: {directory}")
        for path in sorted(directory.rglob("*")):
            if not path.is_file() or not (path.suffix == ".nl" or path.name == "package.toml"):
                continue
            relative = path.relative_to(root).as_posix().encode("utf-8")
            content = path.read_bytes()
            digest.update(len(relative).to_bytes(8, "little"))
            digest.update(relative)
            digest.update(len(content).to_bytes(8, "little"))
            digest.update(content)
    runtime_directory = root / "runtime"
    runtime_source = runtime_directory / "nl_runtime.c"
    if not runtime_source.is_file():
        raise ChainFailure(f"C runtime source is missing: {runtime_source}")
    runtime_files = [runtime_source, *sorted(runtime_directory.rglob("*.h"))]
    for path in runtime_files:
        if not path.is_file():
            raise ChainFailure(f"C runtime dependency is missing: {path}")
        relative = path.relative_to(root).as_posix().encode("utf-8")
        content = path.read_bytes()
        digest.update(len(relative).to_bytes(8, "little"))
        digest.update(relative)
        digest.update(len(content).to_bytes(8, "little"))
        digest.update(content)
    return digest.hexdigest()


def checked_output_directory(root: Path, requested: Path | None) -> Path:
    if requested is None:
        return Path(tempfile.mkdtemp(prefix=".selfhost-stage-chain-", dir=root))

    candidate = requested if requested.is_absolute() else root / requested
    output = candidate.resolve()
    try:
        relative = output.relative_to(root.resolve())
    except ValueError as error:
        raise ChainFailure(f"output directory must be inside the repository: {output}") from error
    if not relative.parts:
        raise ChainFailure("output directory cannot be the repository root")
    if output.exists():
        if not output.is_dir() or any(output.iterdir()):
            raise ChainFailure(f"output directory is not empty or is not a directory: {output}")
    output.mkdir(parents=True, exist_ok=True)
    return output


def clean_environment(root: Path, opt_level: str) -> dict[str, str]:
    environment = os.environ.copy()
    for name in tuple(environment):
        if name.startswith("NLC_") and name not in ("NLC_STACK_MODE",):
            environment.pop(name, None)

    target = Path(environment.get("CARGO_TARGET_DIR", root / "target"))
    if not target.is_absolute():
        target = root / target
    environment["CARGO_TARGET_DIR"] = str(target.resolve())
    environment["NLC_OPT_LEVEL"] = opt_level
    environment["LC_ALL"] = "C"
    environment["LANG"] = "C"
    return environment


def save_text(path: Path, value: str) -> None:
    path.write_text(value + "\n", encoding="utf-8")


def save_report(output: Path, report: dict[str, Any]) -> None:
    report_path = output / "report.json"
    temporary = output / ".report.json.tmp"
    temporary.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, report_path)


def run_command(
    label: str,
    command: list[str],
    root: Path,
    output: Path,
    report: dict[str, Any],
    environment: dict[str, str],
    timeout: int = COMMAND_TIMEOUT_SECONDS,
) -> subprocess.CompletedProcess[bytes]:
    started = time.monotonic()
    entry: dict[str, Any] = {
        "label": label,
        "command": command,
        "cwd": str(root),
        "timeout_seconds": timeout,
    }
    try:
        result = subprocess.run(
            command,
            cwd=root,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout or b""
        stderr = error.stderr or b""
        (output / f"{label}.stdout").write_bytes(stdout)
        (output / f"{label}.stderr").write_bytes(stderr)
        entry.update(
            {
                "status": None,
                "timed_out": True,
                "duration_seconds": round(time.monotonic() - started, 3),
                "stdout_bytes": len(stdout),
                "stderr_bytes": len(stderr),
                "error": f"command exceeded {timeout} seconds",
            }
        )
        report["commands"].append(entry)
        raise ChainFailure(f"{label} timed out after {timeout} seconds") from error
    except OSError as error:
        entry.update(
            {
                "status": None,
                "timed_out": False,
                "duration_seconds": round(time.monotonic() - started, 3),
                "error": str(error),
            }
        )
        report["commands"].append(entry)
        raise ChainFailure(f"could not start {label}: {error}") from error

    (output / f"{label}.stdout").write_bytes(result.stdout)
    (output / f"{label}.stderr").write_bytes(result.stderr)
    entry.update(
        {
            "status": result.returncode,
            "timed_out": False,
            "duration_seconds": round(time.monotonic() - started, 3),
            "stdout_bytes": len(result.stdout),
            "stderr_bytes": len(result.stderr),
            "stderr_preview": result.stderr[:4000].decode("utf-8", "replace"),
        }
    )
    report["commands"].append(entry)
    return result


def require_success(label: str, result: subprocess.CompletedProcess[bytes]) -> None:
    if result.returncode != 0:
        raise ChainFailure(f"{label} failed with status {result.returncode}")


def compile_stage(
    stage: str,
    compiler: Path,
    root: Path,
    output: Path,
    report: dict[str, Any],
    environment: dict[str, str],
) -> Path:
    ir = output / f"{stage}.ll"
    relative_ir = ir.relative_to(root).as_posix()
    command = [str(compiler), "build", "selfhost", "-o", relative_ir, "--runtime=c"]
    result = run_command(f"{stage}-compiler", command, root, output, report, environment)
    require_success(f"{stage} compiler", result)
    if not ir.is_file() or not ir.stat().st_size:
        raise ChainFailure(f"{stage} compiler succeeded without writing {relative_ir}")

    content = ir.read_bytes()
    if C_RUNTIME_HEADER.search(content) is None:
        raise ChainFailure(f"{stage} IR is missing C-runtime metadata")
    if OFFSET_STACK_HEADER.search(content) is None:
        raise ChainFailure(f"{stage} IR is missing offset-stack metadata")
    metadata = {
        "ir_path": str(ir),
        "ir_sha256": sha256_bytes(content),
        "runtime": "c",
        "stack_mode": "offset",
    }
    report["stages"][stage] = metadata
    return ir


def link_c_runtime_ir(
    stage: str,
    clang: str,
    ir: Path,
    root: Path,
    output: Path,
    report: dict[str, Any],
    environment: dict[str, str],
    opt_level: str,
) -> Path:
    executable = output / stage
    command = [
        clang,
        f"-O{opt_level}",
        "-DNLC_STACK_MODE_OFFSET=1",
        str(ir),
        str(root / "runtime/nl_runtime.c"),
        "-o",
        str(executable),
    ]
    result = run_command(f"{stage}-clang", command, root, output, report, environment)
    require_success(f"{stage} clang link", result)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ChainFailure(f"clang succeeded without writing executable {executable}")
    report["stages"][stage]["binary_path"] = str(executable)
    report["stages"][stage]["binary_sha256"] = sha256_bytes(executable.read_bytes())
    return executable


def run_chain(args: argparse.Namespace) -> tuple[int, Path]:
    root = Path(__file__).resolve().parent.parent
    if sys.platform != "linux":
        raise ChainFailure("the C-runtime stage-chain runner requires Linux")

    reference = args.reference.resolve()
    if not reference.is_file() or not os.access(reference, os.X_OK):
        raise ChainFailure(f"reference nlc is not executable: {reference}")
    output = checked_output_directory(root, args.output_dir)
    environment = clean_environment(root, args.opt_level)
    started = time.monotonic()

    report: dict[str, Any] = {
        "scope": "stage-chain-only; compiler corpus validation is not performed",
        "status": "running",
        "failure": None,
        "repository": str(root),
        "output_directory": str(output),
        "reference": str(reference),
        "optimization_level": args.opt_level,
        "tools": {"python": platform.python_version()},
        "source_sha256": None,
        "commands": [],
        "stages": {},
        "comparisons": {},
    }
    report["_started_at"] = started
    report["seed_build_cache_command"] = [
        sys.executable,
        str(root / "scripts/build-selfhost-cached.py"),
        "--reference",
        str(reference),
    ]

    try:
        report["source_sha256"] = source_hash(root)
        clang_version = run_command(
            "tool-clang-version",
            [args.clang, "--version"],
            root,
            output,
            report,
            environment,
            timeout=TOOL_TIMEOUT_SECONDS,
        )
        require_success("clang version check", clang_version)
        report["tools"]["clang"] = clang_version.stdout.decode("utf-8", "replace").strip()
        rustc_version = run_command(
            "tool-rustc-version",
            ["rustc", "--version", "--verbose"],
            root,
            output,
            report,
            environment,
            timeout=TOOL_TIMEOUT_SECONDS,
        )
        require_success("rustc version check", rustc_version)
        report["tools"]["rustc"] = rustc_version.stdout.decode("utf-8", "replace").strip()

        helper = report["seed_build_cache_command"]
        seed_result = run_command(
            "seed-cache",
            helper,
            root,
            output,
            report,
            environment,
            timeout=COMMAND_TIMEOUT_SECONDS,
        )
        require_success("stage-0 seed build", seed_result)
        seed_text = seed_result.stdout.decode("utf-8", "strict").strip()
        if not seed_text:
            raise ChainFailure("seed builder returned no executable path")
        seed = Path(seed_text).resolve()
        if not seed.is_file() or not os.access(seed, os.X_OK):
            raise ChainFailure(f"cached stage-0 compiler is missing: {seed}")
        report["seed"] = {
            "path": str(seed),
            "cache_key": seed.parent.name,
            "binary_sha256": sha256_bytes(seed.read_bytes()),
        }

        stage2_ir = compile_stage("stage2", seed, root, output, report, environment)
        stage2 = link_c_runtime_ir(
            "stage2", args.clang, stage2_ir, root, output, report, environment, args.opt_level
        )
        stage3_ir = compile_stage("stage3", stage2, root, output, report, environment)
        stage3 = link_c_runtime_ir(
            "stage3", args.clang, stage3_ir, root, output, report, environment, args.opt_level
        )

        stage2_ir_hash = sha256_bytes(stage2_ir.read_bytes())
        stage3_ir_hash = sha256_bytes(stage3_ir.read_bytes())
        stage2_binary_hash = sha256_bytes(stage2.read_bytes())
        stage3_binary_hash = sha256_bytes(stage3.read_bytes())
        report["comparisons"] = {
            "ir_identical": stage2_ir.read_bytes() == stage3_ir.read_bytes(),
            "ir_stage2_sha256": stage2_ir_hash,
            "ir_stage3_sha256": stage3_ir_hash,
            "binary_identical": stage2.read_bytes() == stage3.read_bytes(),
            "binary_stage2_sha256": stage2_binary_hash,
            "binary_stage3_sha256": stage3_binary_hash,
        }
        if source_hash(root) != report["source_sha256"]:
            raise ChainFailure("selfhost, core, or C runtime sources changed during the stage-chain run")
        if not report["comparisons"]["ir_identical"]:
            first = next(
                (
                    index
                    for index, (left, right) in enumerate(zip(stage2_ir.read_bytes(), stage3_ir.read_bytes()))
                    if left != right
                ),
                None,
            )
            if first is None and len(stage2_ir.read_bytes()) != len(stage3_ir.read_bytes()):
                first = min(len(stage2_ir.read_bytes()), len(stage3_ir.read_bytes()))
            report["comparisons"]["first_ir_difference_offset"] = first
            raise ChainFailure("stage-2 and stage-3 LLVM IR differ")
        if not report["comparisons"]["binary_identical"]:
            raise ChainFailure("stage-2 and stage-3 executables differ")
        report["status"] = "passed"
        return 0, output
    except (ChainFailure, OSError, subprocess.SubprocessError, UnicodeError) as error:
        report["status"] = "failed"
        report["failure"] = str(error)
        return 1, output
    finally:
        report["total_duration_seconds"] = round(time.monotonic() - report["_started_at"], 3)
        report.pop("_started_at", None)
        save_report(output, report)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True, help="executable frozen Rust nlc used only to build the seed")
    parser.add_argument("--clang", default="clang", help="clang executable used for both C-runtime links")
    parser.add_argument("--opt-level", choices=("1", "3"), default="1")
    parser.add_argument("--output-dir", type=Path, help="empty repository subdirectory for retained artifacts and report")
    args = parser.parse_args()

    try:
        status, output = run_chain(args)
    except (ChainFailure, OSError, subprocess.SubprocessError, ValueError) as error:
        print(f"selfhost stage chain failed: {error}", file=sys.stderr)
        return 1
    report_path = output / "report.json"
    print(f"stage chain { 'passed' if status == 0 else 'failed' }; report: {report_path}")
    print("scope: stage-2/stage-3 identity only; compiler corpus validation not run")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
