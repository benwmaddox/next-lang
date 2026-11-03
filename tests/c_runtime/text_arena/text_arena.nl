// Text arena, stage 1 (docs/design/text-arena.md). An arena is a `pool<byte, N>` (a byte buffer of declared capacity, owned
// by whoever declares it, never copied). A window is an owned id of that arena, `Id<text>`: one long that packs
// (start << 32) | length, so it is plain data, copied freely, and names its arena like any pool id. The compiler's pool-owner
// check refuses a window of one arena where another arena is expected. Every operation takes the arena first, so reading
// bytes never depends on anything hidden. Exhaustion, a bad slice and a bad index fail the program ("unwrap called on none").
// A window is an immutable range of arena bytes; the arena only grows (there is no remove), so windows never dangle.

fn arena_fail<N>(text: pool<byte, N>) -> long {
    text.get(-1L).unwrap().to_long()
}

fn arena_len<N>(text: pool<byte, N>, w: Id<text>) -> long {
    w & 4294967295L
}

fn arena_start<N>(text: pool<byte, N>, w: Id<text>) -> long {
    w >> 32L
}

// The arena slot of byte i of w, as an owned id (the only place that builds an id by arithmetic: a built-in would do this
// inside the compiler). Callers check i against the window's length first.
fn arena_slot<N>(text: pool<byte, N>, w: Id<text>, i: long) -> Id<text> {
    (w >> 32L) + i
}

fn arena_get<N>(text: pool<byte, N>, w: Id<text>, i: long) -> byte {
    text.get(arena_slot(text, w, i)).unwrap()
}

// Appends the bytes of an ASCII text (a literal, or any Ascii value up to 4096 long) and returns its window.
fn arena_add_ascii<N>(text: write pool<byte, N>, s: Ascii max 4096) -> Id<text> {
    let start = text.count()
    for i in 0L..s.len() {
        discard text.add(s[i].to_byte()).unwrap()
    }
    start * 4294967296L + s.len()
}

// Provisional builder (just enough to fill a large arena): `mark = arena_begin(text)`, any number of arena_push / arena_append_*, then `arena_finish(text, mark)`.
// The builder writes at the arena's end, so only one builder may be open at a time (appends of another would interleave).
fn arena_begin<N>(text: pool<byte, N>) -> long {
    text.count()
}

fn arena_push<N>(text: write pool<byte, N>, b: byte) {
    discard text.add(b).unwrap()
}

fn arena_append_ascii<N>(text: write pool<byte, N>, s: Ascii max 4096) {
    for i in 0L..s.len() {
        discard text.add(s[i].to_byte()).unwrap()
    }
}

fn arena_finish<N>(text: pool<byte, N>, mark: long) -> Id<text> {
    mark * 4294967296L + (text.count() - mark)
}

// The window of bytes a..b (b exclusive) of w. No bytes are copied.
fn arena_slice<N>(text: pool<byte, N>, w: Id<text>, a: long, b: long) -> Id<text> {
    if a < 0L || b < a || b > (w & 4294967295L) { discard arena_fail(text) }
    ((w >> 32L) + a) * 4294967296L + (b - a)
}

fn arena_at<N>(text: pool<byte, N>, w: Id<text>, i: long) -> byte {
    if i < 0L || i >= (w & 4294967295L) { discard arena_fail(text) }
    arena_get(text, w, i)
}

fn arena_equal<N>(text: pool<byte, N>, a: Id<text>, b: Id<text>) -> bool {
    let n = a & 4294967295L
    if n != (b & 4294967295L) { return false }
    if arena_start(text, a) == arena_start(text, b) { return true }
    for i in 0L..n {
        if arena_get(text, a, i) != arena_get(text, b, i) { return false }
    }
    true
}

// Bytes in order, then the shorter first (the same order as sort on text).
fn arena_less<N>(text: pool<byte, N>, a: Id<text>, b: Id<text>) -> bool {
    let na = a & 4294967295L
    let nb = b & 4294967295L
    let n = if na < nb { na } else { nb }
    for i in 0L..n {
        let x = arena_get(text, a, i)
        let y = arena_get(text, b, i)
        if x < y { return true }
        if y < x { return false }
    }
    na < nb
}

// Copy out to a bounded value; fails when the window is longer than the bound.
fn arena_to_bytes_256<N>(text: pool<byte, N>, w: Id<text>) -> Bytes max 256 {
    var out: Bytes max 256 = Bytes.empty()
    for i in 0L..arena_len(text, w) {
        discard out.push(arena_get(text, w, i)).unwrap()
    }
    out
}

// Prints the window and a newline, in pieces of at most 256 bytes.
fn arena_print<N>(env: Env, text: pool<byte, N>, w: Id<text>) {
    let n = w & 4294967295L
    var at = 0L
    while at < n {
        let end = if at + 256L < n { at + 256L } else { n }
        match env.out.write(arena_to_bytes_256(text, arena_slice(text, w, at, end))) { ok(_) => (), err(_) => () }
        at = end
    }
    print("")
}
