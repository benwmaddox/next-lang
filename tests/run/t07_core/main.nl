struct Rock { value: int }
struct State {
    nodes: pool<Rock, 1>
    value: int
}
struct Node<P> {
    parent: Option<Id<P>>
    value: int
}

fn depth<P, N>(nodes: pool<Node<P>, N, P>, id: Id<P>) -> long {
    var d = 0L
    var cur = id
    for step in 0..N {
        let node = nodes.get(cur) ?? return d
        let up = node.parent ?? return d
        cur = up
        d += 1
    }
    d
}

fn retain_id<P, N>(nodes: pool<Node<P>, N, P>, id: Id<P>) -> Id<P> {
    id
}

fn rock_count<P, N>(rocks: pool<Rock, N, P>) -> long {
    rocks.count()
}

fn bump(state: write State) {
    state.value += 1
}

fn main() {
    var rocks: pool<Rock, 2> = pool {}
    let first = rocks.add(Rock { value: 10 }).unwrap()
    let second = rocks.add(Rock { value: 20 }).unwrap()
    let full = rocks.add(Rock { value: 30 })
    print(full.is_err())
    print(rocks.count())
    print(rocks)
    for rock, id in rocks {
        rock.value += 1
    }
    print(rocks.get(first).unwrap())
    let removed = rocks.remove(first)
    print(removed.unwrap())
    print(rocks.get(first).is_none())
    print(rocks.remove(first).is_none())
    let replacement = rocks.add(Rock { value: 99 }).unwrap()
    print(first == replacement)
    var copied = rocks.get(second).unwrap()
    copied.value = 77
    print(rocks.get(second).unwrap())
    print(rocks)
    print(rocks.get(first).is_none())

    var state: State = State { nodes: pool {}, value: 5 }
    let state_id: state.nodes.Id = state.nodes.add(Rock { value: 6 }).unwrap()
    let state_id_alias: Id<state.nodes> = state_id
    print(state.nodes.get(state_id_alias).unwrap())
    print(rock_count(state.nodes))
    bump(state)
    print(state.value)
    var other_state: State = State { nodes: pool {}, value: 7 }
    let other_state_id = other_state.nodes.add(Rock { value: 7 }).unwrap()
    print(other_state.nodes.get(other_state_id).unwrap())

    var nodes: pool<Node<nodes>, 4> = pool {}
    let root: nodes.Id = nodes.add(Node { parent: none, value: 1 }).unwrap()
    let leaf: Id<nodes> = nodes.add(Node { parent: some(root), value: 2 }).unwrap()
    print(nodes.get(leaf).unwrap().value)
    print(depth(nodes, leaf))
    let retained: Id<nodes> = retain_id(nodes, leaf)
    print(retained == leaf)
    print(nodes == nodes)

    var other: pool<Node<other>, 4> = pool {}
    let other_root = other.add(Node { parent: none, value: 7 }).unwrap()
    let other_leaf = other.add(Node { parent: some(other_root), value: 8 }).unwrap()
    print(depth(other, other_leaf))
    let other_retained: Id<other> = retain_id(other, other_leaf)
    print(other_retained == other_leaf)
}
