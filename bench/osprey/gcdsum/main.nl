recursive fn gcd(a: long, b: long) -> long {
    match b {
        0L => a
        _ => gcd(b, a % b)
    }
}

fn main() {
    var acc = 0L
    for i: long in 1L..2000000L {
        acc += gcd(i, 1234567L)
    }
    print(acc)
}
