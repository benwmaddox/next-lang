fn add_one(value: int) -> int { value + 1 }
fn wrapper(value: int) -> int { add_one(value) }
const TOO_BIG: int = wrapper(2147483647)

fn main() { print(TOO_BIG) }
