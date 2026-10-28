fn slice_large(input: Ascii max 1048576) -> Ascii max 1048576 {
    input.slice(0L..4L)
}

fn main() {
    let large: Ascii max 1048576 = "large"
    print(slice_large(large))
}
