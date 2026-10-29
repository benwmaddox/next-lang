fn main() {
    var b: Bytes max 8 = Bytes.empty()
    let x: int = 65
    discard b.push(x)
    let y: int = 300
    match b.push(y) {
        ok(_) => print(1)
        err(_) => print(0)
    }
    let z: int = -1
    match b.push(z) {
        ok(_) => print(1)
        err(_) => print(0)
    }
    print(b.len())
    print((int)b[1L])
}
