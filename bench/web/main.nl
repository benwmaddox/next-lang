// A small web service: GET /item/<id> answers {"id":..,"v":..} from a cache job, which asks a database job (SQLite)
// on a miss. Four worker jobs accept connections and serve them; each worker owns a one-slot reply mailbox.
// Run with NLC_DB=<file made by bench/web/make-db.py> (table items(id, v, name)).
const KEYS: long = 5000L
const CACHE_SLOTS: long = 4096L
const PORT: long = 18081L

struct Reply {
    key: long
    value: long
    hit: bool
}

struct Msg {
    kind: long
    key: long
    value: long
    reply: Sender<Reply>
}

struct DbRequest {
    key: long
    reply: Sender<Reply>
    cache: Sender<Msg>
}

struct Slot {
    key: long
    value: long
}

fn value_for(env: Env, key: long) -> long {
    match env.db_query("select v from items where id = ?1", key) {
        some(value) => { value },
        none => { -1L },
    }
}

fn send_msg(to: Sender<Msg>, msg: Msg) {
    for attempt in 0L..1000000000L {
        match to.send(msg) {
            ok(_) => { break },
            err(_) => {},
        }
    }
}

fn reply_to(to: Sender<Reply>, reply: Reply) {
    for attempt in 0L..1000000000L {
        match to.send(reply) {
            ok(_) => { break },
            err(_) => {},
        }
    }
}

fn database(env: Env, inbox: Receiver<DbRequest>) {
    for step in 0L..4000000000L {
        match inbox.recv_wait() {
            some(request) => {
                send_msg(request.cache, Msg { kind: 1L, key: request.key, value: value_for(env, request.key), reply: request.reply })
            },
            none => { break },
        }
    }
}

fn cache(inbox: Receiver<Msg>, self_sender: Sender<Msg>, db: Sender<DbRequest>) {
    var slots: list<Slot, 4096> = list {}
    for index in 0L..CACHE_SLOTS { slots.push(Slot { key: -1L, value: 0L }) }
    for step in 0L..4000000000L {
        match inbox.recv_wait() {
            some(msg) => {
                if msg.kind == 0L {
                    let at = msg.key % CACHE_SLOTS
                    if slots[at].key == msg.key {
                        reply_to(msg.reply, Reply { key: msg.key, value: slots[at].value, hit: true })
                    } else {
                        let request = DbRequest { key: msg.key, reply: msg.reply, cache: self_sender }
                        for attempt in 0L..1000000000L {
                            match db.send(request) {
                                ok(_) => { break },
                                err(_) => {},
                            }
                        }
                    }
                } else {
                    slots[msg.key % CACHE_SLOTS] = Slot { key: msg.key, value: msg.value }
                    reply_to(msg.reply, Reply { key: msg.key, value: msg.value, hit: false })
                }
            },
            none => { break },
        }
    }
}

fn push_number(out: grow Bytes max 64, value: long) {
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

fn render(out: grow Bytes max 64, key: long, value: long) {
    discard out.try_append("{\"id\":".bytes())
    push_number(out, key)
    discard out.try_append(",\"v\":".bytes())
    push_number(out, value)
    discard out.push((byte)125)
}

// The id in "/item/<digits>", or -1.
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

fn worker(env: Env, listener: long, cache: Sender<Msg>, replies: Receiver<Reply>, reply_to_me: Sender<Reply>) {
    var target: Bytes max 256 = Bytes.empty()
    for round in 0L..4000000000L {
        let connection = env.net_accept(listener)
        if connection < 0L { break }
        for request in 0L..4000000000L {
            let method = env.http_read(connection, target)
            if method < 0L { break }
            let id = item_id(target)
            if method != 1L || id < 0L {
                let sent = env.http_write(connection, 404L, 1L, "{\"error\":\"not found\"}")
                if sent < 0L { break }
            } else {
                send_msg(cache, Msg { kind: 0L, key: id, value: 0L, reply: reply_to_me })
                match replies.recv_wait() {
                    some(reply) => {
                        var body: Bytes max 64 = Bytes.empty()
                        render(body, reply.key, reply.value)
                        let sent = env.http_write(connection, 200L, 1L, body)
                        if sent < 0L { break }
                    },
                    none => { break },
                }
            }
        }
        let closed = env.net_close(connection)
    }
}

fn main(env: Env) {
    let listener = env.net_listen(PORT)
    var cache_box: mailbox<Msg, 64> = mailbox {}
    var db_box: mailbox<DbRequest, 64> = mailbox {}
    var r0: mailbox<Reply, 1> = mailbox {}
    var r1: mailbox<Reply, 1> = mailbox {}
    var r2: mailbox<Reply, 1> = mailbox {}
    var r3: mailbox<Reply, 1> = mailbox {}
    spawn database(env, db_box.receiver())
    spawn cache(cache_box.receiver(), cache_box.sender(), db_box.sender())
    spawn worker(env, listener, cache_box.sender(), r0.receiver(), r0.sender())
    spawn worker(env, listener, cache_box.sender(), r1.receiver(), r1.sender())
    spawn worker(env, listener, cache_box.sender(), r2.receiver(), r2.sender())
    spawn worker(env, listener, cache_box.sender(), r3.receiver(), r3.sender())
}
