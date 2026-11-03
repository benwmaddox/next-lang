struct Node { value: int, label: Id<labels> }
struct Label { text: int }
struct World {
    nodes: pool<Node, 4>
    labels: pool<Label, 4>
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {} }
    match world.nodes.add(Node { value: 1, label: -1L }) {
        ok(id) => {
            discard world.nodes.set(id, Node { value: 2, label: id })
        },
        err(_) => {},
    }
}
