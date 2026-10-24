struct Rock { value: int }
struct State { nodes: pool<Rock, 1> }

fn main() {
    var left: State = State { nodes: pool {} }
    var right: State = State { nodes: pool {} }
    let id = left.nodes.add(Rock { value: 1 }).unwrap()
    let missing = right.nodes.get(id)
}
