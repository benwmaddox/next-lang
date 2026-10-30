// Producers send numbered messages through one mailbox to a consumer job; main waits for them all.
fn produce(outbox: Sender<long>, base: long, count: long) {
    for index in 0L..count {
        // a full mailbox refuses the message, so try again
        for attempt in 0L..1000000000L {
            match outbox.send(base + index) {
                ok(_) => { break },
                err(_) => {},
            }
        }
    }
}

fn consume(inbox: Receiver<long>, expected: long) {
    var total = 0L
    var received = 0L
    for step in 0L..expected {
        match inbox.recv_wait() {
            some(value) => {
                total += value
                received += 1L
            },
            none => { break },
        }
    }
    print(total)
    print(received)
}

fn main() {
    var box: mailbox<long, 16> = mailbox {}
    let outbox = box.sender()
    let inbox = box.receiver()
    spawn consume(inbox, 3000L)
    spawn produce(outbox, 0L, 1000L)
    spawn produce(outbox, 100000L, 1000L)
    spawn produce(outbox, 200000L, 1000L)
}
