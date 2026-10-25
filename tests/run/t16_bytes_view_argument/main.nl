fn duplicate(value: Bytes max 16) -> Bytes max 16 { value }

fn main() {
    let text: Text max 4 = "view"
    let copy = duplicate(text.bytes())
    print(copy.len())
}
