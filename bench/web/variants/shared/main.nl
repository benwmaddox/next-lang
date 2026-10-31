// Variant: a process-wide cache of rendered response bodies (env.cache_get / cache_put); a hit never leaves the connection job.
const PORT: long = 18081L

struct Row {
    key: long
    found: bool
    v: long
    price: long
    name: Bytes max 32
}


// The columns this page reads: the struct is the projection, and the query is one statement.
struct ItemData {
    v: long
    price: long
    name: Bytes max 32
}

fn load_row(env: Env, key: long) -> Row {
    var data = ItemData { v: 0L, price: 0L, name: Bytes.empty() }
    let found = env.db_row("from items where id = ?1", key, data)
    Row { key: key, found: found, v: data.v, price: data.price, name: data.name }
}


// Builders append into a response body of at most 512 bytes; a piece that does not fit is dropped.
fn push_number(out: grow Bytes max 512, value: long) {
    var rest = value
    if rest < 0L {
        discard out.push((byte)45)
        rest = 0L - rest
    }
    var digits: list<long, 20> = list {}
    for step in 0L..20L {
        discard digits.push(rest % 10L)
        rest = rest / 10L
        if rest == 0L { break }
    }
    var index = digits.count()
    for position in 0L..digits.count() {
        index -= 1L
        discard out.push((byte)(48L + digits[index]))
    }
}

// cents as dollars: 1234 -> 12.34
fn push_money(out: grow Bytes max 512, cents: long) {
    push_number(out, cents / 100L)
    discard out.push((byte)46)
    let rest = cents % 100L
    discard out.push((byte)(48L + rest / 10L))
    discard out.push((byte)(48L + rest % 10L))
}

fn push_text(out: grow Bytes max 512, text: Ascii max 128) {
    discard out.try_append(text.bytes())
}

// the name with < > & " made safe for HTML
fn push_escaped(out: grow Bytes max 512, name: Bytes max 32) {
    for index in 0L..name.count() {
        let c = name[index].to_long()
        if c == 60L { push_text(out, "&lt;") }
        else if c == 62L { push_text(out, "&gt;") }
        else if c == 38L { push_text(out, "&amp;") }
        else if c == 34L { push_text(out, "&quot;") }
        else { discard out.push(name[index]) }
    }
}

// the name for JSON: quotes and backslashes escaped
fn push_json_string(out: grow Bytes max 512, name: Bytes max 32) {
    discard out.push((byte)34)
    for index in 0L..name.count() {
        let c = name[index].to_long()
        if c == 34L || c == 92L { discard out.push((byte)92) }
        discard out.push(name[index])
    }
    discard out.push((byte)34)
}

fn render_json(out: grow Bytes max 512, row: Row) {
    push_text(out, "{\"id\":")
    push_number(out, row.key)
    push_text(out, ",\"name\":")
    push_json_string(out, row.name)
    push_text(out, ",\"price\":")
    push_money(out, row.price)
    push_text(out, ",\"v\":")
    push_number(out, row.v)
    discard out.push((byte)125)
}

fn render_page(out: grow Bytes max 512, row: Row) {
    push_text(out, "<!doctype html><html><body><h1>")
    push_escaped(out, row.name)
    push_text(out, "</h1><p>item ")
    push_number(out, row.key)
    push_text(out, "</p><p>price with tax: $")
    push_money(out, row.price + row.price * 8L / 100L)
    push_text(out, "</p></body></html>")
}

// The id in "/item/<digits>" or "/page/<digits>", or -1.
fn item_id(target: Bytes max 256) -> long {
    if target.count() < 7L || target.count() > 16L { return -1L }
    var id = 0L
    for index in 6L..target.count() {
        let digit = target[index].to_long() - 48L
        if digit < 0L || digit > 9L { return -1L }
        id = id * 10L + digit
    }
    id
}

// 1 for /item/, 2 for /page/, 0 for anything else.
fn route_of(target: Bytes max 256) -> long {
    if target.count() < 7L { return 0L }
    if target[0].to_long() != 47L || target[5].to_long() != 47L { return 0L }
    if target[1].to_long() == 105L && target[2].to_long() == 116L { return 1L }
    if target[1].to_long() == 112L && target[2].to_long() == 97L { return 2L }
    0L
}

fn serve(env: Env, connection: long) {
    var target: Bytes max 256 = Bytes.empty()
    var body: Bytes max 512 = Bytes.empty()
    for request in 0L..4000000000L {
        let method = env.http_read(connection, target)
        if method < 0L { break }
        let id = item_id(target)
        let route = route_of(target)
        if method != 1L || id < 0L || route == 0L {
            let sent = env.http_write(connection, 404L, 1L, "{\"error\":\"not found\"}")
            if sent < 0L { break }
        } else {
            let key = id * 4L + route
            body = Bytes.empty()
            var status = 200L
            let have = env.cache_get(key, body)
            if have < 0L {
                let row = load_row(env, id)
                if !row.found { status = 404L }
                if status == 404L { push_text(body, "{\"error\":\"no such item\"}") }
                else if route == 1L { render_json(body, row) }
                else { render_page(body, row) }
                if status == 200L {
                    let stored = env.cache_put(key, body)
                }
            }
            let kind = if status == 200L && route == 2L { 0L } else { 1L }
            let sent = env.http_write(connection, status, kind, body)
            if sent < 0L { break }
        }
    }
    let closed = env.net_close(connection)
}

fn acceptor(env: Env, listener: long) {
    for round in 0L..4000000000L {
        let connection = env.net_accept(listener)
        if connection < 0L { break }
        spawn serve(env, connection)
    }
}

fn main(env: Env) {
    let listener = env.net_listen(PORT)
    spawn acceptor(env, listener)
}
