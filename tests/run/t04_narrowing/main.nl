type Small = int 0..=10
struct Container { size: Small }
enum Measured { Amount(Small) }
fn bounded(x: int) -> Small {
    if x < 0 { return 0 }
    if x > 10 { return 10 }
    x
}
fn consume(x: Small) -> int { x }
fn increment(x: Small) -> Small {
    if x < 10 { x + 1 } else { x }
}
fn decrement(x: Small) -> Small {
    if x > 0 { x - 1 } else { x }
}
fn doubled(x: Small) -> Small {
    if x <= 5 { x * 2 } else { x }
}
fn from_minmax(x: int) -> Small { min(max(x, 0), 10) }
fn container(x: int) -> Container { Container { size: min(max(x, 0), 10) } }
fn measured(x: int) -> Measured { Measured.Amount(min(max(x, 0), 10)) }
fn joined(x: int) -> Small {
    var y = x
    if y < 0 { y = 0 } else { y = min(y, 10) }
    y
}
fn by_if(x: int) -> int {
    if x >= 0 && x <= 10 { consume(x) } else { 0 }
}
fn continue_sum(n: Small) -> int {
    var total = 0
    for i in -2..=n {
        if i < 0 { continue }
        total += bounded(i)
    }
    total
}
fn break_sum(n: int) -> int {
    var total = 0
    for i in -2..n {
        if i > 10 { break }
        if i < 0 { continue }
        total += i
    }
    total
}
fn main() {
    print(bounded(50))
    print(increment(9))
    print(increment(10))
    print(decrement(0))
    print(decrement(5))
    print(doubled(5))
    print(doubled(10))
    print(from_minmax(100))
    print(container(100))
    print(measured(100))
    print(joined(100))
    print(by_if(7))
    print(continue_sum(3))
    print(break_sum(100))
}
