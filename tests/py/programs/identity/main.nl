// Env.http_body, Env.http_peer, Env.random_token, Env.password_verify and Env.db_exec, one path each.
struct Note {
    owner: long
    text: Bytes max 64
}

struct Owner {
    owner: long
}

fn serve(env: Env, connection: long) {
    var target: Bytes max 64 = Bytes.empty()
    while true {
        let method = env.http_read(connection, target)
        if method < 0L { break }
        var sent = 0L
        if target.count() == 5L && target[1] == 101 {
            // /echo: the request body, and the method code
            var body: Bytes max 256 = Bytes.empty()
            let size = env.http_body(connection, body)
            sent = env.http_write(connection, 220L + method, 2L, body)
        } else if target.count() == 5L && target[1] == 112 {
            // /peer
            var peer: Bytes max 64 = Bytes.empty()
            discard env.http_peer(connection, peer)
            sent = env.http_write(connection, 200L, 2L, peer)
        } else if target.count() == 6L && target[1] == 116 {
            // /token: 24 random characters
            var token: Bytes max 32 = Bytes.empty()
            discard env.random_token(24L, token)
            sent = env.http_write(connection, 200L, 2L, token)
        } else if target.count() == 7L && target[1] == 118 {
            // /verify: the body is the password
            var body: Bytes max 256 = Bytes.empty()
            discard env.http_body(connection, body)
            var hash: Bytes max 80 = Bytes.empty()
            discard hash.try_append("$2a$04$dcz.lzds.VCqQ5p7isC1l.H1xOKqPl1yyxP5kt5VQq3EbJn4Rocn.".bytes())
            sent = env.http_write(connection, if env.password_verify(hash, body) { 200L } else { 403L }, 2L, "")
        } else if target.count() == 5L && target[1] == 110 {
            // /note: insert a note owned by 7 with the body as its text; answer how many notes 7 has now
            var body: Bytes max 256 = Bytes.empty()
            discard env.http_body(connection, body)
            var note = Note { owner: 7L, text: Bytes.empty() }
            discard note.text.try_append(body)
            let inserted = env.db_exec("insert into notes (owner, text) values (?1, ?2)", note)
            let owner = Owner { owner: 7L }
            let removed = if method == 4L { env.db_exec("delete from notes where owner = ?1", owner) } else { 0L }
            var out: Bytes max 32 = Bytes.empty()
            discard out.try_append(str(inserted).bytes())
            discard out.try_append(b",")
            discard out.try_append(str(removed).bytes())
            sent = env.http_write(connection, 200L, 2L, out)
        } else {
            sent = env.http_write(connection, 404L, 2L, "")
        }
        if sent < 0L { break }
    }
    discard env.net_close(connection)
}

fn main(env: Env) {
    let listener = env.net_listen(18087L)
    while true {
        let connection = env.net_accept(listener)
        if connection < 0L { break }
        spawn serve(env, connection)
    }
}
