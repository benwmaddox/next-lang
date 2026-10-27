struct Cell { score: int }

fn update_index(index: write long) -> int {
    index = 1L
    0
}
fn read_int(value: int, marker: int) {
    print(value)
    print(marker)
}
fn observe(value: write int, marker: int) {
    print(value)
    value = marker
}
fn change_cell(value: write Cell) -> int {
    value.score = 9
    0
}
fn read_cell(value: Cell, marker: int) {
    print(value)
    print(marker)
}
fn change_values(values: write list<int, 3>) -> int {
    values[0L] = 8
    0
}
fn read_values(values: list<int, 3>, marker: int) {
    print(values)
    print(marker)
}

fn main() {
    var array: int[2] = [4, 7]
    var index = 0L
    read_int(array[index], update_index(index))
    print(index)

    var number = 1
    observe(number, if true { number = 9; 0 } else { 0 })
    print(number)

    var cells: list<Cell, 2> = [Cell { score: 1 }]
    read_cell(cells[0L], change_cell(cells[0L]))
    print(cells)

    var values: list<int, 3> = [1, 2]
    read_values(values, change_values(values))
    print(values)
}
