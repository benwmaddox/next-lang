fn main() {
    var values: list<long, 6000000> = list {}
    discard values.push(23L)
    print(values[0L])
}
