fn force_growth() -> int {
    let scratch: list<bool, 300000> = list{}
    7
}

fn observe(value: write int, marker: int) {
    print(value)
    value = marker
}

fn main() {
    var values: list<int, 4> = [1, 2]
    values[0L] = force_growth()
    values[1L] += force_growth()
    print(values)
    observe(values[1L], force_growth())
    print(values)
}
