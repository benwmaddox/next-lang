fn classify(value: byte) -> int {
    match value {
        0 => 0,
        10 => 1,
        13 => 2,
        255 => 3,
        _ => 4
    }
}

fn main() {
    print(classify(0))
    print(classify(10))
    print(classify(13))
    print(classify(255))
    print(classify(65))
}
