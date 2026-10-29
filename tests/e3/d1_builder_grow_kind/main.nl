fn grow_text(out: grow Text max 1 bytes max 4) {
    discard out.try_append("x")
}

fn main() {
    var ascii: Ascii max 1 = ""
    grow_text(ascii)
}
