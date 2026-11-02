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
}
