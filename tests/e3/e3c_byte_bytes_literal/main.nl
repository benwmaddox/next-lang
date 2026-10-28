fn first(value: Bytes max 4) -> byte {
    value[0L]
}

fn main() {
    let signature: Bytes max 4 = [0x89, 0x50, 0x4E, 0x47]
    print(first(signature))
    print(signature[1L])
    print(signature[2L])
    print(signature[3L])
}
