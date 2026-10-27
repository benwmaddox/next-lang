fn fill(out: grow Ascii max 8) {
    discard out.try_append("12345678")
}

fn main() {
    var value: Ascii max 2 = "a"
    fill(value)
    print(value)
}
