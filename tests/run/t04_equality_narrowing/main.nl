type Size = int 1..=3

fn smaller(r: Size) -> Size {
    if r == 1 { return 1 }
    r - 1
}

fn not_one(r: Size) -> Size {
    if r != 1 { return r - 1 }
    r
}

fn upper_endpoint(r: Size) -> Size {
    if r == 3 { return r - 2 }
    r + 1
}

fn conjunction(r: Size) -> Size {
    if r == 1 && r >= 1 { return 2 - r }
    r
}

fn disjunction(r: Size) -> Size {
    if r == 1 || r < 1 { return 1 }
    r - 1
}

fn loop_with_continue() -> Size {
    var result: Size = 1
    for r in 1..=3 {
        if r == 1 { continue }
        result = r - 1
    }
    result
}

fn main() {
    print(smaller(1))
    print(smaller(3))
    print(not_one(1))
    print(not_one(2))
    print(upper_endpoint(2))
    print(upper_endpoint(3))
    print(conjunction(1))
    print(disjunction(3))
    print(loop_with_continue())
}
