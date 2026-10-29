fn main() {
    let a = 2000000000
    let b = 2000000000
    print(a +% b)
    print(a -% (0 - b))
    print(a *% 3)
    let x = 9223372036854775807L
    print(x +% 1L)
    print(x *% 2L)
    print(0L -% x -% 5L)
    print(1 +% 2)
}
