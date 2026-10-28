struct Holder {
    text: Ascii max 4,
    sibling: int,
}

fn fill(out: grow Ascii max 8) {
    discard out.try_append("12345678")
}

fn main() {
    var holder = Holder { text: "a", sibling: 7 }
    fill(holder.text)
    print(holder.text)
    print(holder.sibling)
}
