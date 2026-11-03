struct Cell {
    a: int
    b: int
}

fn sum_row(row: list<int, 4>) -> int {
    var t = 0
    for c in row { t += c }
    t
}

fn main() {
    var rows: list<list<int, 4>, 4> = list {}
    var r1: list<int, 4> = list {}
    discard r1.push(1)
    discard r1.push(2)
    var r2: list<int, 4> = list {}
    discard r2.push(10)
    discard r2.push(20)
    discard rows.push(r1)
    discard rows.push(r2)
    var total = 0
    for row in rows {
        for c in row {
            total += c
        }
    }
    print(total)

    var arrs: list<int[3], 4> = list {}
    var x: int[3] = [1, 2, 3]
    var y: int[3] = [4, 5, 6]
    discard arrs.push(x)
    discard arrs.push(y)
    var atotal = 0
    for arr in arrs {
        for v in arr { atotal = atotal * 2 + v }
    }
    print(atotal)

    var cells: list<list<Cell, 3>, 3> = list {}
    var c1: list<Cell, 3> = list {}
    discard c1.push(Cell { a: 1, b: 2 })
    discard c1.push(Cell { a: 3, b: 4 })
    var c2: list<Cell, 3> = list {}
    discard c2.push(Cell { a: 5, b: 6 })
    discard cells.push(c1)
    discard cells.push(c2)
    var ctotal = 0
    for row in cells {
        for cell in row { ctotal += cell.a * 10 + cell.b }
    }
    print(ctotal)

    for row in rows { print(sum_row(row)) }

    var cube: list<list<list<int, 2>, 2>, 2> = list {}
    var l1: list<int, 2> = list {}
    discard l1.push(1)
    discard l1.push(2)
    var l2: list<int, 2> = list {}
    discard l2.push(3)
    var plane: list<list<int, 2>, 2> = list {}
    discard plane.push(l1)
    discard plane.push(l2)
    discard cube.push(plane)
    discard cube.push(plane)
    var ztotal = 0
    for p in cube {
        for q in p {
            for z in q { ztotal += z }
        }
    }
    print(ztotal)
}
