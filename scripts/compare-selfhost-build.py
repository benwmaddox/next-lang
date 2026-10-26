#!/usr/bin/env python3
"""Compare stage-zero selfhost builds against Rust nlc on the E1 package table."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import random
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass


TIMEOUT_SECONDS = 90


@dataclass
class Result:
    status: int
    stdout: bytes
    stderr: bytes
    build_status: int | None = None


def status_code(code: int | None) -> int:
    return code if code is not None and code >= 0 else 128


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    reference = args.reference.resolve()
    if not reference.is_file() or not os.access(reference, os.X_OK):
        print(f"reference nlc is not executable: {reference}", file=sys.stderr)
        return 2

    env = os.environ.copy()
    env.pop("NLC_TEST_INDEX", None)
    env["NLC_FRONTEND"] = "rust"
    env.setdefault("CARGO_TARGET_DIR", str(Path.home() / ".cache/next-lang/target"))

    table = root / "tests/e1/classification.tsv"
    classifications = read_classifications(table, root)
    discovered = {
        path.relative_to(root).as_posix()
        for base in (root / "tests/run", root / "tests/test", root / "tests/e1")
        for path in base.iterdir()
        if path.is_dir()
    }
    if discovered != set(classifications):
        missing = sorted(discovered - set(classifications))
        extra = sorted(set(classifications) - discovered)
        print(f"classification table does not match package directories; missing={missing}, extra={extra}", file=sys.stderr)
        return 1

    work = Path(tempfile.mkdtemp(prefix=".selfhost-build-compare-", dir=root))
    try:
        stage0 = work / "selfhost"
        build_env = env.copy()
        build_env["NLC_OPT_LEVEL"] = "1"
        build = invoke(
            [str(reference), "--frontend=rust", "build", "selfhost", "-o", str(stage0)],
            cwd=root,
            env=build_env,
            timeout=300,
        )
        if build.status != 0 or not stage0.is_file():
            sys.stderr.buffer.write(build.stdout)
            sys.stderr.buffer.write(build.stderr)
            print("could not build the stage-zero selfhost compiler", file=sys.stderr)
            return 1

        counts = {
            level: {kind: 0 for kind in ("build", "diagnose", "unsupported", "mismatches")}
            for level in (1, 3)
        }
        generated_count = int(os.environ.get("NLC_E1_GENERATED_COUNT", "8"))
        generated_cases = generate_seeded_cases(root, work, generated_count)
        generated_counts = {
            level: {kind: 0 for kind in ("build", "diagnose", "mismatches")}
            for level in (1, 3)
        }
        for level in (1, 3):
            run_env = env.copy()
            run_env["NLC_OPT_LEVEL"] = str(level)
            for package, kind in classifications.items():
                try:
                    reference_result = run_reference(
                        reference, root, package, run_env, work, level
                    )
                    expected = expected_result(root, package)
                    if normalize_result(reference_result, root, package) != expected:
                        raise Mismatch("Rust reference differs from checked-in expected.* files")

                    if kind == "build":
                        if reference_result.build_status != 0:
                            raise Mismatch(
                                f"misclassified build: Rust compile status {reference_result.build_status}",
                                reference_result,
                            )
                        self_result, wrote_ir = run_selfhost(
                            stage0, reference, root, package, run_env, work, level
                        )
                        if not wrote_ir:
                            raise Mismatch("selfhosted compiler rejected a build package", reference_result, self_result)
                        if not same_result(self_result, reference_result):
                            raise Mismatch("built program or test runner differs from Rust nlc", reference_result, self_result)
                        counts[level]["build"] += 1
                    elif kind == "diagnose":
                        manifest_tool_failure = (
                            reference_result.status == 3
                            and expected[0] == 3
                            and (root / package / "package.toml").is_file()
                        )
                        if reference_result.status != 2 and not manifest_tool_failure:
                            raise Mismatch(f"misclassified diagnose: Rust status {reference_result.status}", reference_result)
                        self_result, wrote_ir = run_selfhost(
                            stage0, reference, root, package, run_env, work, level
                        )
                        if wrote_ir:
                            raise Mismatch("selfhosted compiler wrote IR after a rejection", reference_result, self_result)
                        if not same_result(self_result, reference_result):
                            raise Mismatch("diagnostic bytes or status differ from Rust nlc", reference_result, self_result)
                        counts[level]["diagnose"] += 1
                    else:
                        self_result, wrote_ir = run_selfhost(
                            stage0, reference, root, package, run_env, work, level
                        )
                        if wrote_ir:
                            raise Mismatch("unsupported package produced an IR artifact", reference_result, self_result)
                        if not is_unsupported(self_result):
                            raise Mismatch("unsupported package did not get the exact unsupported diagnostic", reference_result, self_result)
                        counts[level]["unsupported"] += 1

                    if package == "tests/test/harness" and kind == "build":
                        compare_test_package_main(
                            stage0, reference, root, package, run_env, work, level
                        )
                except (Mismatch, subprocess.TimeoutExpired, OSError) as error:
                    counts[level]["mismatches"] += 1
                    print(f"[{package} O{level}] {error}", file=sys.stderr)
                    if isinstance(error, Mismatch) and error.reference is not None:
                        print("  Rust:", brief(error.reference), file=sys.stderr)
                    if isinstance(error, Mismatch) and error.selfhost is not None:
                        print("  selfhost:", brief(error.selfhost), file=sys.stderr)
            for package, kind in generated_cases:
                try:
                    reference_result = run_reference(reference, root, package, run_env, work, level)
                    if kind == "build":
                        if reference_result.build_status != 0:
                            raise Mismatch("seeded build did not compile with Rust nlc", reference_result)
                    elif reference_result.status not in (2, 3):
                        raise Mismatch("seeded diagnostic did not diagnose with Rust nlc", reference_result)
                    self_result, wrote_ir = run_selfhost(stage0, reference, root, package, run_env, work, level)
                    if kind == "build":
                        if not wrote_ir:
                            raise Mismatch("selfhost rejected a seeded valid package", reference_result, self_result)
                        if not same_result(reference_result, self_result):
                            raise Mismatch("seeded build differs from Rust nlc", reference_result, self_result)
                        generated_counts[level]["build"] += 1
                    else:
                        if wrote_ir:
                            raise Mismatch("selfhost wrote IR for a seeded diagnostic", reference_result, self_result)
                        if not same_result(reference_result, self_result):
                            raise Mismatch("seeded diagnostic differs from Rust nlc", reference_result, self_result)
                        generated_counts[level]["diagnose"] += 1
                except (Mismatch, subprocess.TimeoutExpired, OSError) as error:
                    generated_counts[level]["mismatches"] += 1
                    print(f"[seeded {package} O{level}] {error}", file=sys.stderr)
                    if isinstance(error, Mismatch) and error.reference is not None:
                        print("  Rust:", brief(error.reference), file=sys.stderr)
                    if isinstance(error, Mismatch) and error.selfhost is not None:
                        print("  selfhost:", brief(error.selfhost), file=sys.stderr)

            print(
                f"O{level}: built and matching {counts[level]['build']}; "
                f"diagnosed and matching {counts[level]['diagnose']}; "
                f"unsupported {counts[level]['unsupported']}; "
                f"mismatches {counts[level]['mismatches']}; "
                f"seeded builds {generated_counts[level]['build']}; "
                f"seeded diagnostics {generated_counts[level]['diagnose']}; "
                f"seeded mismatches {generated_counts[level]['mismatches']}"
            )

        mismatches = sum(counts[level]["mismatches"] + generated_counts[level]["mismatches"] for level in counts)
        return 1 if mismatches else 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


class Mismatch(Exception):
    def __init__(self, message: str, reference: Result | None = None, selfhost: Result | None = None):
        super().__init__(message)
        self.reference = reference
        self.selfhost = selfhost


def read_classifications(path: Path, root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for number, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2 or parts[0] not in ("build", "diagnose", "unsupported"):
            raise ValueError(f"{path}:{number}: expected class<TAB>package")
        package = parts[1]
        if package in result:
            raise ValueError(f"{path}:{number}: duplicate package {package}")
        if not (root / package).is_dir():
            raise ValueError(f"{path}:{number}: missing package directory {package}")
        result[package] = parts[0]
    return result


def generate_seeded_cases(root: Path, work: Path, count: int) -> list[tuple[str, str]]:
    if count < 0 or count > 1000:
        raise ValueError("NLC_E1_GENERATED_COUNT must be between 0 and 1000")
    rng = random.Random(0xE1)
    cases: list[tuple[str, str]] = []
    base = work / "generated"
    valid_root = base / "valid"
    invalid_root = base / "invalid"
    valid_root.mkdir(parents=True)
    invalid_root.mkdir(parents=True)
    for index in range(count):
        package = valid_root / f"case-{index:04d}"
        package.mkdir()
        seed = rng.randint(-9, 9)
        start = rng.randint(-3, 0)
        end = rng.randint(0, 3)
        wide = rng.randint(-100, 100)
        source = (
            "fn adjust(value: int) -> int {\n"
            "    if value > 0 { value * 2 } else { value - 3 }\n"
            "}\n"
            "fn double(value: long) -> long { value * 2L }\n"
            "fn main() {\n"
            f"    var total = {seed}\n"
            f"    for item in {start}..={end} {{\n"
            "        if item % 2 == 0 { total += adjust(item) } else { total -= item }\n"
            "    }\n"
            f"    print(total + {rng.randint(-2, 2)})\n"
            f"    print(double({wide}L) / 2L)\n"
            "    print(false && (1 / 0 == 0))\n"
            "}\n"
        )
        (package / "main.nl").write_text(source)
        cases.append((package.relative_to(root).as_posix(), "build"))

    diagnostics = [
        "fn main() {\n    let value = 1\n    print(vaule)\n}\n",
        "fn main() {\n    let left: int = 1\n    let right: long = 2L\n    print(left + right)\n}\n",
        "fn main() {\n    let start = 0\n    let end = 2L\n    for index in start..end {}\n}\n",
        "fn value(flag: bool) -> int {\n    if flag { return 1 }\n}\n",
        "fn first() -> int { second() }\nfn second() -> int { first() }\nfn main() {}\n",
        "fn main() {\n    let item = 1\n    let item = 2\n}\n",
        "fn main(value: int) {}\n",
        "fn main() {\n    print(2147483648 + missing)\n}\n",
        "fn main() {\n    break\n}\n",
        "fn main() {\n    for index in 0..true {}\n}\n",
    ]
    rng.shuffle(diagnostics)
    for index in range(count):
        package = invalid_root / f"case-{index:04d}"
        package.mkdir()
        (package / "main.nl").write_text(diagnostics[index % len(diagnostics)])
        cases.append((package.relative_to(root).as_posix(), "diagnose"))
    return cases


def invoke(command: list[str], cwd: Path, env: dict[str, str], timeout: int = TIMEOUT_SECONDS) -> Result:
    try:
        proc = subprocess.run(command, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        return Result(status_code(proc.returncode), proc.stdout, proc.stderr)
    except subprocess.TimeoutExpired as error:
        raise TimeoutError(f"timed out after {timeout}s: {' '.join(command)}") from error


def package_cwd(root: Path, package: str) -> tuple[Path, str, bool]:
    if package == "tests/run/t20_probe":
        return root / package, ".", True
    return root, package, False


def is_test_package(package: str) -> bool:
    return package.startswith("tests/test/") or package.startswith("tests/e1/test_")


def run_reference(reference: Path, root: Path, package: str, env: dict[str, str], work: Path, level: int) -> Result:
    cwd, package_arg, local = package_cwd(root, package)
    if is_test_package(package):
        result = invoke(
            [str(reference), "--frontend=rust", "test", package_arg], cwd=cwd, env=env
        )
        result.build_status = 0 if result.status in (0, 1, 70) else result.status
        return result
    package_path = root / package
    suffix = f"{os.getpid()}-{level}"
    exe = work / f"ref-{suffix}"
    if exe.exists():
        exe.unlink()
    built = invoke(
        [str(reference), "--frontend=rust", "build", package_arg, "-o", str(exe) if local else str(exe)],
        cwd=cwd,
        env=env,
    )
    if built.status != 0:
        return built
    generated_file = package_path / "a.txt"
    had_generated_file = generated_file.exists()
    try:
        result = invoke([str(exe)], cwd=cwd, env=env)
        result.build_status = 0
        return result
    finally:
        exe.unlink(missing_ok=True)
        if local and not had_generated_file:
            generated_file.unlink(missing_ok=True)


def run_selfhost(
    stage0: Path,
    reference: Path,
    root: Path,
    package: str,
    env: dict[str, str],
    work: Path,
    level: int,
) -> tuple[Result, bool]:
    cwd, package_arg, local = package_cwd(root, package)
    package_path = root / package
    suffix = f"{os.getpid()}-{level}"
    if local:
        ir = package_path / f".e1-self-{suffix}.ll"
        exe = package_path / f".e1-self-{suffix}"
        ir_arg = ir.name
    else:
        ir = work / f"self-{suffix}.ll"
        exe = work / f"self-{suffix}"
        ir_arg = ir.relative_to(root).as_posix()
    ir.unlink(missing_ok=True)
    exe.unlink(missing_ok=True)
    is_test = is_test_package(package)
    command = [str(stage0), "build", package_arg, "-o", ir_arg]
    if is_test:
        command.append("--test")
    compiled = invoke(command, cwd=cwd, env=env)
    if compiled.status != 0:
        return compiled, ir.exists()
    if not ir.is_file():
        return Result(128, b"", b"selfhost build returned success without an IR file\n"), False
    if is_test:
        linked = invoke([str(reference), "test-ir", str(ir)], cwd=cwd, env=env)
        ir.unlink(missing_ok=True)
        return linked, True
    linked = invoke([str(reference), "link-ir", str(ir), "-o", str(exe)], cwd=cwd, env=env)
    ir.unlink(missing_ok=True)
    if linked.status != 0:
        return linked, True
    try:
        return invoke([str(exe)], cwd=cwd, env=env), True
    finally:
        exe.unlink(missing_ok=True)


def compare_test_package_main(
    stage0: Path, reference: Path, root: Path, package: str, env: dict[str, str], work: Path, level: int
) -> None:
    suffix = f"{os.getpid()}-{level}-main"
    exe = work / f"reference-main-{suffix}"
    ir = work / f"self-main-{suffix}.ll"
    self_exe = work / f"self-main-{suffix}"
    ref = invoke(
        [str(reference), "--frontend=rust", "build", package, "-o", str(exe)], cwd=root, env=env
    )
    if ref.status == 0:
        ref = invoke([str(exe)], cwd=root, env=env)
    exe.unlink(missing_ok=True)
    command = [str(stage0), "build", package, "-o", ir.relative_to(root).as_posix()]
    built = invoke(command, cwd=root, env=env)
    if built.status != 0:
        raise Mismatch("test package program build was rejected", ref, built)
    linked = invoke([str(reference), "link-ir", str(ir), "-o", str(self_exe)], cwd=root, env=env)
    ir.unlink(missing_ok=True)
    actual = linked if linked.status != 0 else invoke([str(self_exe)], cwd=root, env=env)
    self_exe.unlink(missing_ok=True)
    if not same_result(actual, ref):
        raise Mismatch("test package build did not run main like Rust nlc", ref, actual)


def normalize_bytes(data: bytes, root: Path, package: str) -> bytes:
    package_path = (root / package).resolve()
    data = data.replace(str(root.resolve()).encode(), b"<repo>")
    data = data.replace(str(package_path).encode(), b"<package>")
    return re.sub(rb"/tmp/next-lang-[^/]+", b"<temp>", data)


def normalize_result(result: Result, root: Path, package: str) -> tuple[int, bytes, bytes]:
    return (
        result.status,
        normalize_bytes(result.stdout, root, package),
        normalize_bytes(result.stderr, root, package),
    )


def same_result(left: Result, right: Result) -> bool:
    return (left.status, left.stdout, left.stderr) == (right.status, right.stdout, right.stderr)


def expected_result(root: Path, package: str) -> tuple[int, bytes, bytes]:
    directory = root / package
    try:
        stdout = (directory / "expected.stdout").read_bytes()
        stderr = (directory / "expected.stderr").read_bytes()
        exit_code = int((directory / "expected.exit").read_text().strip())
    except (OSError, ValueError) as error:
        raise Mismatch(f"missing or invalid expected.* oracle: {error}") from error
    return exit_code, stdout, stderr


def is_unsupported(result: Result) -> bool:
    return (
        result.status == 2
        and result.stdout == b""
        and re.fullmatch(
            rb"[^\n:]+:[0-9]+:[0-9]+: error: not supported by the self-hosted compiler yet: [^\n]+\n",
            result.stderr,
        )
        is not None
    )


def brief(result: Result) -> str:
    return f"status={result.status}, stdout={result.stdout[:160]!r}, stderr={result.stderr[:240]!r}"


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, Mismatch, TimeoutError, OSError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
