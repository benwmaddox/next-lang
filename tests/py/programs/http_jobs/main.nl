// One job per connection: the acceptor spawns serve(connection); a job waiting for a request suspends instead of
// holding a thread, so a few worker threads serve many connections at once.
fn serve(env: Env, connection: long) {
    var target: Bytes max 256 = Bytes.empty()
    for request in 0L..4000000000L {
        let method = env.http_read(connection, target)
        if method < 0L { break }
        let sent = env.http_write(connection, 200L, 2L, target)
        if sent < 0L { break }
    }
    let closed = env.net_close(connection)
}

fn main(env: Env) {
    let listener = env.net_listen(18083L)
    for round in 0L..4000000000L {
        let connection = env.net_accept(listener)
        if connection < 0L { break }
        spawn serve(env, connection)
    }
}
