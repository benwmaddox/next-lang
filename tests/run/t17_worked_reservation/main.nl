fn line(name: Ascii max 60, count: int 0..=999999) -> Ascii max 80 {
    let upper = ascii_upper(name)
    upper + ": " + str(count)
}

fn render() -> Ascii max 40000 {
    var out: Ascii max 40000 = Ascii.empty()
    for count: int in 0..500 {
        out += line("r", count)
    }
    out
}

fn main() {
    let output = render()
    print(output.len())
}
