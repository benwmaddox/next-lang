recursive fn descend(n: int) -> int {
    if n == 0 { 0 } else { descend(n - 1) + 1 }
}

fn main() {
    print(descend(10000))
}
