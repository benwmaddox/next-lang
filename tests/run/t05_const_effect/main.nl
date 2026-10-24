fn last_step(value: int) -> int {
    print(value)
    value
}

fn middle(value: int) -> int { last_step(value) }
fn first(value: int) -> int { middle(value) }
const REJECTED: int = first(7)

fn main() { print(REJECTED) }
