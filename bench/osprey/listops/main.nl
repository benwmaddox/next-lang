const MINSTD: long = 16807L
const MODULUS: long = 2147483647L
const BIG_MOD: long = 1000000007L

fn r1(x: long) -> long {
    (x * MINSTD) % MODULUS
}

fn hash_at(s: long, i: long) -> long {
    r1(r1(s + i))
}

// Stands in for the reference's stdin read: the first argument is the seed
// selector. "0" means seed 1; any other decimal number selects another seed
// (the reference uses a random one there).
fn read_seed(env: Env) -> long {
    match env.args().get(0L) {
        some(argument) => {
            var m = 0L
            for i: long in 0L..argument.count() {
                let digit = argument.get(i).unwrap().to_long() - 48L
                m = (m * 10L + digit) % 2147483646L
            }
            if m == 0L { 1L } else { m + 1L }
        }
        none => 1L
    }
}

fn main(env: Env) {
    let seed = read_seed(env)
    var acc = 0L
    for t: long in 0L..8L {
        let s = seed + t * 131L
        var xs: list<long, 4000> = list {}
        for i: long in 0L..4000L {
            xs.push(hash_at(s, i) % 1000L).unwrap()
        }
        var sum = 0L
        var below = 0L
        for x in xs {
            sum += x
            if x < 500L {
                below += 1L
            }
        }
        acc = (acc + sum + below) % BIG_MOD
    }
    print(acc)
}
