// A task using a service through its generated, typed senders.
fn main(env: Env) {
    let counter = Counter_start(3L)
    for index in 0L..10L {
        discard_bool(Counter_add(counter, index))
    }
    match Counter_get(counter) {
        some(total) => { print(total) },
        none => { print(-1L) },
    }
    match Counter_calls(counter) {
        some(calls) => { print(calls) },
        none => { print(-1L) },
    }
    let stopped = Counter_stop(counter)
    print(stopped)
}

fn discard_bool(sent: bool) {
    if !sent { print(-2L) }
}
