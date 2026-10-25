fn rewrite(buffer: grow Bytes max 32) -> Bytes max 32 {
    buffer = b"rewritten"
    buffer
}

fn identity(buffer: Bytes max 32) -> Bytes max 32 {
    buffer
}

fn main() {
    var updated: Bytes max 32 = b"old"
    updated = rewrite(updated)
    print(updated)

    var copied: Bytes max 32 = b"copy"
    copied = identity(copied)
    print(copied)
}
