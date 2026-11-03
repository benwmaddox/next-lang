struct Node { value: int }
struct Label { text: int }
struct World {
    nodes: pool<Node, 4>
    labels: pool<Label, 4>
}

fn text_of(world: World, id: Id<labels>) -> int {
    match world.labels.get(id) {
        some(label) => label.text,
        none => -1,
    }
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {} }
    match world.nodes.add(Node { value: 1 }) {
        ok(id) => print(text_of(world, id)),
        err(_) => {},
    }
}
