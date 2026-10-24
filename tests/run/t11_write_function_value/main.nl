fn increment(value: write int) {
    value += 1
}

fn apply(callback: fn(write int), value: write int) {
    callback(value)
}

fn main() {
    let callback: fn(write int) = increment
    var value = 40
    apply(callback, value)
    print(value)
}
