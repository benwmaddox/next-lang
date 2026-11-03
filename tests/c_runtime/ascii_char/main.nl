fn count_digits(s: Ascii max 40) -> long {
    var n = 0L
    for i in 0L..s.len() {
        if "0" <= s[i] && s[i] <= "9" { n += 1L }
    }
    n
}

fn copy_upper(s: Ascii max 40) -> Ascii max 40 {
    var out: Ascii max 40 = ""
    for i in 0L..s.len() {
        let upper = if s[i] >= "a" && s[i] <= "z" { s[i].to_byte() - 32 } else { s[i].to_byte() + 0 }
        discard out.push(upper)
    }
    out
}

fn main() {
    let a: Ascii max 40 = "ab 12 xyz 7"
    print(count_digits(a))
    print(copy_upper(a))
    print(a[0] == "a")
    print(a[2] == "a")
    print(a[1] != "a")
    var c = a[1]
    print(c)
    print(a[4].to_byte())
    var outer: Ascii max 4 = ""
    outer += a[3]
    outer += a[4]
    print(outer)
    print(a[0] < a[1])
    let same: Ascii max 1 = "b"
    print(a[1] == same)
}
