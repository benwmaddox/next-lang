fn coin(k: long) -> long {
    match k {
        1L => 1L
        2L => 5L
        3L => 10L
        4L => 25L
        _ => 50L
    }
}

recursive fn ways(amount: long, kind: long) -> long {
    if amount == 0L {
        1L
    } else if amount < 0L {
        0L
    } else if kind == 0L {
        0L
    } else {
        ways(amount - coin(kind), kind) + ways(amount, kind - 1L)
    }
}

fn main() {
    print(ways(600L, 5L))
}
