struct State { values: list<long, 2> }
global app: State = State {}

fn reorder() { sort(app.values) }

fn main() {
    for value in app.values {
        reorder()
    }
}
