// Env.http_header reads a header of the request last read on the connection; the server answers with what it found.
fn serve(env: Env, connection: long) {
    var target: Bytes max 64 = Bytes.empty()
    var value: Bytes max 64 = Bytes.empty()
    var body: Bytes max 200 = Bytes.empty()
    while true {
        let method = env.http_read(connection, target)
        if method < 0L { break }
        body = Bytes.empty()
        let user = env.http_header(connection, "X-Test-User", value)
        if user >= 0L {
            discard body.try_append("user=".bytes())
            discard body.try_append(value)
        } else {
            discard body.try_append("no user".bytes())
        }
        let cookie = env.http_header(connection, "cookie", value)
        discard body.try_append(" cookie=".bytes())
        if cookie >= 0L { discard body.try_append(value) } else { discard body.try_append("-".bytes()) }
        if env.http_write(connection, 200L, 2L, body) < 0L { break }
    }
    discard env.net_close(connection)
}

fn main(env: Env) {
    let listener = env.net_listen(18085L)
    while true {
        let connection = env.net_accept(listener)
        if connection < 0L { break }
        spawn serve(env, connection)
    }
}
