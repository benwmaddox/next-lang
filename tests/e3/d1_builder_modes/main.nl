fn append(out: grow Ascii max 4) {
    discard out.try_append("x")
}

fn read_then_grow(out: Ascii max 4) {
    append(out)
}

fn main() {
    var mutable: Ascii max 4 = ""
    read_then_grow(mutable)
}
