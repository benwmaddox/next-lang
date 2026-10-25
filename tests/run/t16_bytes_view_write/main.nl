fn overwrite(value: write Bytes max 8) {}

fn main() {
    let text: Text max 2 = "ok"
    overwrite(text.bytes())
}
