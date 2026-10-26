struct Cell { value: int = 0 }

fn update_index(index: write long) -> int {
    index = 1L
    0
}

fn change_and_copy(value: write Cell) -> Cell {
    value.value = 9
    value
}

fn change_list_and_copy(values: write list<long, 1>) -> list<long, 1> {
    values[0L] = 9L
    values
}

fn main() {
    let values: int[2] = [4, 7]
    var index = 0L
    fn_read(values[index], update_index(index))

    var cell = Cell { value: 1 }
    print(cell == change_and_copy(cell))

    var items: list<long, 1> = list {}
    discard items.push(1L)
    print(items == change_list_and_copy(items))
}

fn fn_read(value: int, marker: int) {
    print(value)
    print(marker)
}

