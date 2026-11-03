enum Kind { A, B, C, D }

fn name(k: Kind) -> int {
    match k {
        A | B => 1
        C => 2
        D => 3
    }
}

fn spread(k: Kind) -> int {
    match k {
        Kind.D | Kind.A => 10
        B => 20
        C => 30
    }
}

fn small(n: int) -> int {
    match n {
        0 | 1 | 2 => 100
        -1 | 7 => 200
        _ => 300
    }
}

fn flag(b: bool) -> int {
    match b {
        true | false => 5
    }
}

fn main() {
    let kinds: list<Kind, 4> = [Kind.A, Kind.B, Kind.C, Kind.D]
    var total = 0
    for k in kinds {
        total += name(k)
        print(spread(k))
    }
    print(total)
    for n in -1..9 {
        print(small(n))
    }
    print(flag(true) + flag(false))
}
