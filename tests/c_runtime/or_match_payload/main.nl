enum Op { Add(int), Sub(int), Mul(int, int), Swap(int, int), Neg(long), Nop }

fn amount(op: Op) -> int {
    match op {
        Add(x) | Sub(x) => x * 10
        Mul(a, b) | Swap(b, a) => a - b
        Neg(_) | Nop => 0
    }
}

fn describe(o: Option<int>) -> int {
    match o {
        some(x) => x
        none => -1
    }
}

fn main() {
    let ops: list<Op, 8> = [Op.Add(1), Op.Sub(2), Op.Mul(9, 4), Op.Swap(9, 4), Op.Neg(5L), Op.Nop]
    var total = 0
    for op in ops {
        let v = amount(op)
        print(v)
        match op {
            Add(x) | Sub(x) => { total += x }
            Neg(_) | Nop => { total += 100 }
            Mul(_, _) | Swap(_, _) => { total += 1000 }
        }
    }
    print(total)
    print(describe(some(3)) + describe(none))
    print(nested(Op.Sub(3), Op.Nop))
    print(nested(Op.Add(3), Op.Sub(4)))
    print(nested(Op.Add(3), Op.Swap(1, 2)))
    print(nested(Op.Nop, Op.Nop))
}

fn nested(a: Op, b: Op) -> int {
    var n = 0
    for step in 0..2 {
        n += match a {
            Add(x) | Sub(x) => match b {
                Nop | Neg(_) => x
                Add(y) | Sub(y) => x * y
                Mul(_, _) | Swap(_, _) => -x
            }
            _ => 0
        }
    }
    n
}
