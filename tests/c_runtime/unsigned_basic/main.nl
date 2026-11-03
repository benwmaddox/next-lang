struct Hash { low: uint, high: ulong }

fn mix(h: ulong, v: ulong) -> ulong {
    (h ^ v) *% 1099511628211UL
}

fn main() {
    let a: uint = 4000000000u
    let b = 5u
    print(a)
    print(a + 294967295u)
    print(a / b)
    print(a % 7u)
    print(a > 3u)
    let big: ulong = 18446744073709551615UL
    print(big)
    print(big > 9223372036854775807UL)
    print(big / 10UL)
    print(big >> 60UL)
    print(1UL << 63UL)
    let h = mix(14695981039346656037UL, 97UL)
    print(h)
    var x: uint = 1u
    x <<= 31u
    x |= 5u
    print(x)
    print(~0u)
    print(0u -% 1u)
    print(4294967295u +% 2u)
    var s = Hash { low: 7u, high: 1UL }
    s.low += 1u
    s.high *= 3000000000UL
    print(s.low)
    print(s.high)
    print((ulong)a)
    print((uint)(big >> 40UL) >> 4u)
    print(unchecked((uint)big))
    print((long)5UL)
    print((int)7u)
    print(unchecked((uint)(0 - 1)))
    var total: ulong = 0UL
    for i in 0UL..5UL { total += i }
    print(total)
}
