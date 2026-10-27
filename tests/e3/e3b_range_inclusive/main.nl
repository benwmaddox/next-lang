fn main() {
    var values: list<int, 3> = list {}
    for index in 1..=3 {
        discard values.push(index)
    }
    print(values)
}
