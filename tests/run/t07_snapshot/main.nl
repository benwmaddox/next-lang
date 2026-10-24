struct Item { value: int }

fn main() {
    var items: pool<Item, 3> = pool {}
    let first = items.add(Item { value: 1 }).unwrap()
    for item, id in items {
        discard items.add(Item { value: item.value + 1 })
    }
    print(items.count())
    print(items.get(first).unwrap().value)
    for item, id in items {
        item.value += 10
    }
    print(items.get(first).unwrap().value)
}
