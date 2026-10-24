fn mutate(value: write int) { value += 1 }
fn wrapper(value: int) -> int {
    var copy = value
    mutate(copy)
    copy
}
const REJECTED: int = wrapper(4)

fn main() { print(REJECTED) }
