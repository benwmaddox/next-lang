fn main() {
    var m: map<long, long, 8> = map {}
    for round in 0L..60L {
        for k in 0L..5L {
            m.set(round * 10L + k, round + k).unwrap()
        }
        for k in 0L..5L {
            if k % 2L == 0L { let gone = m.remove(round * 10L + k) }
        }
        if round >= 1L {
            let old_one = m.remove((round - 1L) * 10L + 1L)
            let old_three = m.remove((round - 1L) * 10L + 3L)
        }
        if m.count() > 8L { print(-1L) }
    }
    print(m.count())
    var sum = 0L
    for k in 0L..600L { sum = sum + (m.get(k) ?? 0L) * (k + 1L) }
    print(sum)
    var full: map<int, int, 3> = map {}
    full.set(1, 1).unwrap()
    full.set(2, 2).unwrap()
    full.set(3, 3).unwrap()
    print(full.set(4, 4).is_err())
    let gone_two = full.remove(2)
    print(full.set(4, 4).is_ok())
    print(full.set(1, 9).is_ok())
    print(full.get(1) ?? -1)
    print(full.contains(2))
    print(full.count())
}
