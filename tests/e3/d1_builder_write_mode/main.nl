fn append(out: write Ascii max 4) {
    discard out.try_append("x")
}

fn main() {
    var mutable: Ascii max 4 = ""
    append(mutable)
}
