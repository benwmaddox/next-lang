// A blocking HTTP server on one thread: answers every GET with the request target, as text.
fn main(env: Env) {
    let listener = env.net_listen(18080L)
    print(listener >= 0L)
    var target: Bytes max 256 = Bytes.empty()
    for round in 0L..1000000000L {
        let connection = env.net_accept(listener)
        if connection < 0L { break }
        for request in 0L..1000000000L {
            let method = env.http_read(connection, target)
            if method < 0L { break }
            if method == 1L {
                let sent = env.http_write(connection, 200L, 2L, target)
                if sent < 0L { break }
            } else {
                let sent = env.http_write(connection, 400L, 2L, "bad method")
                if sent < 0L { break }
            }
        }
        let closed = env.net_close(connection)
    }
}
