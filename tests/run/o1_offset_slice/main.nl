struct Pair { x: long, y: long }

fn read_sum(values: list<long, 32767>) -> long {
    var sum = 0L
    for value in values { sum += value }
    sum
}

fn bump(values: write list<long, 32767>) {
    values[1] += 7L
}

fn make_copy(values: list<long, 32767>) -> list<long, 32767> {
    values
}

fn grow_in_callee(values: write list<long, 32767>, out: grow Ascii max 262120) {
    let scratch: list<long, 200000> = list {}
    print(scratch.count())
    values[2] += 3L
    let appended = out.try_append(str(values[2]))
}

fn main() {
    var values: list<long, 32767> = list {}
    discard values.push(10L)
    discard values.push(20L)
    discard values.push(30L)
    bump(values)
    let copied = make_copy(values)
    let total = read_sum(copied)

    var pairs: list<Pair, 10000> = list {}
    discard pairs.push(Pair { x: 2L, y: 5L })
    discard pairs.push(Pair { x: 3L, y: 7L })
    for pair in pairs { pair.y += pair.x }
    for index in 0L..2L { pairs[index].x += 1L }

    var output: Ascii max 262120 = Ascii.empty()
    output += "v="
    for index in 0..26210 { output += "1234567890" }
    var reserve: list<long, 12766> = list {}
    let append = output.try_append(str(values[2]))
    for index in 0..2 { grow_in_callee(values, output) }
    var message: Ascii max 32 = Ascii.empty()
    message += "done=" + str(total)
    print(values.count())
    print(values[1])
    print(values[2])
    print(read_sum(values))
    print(pairs[0].x)
    print(pairs[0].y)
    print(output.len())
    print(append.is_ok())
    print(message.len())
    print(message)
}
