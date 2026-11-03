// A window of one text arena cannot be read through another arena.
fn arena_len<N>(text: pool<byte, N>, w: Id<text>) -> long {
    w & 4294967295L
}

fn main() {
    var a: pool<byte, 100> = pool {}
    var b: pool<byte, 100> = pool {}
    let w = a.add((byte)65).unwrap()
    print(arena_len(a, w))
    print(arena_len(b, w))
}
