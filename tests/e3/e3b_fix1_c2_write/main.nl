fn relocation_seed() {
    var scratch: list<bool, 300000> = list {}
    discard scratch.push(true)
}

fn fill_up(values: write list<int, 4>) {
    discard values.push(1)
    discard values.push(1)
}

fn main() {
    var values: list<int, 4> = list {}
    relocation_seed()
    for index in 0..2 {
        discard values.push(index)
        fill_up(values)
    }
    discard values.push(9)
    print(values)
}
