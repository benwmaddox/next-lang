struct Node { value: int, next: Id<Node> }
struct Label { text: int }

fn main() {
    var nodes: pool<Node, 4> = pool {}
    var labels: pool<Label, 4> = pool {}
    print(nodes.count() + labels.count())
}
