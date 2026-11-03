struct Node { value: int }
struct Label { text: int }
struct World {
    nodes: pool<Node, 4>
    labels: pool<Label, 4>
}

fn main() {
    var one = World { nodes: pool {}, labels: pool {} }
    var two = World { nodes: pool {}, labels: pool {} }
    print(one.nodes.count() + two.nodes.count())
}
