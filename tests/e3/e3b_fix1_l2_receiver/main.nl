struct Item {
    value: int
}

fn read_value(item: Item, ignored: int) -> int { item.value }

fn replace(item: write Option<Item>) -> int {
    item = some(Item { value: 9 })
    0
}

fn main() {
    var item: Option<Item> = some(Item { value: 1 })
    print(item?.read_value(replace(item)))
    print(item)
}
