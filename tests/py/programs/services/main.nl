// A task using a service through its generated, typed senders.
fn main(env: Env) {
    let counter = Counter_start(3L)
    for index in 0L..10L {
        discard_bool(counter.add(index))
    }
    match counter.get() {
        some(total) => { print(total) },
        none => { print(-1L) },
    }
    match counter.calls() {
        some(calls) => { print(calls) },
        none => { print(-1L) },
    }
    let stopped = counter.stop()
    print(stopped)
}

fn discard_bool(sent: bool) {
    if !sent { print(-2L) }
}
