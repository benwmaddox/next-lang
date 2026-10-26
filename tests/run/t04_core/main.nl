type Size = int 1..=3
type Heading = int 0..360 wrap
type Percent = int 0..=100 clamp
type One = int 5..=5 wrap

struct Core {
    size: Size = 2
    heading: Heading = 0
    health: Percent = 100
    child: Child = Child { value: 4 }
}
struct Child { value: int }
struct Defaults {
    first: int = later()
    second: int = later()
    skipped: int = 1 / 0
}

fn later() -> int { 2 }
fn next(n: write int) -> int { n += 1; n }
fn set(c: write Core) { c.size = 3; c.child.value = 9 }
fn forward(c: write Core) { set(c) }
fn bounded(x: int) -> Size {
    if x < 1 { return 1 }
    if x > 3 { return 3 }
    x
}
fn loop_sum(n: Size) -> int {
    var total = 0
    for i in 0..n { total += max(i, min(n, 2)) }
    total
}
fn main() {
    var c = Core {}
    let copy = c
    forward(c)
    c.heading = -1000000
    c.heading += 1000000
    c.heading += -1000000
    c.heading = 360
    c.health = -1000000
    c.health += 1000000
    c.health += -1000000
    var one: One = 2147483647
    one += 0
    var count = 0
    let d = Defaults { second: next(count), skipped: 7 }
    next(count)
    var full: long -9223372036854775808..=9223372036854775807 wrap = -9223372036854775808L
    full += 1
    let opt: Option<Core> = some(c)
    let res: Result<Core, Size> = err(2)
    let ok_res: Result<Core, Size> = ok(c)
    print(c)
    print(copy)
    print(one)
    print(count)
    print(d)
    print(full)
    print(opt)
    print(res)
    print(ok_res)
    print((Size)(3))
    print(11.fit<Size>())
    print(3.fit<Size>())
    let optional_size: Option<Size> = some(3)
    print(optional_size)
    print(9.to_long())
    let maybe_int: Option<int> = none
    print(maybe_int?.to_long())
    print(some(8)?.to_long())
    print(bounded(2))
    print(loop_sum(3))
    if c == copy { print(false) } else { print(true) }
}
