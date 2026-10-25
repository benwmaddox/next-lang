struct Big { data: int[2048] }

recursive fn make(n: int) -> Big {
    if n == 0 { Big { data: fill(n) } } else { make(n - 1) }
}

fn main() {
    print(make(1).data[0])
}
