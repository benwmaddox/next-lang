#!/usr/bin/env python3
"""Compare stage-zero selfhost builds against Rust nlc on the checked package table.

Use ``scripts/compare-selfhost.sh --build`` for the full table. ``--only GLOB``,
``--class build``, and ``--changed [REV]`` (default REV: HEAD) select a focused
package set. Workers default to half the logical CPUs; set ``NLC_TEST_JOBS``
to override. The stage-zero compiler is shared through a source-hash cache in
``CARGO_TARGET_DIR``.
"""

from __future__ import annotations

import argparse
import base64
import binascii
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import random
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass

from test_harness import add_filter_arguments, changed_paths, filter_label, select_packages, worker_count


TIMEOUT_SECONDS = 90


@dataclass
class Result:
    status: int
    stdout: bytes
    stderr: bytes
    build_status: int | None = None


class ReferenceResultCache:
    """Persistent cache of normalized stage-zero reference results."""

    VERSION = 1

    def __init__(self, root: Path, reference: Path, env: dict[str, str], disabled: bool):
        target = Path(env["CARGO_TARGET_DIR"])
        if not target.is_absolute():
            target = root / target
        self.directory = target.resolve() / "next-lang-reference-results"
        self.directory.mkdir(parents=True, exist_ok=True)
        self.reference_hash = hashlib.sha256(reference.read_bytes()).hexdigest()
        clang = subprocess.run(
            ["clang", "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
            text=True,
        )
        if clang.returncode != 0:
            raise RuntimeError(f"cannot identify clang: {clang.stdout.strip()}")
        self.clang_version = clang.stdout
        self.disabled = disabled
        self._lock = threading.Lock()
        self.hits = 0
        self.misses = 0
        self.forced = 0

    def _key(
        self,
        root: Path,
        package: str,
        env: dict[str, str],
        level: int,
        invocation: dict[str, object],
    ) -> tuple[str, dict[str, object]]:
        digest = hashlib.sha256()
        package_path = root / package
        if not package_path.is_dir():
            raise Mismatch(f"reference package is missing: {package}")
        for path in sorted(package_path.rglob("*"), key=lambda item: item.relative_to(package_path).as_posix()):
            if path.is_symlink():
                relative = path.relative_to(package_path).as_posix().encode()
                target = os.readlink(path).encode()
                digest.update(b"symlink\0" + len(relative).to_bytes(8, "little") + relative)
                digest.update(len(target).to_bytes(8, "little") + target)
                if path.is_file():
                    content = path.read_bytes()
                    digest.update(b"file\0" + len(content).to_bytes(8, "little") + content)
            elif path.is_file():
                relative = path.relative_to(package_path).as_posix().encode()
                content = path.read_bytes()
                digest.update(b"file\0" + len(relative).to_bytes(8, "little") + relative)
                digest.update(len(content).to_bytes(8, "little") + content)

        environment_hash = hashlib.sha256(
            json.dumps(sorted(env.items()), separators=(",", ":")).encode()
        ).hexdigest()
        invocation_hash = hashlib.sha256(
            json.dumps(invocation, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()
        environment = sorted(env.items())
        inputs = {
            "version": self.VERSION,
            "stage0_nlc_sha256": self.reference_hash,
            "package": package,
            "package_files_sha256": digest.hexdigest(),
            "optimization_level": level,
            "environment": environment,
            "invocation": invocation,
            "clang_version": self.clang_version,
        }
        encoded = json.dumps(inputs, sort_keys=True, separators=(",", ":")).encode()
        key_inputs = {
            "stage0_nlc_sha256": self.reference_hash,
            "package_files_sha256": digest.hexdigest(),
            "optimization_level": str(level),
            "environment_sha256": environment_hash,
            "invocation_sha256": invocation_hash,
            "clang_version_sha256": hashlib.sha256(self.clang_version.encode()).hexdigest(),
            "environment_variable_hashes": {
                name: hashlib.sha256(value.encode()).hexdigest() for name, value in environment
            },
        }
        return hashlib.sha256(encoded).hexdigest(), key_inputs

    def get_or_run(
        self,
        root: Path,
        package: str,
        env: dict[str, str],
        level: int,
        invocation: dict[str, object],
        run: Callable[[], Result],
    ) -> Result:
        key, key_inputs = self._key(root, package, env, level, invocation)
        entry = self.directory / f"{key}.json"
        if not self.disabled:
            result = self._read(entry, key, package)
            if result is not None:
                with self._lock:
                    self.hits += 1
                return result
            with self._lock:
                self.misses += 1
        else:
            with self._lock:
                self.forced += 1

        result = run()
        normalized = Result(
            status=result.status,
            stdout=normalize_bytes(result.stdout, root, package),
            stderr=normalize_bytes(result.stderr, root, package),
            build_status=result.build_status,
        )
        self._write(entry, key, package, key_inputs, normalized)
        return normalized

    def _read(self, entry: Path, key: str, package: str) -> Result | None:
        try:
            payload = json.loads(entry.read_text())
            if (
                payload.get("version") != self.VERSION
                or payload.get("key") != key
                or payload.get("package") != package
            ):
                return None
            result = payload["result"]
            return Result(
                status=int(result["status"]),
                stdout=base64.b64decode(result["stdout"], validate=True),
                stderr=base64.b64decode(result["stderr"], validate=True),
                build_status=(
                    None if result["build_status"] is None else int(result["build_status"])
                ),
            )
        except (
            OSError,
            ValueError,
            TypeError,
            KeyError,
            AttributeError,
            IndexError,
            binascii.Error,
            json.JSONDecodeError,
        ):
            return None

    def _write(
        self,
        entry: Path,
        key: str,
        package: str,
        key_inputs: dict[str, object],
        result: Result,
    ) -> None:
        payload = {
            "version": self.VERSION,
            "key": key,
            "package": package,
            "key_inputs": key_inputs,
            "result": {
                "status": result.status,
                "stdout": base64.b64encode(result.stdout).decode("ascii"),
                "stderr": base64.b64encode(result.stderr).decode("ascii"),
                "build_status": result.build_status,
            },
        }
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{key}.", suffix=".tmp", dir=self.directory
        )
        temporary = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                json.dump(payload, output, sort_keys=True, separators=(",", ":"))
                output.flush()
                os.fsync(output.fileno())
            # Replacing a single file is atomic, including when another worker
            # or suite publishes the same key at the same time.
            os.replace(temporary, entry)
        finally:
            temporary.unlink(missing_ok=True)

    def summary(self) -> str:
        with self._lock:
            return (
                f"stage-0 reference cache: hits={self.hits} misses={self.misses} "
                f"forced-fresh={self.forced} directory={self.directory}"
            )


def status_code(code: int | None) -> int:
    return code if code is not None and code >= 0 else 128


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument(
        "--no-reference-cache",
        action="store_true",
        help="run stage-zero nlc afresh instead of reading cached reference results",
    )
    add_filter_arguments(parser)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    reference = args.reference.resolve()
    if not reference.is_file() or not os.access(reference, os.X_OK):
        print(f"reference nlc is not executable: {reference}", file=sys.stderr)
        return 2

    env = os.environ.copy()
    env.pop("NLC_TEST_INDEX", None)
    # The tool runner assigns this a new value per command; it is not a test
    # input and would defeat reuse of otherwise identical reference results.
    env.pop("CODEX_TOOL_CALL_ID", None)
    env["NLC_FRONTEND"] = "rust"
    env.setdefault("CARGO_TARGET_DIR", str(Path.home() / ".cache/next-lang/target"))
    parity_mode = os.environ.get("NLC_STAGE0_PARITY") == "1"
    long_tests = os.environ.get("NLC_LONG_TESTS") == "1"
    if parity_mode and not long_tests:
        print("NLC_STAGE0_PARITY=1 requires NLC_LONG_TESTS=1", file=sys.stderr)
        return 2
    reference_cache = ReferenceResultCache(
        root,
        reference,
        env,
        disabled=args.no_reference_cache or parity_mode,
    )
    jobs = worker_count()

    # E3a1 begin: include its directed fixtures and retire the C comparison leg.
    levels = (1, 3) if long_tests else (1,)
    runtimes = ("core",)
    table = root / "tests/e1/classification.tsv"
    classifications = read_classifications(table, root)
    discovered = {
        path.relative_to(root).as_posix()
        for base in (root / "tests/run", root / "tests/test", root / "tests/e1", root / "tests/e2", root / "tests/e3")
        for path in base.iterdir()
        if path.is_dir()
    }
    if discovered != set(classifications):
        missing = sorted(discovered - set(classifications))
        extra = sorted(set(classifications) - discovered)
        print(f"classification table does not match package directories; missing={missing}, extra={extra}", file=sys.stderr)
        return 1
    changed = changed_paths(root, args.changed)
    all_packages = list(classifications)
    packages = select_packages(
        all_packages, classifications, args.only, args.package_class, changed
    )
    # E3a1 end

    work = Path(tempfile.mkdtemp(prefix=".selfhost-build-compare-", dir=root))
    try:
        cached_build = subprocess.run(
            [sys.executable, str(root / "scripts/build-selfhost-cached.py"), "--reference", str(reference)],
            cwd=root,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            text=True,
        )
        if cached_build.returncode != 0:
            sys.stderr.write(cached_build.stderr)
            print("could not build the stage-zero selfhost compiler", file=sys.stderr)
            return 1
        stage0 = Path(cached_build.stdout.strip())
        if not stage0.is_file():
            print(f"cached stage-zero selfhost compiler is missing: {stage0}", file=sys.stderr)
            return 1

        ir_bound_sizes = check_struct_helper_ir_bound(stage0, root, env, work)
        print(
            "selfhost IR bound: "
            f"depth 20 = {ir_bound_sizes[20]} bytes; "
            f"depth 40 = {ir_bound_sizes[40]} bytes; "
            "linear-growth check passed"
        )
        enum_scaling = check_enum_constructor_scaling(stage0, root, env, work)
        print(
            "enum constructor scaling: "
            + "; ".join(f"{size} enums = {seconds:.3f}s" for size, seconds in enum_scaling.items())
            + "; sub-quadratic growth check passed"
        )

        counts = {
            level: {kind: 0 for kind in ("build", "diagnose", "rejects", "unsupported", "mismatches")}
            for level in levels
        }
        generated_cases = []
        if parity_mode and long_tests:
            generated_count = int(os.environ.get("NLC_E1_GENERATED_COUNT", "8"))
            generated_cases = generate_seeded_cases(root, work, generated_count)
        generated_classes = dict(generated_cases)
        selected_generated = set(
            select_packages(
                [package for package, _ in generated_cases],
                generated_classes,
                args.only,
                args.package_class,
                changed,
            )
        )
        generated_cases = [
            (package, kind) for package, kind in generated_cases if package in selected_generated
        ]
        generated_counts = {
            level: {kind: 0 for kind in ("build", "diagnose", "mismatches")}
            for level in levels
        }

        # Backend and optimization comparisons reuse one Rust result per
        # package. The reference build is always made at the default O1 level.
        reference_env = env.copy()
        reference_env["NLC_OPT_LEVEL"] = "1"
        reference_results: dict[str, Result | Exception] = {}

        def reference_for(package: str, package_work: Path) -> Result:
            if package not in reference_results:
                try:
                    reference_results[package] = run_reference(
                        reference,
                        root,
                        package,
                        reference_env,
                        package_work,
                        1,
                        reference_cache,
                    )
                except (Mismatch, subprocess.TimeoutExpired, OSError) as error:
                    reference_results[package] = error
            result = reference_results[package]
            if isinstance(result, Exception):
                raise result
            return result

        test_main_reference: Result | None = None
        test_main_reference_error: Exception | None = None

        def reference_test_main(package_work: Path) -> Result:
            nonlocal test_main_reference, test_main_reference_error
            if test_main_reference is None and test_main_reference_error is None:
                try:
                    test_main_reference = build_reference_main(
                        reference,
                        root,
                        "tests/test/harness",
                        reference_env,
                        package_work,
                        reference_cache,
                    )
                except (Mismatch, subprocess.TimeoutExpired, OSError) as error:
                    test_main_reference_error = error
            if test_main_reference_error is not None:
                raise test_main_reference_error
            assert test_main_reference is not None
            return test_main_reference

        def check_classified_package(
            package: str, kind: str, run_env: dict[str, str], package_work: Path, level: int
        ) -> None:
            reference_result = reference_for(package, package_work)
            expected = expected_result(root, package)
            if normalize_result(reference_result, root, package) != expected:
                raise Mismatch("Rust reference differs from checked-in expected.* files")

            if kind == "build":
                if reference_result.build_status != 0:
                    raise Mismatch(
                        f"misclassified build: Rust compile status {reference_result.build_status}",
                        reference_result,
                    )
                for runtime in runtimes:
                    self_result, wrote_ir = run_selfhost(
                        stage0, reference, root, package, run_env, package_work, level, runtime
                    )
                    if not wrote_ir:
                        raise Mismatch(
                            f"selfhosted {runtime}-runtime comparison leg rejected a build package",
                            reference_result,
                            self_result,
                        )
                    if not same_normalized_result(self_result, reference_result, root, package):
                        raise Mismatch(
                            f"built program or {runtime}-runtime test runner differs from Rust nlc",
                            reference_result,
                            self_result,
                        )
            elif kind == "diagnose":
                manifest_tool_failure = (
                    reference_result.status == 3
                    and expected[0] == 3
                    and (root / package / "package.toml").is_file()
                )
                if reference_result.status != 2 and not manifest_tool_failure:
                    raise Mismatch(
                        f"misclassified diagnose: Rust status {reference_result.status}", reference_result
                    )
                self_result, wrote_ir = run_selfhost(
                    stage0, reference, root, package, run_env, package_work, level
                )
                if wrote_ir:
                    raise Mismatch(
                        "selfhosted compiler wrote IR after a rejection", reference_result, self_result
                    )
                if not same_rejection(self_result, reference_result) and not (
                    manifest_tool_failure
                    and same_normalized_result(self_result, reference_result, root, package)
                ):
                    raise Mismatch(
                        "selfhost did not reject with an error like Rust nlc", reference_result, self_result
                    )
                expected_selfhost = root / package / "expected.selfhost.stderr"
                if expected_selfhost.is_file() and self_result.stderr != expected_selfhost.read_bytes():
                    raise Mismatch(
                        "selfhost diagnostic differs from its explicit oracle", reference_result, self_result
                    )
            elif kind == "rejects":
                if reference_result.build_status != 0:
                    raise Mismatch(
                        f"misclassified rejects: Rust compile status {reference_result.build_status}",
                        reference_result,
                    )
                self_result, wrote_ir = run_selfhost(
                    stage0, reference, root, package, run_env, package_work, level
                )
                if wrote_ir:
                    raise Mismatch(
                        "selfhosted compiler wrote IR for a shadowing package", reference_result, self_result
                    )
                if not is_real_rejection(self_result):
                    raise Mismatch(
                        "selfhost did not reject the shadowing package with status 2 and real error text",
                        reference_result,
                        self_result,
                    )
            else:
                self_result, wrote_ir = run_selfhost(
                    stage0, reference, root, package, run_env, package_work, level
                )
                if wrote_ir:
                    raise Mismatch("unsupported package produced an IR artifact", reference_result, self_result)
                if not is_unsupported(self_result):
                    raise Mismatch(
                        "unsupported package did not get the exact unsupported diagnostic",
                        reference_result,
                        self_result,
                    )
                expected_selfhost = root / package / "expected.selfhost.stderr"
                if expected_selfhost.is_file() and self_result.stderr != expected_selfhost.read_bytes():
                    raise Mismatch(
                        "selfhost unsupported diagnostic differs from its explicit oracle",
                        reference_result,
                        self_result,
                    )

            if package == "tests/test/harness" and kind == "build":
                compare_test_package_main(
                    stage0,
                    reference,
                    root,
                    package,
                    run_env,
                    package_work,
                    level,
                    runtimes,
                    reference_test_main(package_work),
                )

        def check_generated_package(
            package: str, kind: str, run_env: dict[str, str], package_work: Path, level: int
        ) -> None:
            reference_result = reference_for(package, package_work)
            if kind == "build":
                if reference_result.build_status != 0:
                    raise Mismatch("seeded build did not compile with Rust nlc", reference_result)
                for runtime in runtimes:
                    self_result, wrote_ir = run_selfhost(
                        stage0, reference, root, package, run_env, package_work, level, runtime
                    )
                    if not wrote_ir:
                        raise Mismatch(
                            f"selfhost rejected a seeded valid package in its {runtime}-runtime leg",
                            reference_result,
                            self_result,
                        )
                    if not same_normalized_result(reference_result, self_result, root, package):
                        raise Mismatch(
                            f"seeded {runtime}-runtime build differs from Rust nlc",
                            reference_result,
                            self_result,
                        )
            else:
                if reference_result.status not in (2, 3):
                    raise Mismatch("seeded diagnostic did not diagnose with Rust nlc", reference_result)
                self_result, wrote_ir = run_selfhost(
                    stage0, reference, root, package, run_env, package_work, level
                )
                if wrote_ir:
                    raise Mismatch("selfhost wrote IR for a seeded diagnostic", reference_result, self_result)
                if not same_rejection(self_result, reference_result):
                    raise Mismatch(
                        "seeded diagnostic: selfhost did not reject with an error",
                        reference_result,
                        self_result,
                    )

        def check_in_workers(
            tasks: list[tuple[str, str, bool]], run_env: dict[str, str], level: int
        ) -> list[tuple[int, tuple[str, str, bool], Exception | None]]:
            if not tasks:
                return []
            worker_total = min(jobs, len(tasks))
            groups: list[list[tuple[int, tuple[str, str, bool]]]] = [
                [] for _ in range(worker_total)
            ]
            for index, task in enumerate(tasks):
                groups[index % worker_total].append((index, task))

            def run_group(
                worker_index: int, group: list[tuple[int, tuple[str, str, bool]]]
            ) -> list[tuple[int, tuple[str, str, bool], Exception | None]]:
                worker_work = work / f"worker-{worker_index}"
                worker_work.mkdir(exist_ok=True)
                results = []
                for index, task in group:
                    package, kind, generated = task
                    try:
                        check = check_generated_package if generated else check_classified_package
                        check(package, kind, run_env, worker_work, level)
                        error = None
                    except (Mismatch, subprocess.TimeoutExpired, OSError) as caught:
                        error = caught
                    results.append((index, task, error))
                return results

            with ThreadPoolExecutor(max_workers=worker_total) as pool:
                grouped_results = list(
                    pool.map(lambda args: run_group(*args), enumerate(groups))
                )
            return sorted(
                (result for group in grouped_results for result in group), key=lambda item: item[0]
            )

        first_diff_reported = False
        for level in levels:
            run_env = env.copy()
            run_env["NLC_OPT_LEVEL"] = str(level)
            tasks = [(package, kind, False) for package, kind in classifications.items() if package in packages]
            tasks.extend((package, kind, True) for package, kind in generated_cases)
            results = check_in_workers(tasks, run_env, level)
            for _, (package, kind, generated), error in results:
                tally = generated_counts[level] if generated else counts[level]
                if error is None:
                    tally[kind] += 1
                    continue
                tally["mismatches"] += 1
                label = "seeded " if generated else ""
                print(f"[{label}{package} O{level}] {error}", file=sys.stderr)
                if isinstance(error, Mismatch) and error.reference is not None:
                    print("  Rust:", brief(error.reference), file=sys.stderr)
                if isinstance(error, Mismatch) and error.selfhost is not None:
                    print("  selfhost:", brief(error.selfhost), file=sys.stderr)
                if not first_diff_reported and isinstance(error, Mismatch):
                    if error.reference is not None and error.selfhost is not None:
                        for label, left, right in (
                            ("stdout", error.reference.stdout, error.selfhost.stdout),
                            ("stderr", error.reference.stderr, error.selfhost.stderr),
                        ):
                            if left != right:
                                print(f"  first mismatch diff ({label}):", file=sys.stderr)
                                diff = difflib.unified_diff(
                                    left.decode("utf-8", "replace").splitlines(keepends=True),
                                    right.decode("utf-8", "replace").splitlines(keepends=True),
                                    fromfile="Rust",
                                    tofile="selfhost",
                                )
                                for line_index, line in enumerate(diff):
                                    if line_index >= 160:
                                        print("  ... diff truncated ...", file=sys.stderr)
                                        break
                                    sys.stderr.write("  " + line)
                                break
                    first_diff_reported = True

            print(
                f"O{level}: built and matching {counts[level]['build']}; "
                f"diagnosed and matching {counts[level]['diagnose']}; "
                f"rejected by new name rule {counts[level]['rejects']}; "
                f"unsupported {counts[level]['unsupported']}; "
                f"mismatches {counts[level]['mismatches']}; "
                f"seeded builds {generated_counts[level]['build']}; "
                f"seeded diagnostics {generated_counts[level]['diagnose']}; "
                f"seeded mismatches {generated_counts[level]['mismatches']}"
            )

        mismatches = sum(counts[level]["mismatches"] + generated_counts[level]["mismatches"] for level in counts)
        print(
            f"selfhost build comparison: packages={len(packages)} seeded={len(generated_cases)} "
            f"levels={len(levels)} workers={min(jobs, len(packages) + len(generated_cases))} "
            f"mismatches={mismatches} ({filter_label(args.only, args.package_class, args.changed)})"
        )
        return 1 if mismatches else 0
    finally:
        print(reference_cache.summary())
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
        if len(parts) != 2 or parts[0] not in ("build", "diagnose", "rejects", "unsupported"):
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


def check_struct_helper_ir_bound(stage0: Path, root: Path, env: dict[str, str], work: Path) -> dict[int, int]:
    """Compile two shared struct chains using only selfhost and check IR growth."""
    bound_root = work / "struct-helper-ir-bound"
    bound_root.mkdir()
    sizes: dict[int, int] = {}
    for depth in (20, 40):
        package = bound_root / f"depth-{depth}"
        package.mkdir()
        lines = ["struct S0 { value: int }" ]
        for level in range(1, depth + 1):
            lines.append(f"struct S{level} {{ child: S{level - 1} }}")
        lines.append("fn make0() -> S0 { S0 { value: 1 } }")
        for level in range(1, depth + 1):
            lines.append(f"fn make{level}() -> S{level} {{ S{level} {{ child: make{level - 1}() }} }}")
        lines.append(f"fn main() {{ let value = make{depth}(); print(value); if value == value {{}} }}")
        source = "\n".join(lines) + "\n"
        source_path = package / "main.nl"
        source_path.write_text(source)
        package_arg = package.relative_to(root).as_posix()
        ir_path = bound_root / f"depth-{depth}.ll"
        result = invoke(
            [str(stage0), "build", package_arg, "-o", ir_path.relative_to(root).as_posix()],
            cwd=root,
            env=env,
            timeout=90,
        )
        if result.status != 0 or not ir_path.is_file():
            raise Mismatch(
                f"selfhost rejected the depth-{depth} IR-bound package: "
                f"status={result.status}, stderr={result.stderr[:500]!r}"
            )
        ir_size = ir_path.stat().st_size
        sizes[depth] = ir_size
        token_count = len(re.findall(r"[A-Za-z_][A-Za-z0-9_]*|[0-9]+L?|[^\s]", source))
        node_bound = token_count * 2 + 8
        table_entries = (depth + 1) * 2
        derived_bound = 640 * node_bound + 256 * table_entries + len(source.encode()) + 8 * 1024 * 1024
        if ir_size > derived_bound:
            raise Mismatch(
                f"depth-{depth} generated {ir_size} IR bytes above its derived bound {derived_bound}"
            )
    if sizes[40] > 2 * sizes[20] + 16384:
        raise Mismatch(
            f"struct helper IR growth is not linear: depth20={sizes[20]}, depth40={sizes[40]}"
        )
    return sizes


def check_enum_constructor_scaling(
    stage0: Path, root: Path, env: dict[str, str], work: Path
) -> dict[int, float]:
    """Measure resolved constructor lookup over growing enum tables."""
    scale_root = work / "enum-constructor-scaling"
    scale_root.mkdir()
    timings: dict[int, float] = {}
    previous_per_enum = 0.0
    for size in (1600, 3200, 6400):
        package = scale_root / f"enums-{size}"
        package.mkdir()
        lines = [f"enum E{index} {{ Case{index}(int) }}" for index in range(size)]
        lines.append("fn main() {")
        lines.extend(f"    print(E{index}.Case{index}({index}))" for index in range(size))
        lines.append("}")
        (package / "main.nl").write_text("\n".join(lines) + "\n")
        ir_path = scale_root / f"enums-{size}.ll"
        samples: list[float] = []
        for _ in range(3):
            started = time.perf_counter()
            result = invoke(
                [str(stage0), "build", package.relative_to(root).as_posix(), "-o", ir_path.relative_to(root).as_posix()],
                cwd=root,
                env=env,
                timeout=180,
            )
            samples.append(time.perf_counter() - started)
            if result.status != 0 or not ir_path.is_file():
                raise Mismatch(
                    f"selfhost rejected the {size}-enum scaling package: "
                    f"status={result.status}, stderr={result.stderr[:500]!r}"
                )
        elapsed = statistics.median(samples)
        timings[size] = elapsed
        per_enum = elapsed / size
        if previous_per_enum and per_enum > previous_per_enum * 1.75:
            raise Mismatch(
                "enum constructor lookup exceeded the linear per-enum growth bound: "
                f"{size} enums={elapsed:.3f}s, {per_enum:.6f}s/enum"
            )
        previous_per_enum = per_enum
    return timings


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
    return (
        package.startswith("tests/test/")
        or package.startswith("tests/e1/test_")
        or package.startswith("tests/e2/test_")
    )


def run_reference(
    reference: Path,
    root: Path,
    package: str,
    env: dict[str, str],
    work: Path,
    level: int,
    cache: ReferenceResultCache,
) -> Result:
    cwd, package_arg, local = package_cwd(root, package)
    if is_test_package(package):
        commands = [["--frontend=rust", "test", package_arg]]
    else:
        commands = [
            ["--frontend=rust", "build", package_arg, "-o", "<output>"],
            ["<output>"],
        ]
    invocation: dict[str, object] = {
        "cwd": cwd.relative_to(root).as_posix() or ".",
        "commands": commands,
        "stdin": None,
    }
    return cache.get_or_run(
        root,
        package,
        env,
        level,
        invocation,
        lambda: run_reference_uncached(reference, root, package, env, work, level),
    )


def run_reference_uncached(
    reference: Path, root: Path, package: str, env: dict[str, str], work: Path, level: int
) -> Result:
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
        built.build_status = built.status
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
    runtime: str = "core",
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
    command.append(f"--runtime={runtime}")
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


def build_reference_main(
    reference: Path,
    root: Path,
    package: str,
    env: dict[str, str],
    work: Path,
    cache: ReferenceResultCache,
) -> Result:
    invocation: dict[str, object] = {
        "cwd": ".",
        "commands": [
            ["--frontend=rust", "build", package, "-o", "<output>"],
            ["<output>"],
        ],
        "stdin": None,
    }
    result = cache.get_or_run(
        root,
        package,
        env,
        1,
        invocation,
        lambda: build_reference_main_uncached(reference, root, package, env, work),
    )
    if result.build_status != 0:
        raise Mismatch("could not build Rust reference main for the test harness", result)
    return result


def build_reference_main_uncached(
    reference: Path, root: Path, package: str, env: dict[str, str], work: Path
) -> Result:
    exe = work / f"reference-main-{os.getpid()}"
    build = invoke(
        [str(reference), "--frontend=rust", "build", package, "-o", str(exe)],
        cwd=root,
        env=env,
    )
    if build.status != 0:
        build.build_status = build.status
        return build
    try:
        result = invoke([str(exe)], cwd=root, env=env)
        result.build_status = 0
        return result
    finally:
        exe.unlink(missing_ok=True)


def compare_test_package_main(
    stage0: Path,
    reference: Path,
    root: Path,
    package: str,
    env: dict[str, str],
    work: Path,
    level: int,
    runtimes: tuple[str, ...],
    reference_result: Result,
) -> None:
    suffix = f"{os.getpid()}-{level}-main"
    ir = work / f"self-main-{suffix}.ll"
    self_exe = work / f"self-main-{suffix}"
    for runtime in runtimes:
        command = [str(stage0), "build", package, "-o", ir.relative_to(root).as_posix(), f"--runtime={runtime}"]
        built = invoke(command, cwd=root, env=env)
        if built.status != 0:
            raise Mismatch(f"test package {runtime} runtime build was rejected", reference_result, built)
        linked = invoke([str(reference), "link-ir", str(ir), "-o", str(self_exe)], cwd=root, env=env)
        ir.unlink(missing_ok=True)
        actual = linked if linked.status != 0 else invoke([str(self_exe)], cwd=root, env=env)
        self_exe.unlink(missing_ok=True)
        if not same_normalized_result(actual, reference_result, root, package):
            raise Mismatch(
                f"test package {runtime} runtime main differs from Rust nlc",
                reference_result,
                actual,
            )


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


def same_normalized_result(left: Result, right: Result, root: Path, package: str) -> bool:
    return normalize_result(left, root, package) == normalize_result(right, root, package)


def same_rejection(selfhost: Result, reference: Result) -> bool:
    """A rejected package passes when the self-hosted compiler also rejects it
    with the same status and real error text. Which error comes first and its
    exact wording need not match stage 0 (Ben, 2026-10-26); an "unsupported"
    rejection doesn't count, since that means the construct isn't built yet."""
    return (
        selfhost.status == reference.status
        and selfhost.stdout == b""
        and b"error" in selfhost.stderr
        and b"not supported by the self-hosted compiler yet" not in selfhost.stderr
    )


def is_real_rejection(result: Result) -> bool:
    return (
        result.status == 2
        and result.stdout == b""
        and b"error" in result.stderr
        and b"not supported by the self-hosted compiler yet" not in result.stderr
    )


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
