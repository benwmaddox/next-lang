recursive fn is_even(n: long) -> bool {
    if n == 0L {
        true
    } else {
        is_odd(n - 1L)
    }
}

recursive fn is_odd(n: long) -> bool {
    if n == 0L {
        false
    } else {
        is_even(n - 1L)
    }
}

fn main() {
    var acc = 0L
    for i: long in 1L..130000L {
        if is_even(i % 1000L) {
            acc += 1L
        }
    }
    print(acc)
}
