#!/usr/bin/env python3
"""Check the embedded memory functions against byte-wise reference loops."""

from __future__ import annotations

from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
NLC = Path.home() / ".cache/next-lang/target/debug/nlc"

CHECK_SOURCE = r'''#include <stddef.h>
#include <stdint.h>

extern void *core_memcpy(void *, const void *, size_t);
extern void *core_memmove(void *, const void *, size_t);
extern void *core_memset(void *, int, size_t);
extern int core_memcmp(const void *, const void *, size_t);
extern int core_bcmp(const void *, const void *, size_t);

static unsigned char pattern(size_t index) {
    return (unsigned char)(index * 37u + 11u);
}

static int same(const unsigned char *left, const unsigned char *right,
                size_t count) {
    for (size_t index = 0; index < count; ++index) {
        if (left[index] != right[index]) return 0;
    }
    return 1;
}

static void seed(unsigned char *bytes, size_t count) {
    for (size_t index = 0; index < count; ++index) bytes[index] = pattern(index);
}

int memory_check_run(void) {
    unsigned char source[512];
    unsigned char destination[512];
    unsigned char expected[512];
    unsigned char left[512];
    unsigned char right[512];

    for (size_t count = 0; count <= 300; ++count) {
        for (size_t dst_align = 0; dst_align < 16; ++dst_align) {
            for (size_t src_align = 0; src_align < 16; ++src_align) {
                seed(source, sizeof(source));
                seed(destination, sizeof(destination));
                for (size_t index = 0; index < sizeof(destination); ++index) {
                    expected[index] = destination[index];
                }
                for (size_t index = 0; index < count; ++index) {
                    expected[32 + dst_align + index] =
                        source[32 + src_align + index];
                }
                unsigned char *dst = destination + 32 + dst_align;
                const unsigned char *src = source + 32 + src_align;
                if (core_memcpy(dst, src, count) != dst) return 1;
                if (!same(destination, expected, sizeof(destination))) return 2;

                seed(destination, sizeof(destination));
                for (size_t index = 0; index < sizeof(destination); ++index) {
                    expected[index] = destination[index];
                }
                for (size_t index = 0; index < count; ++index) {
                    expected[32 + dst_align + index] = 0xadu;
                }
                if (core_memset(dst, 0x1ad, count) != dst) return 3;
                if (!same(destination, expected, sizeof(destination))) return 4;

                for (size_t index = 0; index < sizeof(left); ++index) {
                    left[index] = pattern(index + 5);
                    right[index] = left[index];
                }
                for (size_t index = 0; index < count; ++index) {
                    left[32 + dst_align + index] = pattern(index + 5);
                    right[32 + src_align + index] = pattern(index + 5);
                }
                const unsigned char *a = left + 32 + dst_align;
                const unsigned char *b = right + 32 + src_align;
                if (core_memcmp(a, b, count) != 0) return 5;
                if (core_bcmp(a, b, count) != 0) return 6;
                if (count != 0) {
                    size_t differing = count / 2;
                    left[32 + dst_align + differing] = 0x31u;
                    right[32 + src_align + differing] = 0x32u;
                    if (core_memcmp(a, b, count) >= 0) return 7;
                    if (core_bcmp(a, b, count) == 0) return 8;
                    left[32 + dst_align + differing] = 0x32u;
                    right[32 + src_align + differing] = 0x31u;
                    if (core_memcmp(a, b, count) <= 0) return 9;
                }
            }
        }

        for (size_t alignment = 0; alignment < 16; ++alignment) {
            for (int direction = 0; direction < 2; ++direction) {
                seed(destination, sizeof(destination));
                for (size_t index = 0; index < sizeof(destination); ++index) {
                    expected[index] = destination[index];
                }
                size_t src_at = 96 + alignment + (direction == 0 ? 0 : 1);
                size_t dst_at = 96 + alignment + (direction == 0 ? 1 : 0);
                if (dst_at > src_at) {
                    for (size_t index = count; index > 0; --index) {
                        expected[dst_at + index - 1] = expected[src_at + index - 1];
                    }
                } else {
                    for (size_t index = 0; index < count; ++index) {
                        expected[dst_at + index] = expected[src_at + index];
                    }
                }
                if (core_memmove(destination + dst_at, destination + src_at, count)
                    != destination + dst_at) return 10;
                if (!same(destination, expected, sizeof(destination))) return 11;
            }
        }
    }
    return 0;
}
'''


