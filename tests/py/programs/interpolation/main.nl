// $"text {hole} text": numbers and text in the holes, {{ and }} for braces; the result is Ascii with the summed bound.
fn describe(id: long, name: Ascii max 8, score: int) -> Ascii max 64 {
    $"user {id}: {name} scored {score}"
}

fn main(env: Env) {
    let id = 42L
    print($"{id}")
    print($"id={id}!")
    print(describe(7L, "ada", -3))
    print($"{{braces}} and {id}{id}")
    print($"{id + 1L} {(id * 2L)}")
    print($"tab\there \"quoted\" {id}")
    print($"")
    print($"plain")
    let label: Ascii max 8 = "x"
    print($"[{label}][{label}]")
    print($"{describe(1L, "bob", 2)}".len())
    var total = 0L
    for index in 0L..3L {
        print($"row {index}: {total}")
        total += index
    }
    builders(env)
}

struct Row {
    name: Bytes max 8
    live: bool
}

fn line(row: Row, id: long) -> Bytes max 64 {
    $"#{id} {row.name} live={row.live}"
}

fn builders(env: Env) {
    let id_text: Ascii max 8 = "ab"
    var row = Row { name: Bytes.empty(), live: true }
    discard row.name.try_append(b"ada")
    let flag = false
    var out: Bytes max 40 = Bytes.empty()
    // appended straight into the builder
    discard out.try_append($"id={7L} name={row.name} live={row.live};")
    discard out.try_append($"flag={flag}\n")
    match env.out.write(out) { ok(_) => (), err(_) => () }
    print(out.count())
    // a builder with too little room: the append fails and changes nothing
    var small: Bytes max 12 = Bytes.empty()
    discard small.try_append(b"abcd")
    match small.try_append($"{row.name} and {123456L}") {
        ok(_) => print("appended"),
        err(_) => print("full"),
    }
    print(small.count())
    // room for the value but not for its largest possible form: the exact length decides
    var tight: Bytes max 24 = Bytes.empty()
    match tight.try_append($"n={5L}") {
        ok(_) => print(tight.count()),
        err(_) => print("full"),
    }
    // the largest value would not fit in 8 bytes, the actual one does: the exact length decides
    var tiny: Bytes max 8 = Bytes.empty()
    match tiny.try_append($"n={5L}") {
        ok(_) => print(tiny.count()),
        err(_) => print("full"),
    }
    let made = line(row, 3L)
    match env.out.write(made) { ok(_) => (), err(_) => () }
    print(made.count())
    // formats: {n:8} width, {n:08} zero-padded, {n:x} hexadecimal, {n:b} binary, {text:8} width
    var cells: Bytes max 80 = Bytes.empty()
    discard cells.try_append($"[{42L:6}][{42L:06}][{-42L:06}][{255L:x}][{5L:b}][{row.name:6}][{row.name:2}]\n")
    match env.out.write(cells) { ok(_) => (), err(_) => () }
    print($"{3:4}|{id_text:5}|{9L:x}")
    var ascii: Ascii max 40 = ""
    discard ascii.try_append($"{flag}/{true}")
    print(ascii)
}
