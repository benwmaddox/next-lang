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

// A "list" here is a segment of one bump arena: (start, length). Every split and
// merge appends a fresh segment, like the reference allocating a fresh Vec.
// (stage 0 rejects large lists held across a recursive call, so the lists
// can't be locals of the recursive function.)
type Arena = list<long, 200000>

// Merges the sorted segments (a, an) and (b, bn) into a new one; returns its start.
fn merge(arena: write Arena, a: long, an: long, b: long, bn: long) -> long {
    let out = arena.count()
    var i = 0L
    var j = 0L
    for _step: long in 0L..an + bn {
        if i >= an || j >= bn {
            break
        }
        if arena[b + j] < arena[a + i] {
            arena.push(arena[b + j]).unwrap()
            j += 1L
        } else {
            arena.push(arena[a + i]).unwrap()
            i += 1L
        }
    }
    for k: long in i..an {
        arena.push(arena[a + k]).unwrap()
    }
    for k: long in j..bn {
        arena.push(arena[b + k]).unwrap()
    }
    out
}

// Naive top-down merge sort: deal the segment into two fresh halves by
// alternating elements, sort both, merge. Returns the start of the sorted segment.
recursive fn merge_sort(arena: write Arena, start: long, len_value: long) -> long {
    if len_value < 2L {
        return start
    }
    let evens = arena.count()
    for k: long in 0L..len_value {
        if k % 2L == 0L {
            arena.push(arena[start + k]).unwrap()
        }
    }
    let odds = arena.count()
    for k: long in 0L..len_value {
        if k % 2L == 1L {
            arena.push(arena[start + k]).unwrap()
        }
    }
    let even_len = (len_value + 1L) / 2L
    let odd_len = len_value / 2L
    let sorted_evens = merge_sort(arena, evens, even_len)
    let sorted_odds = merge_sort(arena, odds, odd_len)
    merge(arena, sorted_evens, even_len, sorted_odds, odd_len)
}

fn main(env: Env) {
    let seed = read_seed(env)
    var acc = 0L
    for t: long in 0L..8L {
        let s = seed + t * 131L
        var arena: Arena = list {}
        for i: long in 0L..2000L {
            arena.push(hash_at(s, i) % 100000L).unwrap()
        }
        let sorted = merge_sort(arena, 0L, 2000L)
        var weight = 0L
        for rank: long in 1L..=2000L {
            weight = (weight + arena[sorted + rank - 1L] * rank) % BIG_MOD
        }
        acc = (acc + weight) % BIG_MOD
    }
    print(acc)
}
