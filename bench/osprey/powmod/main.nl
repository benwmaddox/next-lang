const P: long = 1000000007L

recursive fn powmod(base: long, e: long, acc: long) -> long {
    match e {
        0L => acc
        _ => powmod(base, e - 1L, (acc * base) % P)
    }
}

fn main() {
    var acc = 0L
    for i: long in 1L..1000000L {
        acc = (acc + powmod(i, 20L, 1L)) % P
    }
    print(acc)
}
