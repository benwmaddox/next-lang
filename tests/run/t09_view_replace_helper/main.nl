fn replace(target: write int) {
    target = 20
}

fn main() {
    var values: map<int, int, 2> = map {}
    values.set(1, 10).unwrap()
    for value, key in values { replace(value) }
}
