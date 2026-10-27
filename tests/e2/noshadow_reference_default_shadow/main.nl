struct S { value: int = value() }

fn value() -> int { 9 }
fn main() {
    let value_local = 1
    print(S {}.value)
}
