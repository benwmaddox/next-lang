struct Cell { value: long = 0L }
fn index(calls: write int) -> long { print(1); calls += 1; 0L }
fn value(calls: write int) -> Cell { print(2); calls += 1; Cell { value: 3L } }
fn argument(calls: write int, marker: long) -> long { print(marker); calls += 1; 0L }
fn set_pair(left: write long, right: write long) { left = 4L; right = 5L }
fn insert_index(calls: write int) -> long { print(3); calls += 1; 0L }
fn insert_value(calls: write int) -> long { print(4); calls += 1; 8L }
fn main() {
    var index_calls = 0
    var value_calls = 0
    var cells: Cell[1]
    cells[index(index_calls)] = value(value_calls)
    print(index_calls)
    print(value_calls)
    print(cells)

    var first: long[1] = fill(0L)
    var second: long[1] = fill(0L)
    var argument_calls = 0
    set_pair(first[argument(argument_calls, 1L)], second[argument(argument_calls, 2L)])
    print(argument_calls)
    print(first)
    print(second)

    var list_calls = 0
    var values: list<long, 2> = list {}
    discard values.push(9L)
    print(values.insert(insert_index(list_calls), insert_value(list_calls)))
    print(list_calls)
    print(values)
}
