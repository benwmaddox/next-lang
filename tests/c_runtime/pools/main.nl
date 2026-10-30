// Pools: add returns an id, get looks one up, a full pool refuses another element, and a function
// generic in the pool's capacity works on any pool. (One pool variable per package until owners are checked.)
struct Item {
    weight: int
    name: Ascii max 8
}

fn add_items<N>(items: write pool<Item, N>, count: int) -> long {
    var last = -1L
    for index: int in 0..count {
        let item = Item { weight: index * 10, name: "item" }
        match items.add(item) {
            ok(id) => { last = id },
            err(_) => {},
        }
    }
    last
}

fn weight_of<N>(items: pool<Item, N>, id: long) -> int {
    match items.get(id) {
        some(item) => item.weight,
        none => -1,
    }
}

fn main() {
    var small: pool<Item, 3> = pool {}
    print(add_items(small, 5))
    print(small.count())
    print(weight_of(small, 0L))
    print(weight_of(small, 2L))
    print(weight_of(small, 3L))
    print(weight_of(small, -1L))
    let extra = Item { weight: 1, name: "x" }
    match small.add(extra) {
        ok(_) => print("added"),
        err(_) => print("full"),
    }
    match small.get(1L) {
        some(item) => print(item.name),
        none => print("none"),
    }
}
