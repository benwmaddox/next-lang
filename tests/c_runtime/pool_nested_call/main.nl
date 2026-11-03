struct Node {
    value: int
    next: Id<nodes>
}

struct Label {
    text: int
}

struct World {
    nodes: pool<Node, 8>
    labels: pool<Label, 8>
    count: int
}

fn g(h: World, id: Id<nodes>) -> Id<nodes> {
    match h.nodes.get(id) {
        some(n) => n.next,
        none => -1L,
    }
}

fn f(h: World, id: Id<nodes>) -> int {
    match h.nodes.get(id) {
        some(n) => n.value,
        none => -1,
    }
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {}, count: 7 }
    let a = match world.nodes.add(Node { value: 5, next: -1L }) {
        ok(id) => id,
        err(_) => -1L,
    }
    let b = match world.nodes.add(Node { value: 6, next: a }) {
        ok(id) => id,
        err(_) => -1L,
    }
    print(f(world, g(world, b)))
    print(f(world, b))
}
