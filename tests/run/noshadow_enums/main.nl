enum Shape { Circle(int), Rect(int, int), Empty }
enum Failure { Empty, Full }
enum UnitPayload { Wrap(()) }
fn plus(x: int, amount: int) -> int { x + amount }
fn maybe(x: int) -> Option<int> {
    if x == 0 { none } else { some(x) }
}
fn nested(x: int) -> Option<Option<int>> { some(maybe(x)) }
fn result(x: int) -> Result<int, Failure> {
    if x == 0 { err(Failure.Empty) } else { ok(x) }
}
fn nothing() -> () { () }
fn unit_result(success: bool) -> Result<(), Failure> {
    if success { ok(nothing()) } else { err(Failure.Full) }
}
fn propagate_unit(value: Result<(), Failure>) -> Result<(), Failure> {
    value?
    ok(())
}
fn shape_code(shape: Shape) -> int {
    match shape {
        Circle(r) => {
            let copy = r
            match copy {
                0 => 0
                1 => 1
                _ => copy * 2
            }
        }
        Shape.Rect(w, h) => w * h
        Empty => 0
    }
}
fn shadow_radius(shape: Shape) -> int {
    let r = 99
    match shape {
        Circle(radius) => radius
        Rect(_, _) => r
        Empty => r
    }
}
fn trace_arg() -> int { print(80); 2 }
fn trace_receiver(value: Option<int>) -> Option<int> { print(90); value }
fn read_plain(value: Option<int>) -> Option<int> { value?.plus(2) }
fn read_flat(value: Option<int>) -> Option<int> { value?.maybe() }
fn other_code(value: Other) -> int {
    match value {
        Circle(n) => n
        Other.Empty => 0
    }
}
fn main() {
    print(shape_code(Shape.Circle(4)))
    print(shape_code(Shape.Rect(3, 5)))
    print(shape_code(Shape.Empty))
    print(shadow_radius(Shape.Circle(7)))
    print(other_code(Other.Circle(9)))
    print(match 0 { 0 => 11, 1 => 12, _ => 13 })
    print(match true { true => 14, false => 15 })
    print(maybe(0))
    print(maybe(5))
    print(nested(4))
    print(result(0))
    print(result(7))
    print(unit_result(true))
    print(propagate_unit(unit_result(false)))
    let nested_result: Option<Result<int, Failure>> = some(ok(5))
    print(nested_result)
    print(result(0).ok())
    print(result(7).is_ok())
    print(result(0).is_err())
    print(maybe(4).is_some())
    print(maybe(0).is_none())
    print(UnitPayload.Wrap(()))
    print(read_plain(none))
    print(read_plain(some(3)))
    print(read_flat(some(3)))
    print(read_flat(none))
    let skipped = trace_receiver(none)?.plus(trace_arg())
    print(skipped)
    let skipped_default = trace_receiver(none)?.plus(trace_arg()) ?? 100
    print(skipped_default)
    let called = trace_receiver(some(1))?.plus(trace_arg())
    print(called)
    print(result(8).unwrap())
}
