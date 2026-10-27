struct Small { value: int }
struct EmptyValue {}
struct Box { shape: Shape }
enum Shape { Circle(int), Wide(long), Pair(bool, int), Nested(Small), Empty, Unit(()), EmptyPayload(EmptyValue) }

fn echo(value: Shape) -> Shape { value }
fn make_circle() -> Shape { Circle(12) }
fn make_empty() -> Shape { Empty }
fn shadow(outer: int, shape: Shape) -> int {
    match shape {
        Circle(radius) => radius
        _ => outer
    }
}
fn first_flag() -> bool { print(8); true }
fn second_value() -> int { print(9); 19 }
fn next_shape() -> Shape { print(90); Shape.Wide(123L) }
fn area(shape: Shape) -> int {
    match shape {
        Circle(radius) => { let copy = radius; copy }
        Wide(_) => 1
        Pair(_, _) => 2
        Nested(small) => small.value
        Empty => 0
        Unit(_) => -1
        EmptyPayload(_) => -2
    }
}

fn main() {
    var current: Shape = Shape.Wide(10000000000L)
    print(current)
    current = Shape.Pair(first_flag(), second_value())
    print(current)
    print(current == Shape.Pair(true, 19))
    current = Shape.Circle(7)
    print(current)
    current = Shape.Empty
    print(current)
    print(Shape.Nested(Small { value: 5 }))
    print(Shape.EmptyPayload(EmptyValue {}))
    print(make_circle())
    print(make_empty())
    print(shadow(99, Shape.Circle(7)))
    print(shadow(99, Shape.Empty))
    print(area(Shape.Nested(Small { value: 6 })))
    print(area(next_shape()))
    let selected = match Shape.Pair(false, 3) {
        Circle(value) => Shape.Circle(value)
        Wide(_) => Shape.Empty
        Pair(flag, value) => if flag { Shape.Circle(value) } else { Shape.Wide(value.to_long()) }
        Nested(_) => Shape.Empty
        Empty => Shape.Empty
        Unit(_) => Shape.Empty
        EmptyPayload(_) => Shape.Empty
    }
    print(selected)
    let boxed = Box { shape: selected }
    print(echo(boxed.shape))
    print(Shape.Unit(()))
    print(match Shape.Unit(()) {
        Circle(_) => 0,
        Wide(_) => 0,
        Pair(_, _) => 0,
        Nested(_) => 0,
        Empty => 0,
        Unit(value) => 11,
        EmptyPayload(_) => 0
    })
    print(match -3 { -3 => 30, _ => 31 })
    print(match false { false => 40, true => 41 })
    match Shape.Empty { Empty => print(50), _ => print(51) }
    print(match 5L { 3L => 0, 5L => 12, _ => 1 })
    print(Shape.Circle(8) == Shape.Circle(8))
    print(Shape.Circle(8) != Shape.Circle(9))
    print(Shape.Circle(8) != Shape.Empty)
    print(Shape.Nested(Small { value: 4 }) == Shape.Nested(Small { value: 4 }))
}
