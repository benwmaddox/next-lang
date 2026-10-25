fn main() {
    var out: Ascii max 100 = Ascii.empty()
    for i in 0..=100 {
        let piece = if i >= 0 { out += "x"; "x" } else { "" }
    }
    print(out.len())
}
