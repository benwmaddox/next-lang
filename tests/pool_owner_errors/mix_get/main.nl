struct Node { value: int }
struct Label { text: int }
struct World {
    nodes: pool<Node, 4>
    labels: pool<Label, 4>
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {} }
    match world.nodes.add(Node { value: 1 }) {
        ok(id) => {
            match world.labels.get(id) {
                some(label) => print(label.text),
                none => print("none"),
            }
        },
        err(_) => {},
    }
}
