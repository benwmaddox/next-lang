fn relocation_seed() {
    var scratch: list<bool, 300000> = list {}
    discard scratch.push(true)
}

fn main() {
    var values: list<int, 4> = list {}
    relocation_seed()
    for index in 0..2 {
        discard values.push(index)
        discard values.insert(0L, index)
    }
    discard values.push(9)
    print(values)
}
