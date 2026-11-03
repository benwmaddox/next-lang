struct Node { v: long }
struct Label { text: Ascii max 8 }

fn main() {
    var nodes: pool<Node, 8> = pool {}
    var labels: pool<Label, 8> = pool {}
    let a = nodes.add(Node { v: 1 }).unwrap()
    let b = labels.add(Label { text: "x" }).unwrap()
    var m: map<Id<nodes>, long, 8> = map {}
    m.set(a, 1L).unwrap()
    print(m.contains(b))
}
