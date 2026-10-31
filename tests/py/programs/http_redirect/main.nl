// Env.http_set_header adds header lines to the next response (a redirect is a 302 with a Location; a cookie is a Set-Cookie).
fn serve(env: Env, connection: long) {
    var target: Bytes max 64 = Bytes.empty()
    while true {
        let method = env.http_read(connection, target)
        if method < 0L { break }
        var sent = 0L
        if target.count() == 3L && target[1] == 103 {
            // /go: redirect
            discard env.http_set_header(connection, "Location: /rooms/7")
            sent = env.http_write(connection, 302L, 2L, "")
        } else if target.count() == 7L && target[1] == 99 {
            // /cookie: two cookies, then a body
            discard env.http_set_header(connection, "Set-Cookie: session_token=abc123; HttpOnly; Path=/")
            discard env.http_set_header(connection, "Set-Cookie: theme=dark")
            sent = env.http_write(connection, 200L, 2L, "cookies")
        } else if target.count() == 7L && target[1] == 105 {
            // /inject: a header line with a line break in it is refused, and the response goes out without it
            let refused = env.http_set_header(connection, "X-Evil: yes\r\nSet-Cookie: stolen=1")
            let empty = env.http_set_header(connection, "")
            let no_colon = env.http_set_header(connection, "not a header")
            if refused < 0L && empty < 0L && no_colon < 0L { sent = env.http_write(connection, 200L, 2L, "refused") }
            else { sent = env.http_write(connection, 500L, 2L, "accepted") }
        } else {
            // a header set for one response is not sent with the next
            sent = env.http_write(connection, 200L, 2L, "plain")
        }
        if sent < 0L { break }
    }
    discard env.net_close(connection)
}

fn main(env: Env) {
    let listener = env.net_listen(18086L)
    while true {
        let connection = env.net_accept(listener)
        if connection < 0L { break }
        spawn serve(env, connection)
    }
}
