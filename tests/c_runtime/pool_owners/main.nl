// Ids name their pool: Id<nodes> belongs to the pool nodes. Several pools in one state struct, passed as write.
struct Node {
    value: int
    next: Id<nodes>
    label: Id<labels>
}

struct Label {
    text: int
}

struct World {
    nodes: pool<Node, 8>
    labels: pool<Label, 8>
    head: Id<nodes>
}

fn add_label(world: write World, text: int) -> Id<labels> {
    match world.labels.add(Label { text }) {
        ok(id) => id,
        err(_) => -1L,
    }
}

fn add_node(world: write World, value: int, label: Id<labels>) -> Id<nodes> {
    let previous = world.head
    match world.nodes.add(Node { value, next: previous, label }) {
        ok(id) => {
            world.head = id
            id
        },
        err(_) => -1L,
    }
}

fn label_text(world: World, id: Id<labels>) -> int {
    match world.labels.get(id) {
        some(label) => label.text,
        none => -1,
    }
}

// A helper over any pool: the id parameter names the pool parameter.
fn value_at<N>(nodes: pool<Node, N>, id: Id<nodes>) -> int {
    match nodes.get(id) {
        some(node) => node.value,
        none => -1,
    }
}

fn main() {
    var world = World { nodes: pool {}, labels: pool {}, head: -1L }
    let red = add_label(world, 100)
    let blue = add_label(world, 200)
    discard add_node(world, 1, red)
    let second = add_node(world, 2, blue)
    print(world.nodes.count())
    print(label_text(world, blue))
    print(value_at(world.nodes, second))
    var cursor = world.head
    var total = 0
    while cursor >= 0L {
        match world.nodes.get(cursor) {
            some(node) => {
                total += node.value + label_text(world, node.label)
                cursor = node.next
            },
            none => { cursor = -1L },
        }
    }
    print(total)
    // A second, local pool of the same element type has its own ids.
    var scratch: pool<Label, 4> = pool {}
    var local_ids: list<Id<scratch>, 4> = list {}
    match scratch.add(Label { text: 7 }) {
        ok(id) => { discard local_ids.push(id) },
        err(_) => {},
    }
    match scratch.get(local_ids[0]) {
        some(label) => print(label.text),
        none => print("none"),
    }
}
