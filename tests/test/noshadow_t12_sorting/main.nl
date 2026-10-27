enum Direction { North, East, South, West }

struct Point { x: long, y: long }
struct Unit { x: long, y: long, id: int }
struct Item { key: int, sequence: int }

fn distance_squared(point: Point, unit: Unit) -> long {
    let dx = unit.x - point.x
    let dy = unit.y - point.y
    dx * dx + dy * dy
}

fn closer(point: Point, a: Unit, b: Unit) -> bool {
    distance_squared(point, a) < distance_squared(point, b)
}

fn by_key(ctx: int, a: Item, b: Item) -> bool {
    if ctx == 0 { a.key < b.key } else { a.key > b.key }
}

fn main() { print(777) }

test "natural integer sorting handles empty, single, sorted, reverse, and full lists" {
    var empty_list: list<long, 0> = list {}
    sort(empty_list)
    expect empty_list.count() == 0

    var one: list<long, 1> = list {}
    discard one.push(9L)
    sort(one)
    expect one[0L] == 9L

    var values: list<long, 8> = list {}
    discard values.push(1L)
    discard values.push(2L)
    discard values.push(3L)
    sort(values)
    expect values[0L] == 1L && values[2L] == 3L

    var reversed: list<long, 8> = list {}
    discard reversed.push(8L)
    discard reversed.push(7L)
    discard reversed.push(6L)
    discard reversed.push(5L)
    discard reversed.push(4L)
    discard reversed.push(3L)
    discard reversed.push(2L)
    discard reversed.push(1L)
    sort(reversed)
    expect reversed[0L] == 1L && reversed[7L] == 8L
}

test "bottom-up merge sorting orders both sides of a reverse run" {
    var values: list<long, 32> = list {}
    for i in 0..32 {
        discard values.push((31 - i).to_long())
    }
    sort(values)
    for value, index in values {
        expect value == index
    }
}

test "arrays sort naturally for integer, bool, and payload-free enum values" {
    var numbers: int[4] = fill(0)
    numbers[0L] = 4
    numbers[1L] = 1
    numbers[2L] = 3
    numbers[3L] = 2
    sort(numbers)
    expect numbers[0L] == 1 && numbers[3L] == 4

    var flags: bool[3] = fill(false)
    flags[0L] = true
    flags[1L] = false
    flags[2L] = true
    sort(flags)
    expect !flags[0L] && flags[1L] && flags[2L]

    var directions: Direction[4] = fill(Direction.North)
    directions[0L] = Direction.West
    directions[1L] = Direction.East
    directions[2L] = Direction.South
    directions[3L] = Direction.North
    sort(directions)
    expect directions[0L] == Direction.North
    expect directions[1L] == Direction.East
    expect directions[2L] == Direction.South
    expect directions[3L] == Direction.West
}

test "sort_by passes a read-only context when ordering units by distance" {
    let origin = Point { x: 0L, y: 0L }
    var units: Unit[3] = fill(Unit { x: 0L, y: 0L, id: 0 })
    units[0L] = Unit { x: 3L, y: 4L, id: 1 }
    units[1L] = Unit { x: 1L, y: 1L, id: 2 }
    units[2L] = Unit { x: -1L, y: 0L, id: 3 }
    sort_by(units, origin, closer)
    expect units[0L].id == 3
    expect units[1L].id == 2
    expect units[2L].id == 1
}

test "sort_by remains stable across merge boundaries for equal keys" {
    var items: list<Item, 32> = list {}
    for i in 0..32 {
        discard items.push(Item { key: 1, sequence: i })
    }
    sort_by(items, 0, by_key)
    for item, index in items {
        expect item.sequence.to_long() == index
    }
}

test "sort_by accepts a pure comparator function value" {
    let comparator: fn(int, Item, Item) -> bool = by_key
    var items: list<Item, 3> = list {}
    discard items.push(Item { key: 3, sequence: 0 })
    discard items.push(Item { key: 1, sequence: 1 })
    discard items.push(Item { key: 2, sequence: 2 })
    sort_by(items, 0, comparator)
    expect items[0L].key == 1
    expect items[1L].key == 2
    expect items[2L].key == 3
}

test "binary_search returns the first duplicate and handles both boundaries and empty inputs" {
    let values: long[6] = fill(0L)
    var sorted: long[6] = values
    sorted[0L] = 2L
    sorted[1L] = 4L
    sorted[2L] = 4L
    sorted[3L] = 4L
    sorted[4L] = 7L
    sorted[5L] = 9L
    expect binary_search(sorted, 4L) == some(1L)
    expect binary_search(sorted, 1L) == none
    expect binary_search(sorted, 10L) == none
    let empty_list: list<long, 0> = list {}
    expect binary_search(empty_list, 4L) == none

    var list_values: list<int, 4> = list {}
    discard list_values.push(-1)
    discard list_values.push(3)
    discard list_values.push(5)
    discard list_values.push(5)
    expect binary_search(list_values, 5) == some(2L)
}
