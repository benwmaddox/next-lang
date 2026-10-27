fn main() {
    var values: list<int, 2> = list {}
    for index in 0..2 {
        if index == 0 {
            values.push(3)
        } else {
            values.push(4)
        }
    }
    print(values)
}
