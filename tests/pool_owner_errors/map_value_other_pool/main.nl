struct Node { v: long }
struct Label { text: Ascii max 8 }

fn main() {
    var nodes: pool<Node, 8> = pool {}
    var labels: pool<Label, 8> = pool {}
    let a = nodes.add(Node { v: 1 }).unwrap()
    var m: map<long, Id<labels>, 8> = map {}
    m.set(1L, a).unwrap()
}
