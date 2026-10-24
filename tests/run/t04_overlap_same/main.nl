struct Box { value: int }
fn pair(a: write int, b: int) {}
fn main() { var b = Box { value: 1 }; pair(b.value, b.value) }
