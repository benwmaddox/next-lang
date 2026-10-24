type Small = int 0..=3
enum Mark { Off, On }
struct Cell { value: long = 0L, active: bool = false }
struct RefinedCell { value: Small = 1 }
struct Pair { left: long = 0L, right: long = 0L }
struct Unit { id: long = 0L, inventory: list<long, 2> = list {} }

fn bump(value: write int) -> long {
    value += 1
    value.to_long()
}

fn make_list() -> list<long, 3> {
    var values: list<long, 3> = list {}
    discard values.push(2L)
    discard values.push(4L)
    values
}
fn make_marks() -> list<Mark, 2> {
    var marks: list<Mark, 2> = list {}
    discard marks.push(Mark.Off)
    discard marks.push(Mark.On)
    marks
}

fn pass_list(values: list<long, 4>) -> list<long, 4> { values }
fn pass_array(values: long[2]) -> long[2] { values }
fn make_array() -> long[2] { fill(12L) }
fn no_change(values: write list<long, 4>) {}
fn sum(values: list<long, 4>) -> long {
    var total = 0L
    for value in values { total += value }
    total
}
fn maybe_step(index: long) -> Option<long> {
    if index == 1L { none } else { some(1L) }
}
fn bump_until_none(values: write list<long, 4>) -> Option<long> {
    for item, index in values {
        let step = maybe_step(index)?
        item += step
    }
    some(values.count())
}
fn first_value(values: list<long, 4>) -> Option<long> {
    for item in values { return some(item) }
    none
}
fn proven_try() -> Result<(), Full> {
    var values: list<long, 1> = list {}
    values.push(5L)?
    ok(())
}
fn proven_unwrap() {
    var values: list<long, 1> = list {}
    values.push(6L).unwrap()
    print(values)
}
fn proven_tail() {
    var values: list<long, 1> = list {}
    values.push(8L)
}
fn proven_match() -> Result<(), Full> {
    var values: list<long, 1> = list {}
    match values.push(7L) {
        ok(_) => ok(())
        err(Full) => err(Full)
    }
}
fn set_two(left: write long, right: write long) {
    left = 31L
    right = 32L
}
fn forward(left: write long, right: write long) { set_two(left, right) }

const CAPACITY: int = 3
const ITEMS: list<long, 3> = make_list()
const ITEM_COUNT: long = ITEMS.count()
const GRID: long[CAPACITY] = fill(7L)
const MARKS: list<Mark, 2> = make_marks()

fn main() {
    var calls = 0
    var filled: long[3] = fill(bump(calls))
    print(calls)
    print(filled)
    filled[0] = 4L
    print(filled[0])
    let int_index = 1
    print(filled[int_index.to_long()])
    print(filled.len())
    let zeros: int[0] = fill(9)
    print(zeros)
    var empty: list<long, 0> = list {}
    discard empty.push(1L)
    print(empty)
    let empty_rows: list<long, 2>[2]
    print(empty_rows)
    let refined: Small[2] = fill(2)
    print(refined)
    let refined_cells: RefinedCell[2]
    print(refined_cells)
    let cells: Cell[2]
    print(cells)
    let marks: Mark[2] = fill(Mark.On)
    print(marks)
    var cell_list: list<Cell, 2> = list {}
    discard cell_list.push(Cell { value: 5L, active: true })
    for cell in cell_list { cell.value += 1L }
    print(cell_list)

    var values: list<long, 3> = list {}
    print(values.pop())
    print(values.push(1L))
    print(values.push(2L))
    print(values.push(3L))
    print(values.push(9L))
    print(values)
    print(values.insert(0L, 8L))
    print(values)
    print(values.remove(1L))
    print(values)
    print(values.pop())
    print(values.count())
    values.clear()
    print(values)
    var insertions: list<long, 4> = list {}
    discard insertions.push(2L)
    discard insertions.push(3L)
    print(insertions.insert(0L, 1L))
    print(insertions.insert(insertions.count(), 4L))
    print(insertions)
    print(bump_until_none(insertions))
    print(insertions)
    print(first_value(insertions))

    var visited: list<long, 4> = list {}
    for i: long in 0L..3L { discard visited.push(i) }
    for item, i in visited { item += i }
    var exits = 0
    for item, i in visited {
        if i == 0L { continue }
        if i == 2L { break }
        exits += 1
    }
    print(exits)
    var visits = 0
    for item in visited {
        visits += 1
        discard visited.push(9L)
    }
    print(visits)
    print(visited)
    print(visited.pop())
    print(visited.insert(visited.count(), 7L))
    print(visited.remove(0L))
    visited.clear()
    print(visited)
    visited = list {}
    no_change(visited)

    var units: Unit[2]
    for i: long in 0L..units.len() {
        units[i].id = i
        discard units[i].inventory.push(10L + i)
    }
    for unit in units { discard unit.inventory.push(20L) }
    for unit in units {
        for item in unit.inventory { item += 1L }
    }
    print(units)
    var first_row: list<long, 2> = list {}
    var second_row: list<long, 2> = list {}
    discard first_row.push(4L)
    discard second_row.push(5L)
    discard second_row.push(6L)
    var matrix: list<list<long, 2>, 2> = list {}
    discard matrix.push(first_row)
    discard matrix.push(second_row)
    print(matrix)
    print(matrix[0L].count())

    var left: list<long, 3> = list {}
    discard left.push(1L)
    discard left.push(2L)
    print(left.pop())
    var right: list<long, 3> = list {}
    discard right.push(1L)
    print(left == right)
    print(ITEMS)
    print(GRID)
    let runtime_grid: long[CAPACITY] = fill(7L)
    print(GRID == runtime_grid)
    print(make_array()[0])
    print(make_list()[0L])
    let copied = pass_list(visited)
    print(copied)
    print(sum(copied))
    print(ITEMS == make_list())
    print(ITEM_COUNT)
    print(MARKS)
    print(make_list().count())
    print(Full)
    var branches: list<long, 3> = list {}
    if calls == 1 {
        discard branches.push(1L)
    } else {
        discard branches.push(1L)
        discard branches.push(2L)
    }
    branches.push(3L)
    print(branches)
    var exact: list<long, 3> = list {}
    for i: long in 0L..3L { exact.push(i) }
    print(exact)
    print(match exact.push(4L) { ok(_) => false, err(Full) => true })
    print(proven_try())
    print(proven_match())
    proven_unwrap()
    proven_tail()
    var distinct: long[2] = fill(0L)
    forward(distinct[0L], distinct[1L])
    print(distinct)
    forward(distinct[1L], distinct[0L])
    print(distinct)
    var pair: Pair = Pair {}
    set_two(pair.left, pair.right)
    print(pair)
    print(pass_array(make_array()))
    var proven: long[3] = fill(0L)
    for i: long in 0L..proven.len() { proven[i] = i }
    print(proven)
}
