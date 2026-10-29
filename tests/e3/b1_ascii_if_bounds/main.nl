fn fallback() -> Ascii max 8 {
    "fallback"
}

fn contextual(flag: bool) -> Ascii max 8 {
    if flag { "i8" } else { fallback() }
}

fn show_read(value: Ascii max 8) {
    print(value)
}

fn exercise(flag: bool) {
    print(contextual(flag))
    let local = if flag { "x" } else { "longer" }
    print(local)
    show_read(if flag { "arg" } else { fallback() })
}

fn main() {
    exercise(true)
    exercise(false)
}
