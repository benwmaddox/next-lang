struct Cell { value: int, active: bool }

fn show(cell: Cell) { print(cell) }

fn main() {
    var cells: list<Cell, 4> = [Cell { value: 1, active: true }, Cell { value: 2, active: false }]
    let indexed: Cell = cells[1L]
    print(indexed)
    show(cells[0L])
    for cell, index in cells {
        print(index)
        print(cell)
        let copy: Cell = cell
        print(copy == cell)
        cell.value += 1
        cell.active = !cell.active
    }
    print(cells)

    var array: Cell[2] = [Cell { value: 7, active: true }, Cell { value: 8, active: false }]
    for item in array { item.value += 2 }
    print(array)
}
