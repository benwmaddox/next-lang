; The mailbox ring: a bounded queue with many senders and one receiver, as generated IR. It is the source of
; selfhost/mailbox.nl (the compiler emits these functions, internal, when a program uses a mailbox).
;
; Layout (bytes from the start of the mailbox):
;    0  enqueue position (i64, atomic)      8  capacity (i64)      16  slot stride (i64)     24  element size (i64)
;   64  dequeue position (i64, receiver)    72  wake word (i32)    76  receiver waiting (i32)  80  closed (i32)
;  128  slots: capacity of them, each a sequence number (i64) followed by the element, stride bytes apart
; A slot is free for position p when its sequence is p, and holds a message for position p when it is p + 1; the
; receiver frees it for position p + capacity. Senders claim positions with a compare-and-swap on the enqueue
; position, so any number can send; only the receiver touches the dequeue position. Order is kept per sender.

; @nl.mem.copy(dst, src, bytes) is the program's memory-copy wrapper (defined where maps and pools define it).
declare i32 @nl_park(ptr, i32, i64)
@nl_mbox_spin = external global i64
declare void @nl_wake(ptr, i32)

define internal void @nl.mbox.init(ptr %mb, i64 %capacity, i64 %elem_size) {
entry:
  %stride.raw = add i64 %elem_size, 15
  %stride = and i64 %stride.raw, -8
  store atomic i64 0, ptr %mb monotonic, align 8
  %cap.addr = getelementptr i8, ptr %mb, i64 8
  store i64 %capacity, ptr %cap.addr, align 8
  %stride.addr = getelementptr i8, ptr %mb, i64 16
  store i64 %stride, ptr %stride.addr, align 8
  %size.addr = getelementptr i8, ptr %mb, i64 24
  store i64 %elem_size, ptr %size.addr, align 8
  %deq.addr = getelementptr i8, ptr %mb, i64 64
  store i64 0, ptr %deq.addr, align 8
  %wake.addr = getelementptr i8, ptr %mb, i64 72
  store i32 0, ptr %wake.addr, align 4
  %waiting.addr = getelementptr i8, ptr %mb, i64 76
  store i32 0, ptr %waiting.addr, align 4
  %closed.addr = getelementptr i8, ptr %mb, i64 80
  store i32 0, ptr %closed.addr, align 4
  br label %fill
fill:
  %i = phi i64 [ 0, %entry ], [ %i.next, %fill ]
  %off = mul i64 %i, %stride
  %slot.off = add i64 %off, 128
  %slot = getelementptr i8, ptr %mb, i64 %slot.off
  store atomic i64 %i, ptr %slot release, align 8
  %i.next = add i64 %i, 1
  %more = icmp ult i64 %i.next, %capacity
  br i1 %more, label %fill, label %done
done:
  ret void
}

; Copy one message in. False when the mailbox is full (nothing is written).
define internal i1 @nl.mbox.send(ptr %mb, ptr %elem) {
entry:
  %cap.addr = getelementptr i8, ptr %mb, i64 8
  %cap = load i64, ptr %cap.addr, align 8
  %stride.addr = getelementptr i8, ptr %mb, i64 16
  %stride = load i64, ptr %stride.addr, align 8
  %size.addr = getelementptr i8, ptr %mb, i64 24
  %size = load i64, ptr %size.addr, align 8
  %pos0 = load atomic i64, ptr %mb monotonic, align 8
  br label %try
try:
  %pos = phi i64 [ %pos0, %entry ], [ %pos.retry, %reload ], [ %cas.val, %casfail ]
  %index = urem i64 %pos, %cap
  %off = mul i64 %index, %stride
  %slot.off = add i64 %off, 128
  %slot = getelementptr i8, ptr %mb, i64 %slot.off
  %seq = load atomic i64, ptr %slot acquire, align 8
  %diff = sub i64 %seq, %pos
  %ready = icmp eq i64 %diff, 0
  br i1 %ready, label %claim, label %notready
notready:
  %full = icmp slt i64 %diff, 0
  br i1 %full, label %full.exit, label %reload
reload:
  %pos.retry = load atomic i64, ptr %mb monotonic, align 8
  br label %try
claim:
  %next = add i64 %pos, 1
  %cas = cmpxchg weak ptr %mb, i64 %pos, i64 %next monotonic monotonic, align 8
  %cas.val = extractvalue { i64, i1 } %cas, 0
  %cas.ok = extractvalue { i64, i1 } %cas, 1
  br i1 %cas.ok, label %publish, label %casfail
casfail:
  br label %try
publish:
  %data = getelementptr i8, ptr %slot, i64 8
  %copied.in = call ptr @nl.mem.copy(ptr %data, ptr %elem, i64 %size)
  %published = add i64 %pos, 1
  store atomic i64 %published, ptr %slot release, align 8
  fence seq_cst
  %waiting.addr = getelementptr i8, ptr %mb, i64 76
  %waiting = load atomic i32, ptr %waiting.addr monotonic, align 4
  %anyone = icmp ne i32 %waiting, 0
  br i1 %anyone, label %notify, label %sent
notify:
  %wake.addr = getelementptr i8, ptr %mb, i64 72
  %old = atomicrmw add ptr %wake.addr, i32 1 seq_cst
  call void @nl_wake(ptr %wake.addr, i32 1)
  br label %sent
sent:
  ret i1 true
full.exit:
  ret i1 false
}

