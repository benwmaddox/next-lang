fn build_response(seed: long) -> Ascii max 64 {
    let count = (seed % 10L) + 1L
    return str(count) + "|" + str(seed % 100L)
}

fn main() {
    var checksum = 0L
    var seed = 1L

    for req_index: long in 0L..1000000L {
        var items: list<long, 512> = list {}
        let item_count = (seed % 256L) + 1L

        for _i: long in 0L..item_count {
            seed = (seed * 1103515245L + 12345L) % 2147483648L
            discard items.push(seed)
        }

        var req_checksum = 0L
        for item in items {
            req_checksum = (req_checksum * 31L + item) % 1000000007L
        }

        let resp = build_response(seed)
        checksum = (checksum * 31L + req_checksum) % 1000000007L
        let resp_len: int = (int)resp.len()
        checksum = (checksum * 31L + resp_len.to_long()) % 1000000007L

        seed = (seed * 1103515245L + 12345L) % 2147483648L
    }

    print(checksum)
}
