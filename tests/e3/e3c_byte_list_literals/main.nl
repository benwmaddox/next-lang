fn first(value: list<byte, 4>) -> byte {
    value[0L]
}

fn main() {
    let magic: list<byte, 4> = [0x1F, 0x8B, 8, 0]
    print(first(magic))
    print(magic[1L])
    print(magic[2L])
    print(magic[3L])
}
