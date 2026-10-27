struct S { x: int }
enum E { print(S) }
fn make() -> E { print(S {x: 9}) }
fn main() { match make() { print(_) => () } }
