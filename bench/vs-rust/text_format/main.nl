fn format_record(id: long, value: long, name: long) -> Ascii max 64 {
    return str(id) + ":" + str(value) + "=" + str(name)
}

fn main() {
    var checksum = 0L
    var seed = 1L

    for _batch: long in 0L..400L {
    var output: Ascii max 7000000 = Ascii.empty()
    for _i: long in 0L..100000L {
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let id = seed
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let value = seed % 10000L
        seed = (seed * 1103515245L + 12345L) % 2147483648L
        let name = seed % 1000L

        let line = format_record(id, value, name)
        output += line
        output += ","

        let line_len: int = (int)line.len()
        checksum = (checksum * 31L + line_len.to_long()) % 1000000007L
        checksum = (checksum * 31L + value) % 1000000007L
        checksum = (checksum * 31L + name) % 1000000007L
    }
    let out_len: int = (int)output.len()
    checksum = (checksum * 31L + out_len.to_long()) % 1000000007L
    }

    print(checksum)
}
