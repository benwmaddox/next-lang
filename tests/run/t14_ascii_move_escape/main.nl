fn escaping() -> Option<Ascii max 8> {
    let source: Ascii max 8 = "x"
    return some(take source)
}

fn main() {
    match escaping() {
        some(value) => print(value),
        none => print("none")
    }
}
