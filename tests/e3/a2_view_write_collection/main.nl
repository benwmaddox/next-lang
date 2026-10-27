fn change(values: write list<int, 2>) {}
fn main() {
    var values: list<int, 2> = [1]
    for value in values { change(values) }
}
