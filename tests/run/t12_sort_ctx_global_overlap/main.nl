struct State { values: list<long, 2> }
global app: State = State {}

fn make_context() -> long { app.values.count() }
fn compare(ctx: long, left: long, right: long) -> bool { left < right }

fn main() {
    sort_by(app.values, make_context(), compare)
}
