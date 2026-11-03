enum Shape {
    Id(ulong),
    Pair(uint, ushort),
    Nothing,
}

const MASK: uint = 4294967295u
const BIG: ulong = 18446744073709551615UL

fn half(v: ulong) -> Option<ulong> {
    if v == 0UL { none } else { some(v / 2UL) }
}

fn describe(shape: Shape) -> ulong {
    match shape {
        Shape.Id(v) => v,
        Shape.Pair(a, b) => (ulong)a + (ulong)b,
        Shape.Nothing => 0UL,
    }
}

fn main() {
    var values: list<ulong, 8> = list {}
    values.push(BIG).unwrap()
    values.push(1UL).unwrap()
    print(values[0L])
    print(values[0L] > values[1L])
    var words: uint[4] = [1u, 2u, 3u, 4000000000u]
    words[1L] = 4294967295u
    print(words[1L])
    print(words[3L])
    var counts: map<uint, ulong, 8> = map {}
    counts.set(4000000000u, BIG).unwrap()
    match counts.get(4000000000u) {
        some(v) => print(v),
        none => print(0UL),
    }
    print(describe(Shape.Id(BIG)))
    print(describe(Shape.Pair(4000000000u, 65535)))
    match half(BIG) {
        some(v) => print(v),
        none => print(0UL),
    }
    print(MASK)
    let small: ushort = 65535
    let small16 = small
    let tiny8: sbyte = -5
    print(small)
    let tiny: sbyte = -128
    let word: short = -32768
    print(tiny)
    print(word)
    let text: Ascii max 64 = $"{MASK} {small16} {tiny8}"
    print(text)
    print(small -% 65535)
    print(tiny.to_long())
}
