recursive fn never(n: int) -> int {
    never(n + 1)
}

const BAD: int = never(0)

fn main() {}
