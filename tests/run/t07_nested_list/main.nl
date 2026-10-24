struct Item { value: int }
struct Crate { items: list<Item, 2> }

fn main() {
    var crates: pool<Crate, 2> = pool {}
    let first = crates.add(Crate { items: list {} }).unwrap()
    let second = crates.add(Crate { items: list {} }).unwrap()
    for item, id in crates {
        discard item.items.push(Item { value: 5 })
    }
    print(crates.get(first).unwrap().items.count())
    print(crates.get(second).unwrap().items.count())
    for item, id in crates {
        discard item.items.push(Item { value: 9 })
    }
    print(crates.get(first).unwrap().items.count())
    print(crates.get(second).unwrap().items.count())
}
