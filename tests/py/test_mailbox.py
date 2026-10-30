"""The mailbox ring (selfhost/mailbox_ring.ll) with several sender threads and one receiver, as hand-written IR.

Four threads send 20,000 numbered messages each into a 64-slot mailbox (so senders do find it full and retry);
the main thread receives all 80,000 and checks that every sender's messages arrive in order, that none is lost
or duplicated, and that a closed, drained mailbox ends the receiver."""

import os
import pathlib
import subprocess
import tempfile
import unittest

from support import ROOT

RING = (ROOT / "selfhost" / "mailbox_ring.ll").read_text()
SENDERS = 4
PER_SENDER = 20000
CAPACITY = 64
STRIDE = 16  # 8 for the sequence number, 8 for the i64 message
STORAGE = 128 + CAPACITY * STRIDE

HEADER = '; nlc-link-ir 2\n; nlc.build program\n; nlc.stack offset\n; nlc.recursion none\n; nlc.runtime c\nsource_filename = "mailbox"\n'

PROGRAM = RING + f'''
@entry = private unnamed_addr constant [8 x i8] c"mailbox\\00"
@mailbox = global [{STORAGE} x i8] zeroinitializer, align 64
@pause = global i32 0
declare ptr @nl_context_create(i64, i64, ptr)
declare void @nl_context_destroy(ptr)
declare ptr @nl_thread_start(ptr, ptr, i64, i64)
declare i64 @nl_thread_join(ptr)
declare void @nl_print_long(i64)

define ptr @sender(ptr %arg) {{
entry:
  %id = ptrtoint ptr %arg to i64
  %message = alloca i64, align 8
  br label %next
next:
  %i = phi i64 [ 0, %entry ], [ %i.next, %sent ]
  %shifted = shl i64 %id, 32
  %value = or i64 %shifted, %i
  store i64 %value, ptr %message, align 8
  br label %try
try:
  %ok = call i1 @nl.mbox.send(ptr @mailbox, ptr %message)
  br i1 %ok, label %sent, label %full
full:
  %slept = call i32 @nl_park(ptr @pause, i32 0, i64 20000)
  br label %try
sent:
  %i.next = add i64 %i, 1
  %more = icmp ult i64 %i.next, {PER_SENDER}
  br i1 %more, label %next, label %done
done:
  ret ptr null
}}

define i32 @main(i32 %argc, ptr %argv, ptr %envp) {{
entry:
  %ctx = call ptr @nl_context_create(i64 262144, i64 0, ptr getelementptr inbounds ([8 x i8], ptr @entry, i64 0, i64 0))
  call void @nl.mbox.init(ptr @mailbox, i64 {CAPACITY}, i64 8)
  %last = alloca [{SENDERS} x i64], align 8
  br label %zero
zero:
  %z = phi i64 [ 0, %entry ], [ %z.next, %zero ]
  %z.addr = getelementptr i64, ptr %last, i64 %z
  store i64 -1, ptr %z.addr, align 8
  %z.next = add i64 %z, 1
  %z.more = icmp ult i64 %z.next, {SENDERS}
  br i1 %z.more, label %zero, label %start
start:
''' + "".join(
    f"  %t{n} = call ptr @nl_thread_start(ptr @sender, ptr inttoptr (i64 {n} to ptr), i64 0, i64 -1)\n" for n in range(SENDERS)
) + f'''  %message = alloca i64, align 8
  br label %receive
receive:
  %count = phi i64 [ 0, %start ], [ %count.next, %checked ]
  %errors = phi i64 [ 0, %start ], [ %errors.next, %checked ]
  %got = call i1 @nl.mbox.recv_wait(ptr @mailbox, ptr %message)
  br i1 %got, label %check, label %ended
check:
  %v = load i64, ptr %message, align 8
  %sender = lshr i64 %v, 32
  %seq = and i64 %v, 4294967295
  %slot = getelementptr i64, ptr %last, i64 %sender
  %prev = load i64, ptr %slot, align 8
  %expect = add i64 %prev, 1
  %in.order = icmp eq i64 %seq, %expect
  %bad = zext i1 %in.order to i64
  %bad.flip = xor i64 %bad, 1
  store i64 %seq, ptr %slot, align 8
  %errors.next = add i64 %errors, %bad.flip
  br label %checked
checked:
  %count.next = add i64 %count, 1
  %keep = icmp ult i64 %count.next, {SENDERS * PER_SENDER}
  br i1 %keep, label %receive, label %finish
finish:
''' + "".join(f"  %j{n} = call i64 @nl_thread_join(ptr %t{n})\n" for n in range(SENDERS)) + f'''  call void @nl.mbox.close(ptr @mailbox)
  %after = call i1 @nl.mbox.recv_wait(ptr @mailbox, ptr %message)
  %after.int = zext i1 %after to i64
  call void @nl_print_long(i64 %count.next)
  call void @nl_print_long(i64 %errors.next)
  call void @nl_print_long(i64 %after.int)
  call void @nl_context_destroy(ptr %ctx)
  ret i32 0
ended:
  call void @nl_print_long(i64 -1)
  ret i32 1
}}
'''


def run_program():
    with tempfile.TemporaryDirectory(prefix="nl-mailbox-") as temporary:
        directory = pathlib.Path(temporary)
        (directory / "mailbox.ll").write_text(HEADER + PROGRAM)
        if os.name == "nt":
            link = ["pwsh", "-NoProfile", "-File", str(ROOT / "scripts" / "nlc.ps1"), "link", "mailbox.ll", "-o", "mailbox.exe"]
            program = [str(directory / "mailbox.exe")]
        else:
            link = [str(ROOT / "scripts" / "nlc"), "link-ir", "mailbox.ll", "-o", "mailbox"]
            program = [str(directory / "mailbox")]
        linked = subprocess.run(link, cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if linked.returncode != 0:
            raise AssertionError(linked.stderr.decode(errors="replace") + linked.stdout.decode(errors="replace"))
        return subprocess.run(program, cwd=directory, timeout=120, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


class MailboxRing(unittest.TestCase):
    def test_many_senders_one_receiver_keep_per_sender_order(self):
        for attempt in range(3):  # a race would show up as a lost, duplicated or reordered message
            ran = run_program()
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace") + ran.stdout.decode(errors="replace"))
            self.assertEqual(ran.stdout.decode().split(), [str(SENDERS * PER_SENDER), "0", "0"], f"attempt {attempt}")


if __name__ == "__main__":
    unittest.main()
