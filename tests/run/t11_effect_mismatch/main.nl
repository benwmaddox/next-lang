fn announce(value: int) -> int {
    print(value)
    value
}

fn main() {
    let callback: fn(int) -> int = announce
    print(callback(1))
}
