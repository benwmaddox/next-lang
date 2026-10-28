struct ConstantRecord { value: long = 0L }

const FORWARD: long = BASE + 5L
const QUOTIENT: long = -7L / 2L
const REMAINDER: long = -7L % 2L
const MIN_REMAINDER: long = MINIMUM % -1L

fn main() {
    print(FORWARD)
    print(DOUBLE_BASE)
    print(QUOTIENT)
    print(REMAINDER)
    print(MIN_REMAINDER)
    print(MINIMUM)
    print(MAXIMUM)
    let BASE: long = 3L
    print(BASE)
    let statically_sized: long[BASE] = fill(K)
    print(statically_sized.len())
    if FORWARD == 15L { print(1L) } else { print(0L) }
    var items: list<int, CAPACITY> = list {}
    discard items.push(1)
    discard items.push(2)
    discard items.push(3)
    print(items.count())

    let singleton: long[1] = [K]
    print(singleton[ZERO_INDEX])
    let repeated: long[3] = fill(K)
    print(repeated[INDEX])
    var inserted: list<long, 3> = list {}
    discard inserted.push(K)
    discard inserted.insert(INDEX, K)
    print(inserted[INDEX])
    let word: Ascii max 4 = "word"
    print(word.slice(SLICE_START..SLICE_END))
    let unicode: Text max 4 bytes max 5 = "wörd"
    print(unicode.slice(SLICE_START..SLICE_END))

    var assigned: long[2] = fill(0L)
    assigned[INDEX] = K
    print(assigned[INDEX])
    var removed: list<long, 2> = list {}
    discard removed.push(K)
    discard removed.push(9L)
    print(removed.remove(ZERO_INDEX))
    var records: ConstantRecord[2]
    records[INDEX].value = K
    print(records[INDEX].value)
    print(match 0L { 0L => K, _ => 0L })
}
