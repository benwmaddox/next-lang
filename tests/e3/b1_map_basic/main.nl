struct Cache {
    index: map<Ascii max 16, int, 64>
    hits: int
}

fn lookup(cache: Cache, key: Ascii max 16) -> int {
    match cache.index.get(key) {
        some(v) => v,
        none => -1,
    }
}

fn bump(counts: write map<long, long, 8>, key: long) {
    let current = counts.get(key) ?? 0L
    counts.set(key, current + 1L).unwrap()
}

fn main() {
    var counts: map<long, long, 8> = map {}
    for i in 0L..20L { bump(counts, i % 5L) }
    print(counts.count())
    print(counts.get(2L) ?? -1L)
    print(counts.get(9L) ?? -1L)
    print(counts.contains(4L))
    print(counts.contains(7L))
    let gone = counts.remove(3L)
    print(gone ?? -5L)
    print(counts.count())
    print(counts.contains(3L))
    for i in 10L..14L { counts.set(i, i * 2L).unwrap() }
    print(counts.count())
    print(counts.get(13L) ?? -1L)
    let full = counts.set(99L, 1L)
    print(full.is_err())

    var cache = Cache { index: map {}, hits: 0 }
    cache.index.set("alpha", 1).unwrap()
    cache.index.set("beta", 2).unwrap()
    cache.index.set("alpha", 3).unwrap()
    print(lookup(cache, "alpha"))
    print(lookup(cache, "beta"))
    print(lookup(cache, "gamma"))
    cache.index.remove("alpha")
    print(lookup(cache, "alpha"))
    print(cache.index.count())

    var names: map<Ascii max 8, Ascii max 16, 10> = map {}
    names.set("k1", "first value").unwrap()
    names.set("k2", "second").unwrap()
    match names.get("k1") {
        some(v) => print(v),
        none => print("missing"),
    }
}
