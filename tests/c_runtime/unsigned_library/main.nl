struct Entry { key: ulong, flags: uint }

fn hash_word(h: ulong, word: ulong) -> ulong {
    let mixed = (h ^ word) *% 11400714819323198485UL
    rotl(mixed, 31UL) ^ mul_hi(mixed, 14029467366897019727UL)
}

fn main() {
    let max64: ulong = 18446744073709551615UL
    print(mul_hi(max64, max64))
    print(mul_hi(4294967296UL, 4294967296UL))
    print(mul_hi(3UL, 5UL))
    print(rotl(1u, 33u))
    print(rotr(1u, 1u))
    print(rotl(0x8000000000000001UL, 4UL))
    print(hash_word(1469598103934665603UL, 42UL))
    print(max(5u, 4000000000u))
    print(min(max64, 7UL))
    var seen: map<ulong, uint, 8> = map {}
    seen.set(max64, 1u).unwrap()
    seen.set(9223372036854775808UL, 2u).unwrap()
    seen.set(max64, 3u).unwrap()
    print(seen.count())
    match seen.get(max64) { some(v) => print(v), none => print(0u) }
    match seen.get(9223372036854775808UL) { some(v) => print(v), none => print(0u) }
    var by_small: map<ushort, sbyte, 4> = map {}
    let small_key: ushort = 65535
    let small_value: sbyte = -3
    by_small.set(small_key, small_value).unwrap()
    match by_small.get(small_key) { some(v) => print(v), none => print(small_value) }
    var entries: list<Entry, 4> = list {}
    entries.push(Entry { key: max64, flags: 4294967295u }).unwrap()
    print(entries[0L].key == max64)
    print(entries[0L].flags)
    let xs: list<ulong, 4> = list {}
    print(xs.count())
    for i in 4294967294u..4294967295u { print(i) }
    for i in 18446744073709551614UL..=18446744073709551615UL { print(i) }
}
