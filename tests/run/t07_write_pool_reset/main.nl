struct Rock { value: int }
struct State { nodes: pool<Rock, 1>, value: int }

fn reset(state: write State) {
    state = State { nodes: pool {}, value: 0 }
}

fn main() {
    var state: State = State { nodes: pool {}, value: 0 }
    reset(state)
}
