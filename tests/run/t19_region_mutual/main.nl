recursive fn first(n: int) -> int {
    var scratch: int[2048] = fill(n)
    if n == 0 { scratch[0] } else { second(n - 1) + scratch[0] }
}

recursive fn second(n: int) -> int {
    first(n)
}

fn main() {
    print(first(2))
}
