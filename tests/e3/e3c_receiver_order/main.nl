fn replace_text(value: write Text max 8 bytes max 32) -> long {
    value = "KQ!"
    2L
}

fn replace_with_longer(value: write Text max 8 bytes max 32) -> long {
    value = "éBC"
    3L
}

fn main() {
    var receiver: Text max 8 bytes max 32 = "é🦊Z"
    print(receiver.slice(0L..replace_text(receiver)))
    print(receiver)

    var short: Text max 8 bytes max 32 = "A"
    print(short.slice(0L..replace_with_longer(short)))
}
