#[derive(Clone, Copy)]
struct Item {
    value: i64,
}

struct Group {
    items: Vec<Item>,
}

fn main() {
    let mut checksum: i64 = 0;
    let mut seed: i64 = 1;

    for _iter in 0..40000 {
        let mut groups: Vec<Group> = Vec::new();
        let group_count = (seed % 200) + 1;

        for _g in 0..group_count {
            seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
            let mut items: Vec<Item> = Vec::new();
            let item_count = (seed % 100) + 1;

            for _i in 0..item_count {
                seed = (seed.wrapping_mul(1103515245).wrapping_add(12345)) % 2147483648;
                items.push(Item { value: seed });
            }

            groups.push(Group { items });
        }

        for group in &groups {
            for item in &group.items {
                checksum = (checksum.wrapping_mul(31).wrapping_add(item.value)) % 1000000007;
            }
        }
    }

    println!("{}", checksum);
}
