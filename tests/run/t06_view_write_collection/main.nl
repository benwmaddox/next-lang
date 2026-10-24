fn mutate(values: write list<long, 2>) {}
fn main() { var values: list<long, 2> = list {}; discard values.push(1L); for item in values { mutate(values) } }
