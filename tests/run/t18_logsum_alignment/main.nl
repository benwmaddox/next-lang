struct Top { value: long, key: Ascii max 10 }

fn top_by_value() -> Top {
    Top { value: 42L, key: "alpha" }
}

fn main() {
    let top = top_by_value()
    let rank = 0L
    var out: Ascii max 64 = Ascii.empty()
    out += pad(str(rank + 1L), 3) + " " + pad(str(top.value), 10) + " " + top.key
    print(out)
}
