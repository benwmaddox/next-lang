fn update(value: write int) -> int {
    value = 9
    0
}

fn observe(value: write int, marker: int) {
    print(value)
    print(marker)
}

fn main() {
    var value = 1
    observe(value, update(value))
    print(value)
}
