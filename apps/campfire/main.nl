// Campfire (ONCE Campfire, Rails 90b3300) in next-lang. Slice 1: reading. The data is the Rails tables (schema.sql); the
// pages are templates (pages.tpl). One task per connection reads the request, finds the user from the session cookie, and
// answers GET / (the rooms you are in) and GET /rooms/:id (the room's last 40 messages).
const PORT: long = 18090L

struct User {
    id: long
    name: Bytes max 32
}

struct Room {
    id: long
    name: Bytes max 64
    kind: Bytes max 32
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

struct Membership {
    id: long
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
            if matches && cookie[first + index] != name.bytes()[index] { matches = false }
        }
        if matches {
            for index in first + name.len() + 1L..end { discard found.push(cookie[index]) }
            return found
        }
        start = end + 1L
    }
    found
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
    env.db_row("from (select u.id as id, u.name as name from sessions s join users u on u.id = s.user_id where s.token = ?1 and u.status = 0)", token, user)
}

fn rooms_of(env: Env, user: User, rooms: write list<Room, 100>) {
    discard env.db_rows("from (select r.id as id, coalesce(r.name, 'Direct') as name, r.type as kind from rooms r join memberships m on m.room_id = r.id where m.user_id = ?1 order by r.name) limit 100", user.id, rooms)
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
        var user = User { id: 0L, name: Bytes.empty() }
        var status = 200L
        if method != 1L {
            status = 400L
            render_text(page, "bad request")
        } else if !current_user(env, connection, user) {
            status = 401L
            render_text(page, "sign in")
        } else if target.count() == 1L && target[0] == 47 {
            var rooms: list<Room, 100> = list {}
            rooms_of(env, user, rooms)
            render_home(page, user, rooms)
        } else if is_rooms_path(target) && room_id(target) >= 0L {
            let id = room_id(target)
            var room = Room { id: 0L, name: Bytes.empty(), kind: Bytes.empty() }
            let member = RoomAndUser { room_id: id, user_id: user.id }
            var membership = Membership { id: 0L }
            if env.db_row("from (select id, coalesce(name, 'Direct') as name, type as kind from rooms) where id = ?1", id, room) && env.db_row("from memberships where room_id = ?1 and user_id = ?2", member, membership) {
                var rooms: list<Room, 100> = list {}
                rooms_of(env, user, rooms)
                var messages: list<Message, 40> = list {}
                discard env.db_rows("from (select id, client_message_id, created_at, creator_id, author, body from (select m.id as id, m.client_message_id as client_message_id, m.created_at as created_at, m.creator_id as creator_id, u.name as author, coalesce(r.body, '') as body from messages m join users u on u.id = m.creator_id left join action_text_rich_texts r on r.record_id = m.id and r.record_type = 'Message' and r.name = 'body' where m.room_id = ?1 order by m.id desc limit 40) order by id asc) limit 40", id, messages)
                render_room(page, user, room, rooms, messages)
            } else {
                status = 404L
                render_text(page, "not found")
            }
        } else {
            status = 404L
            render_text(page, "not found")
        }
        if !reply(env, connection, status, if status == 200L { 0L } else { 2L }, page) { break }
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
