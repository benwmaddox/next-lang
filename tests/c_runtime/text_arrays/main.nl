const WIDTH: int = 8

struct Row { names: Bytes max 16[3], tags: Ascii max 8[2], plain: Ascii max (WIDTH + 2) }

fn longest(names: Bytes max 16[3]) -> long {
    var best = 0L
    for name in names { if name.len() > best { best = name.len() } }
    best
}

fn main() {
    var names: Bytes max 16[3] = [b"a", b"bb", b"ccc"]
    print(names[1].len())
    print(longest(names))
    var row = Row { names, tags: ["x", "yy"], plain: "0123456789" }
    row.tags[0] = "zzz"
    print(row.tags[0])
    print(row.tags[1])
    print(row.names[2].len())
    print(row.plain)
}
