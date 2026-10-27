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

// Go's any, for the values converted code stores in it.
enum GoAny { Nil, Str(Bytes max go_string_max), Int(long), Bool(bool) }

// Go's error: 0 is nil; strconv.ErrRange is 1, strconv.ErrSyntax 2.
type GoError = long

// A rune and its width in bytes, as utf8.DecodeRuneInString returns them.
struct GoRuneSize { r0: int = 0, r1: long = 0L }
// An int64 and an error, as strconv.ParseInt returns them.
struct GoLongError { r0: long = 0L, r1: GoError = 0L }
// Two runes, as utf16.EncodeRune returns them.
struct GoRunePair { r0: int = 0, r1: int = 0 }

fn go_utf8_cont(b: byte) -> bool { b >= 128 && b <= 191 }

// utf8.DecodeRuneInString, with Go's rules: U+FFFD and width 1 for an invalid
// or truncated sequence, width 0 for an empty string.
fn go_utf8_DecodeRuneInString(s: Bytes max go_string_max) -> GoRuneSize {
    let n = s.len()
    if n == 0L { return GoRuneSize { r0: 65533, r1: 0L } }
    let b0 = s[0L]
    if b0 < 128 { return GoRuneSize { r0: (int)(b0), r1: 1L } }
    let bad = GoRuneSize { r0: 65533, r1: 1L }
    if b0 < 194 || b0 > 244 { return bad }
    if n < 2L { return bad }
    let b1 = s[1L]
    if b0 < 224 {
        if !go_utf8_cont(b1) { return bad }
        return GoRuneSize { r0: (((int)(b0) & 31) << 6) | ((int)(b1) & 63), r1: 2L }
    }
    // The second byte's range depends on the first (no overlongs, no surrogates).
    var lo: byte = 128
    var hi: byte = 191
    if b0 == 224 { lo = 160 }
    if b0 == 237 { hi = 159 }
    if b0 == 240 { lo = 144 }
    if b0 == 244 { hi = 143 }
    if b1 < lo || b1 > hi { return bad }
    if n < 3L { return bad }
    let b2 = s[2L]
    if !go_utf8_cont(b2) { return bad }
    if b0 < 240 {
        return GoRuneSize { r0: (((int)(b0) & 15) << 12) | (((int)(b1) & 63) << 6) | ((int)(b2) & 63), r1: 3L }
    }
    if n < 4L { return bad }
    let b3 = s[3L]
    if !go_utf8_cont(b3) { return bad }
    GoRuneSize { r0: (((int)(b0) & 7) << 18) | (((int)(b1) & 63) << 12) | (((int)(b2) & 63) << 6) | ((int)(b3) & 63), r1: 4L }
}

// utf8.DecodeLastRuneInString.
fn go_utf8_DecodeLastRuneInString(s: Bytes max go_string_max) -> GoRuneSize {
    let end = s.len()
    if end == 0L { return GoRuneSize { r0: 65533, r1: 0L } }
    var start = end - 1L
    if s[start] < 128 { return GoRuneSize { r0: (int)(s[start]), r1: 1L } }
    var lim = end - 4L
    if lim < 0L { lim = 0L }
    for step in 0L..4L {
        start -= 1L
        if start < lim { break }
        if !go_utf8_cont(s[start]) { break }
    }
    if start < 0L { start = 0L }
    let decoded = go_utf8_DecodeRuneInString(s.slice(start..end))
    if start + decoded.r1 != end { return GoRuneSize { r0: 65533, r1: 1L } }
    decoded
}

// utf8.RuneLen: -1 for a value that isn't a valid rune.
fn go_utf8_RuneLen(r: int) -> long {
    if r < 0 { return -1L }
    if r < 128 { return 1L }
    if r < 2048 { return 2L }
    if r >= 55296 && r <= 57343 { return -1L }
    if r < 65536 { return 3L }
    if r <= 1114111 { return 4L }
    -1L
}