; Take the next message if there is one (receiver only).
define internal i1 @nl.mbox.recv(ptr %mb, ptr %out) {
entry:
  %cap.addr = getelementptr i8, ptr %mb, i64 8
  %cap = load i64, ptr %cap.addr, align 8
  %stride.addr = getelementptr i8, ptr %mb, i64 16
  %stride = load i64, ptr %stride.addr, align 8
  %size.addr = getelementptr i8, ptr %mb, i64 24
  %size = load i64, ptr %size.addr, align 8
  %deq.addr = getelementptr i8, ptr %mb, i64 64
  %pos = load i64, ptr %deq.addr, align 8
  %index = urem i64 %pos, %cap
  %off = mul i64 %index, %stride
  %slot.off = add i64 %off, 128
  %slot = getelementptr i8, ptr %mb, i64 %slot.off
  %seq = load atomic i64, ptr %slot acquire, align 8
  %want = add i64 %pos, 1
  %ready = icmp eq i64 %seq, %want
  br i1 %ready, label %take, label %empty
take:
  %data = getelementptr i8, ptr %slot, i64 8
  %copied.out = call ptr @nl.mem.copy(ptr %out, ptr %data, i64 %size)
  %freed = add i64 %pos, %cap
  store atomic i64 %freed, ptr %slot release, align 8
  store i64 %want, ptr %deq.addr, align 8
  ret i1 true
empty:
  ret i1 false
}

; Take the next message, parking the receiver while there is none. False once the mailbox is closed and drained.
define internal i1 @nl.mbox.recv_wait(ptr %mb, ptr %out) {
entry:
  br label %again
again:
  %got = call i1 @nl.mbox.recv(ptr %mb, ptr %out)
  br i1 %got, label %yes, label %check
check:
  %closed.addr = getelementptr i8, ptr %mb, i64 80
  %closed = load atomic i32, ptr %closed.addr acquire, align 4
  %is.closed = icmp ne i32 %closed, 0
  br i1 %is.closed, label %drain, label %spin
; Spin briefly before sleeping: a message that arrives within a few microseconds then costs no futex wake.
spin:
  %spin.i = phi i64 [ 0, %check ], [ %spin.next, %spin.again ]
  %spin.got = call i1 @nl.mbox.recv(ptr %mb, ptr %out)
  br i1 %spin.got, label %yes, label %spin.again
spin.again:
  %spin.next = add i64 %spin.i, 1
  %spin.limit = load i64, ptr @nl_mbox_spin, align 8
  %spin.more = icmp ult i64 %spin.next, %spin.limit
  br i1 %spin.more, label %spin, label %prepare
prepare:
  %wake.addr = getelementptr i8, ptr %mb, i64 72
  %waiting.addr = getelementptr i8, ptr %mb, i64 76
  %ticket = load atomic i32, ptr %wake.addr seq_cst, align 4
  store atomic i32 1, ptr %waiting.addr seq_cst, align 4
  fence seq_cst
  %again.got = call i1 @nl.mbox.recv(ptr %mb, ptr %out)
  br i1 %again.got, label %got.clear, label %sleep
sleep:
  %closed2 = load atomic i32, ptr %closed.addr acquire, align 4
  %is.closed2 = icmp ne i32 %closed2, 0
  br i1 %is.closed2, label %closed.clear, label %park
park:
  %parked = call i32 @nl_park(ptr %wake.addr, i32 %ticket, i64 -1)
  store atomic i32 0, ptr %waiting.addr seq_cst, align 4
  br label %again
got.clear:
  store atomic i32 0, ptr %waiting.addr seq_cst, align 4
  ret i1 true
closed.clear:
  store atomic i32 0, ptr %waiting.addr seq_cst, align 4
  br label %drain
drain:
  %last = call i1 @nl.mbox.recv(ptr %mb, ptr %out)
  ret i1 %last
yes:
  ret i1 true
}

; No more messages will be sent: wake the receiver, which sees the end once it has drained what was sent.
define internal void @nl.mbox.close(ptr %mb) {
entry:
  %closed.addr = getelementptr i8, ptr %mb, i64 80
  store atomic i32 1, ptr %closed.addr seq_cst, align 4
  %wake.addr = getelementptr i8, ptr %mb, i64 72
  %old = atomicrmw add ptr %wake.addr, i32 1 seq_cst
  call void @nl_wake(ptr %wake.addr, i32 2147483647)
  ret void
}
