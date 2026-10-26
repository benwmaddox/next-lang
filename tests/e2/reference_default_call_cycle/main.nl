struct S { x: int = build_value() }

fn build_value() -> int {
    let value = S {}
    1
}

fn main() {
    let value = S {}
}
