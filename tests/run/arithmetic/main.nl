fn main() {
    print(combine(2, 3))
    let big: long = 3_000_000_000L + 1L
    print(big)
    let narrowed = (int)12L
    print(narrowed)
    print((long)narrowed)
    print(widen(-3))
    var n = 10
    n += 2
    n -= 1
    n *= 3
    n /= 3
    n %= 4
    print(n)
    print(2147483647 +% 1)
    print((5 & 3) | (8 ^ 2))
    if true { print(100) } else { print(200) }
    let branch = if false { 1 } else if true { 2 } else { 3 }
    print(branch)
    let shadow = 1
    if true { let shadow = 2; print(shadow) }
    print(shadow)
}
