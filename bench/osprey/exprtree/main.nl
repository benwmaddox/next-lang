const MINSTD: long = 16807L
const MODULUS: long = 2147483647L
const BIG_MOD: long = 1000000007L

fn r1(x: long) -> long {
    (x * MINSTD) % MODULUS
}

fn hash_at(s: long, i: long) -> long {
    r1(r1(s + i))
}

// Stands in for the reference's stdin read: the first argument is the seed
// selector. "0" means seed 1; any other decimal number selects another seed
// (the reference uses a random one there).
fn read_seed(env: Env) -> long {
    match env.args().get(0L) {
        some(argument) => {
            var m = 0L
            for i: long in 0L..argument.count() {
                let digit = argument.get(i).unwrap().to_long() - 48L
                m = (m * 10L + digit) % 2147483646L
            }
            if m == 0L { 1L } else { m + 1L }
        }
        none => 1L
    }
}

enum Op { Lit, Add, Mul }

// Stage 0 has no generic enums, so an expression node is a struct: `value` is
// used by Lit, `left` and `right` by Add and Mul.
struct Expr<P> {
    op: Op
    value: long
    left: Option<Id<P>>
    right: Option<Id<P>>
}

recursive fn build<P, N>(nodes: write pool<Expr<P>, N, P>, s: long, idx: long, depth: long) -> Id<P> {
    if depth == 0L {
        nodes.add(Expr { op: Op.Lit, value: hash_at(s, idx) % 1000L, left: none, right: none }).unwrap()
    } else {
        let op = hash_at(s, idx) % 2L
        let l = build(nodes, s, idx * 2L + 1L, depth - 1L)
        let r = build(nodes, s, idx * 2L + 2L, depth - 1L)
        let kind = if op == 0L { Op.Add } else { Op.Mul }
        nodes.add(Expr { op: kind, value: 0L, left: some(l), right: some(r) }).unwrap()
    }
}

recursive fn eval<P, N>(nodes: pool<Expr<P>, N, P>, id: Id<P>) -> long {
    let e = nodes.get(id).unwrap()
    match e.op {
        Lit => e.value
        Add => (eval(nodes, e.left.unwrap()) + eval(nodes, e.right.unwrap())) % BIG_MOD
        Mul => (eval(nodes, e.left.unwrap()) * eval(nodes, e.right.unwrap())) % BIG_MOD
    }
}

fn main(env: Env) {
    let seed = read_seed(env)
    var acc = 0L
    for t: long in 0L..10L {
        var nodes: pool<Expr<nodes>, 32767> = pool {}
        let root = build(nodes, seed + t * 7L, 1L, 14L)
        acc = (acc + eval(nodes, root)) % BIG_MOD
    }
    print(acc)
}
