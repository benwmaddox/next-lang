fn show_ascii(label: Ascii max 8, value: Option<Ascii max 1>) {
    match value {
        some(c) => print(label + c),
        none => print(label + "-"),
    }
}

fn show_text(label: Ascii max 8, value: Option<Text max 1>) {
    match value {
        some(c) => print(label + c),
        none => print(label + "-"),
    }
}

fn main() {
    let empty: Ascii max 8 = ""
    let word: Ascii max 8 = "hello"
    show_ascii("first ", word.first())
    show_ascii("last ", word.last())
    show_ascii("first ", empty.first())
    show_ascii("last ", empty.last())

    let blank: Text max 8 = ""
    let mixed: Text max 8 = "aé€😀"
    let ends: Text max 8 = "😀bé"
    show_text("tfirst ", mixed.first())
    show_text("tlast ", mixed.last())
    show_text("efirst ", ends.first())
    show_text("elast ", ends.last())
    show_text("nfirst ", blank.first())
    show_text("nlast ", blank.last())

    // Text +=, push, appending a character
    var t: Text max 6 = ""
    t += "ab"
    t += "c"
    t += mixed.slice(1..3)
    print(t)
    print(t.len())
    var p: Text max 3 = ""
    discard p.push(72)
    discard p.push(105)
    print(p)
    match p.push(33) { ok(_) => print("pushed"), err(_) => print("full") }
    match p.push(33) { ok(_) => print("pushed"), err(_) => print("full") }
    print(p.len())
    var a: Ascii max 4 = ""
    discard a.push(104)
    discard a.push(105)
    print(a)

    // to_bytes copies
    let b = word.to_bytes()
    print(b.count())
    print(b[1])
    let tb = ends.to_bytes()
    print(tb.count())
    print(tb[0])

    // tight constant-range slices append into small destinations without try_append
    let long_word: Ascii max 1000 = "0123456789"
    var one: Ascii max 2 = ""
    one += long_word.slice(3..4)
    print(one)
    var two: Ascii max 1 = ""
    two += long_word.slice(5..=5)
    print(two)
}
