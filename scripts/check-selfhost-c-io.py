#!/usr/bin/env python3
"""Run the small C-runtime I/O bootstrap fixtures with an existing compiler."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


TIMEOUT_SECONDS = 180
FIXTURES = ("c_io_args", "c_io_files", "c_io_fields")
RUNS = (
    ("c_io_args", "no-args", "expected", ()),
    ("c_io_args", "two-args", "manual-two-args", ("alpha", "beta")),
    ("c_io_files", "file-workflow", "expected", ()),
    ("c_io_fields", "record-fields", "expected", ()),
)


class SmokeFailure(RuntimeError):
    pass


def clean_environment(level: int) -> dict[str, str]:
    env = os.environ.copy()
    for name in tuple(env):
        if name.startswith("NLC_") and name != "NLC_STACK_MODE":
            env.pop(name, None)
    env.pop("CODEX_TOOL_CALL_ID", None)
    env["NLC_OPT_LEVEL"] = str(level)
    return env


def as_bytes(value: bytes | str | None) -> bytes:
    if value is None:
        return b""
    return value.encode("utf-8") if isinstance(value, str) else value


def record_outputs(
    work: Path,
    label: str,
    stdout: bytes,
    stderr: bytes,
) -> tuple[str, str]:
    stdout_path = work / f"{label}.stdout"
    stderr_path = work / f"{label}.stderr"
    stdout_path.write_bytes(stdout)
    stderr_path.write_bytes(stderr)
    return str(stdout_path), str(stderr_path)


def run_command(
    label: str,
    command: list[str],
    cwd: Path,
    env: dict[str, str],
    work: Path,
    report: dict[str, Any],
) -> subprocess.CompletedProcess[bytes]:
    started = time.monotonic()
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            capture_output=True,
            timeout=TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        stdout_path, stderr_path = record_outputs(
            work, label, as_bytes(error.stdout), as_bytes(error.stderr)
        )
        report["steps"].append(
            {
                "label": label,
                "command": command,
                "cwd": str(cwd),
                "status": None,
                "timed_out": True,
                "seconds": time.monotonic() - started,
                "stdout": stdout_path,
                "stderr": stderr_path,
            }
        )
        raise SmokeFailure(f"{label} timed out after {TIMEOUT_SECONDS} seconds") from error
    except OSError as error:
        report["steps"].append(
            {
                "label": label,
                "command": command,
                "cwd": str(cwd),
                "status": None,
                "error": str(error),
                "seconds": time.monotonic() - started,
            }
        )
        raise SmokeFailure(f"{label} could not run: {error}") from error

    stdout_path, stderr_path = record_outputs(work, label, result.stdout, result.stderr)
    report["steps"].append(
        {
            "label": label,
            "command": command,
            "cwd": str(cwd),
            "status": result.returncode,
            "seconds": time.monotonic() - started,
            "stdout": stdout_path,
            "stderr": stderr_path,
        }
    )
    return result


def require_success(label: str, result: subprocess.CompletedProcess[bytes]) -> None:
    if result.returncode != 0:
        stdout = result.stdout.decode("utf-8", "replace")[-4000:]
        stderr = result.stderr.decode("utf-8", "replace")[-4000:]
        raise SmokeFailure(
            f"{label} exited {result.returncode}; stdout={stdout!r}; stderr={stderr!r}"
        )


def expected_result(
    package: Path,
    prefix: str,
    default_arguments: tuple[str, ...],
) -> tuple[list[str], int, bytes, bytes]:
    arguments_path = package / f"{prefix}.args"
    try:
        arguments = (
            arguments_path.read_text(encoding="utf-8").splitlines()
            if arguments_path.is_file()
            else list(default_arguments)
        )
        exit_code = int((package / f"{prefix}.exit").read_text(encoding="utf-8").strip())
        stdout = (package / f"{prefix}.stdout").read_bytes()
        stderr = (package / f"{prefix}.stderr").read_bytes()
    except (OSError, ValueError, UnicodeError) as error:
        raise SmokeFailure(f"could not read {prefix} oracle in {package}: {error}") from error
    return arguments, exit_code, stdout, stderr


def compare_run(
    label: str,
    package: Path,
    prefix: str,
    default_arguments: tuple[str, ...],
    result: subprocess.CompletedProcess[bytes],
    report: dict[str, Any],
) -> None:
    arguments, exit_code, stdout, stderr = expected_result(
        package, prefix, default_arguments
    )
    matches = (result.returncode, result.stdout, result.stderr) == (
        exit_code,
        stdout,
        stderr,
    )
    report["checks"].append(
        {
            "label": label,
            "arguments": arguments,
            "matches": matches,
            "expected_exit": exit_code,
            "actual_exit": result.returncode,
        }
    )
    if not matches:
        raise SmokeFailure(
            f"{label} differs from {prefix} oracle: "
            f"expected=({exit_code}, {stdout!r}, {stderr!r}), "
            f"actual=({result.returncode}, {result.stdout!r}, {result.stderr!r})"
        )


def run_smoke(root: Path, compiler: Path, clang: str, work: Path, report: dict[str, Any]) -> None:
    source_root = root / "tests" / "bootstrap"
    package_root = work / "packages"
    build_root = work / "build"
    package_root.mkdir()
    build_root.mkdir()
    for level in (1, 3):
        env = clean_environment(level)
        packages: dict[str, Path] = {}
        executables: dict[str, Path] = {}

        for fixture in FIXTURES:
            source_package = source_root / fixture
            label = f"{fixture}-O{level}"
            package = package_root / label
            shutil.copytree(
                source_package,
                package,
                ignore=shutil.ignore_patterns("output.data"),
            )
            packages[fixture] = package

            ir = build_root / f"{label}.ll"
            executable = build_root / label
            compile_command = [
                str(compiler),
                "build",
                package.relative_to(root).as_posix(),
                "-o",
                ir.relative_to(root).as_posix(),
                "--runtime=c",
            ]
            compiled = run_command(
                f"{label}-compile", compile_command, root, env, work, report
            )
            require_success(f"{label} compiler", compiled)

            link_command = [
                clang,
                f"-O{level}",
                "-DNLC_STACK_MODE_OFFSET=1",
                str(ir),
                str(root / "runtime" / "nl_runtime.c"),
                "-o",
                str(executable),
            ]
            linked = run_command(f"{label}-clang", link_command, root, env, work, report)
            require_success(f"{label} clang link", linked)
            if not executable.is_file() or not os.access(executable, os.X_OK):
                raise SmokeFailure(f"clang did not create executable {executable}")
            executables[fixture] = executable

        for fixture, case_name, prefix, default_arguments in RUNS:
            package = packages[fixture]
            arguments, _, _, _ = expected_result(
                package, prefix, default_arguments
            )
            label = f"{fixture}-O{level}-{case_name}"
            run_result = run_command(
                f"{label}-run",
                [str(executables[fixture]), *arguments],
                package,
                env,
                work,
                report,
            )
            compare_run(
                label,
                package,
                prefix,
                default_arguments,
                run_result,
                report,
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument(
        "--clang",
        default="clang",
        help="C compiler used to link runtime/nl_runtime.c (default: clang)",
    )
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    if not compiler.is_file() or not os.access(compiler, os.X_OK):
        print(f"compiler is not an executable file: {compiler}", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent
    try:
        work = Path(tempfile.mkdtemp(prefix=".c-bootstrap-smoke-", dir=root))
    except OSError as error:
        print(f"could not create bootstrap smoke directory: {error}", file=sys.stderr)
        return 1
    report: dict[str, Any] = {
        "compiler": str(compiler),
        "clang": args.clang,
        "timeout_seconds": TIMEOUT_SECONDS,
        "passed": False,
        "steps": [],
        "checks": [],
    }

    try:
        run_smoke(root, compiler, args.clang, work, report)
    except (SmokeFailure, OSError) as error:
        report["failure"] = str(error)
        try:
            (work / "report.json").write_text(
                json.dumps(report, indent=2) + "\n", encoding="utf-8"
            )
        except OSError as report_error:
            print(f"could not write smoke report: {report_error}", file=sys.stderr)
        print(f"FAIL: {error}", file=sys.stderr)
        print(f"Artifacts and report: {work}", file=sys.stderr)
        return 1

    report["passed"] = True
    shutil.rmtree(work, ignore_errors=True)
    print("PASS: C bootstrap fixtures at O1/O3, eight golden runs (including alpha beta and expected.args)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
