fn main() {
    let source: Ascii max 8 = "cat"
    match source.fit<Ascii max 3>() {
        some(value) => print(value),
        none => print("missing"),
    }
    match source.fit<Ascii max 2>() {
        some(value) => print(value),
        none => print("none"),
    }
    match "dog".fit<Ascii max 3>() {
        some(value) => print(value),
        none => print("missing"),
    }
}
