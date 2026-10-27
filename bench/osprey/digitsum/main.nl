recursive fn digsum(n: long) -> long {
    if n < 10L {
        n
    } else {
        n % 10L + digsum(n / 10L)
    }
}

fn main() {
    var acc = 0L
    for i: long in 1L..2000001L {
        acc += digsum(i)
    }
    print(acc)
}
