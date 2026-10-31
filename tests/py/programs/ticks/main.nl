// recv_for waits at most a number of milliseconds; a service with `tick every` runs at a fixed rate.
fn wait_ms(env: Env, ms: long) {
    var nobody: mailbox<long, 1> = mailbox {}
    let inbox = nobody.receiver()
    match inbox.recv_for(ms) {
        some(_) => {},
        none => {},
    }
    nobody.release()
}

fn main(env: Env) {
    // a timeout returns none, after about the time given
    var box: mailbox<long, 4> = mailbox {}
    let inbox = box.receiver()
    let started = env.now_ms()
    match inbox.recv_for(50L) {
        some(_) => { print(-1L) },
        none => { print(0L) },
    }
    let waited = env.now_ms() - started
    print(waited >= 45L && waited < 150L)
    print(inbox.is_closed())
    // a message that arrives in time is returned at once
    match box.sender().send(7L) {
        ok(_) => {},
        err(_) => {},
    }
    match inbox.recv_for(1000L) {
        some(value) => { print(value) },
        none => { print(-2L) },
    }
    box.sender().close()
    print(inbox.is_closed())
    // a service ticking every 20 ms, observed for about 210 ms
    let ticker = Ticker_start(env)
    wait_ms(env, 210L)
    match Ticker_count(ticker) {
        some(ticks) => { print(ticks >= 7L && ticks <= 11L) },
        none => { print(-3L) },
    }
    match Ticker_missed(ticker) {
        some(missed) => { print(missed < 3L) },
        none => { print(-4L) },
    }
    let stopped = Ticker_stop(ticker)
    // the idler: messages are handled between idle steps, and the backlog is worked off while it is quiet
    let idler = Idler_start(env)
    for index in 0L..5L {
        if !Idler_note(idler) { print(-5L) }
    }
    wait_ms(env, 100L)
    match Idler_report(idler) {
        some(report) => { print(report) },
        none => { print(-6L) },
    }
    let idler_stopped = Idler_stop(idler)
}
