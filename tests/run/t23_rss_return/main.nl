fn make() -> list<long, 2000000> {
    var values: list<long, 2000000> = list {}
    discard values.push(25L)
    values
}

fn main() {
    let values = make()
    print(values[0L])
}
