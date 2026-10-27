struct Cell { score: int, enabled: bool }
struct Pair { left: int, right: int }

fn bump(value: write int) { value += 2 }
fn bump_long(value: write long) { value += 1L }
fn toggle(value: write bool) { value = !value }
fn forward(value: write int) { bump(value) }
fn update_cell(value: write Cell) {
    value.score += 4
    value.enabled = false
}
fn exchange(left: write int, right: write int) {
    let saved = left
    left = right
    right = saved
}

fn main() {
    var number = 1
    forward(number)
    print(number)

    var wide = 4L
    bump_long(wide)
    print(wide)

    var enabled = true
    toggle(enabled)
    print(enabled)

    var values: list<int, 3> = [2, 3]
    bump(values[1L])
    print(values)

    var cells: list<Cell, 2> = [Cell { score: 5, enabled: true }]
    update_cell(cells[0L])
    bump(cells[0L].score)
    print(cells)

    var pair = Pair { left: 3, right: 7 }
    exchange(pair.left, pair.right)
    print(pair)

    var slots: list<int, 2> = [4, 9]
    exchange(slots[0L], slots[1L])
    print(slots)
}
