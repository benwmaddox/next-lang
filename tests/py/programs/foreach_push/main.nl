struct Entry { size: long }
struct Named { name: Bytes max 8, size: long }

fn show(name: Bytes max 8, size: long) {
    print(name.len())
    print(size)
}

fn main() {
    var files: list<Entry, 4> = list {}
    discard files.push(Entry { size: 1L })
    discard files.push(Entry { size: 2L })
    var other: list<Entry, 4> = list {}
    for edge in files { discard other.push(edge) }
    print(other.count())

    var named: list<Named, 4> = list {}
    discard named.push(Named { name: b"ab", size: 10L })
    discard named.push(Named { name: b"abcd", size: 20L })
    discard named.push(Named { name: b"abcdefgh", size: 30L })
    var copy: list<Named, 4> = list {}
    for entry in named {
        show(entry.name, entry.size)
        discard copy.push(entry)
    }
    print(copy.count())
    print(copy[0L].name.len())
    print(copy[1L].name.len())
    print(copy[2L].name.len())
    print(copy[2L].size)
}
