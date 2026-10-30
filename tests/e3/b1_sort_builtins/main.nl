struct Entry { first: long, second: long, index: long }

fn entry_less(ctx: int, a: Entry, b: Entry) -> bool {
    if a.first != b.first { a.first < b.first } else { a.second < b.second }
}

fn longer_first(ctx: int, a: long, b: long) -> bool {
    if ctx == 1 { a > b } else { a < b }
}

fn main() {
    var values: list<int, 16> = list {}
    var seed = 7
    for i in 0L..12L {
        seed = (seed * 31 + 11) % 97
        values.push(seed).unwrap()
    }
    var t = values
    sort(t)
    for i in 0L..t.count() { print(t[i]) }
    var entries: list<Entry, 20> = list {}
    for i in 0L..9L {
        entries.push(Entry { first: (i * 5L) % 3L, second: (i * 7L) % 4L, index: i }).unwrap()
    }
    sort_by(entries, 0, entry_less)
    for i in 0L..entries.count() { print(entries[i].index) }
    var longs: long[6] = [5L, 1L, 9L, 3L, 7L, 2L]
    sort_by(longs, 1, longer_first)
    for i in 0L..6L { print(longs[i]) }
    sort(longs)
    for i in 0L..6L { print(longs[i]) }
}
