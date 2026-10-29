fn main() {
    let a: long = 7L
    let b: long = -3L
    let x: int = 5
    let y: int = -9
    print(min(a, b))
    print(max(a, b))
    print(min(x, y))
    print(max(x, y))
    print(abs(b))
    print(abs(y))
    print(clamp(a, 0L, 5L))
    print(clamp(y, -4, 4))
    print(clamp(x, 0, 10))
    print(max(a / 2L, 1L) + min(a, 100L))
}
