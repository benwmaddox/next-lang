struct Node { value: int }
struct Label { text: int }
struct World {
    nodes: pool<Node, 4>
    labels: pool<Label, 4>
    all: list<Id<nodes>, 4>
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {}, all: list {} }
    for p in world.all {
        match world.labels.get(p) {
            some(label) => print(label.text),
            none => print("none"),
        }
    }
}
