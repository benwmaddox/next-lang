struct Big { a: int, pad: int[1100] }
global g: Big = Big { a: 1, pad: fill(0) }

fn bump() -> int {
    g.a = 9
    0
}

fn show(b: Big, z: int) {
    print(b.a)
}

fn main() {
    show(g, bump())
}
