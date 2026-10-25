fn classify(value: byte) -> int {
    match value {
        10 => 1,
        13 => 2
    }
}

fn main() {
    print(classify(10))
}
