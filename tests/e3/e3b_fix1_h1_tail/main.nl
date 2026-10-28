fn relocation_seed() {
    var scratch: list<bool, 300000> = list {}
    discard scratch.push(true)
}

fn main() {
    var values: list<int, 3> = list {}
    relocation_seed()
    let append_it: bool = true
    if append_it { values.push(1) }
    print(values)
}
