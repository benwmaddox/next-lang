struct SmallPack { items: list<int, 2> }

fn grow_value() -> int {
    let scratch: list<bool, 300000> = list {}
    9
}
fn update_small(value: write SmallPack) { value.items[0L] = grow_value() }

fn main() {
    var small = SmallPack { items: [1] }
    update_small(small)
    print(small.items)
}
