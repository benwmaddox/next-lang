struct LargePack { padding: long[513], items: list<int, 2> }

fn grow_value() -> int {
    let scratch: list<bool, 300000> = list {}
    9
}
fn update_large(value: write LargePack) { value.items[0L] = grow_value() }

fn main() {
    var large = LargePack { padding: fill(0L), items: [2] }
    update_large(large)
    print(large.items)
}
