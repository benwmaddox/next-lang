struct Cell {
    id: int
    tags: list<int, 4>
}

fn row_sum(row: list<int, 3>) -> int {
    var total = 0
    for value in row { total += value }
    total
}

fn main() {
    var grid: list<list<int, 3>, 3> = list {}
    var next = 1
    for r in 0L..3L {
        var row: list<int, 3> = list {}
        for c in 0L..3L {
            row.push(next).unwrap()
            next += 1
        }
        grid.push(row).unwrap()
    }
    var sum = 0
    for r in 0L..grid.count() {
        for c in 0L..grid[r].count() { sum += grid[r][c] }
    }
    print(sum)
    grid[1L][1L] = 100
    print(grid[1L][1L])
    print(row_sum(grid[1L]))

    var cells: list<Cell, 4> = list {}
    cells.push(Cell { id: 7, tags: [1, 2] }).unwrap()
    cells.push(Cell { id: 8, tags: [] }).unwrap()
    cells[0L].tags.push(9).unwrap()
    print(cells[0L].tags.count())
    print(cells[0L].tags[2L])
    print(cells[1L].tags.count())

    let copy = cells
    cells[0L].tags[0L] = 50
    print(copy[0L].tags[0L])
    print(cells[0L].tags[0L])

    var board: Cell[1000] = fill(Cell { id: 1, tags: [] })
    board[999L].tags.push(4).unwrap()
    print(board[0L].tags.count())
    print(board[999L].tags[0L])
}
