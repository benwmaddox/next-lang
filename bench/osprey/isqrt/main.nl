fn isqrt(n: long) -> long {
    if n < 2L {
        return n
    }
    var x = n
    for _step: long in 0L..64L {
        let y = (x + n / x) / 2L
        if y < x {
            x = y
        } else {
            break
        }
    }
    x
}

fn main() {
    var acc = 0L
    for i: long in 1L..1000001L {
        acc += isqrt(i)
    }
    print(acc)
}
