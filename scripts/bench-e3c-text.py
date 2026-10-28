#!/usr/bin/env python3
"""Output-checked E3c text, copy, bootstrap, and stack measurements.

Run this under Linux/WSL with a stage-zero nlc and a selfhost compiler built
from the working tree. The script takes the shared benchmark lock itself.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import re
import resource
import shutil
import statistics
import struct
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LOCK = Path("/home/ben/linuxbench/bench.lock")
DEFAULT_TARGET = Path(os.environ.get("CARGO_TARGET_DIR", Path.home() / ".cache/next-lang/target"))
COPY_MAX_BYTES = (8, 40, 64, 256, 4096)
TEXT_ITERATIONS = 1_000_000
TEXT_PRINT_EVERY = 4096
MEMORY_LIMIT_KIB = 8_000_000
U64_MASK = (1 << 64) - 1


def child_setup() -> None:
    """Apply the documented 8,000,000 KiB address-space limit to children."""
    maximum = MEMORY_LIMIT_KIB * 1024
    resource.setrlimit(resource.RLIMIT_AS, (maximum, maximum))


def pin_command(command: list[str], cpu: int) -> list[str]:
    taskset = shutil.which("taskset")
    if taskset is None:
        raise RuntimeError("taskset is required to pin measurements")
    affinity = os.sched_getaffinity(0)
    if cpu not in affinity:
        raise RuntimeError(f"requested benchmark CPU {cpu} is outside this process affinity {sorted(affinity)}")
    return [taskset, "-c", str(cpu), *command]


def run_process(
    command: list[str],
    *,
    cwd: Path,
    env: dict[str, str],
    timeout: int = 300,
) -> subprocess.CompletedProcess[bytes]:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
        preexec_fn=child_setup,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"stdout={result.stdout.decode(errors='replace')[:1000]}\n"
            f"stderr={result.stderr.decode(errors='replace')[:2000]}"
        )
    return result


def checked_output(executable: Path, *, env: dict[str, str], expected: bytes) -> bytes:
    result = run_process([str(executable)], cwd=ROOT, env=env, timeout=180)
    if result.stderr:
        raise RuntimeError(
            f"program wrote stderr: {executable}\n{result.stderr.decode(errors='replace')[:2000]}"
        )
    if result.stdout != expected:
        raise RuntimeError(
            f"program output mismatch: {executable}\n"
            f"expected={expected[:1000]!r}\nactual={result.stdout[:1000]!r}"
        )
    return result.stdout


def text_source(iterations: int, print_every: int) -> str:
    return f'''fn render(value: Text max 21 bytes max 22) -> Text max 35 bytes max 36 {{
    let joined = "prefix:" + value + ":suffix"
    joined.slice(1L..9L)
}}

fn main() {{
    var checksum: long = 0L
    for index: long in 0L..{iterations}L {{
        let value: Text max 21 bytes max 22 = "é" + str(index)
        let result = render(value)
        let matches_first = result == "refix:é0"
        let matched: long = if matches_first {{ 1L }} else {{ 0L }}
        checksum = (checksum * 31L + matched + result.len() + result.byte_len()) % 1000000007L
        if index % {print_every}L == 0L {{ print(result) }}
    }}
    print(checksum)
}}
'''


def text_expected_output(iterations: int, print_every: int) -> bytes:
    output: list[str] = []
    checksum = 0
    for index in range(iterations):
        if index % print_every == 0:
            output.append(f"refix:é{str(index)[0]}\n")
        checksum = (checksum * 31 + int(index == 0) + 8 + 9) % 1_000_000_007
    output.append(f"{checksum}\n")
    return "".join(output).encode("utf-8")


def prepare_package(package: Path, source: str) -> None:
    package.mkdir(parents=True)
    (package / "main.nl").write_text(source, encoding="utf-8")
    (package / "package.toml").write_text('capabilities = ["out"]\n', encoding="utf-8")


def compile_with_stage0(
    reference: Path,
    package: Path,
    output: Path,
    *,
    env: dict[str, str],
) -> None:
    run_process(
        [str(reference), "--frontend=rust", "build", ".", "-o", str(output)],
        cwd=package,
        env=env,
    )
    if not output.is_file() or not os.access(output, os.X_OK):
        raise RuntimeError(f"stage-zero build did not produce an executable: {output}")


def compile_with_selfhost(
    reference: Path,
    selfhost: Path,
    package: Path,
    ir_path: Path,
    output: Path,
    *,
    env: dict[str, str],
) -> None:
    run_process(
        [str(selfhost), "build", ".", "-o", ir_path.name, "--runtime=core"],
        cwd=package,
        env=env,
    )
    if not ir_path.is_file():
        raise RuntimeError(f"selfhost build did not produce IR: {ir_path}")
    run_process(
        [str(reference), "--frontend=rust", "link-ir", str(ir_path), "-o", str(output)],
        cwd=package,
        env=env,
    )
    if not output.is_file() or not os.access(output, os.X_OK):
        raise RuntimeError(f"link-ir did not produce an executable: {output}")


def timed_output(
    executable: Path,
    *,
    env: dict[str, str],
    expected: bytes,
    cpu: int,
) -> float:
    command = pin_command([str(executable)], cpu)
    start = time.perf_counter_ns()
    result = run_process(command, cwd=ROOT, env=env, timeout=180)
    elapsed = time.perf_counter_ns() - start
    if result.stderr:
        raise RuntimeError(
            f"timed sample wrote stderr: {executable}\n{result.stderr.decode(errors='replace')[:2000]}"
        )
    if result.stdout != expected:
        raise RuntimeError(
            f"timed sample output mismatch: {executable}; "
            f"expected sha256={hashlib.sha256(expected).hexdigest()}, "
            f"actual sha256={hashlib.sha256(result.stdout).hexdigest()}"
        )
    return elapsed / 1_000_000_000


def summarize(samples: list[float]) -> tuple[float, float, float]:
    return min(samples), statistics.median(samples), max(samples)


def print_time_row(label: str, samples: list[float]) -> None:
    best, median, worst = summarize(samples)
    print(
        f"{label}: best={best:.6f}s median={median:.6f}s worst={worst:.6f}s "
        f"spread={worst - best:.6f}s ({(worst - best) / median * 100:.2f}% of median)"
    )


def run_text_benchmark(
    reference: Path,
    selfhost: Path,
    env: dict[str, str],
    work: Path,
    *,
    iterations: int,
    print_every: int,
    cpu: int,
) -> None:
    print("\n## Text-heavy workload")
    package = work / "text-heavy"
    prepare_package(package, text_source(iterations, print_every))
    expected = text_expected_output(iterations, print_every)
    stage0 = work / "text-heavy-stage0"
    selfhost_exe = work / "text-heavy-selfhost"
    ir_path = package / "selfhost.ll"
    compile_with_stage0(reference, package, stage0, env=env)
    compile_with_selfhost(reference, selfhost, package, ir_path, selfhost_exe, env=env)

    stage0_output = checked_output(stage0, env=env, expected=expected)
    selfhost_output = checked_output(selfhost_exe, env=env, expected=expected)
    if stage0_output != selfhost_output:
        raise RuntimeError("stage-zero and selfhost text outputs differ")
    print(f"iterations={iterations} print_every={print_every}")
    print(f"checked_output_bytes={len(expected)} sha256={hashlib.sha256(expected).hexdigest()}")

    # Warm both executables before collecting alternating, output-checked runs.
    checked_output(stage0, env=env, expected=expected)
    checked_output(selfhost_exe, env=env, expected=expected)
    samples = {"stage0": [], "selfhost": []}
    for repeat in range(5):
        order = (("stage0", stage0), ("selfhost", selfhost_exe))
        if repeat % 2:
            order = tuple(reversed(order))
        for label, executable in order:
            samples[label].append(
                timed_output(executable, env=env, expected=expected, cpu=cpu)
            )
    print_time_row("stage0", samples["stage0"])
    print_time_row("selfhost", samples["selfhost"])
    ratio = statistics.median(samples["stage0"]) / statistics.median(samples["selfhost"])
    print(f"stage0_over_selfhost_median={ratio:.3f}x")


def text_copy_source(max_bytes: int) -> str:
    return f'''fn duplicate(value: Text max {max_bytes} bytes max {max_bytes}) -> Text max {max_bytes} bytes max {max_bytes} {{
    var copied: Text max {max_bytes} bytes max {max_bytes} = Text.empty()
    copied = value
    copied
}}

fn main() {{
    let value: Text max {max_bytes} bytes max {max_bytes} = Text.empty()
    let copied = duplicate(value)
    print(copied.len())
}}
'''


def replace_main_with_bench(ir: str) -> str:
    main = re.search(r"define i32 @main\([^\n]*\) \{\n(.*?)^\}\n", ir, re.MULTILINE | re.DOTALL)
    if main is None:
        raise RuntimeError("could not find generated entry point in text-copy IR")
    if re.search(r"call void @nl_fn_[0-9]+\(ptr %nl\.ctx, i64 %nl\.top\)", main.group(1)) is None:
        raise RuntimeError("could not find the source main call in text-copy IR")
    function_id = re.search(
        r"call void @nl_fn_([0-9]+)\(ptr %nl\.ctx, i64 %nl\.top\)", main.group(1)
    )
    if function_id is None:
        raise RuntimeError("could not identify the generated source main function")
    identifier = function_id.group(1)
    pattern = re.compile(
        rf"define void @nl_fn_{identifier}\([^\n]*\) \{{\n.*?^\}}\n",
        re.MULTILINE | re.DOTALL,
    )
    replacement = (
        f"define void @nl_fn_{identifier}(ptr %nl.ctx, i64 %nl.top) {{\n"
        "entry:\n  call void @bench_run(ptr %nl.ctx)\n  ret void\n}\n"
    )
    ir, count = pattern.subn(replacement, ir, count=1)
    if count != 1:
        raise RuntimeError("could not replace the generated source main function")
    return ir.replace(
        "define i32 @main(", "declare void @bench_run(ptr)\n\ndefine i32 @main(", 1
    )


def text_copy_helper_id(ir: str, text_helpers: list[tuple[str, str]]) -> str:
    entry = re.search(r"define i32 @main\([^\n]*\) \{\n(.*?)^\}\n", ir, re.MULTILINE | re.DOTALL)
    if entry is None:
        raise RuntimeError("could not find generated entry point for Text-copy helper selection")
    main_id = re.search(r"call void @nl_fn_([0-9]+)\(ptr %nl\.ctx, i64 %nl\.top\)", entry.group(1))
    if main_id is None:
        raise RuntimeError("could not identify the generated source main function for Text-copy helper selection")

    function_pattern = re.compile(
        r"define void @nl_fn_([0-9]+)\([^\n]*\) \{\n(.*?)^\}\n",
        re.MULTILINE | re.DOTALL,
    )
    functions = {identifier: body for identifier, body in function_pattern.findall(ir)}
    source_main = functions.get(main_id.group(1))
    if source_main is None:
        raise RuntimeError("could not find source main body for Text-copy helper selection")

    duplicate_ids = re.findall(r"call void @nl_fn_([0-9]+)\(", source_main)
    if len(duplicate_ids) != 1:
        raise RuntimeError(
            "expected source main to call duplicate exactly once; "
            f"found generated function calls {duplicate_ids}"
        )
    duplicate_body = functions.get(duplicate_ids[0])
    if duplicate_body is None:
        raise RuntimeError("could not find duplicate body for Text-copy helper selection")

    available = {identifier for identifier, _ in text_helpers}
    referenced = set(re.findall(r"call void @nl\.copy\.([0-9]+)\(", duplicate_body))
    used_text_helpers = available & referenced
    if len(used_text_helpers) != 1:
        all_copy_calls = sorted(re.findall(r"call void @nl\.copy\.([0-9]+)\(", duplicate_body))
        raise RuntimeError(
            "expected duplicate to call one generated Text copy helper for its stored local copy; "
            f"found {sorted(used_text_helpers)} among available {sorted(available)}; "
            f"all copy calls in duplicate={all_copy_calls}"
        )
    return next(iter(used_text_helpers))


def patch_text_copy_ir(ir_path: Path, max_bytes: int, live_bytes: int) -> None:
    ir = ir_path.read_text(encoding="utf-8")
    helpers = re.findall(
        r"define internal void @nl\.copy\.([0-9]+)\([^\n]*\) \{\n(.*?)^\}\n",
        ir,
        re.MULTILINE | re.DOTALL,
    )
    text_helpers = [
        (type_id, body)
        for type_id, body in helpers
        if f"%text.copy.length.src.{type_id}" in body
        and f"%text.copy.call.{type_id}" in body
    ]
    if not text_helpers:
        raise RuntimeError("no generated Text copy helper found")
    type_id = text_copy_helper_id(ir, text_helpers)
    ir = replace_main_with_bench(ir)
    additions = (
        f"define void @bench_special(ptr %dst, ptr %src) {{\n"
        f"entry:\n  call void @nl.copy.{type_id}(ptr null, ptr %dst, ptr %src)\n  ret void\n}}\n\n"
        f"define void @bench_generic_live(ptr %dst, ptr %src) {{\n"
        f"entry:\n  %result = call ptr @memcpy(ptr %dst, ptr %src, i64 {16 + live_bytes})\n  ret void\n}}\n\n"
        f"define void @bench_generic_full(ptr %dst, ptr %src) {{\n"
        f"entry:\n  %result = call ptr @memcpy(ptr %dst, ptr %src, i64 {16 + max_bytes})\n  ret void\n}}\n\n"
    )
    marker = "; nlc-link-ir end"
    if marker not in ir:
        raise RuntimeError("generated Text module has no link-ir end marker")
    ir_path.write_text(ir.replace(marker, additions + marker, 1), encoding="utf-8")


TEXT_COPY_C = r'''#include <stddef.h>
#include <stdint.h>

#ifndef BENCH_MAX_BYTES
#error BENCH_MAX_BYTES must be supplied
#endif
#ifndef BENCH_LIVE_BYTES
#error BENCH_LIVE_BYTES must be supplied
#endif

#define HEADER_BYTES 16u
#define SLOT_BYTES (HEADER_BYTES + BENCH_MAX_BYTES)
typedef void (*copy_function)(void *, const void *);
typedef struct { long seconds; long nanoseconds; } timespec_raw;

extern void bench_special(void *, const void *);
extern void bench_generic_live(void *, const void *);
extern void bench_generic_full(void *, const void *);
extern void *memcpy(void *, const void *, size_t);

static unsigned char source[SLOT_BYTES + 64] __attribute__((aligned(64)));
static unsigned char destination[SLOT_BYTES + 64] __attribute__((aligned(64)));
static volatile uint64_t sink;
static copy_function volatile special_copy = bench_special;
static copy_function volatile live_copy = bench_generic_live;
static copy_function volatile full_copy = bench_generic_full;
static int matches_live_value(void);
static int matches_full_value(void);

static inline long raw_clock_gettime(timespec_raw *value) {
    long result;
    __asm__ volatile("syscall" : "=a"(result) : "0"(228L), "D"(1L), "S"(value)
                     : "rcx", "r11", "memory");
    return result;
}

static inline long raw_write(int fd, const void *bytes, size_t count) {
    long result;
    __asm__ volatile("syscall" : "=a"(result) : "0"(1L), "D"((long)fd),
                     "S"(bytes), "d"((long)count) : "rcx", "r11", "memory");
    return result;
}

static uint64_t now_ns(void) {
    timespec_raw value;
    if (raw_clock_gettime(&value) != 0) return 0;
    return (uint64_t)value.seconds * 1000000000ull + (uint64_t)value.nanoseconds;
}

static uint64_t time_copy(copy_function volatile *slot, int full_slot) {
    const uint64_t target_ns = 100000000ull;
    uint64_t start = now_ns(), end = start, calls = 0;
    copy_function operation = *slot;
    do {
        operation(destination, source);
        sink += destination[HEADER_BYTES + BENCH_LIVE_BYTES - 1u];
        ++calls;
        if ((calls & 4095u) == 0) end = now_ns();
    } while (end >= start && end - start < target_ns);
    if (full_slot ? !matches_full_value() : !matches_live_value()) __builtin_trap();
    return calls == 0 || end < start ? 0 : (end - start) * 1000 / calls;
}

static void sort(uint64_t values[5]) {
    for (size_t index = 0; index < 5; ++index) {
        for (size_t other = index + 1; other < 5; ++other) {
            if (values[other] < values[index]) {
                uint64_t swap = values[index];
                values[index] = values[other];
                values[other] = swap;
            }
        }
    }
}

static void append_u64(char *output, size_t *at, uint64_t value) {
    char digits[24];
    size_t count = 0;
    do { digits[count++] = (char)('0' + value % 10); value /= 10; } while (value != 0);
    while (count != 0) output[(*at)++] = digits[--count];
}

static void append_text(char *output, size_t *at, const char *value) {
    while (*value) output[(*at)++] = *value++;
}

static int matches_live_value(void) {
    for (size_t index = 0; index < HEADER_BYTES + BENCH_LIVE_BYTES; ++index) {
        if (destination[index] != source[index]) return 0;
    }
    return 1;
}

static int matches_full_value(void) {
    for (size_t index = 0; index < SLOT_BYTES; ++index) {
        if (destination[index] != source[index]) return 0;
    }
    return 1;
}

static uint64_t live_checksum(void) {
    uint64_t value = 1;
    for (size_t index = 0; index < HEADER_BYTES + BENCH_LIVE_BYTES; ++index) {
        value = value * 131u + destination[index];
    }
    return value;
}

static void emit_result(const uint64_t special[5], const uint64_t live[5],
                        const uint64_t full[5], uint64_t checksum) {
    char line[512];
    size_t at = 0;
    append_text(line, &at, "text-copy,");
    append_u64(line, &at, BENCH_MAX_BYTES); line[at++] = ',';
    append_u64(line, &at, BENCH_LIVE_BYTES); line[at++] = ',';
    append_u64(line, &at, SLOT_BYTES); line[at++] = ',';
    /* Print best, median, worst for each path. */
    append_u64(line, &at, special[0]); line[at++] = ',';
    append_u64(line, &at, special[2]); line[at++] = ',';
    append_u64(line, &at, special[4]); line[at++] = ',';
    append_u64(line, &at, special[4] - special[0]); line[at++] = ',';
    append_u64(line, &at, live[0]); line[at++] = ',';
    append_u64(line, &at, live[2]); line[at++] = ',';
    append_u64(line, &at, live[4]); line[at++] = ',';
    append_u64(line, &at, live[4] - live[0]); line[at++] = ',';
    append_u64(line, &at, full[0]); line[at++] = ',';
    append_u64(line, &at, full[2]); line[at++] = ',';
    append_u64(line, &at, full[4]); line[at++] = ',';
    append_u64(line, &at, full[4] - full[0]); line[at++] = ',';
    append_u64(line, &at, live[2] * 1000 / (special[2] ? special[2] : 1)); line[at++] = ',';
    append_u64(line, &at, full[2] * 1000 / (special[2] ? special[2] : 1)); line[at++] = ',';
    append_u64(line, &at, checksum); line[at++] = '\n';
    (void)raw_write(1, line, at);
}

void bench_run(void *context) {
    uint64_t live_length = BENCH_LIVE_BYTES;
    uint64_t live_points = BENCH_LIVE_BYTES;
    for (size_t index = 0; index < SLOT_BYTES + 64; ++index) {
        source[index] = 0;
        destination[index] = 0xA5;
    }
    __builtin_memcpy(source, &live_length, 8);
    __builtin_memcpy(source + 8, &live_points, 8);
    for (size_t index = 0; index < BENCH_LIVE_BYTES; ++index) {
        source[HEADER_BYTES + index] = (unsigned char)('a' + index % 26u);
    }
    bench_special(destination, source);
    if (!matches_live_value()) __builtin_trap();
    uint64_t checksum = live_checksum();
    for (size_t index = 0; index < SLOT_BYTES + 64; ++index) destination[index] = 0xA5;
    bench_generic_live(destination, source);
    if (!matches_live_value() || live_checksum() != checksum) __builtin_trap();
    for (size_t index = 0; index < SLOT_BYTES + 64; ++index) destination[index] = 0xA5;
    bench_generic_full(destination, source);
    if (!matches_full_value() || live_checksum() != checksum) __builtin_trap();

    uint64_t special[5], live[5], full[5];
    for (size_t repeat = 0; repeat < 5; ++repeat) {
        if (repeat % 3u == 0u) {
            special[repeat] = time_copy(&special_copy, 0);
            live[repeat] = time_copy(&live_copy, 0);
            full[repeat] = time_copy(&full_copy, 1);
        } else if (repeat % 3u == 1u) {
            live[repeat] = time_copy(&live_copy, 0);
            full[repeat] = time_copy(&full_copy, 1);
            special[repeat] = time_copy(&special_copy, 0);
        } else {
            full[repeat] = time_copy(&full_copy, 1);
            special[repeat] = time_copy(&special_copy, 0);
            live[repeat] = time_copy(&live_copy, 0);
        }
    }
    sort(special); sort(live); sort(full);
    emit_result(special, live, full, checksum);
    (void)context; (void)sink;
}
'''


def expected_copy_checksum(max_bytes: int, live_bytes: int) -> int:
    data = struct.pack("<QQ", live_bytes, live_bytes)
    data += bytes(ord("a") + index % 26 for index in range(live_bytes))
    checksum = 1
    for value in data:
        checksum = (checksum * 131 + value) & U64_MASK
    return checksum


def parse_copy_result(output: bytes, max_bytes: int, live_bytes: int) -> list[int]:
    try:
        row = output.decode("ascii").strip().split(",")
    except UnicodeDecodeError as error:
        raise RuntimeError(f"Text-copy benchmark output was not ASCII: {output!r}") from error
    if len(row) != 19 or row[0] != "text-copy":
        raise RuntimeError(f"unexpected Text-copy output row: {row!r}")
    try:
        values = [int(value) for value in row[1:]]
    except ValueError as error:
        raise RuntimeError(f"non-integer Text-copy output field: {row!r}") from error
    if values[:3] != [max_bytes, live_bytes, 16 + max_bytes]:
        raise RuntimeError(f"Text-copy shape differs: {row!r}")
    if values[-1] != expected_copy_checksum(max_bytes, live_bytes):
        raise RuntimeError(f"Text-copy checksum differs: {row!r}")
    for start in (3, 7, 11):
        best, median, worst = values[start : start + 3]
        if not 0 < best <= median <= worst:
            raise RuntimeError(f"invalid Text-copy timing triplet: {row!r}")
    if values[6] != values[5] - values[3] or values[10] != values[9] - values[7] or values[14] != values[13] - values[11]:
        raise RuntimeError(f"Text-copy spread does not match best and worst: {row!r}")
    if values[15] != values[8] * 1000 // values[4] or values[16] != values[12] * 1000 // values[4]:
        raise RuntimeError(f"Text-copy ratio does not match medians: {row!r}")
    return values


def is_known_stage0_stack_failure(message: str, executable: Path, max_bytes: int) -> bool:
    expected = (
        f"command failed (1): {executable}\nstdout=\nstderr=main.nl:2:5: data stack exhausted"
    )
    return max_bytes == 4096 and message.rstrip() == expected


def run_text_copy_benchmarks(
    reference: Path,
    selfhost: Path,
    env: dict[str, str],
    work: Path,
    *,
    cpu: int,
    clang: str,
) -> None:
    print("\n## Text-copy microbenchmark")
    print("Baselines: live-slot memcpy copies the 16-byte Text header plus live bytes; full-slot memcpy copies the entire 16-byte header plus maximum byte capacity.")
    for max_bytes in COPY_MAX_BYTES:
        package = work / f"text-copy-{max_bytes}"
        prepare_package(package, text_copy_source(max_bytes))
        stage0 = work / f"text-copy-{max_bytes}-stage0"
        selfhost_exe = work / f"text-copy-{max_bytes}-selfhost"
        base_ir = package / "selfhost.ll"
        compile_with_stage0(reference, package, stage0, env=env)
        compile_with_selfhost(reference, selfhost, package, base_ir, selfhost_exe, env=env)
        expected = b"0\n"
        stage0_output: bytes | None = None
        try:
            stage0_output = checked_output(stage0, env=env, expected=expected)
        except RuntimeError as error:
            if not is_known_stage0_stack_failure(str(error), stage0, max_bytes):
                raise
            print("stage0-output-check=skipped: frozen stage-zero runtime exhausts its fixed data stack at Text max 4096")
        selfhost_output = checked_output(selfhost_exe, env=env, expected=expected)
        if stage0_output is not None and stage0_output != selfhost_output:
            raise RuntimeError(f"stage0 and selfhost Text-copy fixture outputs differ at max={max_bytes}")

        live_sizes = sorted({min(8, max_bytes), max_bytes})
        base_text_ir = base_ir.read_text(encoding="utf-8")
        for live_bytes in live_sizes:
            case = work / f"text-copy-{max_bytes}-live-{live_bytes}"
            case.mkdir()
            ir_path = case / "bench.ll"
            ir_path.write_text(base_text_ir, encoding="utf-8")
            patch_text_copy_ir(ir_path, max_bytes, live_bytes)
            c_path = case / "bench.c"
            c_path.write_text(TEXT_COPY_C, encoding="utf-8")
            object_path = case / "bench.o"
            executable = case / "bench.exe"
            run_process(
                [
                    clang,
                    "-O3",
                    "-fno-builtin",
                    "-fno-stack-protector",
                    "-fno-pie",
                    f"-DBENCH_MAX_BYTES={max_bytes}",
                    f"-DBENCH_LIVE_BYTES={live_bytes}",
                    "-c",
                    str(c_path),
                    "-o",
                    str(object_path),
                ],
                cwd=ROOT,
                env=env,
            )
            run_process(
                [
                    clang,
                    "-O3",
                    "-nostartfiles",
                    "-no-pie",
                    "-Wl,-e,_start",
                    "-Wl,--build-id=none",
                    str(ir_path),
                    str(object_path),
                    "-o",
                    str(executable),
                ],
                cwd=ROOT,
                env=env,
            )
            if not executable.is_file() or not os.access(executable, os.X_OK):
                raise RuntimeError(f"clang did not produce the Text-copy benchmark: {executable}")
            command = pin_command([str(executable)], cpu)
            # Every timed process is also checked; the one-line result is the
            # copied-value checksum followed by the five-sample statistics.
            result = run_process(command, cwd=ROOT, env=env, timeout=120)
            if result.stderr:
                raise RuntimeError(result.stderr.decode(errors="replace"))
            values = parse_copy_result(result.stdout, max_bytes, live_bytes)
            print(",".join(str(value) for value in values))
    print("columns: max_bytes,live_bytes,slot_bytes,special_best_ps,special_median_ps,special_worst_ps,special_spread_ps,live_memcpy_best_ps,live_memcpy_median_ps,live_memcpy_worst_ps,live_memcpy_spread_ps,full_memcpy_best_ps,full_memcpy_median_ps,full_memcpy_worst_ps,full_memcpy_spread_ps,live_over_special_milli,full_over_special_milli,checksum")


def run_bootstrap(reference: Path, env: dict[str, str], work: Path, cpu: int) -> None:
    print("\n## Stage-zero O1 selfhost bootstrap")
    bootstrap_env = env.copy()
    bootstrap_env["NLC_OPT_LEVEL"] = "1"
    samples: list[float] = []
    for index in range(5):
        output = work / f"bootstrap-{index}"
        command = pin_command(
            [str(reference), "--frontend=rust", "build", "selfhost", "-o", str(output)], cpu
        )
        start = time.perf_counter_ns()
        result = run_process(command, cwd=ROOT, env=bootstrap_env, timeout=300)
        elapsed = (time.perf_counter_ns() - start) / 1_000_000_000
        if result.stderr:
            raise RuntimeError(
                f"bootstrap {index + 1} wrote stderr: {result.stderr.decode(errors='replace')[:2000]}"
            )
        if not output.is_file() or not os.access(output, os.X_OK):
            raise RuntimeError(f"bootstrap {index + 1} did not produce an executable: {output}")
        samples.append(elapsed)
    print_time_row("bootstrap", samples)


def inspect_stacks(reference: Path, env: dict[str, str], cpu: int) -> None:
    print("\n## nlc inspect stacks selfhost")
    command = pin_command([str(reference), "--frontend=rust", "inspect", "stacks", "selfhost"], cpu)
    result = run_process(command, cwd=ROOT, env=env, timeout=300)
    if result.stderr:
        raise RuntimeError(f"inspect stacks wrote stderr: {result.stderr.decode(errors='replace')[:2000]}")
    text = result.stdout.decode("utf-8", errors="replace")
    if not text.strip():
        raise RuntimeError("nlc inspect stacks selfhost returned no report")
    print(text.rstrip())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage0", required=True, type=Path, help="fresh release stage-zero nlc")
    parser.add_argument("--selfhost", required=True, type=Path, help="selfhost compiler built from this working tree")
    parser.add_argument("--target-dir", type=Path, default=DEFAULT_TARGET, help="CARGO_TARGET_DIR for link-ir caches")
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK, help="shared exclusive benchmark lock")
    parser.add_argument("--cpu", type=int, default=8)
    parser.add_argument("--iterations", type=int, default=TEXT_ITERATIONS)
    parser.add_argument("--print-every", type=int, default=TEXT_PRINT_EVERY)
    parser.add_argument("--skip-bootstrap", action="store_true")
    parser.add_argument("--skip-stack-report", action="store_true")
    parser.add_argument("--copy-only", action="store_true", help="run only the specialized Text-copy microbenchmarks")
    args = parser.parse_args()

    stage0 = args.stage0.resolve()
    selfhost = args.selfhost.resolve()
    for label, executable in (("stage0", stage0), ("selfhost", selfhost)):
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise RuntimeError(f"{label} executable is missing or not executable: {executable}")
    if args.iterations <= 0 or args.print_every <= 0:
        raise RuntimeError("iterations and print-every must be positive")
    clang = shutil.which("clang")
    if clang is None:
        raise RuntimeError("clang is required for the specialized-copy microbenchmark")
    if not args.lock.parent.is_dir():
        raise RuntimeError(f"benchmark lock directory is missing: {args.lock.parent}")

    target_dir = args.target_dir.resolve()
    target_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["NLC_OPT_LEVEL"] = "3"
    env["CARGO_TARGET_DIR"] = str(target_dir)
    env["NLC_FRONTEND"] = "rust"

    with args.lock.open("a+b") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        print(f"root={ROOT}")
        print(f"stage0={stage0}")
        print(f"selfhost={selfhost}")
        print(f"target_dir={target_dir}")
        print(f"cpu={args.cpu} memory_limit_kib={MEMORY_LIMIT_KIB}")
        with tempfile.TemporaryDirectory(prefix="bench-e3c-text-") as temporary:
            work = Path(temporary)
            if not args.skip_bootstrap:
                run_bootstrap(stage0, env, work, args.cpu)
            if not args.skip_stack_report:
                inspect_stacks(stage0, env, args.cpu)
            if not args.copy_only:
                run_text_benchmark(
                    stage0,
                    selfhost,
                    env,
                    work,
                    iterations=args.iterations,
                    print_every=args.print_every,
                    cpu=args.cpu,
                )
            run_text_copy_benchmarks(stage0, selfhost, env, work, cpu=args.cpu, clang=clang)
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
