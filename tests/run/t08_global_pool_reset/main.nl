struct Node<P> { parent: Option<Id<P>>, value: int }
struct App<P> { nodes: pool<Node<P>, 2, P>, score: int }
global app: App<app.nodes> = App { nodes: pool {}, score: 5 }

fn main() {
    app = App { nodes: pool {}, score: 0 }
}
