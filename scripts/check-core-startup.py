#!/usr/bin/env python3
"""Compare C and core argument and startup-environment boundaries."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
TARGET = Path.home() / ".cache/next-lang/target"
NLC_RELEASE = TARGET / "release/nlc"
NLC = NLC_RELEASE if NLC_RELEASE.is_file() else TARGET / "debug/nlc"


def checked(command: list[str], *, timeout: int) -> None:
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


def build_pair(work: Path, package: Path) -> dict[str, Path]:
    outputs: dict[str, Path] = {}
    for runtime in ("c", "core"):
        ir = work / f"startup-{runtime}.ll"
        executable = work / f"startup-{runtime}"
        checked(
            [
                str(NLC),
                "run",
                "selfhost",
                "--",
                "build",
                package.relative_to(ROOT).as_posix(),
                "-o",
                ir.relative_to(ROOT).as_posix(),
                f"--runtime={runtime}",
            ],
            timeout=300,
        )
        checked([str(NLC), "link-ir", ir.relative_to(ROOT).as_posix(), "-o", executable.relative_to(ROOT).as_posix()], timeout=180)
        outputs[runtime] = executable
    return outputs


def run_case(binary: Path, args: list[str], env: dict[str, str], *, cwd: Path | None = None, preexec_fn=None) -> tuple[int, bytes, bytes]:
    result = subprocess.run(
        [str(binary), *args],
        cwd=cwd or ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
        preexec_fn=preexec_fn,
    )
    return result.returncode, result.stdout, result.stderr


def main() -> int:
    if not NLC.is_file():
        raise RuntimeError(f"nlc is missing: {NLC}; run cargo build first")
    if not shutil.which("clang"):
        raise RuntimeError("clang is not on PATH")

    work = Path(tempfile.mkdtemp(prefix=".core-startup-check-", dir=ROOT))
    try:
        package = work / "package"
        package.mkdir()
        (package / "package.toml").write_text('name = "startup-check"\n')
        (package / "main.nl").write_text("fn main() {}\n")
        binaries = build_pair(work, package)
        base_env = os.environ.copy()
        expected_cases = [
            ("64 arguments", ["arg"] * 64, base_env, None, None, 0, b""),
            ("65 arguments", ["arg"] * 65, base_env, None, None, 1, b"nlc: startup argument failure: more than 64 program arguments were supplied\n"),
            ("4096-byte argument", ["x" * 4096], base_env, None, None, 0, b""),
            ("4097-byte argument", ["x" * 4097], base_env, None, None, 1, b"nlc: startup argument failure: a program argument is longer than 4096 bytes\n"),
        ]
        for label, args, env, cwd, preexec, status, expected_error in expected_cases:
            outputs = {
                runtime: run_case(binary, args, env, cwd=cwd, preexec_fn=preexec)
                for runtime, binary in binaries.items()
            }
            if outputs["c"] != outputs["core"]:
                raise RuntimeError(f"{label} C/core startup mismatch: {outputs!r}")
            code, stdout, stderr = outputs["core"]
            if code != status or stdout or stderr != expected_error:
                raise RuntimeError(f"{label} unexpected result: {(code, stdout, stderr)!r}")

        prealloc_env = base_env.copy()
        prealloc_env["NLC_STACK_PREALLOC"] = "1"
        prealloc = {runtime: run_case(binary, [], prealloc_env) for runtime, binary in binaries.items()}
        if prealloc["c"] != prealloc["core"] or prealloc["core"] != (0, b"", b""):
            raise RuntimeError(f"NLC_STACK_PREALLOC=1 C/core startup mismatch: {prealloc!r}")

        if os.geteuid() != 0:
            restricted = work / "restricted"
            restricted.mkdir(mode=0o700)

            def remove_search_permission() -> None:
                os.chmod(".", 0o600)

            try:
                failures = {
                    runtime: run_case(binary, [], base_env, cwd=restricted, preexec_fn=remove_search_permission)
                    for runtime, binary in binaries.items()
                }
            finally:
                os.chmod(restricted, 0o700)
            expected = (1, b"", b"nlc: data stack startup failure: cannot open the file-system root\n")
            if failures["c"] != failures["core"] or failures["core"] != expected:
                raise RuntimeError(f"root-open startup mismatch: {failures!r}")
        else:
            print("working-directory permission test skipped when running as root")

        print("startup checks passed: 64/65 arguments, 4096/4097-byte arguments, NLC_STACK_PREALLOC, root-open failure")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=__import__("sys").stderr)
        raise SystemExit(1)