def run(command: list[str], *, timeout: int) -> subprocess.CompletedProcess[bytes]:
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
    return result


def patch_module(ir: Path) -> None:
    source = ir.read_text()
    main = re.compile(
        r"^define i32 @main\(i32 %argc, ptr %argv, ptr %envp\) \{\n.*?^\}\n",
        re.MULTILINE | re.DOTALL,
    )
    replacement = '''declare i32 @memory_check_run()

define i32 @main(i32 %argc, ptr %argv, ptr %envp) {
entry:
  call void @nl_core_init(i32 %argc, ptr %argv, ptr %envp)
  %status = call i32 @memory_check_run()
  ret i32 %status
}
'''
    source, count = main.subn(replacement, source, count=1)
    if count != 1:
        raise RuntimeError("could not find core-mode main in memory-check IR")
    additions = '''
define ptr @core_memcpy(ptr %dst, ptr %src, i64 %count) noinline {
entry:
  %result = call ptr @memcpy(ptr %dst, ptr %src, i64 %count)
  ret ptr %result
}

define ptr @core_memmove(ptr %dst, ptr %src, i64 %count) noinline {
entry:
  %result = call ptr @memmove(ptr %dst, ptr %src, i64 %count)
  ret ptr %result
}

define ptr @core_memset(ptr %dst, i32 %value, i64 %count) noinline {
entry:
  %result = call ptr @memset(ptr %dst, i32 %value, i64 %count)
  ret ptr %result
}

define i32 @core_memcmp(ptr %left, ptr %right, i64 %count) noinline {
entry:
  %result = call i32 @memcmp(ptr %left, ptr %right, i64 %count)
  ret i32 %result
}

define i32 @core_bcmp(ptr %left, ptr %right, i64 %count) noinline {
entry:
  %result = call i32 @bcmp(ptr %left, ptr %right, i64 %count)
  ret i32 %result
}
'''
    marker = "; nlc-link-ir end"
    if marker not in source:
        raise RuntimeError("memory-check IR has no link-ir end marker")
    ir.write_text(source.replace(marker, additions + "\n" + marker, 1))


def main() -> int:
    if not NLC.is_file():
        raise RuntimeError(f"nlc is missing: {NLC}; run cargo build first")
    clang = shutil.which("clang")
    if not clang:
        raise RuntimeError("clang is not on PATH")

    work = Path(tempfile.mkdtemp(prefix=".core-memory-check-", dir=ROOT))
    try:
        relative = work.relative_to(ROOT).as_posix()
        ir = work / "memory.ll"
        shim = work / "memory-check.c"
        obj = work / "memory-check.o"
        shim.write_text(CHECK_SOURCE)
        run(
            [str(NLC), "run", "selfhost", "--", "build", "bench/memfn", "-o", f"{relative}/memory.ll"],
            timeout=300,
        )
        patch_module(ir)
        run(
            [clang, "-O2", "-fno-builtin", "-fno-stack-protector", "-fno-pie", "-c", str(shim), "-o", str(obj)],
            timeout=120,
        )
        for optimization in ("1", "3"):
            executable = work / f"memory-O{optimization}"
            run(
                [clang, f"-O{optimization}", "-nostartfiles", "-no-pie", "-Wl,-e,_start", "-Wl,--build-id=none", str(ir), str(obj), "-o", str(executable)],
                timeout=180,
            )
            run([str(executable)], timeout=300)
            print(f"memory correctness passed at O{optimization} (sizes 0..300, alignments 0..15, both memmove overlaps)")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=__import__("sys").stderr)
        raise SystemExit(1)
