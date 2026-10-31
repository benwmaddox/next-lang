// A small web service built from jobs and mailboxes.
//   GET /item/<id>  -> JSON  {"id":..,"name":"..","price":..,"v":..}
//   GET /page/<id>  -> HTML page with the name escaped and the price shown with 8% tax added
// An acceptor job spawns one `serve` task per connection. Each request is a call to the Cache service (cache.svc: a direct-mapped array
// of rows); on a miss it forwards the request to the Database service (database.svc), which reads the row from SQLite,
// answers the caller and fills the cache. If the cache mailbox is full the connection answers 503
// at once instead of waiting. Run with NLC_DB=<file made by bench/web/make-db.py>.
const CACHE_SLOTS: long = 4096L
const PORT: long = 18081L

struct Row {
    key: long
    found: bool
    v: long
    price: long
    name: Bytes max 32
}

struct Reply {
    row: Row
    hit: bool
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

// One job per connection (a task). Asking the cache is a call: Cache_get sends the request with a reply slot and waits.
// None means the cache's mailbox was full, which is the 503.
fn serve(env: Env, connection: long, cache_inbox: Sender<CacheMessage>) {
    let cache = Cache { inbox: cache_inbox }
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
            match Cache_get(cache, id) {
                some(reply) => {
                    body = Bytes.empty()
                    var status = 200L
                    if !reply.row.found { status = 404L }
                    if status == 404L { discard body.try_append("{\"error\":\"no such item\"}".bytes()) }
                    else if route == 1L { render_item(body, reply.row) }
                    else { render_page(body, reply.row, reply.row.price + reply.row.price * 8L / 100L) }
                    let kind = if status == 200L && route == 2L { 0L } else { 1L }
                    let sent = env.http_write(connection, status, kind, body)
                    if sent < 0L { break }
                },
                none => {
                    let sent = env.http_write(connection, 503L, 1L, "{\"error\":\"busy\"}")
                    if sent < 0L { break }
                },
            }
        }
    }
    let closed = env.net_close(connection)
}

fn acceptor(env: Env, listener: long, cache_inbox: Sender<CacheMessage>) {
    for round in 0L..4000000000L {
        let connection = env.net_accept(listener)
        if connection < 0L { break }
        spawn serve(env, connection, cache_inbox)
    }
}

fn main(env: Env) {
    let listener = env.net_listen(PORT)
    let database = Database_start(env)
    let cache = Cache_start(database)
    spawn acceptor(env, listener, cache.inbox)
}