// string(r): the UTF-8 encoding of r, or of U+FFFD if r isn't a valid rune.
fn go_string_from_rune(rune_in: int) -> Bytes max go_string_max {
    var r = rune_in
    if go_utf8_RuneLen(r) < 0L { r = 65533 }
    var out: Bytes max go_string_max = b""
    if r < 128 {
        out.push(r.fit<byte>().unwrap()).unwrap()
    } else if r < 2048 {
        out.push((192 | (r >> 6)).fit<byte>().unwrap()).unwrap()
        out.push((128 | (r & 63)).fit<byte>().unwrap()).unwrap()
    } else if r < 65536 {
        out.push((224 | (r >> 12)).fit<byte>().unwrap()).unwrap()
        out.push((128 | ((r >> 6) & 63)).fit<byte>().unwrap()).unwrap()
        out.push((128 | (r & 63)).fit<byte>().unwrap()).unwrap()
    } else {
        out.push((240 | (r >> 18)).fit<byte>().unwrap()).unwrap()
        out.push((128 | ((r >> 12) & 63)).fit<byte>().unwrap()).unwrap()
        out.push((128 | ((r >> 6) & 63)).fit<byte>().unwrap()).unwrap()
        out.push((128 | (r & 63)).fit<byte>().unwrap()).unwrap()
    }
    out
}

// utf16.IsSurrogate, DecodeRune, EncodeRune.
fn go_utf16_IsSurrogate(r: int) -> bool { r >= 55296 && r < 57344 }

fn go_utf16_DecodeRune(r1: int, r2: int) -> int {
    if r1 >= 55296 && r1 < 56320 && r2 >= 56320 && r2 < 57344 {
        return (((r1 - 55296) << 10) | (r2 - 56320)) + 65536
    }
    65533
}

fn go_utf16_EncodeRune(r: int) -> GoRunePair {
    if r < 65536 || r > 1114111 { return GoRunePair { r0: 65533, r1: 65533 } }
    let v = r - 65536
    GoRunePair { r0: 55296 + ((v >> 10) & 1023), r1: 56320 + (v & 1023) }
}

// strings.Builder, held as Bytes.
fn go_strings_Builder_WriteString(b: grow Bytes max go_string_max, s: Bytes max go_string_max) {
    b.try_append(s).unwrap()
}
fn go_strings_Builder_WriteByte(b: grow Bytes max go_string_max, c: byte) {
    b.push(c).unwrap()
}
fn go_strings_Builder_WriteRune(b: grow Bytes max go_string_max, r: int) {
    b.try_append(go_string_from_rune(r)).unwrap()
}
fn go_strings_Builder_Grow(b: grow Bytes max go_string_max, n: long) {}
fn go_strings_Builder_Reset(b: write Bytes max go_string_max) { b = b"" }
fn go_strings_Builder_String(b: Bytes max go_string_max) -> Bytes max go_string_max { b }
fn go_strings_Builder_Len(b: Bytes max go_string_max) -> long { b.len() }

// strings.TrimSuffix, TrimPrefix.
fn go_strings_TrimSuffix(s: Bytes max go_string_max, suffix: Bytes max go_string_max) -> Bytes max go_string_max {
    if go_strings_HasSuffix(s, suffix) { return s.slice(0L..(s.len() - suffix.len())) }
    s
}
fn go_strings_TrimPrefix(s: Bytes max go_string_max, prefix: Bytes max go_string_max) -> Bytes max go_string_max {
    if go_strings_HasPrefix(s, prefix) { return s.slice(prefix.len()..s.len()) }
    s
}

fn go_digit_value(c: byte) -> long {
    if c >= 48 && c <= 57 { return (long)(c) - 48L }
    if c >= 97 && c <= 122 { return (long)(c) - 87L }
    if c >= 65 && c <= 90 { return (long)(c) - 55L }
    99L
}

