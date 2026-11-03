// pool.set overwrites an element in place by id and says whether the id named a slot in use.
struct Node {
    value: int
    label: Ascii max 8
    parent: long
}

fn relink<N>(nodes: write pool<Node, N>, id: long, parent: long) -> bool {
    match nodes.get(id) {
        some(node) => nodes.set(id, Node { value: node.value, label: node.label, parent }),
        none => false,
    }
}

fn main() {
    var nodes: pool<Node, 4> = pool {}
    var root = -1L
    var child = -1L
    match nodes.add(Node { value: 1, label: "root", parent: -1L }) {
        ok(id) => { root = id },
        err(_) => {},
    }
    match nodes.add(Node { value: 2, label: "child", parent: -1L }) {
        ok(id) => { child = id },
        err(_) => {},
    }
    print(relink(nodes, child, root))
    print(nodes.set(root, Node { value: 10, label: "top", parent: -1L }))
    print(nodes.set(5L, Node { value: 0, label: "x", parent: -1L }))
    print(nodes.set(-1L, Node { value: 0, label: "x", parent: -1L }))
    match nodes.get(child) {
        some(node) => { print(node.value); print(node.label); print(node.parent) },
        none => print("none"),
    }
    match nodes.get(root) {
        some(node) => { print(node.value); print(node.label); print(node.parent) },
        none => print("none"),
    }
    print(nodes.count())
}
