fn first(x: write int) -> int { x = 1; 10 }
fn second(x: write int) -> int { x = 2; 20 }
fn pair(a: int, b: int) { print(a); print(b) }
fn main() {
    var state = 0
    pair(first(state), second(state))
    print(state)
}
