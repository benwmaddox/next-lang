struct Node { value: int }
struct Label { text: int }
struct World {
    nodes: pool<Node, 4>
    labels: pool<Label, 4>
    by_key: map<long, Id<nodes>, 4>
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {}, by_key: map {} }
    match world.by_key.get(1L) {
        some(id) => {
            match world.labels.get(id) {
                some(label) => print(label.text),
                none => print("none"),
            }
        },
        none => {},
    }
}
