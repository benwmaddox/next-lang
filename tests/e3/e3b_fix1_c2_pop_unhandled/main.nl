fn main() {
    var values: list<int, 4> = list {}
    for index in 0..2 {
        discard values.push(index)
        let removed = values.pop()
        match removed {
            some(value) => (),
            none => (),
        }
    }
    values.push(9)
}
