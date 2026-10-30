// A producer sends whole records and closes the mailbox when it is done; the consumer sees them in order and then
// the end. The handles are passed to the jobs as expressions.
struct Order {
    id: long
    weight: long
    name: Ascii max 8
}

fn produce(outbox: Sender<Order>) {
    for index in 0L..200L {
        let order = Order { id: index, weight: index * 2L, name: "order" }
        for attempt in 0L..1000000000L {
            match outbox.send(order) {
                ok(_) => { break },
                err(_) => {},
            }
        }
    }
    outbox.close()
}

fn consume(inbox: Receiver<Order>) {
    var count = 0L
    var weights = 0L
    var last = -1L
    var in_order = true
    var named = true
    for step in 0L..1000000L {
        match inbox.recv_wait() {
            some(order) => {
                if order.id != last + 1L { in_order = false }
                if order.name != "order" { named = false }
                last = order.id
                weights += order.weight
                count += 1L
            },
            none => { break },
        }
    }
    print(count)
    print(weights)
    print(in_order)
    print(named)
}

fn main() {
    var box: mailbox<Order, 8> = mailbox {}
    spawn consume(box.receiver())
    spawn produce(box.sender())
}
