enum Choice {
    Caption(Text max 3 bytes max 12),
    Label(Ascii max 8),
    Binary(Bytes max 8),
    Empty,
}

fn hold(values: Choice[2], items: list<Choice, 2>) {}

fn main() {}
