// Binarytrees::Arena: nodes in one array, children named by index (-1 for none).
const TEST_DEPTH: int = 4
const TEST_ITERATIONS: long = 3L
const RUN_DEPTH: int = 20
const RUN_ITERATIONS: long = 30L
const MODULUS: long = 4294967296L

struct Node {
    item: int
    left: int
    right: int
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

recursive fn build(arena: write list<Node, 2097151>, item: int, depth: int) -> int {
    let index = (int)arena.count()
    arena.push(Node { item: item, left: -1, right: -1 }).unwrap()
    if depth > 0 {
        let step = 1 << (depth - 1)
        let left = build(arena, item - step, depth - 1)
        let right = build(arena, item + step, depth - 1)
        arena[index.to_long()].left = left
        arena[index.to_long()].right = right
    }
    index
}

// The signed sum of (item + 1) over the subtree; reduced modulo 2^32 by the caller.
recursive fn sum(arena: list<Node, 2097151>, index: int) -> long {
    let node = arena[index.to_long()]
    var total = node.item.to_long() + 1L
    if node.left >= 0 { total += sum(arena, node.left) }
    if node.right >= 0 { total += sum(arena, node.right) }
    total
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let depth = if run { RUN_DEPTH } else { TEST_DEPTH }
    let iterations = if run { RUN_ITERATIONS } else { TEST_ITERATIONS }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }
    var result = 0L
    for _round: long in 0L..(warmup + iterations) {
        var arena: list<Node, 2097151> = list {}
        let root = build(arena, 0, depth)
        let total = sum(arena, root)
        result = (result + ((total % MODULUS) + MODULUS) % MODULUS) % MODULUS
    }
    print(result)
}
