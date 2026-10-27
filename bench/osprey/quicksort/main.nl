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

// A "list" here is a segment of one bump arena: (start, length). Every partition
// and join appends fresh segments, like the reference allocating fresh Vecs.
// (stage 0 rejects large lists held across a recursive call, so the lists
// can't be locals of the recursive function.)
type Arena = list<long, 400000>

// Naive first-element-pivot quicksort: split the tail into two fresh segments
// around the pivot, sort both, join. Returns the start of the sorted segment.
recursive fn quicksort(arena: write Arena, start: long, len: long) -> long {
    if len == 0L {
        return start
    }
    let pivot = arena[start]
    let below = arena.count()
    for k: long in 1L..len {
        if arena[start + k] < pivot {
            arena.push(arena[start + k]).unwrap()
        }
    }
    let below_len = arena.count() - below
    let at_least = arena.count()
    for k: long in 1L..len {
        if arena[start + k] >= pivot {
            arena.push(arena[start + k]).unwrap()
        }
    }
    let at_least_len = arena.count() - at_least
    let sorted_below = quicksort(arena, below, below_len)
    let sorted_at_least = quicksort(arena, at_least, at_least_len)
    let out = arena.count()
    for k: long in 0L..below_len {
        arena.push(arena[sorted_below + k]).unwrap()
    }
    arena.push(pivot).unwrap()
    for k: long in 0L..at_least_len {
        arena.push(arena[sorted_at_least + k]).unwrap()
    }
    out
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
        let sorted = quicksort(arena, 0L, 2000L)
        var weight = 0L
        for rank: long in 1L..=2000L {
            weight = (weight + arena[sorted + rank - 1L] * rank) % BIG_MOD
        }
        acc = (acc + weight) % BIG_MOD
    }
    print(acc)
}
