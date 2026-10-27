recursive fn hanoi(n: long, acc: long) -> long {
    if n == 0L {
        acc
    } else {
        hanoi(n - 1L, hanoi(n - 1L, acc) + 1L)
    }
}

fn main() {
    print(hanoi(25L, 0L))
}
