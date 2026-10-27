fn seed() -> int {
    print(91)
    5
}

fn main() {
    var values: int[3] = [1, 2, 3]
    print(values.len())
    print(values)
    values[1L] = 8
    values[0L] += 2
    print(values)

    let repeated: bool[3] = fill(true)
    print(repeated)
    let seeded: int[2] = fill(seed())
    print(seeded)
    let zero_array: int[0] = []
    print(zero_array.len())
    print(zero_array)

    var items: list<int, 4> = list {}
    print(items.count())
    discard items.push(2)
    discard items.push(4)
    discard items.insert(1L, 3)
    print(items)
    print(items.remove(0L))
    let copied: list<int, 4> = items
    discard items.push(9)
    print(items == copied)
    print(copied)
    items.clear()
    print(items)

    var full: list<int, 1> = [6]
    discard full.push(7)
    discard full.insert(0L, 8)
    print(full)
    let full_copy: list<int, 1> = full
    print(full_copy)
    print(full_copy == full)
}
