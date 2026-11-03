struct Node { v: long }
struct Label { text: Ascii max 8 }
struct Point { x: long, y: long }
struct Big { head: long, data: long[3000], tail: long }

struct World {
    nodes: pool<Node, 8>
    labels: pool<Label, 8>
    owner_of: map<Id<nodes>, Id<nodes>, 8>
    label_of: map<Id<nodes>, Id<labels>, 8>
    scores: map<Ascii max 8, long, 8>
}

fn total(world: World) -> long {
    var sum = 0L
    for name, score in world.scores {
        sum += score + name.len()
    }
    sum
}

fn main() {
    var scores: map<Ascii max 8, long, 8> = map {}
    scores.set("one", 1L).unwrap()
    scores.set("two", 2L).unwrap()
    scores.set("three", 3L).unwrap()
    for k, v in scores { print(k); print(v) }
    // removal then insertion: the new key goes last, an existing key keeps its place
    scores.remove("two")
    scores.set("four", 4L).unwrap()
    scores.set("one", 10L).unwrap()
    for k, v in scores { print(k); print(v) }
    var keys = 0L
    for k in scores { keys += k.len() }
    print(keys)

    var points: map<Point, Point, 8> = map {}
    points.set(Point { x: 1, y: 2 }, Point { x: 10, y: 20 }).unwrap()
    points.set(Point { x: 3, y: 4 }, Point { x: 30, y: 40 }).unwrap()
    for p, q in points { print(p.x + p.y + q.x + q.y) }

    var lists: map<int, list<long, 4>, 4> = map {}
    var l: list<long, 4> = list {}
    l.push(5L).unwrap()
    l.push(6L).unwrap()
    lists.set(7, l).unwrap()
    for k, items in lists {
        for x in items { print(x * k.to_long()) }
    }

    // churn: compaction keeps the order
    var grid: map<long, long, 4> = map {}
    for round in 0L..10L {
        grid.set(round, round * 2L).unwrap()
        if round >= 3L { grid.remove(round - 3L); () }
    }
    for k, v in grid { print(k * 100L + v) }

    // ids: the owner flows to the loop variables
    var world = World { nodes: pool {}, labels: pool {}, owner_of: map {}, label_of: map {}, scores: map {} }
    let a = world.nodes.add(Node { v: 11 }).unwrap()
    let b = world.nodes.add(Node { v: 22 }).unwrap()
    world.owner_of.set(a, b).unwrap()
    world.owner_of.set(b, a).unwrap()
    for child, parent in world.owner_of { print(world.nodes[child].v * 100L + world.nodes[parent].v) }
    let red = world.labels.add(Label { text: "red" }).unwrap()
    world.label_of.set(b, red).unwrap()
    for n, lab in world.label_of { print(world.labels[lab].text); print(world.nodes[n].v) }
    world.scores.set("ab", 5L).unwrap()
    print(total(world))

    // break and continue
    var seen = 0L
    for k, v in scores {
        if v == 3L { continue }
        seen += 1L
        if seen == 2L { break }
    }
    print(seen)
    var empty: map<long, long, 4> = map {}
    for k, v in empty { print(-1L) }
    print(0L)

    // a large value is copied into the loop variable
    var bigs: map<Ascii max 4, Big, 2> = map {}
    var payload: long[3000] = fill(0L)
    payload[2999] = 5L
    var one = Big { head: 1L, data: payload, tail: 9L }
    bigs.set("a", one).unwrap()
    for name, big in bigs { print(name); print(big.head + big.tail + big.data[2999]) }
}
