#!/usr/bin/env python3
"""Check that self-hosted programs preserve behaviour when their stack moves."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


TIMEOUT_SECONDS = 180
STATS = re.compile(
    rb"^nl offset stack entry '.*': initial=([0-9]+) reserved=([0-9]+) "
    rb"peak_used=([0-9]+) growths=([0-9]+) relocations=([0-9]+) growth_ns=([0-9]+)$"
)


class CheckError(RuntimeError):
    pass


def invoke(command: list[str], cwd: Path, env: dict[str, str]) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise CheckError(f"timed out after {TIMEOUT_SECONDS}s: {' '.join(command)}") from error


def command_result(result: subprocess.CompletedProcess[bytes]) -> str:
    return (
        f"status={result.returncode}, stdout={result.stdout[:160]!r}, "
        f"stderr={result.stderr[:240]!r}"
    )


def read_classifications(path: Path, root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for number, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2 or parts[0] not in ("build", "diagnose", "rejects", "unsupported"):
            raise CheckError(f"{path}:{number}: expected class<TAB>package")
        if parts[1] in result:
            raise CheckError(f"{path}:{number}: duplicate package {parts[1]}")
        if not (root / parts[1]).is_dir():
            raise CheckError(f"{path}:{number}: missing package directory {parts[1]}")
        result[parts[1]] = parts[0]
    return result


def package_cwd(root: Path, package: str) -> Path:
    return root / package if package == "tests/run/t20_probe" else root


def build_ir(
    stage0: Path,
    root: Path,
    package: str,
    level: int,
    work: Path,
    label: str,
    threshold_zero: bool,
    env: dict[str, str],
) -> tuple[Path, list[int]]:
    ir = work / f"{label}.ll"
    args = [str(stage0), "build", package, "-o", ir.relative_to(root).as_posix(), "--test"]
    if threshold_zero:
        args.append("--test-region-threshold=0")
    build_env = env.copy()
    build_env["NLC_OPT_LEVEL"] = str(level)
    built = invoke(args, root, build_env)
    if built.returncode != 0 or not ir.is_file():
        raise CheckError(
            f"selfhost could not compile {package} at O{level} ({label}): "
            f"{command_result(built)}"
        )
    tests = [
        int(value)
        for value in re.findall(rb"^; nlc\.test ([0-9]+) ", ir.read_bytes(), re.MULTILINE)
    ]
    return ir, tests


def link_ir(reference: Path, root: Path, ir: Path, exe: Path, level: int, env: dict[str, str]) -> None:
    link_env = env.copy()
    link_env["NLC_OPT_LEVEL"] = str(level)
    linked = invoke(
        [str(reference), "link-ir", ir.relative_to(root).as_posix(), "-o", exe.relative_to(root).as_posix()],
        root,
        link_env,
    )
    if linked.returncode != 0 or not exe.is_file():
        raise CheckError(f"could not link {ir.name} at O{level}: {command_result(linked)}")


def clean_runtime_environment(level: int, special: str | None) -> dict[str, str]:
    env = os.environ.copy()
    for key in tuple(env):
        if key.startswith("NLC_TEST_STACK_") or key in (
            "NLC_TEST_INDEX",
            "NLC_STACK_VERIFY",
            "NLC_STACK_STATS",
            "NLC_STACK_PREALLOC",
        ):
            env.pop(key, None)
    env["NLC_FRONTEND"] = "rust"
    env["NLC_OPT_LEVEL"] = str(level)
    if special == "two-phase":
        env["NLC_TEST_STACK_TWO_PHASE"] = "1"
    elif special == "grow":
        env["NLC_TEST_STACK_GROW"] = "1"
    return env


def run_program(
    executable: Path,
    cwd: Path,
    env: dict[str, str],
    test_index: int | None,
) -> subprocess.CompletedProcess[bytes]:
    run_env = env.copy()
    if test_index is not None:
        run_env["NLC_TEST_INDEX"] = str(test_index)
    return invoke([str(executable)], cwd, run_env)


def take_stats(stderr: bytes, package: str, level: int, test_index: int | None) -> tuple[bytes, tuple[int, ...]]:
    lines = stderr.splitlines(keepends=True)
    matches = [index for index, line in enumerate(lines) if line.startswith(b"nl offset stack entry ")]
    if len(matches) != 1:
        raise CheckError(
            f"{package} at O{level} test={test_index}: expected one stack stats line, "
            f"found {len(matches)} in {stderr!r}"
        )
    index = matches[0]
    raw_line = lines[index].rstrip(b"\r\n")
    parsed = STATS.fullmatch(raw_line)
    if parsed is None:
        raise CheckError(f"{package} at O{level}: malformed stats line {raw_line!r}")
    values = tuple(int(value) for value in parsed.groups())
    if values[3] != values[4]:
        raise CheckError(
            f"{package} at O{level} test={test_index}: growths {values[3]} "
            f"do not equal relocations {values[4]}"
        )
    del lines[index]
    return b"".join(lines), values


def compare_run(
    ordinary: subprocess.CompletedProcess[bytes],
    moved: subprocess.CompletedProcess[bytes],
    package: str,
    level: int,
    test_index: int | None,
) -> tuple[int, ...]:
    moved_stderr, stats = take_stats(moved.stderr, package, level, test_index)
    if (ordinary.returncode, ordinary.stdout, ordinary.stderr) != (
        moved.returncode,
        moved.stdout,
        moved_stderr,
    ):
        raise CheckError(
            f"relocated output differs for {package} at O{level} test={test_index}: "
            f"ordinary=({command_result(ordinary)}), moved=(status={moved.returncode}, "
            f"stdout={moved.stdout[:160]!r}, stderr={moved_stderr[:240]!r})"
        )
    return stats


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    reference = args.reference.resolve()
    if not reference.is_file() or not os.access(reference, os.X_OK):
        raise CheckError(f"reference nlc is not executable: {reference}")

    env = os.environ.copy()
    env["NLC_FRONTEND"] = "rust"
    env.setdefault("CARGO_TARGET_DIR", str(Path.home() / ".cache/next-lang/target"))
    classifications = read_classifications(root / "tests/e1/classification.tsv", root)
    package_roots = tuple(root / f"tests/{name}" for name in ("run", "test", "e1", "e2", "e3"))
    discovered = {
        path.relative_to(root).as_posix()
        for base in package_roots
        for path in base.iterdir()
        if path.is_dir()
    }
    if discovered != set(classifications):
        missing = sorted(discovered - set(classifications))
        extra = sorted(set(classifications) - discovered)
        raise CheckError(f"classification table mismatch: missing={missing}, extra={extra}")
    packages = [package for package, kind in classifications.items() if kind == "build"]

    work = Path(tempfile.mkdtemp(prefix=".selfhost-relocation-", dir=root))
    generated_path = root / "tests/run/t20_probe/a.txt"
    had_generated = generated_path.exists()
    generated_bytes = generated_path.read_bytes() if had_generated else b""
    try:
        stage0 = work / "selfhost"
        stage0_env = env.copy()
        stage0_env["NLC_OPT_LEVEL"] = "1"
        built = invoke(
            [str(reference), "--frontend=rust", "build", "selfhost", "-o", stage0.relative_to(root).as_posix()],
            root,
            stage0_env,
        )
        if built.returncode != 0 or not stage0.is_file():
            raise CheckError(f"could not build the stage-zero selfhost compiler: {command_result(built)}")

        run_count = {1: 0, 3: 0}
        relocated_packages = {1: set(), 3: set()}
        for level in (1, 3):
            for package_index, package in enumerate(packages, 1):
                special = None
                if package == "tests/e3/a1_two_phase":
                    special = "two-phase"
                elif package == "tests/e3/a1_core_probes":
                    special = "grow"
                ordinary_env = clean_runtime_environment(level, special)

                ordinary_ir, ordinary_tests = build_ir(
                    stage0, root, package, level, work, f"o{level}-ordinary-{package_index}", False, env
                )
                moved_ir, moved_tests = build_ir(
                    stage0, root, package, level, work, f"o{level}-moved-{package_index}", True, env
                )
                if ordinary_tests != moved_tests:
                    raise CheckError(f"test index tables differ for {package} at O{level}")
                ordinary_exe = work / f"o{level}-ordinary-{package_index}"
                moved_exe = work / f"o{level}-moved-{package_index}"
                link_ir(reference, root, ordinary_ir, ordinary_exe, level, env)
                link_ir(reference, root, moved_ir, moved_exe, level, env)
                cwd = package_cwd(root, package)

                indices: list[int | None] = [None, *ordinary_tests]
                package_relocated = False
                for test_index in indices:
                    ordinary_result = run_program(ordinary_exe, cwd, ordinary_env, test_index)
                    moved_env = ordinary_env.copy()
                    moved_env["NLC_TEST_STACK_FORCE_MOVE"] = "1"
                    moved_env["NLC_STACK_VERIFY"] = "1"
                    moved_env["NLC_STACK_STATS"] = "1"
                    moved_result = run_program(moved_exe, cwd, moved_env, test_index)
                    stats = compare_run(ordinary_result, moved_result, package, level, test_index)
                    if stats[4] > 0:
                        package_relocated = True
                    run_count[level] += 1

                if package.startswith(("tests/e3/a1_", "tests/e3/merge_")) and not package_relocated:
                    raise CheckError(f"directed relocation fixture {package} never relocated at O{level}")
                if package_relocated:
                    relocated_packages[level].add(package)

                if package == "tests/e3/a1_core_probes":
                    moved_env = ordinary_env.copy()
                    moved_env.update(
                        {
                            "NLC_TEST_STACK_FORCE_MOVE": "1",
                            "NLC_STACK_VERIFY": "1",
                            "NLC_TEST_INDEX": "0",
                            "NLC_TEST_STACK_PIN_REFUSAL": "1",
                        }
                    )
                    pin = invoke([str(moved_exe)], cwd, moved_env)
                    if pin.returncode != 70 or b"data stack exhausted" not in pin.stderr:
                        raise CheckError(f"pin refusal probe did not fail with kind 18: {command_result(pin)}")
                    poison_env = ordinary_env.copy()
                    poison_env.update(
                        {
                            "NLC_TEST_STACK_FORCE_MOVE": "1",
                            "NLC_STACK_VERIFY": "1",
                            "NLC_TEST_INDEX": "0",
                            "NLC_TEST_STACK_POISON_FULL": "1",
                        }
                    )
                    poison = invoke([str(moved_exe)], cwd, poison_env)
                    if poison.returncode != 70 or b"data stack exhausted" not in poison.stderr:
                        raise CheckError(f"full poison table probe did not fail with kind 18: {command_result(poison)}")

                if package_index % 25 == 0 or package_index == len(packages):
                    print(f"O{level}: checked {package_index}/{len(packages)} packages", flush=True)

            print(
                f"O{level}: {run_count[level]} runs, {len(relocated_packages[level])} packages relocated",
                flush=True,
            )
        print(f"relocation check passed: {len(packages)} build packages; zero mismatches")
    finally:
        if had_generated:
            generated_path.write_bytes(generated_bytes)
        else:
            generated_path.unlink(missing_ok=True)
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (CheckError, OSError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
