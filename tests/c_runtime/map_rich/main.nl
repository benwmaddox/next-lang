enum Color { Red, Green, Blue }

struct Inner { c: Color, n: int }
struct Key { a: long, tag: Ascii max 8, inner: Inner, flag: bool }
struct Point { x: long, y: long }

fn key(a: long, tag: Ascii max 8, c: Color, n: int, flag: bool) -> Key {
    Key { a, tag, inner: Inner { c, n }, flag }
}

struct Book { by_point: map<Point, Inner, 8>, names: map<Ascii max 8, list<int, 4>, 4> }

fn lookup(book: Book, p: Point) -> int {
    match book.by_point.get(p) { some(i) => i.n, none => -1 }
}

fn main() {
    // struct values
    var points: map<Ascii max 8, Point, 8> = map {}
    points.set("a", Point { x: 1, y: 2 }).unwrap()
    points.set("b", Point { x: 3, y: 4 }).unwrap()
    points.set("a", Point { x: 5, y: 6 }).unwrap()
    match points.get("a") { some(p) => print(p.x + p.y), none => print(-1L) }
    match points.get("zz") { some(p) => print(p.x), none => print(-1L) }
    let gone = points.remove("b")
    match gone { some(p) => print(p.y), none => print(-1L) }
    print(points.count())

    // struct keys: nested struct, enum, text and bool fields
    var seen: map<Key, long, 16> = map {}
    seen.set(key(1, "x", Color.Red, 1, true), 10L).unwrap()
    seen.set(key(1, "x", Color.Green, 1, true), 20L).unwrap()
    seen.set(key(1, "y", Color.Red, 1, true), 30L).unwrap()
    seen.set(key(1, "x", Color.Red, 1, false), 40L).unwrap()
    seen.set(key(1, "x", Color.Red, 2, true), 50L).unwrap()
    seen.set(key(1, "x", Color.Red, 1, true), 11L).unwrap()
    print(seen.count())
    print(seen.get(key(1, "x", Color.Red, 1, true)) ?? -1L)
    print(seen.get(key(1, "x", Color.Green, 1, true)) ?? -1L)
    print(seen.get(key(1, "y", Color.Red, 1, true)) ?? -1L)
    print(seen.get(key(1, "x", Color.Red, 1, false)) ?? -1L)
    print(seen.get(key(1, "x", Color.Red, 2, true)) ?? -1L)
    print(seen.get(key(2, "x", Color.Red, 1, true)) ?? -1L)
    print(seen.contains(key(1, "y", Color.Red, 1, true)))
    print(seen.contains(key(1, "yy", Color.Red, 1, true)))
    seen.remove(key(1, "y", Color.Red, 1, true))
    print(seen.count())
    print(seen.contains(key(1, "y", Color.Red, 1, true)))
    // enough churn to force compaction and index rebuilds
    var grid: map<Point, long, 8> = map {}
    for round in 0L..50L {
        grid.set(Point { x: round, y: round * 2L }, round).unwrap()
        if round >= 6L { grid.remove(Point { x: round - 6L, y: (round - 6L) * 2L }); () }
    }
    print(grid.count())
    print(grid.get(Point { x: 49, y: 98 }) ?? -1L)
    print(grid.get(Point { x: 44, y: 88 }) ?? -1L)
    print(grid.get(Point { x: 43, y: 86 }) ?? -1L)

    // list values
    var groups: map<Ascii max 16, list<long, 8>, 32> = map {}
    var first: list<long, 8> = list {}
    first.push(1L).unwrap()
    first.push(2L).unwrap()
    groups.set("odd", first).unwrap()
    var second: list<long, 8> = list {}
    second.push(7L).unwrap()
    groups.set("even", second).unwrap()
    match groups.get("odd") {
        some(l) => { print(l.count()); print(l[1]) },
        none => print(-1L),
    }
    match groups.get("even") { some(l) => print(l[0]), none => print(-1L) }
    match groups.get("none") { some(l) => print(l.count()), none => print(-1L) }

    // array values and map values
    var arrays: map<long, long[3], 4> = map {}
    let three: long[3] = [4L, 5L, 6L]
    arrays.set(1L, three).unwrap()
    match arrays.get(1L) { some(a) => print(a[2]), none => print(-1L) }
    var nested: map<long, map<long, long, 4>, 4> = map {}
    var inner: map<long, long, 4> = map {}
    inner.set(9L, 99L).unwrap()
    nested.set(1L, inner).unwrap()
    match nested.get(1L) { some(m) => print(m.get(9L) ?? -1L), none => print(-1L) }

    // maps of structs and lists inside a struct
    var book = Book { by_point: map {}, names: map {} }
    book.by_point.set(Point { x: 1, y: 1 }, Inner { c: Color.Blue, n: 77 }).unwrap()
    print(lookup(book, Point { x: 1, y: 1 }))
    print(lookup(book, Point { x: 2, y: 1 }))
    var numbers: list<int, 4> = list {}
    numbers.push(5).unwrap()
    book.names.set("n", numbers).unwrap()
    match book.names.get("n") { some(l) => print(l[0]), none => print(-1L) }
}
