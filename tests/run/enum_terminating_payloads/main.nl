enum E { C(int), D }
fn return_payload() -> int { let value = E.C(return 6); 9 }
fn return_some(value: Option<int>) -> Option<int> { some(return value); some(0) }
fn return_ok(value: Result<int, int>) -> Result<int, int> { let unreachable: Result<int, int> = ok(return value); ok(0) }
fn return_err(value: Result<int, int>) -> Result<int, int> { let unreachable: Result<int, int> = err(return value); err(0) }
fn maybe_value(value: int) -> Option<int> { if value < 0 { none } else { some(value) } }
fn try_payload(value: int) -> Option<E> { some(E.C(maybe_value(value)?)) }
fn main() {
    print(return_payload())
    print(return_some(some(8)))
    print(return_ok(ok(4)))
    print(return_err(err(5)))
    for index in 0..2 { print(index); let item = E.C(continue); print(99) }
    print(7)
    for index in 0..3 { print(index); let item = E.C(break); print(88) }
    print(9)
    print(try_payload(-1))
    print(try_payload(3))
}
