struct Big { data: int[2048] }

fn make_big() -> Big {
    Big { data: fill(1) }
}

recursive fn walk(n: int, value: Big) -> int {
    if n == 0 { value.data[0] } else { walk(n - 1, make_big()) }
}

fn main() {
    print(walk(1, make_big()))
}
