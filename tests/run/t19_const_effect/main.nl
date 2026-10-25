recursive fn first(n: int) -> int {
    if n == 0 { 0 } else { second(n - 1) }
}

recursive fn second(n: int) -> int {
    print(n)
    if n == 0 { 0 } else { first(n - 1) }
}

const BAD: int = first(4)

fn main() {}
