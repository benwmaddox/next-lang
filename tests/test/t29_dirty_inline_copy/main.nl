fn duplicate(value: Ascii max 9000000) -> Ascii max 9000000 { value }

test "copy only touches live inline field bytes" {
    var source: Ascii max 9000000 = Ascii.empty()
    for index in 0..8000000 { source += "x" }
    expect source.len() == 8000000L
    source = "x"
    let copied = duplicate(source)
    expect copied == "x"
}

fn main() {}
