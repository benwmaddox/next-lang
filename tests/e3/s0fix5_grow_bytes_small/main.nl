fn fill(out: grow Bytes max 4) {
    discard out.try_append(b"1234")
}

fn main() {
    var value: Bytes max 2 = b"a"
    fill(value)
}
