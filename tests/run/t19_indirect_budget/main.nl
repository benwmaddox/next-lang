recursive fn descend(n: int) -> int {
    if n == 0 {
        0
    } else {
        let callback: fn(int) -> int = descend
        callback(n - 1) + 1
    }
}

fn main() {
    print(descend(10000))
}
