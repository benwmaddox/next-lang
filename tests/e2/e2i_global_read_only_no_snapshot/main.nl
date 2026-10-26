struct Big { a: int, pad: int[1100] }
global g: Big = Big { a: 1, pad: fill(0) }

fn peek() -> int {
    g.a
}

fn show(b: Big, marker: int) {
    print(b.a)
    print(marker)
}

fn main() {
    show(g, peek())
}
