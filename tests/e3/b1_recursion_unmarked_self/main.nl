fn walk(depth: long) -> long {
    if depth == 0L { 0L } else { walk(depth - 1L) }
}

fn main() {
    print(walk(1L))
}
