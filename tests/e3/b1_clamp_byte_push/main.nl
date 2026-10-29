fn main() {
    var out: Bytes max 8 = Bytes.empty()
    let n: long = 300L
    let m: long = -5L
    out.push(clamp((int)n, 0, 255)).unwrap()
    out.push(clamp((int)m, 0, 255)).unwrap()
    out.push(clamp(7, 0, 255)).unwrap()
    print(out.len())
    print((int)out[0L])
    print((int)out[1L])
    print((int)out[2L])
}