// strconv.ParseInt for an explicit base (2 to 36) and bit size: ErrSyntax for
// a bad digit, ErrRange with the clamped value when it doesn't fit.
fn go_strconv_ParseInt(s: Bytes max go_string_max, base: long, bit_size: long) -> GoLongError {
    if s.len() == 0L { return GoLongError { r0: 0L, r1: 2L } }
    var i = 0L
    var negative = false
    if s[0L] == 43 || s[0L] == 45 {
        negative = s[0L] == 45
        i = 1L
    }
    if i >= s.len() { return GoLongError { r0: 0L, r1: 2L } }
    var bits = bit_size
    if bits == 0L { bits = 64L }
    // The largest positive value: 2^(bits-1) - 1.
    var max_positive = 9223372036854775807L
    if bits < 64L {
        max_positive = 1L
        for k in 0L..(bits - 1L) { max_positive = max_positive * 2L }
        max_positive = max_positive - 1L
    }
    let min_negative = -max_positive - 1L
    // A negative value accumulates below zero, so the most negative one fits.
    var value = 0L
    var over = false
    for step in 0L..s.len() {
        if i >= s.len() { break }
        let d = go_digit_value(s[i])
        if d >= base { return GoLongError { r0: 0L, r1: 2L } }
        if !over {
            if negative {
                if value < (min_negative + d) / base { over = true } else { value = value * base - d }
            } else {
                if value > (max_positive - d) / base { over = true } else { value = value * base + d }
            }
        }
        i += 1L
    }
    if over {
        if negative { return GoLongError { r0: min_negative, r1: 1L } }
        return GoLongError { r0: max_positive, r1: 1L }
    }
    GoLongError { r0: value, r1: 0L }
}

fn go_strconv_Atoi(s: Bytes max go_string_max) -> GoLongError { go_strconv_ParseInt(s, 10L, 64L) }

// strconv.FormatInt, lowercase digits; strconv.Itoa.
fn go_strconv_FormatInt(value: long, base: long) -> Bytes max go_string_max {
    if value == 0L { return b"0" }
    let digit_chars = b"0123456789abcdefghijklmnopqrstuvwxyz"
    var digits: Bytes max 72 = b""
    var rest = value
    for step in 0L..72L {
        if rest == 0L { break }
        var d = rest % base
        if d < 0L { d = -d }
        digits.push(digit_chars[d]).unwrap()
        rest = rest / base
    }
    var out: Bytes max go_string_max = b""
    if value < 0L { out.push(45).unwrap() }
    for k in 0L..digits.len() { out.push(digits[digits.len() - 1L - k]).unwrap() }
    out
}

fn go_strconv_Itoa(value: long) -> Bytes max go_string_max { go_strconv_FormatInt(value, 10L) }

fn go_ascii_upper(s: Bytes max go_string_max) -> Bytes max go_string_max {
    var out: Bytes max go_string_max = b""
    for k in 0L..s.len() {
        let c = s[k]
        if c >= 97 && c <= 122 { out.push(c - 32).unwrap() } else { out.push(c).unwrap() }
    }
    out
}

// Left-pads s to width with the byte pad (fmt's %0Nx and %Nd).
fn go_pad_left(s: Bytes max go_string_max, width: long, pad: byte) -> Bytes max go_string_max {
    var out: Bytes max go_string_max = b""
    for k in s.len()..width { out.push(pad).unwrap() }
    out.try_append(s).unwrap()
    out
}

// unicode.RangeTable and unicode.Is. Go searches short tables linearly and long
// ones by halving; both give the same answer on sorted ranges, so this halves.
struct GoRange { lo: int = 0, hi: int = 0, stride: int = 1 }
struct GoRangeTable {
    r16: list<GoRange, 512> = list {}
    r32: list<GoRange, 512> = list {}
    latin_offset: long = 0L
}

fn go_unicode_in_ranges(ranges: list<GoRange, 512>, r: int) -> bool {
    var lo: long = 0L
    var hi: long = ranges.count()
    for step in 0L..64L {
        if lo >= hi { break }
        let m = lo + (hi - lo) / 2L
        let range = ranges[m]
        if range.lo <= r && r <= range.hi {
            return range.stride == 1 || (r - range.lo) % range.stride == 0
        }
        if r < range.lo { hi = m } else { lo = m + 1L }
    }
    false
}

fn go_unicode_Is(table: GoRangeTable, r: int) -> bool {
    if r < 0 { return false }
    let n16 = table.r16.count()
    if n16 > 0L && r <= table.r16[n16 - 1L].hi { return go_unicode_in_ranges(table.r16, r) }
    if table.r32.count() > 0L && r >= table.r32[0L].lo { return go_unicode_in_ranges(table.r32, r) }
    false
}

// strings.Join
fn go_strings_Join(parts: list<Bytes max go_string_max, go_slice_max>, sep: Bytes max go_string_max) -> Bytes max go_string_max {
    var out: Bytes max go_string_max = b""
    for part, index in parts {
        if index > 0L { out.try_append(sep).unwrap() }
        out.try_append(part).unwrap()
    }
    out
}
