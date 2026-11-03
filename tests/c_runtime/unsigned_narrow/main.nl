struct Pixel { r: sbyte, g: ushort, b: short }

fn checksum(data: ushort[4]) -> ushort {
    var sum: ushort = 0
    for i in 0L..4L { sum +%= data[i] }
    sum
}

fn main() {
    let a: ushort = 60000
    let b: ushort = 5535
    print(a + b)
    print(a -% 60001)
    print(a *% 3)
    print(a / 7)
    print(a % 7)
    print(a > 3)
    print(a << 1)
    let c: short = -32768
    let d: short = 32767
    print(c)
    print(c < d)
    print(c +% -1)
    print(d +% 1)
    print(c >> 3)
    print(d << 1)
    print(~d)
    print(~b)
    print(-d)
    let e: sbyte = -100
    let f: sbyte = 27
    print(e - f)
    print(e *% 3)
    print(e % 7)
    print(e / f)
    print(e >> 2)
    print((int)e)
    print((byte)f)
    print((sbyte)(byte)f)
    print((short)e)
    print((ushort)300)
    print(unchecked((sbyte)200))
    print(unchecked((ushort)(-1)))
    print(unchecked((short)40000))
    print((uint)b)
    print((ulong)f)
    print((long)c)
    let p = Pixel { r: -1, g: 65535, b: -2 }
    print(p.r)
    print(p.g)
    print(p.b)
    var q = p
    q.r -%= 127
    q.r -%= 2
    print(q.r)
    print(checksum([60000, 5000, 600, 70]))
    var wide: int = 2147483647
    wide +%= 2
    print(wide)
    var big: long = 9223372036854775807L
    big *%= 2L
    print(big)
    var h: uint = 2166136261u
    h ^= 97u
    h *%= 16777619u
    print(h)
    print(a.to_long())
    print(e.to_long())
}
