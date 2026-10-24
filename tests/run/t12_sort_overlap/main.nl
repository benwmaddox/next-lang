fn compare(ctx: long, left: long, right: long) -> bool { left < right }

fn main() {
    var values: list<long, 2> = list {}
    discard values.push(2L)
    discard values.push(1L)
    sort_by(values, values[0L], compare)
}
