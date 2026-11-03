fn main() {
    var m: map<long, long, 8> = map {}
    m.set(1L, 1L).unwrap()
    for k, v in m {
        m.set(k + 10L, v).unwrap()
    }
}
