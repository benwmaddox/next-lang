#!/usr/bin/env python3
"""Build or reuse stage 0, keyed by selfhost/core sources and stage-0 sources.

The cache lives in CARGO_TARGET_DIR and is shared by the build, lexer/parser,
and relocation checks. A test-only edit therefore leaves the compiler build
reusable. Use --reference <nlc>; the absolute cached executable path is printed
to stdout for callers.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def cache_key(root: Path, reference: Path) -> str:
    digest = hashlib.sha256()
    digest.update(f"{sys.platform}:{platform.machine()}".encode())
    for directory in (root / "selfhost", root / "core"):
        if not directory.is_dir():
            raise RuntimeError(f"source directory is missing: {directory}")
        for path in sorted(directory.rglob("*")):
            if not path.is_file() or not (path.suffix == ".nl" or path.name == "package.toml"):
                continue
            relative = path.relative_to(root).as_posix().encode()
            content = path.read_bytes()
            digest.update(len(relative).to_bytes(8, "little"))
            digest.update(relative)
            digest.update(len(content).to_bytes(8, "little"))
            digest.update(content)
    # Stage 0 is identified by its sources (rustc's version is added below),
    # not by the nlc binary, which embeds its checkout path and so differs for
    # every pre-commit snapshot.
    digest.update(b"reference-nlc-sources\0")
    stage0_files = [root / "Cargo.lock", root / "compiler/Cargo.toml", root / "compiler/build.rs"]
    stage0_files += sorted(path for path in (root / "compiler/src").rglob("*") if path.is_file())
    for path in stage0_files:
        if path.is_file():
            relative = path.relative_to(root).as_posix().encode()
            content = path.read_bytes()
            digest.update(len(relative).to_bytes(8, "little") + relative)
            digest.update(len(content).to_bytes(8, "little") + content)
    for name in ("NLC_STACK_MODE", "TARGET"):
        digest.update(name.encode() + b"\0" + os.environ.get(name, "").encode() + b"\0")
    for tool in ("clang", "rustc"):
        try:
            version = subprocess.run(
                [tool, "--version"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
                text=True,
            )
        except OSError as error:
            raise RuntimeError(f"cannot identify {tool}: {error}") from error
        if version.returncode != 0:
            raise RuntimeError(f"cannot identify {tool}: {version.stdout.strip()}")
        digest.update(tool.encode() + b"\0" + version.stdout.encode() + b"\0")
    return digest.hexdigest()


def artifact_is_valid(directory: Path, binary: Path) -> bool:
    if not binary.is_file() or not os.access(binary, os.X_OK):
        return False
    try:
        expected = (directory / "binary.sha256").read_text().strip()
        actual = hashlib.sha256(binary.read_bytes()).hexdigest()
    except OSError:
        return False
    return expected == actual


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path)
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    reference = args.reference.resolve()
    if not reference.is_file() or not os.access(reference, os.X_OK):
        raise RuntimeError(f"reference nlc is not executable: {reference}")

    target_dir = Path(os.environ.get("CARGO_TARGET_DIR", root / "target"))
    if not target_dir.is_absolute():
        target_dir = root / target_dir
    cache_root = target_dir.resolve() / "next-lang-test-selfhost"
    cache_root.mkdir(parents=True, exist_ok=True)
    key = cache_key(root, reference)
    artifact_dir = cache_root / key
    binary_name = "selfhost.exe" if os.name == "nt" else "selfhost"
    binary = artifact_dir / binary_name

    with (cache_root / "build.lock").open("a+b") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        if not artifact_is_valid(artifact_dir, binary):
            if artifact_dir.exists():
                shutil.rmtree(artifact_dir)
            staging = Path(tempfile.mkdtemp(prefix=f".{key}.", dir=cache_root))
            try:
                staged_binary = staging / binary_name
                environment = os.environ.copy()
                environment["NLC_FRONTEND"] = "rust"
                environment["NLC_OPT_LEVEL"] = "1"
                environment.pop("NLC_TEST_INDEX", None)
                for name in tuple(environment):
                    if name.startswith("NLC_TEST_STACK_"):
                        environment.pop(name, None)
                result = subprocess.run(
                    [str(reference), "--frontend=rust", "build", "selfhost", "-o", str(staged_binary)],
                    cwd=root,
                    env=environment,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=300,
                    check=False,
                )
                if result.returncode != 0 or not staged_binary.is_file():
                    sys.stderr.buffer.write(result.stdout)
                    sys.stderr.buffer.write(result.stderr)
                    raise RuntimeError(
                        f"could not build stage-zero selfhost compiler (status {result.returncode})"
                    )
                marker = hashlib.sha256(staged_binary.read_bytes()).hexdigest()
                (staging / "binary.sha256").write_text(marker + "\n")
                os.replace(staging, artifact_dir)
            finally:
                if staging.exists():
                    shutil.rmtree(staging, ignore_errors=True)
        if not artifact_is_valid(artifact_dir, binary):
            raise RuntimeError(f"cached selfhost compiler failed validation: {binary}")

    print(binary)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
