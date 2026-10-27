recursive fn collatz(n: long) -> long {
    if n == 1L {
        0L
    } else if n % 2L == 0L {
        1L + collatz(n / 2L)
    } else {
        1L + collatz(3L * n + 1L)
    }
}

fn main() {
    var acc = 0L
    for i: long in 1L..100001L {
        acc += collatz(i)
    }
    print(acc)
}
