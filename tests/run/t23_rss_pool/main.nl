struct Item { value: long = 0L }

fn main() {
    var values: pool<Item, 2000000> = pool {}
    discard values.add(Item { value: 26L })
    print(values.count())
}
