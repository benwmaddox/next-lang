recursive fn has_factor(n: long, d: long) -> bool {
    if d * d > n {
        false
    } else if n % d == 0L {
        true
    } else {
        has_factor(n, d + 1L)
    }
}

fn is_prime(n: long) -> bool {
    if n < 2L {
        false
    } else {
        !has_factor(n, 2L)
    }
}

fn main() {
    var acc = 0L
    for n: long in 2L..200000L {
        if is_prime(n) {
            acc += 1L
        }
    }
    print(acc)
}
