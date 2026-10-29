fn append(out: grow Ascii max 4) {
    discard out.try_append("x")
}

fn make_ascii() -> Ascii max 4 {
    "a"
}

fn main() {
    append(make_ascii())
}
