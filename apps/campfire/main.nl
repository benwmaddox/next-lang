// Campfire (ONCE Campfire, Rails 90b3300) in next-lang. Slice 1: reading. The data is the Rails tables (schema.sql); the
// pages are templates (pages.tpl). One task per connection reads the request, finds the user from the session cookie, and
// answers GET / (the rooms you are in) and GET /rooms/:id (the room's last 40 messages).
const PORT: long = 18090L

struct User {
    id: long = 0L
    name: Bytes max 32 = Bytes.empty()
}

struct Room {
    id: long = 0L
    name: Bytes max 64 = Bytes.empty()
    kind: Bytes max 32 = Bytes.empty()
}

struct Message {
    id: long
    client_message_id: Bytes max 40
    created_at: Bytes max 32
    creator_id: long
    author: Bytes max 32
    body: Bytes max 2048
}

struct Token {
    value: Bytes max 64
}

struct Email {
    value: Bytes max 128
}

struct Credential {
    id: long = 0L
    digest: Bytes max 80 = Bytes.empty()
}

struct NewSession {
    user_id: long
    token: Bytes max 64
    ip: Bytes max 64
    agent: Bytes max 256
}

struct Membership {
    id: long = 0L
}

struct RoomAndUser {
    room_id: long
    user_id: long
}

type Page = Bytes max 196608

// The value of the cookie `name` in a Cookie header ("a=1; session_token=abc; b=2"), or an empty value.
fn cookie_value(cookie: Bytes max 512, name: Ascii max 32) -> Bytes max 64 {
    var found: Bytes max 64 = Bytes.empty()

    var start = 0L
    while start < cookie.count() {
        // a pair runs to the next ';' and may be preceded by spaces
        var end = start
        while end < cookie.count() && cookie[end] != 59 { end += 1L }
        var first = start
        while first < end && cookie[first] == 32 { first += 1L }
        var matches = end - first > name.len() && cookie[first + name.len()] == 61
        for index in 0L..name.len() {
            if matches && cookie[first + index] != name[index] { matches = false }
        }
        if matches {
            for index in first + name.len() + 1L..end { discard found.push(cookie[index]) }
            return found
        }
        start = end + 1L
    }
    found
}

fn hex_value(c: byte) -> long {
    let v = c.to_long()
    if v >= 48L && v <= 57L { return v - 48L }
    if v >= 65L && v <= 70L { return v - 55L }
    if v >= 97L && v <= 102L { return v - 87L }
    -1L
}

// The value of the field `name` in a form body ("a=1&email_address=x%40y.com"), decoded; empty when absent.
fn form_value(body: Bytes max 1024, name: Ascii max 32) -> Bytes max 128 {
    var found: Bytes max 128 = Bytes.empty()
    var start = 0L
    while start < body.count() {
        var end = start
        while end < body.count() && body[end] != 38 { end += 1L }
        var matches = end - start > name.len() && body[start + name.len()] == 61
        for index in 0L..name.len() {
            if matches && body[start + index] != name[index] { matches = false }
        }
        if matches {
            var at = start + name.len() + 1L
            while at < end {
                let c = body[at].to_long()
                if c == 43L {
                    discard found.push((byte)32)
                } else if c == 37L && at + 2L < end && hex_value(body[at + 1L]) >= 0L && hex_value(body[at + 2L]) >= 0L {
                    discard found.push((byte)(hex_value(body[at + 1L]) * 16L + hex_value(body[at + 2L])))
                    at += 2L
                } else {
                    discard found.push(body[at])
                }
                at += 1L
            }
            return found
        }
        start = end + 1L
    }
    found
}

fn target_is(target: Bytes max 256, text: Ascii max 32) -> bool {
    if target.count() != text.len() { return false }
    for index in 0L..text.len() {
        if target[index] != text[index] { return false }
    }
    true
}

// A 303 to `location` (a header line such as "Location: /session/new"), with the cookie line when there is one.
fn redirect(env: Env, connection: long, location: Ascii max 64, cookie: Bytes max 128) -> bool {
    if cookie.count() > 0L { discard env.http_set_header(connection, cookie) }
    discard env.http_set_header(connection, location)
    env.http_write(connection, 303L, 2L, "") >= 0L
}

// Sign in: the form's email address and password. On success a session row, its cookie, and a redirect home; otherwise
// back to the form. A deactivated user (status 1) is never found.
fn sign_in(env: Env, connection: long) -> bool {
    var body: Bytes max 1024 = Bytes.empty()
    discard env.http_body(connection, body)
    let email = Email { value: form_value(body, "email_address") }
    let password = form_value(body, "password")
    var credential = Credential {}
    var accepted = false
    if email.value.count() > 0L && password.count() > 0L {
        let found = env.db_row("""
            from (select id, coalesce(password_digest, '') as digest from users where email_address = ?1 and status = 0)
        """, email, credential)
        accepted = found && env.password_verify(credential.digest, password)
    }
    if !accepted { return redirect(env, connection, "Location: /session/new?failed=1", Bytes.empty()) }
    var session = NewSession { user_id: credential.id, token: Bytes.empty(), ip: Bytes.empty(), agent: Bytes.empty() }
    discard env.random_token(32L, session.token)
    discard env.http_peer(connection, session.ip)
    discard env.http_header(connection, "User-Agent", session.agent)
    discard env.db_exec("""
        insert into sessions (user_id, token, ip_address, user_agent, last_active_at, created_at, updated_at)
        values (?1, ?2, ?3, ?4, datetime('now'), datetime('now'), datetime('now'))
    """, session)
    var line: Bytes max 128 = Bytes.empty()
    discard line.try_append("Set-Cookie: session_token=".bytes())
    discard line.try_append(session.token)
    discard line.try_append("; HttpOnly; Path=/; SameSite=Lax".bytes())
    redirect(env, connection, "Location: /", line)
}

