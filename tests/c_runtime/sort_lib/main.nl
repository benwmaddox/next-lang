struct Node { v: long, tag: long }
struct World { nodes: pool<Node, 8>, bias: long }
struct Rule { descending: bool, weight: long }
struct Item { key: long, order: long }

fn by_value(world: World, a: Id<nodes>, b: Id<nodes>) -> bool {
    world.nodes[a].v + world.bias < world.nodes[b].v + world.bias
}

fn by_key(rule: Rule, a: Item, b: Item) -> bool {
    if rule.descending { a.key * rule.weight > b.key * rule.weight } else { a.key * rule.weight < b.key * rule.weight }
}

fn by_length(prefix: Ascii max 4, a: Ascii max 8, b: Ascii max 8) -> bool {
    a.len() < b.len()
}

fn is_sorted(xs: list<long, 300>) -> bool {
    for i in 1L..xs.count() {
        if xs[i - 1L] > xs[i] { return false }
    }
    true
}

fn main() {
    // text
    var names: list<Ascii max 8, 8> = list {}
    names.push("pear").unwrap()
    names.push("apple").unwrap()
    names.push("fig").unwrap()
    names.push("app").unwrap()
    names.push("").unwrap()
    sort(names)
    for n in names { print(n) }
    var texts: (Bytes max 8)[3] = [b"b", b"a", b"ab"]
    sort(texts)
    for t in texts { print(t) }

    // numbers: bytes above 127 sort as unsigned, floats and doubles by value, negatives
    var bytes: list<byte, 6> = list {}
    bytes.push(200).unwrap()
    bytes.push(5).unwrap()
    bytes.push(130).unwrap()
    sort(bytes)
    for b in bytes { print(b == 5) ; print(b > 129) }
    var doubles: list<double, 4> = list {}
    doubles.push(2.5).unwrap()
    doubles.push(-1.5).unwrap()
    doubles.push(0.25).unwrap()
    sort(doubles)
    print(doubles[0] < doubles[1] && doubles[1] < doubles[2])
    var floats: float[3] = [3.0, 1.0, 2.0]
    sort(floats)
    print(floats[0] < floats[1] && floats[1] < floats[2])
    var negatives: list<int, 5> = list {}
    negatives.push(3).unwrap()
    negatives.push(-7).unwrap()
    negatives.push(0).unwrap()
    sort(negatives)
    for n in negatives { print(n) }

    // a record context holding a pool, read in place
    var world = World { nodes: pool {}, bias: 1L }
    var ids: list<Id<nodes>, 4> = list {}
    ids.push(world.nodes.add(Node { v: 30, tag: 0 }).unwrap()).unwrap()
    ids.push(world.nodes.add(Node { v: 10, tag: 0 }).unwrap()).unwrap()
    ids.push(world.nodes.add(Node { v: 20, tag: 0 }).unwrap()).unwrap()
    sort_by(ids, world, by_value)
    for i in ids { print(world.nodes[i].v) }

    // stable, with a record context, ascending and descending
    var items: list<Item, 12> = list {}
    for i in 0L..9L { items.push(Item { key: i % 3L, order: i }).unwrap() }
    let ascending = Rule { descending: false, weight: 1L }
    sort_by(items, ascending, by_key)
    for it in items { print(it.key * 10L + it.order) }
    let rule = Rule { descending: true, weight: 2L }
    sort_by(items, rule, by_key)
    for it in items { print(it.key * 10L + it.order) }

    // a text context
    var words: list<Ascii max 8, 4> = list {}
    words.push("ccc").unwrap()
    words.push("a").unwrap()
    words.push("bb").unwrap()
    let marker: Ascii max 4 = "x"
    sort_by(words, marker, by_length)
    for w in words { print(w) }

    // many elements
    var big: list<long, 300> = list {}
    var seed = 12345L
    for i in 0L..300L {
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        big.push(seed % 1000L).unwrap()
    }
    sort(big)
    print(is_sorted(big))
    sort(big)
    print(is_sorted(big))
}
