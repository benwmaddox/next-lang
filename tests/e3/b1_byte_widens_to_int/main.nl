struct P {
    cur: int
}

fn twice(x: int) -> int {
    x * 2
}

fn get(b: byte) -> int {
    b
}

fn main() {
    let b: byte = 200
    let x: int = b
    var p = P { cur: 0 }
    p.cur = b
    print(x)
    print(p.cur)
    print(twice(b))
    print(get(b))
    print(b + 5)
    print(b == 200)
}
