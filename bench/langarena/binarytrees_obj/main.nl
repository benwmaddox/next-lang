// Binarytrees::Obj: LangArena's pointer-based binary tree, as a pool with typed ids.
const TEST_DEPTH: int = 4
const TEST_ITERATIONS: long = 3L
const RUN_DEPTH: int = 20
const RUN_ITERATIONS: long = 30L
const MODULUS: long = 4294967296L

struct Node<P> {
    item: int
    left: Option<Id<P>>
    right: Option<Id<P>>
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

recursive fn build<P, N>(nodes: write pool<Node<P>, N, P>, item: int, depth: int) -> Id<P> {
    var left: Option<Id<P>> = none
    var right: Option<Id<P>> = none
    if depth > 0 {
        let step = 1 << (depth - 1)
        left = some(build(nodes, item - step, depth - 1))
        right = some(build(nodes, item + step, depth - 1))
    }
    nodes.add(Node { item: item, left: left, right: right }).unwrap()
}

// The signed sum of (item + 1) over the subtree; reduced modulo 2^32 by the caller.
recursive fn sum<P, N>(nodes: pool<Node<P>, N, P>, id: Id<P>) -> long {
    let node = nodes.get(id) ?? return 0L
    var total = node.item.to_long() + 1L
    let left = node.left
    let right = node.right
    match left {
        some(child) => { total += sum(nodes, child) },
        none => {}
    }
    match right {
        some(child) => { total += sum(nodes, child) },
        none => {}
    }
    total
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let depth = if run { RUN_DEPTH } else { TEST_DEPTH }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    var result = 0L
    for _round: long in 0L..(warmup + iterations) {
        var nodes: pool<Node<nodes>, 2097151> = pool {}
        let root = build(nodes, 0, depth)
        let total = sum(nodes, root)
        result = (result + ((total % MODULUS) + MODULUS) % MODULUS) % MODULUS
    }
    print(result)
}
