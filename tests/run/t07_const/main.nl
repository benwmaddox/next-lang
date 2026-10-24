struct Stone { value: int }

fn measure() -> long {
    var stones: pool<Stone, 2> = pool {}
    let first = stones.add(Stone { value: 40 }).unwrap()
    let original = stones.get(first).unwrap()
    let removed = stones.remove(first)
    let stale = stones.get(first).is_none()
    let next = stones.add(Stone { value: 42 }).unwrap()
    if stale {
        stones.count() + original.value.to_long() + stones.get(next).unwrap().value.to_long()
    } else {
        0L
    }
}

const MEASURED: long = measure()

fn measure_loop() -> long {
    var stones: pool<Stone, 3> = pool {}
    discard stones.add(Stone { value: 2 })
    discard stones.add(Stone { value: 3 })
    discard stones.add(Stone { value: 4 })
    var total = 0L
    for stone, id in stones {
        if stones.contains(id) {
            total += stone.value.to_long()
        }
    }
    total
}

const LOOP_MEASURED: long = measure_loop()

fn main() {
    print(MEASURED)
    print(measure())
    print(LOOP_MEASURED)
    print(measure_loop())
}
