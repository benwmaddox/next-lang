recursive fn alpha(depth: long) -> long {
    if depth == 0L { 0L } else { beta(depth - 1L) }
}

fn beta(depth: long) -> long {
    if depth == 0L { 1L } else { alpha(depth - 1L) + gamma(depth - 1L) }
}

recursive fn gamma(depth: long) -> long {
    if depth == 0L { 2L } else { beta(depth - 1L) }
}

fn main() {
    print(alpha(1L))
}
