struct Node<P> { parent: Option<Id<P>>, value: int }
struct App<P> { nodes: pool<Node<P>, 2, P>, score: int }
global app: App<app.nodes> = App { nodes: pool {}, score: 5 }

fn main() {
    let id: app.nodes.Id = app.nodes.add(Node { parent: none, value: 9 }).unwrap()
    var ids: list<app.nodes.Id, 2> = list {}
    ids.push(id).unwrap()
    print(app.nodes.get(ids[0]).unwrap().value)
    print(app.nodes.count())
}
