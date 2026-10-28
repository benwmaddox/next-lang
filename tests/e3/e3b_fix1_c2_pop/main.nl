fn relocation_seed() {
    var scratch: list<bool, 300000> = list {}
    discard scratch.push(true)
}

fn main() {
    var values: list<int, 4> = list {}
    relocation_seed()
    for index in 0..2 {
        discard values.push(index)
        let removed = values.pop()
        match removed {
            some(value) => (),
            none => (),
        }
    }
    discard values.push(9)
    print(values)
}
