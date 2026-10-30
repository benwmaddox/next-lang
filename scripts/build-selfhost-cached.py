#!/usr/bin/env python3
"""Build or reuse the self-hosted compiler, keyed by the selfhost/core sources and the seed IR.

The cache lives in CARGO_TARGET_DIR and is shared by the build, lexer/parser,
and relocation checks. A test-only edit therefore leaves the compiler build
reusable. The compiler is built from seed/seed.ll.gz with clang and the live runtime; the absolute path of
the cached executable is printed to stdout for callers.
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


def artifact_is_valid(directory: Path, binary: Path) -> bool:
    if not binary.is_file() or not os.access(binary, os.X_OK):
        return False
    try:
        expected = (directory / "binary.sha256").read_text().strip()
        actual = hashlib.sha256(binary.read_bytes()).hexdigest()
    except OSError:
        return False
    return expected == actual


def seed_cache_key(root: Path, seed: Path) -> str:
    digest = hashlib.sha256()
    digest.update(f"{sys.platform}:{platform.machine()}".encode())
    for directory in (root / "selfhost", root / "core"):
        for path in sorted(directory.rglob("*")):
            if not path.is_file() or not (path.suffix == ".nl" or path.name == "package.toml"):
                continue
            relative = path.relative_to(root).as_posix().encode()
            content = path.read_bytes()
            digest.update(len(relative).to_bytes(8, "little") + relative)
            digest.update(len(content).to_bytes(8, "little") + content)
    digest.update(b"seed\0" + hashlib.sha256(seed.read_bytes()).digest())
    digest.update((root / "runtime" / "nl_runtime.c").read_bytes())
    version = subprocess.run(["clang", "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False, text=True)
    digest.update(version.stdout.encode())
    return digest.hexdigest()


def build_seed_compiler(root: Path, seed: Path, directory: Path) -> Path:
    """Compile the checked-in seed IR (gzip) with the C runtime into a compiler binary."""
    import gzip

    directory.mkdir(parents=True, exist_ok=True)
    binary = directory / "seedc"
    if binary.is_file():
        return binary
    ir = directory / "seed.ll"
    with gzip.open(seed, "rb") as source, ir.open("wb") as target:
        shutil.copyfileobj(source, target)
    staged = directory / f"seedc.{os.getpid()}"
    result = subprocess.run(
        ["clang", "-O1", "-DNLC_STACK_MODE_OFFSET=1", str(ir), str(root / "runtime" / "nl_runtime.c"), "-o", str(staged)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    ir.unlink(missing_ok=True)
    if result.returncode != 0:
        sys.stderr.buffer.write(result.stderr)
        raise RuntimeError("could not build the compiler from the seed IR")
    os.replace(staged, binary)
    return binary


def main_from_seed(root: Path, seed: Path) -> int:
    """Build the selfhost compiler from the current sources using the compiler built from the seed IR."""
    target_dir = Path(os.environ.get("CARGO_TARGET_DIR", root / "target"))
    if not target_dir.is_absolute():
        target_dir = root / target_dir
    cache_root = target_dir.resolve() / "next-lang-test-selfhost-seed"
    cache_root.mkdir(parents=True, exist_ok=True)
    key = seed_cache_key(root, seed)
    artifact_dir = cache_root / key
    binary = artifact_dir / "selfhost"
    with (cache_root / "build.lock").open("a+b") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        if not artifact_is_valid(artifact_dir, binary):
            if artifact_dir.exists():
                shutil.rmtree(artifact_dir)
            seed_hash = hashlib.sha256(seed.read_bytes()).hexdigest()[:16]
            seed_compiler = build_seed_compiler(root, seed, cache_root / f"seed-{seed_hash}")
            staging = Path(tempfile.mkdtemp(prefix=f".{key}.", dir=cache_root))
            ir_name = f".seed-build-{os.getpid()}.ll"
            try:
                environment = os.environ.copy()
                for name in tuple(environment):
                    if name.startswith("NLC_TEST_"):
                        environment.pop(name, None)
                # The compiler reads and writes only beneath its working directory, so the IR goes in the root.
                result = subprocess.run(
                    [str(seed_compiler), "build", "selfhost", "-o", ir_name, "--runtime=c"],
                    cwd=root, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600, check=False,
                )
                if result.returncode != 0 or not (root / ir_name).is_file():
                    sys.stderr.buffer.write(result.stdout + result.stderr)
                    raise RuntimeError(f"the seed compiler could not build selfhost (status {result.returncode})")
                staged_binary = staging / "selfhost"
                link = subprocess.run(
                    ["clang", "-O1", "-DNLC_STACK_MODE_OFFSET=1", str(root / ir_name), str(root / "runtime" / "nl_runtime.c"), "-o", str(staged_binary)],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
                )
                if link.returncode != 0:
                    sys.stderr.buffer.write(link.stderr)
                    raise RuntimeError("clang could not link the selfhost compiler")
                (staging / "binary.sha256").write_text(hashlib.sha256(staged_binary.read_bytes()).hexdigest() + "\n")
                os.replace(staging, artifact_dir)
            finally:
                (root / ir_name).unlink(missing_ok=True)
                if staging.exists():
                    shutil.rmtree(staging, ignore_errors=True)
        if not artifact_is_valid(artifact_dir, binary):
            raise RuntimeError(f"cached selfhost compiler failed validation: {binary}")
    print(binary)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=Path, help="seed IR (gzip); default seed/seed.ll.gz")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    return main_from_seed(root, (args.seed or root / "seed" / "seed.ll.gz").resolve())


if __name__ == "__main__":
    sys.exit(main())
