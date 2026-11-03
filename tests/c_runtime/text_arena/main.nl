// Text arena windows (see text_arena.nl and docs/design/text-arena.md).
struct Source { text: pool<byte, 5000000>, name: Ascii max 8 }

fn token_sum<N>(text: pool<byte, N>, w: Id<text>, pieces: long) -> long {
    // slices w into `pieces` windows and sums their lengths and first bytes; nothing is copied
    var total = 0L
    let n = arena_len(text, w)
    for i in 0L..pieces {
        let a = i % n
        let piece = arena_slice(text, w, a, a + 1L)
        total += arena_len(text, piece) + arena_at(text, piece, 0L).to_long()
    }
    total
}

// Recursion with the arena passed read-only: it is passed by address, so the frames stay small.
recursive fn depth(src: Source, w: Id<text>, level: long) -> long {
    if level == 0L { return arena_len(src.text, w) }
    depth(src, arena_slice(src.text, w, 1L, arena_len(src.text, w)), level - 1L) + 1L
}

fn main(env: Env) {
    var small: pool<byte, 1000> = pool {}
    let w = arena_add_ascii(small, "hello world")
    print(arena_len(small, w))
    print(arena_at(small, w, 4L))
    let h = arena_slice(small, w, 0L, 5L)
    let o = arena_slice(small, w, 6L, 11L)
    print(arena_to_bytes_256(small, h))
    arena_print(env, small, o)

    // equality and order by content, regardless of position
    let again = arena_add_ascii(small, "hello")
    print(h != again)
    print(arena_equal(small, h, again))
    print(arena_equal(small, h, o))
    print(arena_less(small, h, o))
    print(arena_less(small, o, h))
    print(arena_less(small, h, w))

    // builder: text generated piece by piece, then a window over it
    let mark = arena_begin(small)
    arena_append_ascii(small, "<")
    arena_append_ascii(small, "hello")
    arena_push(small, (byte)62)
    let built = arena_finish(small, mark)
    print(arena_to_bytes_256(small, built))
    print(arena_len(small, built))

    // a 5 MB source: filled once, then sliced many times without copying
    var src = Source { text: pool {}, name: "main" }
    let start = arena_begin(src.text)
    for i in 0L..5000000L {
        arena_push(src.text, (byte)(97L + i % 26L))
    }
    let file = arena_finish(src.text, start)
    print(arena_len(src.text, file))
    print(token_sum(src.text, file, 3000000L))
    let tail = arena_slice(src.text, file, 4999990L, 5000000L)
    print(arena_to_bytes_256(src.text, tail))
    print(depth(src, file, 2000L))
}
