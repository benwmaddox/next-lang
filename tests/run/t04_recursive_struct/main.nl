struct A { next: Option<A> }
fn main() { let a = A { next: none }; print(a) }
