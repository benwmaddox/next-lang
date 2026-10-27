fn add(a: long, b: long) -> long {
    a + b
}

fn sub(a: long, b: long) -> long {
    a - b
}

recursive fn ack(m: long, n: long) -> long {
    if m == 0L {
        add(n, 1L)
    } else if n == 0L {
        ack(sub(m, 1L), 1L)
    } else {
        ack(sub(m, 1L), ack(m, sub(n, 1L)))
    }
}

fn main() {
    print(ack(3L, 10L))
}
