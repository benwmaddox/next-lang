fn main() {
    var values: set<int, 2> = set {}
    values.add(1).unwrap()
    for key in values { values.remove(key) }
}
