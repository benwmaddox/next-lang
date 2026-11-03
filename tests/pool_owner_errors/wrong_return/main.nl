struct Node { value: int }
struct Label { text: int }
struct World {
    nodes: pool<Node, 4>
    labels: pool<Label, 4>
}

fn pick(world: write World) -> Id<labels> {
    match world.nodes.add(Node { value: 1 }) {
        ok(id) => id,
        err(_) => -1L,
    }
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {} }
    print(pick(world))
}
