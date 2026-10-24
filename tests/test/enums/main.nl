enum Shape { Circle(int), Rect(int, int), Empty }
enum Failure { Missing }
enum UnitPayload { Wrap(()) }
fn make_circle(radius: int) -> Shape { print(radius); Shape.Circle(radius) }
test "enum copies, tags, and nested payload equality" {
    let original = Shape.Circle(3)
    let copy = original
    expect original == copy
    expect Shape.Empty != Shape.Circle(0)
    let wrapped: Option<Result<int, Failure>> = some(ok(5))
    expect wrapped == some(ok(5))
    expect UnitPayload.Wrap(()) == UnitPayload.Wrap(())
}
test "match bindings shadow outer names and arms can contain blocks" {
    let r = 99
    let matched = match Shape.Circle(6) {
        Circle(r) => { let copy = r; copy }
        Rect(_, _) => r
        Empty => 0
    }
    expect matched == 6
    expect match true { true => 1, false => 0 } == 1
    expect match 2 { 0 => 0, _ => 2 } == 2
}
test "comparison operands are evaluated once" {
    expect make_circle(4) == make_circle(4)
}
test "failed enum expectation displays active payloads" {
    expect Shape.Rect(2, 3) == Shape.Rect(2, 4)
}
