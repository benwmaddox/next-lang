fn line(name: Ascii max 60, amount: int 0..=999999) -> Ascii max 80 {
    let upper = ascii_upper(name)
    upper + ": " + str(amount)
}

fn render() -> Ascii max 40000 {
    var out: Ascii max 40000 = Ascii.empty()
    for amount: int in 0..500 {
        out += line("r", amount)
    }
    out
}

fn main() {
    let output = render()
    print(output.len())
}
