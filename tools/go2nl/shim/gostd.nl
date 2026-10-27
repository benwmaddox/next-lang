// go2nl's shim: hand-written next-lang for the Go runtime and standard-library
// pieces that converted code calls. It is not generated, and its lines are
// counted apart from converted code. go_string_max comes from the conversion's
// config (go2nl_config.nl).

// Go's narrow integer types, as ranges. Go wraps on overflow; these fail the
// program instead, so a difference shows up as a failure, never a wrong value.
type GoI8 = int -128..=127
type GoI16 = int -32768..=32767
type GoU16 = int 0..=65535
type GoU32 = long 0..=4294967295

// a + b for Go strings. Past go_string_max bytes the program fails.
fn go_concat(a: Bytes max go_string_max, b: Bytes max go_string_max) -> Bytes max go_string_max {
    var joined: Bytes max go_string_max = a
    joined.try_append(b).unwrap()
    joined
}

// Go's panic: the program stops with a failure.
fn go_panic() {
    let nothing: Option<long> = none
    let unreachable_value = nothing.unwrap()
}

// strings.HasPrefix
fn go_strings_HasPrefix(s: Bytes max go_string_max, prefix: Bytes max go_string_max) -> bool {
    if prefix.len() > s.len() { return false }
    s.slice(0L..prefix.len()) == prefix
}

// strings.HasSuffix
fn go_strings_HasSuffix(s: Bytes max go_string_max, suffix: Bytes max go_string_max) -> bool {
    if suffix.len() > s.len() { return false }
    s.slice((s.len() - suffix.len())..s.len()) == suffix
}

// strings.IndexByte
fn go_strings_IndexByte(s: Bytes max go_string_max, c: byte) -> long {
    for index in 0L..s.len() {
        if s[index] == c { return index }
    }
    -1L
}

// strings.Repeat, bounded by go_string_max.
fn go_strings_Repeat(s: Bytes max go_string_max, count: long) -> Bytes max go_string_max {
    var out: Bytes max go_string_max = b""
    for i in 0L..count { out.try_append(s).unwrap() }
    out
}

// strconv.Itoa / FormatInt base 10.
fn go_strconv_Itoa(value: long) -> Bytes max go_string_max {
    if value == 0L { return b"0" }
    var digits: Bytes max 24 = b""
    var rest = value
    let negative = value < 0L
    for step in 0L..24L {
        if rest == 0L { break }
        var digit = rest % 10L
        if digit < 0L { digit = -digit }
        digits.push(((int)(digit + 48L)).fit<byte>().unwrap()).unwrap()
        rest = rest / 10L
    }
    var out: Bytes max go_string_max = b""
    if negative { out.push(45).unwrap() }
    for k in 0L..digits.len() { out.push(digits[digits.len() - 1L - k]).unwrap() }
    out
}
