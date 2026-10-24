fn recur(value: int) -> int {
    let callback: fn(int) -> int = recur
    callback(value)
}

fn main() {
    print(recur(1))
}
