fn main() {
    let text: Text max 4 bytes max 10 = "Aé😀Z"
    print(text.slice(0L..=9223372036854775807L))
}
