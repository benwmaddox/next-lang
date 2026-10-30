// Request -> cache -> "database" -> reply, as jobs joined by mailboxes. Each client owns a one-slot reply mailbox
// and puts its sender in every request. The cache job answers hits itself and sends misses to the database job,
// which answers the cache; the cache stores the row and replies to the client. The database is a stand-in
// (a hash loop) until the Db capability exists.
const CLIENTS: long = 4L
const KEYS: long = 5000L
const CACHE_SLOTS: long = 1024L

struct Reply {
    key: long
    value: long
    hit: bool
}

// kind 0: request from a client; kind 1: row from the database; kind 2: a client is done
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

fn row_for(key: long) -> long {
    var x = key * 40503L + 12345L
    for round in 0L..200L {
        x = (x * 48271L + 11L) % 2147483647L
    }
    x
}

fn send_msg(to: Sender<Msg>, msg: Msg) {
    for attempt in 0L..1000000000L {
        match to.send(msg) {
            ok(_) => { break },
            err(_) => {},
        }
    }
}

fn database(inbox: Receiver<DbRequest>) {
    for step in 0L..1000000000L {
        match inbox.recv_wait() {
            some(request) => {
                send_msg(request.cache, Msg { kind: 1L, key: request.key, value: row_for(request.key), reply: request.reply })
            },
            none => { break },
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

fn cache(inbox: Receiver<Msg>, self_sender: Sender<Msg>, db: Sender<DbRequest>, db_close: Sender<DbRequest>) {
    var slots: list<Slot, 1024> = list {}
    for index in 0L..CACHE_SLOTS { slots.push(Slot { key: -1L, value: 0L }) }
    var done = 0L
    for step in 0L..1000000000L {
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
                } else if msg.kind == 1L {
                    slots[msg.key % CACHE_SLOTS] = Slot { key: msg.key, value: msg.value }
                    reply_to(msg.reply, Reply { key: msg.key, value: msg.value, hit: false })
                } else {
                    done += 1L
                    if done == CLIENTS {
                        db_close.close()
                        break
                    }
                }
            },
            none => { break },
        }
    }
}

fn client(id: long, requests: long, cache: Sender<Msg>, replies: Receiver<Reply>, reply_to_me: Sender<Reply>) {
    var seed = id * 7919L + 1L
    var checksum = 0L
    var hits = 0L
    for index in 0L..requests {
        seed = (seed * 48271L + 11L) % 2147483647L
        // skewed keys: squaring a uniform number makes low keys much hotter
        let u = seed % KEYS
        let key = (u * u) / KEYS
        send_msg(cache, Msg { kind: 0L, key: key, value: 0L, reply: reply_to_me })
        match replies.recv_wait() {
            some(reply) => {
                checksum += reply.value % 1000L
                if reply.hit { hits += 1L }
            },
            none => { break },
        }
    }
    send_msg(cache, Msg { kind: 2L, key: 0L, value: 0L, reply: reply_to_me })
    print(checksum)
    print(hits)
}

fn main() {
    var cache_box: mailbox<Msg, 64> = mailbox {}
    var db_box: mailbox<DbRequest, 64> = mailbox {}
    var r0: mailbox<Reply, 1> = mailbox {}
    var r1: mailbox<Reply, 1> = mailbox {}
    var r2: mailbox<Reply, 1> = mailbox {}
    var r3: mailbox<Reply, 1> = mailbox {}
    spawn database(db_box.receiver())
    spawn cache(cache_box.receiver(), cache_box.sender(), db_box.sender(), db_box.sender())
    spawn client(0L, 2000L, cache_box.sender(), r0.receiver(), r0.sender())
    spawn client(1L, 2000L, cache_box.sender(), r1.receiver(), r1.sender())
    spawn client(2L, 2000L, cache_box.sender(), r2.receiver(), r2.sender())
    spawn client(3L, 2000L, cache_box.sender(), r3.receiver(), r3.sender())
}
