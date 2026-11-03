struct Node {
    value: int
    next: Id<Node>
}

struct World {
    nodes: pool<Node, 8>
    count: int
}

fn grow(world: write World, value: int) -> long {
    match world.nodes.add(Node { value, next: -1L }) {
        ok(id) => { world.count += 1; id },
        err(_) => -1L,
    }
}

fn main() {
    var world = World { nodes: pool {}, count: 0 }
    let first = grow(world, 5)
    let second = grow(world, 7)
    discard world.nodes.set(first, Node { value: 5, next: second })
    match world.nodes.get(first) {
        some(node) => print(node.value + world.count),
        none => print("none"),
    }
    print(world.nodes.count())
}
