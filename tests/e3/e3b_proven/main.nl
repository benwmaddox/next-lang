fn main() {
    var values: list<int, 2> = list {}
    for index in 0..2 {
        values.push(index)
    }
    print(values)
    print(values.push(5))
    print(values)
}
