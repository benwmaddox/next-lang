fn make_list() -> list<long, 2> {
    var values: list<long, 2> = list {}
    discard values.push(3L)
    discard values.push(5L)
    values
}
const VALUES: list<long, 2> = make_list()
const GRID: long[2] = fill(7L)
fn left() -> list<long, 2> { print(1); make_list() }
fn right() -> list<long, 2> { print(2); make_list() }
fn main() { print(777) }
