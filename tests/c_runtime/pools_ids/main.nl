// Id<Node> is a pool slot number (a long underneath); -1L is the "no node" id. A tree is built by adding nodes
// and then linking them with pool.set.
const NO_NODE: long = -1L

struct Node {
    value: int
    parent: Id<Node>
    left: Id<Node>
    right: Id<Node>
}

fn leaf(value: int) -> Node {
    Node { value, parent: NO_NODE, left: NO_NODE, right: NO_NODE }
}

recursive fn sum<N>(nodes: pool<Node, N>, id: Id<Node>) -> int {
    if id < 0L { return 0 }
    match nodes.get(id) {
        some(node) => node.value + sum(nodes, node.left) + sum(nodes, node.right),
        none => 0,
    }
}

fn main() {
    var nodes: pool<Node, 8> = pool {}
    var ids: list<Id<Node>, 3> = list {}
    for value: int in 1..4 {
        match nodes.add(leaf(value * 10)) {
            ok(id) => { discard ids.push(id) },
            err(_) => {},
        }
    }
    let top = ids[0]
    discard nodes.set(top, Node { value: 10, parent: NO_NODE, left: ids[1], right: ids[2] })
    discard nodes.set(ids[1], Node { value: 20, parent: top, left: NO_NODE, right: NO_NODE })
    discard nodes.set(ids[2], Node { value: 30, parent: top, left: NO_NODE, right: NO_NODE })
    print(sum(nodes, top))
    match nodes.get(ids[2]) {
        some(node) => print(node.parent == top),
        none => print("none"),
    }
}
