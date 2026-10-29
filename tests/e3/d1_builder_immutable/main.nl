fn append(out: grow Ascii max 4) {
    discard out.try_append("x")
}

fn main() {
    let fixed: Ascii max 4 = "a"
    append(fixed)
}
