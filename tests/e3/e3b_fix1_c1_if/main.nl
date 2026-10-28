fn relocation_seed() {
    var scratch: list<bool, 300000> = list {}
    discard scratch.push(true)
}

fn main() {
    var values: list<int, 1> = list {}
    discard values.push(5)
    relocation_seed()
    let clear_it: bool = false
    if clear_it { values.clear() }
    discard values.push(7)
    print(values)
}
