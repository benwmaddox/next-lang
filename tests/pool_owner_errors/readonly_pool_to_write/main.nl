struct Node { value: long }
struct World { nodes: pool<Node, 8>, count: long }

fn bump(h: write World) { h.count += 1L }

fn look(h: World) -> long {
    bump(h)
    h.count
}

fn main() {
    var world = World { nodes: pool {}, count: 0L }
    print(look(world))
}
