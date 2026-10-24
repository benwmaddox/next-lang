fn mutate(values: write list<long, 2>) { discard values.push(2L) }
fn main() {
    var values: list<long, 2> = list {}
    values.push(1L)
    mutate(values)
    values.push(3L)
    print(0)
}
