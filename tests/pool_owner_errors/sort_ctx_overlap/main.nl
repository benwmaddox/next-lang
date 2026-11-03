struct Bag { items: list<long, 4>, bias: long }

fn before(bag: Bag, a: long, b: long) -> bool { a + bag.bias < b + bag.bias }

fn main() {
    var bag = Bag { items: list {}, bias: 0L }
    bag.items.push(2L).unwrap()
    bag.items.push(1L).unwrap()
    sort_by(bag.items, bag, before)
}
