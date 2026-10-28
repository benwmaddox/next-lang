fn relocation_seed() {
    var scratch: list<bool, 300000> = list {}
    discard scratch.push(true)
}

fn main() {
    var values: list<int, 2> = list {}
    relocation_seed()
    let full: list<int, 2> = [8, 8]
    for index in 0..1 {
        discard values.push(index)
        values = full
    }
    discard values.push(9)
    print(values)
}