// Sign out: the session row goes and the cookie is cleared.
fn sign_out(env: Env, connection: long) -> bool {
    var cookie: Bytes max 512 = Bytes.empty()
    discard env.http_header(connection, "Cookie", cookie)
    let token = Token { value: cookie_value(cookie, "session_token") }
    discard env.db_exec("delete from sessions where token = ?1", token)
    var line: Bytes max 128 = Bytes.empty()
    discard line.try_append("Set-Cookie: session_token=; Max-Age=0; HttpOnly; Path=/".bytes())
    redirect(env, connection, "Location: /session/new", line)
}

// The digits after "/rooms/" in a target, or -1.
fn room_id(target: Bytes max 256) -> long {
    if target.count() < 8L || target.count() > 24L { return -1L }
    var id = 0L
    for index in 7L..target.count() {
        let digit = target[index].to_long() - 48L
        if digit < 0L || digit > 9L { return -1L }
        id = id * 10L + digit
    }
    id
}

fn is_rooms_path(target: Bytes max 256) -> bool {
    target.count() > 7L && target[0] == 47 && target[1] == 114 && target[2] == 111 && target[3] == 111 && target[4] == 109 && target[5] == 115 && target[6] == 47
}

// The signed-in user for this request, found by the session cookie; found is false when there is none.
fn current_user(env: Env, connection: long, user: write User) -> bool {
    var cookie: Bytes max 512 = Bytes.empty()
    if env.http_header(connection, "Cookie", cookie) < 0L { return false }
    let token = Token { value: cookie_value(cookie, "session_token") }
    if token.value.count() == 0L { return false }
    env.db_row("""
        from (select u.id as id, u.name as name
              from sessions s join users u on u.id = s.user_id
              where s.token = ?1 and u.status = 0)
    """, token, user)
}

// The rooms the user is in, by name (a room with no name is a direct room).
fn rooms_of(env: Env, user: User, rooms: write list<Room, 100>) {
    discard env.db_rows("""
        from (select r.id as id, coalesce(r.name, 'Direct') as name, r.type as kind
              from rooms r join memberships m on m.room_id = r.id
              where m.user_id = ?1
              order by r.name)
        limit 100
    """, user.id, rooms)
}

fn reply(env: Env, connection: long, status: long, kind: long, body: Page) -> bool {
    env.http_write(connection, status, kind, body) >= 0L
}

fn serve(env: Env, connection: long) {
    var target: Bytes max 256 = Bytes.empty()
    var page: Page = Bytes.empty()
    while true {
        let method = env.http_read(connection, target)
        if method < 0L { break }
        page = Bytes.empty()
        var user = User {}
        var status = 200L
        var handled = false
        if method == 2L && target_is(target, "/session") {
            if !sign_in(env, connection) { break }
            handled = true
        } else if method == 4L && target_is(target, "/session") {
            if !sign_out(env, connection) { break }
            handled = true
        }
        let signed_in = !handled && current_user(env, connection, user)
        if handled {
            // already answered
        } else if method != 1L {
            status = 400L
            render_text(page, "bad request")
        } else if target_is(target, "/session/new") || target_is(target, "/session/new?failed=1") {
            if signed_in {
                if !redirect(env, connection, "Location: /", Bytes.empty()) { break }
                handled = true
            } else {
                render_signin(page, target.count() > 12L)
            }
        } else if !signed_in {
            if !redirect(env, connection, "Location: /session/new", Bytes.empty()) { break }
            handled = true
        } else if target.count() == 1L && target[0] == 47 {
            var rooms: list<Room, 100> = list {}
            rooms_of(env, user, rooms)
            render_home(page, user, rooms)
        } else if is_rooms_path(target) && room_id(target) >= 0L {
            let id = room_id(target)
            var room = Room {}
            let member = RoomAndUser { room_id: id, user_id: user.id }
            var membership = Membership {}
            let found_room = env.db_row("""
                from (select id, coalesce(name, 'Direct') as name, type as kind from rooms)
                where id = ?1
            """, id, room)
            let is_member = env.db_row("from memberships where room_id = ?1 and user_id = ?2", member, membership)
            if found_room && is_member {
                var rooms: list<Room, 100> = list {}
                rooms_of(env, user, rooms)
                var messages: list<Message, 40> = list {}
                // the room's last 40 messages, oldest first, each with its author and its rich-text body
                discard env.db_rows("""
                    from (select m.id as id, m.client_message_id as client_message_id, m.created_at as created_at,
                                 m.creator_id as creator_id, u.name as author, coalesce(r.body, '') as body
                          from messages m
                          join users u on u.id = m.creator_id
                          left join action_text_rich_texts r
                            on r.record_id = m.id and r.record_type = 'Message' and r.name = 'body'
                          where m.room_id = ?1
                          order by m.id desc
                          limit 40)
                    order by id asc
                    limit 40
                """, id, messages)
                render_room(page, user, room, rooms, messages)
            } else {
                status = 404L
                render_text(page, "not found")
            }
        } else {
            status = 404L
            render_text(page, "not found")
        }
        if !handled && !reply(env, connection, status, if status == 200L { 0L } else { 2L }, page) { break }
    }
    discard env.net_close(connection)
}

fn main(env: Env) {
    let listener = env.net_listen(PORT)
    while true {
        let connection = env.net_accept(listener)
        if connection < 0L { break }
        spawn serve(env, connection)
    }
}
