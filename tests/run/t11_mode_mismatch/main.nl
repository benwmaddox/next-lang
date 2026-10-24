fn change(value: write int) {
    value += 1
}

fn main() {
    let callback: fn(int) = change
    callback
}
