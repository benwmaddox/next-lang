struct State { values: list<long, 2> }
global app: State = State {}

fn compare(ctx: long, left: long, right: long) -> bool {
    app.values.count() > 0 && left < right
}

fn main() {
    sort_by(app.values, 0L, compare)
}
