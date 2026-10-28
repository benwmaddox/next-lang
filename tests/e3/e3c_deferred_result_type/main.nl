fn main() {
    var out: Ascii max 8 = "a"
    let invalid: long = out.try_append("b")
    print(invalid)
}
