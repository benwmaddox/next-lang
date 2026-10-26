struct Item {
    value: long
}

struct Group {
    items: list<Item, 128>
}

fn main() {
    var checksum = 0L
    var seed = 1L

    for _iter: long in 0L..40000L {
        var groups: list<Group, 256> = list {}
        let group_count = (seed % 200L) + 1L

        for _g: long in 0L..group_count {
            seed = (seed * 1103515245L + 12345L) % 2147483648L
            var items: list<Item, 128> = list {}
            let item_count = (seed % 100L) + 1L

            for _i: long in 0L..item_count {
                seed = (seed * 1103515245L + 12345L) % 2147483648L
                discard items.push(Item { value: seed })
            }

            discard groups.push(Group { items: items })
        }

        for group in groups {
            for item in group.items {
                checksum = (checksum * 31L + item.value) % 1000000007L
            }
        }
    }

    print(checksum)
}
