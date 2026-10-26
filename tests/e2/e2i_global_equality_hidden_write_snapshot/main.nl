struct Big { a: int, pad: int[1100] }
global g: Big = Big { a: 1, pad: fill(0) }

fn touch_then_copy() -> Big {
    g.a = 9
    g
}

fn main() {
    print(g == touch_then_copy())
}
