fn change(value: write int, values: write list<int, 2>) {}
fn main() {
    var values: list<int, 2> = [1]
    change(values[0L], values)
}
