fn main() { var values: list<long, 2> = list {}; discard values.push(1L); for item in values { values.insert(0L, 2L) } }
