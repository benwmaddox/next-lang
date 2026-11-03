fn main() {
    let a: uint = 4000000000u
    let b: ulong = 18446744073709551615UL
    print((long)(a.to_double() / 2.0))
    print(b.to_double() > 1.8e19)
    print((ulong)(1.5e19))
    print((uint)(4294967295.0))
    print((ushort)(65535.9))
    print((sbyte)(-128.5))
    let f: float = 3000000000.0
    print((uint)f)
}
