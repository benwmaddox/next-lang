fn spin() -> int {
    for i in 0..100000000 {}
    0
}

const NEVER: int = spin()
fn main() { print(NEVER) }
