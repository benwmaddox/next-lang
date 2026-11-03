struct Node { v: long }
struct World { nodes: pool<Node, 8>, n: long }
fn make(n: long) -> World { World { nodes: pool {}, n } }
fn make_twice() -> World { make(7L) }
fn make_pool() -> pool<Node, 4> { pool {} }
fn fill(world: write World) -> Id<nodes> {
  world.nodes.add(Node { v: world.n }).unwrap()
}
fn main() {
  var w = make_twice()
  let a = fill(w)
  print(w.nodes[a].v)
  var p = make_pool()
  let b = p.add(Node { v: 9 }).unwrap()
  print(p[b].v)
  print(p.count())
}
