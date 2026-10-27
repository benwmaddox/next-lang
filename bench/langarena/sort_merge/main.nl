// LangArena Sort::Merge: merge sort of a copy of the data, checksum from two random picks per run.
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

recursive fn merge_sort(arr: write list<int, 400000>, temp: write list<int, 400000>, left: long, right: long) {
    if left >= right { return }
    let mid = (left + right) / 2L
    merge_sort(arr, temp, left, mid)
    merge_sort(arr, temp, mid + 1L, right)
    for x in left..=right { temp[x] = arr[x] }
    var i = left
    var j = mid + 1L
    var k = left
    for _step in 0L..right - left + 1L {
        if i > mid || j > right { break }
        if temp[i] <= temp[j] {
            arr[k] = temp[i]
            i += 1L
        } else {
            arr[k] = temp[j]
            j += 1L
        }
        k += 1L
    }
    for _rest in 0L..right - left + 1L {
        if i > mid { break }
        arr[k] = temp[i]
        i += 1L
        k += 1L
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

    var scratch: list<int, 400000> = list {}
    for _z in 0L..size { discard scratch.push(0) }
    var result = 0L
    for _round in 0L..warmup + iterations {
        if _round == warmup { rng.last = 42L }
        result = (result + data[next_int(rng, size)].to_long()) % MODULUS
        var t = data
        merge_sort(t, scratch, 0L, size - 1L)
        result = (result + t[next_int(rng, size)].to_long()) % MODULUS
    }
    print(result)
}
