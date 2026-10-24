fn main() {
    var values: list<long, 2> = list {}
    discard values.push(1L)
    for item, index in values { index = 0L }
}
