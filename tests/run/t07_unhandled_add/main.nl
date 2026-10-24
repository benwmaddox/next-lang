struct Item { value: int }

fn main() {
    var items: pool<Item, 2> = pool {}
    for index in 0..3 {
        items.add(Item { value: index })
    }
}
