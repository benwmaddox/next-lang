"""Shared helpers for the selfhost test suite (python3 -m unittest discover -s tests/py).

The self-hosted compiler is built from the checked-in seed by scripts/build-selfhost-cached.py, or taken
from NLC_SELFHOST. The compiler reads and writes only beneath its working directory, so temporary packages
are created as directories and compiled with the current directory set to them.
"""

import contextlib
import functools
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


@functools.lru_cache(maxsize=1)
def selfhost() -> pathlib.Path:
    override = os.environ.get("NLC_SELFHOST")
    if override:
        return pathlib.Path(override).resolve()
    built = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "build-selfhost-cached.py")],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )
    if built.returncode != 0:
        raise RuntimeError("selfhost build failed:\n" + built.stderr.decode(errors="replace"))
    return pathlib.Path(built.stdout.decode().strip())


@contextlib.contextmanager
def temporary_package(files):
    """A directory holding the given {name: text} files; removed afterwards."""
    directory = pathlib.Path(tempfile.mkdtemp(prefix="nl-test-"))
    try:
        for name, text in files.items():
            (directory / name).write_text(text)
        yield directory
    finally:
        shutil.rmtree(directory, ignore_errors=True)


def compile_package(directory, output="out.ll", runtime="core", extra=(), timeout=120, package="."):
    """Run the self-hosted compiler in `directory` on `package`; returns the CompletedProcess."""
    return subprocess.run(
        [str(selfhost()), "build", str(package), "-o", output, f"--runtime={runtime}", *extra],
        cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False,
    )


def verify_ir(directory, ir="out.ll"):
    """Have LLVM check that the IR is well formed (the module is compiled to an object)."""
    return subprocess.run(
        ["clang", "-x", "ir", "-c", ir, "-o", "out.o"],
        cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
    )


def run_script(script, *args, timeout=3600):
    return subprocess.run(
        [sys.executable, str(ROOT / "scripts" / script), *args],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False,
    )
