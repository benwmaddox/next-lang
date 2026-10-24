struct Item { value: int }

fn main() {
    var items: pool<Item, 2> = pool {}
    let a = items.add(Item { value: 3 }).unwrap()
    let b = items.add(Item { value: 4 }).unwrap()
    var ids: list<Id<items>, 2> = list {}
    for item, id in items {
        discard ids.push(id)
    }
    for id in ids {
        print(items.remove(id).is_some())
    }
    print(items.count())
    print(items.get(a).is_none())
    print(items.get(b).is_none())
}
