struct Rock { value: int }
struct State { nodes: pool<Rock, 1>, value: int }

fn main() {
    var state: State = State { nodes: pool {}, value: 0 }
    state = State { nodes: pool {}, value: 0 }
}
