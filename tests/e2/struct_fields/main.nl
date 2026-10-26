struct Point { x: int, y: int = 2, flag: bool = false }
struct Empty {}
struct Inner { value: int }
struct Outer { inner: Inner }

fn add_x(point: Point) -> Point {
    var result = point
    result.x += 5
    result
}

fn main() {
    var point = Point { x: 3 }
    print(point.x)
    print(point.y)

    var copy = point
    point.y = 9
    print(copy.y)
    print(point.y)

    copy.x += 2
    print(copy.x)

    let result = add_x(copy)
    print(result.x)

    let shorthand_x = 12
    let shorthand = Point { x: shorthand_x }
    print(shorthand.x)

    var swap = Point { x: 10, y: 20 }
    swap = Point { x: swap.y, y: swap.x }
    print(swap.x)
    print(swap.y)

    var nested = Outer { inner: Inner { value: 4 } }
    nested.inner.value = 8
    nested.inner.value += 3
    print(nested.inner.value)
}
