#!/usr/bin/env python3
"""Compare E3a2's typed copy helpers with the generic core memcpy call."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
SIZES = (8, 40, 64, 256, 4096)
LIST_COUNTS = (8, 64, 1024)


def run(command: list[str], *, env: dict[str, str], timeout: int = 300) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"stdout={result.stdout.decode(errors='replace')[:500]}\n"
            f"stderr={result.stderr.decode(errors='replace')[:1000]}"
        )
    return result


def source_for_struct(size: int) -> str:
    fields = ", ".join(f"f{index}: long" for index in range(size // 8))
    return f"struct Blob {{ {fields} }}\nfn copy_value(value: Blob) -> Blob {{ value }}\nfn main() {{}}\n"


def source_for_list(capacity: int) -> str:
    return (
        "struct Cell { left: long, right: long, active: bool }\n"
        f"fn copy_value(value: list<Cell, {capacity}>) -> list<Cell, {capacity}> {{ value }}\n"
        "fn main() {}\n"
    )


def replace_main_body(ir: str) -> str:
    main_body = re.search(r"define i32 @main\([^\n]*\) \{\n(.*?)^\}\n", ir, re.MULTILINE | re.DOTALL)
    if main_body is None:
        raise RuntimeError("could not find generated entry point")
    function_call = re.search(r"call void @nl_fn_([0-9]+)\(ptr %nl\.ctx, i64 %nl\.top\)", main_body.group(1))
    if function_call is None:
        raise RuntimeError("could not find the source main function call")
    function_id = function_call.group(1)
    pattern = re.compile(rf"define void @nl_fn_{function_id}\([^\n]*\) \{{\n.*?^\}}\n", re.MULTILINE | re.DOTALL)
    replacement = (
        f"define void @nl_fn_{function_id}(ptr %nl.ctx, i64 %nl.top) {{\n"
        "entry:\n  call void @bench_run(ptr %nl.ctx)\n  ret void\n}\n"
    )
    ir, count = pattern.subn(replacement, ir, count=1)
    if count != 1:
        raise RuntimeError("could not replace the generated source main function")
    return ir


def patch_module(ir_path: Path, copy_kind: str, copy_size: int) -> None:
    ir = ir_path.read_text()
    helpers = re.findall(
        r"define internal void @nl\.copy\.([0-9]+)\([^\n]*\) \{\n(.*?)^\}\n",
        ir,
        re.MULTILINE | re.DOTALL,
    )
    if copy_kind == "list":
        candidates = [(name, body) for name, body in helpers if "%coll.copy.count." in body]
    else:
        candidates = [
            (name, body)
            for name, body in helpers
            if "%copy.value." in body or "%copy.bulk." in body
        ]
    if len(candidates) != 1:
        raise RuntimeError(f"expected one {copy_kind} copy helper, found {len(candidates)}")
    helper_id, _ = candidates[0]

    ir = replace_main_body(ir)
    ir = ir.replace(
        "define i32 @main(",
        "declare void @bench_run(ptr)\n\ndefine i32 @main(",
        1,
    )
    additions = (
        f"define void @bench_special(ptr %dst, ptr %src) {{\n"
        f"entry:\n  call void @nl.copy.{helper_id}(ptr null, ptr %dst, ptr %src)\n  ret void\n}}\n\n"
        f"define void @bench_generic(ptr %dst, ptr %src) {{\n"
        f"entry:\n  %result = call ptr @memcpy(ptr %dst, ptr %src, i64 {copy_size})\n  ret void\n}}\n\n"
    )
    marker = "; nlc-link-ir end"
    if marker not in ir:
        raise RuntimeError("generated module has no link-ir end marker")
    ir_path.write_text(ir.replace(marker, additions + marker, 1))


def build_one(
    *, label: str, kind: str, size: int, source: str, compiler: Path,
    clang: str, root_relative_work: str, work: Path, env: dict[str, str],
    list_count: int = 0,
) -> tuple[int, str]:
    package = work / label
    package.mkdir()
    (package / "main.nl").write_text(source)
    ir = work / f"{label}.ll"
    run(
        [str(compiler), "build", f"{root_relative_work}/{label}", "-o", f"{root_relative_work}/{label}.ll", "--runtime=core"],
        env=env,
    )
    patch_module(ir, kind, size)
    object_file = work / f"{label}.o"
    executable = work / f"{label}.exe"
    c_flags = ["-O3", "-fno-stack-protector", "-fno-pie", f"-DBENCH_SIZE={size}", f'-DBENCH_LABEL="{label}"']
    if kind == "list":
        c_flags.append(f"-DBENCH_LIST_COUNT={list_count}")
    run(
        [clang, *c_flags, "-c", "bench/e3a2/copy_bench.c", "-o", str(object_file)],
        env=env,
    )
    run(
        [clang, "-O3", "-nostartfiles", "-no-pie", "-Wl,-e,_start", "-Wl,--build-id=none", str(ir), str(object_file), "-o", str(executable)],
        env=env,
    )
    affinity = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else []
    taskset = shutil.which("taskset")
    command = [str(executable)]
    if taskset and affinity:
        command = [taskset, "-c", str(affinity[0]), *command]
    measured = run(command, env=env, timeout=120)
    line = measured.stdout.decode("ascii").strip()
    return size, line


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True, type=Path, help="current self-hosted compiler executable")
    parser.add_argument("--nlc", type=Path, default=Path.home() / ".cache/next-lang/target/debug/nlc")
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    if not compiler.is_file() or not os.access(compiler, os.X_OK):
        raise RuntimeError(f"self-hosted compiler is not executable: {compiler}")
    if not args.nlc.is_file() or not os.access(args.nlc, os.X_OK):
        raise RuntimeError(f"nlc is not executable: {args.nlc}")
    clang = shutil.which("clang")
    if not clang:
        raise RuntimeError("clang is not on PATH")

    work = Path(tempfile.mkdtemp(prefix=".selfhost-copy-bench-", dir=ROOT))
    env = os.environ.copy()
    env["NLC_OPT_LEVEL"] = "3"
    env["CARGO_TARGET_DIR"] = str(Path.home() / ".cache/next-lang/target")
    relative = work.relative_to(ROOT).as_posix()
    results: list[str] = []
    try:
        for size in SIZES:
            _, result = build_one(
                label=f"struct-{size}", kind="struct", size=size,
                source=source_for_struct(size), compiler=compiler, clang=clang,
                root_relative_work=relative, work=work, env=env,
            )
            results.append(result)
        for capacity in LIST_COUNTS:
            total_size = 8 + 17 * capacity
            _, result = build_one(
                label=f"list-cell-{capacity}", kind="list", size=total_size,
                source=source_for_list(capacity), compiler=compiler, clang=clang,
                root_relative_work=relative, work=work, env=env, list_count=capacity,
            )
            results.append(result)
        print("kind,storage_bytes,specialized_best_ps,specialized_median_ps,specialized_worst_ps,generic_best_ps,generic_median_ps,generic_worst_ps,generic_over_specialized_milli")
        for result in results:
            print(result)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=__import__("sys").stderr)
        raise SystemExit(1)
