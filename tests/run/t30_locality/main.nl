fn locality() -> long {
    let before: Ascii max 16 = "before"
    var buffer: Bytes max 1048576 = Bytes.empty()
    let fixed: list<long, 4> = list {}
    let after: Ascii max 16 = "after"
    before.len() + fixed.count() + after.len()
}

fn main() {
    print(locality())
}
