struct Item {
    id: int
    tags: list<int, 4>
}

struct Node {
    value: int
    kids: list<int, 4>
}

struct World {
    nodes: pool<Node, 8>
}

fn main() {
    var items: list<Item, 4> = list {}
    var t1: list<int, 4> = list {}
    discard t1.push(5)
    discard t1.push(6)
    var t2: list<int, 4> = list {}
    discard t2.push(7)
    discard items.push(Item { id: 1, tags: t1 })
    discard items.push(Item { id: 2, tags: t2 })
    var total = 0
    for item in items {
        for tag in item.tags { total += item.id * tag }
    }
    print(total)

    var world = World { nodes: pool {} }
    var k: list<int, 4> = list {}
    discard k.push(3)
    discard k.push(4)
    let a = match world.nodes.add(Node { value: 10, kids: k }) {
        ok(id) => id,
        err(_) => -1L,
    }
    var sum = 0
    for kid in world.nodes[a].kids { sum += kid }
    print(sum)
    var ids: list<Id<nodes>, 4> = list {}
    discard ids.push(a)
    for id in ids {
        for kid in world.nodes[id].kids { sum += kid * 10 }
    }
    print(sum)
}
