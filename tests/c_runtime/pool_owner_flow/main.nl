// Ids keep their pool through map.get payloads, for-each variables over lists and arrays of ids, and match bindings.
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
    by_key: map<long, Id<nodes>, 8>
    all: list<Id<nodes>, 8>
}

fn add_node(world: write World, key: long, value: int) -> Id<nodes> {
    match world.nodes.add(Node { value, next: -1L }) {
        ok(id) => {
            world.by_key.set(key, id).unwrap()
            discard world.all.push(id)
            id
        },
        err(_) => -1L,
    }
}

fn value_of_key(world: World, key: long) -> int {
    match world.by_key.get(key) {
        some(id) => match world.nodes.get(id) {
            some(node) => node.value,
            none => -1,
        },
        none => -2,
    }
}

fn sum_all(world: World) -> int {
    var total = 0
    for p in world.all {
        match world.nodes.get(p) {
            some(node) => { total += node.value },
            none => (),
        }
    }
    total
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {}, by_key: map {}, all: list {} }
    discard add_node(world, 10L, 4)
    discard add_node(world, 20L, 9)
    print(value_of_key(world, 20L))
    print(value_of_key(world, 30L))
    print(sum_all(world))
    let first = world.all[0]
    let second = world.all[1]
    var local: Id<nodes>[2] = [first, second]
    for q in local {
        match world.nodes.get(q) {
            some(node) => print(node.value),
            none => (),
        }
    }
}
