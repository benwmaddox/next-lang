fn main() {
    let source: Ascii max 8 = "x"
    let moved: Ascii max 8 = take source
    print(moved)
    print(source)
}
