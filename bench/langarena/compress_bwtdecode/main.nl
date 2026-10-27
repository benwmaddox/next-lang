// LangArena Compress::BWTDecode: inverse Burrows-Wheeler transform of data produced by a
// prefix-doubling forward transform (sort the rotations by pairs of ranks).
type Octet = int 0..=255

struct Entry {
    first: long
    second: long
    index: long
}

struct BwtResult {
    transformed: list<byte, 1000001>
    original_idx: long
}

fn is_run_mode(env: Env) -> bool {
    match env.args().get(0L) {
        some(argument) => argument.count() == 3L,
        none => false
    }
}

fn generate_test_data(size: long) -> list<byte, 1000001> {
    let pattern: Bytes max 11 = b"ABRACADABRA"
    var data: list<byte, 1000001> = list {}
    for i: long in 0L..size {
        discard data.push(pattern[i % 11L])
    }
    data
}

fn entry_less(ctx: int, a: Entry, b: Entry) -> bool {
    if a.first != b.first {
        a.first < b.first
    } else {
        a.second < b.second
    }
}

fn bwt_transform(input: list<byte, 1000001>) -> BwtResult {
    let size = input.count()
    var result = BwtResult { transformed: list {}, original_idx: 0L }
    if size == 0L {
        return result
    }

    var suffixes: list<long, 1000001> = list {}
    for _i: long in 0L..size {
        discard suffixes.push(0L)
    }

    var counts: long[256] = fill(0L)
    for i: long in 0L..size {
        counts[input[i].to_long()] += 1L
    }
    var positions: long[256] = fill(0L)
    var total = 0L
    for c: long in 0L..256L {
        positions[c] = total
        total += counts[c]
    }
    var placed: long[256] = fill(0L)
    for i: long in 0L..size {
        let byte_value = input[i].to_long()
        suffixes[positions[byte_value] + placed[byte_value]] = i
        placed[byte_value] += 1L
    }

    if size > 1L {
        var rank: list<long, 1000001> = list {}
        for _i: long in 0L..size {
            discard rank.push(0L)
        }
        var current_rank = 0L
        var previous = input[suffixes[0L]]
        for position: long in 0L..size {
            let index = suffixes[position]
            if input[index] != previous {
                current_rank += 1L
                previous = input[index]
            }
            rank[index] = current_rank
        }

        var entries: list<Entry, 1000001> = list {}
        for position: long in 0L..size {
            discard entries.push(Entry { first: 0L, second: 0L, index: suffixes[position] })
        }

        var k = 1L
        for _round: long in 0L..64L {
            if k >= size { break }
            for position: long in 0L..size {
                let index = entries[position].index
                entries[position].first = rank[index]
                entries[position].second = rank[(index + k) % size]
            }
            sort_by(entries, 0, entry_less)
            var next_rank = 0L
            rank[entries[0L].index] = 0L
            for position: long in 1L..size {
                let before = entries[position - 1L]
                let at = entries[position]
                if before.first != at.first || before.second != at.second {
                    next_rank += 1L
                }
                rank[at.index] = next_rank
            }
            k = k * 2L
        }
        for position: long in 0L..size {
            suffixes[position] = entries[position].index
        }
    }

    for i: long in 0L..size {
        let suffix = suffixes[i]
        if suffix == 0L {
            discard result.transformed.push(input[size - 1L])
            result.original_idx = i
        } else {
            discard result.transformed.push(input[suffix - 1L])
        }
    }
    result
}

fn bwt_inverse(bwt: list<byte, 1000001>, original_idx: long) -> list<byte, 1000001> {
    let size = bwt.count()
    var result: list<byte, 1000001> = list {}
    if size == 0L {
        return result
    }

    var counts: long[256] = fill(0L)
    for i: long in 0L..size {
        counts[bwt[i].to_long()] += 1L
    }
    var positions: long[256] = fill(0L)
    var total = 0L
    for c: long in 0L..256L {
        positions[c] = total
        total += counts[c]
    }

    var next: list<long, 1000001> = list {}
    for _i: long in 0L..size {
        discard next.push(0L)
    }
    var placed: long[256] = fill(0L)
    for i: long in 0L..size {
        let byte_value = bwt[i].to_long()
        next[positions[byte_value] + placed[byte_value]] = i
        placed[byte_value] += 1L
    }

    var index = original_idx
    for _i: long in 0L..size {
        index = next[index]
        discard result.push(bwt[index])
    }
    result
}

fn main(env: Env) {
    let run_mode = is_run_mode(env)
    let size = if run_mode { 1000001L } else { 51L }
    let iterations = if run_mode { 180L } else { 3L }
    let warmup = max(iterations / 5L, 1L)

    let test_data = generate_test_data(size)
    let encoded = bwt_transform(test_data)
    var result = 0L
    var inverted: list<byte, 1000001> = list {}
    for _w: long in 0L..warmup + iterations {
        inverted = bwt_inverse(encoded.transformed, encoded.original_idx)
        result = (result + inverted.count()) % 4294967296L
    }
    if inverted == test_data {
        result = (result + 100000L) % 4294967296L
    }
    print(result)
}
