fn main() {
    var values: map<int, int, 2> = map {}
    values.set(1, 10).unwrap()
    for value, key in values { value = 20 }
}
