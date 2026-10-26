struct S { x: int = if true {
    expect true
    1
} else { 1 } }

fn main() {}
