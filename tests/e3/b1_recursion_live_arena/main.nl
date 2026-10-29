recursive fn keep_frame(depth: long) -> long {
    let frame: list<long, 60000> = [depth]
    if depth == 0L {
        frame[0L]
    } else {
        let child = keep_frame(depth - 1L)
        frame[0L] * 100L + child
    }
}

fn main() {
    print(keep_frame(2L))
}
