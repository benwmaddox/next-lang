fn main() {
    var acc = 0L
    for i: long in 2L..10000001L {
        acc = (acc + 7L) % i
    }
    print(acc)
}
