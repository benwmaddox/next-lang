struct Node { value: int }

fn main() {
    var first: pool<Node, 4> = pool {}
    var second: pool<Node, 4> = pool {}
    match first.add(Node { value: 1 }) {
        ok(id) => {
            match second.get(id) {
                some(node) => print(node.value),
                none => print("none"),
            }
        },
        err(_) => {},
    }
}
