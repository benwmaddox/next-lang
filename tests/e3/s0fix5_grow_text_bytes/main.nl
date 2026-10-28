fn fill(out: grow Text max 2 bytes max 8) {
    discard out.try_append("😀😀")
}

fn main() {
    var value: Text max 2 bytes max 4 = ""
    fill(value)
}
