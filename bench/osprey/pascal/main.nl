recursive fn binom(n: long, k: long) -> long {
    if k == 0L {
        1L
    } else if k == n {
        1L
    } else {
        binom(n - 1L, k - 1L) + binom(n - 1L, k)
    }
}

fn main() {
    print(binom(27L, 13L))
}
