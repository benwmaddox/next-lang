fn fill(out: grow Text max 4 bytes max 8) {
    discard out.try_append("ééé")
}

fn main() {
    var value: Text max 2 bytes max 8 = ""
    fill(value)
}
