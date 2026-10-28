fn relocation_seed() {
    var scratch: list<bool, 300000> = list {}
    discard scratch.push(true)
}

fn main() {
    var values: list<int, 2> = [1]
    relocation_seed()
    discard values.push(2)
    print(values)
}
