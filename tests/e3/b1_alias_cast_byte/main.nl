type Octet = byte

fn widen(o: Octet) -> int {
    (int)o + 1
}

fn main() {
    let y: int = 200
    let o = (Octet)(y)
    print(widen(o))
}
