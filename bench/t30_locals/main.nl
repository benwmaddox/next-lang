fn rewrite(buffer: grow Bytes max 32, index: long) -> Bytes max 32 {
    if index % 2L == 0L {
        buffer = b"even"
    } else {
        buffer = b"odd"
    }
    buffer
}

fn locality(index: long) -> long {
    let before: Ascii max 16 = "before"
    var reserved: Bytes max 1048576 = Bytes.empty()
    var fixed: list<long, 4> = list {}
    discard fixed.push(index)
    let after: Ascii max 16 = "after"
    before.len() + fixed[0L] + after.len()
}

fn main() {
    var buffer: Bytes max 32 = b"old"
    var total: long = 0L
    for i in 0..10000000 {
        let index = i.to_long()
        buffer = rewrite(buffer, index)
        total += locality(index)
    }
    print(total)
    print(buffer)
}
