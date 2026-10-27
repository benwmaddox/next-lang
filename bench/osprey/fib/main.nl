fn add(a: long, b: long) -> long {
    a + b
}

fn sub(a: long, b: long) -> long {
    a - b
}

recursive fn fib(n: long) -> long {
    match n {
        0L => 0L
        1L => 1L
        _ => add(fib(sub(n, 1L)), fib(sub(n, 2L)))
    }
}

fn main() {
    print(fib(35L))
}
