struct State { score: int }
global app: State = State { score: 0 }

fn update(value: int) -> int {
    app.score += value
    app.score
}

fn main() {
    let callback: fn(int) -> int effects reads app.score = update
    print(callback(2))
}
