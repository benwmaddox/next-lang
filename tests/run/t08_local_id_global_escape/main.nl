struct Node<P> { parent: Option<Id<P>>, value: int }
struct App<P> { nodes: pool<Node<P>, 2, P> }
global app: App<app.nodes> = App { nodes: pool {} }
global saved: Option<app.nodes.Id> = none

fn main() {
    var local: pool<Node<local>, 2> = pool {}
    let id = local.add(Node { parent: none, value: 1 }).unwrap()
    saved = some(id)
}
