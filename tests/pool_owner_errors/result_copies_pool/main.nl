struct Node { v: long }
struct World { nodes: pool<Node, 8> }

fn same(world: World) -> World {
    world
}

fn main() {
    var copy = same(World { nodes: pool {} })
    print(copy.nodes.count())
}
