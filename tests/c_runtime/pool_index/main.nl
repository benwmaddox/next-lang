// A pool indexed by an id of that pool: read and write one field in place, like a list element.
struct Node {
    value: int
    parent: Id<nodes>
}

struct Label {
    text: int
}

struct World {
    nodes: pool<Node, 8>
    labels: pool<Label, 8>
}

fn add(world: write World, value: int) -> Id<nodes> {
    match world.nodes.add(Node { value, parent: -1L }) {
        ok(id) => id,
        err(_) => -1L,
    }
}

fn reparent(world: write World, child: Id<nodes>, parent: Id<nodes>) {
    world.nodes[child].parent = parent
    world.nodes[child].value += 100
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {} }
    let a = add(world, 1)
    let b = add(world, 2)
    reparent(world, b, a)
    print(world.nodes[b].value)
    print(world.nodes[world.nodes[b].parent].value)
    print(world.nodes[a].parent < 0L)
    let copy = world.nodes[b]
    print(copy.value)
    var local: pool<Label, 4> = pool {}
    match local.add(Label { text: 7 }) {
        ok(id) => {
            local[id].text = 9
            print(local[id].text)
        },
        err(_) => {},
    }
}
