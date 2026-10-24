fn main() {
    var r: ring<long, 1> = ring {}
    r.push(1L)
    for item in r {
        r.push(item)
    }
}
