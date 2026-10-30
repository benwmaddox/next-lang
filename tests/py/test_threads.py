"""Thread start/join, park/wake and locked output in the C runtime, driven by hand-written IR."""

import os
import pathlib
import subprocess
import tempfile
import unittest

from support import ROOT

HEADER = "; nlc-link-ir 2\n; nlc.build program\n; nlc.stack offset\n; nlc.recursion none\n; nlc.runtime c\nsource_filename = \"threads\"\n"

COMMON = r'''
@entry = private unnamed_addr constant [8 x i8] c"threads\00"
declare ptr @nl_context_create(i64, i64, ptr)
declare void @nl_context_destroy(ptr)
declare ptr @nl_thread_start(ptr, ptr, i64, i64)
declare i64 @nl_thread_join(ptr)
declare i32 @nl_park(ptr, i32, i64)
declare void @nl_wake(ptr, i32)
declare void @nl_print_int(i32)
'''

START_CONTEXT = '''  %ctx = call ptr @nl_context_create(i64 262144, i64 0, ptr getelementptr inbounds ([8 x i8], ptr @entry, i64 0, i64 0))
'''
END = '''  call void @nl_context_destroy(ptr %ctx)
  ret i32 0
}
'''


def start_and_join(count, entry, pin="-1"):
    """IR text starting `count` threads at @entry and joining them all."""
    lines = []
    for index in range(count):
        lines.append(f"  %t{index} = call ptr @nl_thread_start(ptr @{entry}, ptr null, i64 0, i64 {pin if pin != 'index' else index})")
    for index in range(count):
        lines.append(f"  %j{index} = call i64 @nl_thread_join(ptr %t{index})")
    return "\n".join(lines) + "\n"


COUNTER = COMMON + r'''
@counter = global i32 0
define ptr @worker(ptr %arg) {
entry:
  br label %loop
loop:
  %i = phi i32 [ 0, %entry ], [ %next, %loop ]
  %old = atomicrmw add ptr @counter, i32 1 seq_cst
  %next = add i32 %i, 1
  %done = icmp eq i32 %next, 100000
  br i1 %done, label %exit, label %loop
exit:
  ret ptr null
}
define i32 @main(i32 %argc, ptr %argv, ptr %envp) {
entry:
''' + START_CONTEXT + "@@START@@" + r'''  %total = load atomic i32, ptr @counter seq_cst, align 4
  call void @nl_print_int(i32 %total)
''' + END

PRINTS = COMMON + r'''
define ptr @printer(ptr %arg) {
entry:
  br label %loop
loop:
  %i = phi i32 [ 0, %entry ], [ %next, %loop ]
  call void @nl_print_int(i32 %i)
  %next = add i32 %i, 1
  %done = icmp eq i32 %next, 500
  br i1 %done, label %exit, label %loop
exit:
  ret ptr null
}
define i32 @main(i32 %argc, ptr %argv, ptr %envp) {
entry:
''' + START_CONTEXT + "@@START@@" + END

PARK = COMMON + r'''
@flag = global i32 0
@never = global i32 0
define ptr @setter(ptr %arg) {
entry:
  store atomic i32 1, ptr @flag seq_cst, align 4
  call void @nl_wake(ptr @flag, i32 1)
  ret ptr null
}
define i32 @main(i32 %argc, ptr %argv, ptr %envp) {
entry:
''' + START_CONTEXT + r'''  %t = call ptr @nl_thread_start(ptr @setter, ptr null, i64 0, i64 -1)
  br label %wait
wait:
  %seen = load atomic i32, ptr @flag seq_cst, align 4
  %set = icmp ne i32 %seen, 0
  br i1 %set, label %woken, label %sleep
sleep:
  %r = call i32 @nl_park(ptr @flag, i32 0, i64 -1)
  br label %wait
woken:
  %j = call i64 @nl_thread_join(ptr %t)
  call void @nl_print_int(i32 %seen)
  %timed = call i32 @nl_park(ptr @never, i32 0, i64 20000000)
  call void @nl_print_int(i32 %timed)
''' + END


def run_ir(body):
    with tempfile.TemporaryDirectory(prefix="nl-threads-") as temporary:
        directory = pathlib.Path(temporary)
        (directory / "threads.ll").write_text(HEADER + body)
        if os.name == "nt":
            link = ["pwsh", "-NoProfile", "-File", str(ROOT / "scripts" / "nlc.ps1"), "link", "threads.ll", "-o", "threads.exe"]
            program = [str(directory / "threads.exe")]
        else:
            link = [str(ROOT / "scripts" / "nlc"), "link-ir", "threads.ll", "-o", "threads"]
            program = [str(directory / "threads")]
        linked = subprocess.run(link, cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if linked.returncode != 0:
            raise AssertionError(linked.stderr.decode(errors="replace") + linked.stdout.decode(errors="replace"))
        return subprocess.run(program, cwd=directory, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


class Threads(unittest.TestCase):
    def test_threads_run_concurrently_and_join(self):
        ran = run_ir(COUNTER.replace("@@START@@", start_and_join(4, "worker")))
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        self.assertEqual(ran.stdout.decode().split(), ["400000"])

    def test_pinning_to_positions_still_works(self):
        ran = run_ir(COUNTER.replace("@@START@@", start_and_join(4, "worker", pin="index")))
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        self.assertEqual(ran.stdout.decode().split(), ["400000"])

    def test_concurrent_output_lines_stay_whole(self):
        ran = run_ir(PRINTS.replace("@@START@@", start_and_join(4, "printer")))
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        lines = ran.stdout.decode().replace("\r\n", "\n").split("\n")
        self.assertEqual(lines.pop(), "")
        self.assertEqual(len(lines), 4 * 500)
        counts = {}
        for line in lines:
            self.assertTrue(line.isdigit() and 0 <= int(line) < 500, f"torn line {line!r}")
            counts[int(line)] = counts.get(int(line), 0) + 1
        self.assertTrue(all(counts[value] == 4 for value in range(500)))

    def test_park_wakes_and_times_out(self):
        ran = run_ir(PARK)
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        # the flag was seen set; parking on an unchanging word times out (1)
        self.assertEqual(ran.stdout.decode().split(), ["1", "1"])


if __name__ == "__main__":
    unittest.main()
