enum Failure { Bad }
type Tiny = Ascii max 2

fn identity(value: Ascii max 80) -> Ascii max 80 { value }

fn short_word() -> Ascii max 4 { "word" }

fn concat_function_result() -> Ascii max 5 { short_word() + "!" }

fn concat_function_value(callback: fn() -> Ascii max 4) -> Ascii max 5 {
    callback() + "!"
}

fn small_integer_text(value: int 0..=999999) -> Ascii max 6 { str(value) }

fn returned_local() -> Ascii max 8 {
    let local: Ascii max 8 = "local"
    let measured_length = local.len()
    local
}

fn append_leaf(out: grow Ascii max 8) {
    out.try_append("!").unwrap()
}

fn append_middle(out: grow Ascii max 8) {
    append_leaf(out)
}

fn clear_text(out: write Ascii max 8) {
    out = Ascii.empty()
}

fn append_result(out: grow Ascii max 8) -> Ascii max 8 {
    append_middle(out)
    out
}

fn make_option() -> Option<Ascii max 8> {
    let local: Ascii max 8 = "option"
    some(local)
}

fn echo_option(value: Option<Ascii max 8>) -> Option<Ascii max 8> { value }

fn make_result() -> Result<Ascii max 8, Failure> { ok("result") }

fn echo_result(value: Result<Ascii max 8, Failure>) -> Result<Ascii max 8, Failure> { value }

fn make_ascii_error() -> Result<Ascii max 8, Ascii max 8> { err("failure") }

fn echo_ascii_result(
    value: Result<Ascii max 8, Ascii max 8>
) -> Result<Ascii max 8, Ascii max 8> { value }

fn append_loop() -> long {
    var total: long = 0L
    for i: long in 0L..8L {
        var output: Ascii max 8 = Ascii.empty()
        output += "x"
        total += output.len()
    }
    total
}

fn main() {
    let input: Ascii max 80 = "hi"
    print(identity(input))
    print(input)
    print(returned_local())
    print(concat_function_result())
    print(concat_function_value(short_word))

    let source: Ascii max 8 = "a"
    var copied: Ascii max 8 = source
    var moved: Ascii max 8 = take source
    let live_above: Ascii max 8 = "z"
    copied += "b"
    moved += "c"
    print(copied)
    print(moved)
    print(live_above)

    var joined: Ascii max 4 = Ascii.empty()
    joined += "ab"
    joined += "cd"
    print(joined)
    var duplicate: Ascii max 4 = "xy"
    duplicate = duplicate + duplicate
    print(duplicate)

    var full: Ascii max 4 = "abcd"
    let full_result = full.try_append("!")
    let full_result_again = full.try_append("!")
    print(full_result.is_err())
    print(full_result_again.is_err())
    print(full.len())
    print(full)
    let fit_result = "abc".fit<Tiny>()
    print(fit_result.is_none())
    let fit_some = "ok".fit<Tiny>()
    print(fit_some.is_some())
    let wider: Ascii max 8 = "ok"
    let casted: Ascii max 2 = (Ascii max 2)(wider)
    print(casted)

    print(str(-2147483648))
    print(str(-9223372036854775808L))
    print(small_integer_text(999999))
    print(ascii_upper("aBc\0z"))
    print("a\0b" == "a\0b")
    print("a\0b" < "a\0c")

    var grown: Ascii max 8 = "x"
    print(append_result(grown))
    print(grown)

    var cleared: Ascii max 8 = "clear"
    clear_text(cleared)
    print(cleared.len())

    let maybe = make_option()
    let maybe_copy = echo_option(maybe)
    match maybe_copy {
        some(text) => print(text),
        none => print("none")
    }
    let absent: Option<Ascii max 8> = none
    print(echo_option(absent).is_none())
    let result = make_result()
    let result_copy = echo_result(result)
    match result_copy {
        ok(text) => print(text),
        err(_) => print("bad")
    }
    let ascii_error = echo_ascii_result(make_ascii_error())
    match ascii_error {
        ok(text) => print(text),
        err(text) => print(text)
    }

    var first: Ascii max 16 = Ascii.empty()
    var second: Ascii max 16 = Ascii.empty()
    var third: Ascii max 16 = Ascii.empty()
    first += "A"
    second += "B"
    third += "C"
    first += "1"
    second += "2"
    third += "3"
    print(first)
    print(second)
    print(third)
    print(append_loop())
}
