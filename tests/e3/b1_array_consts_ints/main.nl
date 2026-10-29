const PRIMES: int[6] = [2, 3, 5, 7, 11, 13]
const WEIGHTS: long[3] = [10000000000L, -5L, 7L]
const MASKS: byte[4] = [1, 2, 4, 128]

fn main() {
    var total: long = 0L
    for i: long in 0L..6L { total += (long)PRIMES[i] }
    print(total)
    print(WEIGHTS[0L] + WEIGHTS[1L] + WEIGHTS[2L])
    print((int)MASKS[3L] + (int)MASKS[1L])
    let local = PRIMES
    print(local[5L])
}
