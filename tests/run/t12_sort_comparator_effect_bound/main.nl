fn less(ctx: int, a: int, b: int) -> bool {
    a < b
}

fn main() {
    let callback: fn(int, int, int) -> bool effects out = less
    var values: list<int, 2> = list {}
    sort_by(values, 0, callback)
}
