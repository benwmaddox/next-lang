// Built-in unbounded text: arena<N> and Window<arena> (provisional names), docs/design/text-arena.md.
struct Source { name: Ascii max 8, text: arena<5000000> }

fn describe<N>(src: arena<N>, w: Window<src>) -> long {
    w.len() + w[0L].to_long()
}

fn token_sum<N>(src: arena<N>, w: Window<src>, pieces: long) -> long {
    // slices w into `pieces` one-byte windows and sums lengths and bytes; nothing is copied
    var total = 0L
    let n = w.len()
    for i in 0L..pieces {
        let a = i % n
        let piece = w.slice(a..a + 1L)
        total += piece.len() + piece[0L].to_long()
    }
    total
}

// Recursion with the arena passed read-only (by address): the frames stay small for a 5 MB arena.
recursive fn depth<N>(src: arena<N>, w: Window<src>, level: long) -> long {
    if level == 0L { return w.len() }
    depth(src, w.slice(1L..w.len()), level - 1L) + 1L
}

fn fill(src: write arena<5000000>) -> Window<src> {
    src.begin()
    for i in 0L..5000000L {
        src.push((byte)(97L + i % 26L))
    }
    src.finish()
}

fn main(env: Env) {
    var small: arena<1000> = arena {}
    let w = small.add("hello world")
    print(w.len())
    print(w[4L])
    print(small.used())
    let h = w.slice(0L..5L)
    let o = w.slice(6L..11L)
    print(h)
    print(o)
    print(describe(small, h))

    // equality and order by content, regardless of position
    let again = small.add("hello")
    print(h == again)
    print(h != again)
    print(h == o)
    print(h < o)
    print(o < h)
    print(h < w)
    print(w >= h)
    print(small.used())

    // copy out to a bounded value
    let b: Bytes max 64 = o.to_bytes()
    print(b.len())
    let a: Ascii max 8 = h.to_bytes()
    print(a)

    // builder: text generated piece by piece in the same arena, then a window over it
    small.begin()
    small.append("<")
    small.append(h)
    small.push((byte)62)
    let built = small.finish()
    print(built)
    print(built.len())

    // a 5 MB source in a struct field: filled once, sliced many times without copying
    var s = Source { name: "main", text: arena {} }
    let file = fill(s.text)
    print(file.len())
    print(s.text.used())
    print(token_sum(s.text, file, 3000000L))
    print(depth(s.text, file, 2000L))
    let tail = file.slice(4999990L..5000000L)
    print(tail)
}
