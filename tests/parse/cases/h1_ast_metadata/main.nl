type Effectful = fn(int) -> int effects out, reads app.value

enum Pair {
    Values(int, int)
}

fn identity(value: int) -> int { value }

fn main() {
    let grouped = (
        identity
    )(
        5
    )
    let selected = match Pair.Values(1, 2) {
        Pair.Values(first, _) => first
    }
    let omitted: int
    expect grouped == selected
}
