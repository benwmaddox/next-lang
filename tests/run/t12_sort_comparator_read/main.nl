global app: int = 0

fn less(ctx: int, a: int, b: int) -> bool {
    app == 0 && a < b
}

fn main() {
    var values: list<int, 2> = list {}
    sort_by(values, 0, less)
}
