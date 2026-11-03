struct Node { value: long, next: Id<nodes> }
struct World { nodes: pool<Node, 100000>, count: long }
struct Session { world: World, name: Ascii max 8 }

fn value_of(h: World, id: Id<nodes>) -> long {
    h.nodes[id].value
}

fn next_of(h: World, id: Id<nodes>) -> Id<nodes> {
    h.nodes[id].next
}

fn peek(h: World, id: Id<nodes>) -> long {
    match h.nodes.get(id) { some(n) => n.value, none => -1L }
}

recursive fn depth(h: World, id: Id<nodes>) -> long {
    if id < 0L { return 0L }
    1L + depth(h, next_of(h, id))
}

fn sum_to(h: World, id: Id<nodes>) -> long {
    var total = 0L
    var cur = id
    while cur >= 0L {
        total += value_of(h, cur) + peek(h, cur)
        cur = next_of(h, cur)
    }
    total
}

fn session_total(s: Session, id: Id<nodes>) -> long {
    sum_to(s.world, id) + depth(s.world, id)
}

fn bump(h: write World) { h.count += 1L }

fn mixed(h: write World, id: Id<nodes>) -> long {
    bump(h)
    sum_to(h, id) + depth(h, next_of(h, id))
}

fn main() {
    var session = Session { world: World { nodes: pool {}, count: 0L }, name: "s" }
    var prev = -1L
    for i in 0L..2000L {
        prev = session.world.nodes.add(Node { value: i, next: prev }).unwrap()
    }
    print(value_of(session.world, next_of(session.world, prev)))
    print(depth(session.world, prev))
    print(session_total(session, prev))
    print(mixed(session.world, prev))
    print(session.world.count)
}
