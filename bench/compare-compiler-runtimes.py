#!/usr/bin/env python3
"""Compare LangArena, Osprey, and paired-program runtimes across nlc stages.

Run this under Linux or WSL. Each Next program is compiled to LLVM IR by the
Rust API helper or one of the supplied nlc stages, linked with the same Clang
and runtime/nl_runtime.c, checked against its byte-exact oracle, then timed.
The JSON report and command logs are written beneath a fresh repository-relative
output directory so a run can be inspected while it is still in progress.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time
from typing import Any

try:
    import fcntl
except ImportError:  # Keep --help and --py_compile usable outside Linux/WSL.
    fcntl = None


ROOT = pathlib.Path(__file__).resolve().parents[1]
LOCK_PATH = pathlib.Path("/home/ben/linuxbench/bench.lock")
STAGES = ("stage0", "stage1", "stage2", "stage3")
STAGE_DESCRIPTIONS = {
    "stage0": "Rust compiler API helper emits LLVM IR (pointer data stack)",
    "stage1": "self-hosted compiler built by the Rust Stage 0 compiler",
    "stage2": "self-hosted compiler built by Stage 1",
    "stage3": "self-hosted compiler built by Stage 2",
}
RUST_FLAGS = (
    "--edition",
    "2021",
    "-C",
    "opt-level=3",
    "-C",
    "codegen-units=1",
    "-C",
    "lto=fat",
    "-C",
    "panic=abort",
    "-C",
    "strip=symbols",
)
TIME_FORMAT = "%U %S %M %e"
LOG_PREVIEW_BYTES = 4000


class RunnerError(RuntimeError):
    pass


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def artifact(path: pathlib.Path) -> dict[str, Any]:
    return {
        "path": str(path.resolve()),
        "size_bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def hash_tree(paths: list[pathlib.Path]) -> str:
    """Hash named files in a stable order, including names and lengths."""
    digest = hashlib.sha256()
    files: list[tuple[str, pathlib.Path]] = []
    for item in paths:
        if item.is_dir():
            files.extend(
                (child.relative_to(ROOT).as_posix(), child)
                for child in item.rglob("*")
                if child.is_file() and not child.is_symlink()
            )
        elif item.is_file():
            files.append((item.relative_to(ROOT).as_posix(), item))
    for relative, path in sorted(files):
        name = relative.encode("utf-8")
        content = path.read_bytes()
        digest.update(len(name).to_bytes(8, "little"))
        digest.update(name)
        digest.update(len(content).to_bytes(8, "little"))
        digest.update(content)
    return digest.hexdigest()


def clean_environment(extra: dict[str, str] | None = None) -> dict[str, str]:
    """Remove ambient compiler controls so every stage sees a known environment."""
    environment = os.environ.copy()
    for name in tuple(environment):
        if name.startswith("NLC_"):
            environment.pop(name, None)
    environment["LC_ALL"] = "C"
    environment["LANG"] = "C"
    if extra:
        environment.update(extra)
    return environment


def decode_preview(value: bytes) -> str:
    decoded = value[:LOG_PREVIEW_BYTES].decode("utf-8", "replace")
    if len(value) > LOG_PREVIEW_BYTES:
        decoded += f"\n… ({len(value) - LOG_PREVIEW_BYTES} more bytes in the full log)"
    return decoded


def resolve_tool(value: str, label: str) -> pathlib.Path:
    candidate = pathlib.Path(value).expanduser()
    if not candidate.is_absolute():
        candidate = ROOT / candidate
    if not candidate.is_file():
        found = shutil.which(value)
        if found:
            candidate = pathlib.Path(found)
    if not candidate.is_file():
        raise RunnerError(f"{label} was not found: {value}")
    # Keep the invoked path intact. In particular, `rustc` is often a rustup
    # proxy whose behavior depends on argv[0]; resolving its symlink invokes
    # `rustup` directly and changes the accepted command-line interface.
    return pathlib.Path(os.path.abspath(candidate))


def checked_output_dir(value: str) -> pathlib.Path:
    requested = pathlib.Path(value).expanduser()
    if requested.is_absolute():
        raise RunnerError("--output-dir must be repository-relative")
    output = (ROOT / requested).resolve()
    try:
        output.relative_to(ROOT.resolve())
    except ValueError as error:
        raise RunnerError("--output-dir must stay inside the repository") from error
    if output == ROOT.resolve():
        raise RunnerError("--output-dir cannot be the repository root")
    for suite in ("langarena", "osprey", "vs-rust"):
        suite_root = (ROOT / "bench" / suite).resolve()
        if output == suite_root or suite_root in output.parents:
            raise RunnerError("--output-dir cannot be inside a benchmark input directory")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise RunnerError(f"--output-dir must be a new or empty directory: {output}")
    output.mkdir(parents=True, exist_ok=True)
    return output


def atomic_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def write_bytes(path: pathlib.Path, value: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(value)


def append_failure(
    report: dict[str, Any],
    *,
    suite: str,
    case: str,
    stage: str,
    phase: str,
    message: str,
    command_id: str | None = None,
) -> None:
    failure: dict[str, Any] = {
        "suite": suite,
        "case": case,
        "stage": stage,
        "phase": phase,
        "message": message,
    }
    if command_id is not None:
        failure["command_id"] = command_id
    report["failures"].append(failure)


def make_runner(output: pathlib.Path, timeout: int, cpu: int):
    report_path = output / "report.json"
    command_counter = 0

    def checkpoint(report: dict[str, Any]) -> None:
        atomic_json(report_path, report)

    def run_command(
        report: dict[str, Any],
        *,
        label: str,
        argv: list[str],
        cwd: pathlib.Path,
        environment: dict[str, str],
        timed: bool = False,
        timeout_seconds: int | None = None,
    ) -> dict[str, Any]:
        nonlocal command_counter
        command_counter += 1
        safe_label = re.sub(r"[^A-Za-z0-9_.-]+", "_", label).strip("_") or "command"
        command_id = f"{command_counter:05d}-{safe_label}"
        logs = output / "logs"
        stdout_path = logs / f"{command_id}.stdout"
        stderr_path = logs / f"{command_id}.stderr"
        time_path = logs / f"{command_id}.time"
        command = list(argv)
        if timed:
            command = [
                "taskset",
                "-c",
                str(cpu),
                "/usr/bin/time",
                "-f",
                TIME_FORMAT,
                "-o",
                str(time_path),
                "--",
                *command,
            ]
        command_record: dict[str, Any] = {
            "id": command_id,
            "label": label,
            "command": command,
            "cwd": str(cwd.resolve()),
            "timeout_seconds": timeout_seconds or timeout,
            "pinned_cpu": cpu if timed else None,
            "stdout_log": stdout_path.relative_to(output).as_posix(),
            "stderr_log": stderr_path.relative_to(output).as_posix(),
        }
        report["commands"].append(command_record)
        checkpoint(report)
        started = time.perf_counter_ns()
        timed_out = False
        stdout = b""
        stderr = b""
        returncode: int | None
        process: subprocess.Popen[bytes] | None = None
        try:
            process = subprocess.Popen(
                command,
                cwd=cwd,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
            try:
                stdout, stderr = process.communicate(timeout=command_record["timeout_seconds"])
                returncode = process.returncode
            except subprocess.TimeoutExpired:
                timed_out = True
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                stdout, stderr = process.communicate()
                returncode = None
        except OSError as error:
            stderr = str(error).encode("utf-8", "replace")
            returncode = None
        wall_ns = time.perf_counter_ns() - started
        write_bytes(stdout_path, stdout)
        write_bytes(stderr_path, stderr)
        command_record.update(
            {
                "returncode": returncode,
                "timed_out": timed_out,
                "wall_nanoseconds": wall_ns,
                "wall_seconds": wall_ns / 1_000_000_000,
                "stdout_sha256": sha256_bytes(stdout),
                "stderr_sha256": sha256_bytes(stderr),
                "stdout_preview": decode_preview(stdout),
                "stderr_preview": decode_preview(stderr),
            }
        )
        if timed:
            command_record["time_log"] = time_path.relative_to(output).as_posix()
            try:
                fields = time_path.read_text(encoding="ascii").split()
                if len(fields) != 4:
                    raise ValueError(f"expected four fields, found {len(fields)}")
                command_record["process_metrics"] = {
                    "user_seconds": float(fields[0]),
                    "system_seconds": float(fields[1]),
                    "peak_rss_kib": int(fields[2]),
                    "time_wall_seconds": float(fields[3]),
                }
            except (OSError, ValueError) as error:
                command_record["process_metrics_error"] = str(error)
        checkpoint(report)
        return command_record

    return run_command, checkpoint


def langarena_inventory() -> tuple[list[dict[str, Any]], dict[str, Any], dict[str, dict[str, Any]]]:
    suite_root = ROOT / "bench" / "langarena"
    params_by_mode: dict[str, dict[str, Any]] = {}
    for mode in ("test", "run"):
        path = suite_root / ("test.js" if mode == "test" else "run.js")
        values = json.loads(path.read_text(encoding="utf-8"))
        params_by_mode[mode] = {entry["name"]: entry for entry in values}

    packages: list[dict[str, Any]] = []
    present_official: set[str] = set()
    groups: dict[str, int] = {}
    for directory in sorted(suite_root.iterdir()):
        if not directory.is_dir() or not (directory / "name").is_file():
            continue
        name = (directory / "name").read_text(encoding="utf-8").strip()
        status = (directory / "status").read_text(encoding="utf-8").strip() if (directory / "status").is_file() else "ready"
        audit = (directory / "audit").read_text(encoding="utf-8").strip() if (directory / "audit").is_file() else ""
        if status.startswith("pending-"):
            group = "pending"
        elif status.startswith("variant-"):
            group = "variants"
        elif status.startswith("not-comparable"):
            group = "not_comparable"
        elif audit.startswith("closest-possible:"):
            group = "closest"
        else:
            group = "headline"
        groups[group] = groups.get(group, 0) + 1
        if not status.startswith("variant-"):
            present_official.add(name)
        packages.append(
            {
                "suite": "langarena",
                "id": directory.name,
                "display_name": name,
                "directory": directory,
                "status": status,
                "audit": audit,
                "group": group,
            }
        )

    official_names = set(params_by_mode["run"])
    pending_cases = [
        {"id": package["id"], "display_name": package["display_name"], "reason": package["status"]}
        for package in packages
        if package["status"].startswith("pending-")
    ]
    coverage = {
        "official_name_count": len(official_names),
        "present_official_name_count": len(present_official),
        "missing_official_names": sorted(official_names - present_official),
        "package_directory_count": len(packages),
        "declared_pending_count": len(pending_cases),
        "declared_pending_cases": pending_cases,
        "status_and_audit_groups": groups,
    }
    return packages, coverage, params_by_mode


def discover_packages() -> tuple[dict[str, list[dict[str, Any]]], dict[str, Any], dict[str, Any]]:
    langarena, langarena_coverage, langarena_params = langarena_inventory()
    packages: dict[str, list[dict[str, Any]]] = {"langarena": langarena, "osprey": [], "vs-rust": []}
    for suite, required in (("osprey", "main.nl"), ("vs-rust", "main.nl")):
        suite_root = ROOT / "bench" / suite
        for directory in sorted(suite_root.iterdir()):
            if not directory.is_dir() or not (directory / required).is_file():
                continue
            status = (directory / "status").read_text(encoding="utf-8").strip() if (directory / "status").is_file() else "ready"
            if suite == "osprey":
                display_name = directory.name
                group = "pending" if status.startswith("pending-") else "ready"
            else:
                display_name = directory.name
                group = "ready"
            packages[suite].append(
                {
                    "suite": suite,
                    "id": directory.name,
                    "display_name": display_name,
                    "directory": directory,
                    "status": status,
                    "audit": "",
                    "group": group,
                }
            )
    other_coverage = {
        suite: {
            "package_directory_count": len(packages[suite]),
            "pending_cases": [
                {"id": case["id"], "reason": case["status"]}
                for case in packages[suite]
                if case["status"].startswith("pending-")
            ],
        }
        for suite in ("osprey", "vs-rust")
    }
    return packages, {"langarena": langarena_coverage, **other_coverage}, langarena_params


def select_packages(
    packages: dict[str, list[dict[str, Any]]], suites: list[str], filters: list[str]
) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    matched_filters: set[str] = set()
    for suite in suites:
        for package in packages[suite]:
            if not filters:
                selected.append(package)
                continue
            matched = [
                case_filter
                for case_filter in filters
                if case_filter == package["id"] or case_filter == package["display_name"]
            ]
            if matched:
                selected.append(package)
                matched_filters.update(matched)
    unmatched = [case_filter for case_filter in dict.fromkeys(filters) if case_filter not in matched_filters]
    if unmatched:
        raise RunnerError(
            "unmatched --case filter(s) for selected suites "
            f"{', '.join(suites)}: {', '.join(unmatched)}"
        )
    return selected


def package_expected(
    package: dict[str, Any], mode: str, langarena_params: dict[str, dict[str, Any]]
) -> tuple[bytes | None, list[str], str]:
    directory: pathlib.Path = package["directory"]
    suite = package["suite"]
    if suite == "langarena":
        parameters = langarena_params[mode].get(package["display_name"])
        if parameters is None:
            return None, [], f"LangArena {mode}.js has no entry for {package['display_name']}"
        return f"{parameters['checksum']}\n".encode("ascii"), [mode], "LangArena vendored checksum"
    if suite == "osprey":
        expected_path = directory / "expected.txt"
        if not expected_path.is_file():
            return None, [], "missing expected.txt"
        package_text = (directory / "package.toml").read_text(encoding="utf-8")
        capabilities = re.search(r"(?ms)^\s*capabilities\s*=\s*\[([^\]]*)\]", package_text)
        seeded = bool(capabilities and re.search(r"['\"]env['\"]", capabilities.group(1)))
        return expected_path.read_bytes(), (["0"] if seeded else []), "vendored expected.txt"
    return None, [], "freshly compiled Rust stdout oracle"


def parse_ir_metadata(stage: str, content: bytes) -> dict[str, Any]:
    text = content.decode("utf-8", "replace")
    runtime_lines = re.findall(r"(?m)^; nlc\.runtime\s+(\S+)\s*$", text)
    stack_lines = re.findall(r"(?m)^; nlc\.stack\s+(\S+)\s*$", text)
    if stage == "stage0":
        if runtime_lines and runtime_lines != ["c"]:
            raise RunnerError(f"Stage 0 helper IR declares an unexpected runtime: {runtime_lines!r}")
        if stack_lines and stack_lines != ["pointer"]:
            raise RunnerError(f"Stage 0 helper was required to emit pointer-stack IR; found {stack_lines!r}")
        if b"@nl_context_create" not in content:
            raise RunnerError("Stage 0 IR lacks the C runtime context API symbol @nl_context_create")
        return {
            "runtime": "c",
            "runtime_verification": "Rust API C-runtime ABI; helper output has no runtime marker",
            "runtime_marker": runtime_lines[0] if runtime_lines else None,
            "stack_mode": "pointer",
            "stack_marker": stack_lines[0] if stack_lines else None,
            "stack_mode_source": "NLC_STACK_MODE=pointer; absent Rust-IR marker means pointer mode",
        }
    if runtime_lines != ["c"]:
        raise RunnerError(f"IR must contain exactly one '; nlc.runtime c' marker; found {runtime_lines!r}")
    if len(stack_lines) != 1 or stack_lines[0] not in ("offset", "pointer"):
        raise RunnerError(f"IR must contain one known stack marker; found {stack_lines!r}")
    return {
        "runtime": "c",
        "runtime_verification": "explicit nlc.runtime marker",
        "runtime_marker": runtime_lines[0],
        "stack_mode": stack_lines[0],
        "stack_marker": stack_lines[0],
        "stack_mode_source": "explicit nlc.stack marker",
    }


def timed_command_ok(command: dict[str, Any]) -> tuple[bool, str | None]:
    if command.get("timed_out"):
        return False, "timed out"
    if command.get("returncode") != 0:
        return False, f"exit status {command.get('returncode')}"
    if "process_metrics" not in command:
        return False, f"missing /usr/bin/time metrics: {command.get('process_metrics_error', 'unknown error')}"
    return True, None


def verify_output(
    command: dict[str, Any], expected: bytes, report: dict[str, Any]
) -> tuple[bool, dict[str, Any]]:
    stdout_path = pathlib.Path(report["output_dir"]) / command["stdout_log"]
    actual = stdout_path.read_bytes()
    status_ok = command.get("returncode") == 0 and not command.get("timed_out")
    output_ok = actual == expected
    return status_ok and output_ok, {
        "status_ok": status_ok,
        "output_ok": output_ok,
        "expected_sha256": sha256_bytes(expected),
        "actual_sha256": sha256_bytes(actual),
        "expected_size_bytes": len(expected),
        "actual_size_bytes": len(actual),
        "actual_preview": decode_preview(actual),
    }


def version_probe(
    report: dict[str, Any],
    run_command,
    label: str,
    argv: list[str],
    cwd: pathlib.Path,
    environment: dict[str, str],
) -> str:
    command = run_command(
        report,
        label=label,
        argv=argv,
        cwd=cwd,
        environment=environment,
        timeout_seconds=20,
    )
    text = command["stdout_preview"].strip() or command["stderr_preview"].strip()
    if command.get("returncode") != 0 or command.get("timed_out"):
        report["tool_probe_failures"].append({"label": label, "command_id": command["id"]})
        append_failure(
            report,
            suite="toolchain",
            case="-",
            stage=label,
            phase="version_probe",
            message="tool version probe failed",
            command_id=command["id"],
        )
    return text


def compiler_build_command(stage: str, compiler: pathlib.Path, package: pathlib.Path, ir: pathlib.Path) -> list[str]:
    package_arg = package.resolve().relative_to(ROOT.resolve()).as_posix()
    ir_arg = ir.resolve().relative_to(ROOT.resolve()).as_posix()
    if stage == "stage0":
        return [str(compiler), package_arg, ir_arg]
    return [str(compiler), "build", package_arg, "-o", ir_arg, "--runtime=c"]


def compiler_environment(stage: str) -> dict[str, str]:
    if stage == "stage0":
        return clean_environment({"NLC_STACK_MODE": "pointer", "NLC_OPT_LEVEL": "3"})
    return clean_environment()


def compile_rust_reference(
    package: dict[str, Any],
    case_result: dict[str, Any],
    report: dict[str, Any],
    run_command,
    output: pathlib.Path,
    rustc: pathlib.Path,
    cpu: int,
    timeout: int,
) -> bytes | None:
    directory: pathlib.Path = package["directory"]
    source = directory / "main.rs"
    if not source.is_file():
        append_failure(
            report,
            suite=package["suite"],
            case=package["id"],
            stage="rust-reference",
            phase="build",
            message="missing main.rs",
        )
        return None
    exe = output / "artifacts" / package["suite"] / package["id"] / "rust-reference"
    exe.parent.mkdir(parents=True, exist_ok=True)
    argv = [str(rustc), *RUST_FLAGS, str(source), "-o", str(exe)]
    command = run_command(
        report,
        label=f"{package['suite']}-{package['id']}-rust-build",
        argv=argv,
        cwd=ROOT,
        environment=clean_environment(),
        timeout_seconds=timeout,
    )
    ref: dict[str, Any] = {"build_command_id": command["id"], "source": artifact(source)}
    if command.get("returncode") != 0 or command.get("timed_out") or not exe.is_file():
        ref["status"] = "build_failed"
        case_result["rust_reference"] = ref
        append_failure(
            report,
            suite=package["suite"],
            case=package["id"],
            stage="rust-reference",
            phase="build",
            message="Rust reference did not build successfully",
            command_id=command["id"],
        )
        return None
    ref["executable"] = artifact(exe)
    oracle_command = run_command(
        report,
        label=f"{package['suite']}-{package['id']}-rust-oracle",
        argv=["taskset", "-c", str(cpu), str(exe)],
        cwd=ROOT,
        environment=clean_environment(),
        timeout_seconds=timeout,
    )
    oracle_ok = oracle_command.get("returncode") == 0 and not oracle_command.get("timed_out")
    if not oracle_ok:
        ref["status"] = "oracle_failed"
        ref["oracle_command_id"] = oracle_command["id"]
        case_result["rust_reference"] = ref
        append_failure(
            report,
            suite=package["suite"],
            case=package["id"],
            stage="rust-reference",
            phase="oracle",
            message="Rust reference did not exit successfully",
            command_id=oracle_command["id"],
        )
        return None
    stdout_path = output / oracle_command["stdout_log"]
    expected = stdout_path.read_bytes()
    ref.update(
        {
            "status": "oracle_ready",
            "oracle_command_id": oracle_command["id"],
            "expected_stdout_sha256": sha256_bytes(expected),
            "expected_stdout_size_bytes": len(expected),
        }
    )
    case_result["rust_reference"] = ref
    return expected


def prepare_case_expected(
    package: dict[str, Any],
    mode: str,
    langarena_params: dict[str, dict[str, Any]],
    case_result: dict[str, Any],
    report: dict[str, Any],
) -> tuple[bytes | None, list[str]]:
    expected, arguments, description = package_expected(package, mode, langarena_params)
    case_result["oracle"] = {
        "description": description,
        "arguments": arguments,
        "stdout_sha256": sha256_bytes(expected) if expected is not None else None,
        "stdout_size_bytes": len(expected) if expected is not None else None,
    }
    if expected is None and package["suite"] != "vs-rust":
        append_failure(
            report,
            suite=package["suite"],
            case=package["id"],
            stage="all",
            phase="oracle",
            message=description,
        )
    return expected, arguments


def median_stats(samples: list[dict[str, Any]]) -> dict[str, Any]:
    if not samples:
        return {"valid_sample_count": 0, "median_wall_seconds": None, "sample_wall_seconds": []}
    walls = [sample["wall_nanoseconds"] for sample in samples]
    return {
        "valid_sample_count": len(samples),
        "median_wall_seconds": statistics.median(walls) / 1_000_000_000,
        "median_wall_nanoseconds": statistics.median(walls),
        "sample_wall_seconds": [value / 1_000_000_000 for value in walls],
        "peak_rss_kib": max(sample["peak_rss_kib"] for sample in samples),
        "median_user_seconds": statistics.median(sample["user_seconds"] for sample in samples),
        "median_system_seconds": statistics.median(sample["system_seconds"] for sample in samples),
    }


def compare_stages(case_result: dict[str, Any]) -> None:
    builds = case_result["builds"]
    pairs: dict[str, Any] = {}
    for left_index, left in enumerate(STAGES[1:], 0):
        for right in STAGES[2 + left_index :]:
            left_build = builds.get(left, {})
            right_build = builds.get(right, {})
            pair = f"{left}_vs_{right}"
            pairs[pair] = {
                "ir_identical": bool(
                    left_build.get("ir", {}).get("sha256")
                    and left_build.get("ir", {}).get("sha256") == right_build.get("ir", {}).get("sha256")
                ),
                "binary_identical": bool(
                    left_build.get("executable", {}).get("sha256")
                    and left_build.get("executable", {}).get("sha256")
                    == right_build.get("executable", {}).get("sha256")
                ),
                "ir_comparable": bool(left_build.get("ir") and right_build.get("ir")),
                "binary_comparable": bool(left_build.get("executable") and right_build.get("executable")),
            }
    case_result["stage_identity_comparisons"] = pairs


def build_all_stages(
    package: dict[str, Any],
    case_result: dict[str, Any],
    report: dict[str, Any],
    run_command,
    checkpoint,
    output: pathlib.Path,
    compilers: dict[str, pathlib.Path],
    clang: pathlib.Path,
    runtime: pathlib.Path,
    timeout: int,
) -> None:
    directory: pathlib.Path = package["directory"]
    case_work = output / "artifacts" / package["suite"] / package["id"]
    case_work.mkdir(parents=True, exist_ok=True)
    case_result["builds"] = {}
    for stage in STAGES:
        ir = case_work / f"{stage}.ll"
        exe = case_work / f"{stage}.exe"
        compiler = compilers[stage]
        command = run_command(
            report,
            label=f"{package['suite']}-{package['id']}-{stage}-build-ir",
            argv=compiler_build_command(stage, compiler, directory, ir),
            cwd=ROOT,
            environment=compiler_environment(stage),
            timeout_seconds=timeout,
        )
        build: dict[str, Any] = {
            "description": STAGE_DESCRIPTIONS[stage],
            "compiler": report["compilers"][stage],
            "build_command_id": command["id"],
            "status": "build_failed",
        }
        case_result["builds"][stage] = build
        if command.get("returncode") != 0 or command.get("timed_out") or not ir.is_file():
            append_failure(
                report,
                suite=package["suite"],
                case=package["id"],
                stage=stage,
                phase="build_ir",
                message="compiler failed to emit LLVM IR",
                command_id=command["id"],
            )
            checkpoint(report)
            continue
        build["ir"] = artifact(ir)
        try:
            build["metadata"] = parse_ir_metadata(stage, ir.read_bytes())
        except RunnerError as error:
            build["status"] = "invalid_ir_metadata"
            build["metadata_error"] = str(error)
            append_failure(
                report,
                suite=package["suite"],
                case=package["id"],
                stage=stage,
                phase="ir_metadata",
                message=str(error),
                command_id=command["id"],
            )
            checkpoint(report)
            continue
        link_argv = [str(clang), "-O3"]
        if build["metadata"]["stack_mode"] == "offset":
            link_argv.append("-DNLC_STACK_MODE_OFFSET=1")
        link_argv.extend([str(ir), str(runtime), "-o", str(exe)])
        link_command = run_command(
            report,
            label=f"{package['suite']}-{package['id']}-{stage}-clang-link",
            argv=link_argv,
            cwd=ROOT,
            environment=clean_environment(),
            timeout_seconds=timeout,
        )
        build["link_command_id"] = link_command["id"]
        if link_command.get("returncode") != 0 or link_command.get("timed_out") or not exe.is_file():
            build["status"] = "link_failed"
            append_failure(
                report,
                suite=package["suite"],
                case=package["id"],
                stage=stage,
                phase="link",
                message="Clang failed to link LLVM IR with the C runtime",
                command_id=link_command["id"],
            )
            checkpoint(report)
            continue
        build["executable"] = artifact(exe)
        build["status"] = "built"
        checkpoint(report)
    compare_stages(case_result)
    checkpoint(report)


def run_case_program(
    package: dict[str, Any],
    stage: str,
    exe: pathlib.Path,
    arguments: list[str],
    expected: bytes,
    round_number: int | None,
    report: dict[str, Any],
    run_command,
    cpu: int,
    timeout: int,
    timed: bool,
) -> tuple[bool, dict[str, Any]]:
    label = f"{package['suite']}-{package['id']}-{stage}-{'warmup' if round_number is None else f'round-{round_number + 1}'}"
    command = run_command(
        report,
        label=label,
        argv=[str(exe), *arguments],
        cwd=ROOT,
        environment=clean_environment(),
        timed=timed,
        timeout_seconds=timeout,
    )
    valid, output_info = verify_output(command, expected, report)
    run_record: dict[str, Any] = {
        "command_id": command["id"],
        "round": round_number,
        "warmup": round_number is None,
        "output_validation": output_info,
        "returncode": command.get("returncode"),
        "timed_out": command.get("timed_out", False),
    }
    if timed:
        metrics_ok, timing_error = timed_command_ok(command)
        if metrics_ok:
            run_record.update(command["process_metrics"])
            run_record["wall_nanoseconds"] = command["wall_nanoseconds"]
        else:
            run_record["timing_error"] = timing_error
        valid = valid and metrics_ok
    if not output_info["status_ok"]:
        reason = "program did not exit successfully"
    elif not output_info["output_ok"]:
        reason = "stdout differs from the exact oracle bytes"
    elif timed and "timing_error" in run_record:
        reason = f"timing wrapper failed: {run_record['timing_error']}"
    else:
        reason = None
    if reason:
        append_failure(
            report,
            suite=package["suite"],
            case=package["id"],
            stage=stage,
            phase="warmup" if round_number is None else "timed_run",
            message=reason,
            command_id=command["id"],
        )
    return valid, run_record


def benchmark_case(
    package: dict[str, Any],
    case_result: dict[str, Any],
    expected: bytes | None,
    arguments: list[str],
    report: dict[str, Any],
    run_command,
    output: pathlib.Path,
    cpu: int,
    timeout: int,
    samples: int,
    case_index: int,
) -> None:
    case_result["timings"] = {}
    if package["status"].startswith("pending-"):
        case_result["status"] = "pending"
        case_result["pending_reason"] = package["status"]
        case_result["timings"] = {stage: {"status": "skipped_pending"} for stage in STAGES}
        return

    runtimes: dict[str, pathlib.Path] = {}
    for stage in STAGES:
        build = case_result["builds"].get(stage, {})
        if build.get("status") == "built" and expected is not None:
            runtimes[stage] = pathlib.Path(build["executable"]["path"])
        case_result["timings"][stage] = {"status": "not_run", "warmup": None, "samples": []}

    if package["suite"] == "vs-rust" and case_result.get("rust_reference", {}).get("status") == "oracle_ready":
        ref_path = pathlib.Path(case_result["rust_reference"]["executable"]["path"])
        runtimes["rust-reference"] = ref_path
        case_result["timings"]["rust-reference"] = {"status": "ready", "warmup": None, "samples": []}

    if expected is None:
        case_result["status"] = "oracle_unavailable"
        for stage in STAGES:
            case_result["timings"][stage]["status"] = "skipped_no_oracle"
        return

    timing_stages = list(runtimes)
    failed_stages: set[str] = set()
    if timing_stages:
        warmup_order = timing_stages[case_index % len(timing_stages) :] + timing_stages[: case_index % len(timing_stages)]
        for stage in warmup_order:
            if stage.startswith("stage"):
                exe = runtimes[stage]
                args = arguments
            else:
                exe = runtimes[stage]
                args = []
            valid, run_record = run_case_program(
                package,
                stage,
                exe,
                args,
                expected,
                None,
                report,
                run_command,
                cpu,
                timeout,
                timed=True,
            )
            case_result["timings"][stage]["warmup"] = run_record
            if not valid:
                failed_stages.add(stage)
                case_result["timings"][stage]["status"] = "warmup_failed"
            else:
                case_result["timings"][stage]["status"] = "ready"

        for round_number in range(samples):
            rotation = (case_index + round_number) % len(timing_stages)
            order = timing_stages[rotation:] + timing_stages[:rotation]
            for stage in order:
                if stage in failed_stages:
                    continue
                valid, run_record = run_case_program(
                    package,
                    stage,
                    runtimes[stage],
                    arguments if stage.startswith("stage") else [],
                    expected,
                    round_number,
                    report,
                    run_command,
                    cpu,
                    timeout,
                    timed=True,
                )
                if valid:
                    case_result["timings"][stage]["samples"].append(run_record)
                else:
                    failed_stages.add(stage)
                    case_result["timings"][stage]["status"] = "timed_run_failed"

    for stage in list(case_result["timings"]):
        timing = case_result["timings"][stage]
        if timing.get("status") == "ready" and len(timing.get("samples", [])) == samples:
            timing["status"] = "complete"
        elif timing.get("status") == "ready":
            timing["status"] = "incomplete"
        timing["statistics"] = median_stats(timing.get("samples", []))

    stage0_runs = {sample["round"]: sample for sample in case_result["timings"].get("stage0", {}).get("samples", [])}
    for stage in STAGES[1:]:
        timing = case_result["timings"].get(stage)
        if timing is None:
            continue
        runs = {sample["round"]: sample for sample in timing.get("samples", [])}
        paired_rounds = sorted(stage0_runs.keys() & runs.keys())
        if paired_rounds:
            baseline = statistics.median(stage0_runs[item]["wall_nanoseconds"] for item in paired_rounds)
            measured = statistics.median(runs[item]["wall_nanoseconds"] for item in paired_rounds)
            timing["ratio_vs_stage0"] = measured / baseline if baseline else None
            timing["ratio_sample_count"] = len(paired_rounds)
        else:
            timing["ratio_vs_stage0"] = None
            timing["ratio_sample_count"] = 0
    case_result["status"] = "complete" if (
        not failed_stages
        and expected is not None
        and all(case_result["timings"].get(stage, {}).get("status") == "complete" for stage in STAGES)
    ) else "partial"


def format_seconds(timing: dict[str, Any], stage: str) -> str:
    value = timing.get("statistics", {}).get("median_wall_seconds")
    count = timing.get("statistics", {}).get("valid_sample_count", 0)
    if value is None:
        return "—"
    ratio = timing.get("ratio_vs_stage0") if stage != "stage0" else None
    ratio_text = f"; {ratio:.3f}× Stage 0" if ratio is not None else ""
    return f"{value:.6f} s ({count}{ratio_text})"


def write_summary(output: pathlib.Path, report: dict[str, Any]) -> None:
    langarena_coverage = report["coverage"]["langarena"]
    selection = report["coverage"]["selection"]
    pending_descriptions = [
        f"LangArena/{case['id']} ({case['reason']})"
        for case in langarena_coverage["declared_pending_cases"]
    ]
    for suite in ("osprey", "vs-rust"):
        pending_descriptions.extend(
            f"{suite}/{case['id']} ({case['reason']})"
            for case in report["coverage"][suite].get("pending_cases", [])
        )
    missing_official = langarena_coverage["missing_official_names"]
    langarena_groups = langarena_coverage["status_and_audit_groups"]
    lines = [
        "# Compiler runtime benchmark summary",
        "",
        f"Status: `{report.get('status', 'running')}`. Mode: `{report['configuration']['mode']}`. "
        f"Samples per case: {report['configuration']['samples']} plus one validated warmup.",
        "",
        f"Selected {selection['selected_case_count']} present package(s) in {', '.join(selection['suites'])}; "
        + (
            "all present cases in those selected suites were selected."
            if selection["full_present_package_selection"]
            else "this result covers only the selected cases."
        ),
        f"Cases completing all four compiler stages: {report.get('summary', {}).get('complete_case_count', 0)}; "
        f"pending packages selected: {selection['selected_pending_count']}.",
        f"LangArena coverage: {langarena_coverage['present_official_name_count']}/"
        f"{langarena_coverage['official_name_count']} official names present; "
        f"{len(missing_official)} official names missing; "
        f"{langarena_coverage['declared_pending_count']} of "
        f"{langarena_coverage['package_directory_count']} package directories declared pending. "
        f"Groups: headline {langarena_groups.get('headline', 0)}, closest {langarena_groups.get('closest', 0)}, "
        f"not comparable {langarena_groups.get('not_comparable', 0)}, variants {langarena_groups.get('variants', 0)}.",
        "Missing official LangArena names: "
        + (", ".join(missing_official) if missing_official else "none"),
        "Declared pending cases: "
        + (", ".join(pending_descriptions) if pending_descriptions else "none"),
        "",
        "Elapsed values are whole-process medians, including LangArena preparation and warmup. "
        "Each count is the number of output-validated timed samples. Ratios use paired valid "
        "rounds against Stage 0. No combined geometric mean is calculated.",
        "",
        "| Suite | Case | Group | Stage 0 | Stage 1 | Stage 2 | Stage 3 | Rust reference |",
        "|---|---|---|---:|---:|---:|---:|---:|",
    ]
    for case in report["cases"]:
        if case.get("status") == "pending":
            cells = [case["suite"], case["id"], case.get("group", "pending"), "pending", "pending", "pending", "pending", "—"]
        else:
            timings = case.get("timings", {})
            cells = [
                case["suite"],
                case["id"],
                case.get("group", ""),
                *(format_seconds(timings.get(stage, {}), stage) for stage in STAGES),
                format_seconds(timings.get("rust-reference", {}), "rust-reference"),
            ]
        lines.append("| " + " | ".join(str(cell).replace("|", "\\|") for cell in cells) + " |")
    lines.extend(
        [
            "",
            f"Failures recorded: {len(report['failures'])}.",
            "See `report.json` for exact commands, hashes, raw samples, per-run validation, and log paths.",
            "",
        ]
    )
    temporary = output / ".summary.md.tmp"
    temporary.write_text("\n".join(lines), encoding="utf-8")
    os.replace(temporary, output / "summary.md")


def print_case_summary(case: dict[str, Any], samples: int) -> None:
    if case.get("status") == "pending":
        print(f"  {case['suite']}/{case['id']}: {case.get('pending_reason', 'pending')}", flush=True)
        return
    parts = []
    for stage in STAGES:
        timing = case.get("timings", {}).get(stage, {})
        stat = timing.get("statistics", {})
        value = stat.get("median_wall_seconds")
        count = stat.get("valid_sample_count", 0)
        parts.append(f"{stage}={value:.6f}s/{count}" if value is not None else f"{stage}=—")
    print(f"  {case['suite']}/{case['id']}: " + " ".join(parts), flush=True)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage0-ir-helper", required=True, help="compiled Rust API helper that emits Stage 0 LLVM IR")
    parser.add_argument("--stage0-nlc", help="optional Rust-built nlc binary to fingerprint in the report")
    parser.add_argument("--stage1", required=True, help="Rust-built self-hosted compiler executable")
    parser.add_argument("--stage2", required=True, help="Stage 1-built compiler executable")
    parser.add_argument("--stage3", required=True, help="Stage 2-built compiler executable")
    parser.add_argument("--output-dir", required=True, help="new output directory, relative to the repository root")
    parser.add_argument("--clang", default="clang", help="Clang executable used for every C-runtime link")
    parser.add_argument("--rustc", default="rustc", help="Rust compiler used only for paired Rust reference programs")
    parser.add_argument("--cpu", type=int, default=8, help="single CPU pinned for each runtime process (default: 8)")
    parser.add_argument("--samples", type=int, default=3, help="validated measured runs per program (default: 3)")
    parser.add_argument("--timeout", type=int, default=120, help="per-command timeout in seconds (default: 120)")
    parser.add_argument("--mode", choices=("test", "run"), default="run", help="LangArena parameters; default is the full run")
    parser.add_argument(
        "--suite",
        action="append",
        choices=("all", "langarena", "osprey", "vs-rust"),
        help="suite to run; repeat to select several (default: all)",
    )
    parser.add_argument(
        "--case",
        action="append",
        help="case directory name or suite display name; repeat to select several",
    )
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("--samples must be at least 1")
    if args.timeout < 1:
        parser.error("--timeout must be at least 1 second")
    if args.cpu < 0:
        parser.error("--cpu must be a nonnegative CPU number")
    return args


def main() -> int:
    args = parse_arguments()
    if sys.platform != "linux" or fcntl is None:
        raise RunnerError("the benchmark runner requires Linux or WSL with fcntl")
    if not shutil.which("taskset") or not pathlib.Path("/usr/bin/time").is_file():
        raise RunnerError("taskset and GNU /usr/bin/time are required")
    if not LOCK_PATH.parent.is_dir():
        raise RunnerError(f"benchmark lock directory is missing: {LOCK_PATH.parent}")

    output = checked_output_dir(args.output_dir)
    stage0_helper = resolve_tool(args.stage0_ir_helper, "Stage 0 IR helper")
    stage0_nlc = resolve_tool(args.stage0_nlc, "Stage 0 nlc") if args.stage0_nlc else None
    compilers = {
        "stage0": stage0_helper,
        "stage1": resolve_tool(args.stage1, "Stage 1 compiler"),
        "stage2": resolve_tool(args.stage2, "Stage 2 compiler"),
        "stage3": resolve_tool(args.stage3, "Stage 3 compiler"),
    }
    clang = resolve_tool(args.clang, "Clang")
    rustc = resolve_tool(args.rustc, "rustc")
    runtime = ROOT / "runtime" / "nl_runtime.c"
    if not runtime.is_file():
        raise RunnerError(f"C runtime source is missing: {runtime}")

    discovered, coverage, langarena_params = discover_packages()
    if args.suite is None or "all" in args.suite:
        suites = ["langarena", "osprey", "vs-rust"]
    else:
        suites = list(dict.fromkeys(args.suite))
    selected = select_packages(discovered, suites, args.case or [])
    if not selected:
        raise RunnerError("no benchmark cases were found")

    selected_by_suite = {
        suite: {case["id"] for case in selected if case["suite"] == suite}
        for suite in suites
    }
    full_present_selection = all(
        selected_by_suite[suite] == {case["id"] for case in discovered[suite]}
        for suite in suites
    )
    selected_pending_count = sum(
        case["status"].startswith("pending-") for case in selected
    )
    missing_official_in_full_selection = (
        "langarena" in suites
        and full_present_selection
        and bool(coverage["langarena"]["missing_official_names"])
    )
    has_coverage_gaps = selected_pending_count > 0 or missing_official_in_full_selection
    coverage["selection"] = {
        "suites": suites,
        "selected_case_count": len(selected),
        "selected_by_suite": {suite: len(selected_by_suite[suite]) for suite in suites},
        "full_present_package_selection": full_present_selection,
        "selected_pending_count": selected_pending_count,
        "full_selection_has_missing_official_langarena_names": missing_official_in_full_selection,
        "has_coverage_gaps": has_coverage_gaps,
    }

    report: dict[str, Any] = {
        "schema_version": 1,
        "status": "running",
        "repository": {
            "path": str(ROOT),
            "head": None,
            "compiler_source_sha256": hash_tree(
                [ROOT / "Cargo.toml", ROOT / "Cargo.lock", ROOT / "compiler" / "Cargo.toml", ROOT / "compiler" / "src"]
            ),
            "selfhost_source_sha256": hash_tree([ROOT / "selfhost"]),
            "stage0_helper_source": artifact(ROOT / "bench" / "runtime-stage0-ir.rs"),
        },
        "output_dir": str(output),
        "configuration": {
            "mode": args.mode,
            "suites": suites,
            "case_filters": args.case or [],
            "cpu": args.cpu,
            "samples": args.samples,
            "warmups": 1,
            "timeout_seconds": args.timeout,
            "clang_flags": ["-O3", "-DNLC_STACK_MODE_OFFSET=1 when IR says offset"],
            "runtime_source": artifact(runtime),
            "langarena_timing_method": "whole process; includes preparation and warmup; no prep subtraction",
            "rust_reference_flags": list(RUST_FLAGS),
            "rust_reuse_variants": "omitted by scope",
            "ratio_method": "median of the same output-validated sample rounds relative to Stage 0; per case only",
            "environment_policy": "strip inherited NLC_* variables; Stage 0 helper receives NLC_STACK_MODE=pointer and NLC_OPT_LEVEL=3; all other processes receive neither",
        },
        "coverage": coverage,
        "compilers": {},
        "toolchain": {},
        "commands": [],
        "failures": [],
        "tool_probe_failures": [],
        "cases": [],
    }
    try:
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout.strip()
        report["repository"]["head"] = head
    except (OSError, subprocess.SubprocessError):
        report["repository"]["head"] = "unavailable"

    run_command, checkpoint = make_runner(output, args.timeout, args.cpu)
    base_environment = clean_environment()
    for stage, path in compilers.items():
        compiler_info = artifact(path)
        compiler_info["description"] = STAGE_DESCRIPTIONS[stage]
        compiler_info["source_fingerprint"] = (
            report["repository"]["compiler_source_sha256"] if stage == "stage0" else report["repository"]["selfhost_source_sha256"]
        )
        report["compilers"][stage] = compiler_info
    if stage0_nlc:
        report["compilers"]["stage0_nlc_fingerprint"] = artifact(stage0_nlc)

    for package in selected:
        case_result: dict[str, Any] = {
            "suite": package["suite"],
            "id": package["id"],
            "display_name": package["display_name"],
            "group": package["group"],
            "status_marker": package["status"],
            "audit": package["audit"],
            "package": {
                "path": str(package["directory"].resolve()),
                "sha256": hash_tree([package["directory"]]),
            },
        }
        report["cases"].append(case_result)

    checkpoint(report)
    with LOCK_PATH.open("a", encoding="ascii") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            print(f"Benchmark lock acquired: {LOCK_PATH}", flush=True)
            report["toolchain"]["python"] = platform.python_version()
            report["toolchain"]["platform"] = platform.platform()
            report["toolchain"]["clang"] = {
                "binary": artifact(clang),
                "version": version_probe(
                    report, run_command, "tool-clang-version", [str(clang), "--version"], ROOT, base_environment
                ),
            }
            report["toolchain"]["rustc"] = {
                "binary": artifact(rustc),
                "version": version_probe(
                    report, run_command, "tool-rustc-version", [str(rustc), "--version", "--verbose"], ROOT, base_environment
                ),
            }
            taskset_path = pathlib.Path(shutil.which("taskset") or "taskset").resolve()
            report["toolchain"]["taskset"] = {
                "binary": artifact(taskset_path),
                "version": version_probe(
                    report, run_command, "tool-taskset-version", [str(taskset_path), "--version"], ROOT, base_environment
                ),
            }
            time_binary = pathlib.Path("/usr/bin/time")
            report["toolchain"]["time"] = {
                "binary": artifact(time_binary),
                "version": version_probe(
                    report, run_command, "tool-time-version", ["/usr/bin/time", "--version"], ROOT, base_environment
                ),
            }
            checkpoint(report)

            for index, (package, case_result) in enumerate(zip(selected, report["cases"])):
                print(f"[{index + 1}/{len(selected)}] {package['suite']}/{package['id']} ({package['group']})", flush=True)
                before_hash = case_result["package"]["sha256"]
                expected, arguments = prepare_case_expected(
                    package, args.mode, langarena_params, case_result, report
                )
                if package["suite"] == "vs-rust" and not package["status"].startswith("pending-"):
                    expected = compile_rust_reference(
                        package,
                        case_result,
                        report,
                        run_command,
                        output,
                        rustc,
                        args.cpu,
                        args.timeout,
                    )
                    case_result["oracle"] = {
                        "description": "freshly compiled Rust stdout oracle",
                        "arguments": [],
                        "stdout_sha256": sha256_bytes(expected) if expected is not None else None,
                        "stdout_size_bytes": len(expected) if expected is not None else None,
                    }
                if package["status"].startswith("pending-"):
                    case_result["builds"] = {stage: {"status": "skipped_pending"} for stage in STAGES}
                    benchmark_case(
                        package,
                        case_result,
                        expected,
                        arguments,
                        report,
                        run_command,
                        output,
                        args.cpu,
                        args.timeout,
                        args.samples,
                        index,
                    )
                else:
                    build_all_stages(
                        package,
                        case_result,
                        report,
                        run_command,
                        checkpoint,
                        output,
                        compilers,
                        clang,
                        runtime,
                        args.timeout,
                    )
                    benchmark_case(
                        package,
                        case_result,
                        expected,
                        arguments,
                        report,
                        run_command,
                        output,
                        args.cpu,
                        args.timeout,
                        args.samples,
                        index,
                    )
                after_hash = hash_tree([package["directory"]])
                case_result["package"]["unchanged_during_run"] = before_hash == after_hash
                if before_hash != after_hash:
                    append_failure(
                        report,
                        suite=package["suite"],
                        case=package["id"],
                        stage="all",
                        phase="source_integrity",
                        message="benchmark package source changed while the run was active",
                    )
                write_summary(output, report)
                checkpoint(report)
                print_case_summary(case_result, args.samples)

            report["summary"] = {
                "selected_case_count": len(report["cases"]),
                "complete_case_count": sum(case.get("status") == "complete" for case in report["cases"]),
                "pending_case_count": sum(case.get("status") == "pending" for case in report["cases"]),
                "partial_case_count": sum(case.get("status") == "partial" for case in report["cases"]),
                "oracle_unavailable_case_count": sum(case.get("status") == "oracle_unavailable" for case in report["cases"]),
                "failure_count": len(report["failures"]),
                "full_present_package_selection": report["coverage"]["selection"]["full_present_package_selection"],
                "declared_pending_count": sum(
                    len(report["coverage"][suite].get("pending_cases", []))
                    if suite != "langarena"
                    else report["coverage"][suite]["declared_pending_count"]
                    for suite in suites
                ),
                "missing_official_langarena_count": len(report["coverage"]["langarena"]["missing_official_names"]),
            }
            if report["failures"]:
                report["status"] = "failed"
            elif report["coverage"]["selection"]["has_coverage_gaps"]:
                report["status"] = "completed_with_coverage_gaps"
            else:
                report["status"] = "passed_selected_cases"
            report["finished_at_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            write_summary(output, report)
            checkpoint(report)
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
    print(f"Report: {(output / 'report.json').relative_to(ROOT)}", flush=True)
    print(f"Summary: {(output / 'summary.md').relative_to(ROOT)}", flush=True)
    print(f"Status: {report['status']}", flush=True)
    print(f"Failures: {len(report['failures'])}", flush=True)
    return 0 if not report["failures"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RunnerError, OSError, ValueError) as error:
        print(f"runtime benchmark runner: {error}", file=sys.stderr, flush=True)
        raise SystemExit(2)
