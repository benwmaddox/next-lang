fn label(i: int 0..=499) -> Ascii max 60 {
    ascii_upper("row") + str(i)
}

fn line(i: int 0..=499) -> Ascii max 80 {
    let name = label(i)
    name + ": " + str(i * 7)
}

fn render(n: int 0..=500) -> Ascii max 40000 {
    var out: Ascii max 40000 = Ascii.empty()
    for i in 0..n { out += line(i) }
    out
}

fn one(i: int 0..=2) -> Ascii max 1 { str(i) }

fn via_callback(callback: fn(int 0..=2) -> Ascii max 3, i: int 0..=2) -> Ascii max 3 {
    callback(i)
}

fn interleave() {
    var first: Ascii max 9 = Ascii.empty()
    var second: Ascii max 3 = Ascii.empty()
    var third: Ascii max 9 = Ascii.empty()
    for i in 0..3 {
        first += via_callback(one, i)
        second += one(i)
        third += via_callback(one, i)
    }
    print(first)
    print(second)
    print(third)
}

fn echo(value: Ascii max 16) -> Ascii max 1 {
    if value.len() == 0 { "!" } else { "?" }
}

fn overlap_fallback() -> Ascii max 16 {
    var out: Ascii max 16 = "a"
    out += echo(out)
    out
}

fn partial(raw: Ascii max 4) -> Result<Ascii max 8, Full> {
    var out: Ascii max 8 = Ascii.empty()
    out += "P"
    if raw == "bad" { return err(Full) }
    out += raw
    ok(out)
}

fn append_partial(buf: grow Ascii max 20, raw: Ascii max 4) -> Result<(), Full> {
    buf.try_append(partial(raw)?)
}

fn collect_partial(raw: Ascii max 4) -> Result<Ascii max 16, Full> {
    var out: Ascii max 16 = Ascii.empty()
    out += "S"
    out += partial(raw)?
    out += "E"
    ok(out)
}

fn append_origin(buf: grow Ascii max 8, raw: Ascii max 4) -> Result<int, Full> {
    match buf.try_append(partial(raw)?) {
        ok(_) => ok(1),
        err(Full) => ok(2)
    }
}

fn field(raw: Ascii max 4) -> Result<Ascii max 8, Full> {
    if raw == "bad" { err(Full) } else { ok("P" + raw) }
}

fn narrow_field(raw: Ascii max 4) -> Result<Ascii max 4, Full> {
    if raw == "bad" { return err(Full) }
    ok(raw)
}

fn matched_field(raw: Ascii max 4) -> Result<Ascii max 8, Full> {
    match raw == "bad" {
        true => err(Full),
        false => ok("M" + raw)
    }
}

fn append_callback(
    callback: fn(Ascii max 4) -> Result<Ascii max 8, Full>,
    buf: grow Ascii max 20,
    raw: Ascii max 4
) -> Result<(), Full> {
    buf.try_append(callback(raw)?)
}

fn log_callback(
    callback: fn(Ascii max 4) -> Result<Ascii max 8, Full>,
    buf: grow Ascii max 20,
    raw: Ascii max 4
) -> Result<(), Full> {
    match callback(raw) {
        ok(f) => buf.try_append(f),
        err(_) => ok(())
    }
}

fn log_line(buf: grow Ascii max 20, raw: Ascii max 4) -> Result<(), Full> {
    match field(raw) {
        ok(f) => buf.try_append(f),
        err(_) => ok(())
    }
}

fn inner_piece() -> Ascii max 3 { "xyz" }

fn nested_capacity(buf: grow Ascii max 4) -> Result<(), Full> {
    buf.try_append(inner_piece() + "!")
}

fn exact_piece() -> Ascii max 4 { "wxyz" }

fn exact_append() -> Ascii max 8 {
    var out: Ascii max 8 = "abcd"
    out += exact_piece()
    out
}

fn merge(left: Ascii max 16, right: Ascii max 1) -> Ascii max 16 {
    match left.fit<Ascii max 15>() {
        some(short) => short + right,
        none => left
    }
}

fn merge_in_loop() -> Ascii max 16 {
    var acc: Ascii max 16 = "a"
    let piece: Ascii max 1 = "x"
    for i in 0..2 { acc = merge(acc, piece) }
    acc
}

fn million_bytes() -> long {
    var out: Ascii max 1000000 = Ascii.empty()
    for i: long in 0L..1000000L {
        let piece: Ascii max 1 = "x"
        out += piece
    }
    out.len()
}

fn main() {
    print(render(3))
    interleave()
    print(overlap_fallback())
    print(merge_in_loop())
    print(exact_append())
    var exact_try: Ascii max 4 = "ab"
    print(exact_try.try_append("cd").is_ok())
    print(exact_try)
    print(collect_partial("bad").is_err())
    print(collect_partial("ok").unwrap())

    var recovered: Ascii max 20 = "seed"
    print(append_partial(recovered, "bad").is_err())
    print(recovered)
    print(append_partial(recovered, "ok").is_ok())
    print(recovered)

    var tight: Ascii max 8 = "123456"
    print(append_origin(tight, "ok"))
    print(append_origin(tight, "bad"))
    print(tight)

    var logged: Ascii max 20 = "log:"
    print(log_line(logged, "bad").is_ok())
    print(logged)
    print(log_line(logged, "ok").is_ok())
    print(logged)
    var almost_full: Ascii max 20 = "1234567890123456"
    print(log_line(almost_full, "ok").is_ok())
    print(almost_full)

    var callback_output: Ascii max 20 = "callback:"
    print(append_callback(narrow_field, callback_output, "ok").is_ok())
    print(callback_output)
    print(log_callback(narrow_field, callback_output, "bad").is_ok())
    print(callback_output)
    print(log_callback(matched_field, callback_output, "ok").is_ok())
    print(callback_output)
    print(log_callback(matched_field, callback_output, "bad").is_ok())
    print(callback_output)
    var wide_callback_output: Ascii max 20 = "wide:"
    print(append_callback(field, wide_callback_output, "ok").is_ok())
    print(wide_callback_output)

    var nested: Ascii max 4 = "a"
    print(nested_capacity(nested).is_err())
    print(nested)
    print(nested.try_append("x").is_ok())
    print(nested)
    print(million_bytes())
}
