struct S { value: int = effect() }

fn effect() -> int {
    print(77)
    5
}
fn main() {
    print(S { value: 1 }.value)
}
