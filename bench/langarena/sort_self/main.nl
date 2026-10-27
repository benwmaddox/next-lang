// LangArena Sort::Self: built-in sort of a copy of the data, checksum from two random picks per run.
const CAPACITY: long = 400000L
const MODULUS: long = 4294967296L

struct Rng { last: long }

fn next_int(rng: write Rng, max_value: long) -> long {
    rng.last = (rng.last * 3877L + 29573L) % 139968L
    rng.last * max_value / 139968L
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn main(env: Env) {
    let run = is_run_mode(env)
    let size = if run { 400000L } else { 100000L }
    let iterations = if run { 50L } else { 2L }
    let warmup = if iterations / 5L > 1L { iterations / 5L } else { 1L }

    var rng = Rng { last: 42L }
    var data: list<int, 400000> = list {}
    for _i in 0L..size {
        discard data.push((int)next_int(rng, 1000000L))
    }

    var result = 0L
    for _round in 0L..warmup + iterations {
        if _round == warmup { rng.last = 42L }
        result = (result + data[next_int(rng, size)].to_long()) % MODULUS
        var t = data
        sort(t)
        result = (result + t[next_int(rng, size)].to_long()) % MODULUS
    }
    print(result)
}
