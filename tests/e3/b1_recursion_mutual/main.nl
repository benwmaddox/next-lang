recursive fn alpha(depth: long) -> long {
    if depth == 0L { 10L } else { beta(depth - 1L) + 1L }
}

recursive fn beta(depth: long) -> long {
    if depth == 0L {
        20L
    } else if depth == 1L {
        alpha(depth - 1L) + 2L
    } else {
        gamma(depth - 1L) + 3L
    }
}

recursive fn gamma(depth: long) -> long {
    if depth == 0L { 30L } else { beta(depth - 1L) + 4L }
}

recursive fn marked_acyclic(value: long) -> long {
    value * 2L
}

fn main() {
    print(alpha(3L))
    print(beta(2L))
    print(gamma(2L))
    print(marked_acyclic(5L))
}
