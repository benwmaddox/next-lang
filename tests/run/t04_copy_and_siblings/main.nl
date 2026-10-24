struct Point { x: int, y: int }
fn move(x: write int, y: write int) { x += 1; y += 2 }
fn read_twice(a: int, b: int) -> int { a + b }
fn main() {
    var p = Point { x: 2, y: 4 }
    let copy = p
    move(p.x, p.y)
    print(p)
    print(copy)
    print(read_twice(p.x, p.x))
    let x = 7
    let y = 8
    let shorthand = Point { x, y }
    print(shorthand)
}
