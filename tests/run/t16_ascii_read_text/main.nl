fn read_text(value: Text max 8) -> long { value.len() }

fn main() {
    let value: Ascii max 5 = "plain"
    print(read_text(value))
}
