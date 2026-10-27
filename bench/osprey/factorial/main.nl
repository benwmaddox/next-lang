const MOD: long = 1000000007L

fn main() {
    var acc = 1L
    for i: long in 1L..=10000000L {
        acc = (acc * i) % MOD
    }
    print(acc)
}
