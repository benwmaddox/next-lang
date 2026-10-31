// Language conveniences found while writing the web workload: struct literals inside a call in a match head, discard of a
// plain value or a mailbox send, while loops.
struct Msg {
    kind: long
    value: long
}

fn double(x: long) -> long {
    x * 2L
}

struct Job {
    id: long
    label: Bytes max 8
    repeat: int
}

fn worker(job: Job, done: Sender<long>) {
    var total = 0L
    for index in 0L..job.repeat.to_long() { total += job.id + index }
    match done.send(total + job.label.count()) {
        ok(_) => {},
        err(_) => {},
    }
}

fn main(env: Env) {
    var box: mailbox<Msg, 4> = mailbox {}
    let inbox = box.receiver()
    // a struct literal as an argument inside a match head
    match box.sender().send(Msg { kind: 1L, value: 21L }) {
        ok(_) => { print(1L) },
        err(_) => { print(-1L) },
    }
    // discard a mailbox send, and a plain number
    discard box.sender().send(Msg { kind: 2L, value: 5L })
    discard double(4L)
    discard env.now_ms()
    match inbox.recv() {
        some(message) => { print(double(message.value)) },
        none => { print(-2L) },
    }
    // a struct literal in an if condition's call
    if double(Msg { kind: 0L, value: 7L }.value) == 14L { print(14L) }
    // while
    var count = 0L
    var total = 0L
    while count < 5L {
        count += 1L
        if count == 2L { continue }
        total += count
        if total > 100L { break }
    }
    print(total)
    var rest = 100L
    while rest > 1L {
        rest = rest / 2L
    }
    print(rest)
    // spawn takes a struct
    var finished: mailbox<long, 4> = mailbox {}
    var label: Bytes max 8 = Bytes.empty()
    discard label.try_append("abc".bytes())
    let job = Job { id: 10L, label: label, repeat: 3 }
    spawn worker(job, finished.sender())
    match finished.receiver().recv_wait() {
        some(value) => { print(value) },
        none => { print(-3L) },
    }
}
