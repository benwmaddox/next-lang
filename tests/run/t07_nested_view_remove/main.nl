struct Item { value: int }
struct Crate { items: list<Item, 2> }

fn main() {
    var crates: pool<Crate, 2> = pool {}
    let id = crates.add(Crate { items: list {} }).unwrap()
    for crate, outer_id in crates {
        for item in crate.items {
            let removed = crates.remove(outer_id)
        }
    }
}
