const P: long = 1000000007L

fn loop_k(i: long, j: long, n: long, start: long) -> long {
    var acc = start
    for k: long in 1L..=n {
        acc = (acc + i * j * k) % P
    }
    acc
}

fn loop_j(i: long, n: long, start: long) -> long {
    var acc = start
    for j: long in 1L..=n {
        acc = loop_k(i, j, n, acc)
    }
    acc
}

fn loop_i(n: long, start: long) -> long {
    var acc = start
    for i: long in 1L..=n {
        acc = loop_j(i, n, acc)
    }
    acc
}

fn main() {
    print(loop_i(250L, 0L))
}
