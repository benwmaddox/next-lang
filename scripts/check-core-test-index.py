#!/usr/bin/env python3
"""Compare C and core test-index parsing against strtol edge cases."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
NLC = Path.home() / ".cache/next-lang/target/debug/nlc"
VALUES = [
    ("0", True),
    (" 0", True),
    ("\t\n\v\f\r+0", True),
    ("-0", True),
    ("-1", False),
    ("1x", False),
    ("", False),
    ("+", False),
    ("999999999999999999999999", False),
]


def run(command: list[str], *, timeout: int) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(
        command,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"{result.stderr.decode(errors='replace')}"
        )
    return result


def main() -> int:
    if not NLC.is_file():
        raise RuntimeError(f"nlc is missing: {NLC}; run cargo build first")
    clang = shutil.which("clang")
    if not clang:
        raise RuntimeError("clang is not on PATH")

    work = Path(tempfile.mkdtemp(prefix=".core-test-index-", dir=ROOT))
    try:
        package = work / "package"
        package.mkdir()
        (package / "package.toml").write_text('name = "test-index"\n')
        (package / "main.nl").write_text(
            'fn main() { print(67890) }\n'
            'test "selection marker" { print(12345); expect true }\n'
        )
        for runtime in ("c", "core"):
            ir = work / f"{runtime}.ll"
            executable = work / runtime
            rel_ir = ir.relative_to(ROOT).as_posix()
            run(
                [
                    str(NLC),
                    "run",
                    "selfhost",
                    "--",
                    "build",
                    package.relative_to(ROOT).as_posix(),
                    "-o",
                    rel_ir,
                    "--test",
                    f"--runtime={runtime}",
                ],
                timeout=300,
            )
            run([str(NLC), "link-ir", rel_ir, "-o", executable.relative_to(ROOT).as_posix()], timeout=180)

            for value, selected in VALUES:
                environment = os.environ.copy()
                environment["NLC_TEST_INDEX"] = value
                result = subprocess.run(
                    [str(executable)],
                    cwd=ROOT,
                    env=environment,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=30,
                    check=False,
                )
                expected = b"12345\n" if selected else b"67890\n"
                if result.returncode != 0 or result.stdout != expected or result.stderr:
                    raise RuntimeError(
                        f"{runtime} NLC_TEST_INDEX={value!r}: status={result.returncode}, "
                        f"stdout={result.stdout!r}, stderr={result.stderr!r}, expected={expected!r}"
                    )
        print("NLC_TEST_INDEX C/core selection matched for whitespace, sign, -0, invalid suffix, and overflow cases")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=__import__("sys").stderr)
        raise SystemExit(1)
