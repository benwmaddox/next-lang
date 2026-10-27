recursive fn gcd(a: long, b: long) -> long {
    if b == 0L { a } else { gcd(b, a % b) }
}

fn main() {
    let n = 2000L
    var acc = 0L
    for i: long in 1L..=n {
        for j: long in 1L..=n {
            if gcd(i, j) == 1L {
                acc += 1L
            }
        }
    }
    print(acc)
}
