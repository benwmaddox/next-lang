struct Cell { value: int = 0 }

fn change_and_copy(value: write Cell) -> Cell {
    value.value = 9
    value
}

test "aggregate equality keeps the left operand snapshot" {
    var cell = Cell { value: 1 }
    expect cell == change_and_copy(cell)
}
