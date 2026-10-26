struct A { value: int = B {}.value }
struct B { value: int = A {}.value }
fn main() {}
