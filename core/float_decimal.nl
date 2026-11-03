// Decimal text for double and float, in plain next-lang on exact integers: no floating-point instruction runs.
//
// nl_float_shortest(bits, kind, scratch, out) writes the SHORTEST decimal text that reads back as the same value
// (Steele and White / Burger and Dybvig free-format printing on big integers) in the JavaScript Number-to-string
// layout, and returns its length (at most 25 bytes):
//   plain digits when 1e-6 <= |x| < 1e21 ("0.000001", "123.456", "100000000000000000000"), else "1.5e+21" or "1e-7";
//   whole numbers have no ".0"; zero, and negative zero too, is "0"; infinities are "Infinity" and "-Infinity".
// nl_float_parse(data, count, scratch) reads decimal text and returns the bits of the nearest double (ties to even,
// subnormals, overflow to infinity), or the quiet-NaN pattern when the text is malformed.
//
// bits is the IEEE pattern of the value (kind 0: double; kind 1: float, in the low 32 bits). scratch is caller
// memory: 2112 bytes for printing, 3648 for parsing. Big integers are little-endian limbs of 28 bits in 8-byte slots
// (slot 0 holds the limb count), so every product of two limbs, or of a limb and a multiplier up to 10^9, fits a long.
// The sizes below are bounds, not safety margins: printing needs at most 1200 bits, parsing at most 4000.
//
// Not fast: about 10 to 30 microseconds per call. Ryu (printing) and Eisel-Lemire (parsing) are the planned fast
// paths and need unsigned 64-bit multiplication; this code stays as their exact fallback and oracle.

fn nl_big_get(a: sys.Addr, index: long) -> long { sys.load64(a, 8L + index * 8L) }
fn nl_big_put(a: sys.Addr, index: long, value: long) { sys.store64(a, 8L + index * 8L, value) }
fn nl_big_len(a: sys.Addr) -> long { sys.load64(a, 0L) }
fn nl_big_set_len(a: sys.Addr, count: long) { sys.store64(a, 0L, count) }
fn nl_big_at(scratch: sys.Addr, index: long, stride: long) -> sys.Addr { sys.offset(scratch, index * stride) }

// a = value, for 0 <= value < 2^62
fn nl_big_from(a: sys.Addr, value: long) {
    var count = 0L
    var rest = value
    for step in 0L..3L {
        if rest == 0L { break }
        nl_big_put(a, count, rest & 268435455L)
        rest = rest >> 28
        count += 1L
    }
    nl_big_set_len(a, count)
}

fn nl_big_copy(target: sys.Addr, source: sys.Addr) {
    let count = nl_big_len(source)
    for index in 0L..count { nl_big_put(target, index, nl_big_get(source, index)) }
    nl_big_set_len(target, count)
}

fn nl_big_trim(a: sys.Addr) {
    var count = nl_big_len(a)
    for step in 0L..200L {
        if count == 0L || nl_big_get(a, count - 1L) != 0L { break }
        count -= 1L
    }
    nl_big_set_len(a, count)
}

// a = a * multiplier, for 0 <= multiplier <= 10^9
fn nl_big_mul_small(a: sys.Addr, multiplier: long) {
    let count = nl_big_len(a)
    var carry = 0L
    for index in 0L..count {
        let total = nl_big_get(a, index) * multiplier + carry
        nl_big_put(a, index, total & 268435455L)
        carry = total >> 28
    }
    var length = count
    for step in 0L..3L {
        if carry == 0L { break }
        nl_big_put(a, length, carry & 268435455L)
        carry = carry >> 28
        length += 1L
    }
    nl_big_set_len(a, length)
}

// a = a + value, for 0 <= value < 2^40
fn nl_big_add_small(a: sys.Addr, value: long) {
    var length = nl_big_len(a)
    var carry = value
    var index = 0L
    for step in 0L..200L {
        if carry == 0L { break }
        if index < length {
            let total = nl_big_get(a, index) + carry
            nl_big_put(a, index, total & 268435455L)
            carry = total >> 28
        } else {
            nl_big_put(a, index, carry & 268435455L)
            carry = carry >> 28
            length += 1L
        }
        index += 1L
    }
    nl_big_set_len(a, length)
}

fn nl_big_shl(a: sys.Addr, bits: long) {
    let count = nl_big_len(a)
    if count == 0L || bits == 0L { return }
    let whole = bits / 28L
    let part = bits % 28L
    let top = nl_big_get(a, count - 1L) >> (28L - part)
    if top != 0L { nl_big_put(a, count + whole, top) }
    for step in 0L..count {
        let index = count - 1L - step
        let high = nl_big_get(a, index)
        let low = if index > 0L { nl_big_get(a, index - 1L) } else { 0L }
        nl_big_put(a, index + whole, ((high << part) & 268435455L) | (low >> (28L - part)))
    }
    for index in 0L..whole { nl_big_put(a, index, 0L) }
    nl_big_set_len(a, count + whole + if top != 0L { 1L } else { 0L })
}

fn nl_big_shr1(a: sys.Addr) {
    let count = nl_big_len(a)
    for index in 0L..count {
        let above = if index + 1L < count { nl_big_get(a, index + 1L) & 1L } else { 0L }
        nl_big_put(a, index, (nl_big_get(a, index) >> 1) | (above << 27))
    }
    nl_big_trim(a)
}

fn nl_big_cmp(a: sys.Addr, b: sys.Addr) -> long {
    let count = nl_big_len(a)
    let other = nl_big_len(b)
    if count != other { return if count < other { -1L } else { 1L } }
    for step in 0L..count {
        let index = count - 1L - step
        let x = nl_big_get(a, index)
        let y = nl_big_get(b, index)
        if x != y { return if x < y { -1L } else { 1L } }
    }
    0L
}

// a = a + b
fn nl_big_add(a: sys.Addr, b: sys.Addr) {
    let count = nl_big_len(a)
    let other = nl_big_len(b)
    let longest = if count > other { count } else { other }
    var carry = 0L
    for index in 0L..longest {
        let x = if index < count { nl_big_get(a, index) } else { 0L }
        let y = if index < other { nl_big_get(b, index) } else { 0L }
        let total = x + y + carry
        nl_big_put(a, index, total & 268435455L)
        carry = total >> 28
    }
    var length = longest
    if carry != 0L {
        nl_big_put(a, longest, carry)
        length += 1L
    }
    nl_big_set_len(a, length)
}

// a = a - b, for a >= b
fn nl_big_sub(a: sys.Addr, b: sys.Addr) {
    let count = nl_big_len(a)
    let other = nl_big_len(b)
    var borrow = 0L
    for index in 0L..count {
        let y = if index < other { nl_big_get(b, index) } else { 0L }
        var total = nl_big_get(a, index) - y - borrow
        if total < 0L {
            total += 268435456L
            borrow = 1L
        } else { borrow = 0L }
        nl_big_put(a, index, total)
    }
    nl_big_trim(a)
}

fn nl_big_pow10_small(power: long) -> long {
    var result = 1L
    for step in 0L..power { result = result * 10L }
    result
}

// a = a * 10^power
fn nl_big_mul_pow10(a: sys.Addr, power: long) {
    var remaining = power
    for step in 0L..200L {
        if remaining < 9L { break }
        nl_big_mul_small(a, 1000000000L)
        remaining -= 9L
    }
    nl_big_mul_small(a, nl_big_pow10_small(remaining))
}

fn nl_big_bit_length(a: sys.Addr) -> long {
    let count = nl_big_len(a)
    if count == 0L { return 0L }
    var top = nl_big_get(a, count - 1L)
    var bits = 0L
    for step in 0L..29L {
        if top == 0L { break }
        bits += 1L
        top = top >> 1
    }
    (count - 1L) * 28L + bits
}

fn nl_float_bit_length(value: long) -> long {
    var rest = value
    var bits = 0L
    for step in 0L..63L {
        if rest == 0L { break }
        bits += 1L
        rest = rest >> 1
    }
    bits
}

fn nl_float_put(out: sys.Addr, position: long, character: long) { sys.store8(out, position, (int)character) }

fn nl_float_put_infinity(out: sys.Addr, negative: bool) -> long {
    var position = 0L
    if negative {
        nl_float_put(out, 0L, 45L)
        position = 1L
    }
    nl_float_put(out, position, 73L)
    nl_float_put(out, position + 1L, 110L)
    nl_float_put(out, position + 2L, 102L)
    nl_float_put(out, position + 3L, 105L)
    nl_float_put(out, position + 4L, 110L)
    nl_float_put(out, position + 5L, 105L)
    nl_float_put(out, position + 6L, 116L)
    nl_float_put(out, position + 7L, 121L)
    position + 8L
}

// The digits d[0..count) with the decimal point after k of them (value = 0.d1d2... * 10^k) in JavaScript layout.
fn nl_float_layout(digits: sys.Addr, count: long, k: long, negative: bool, out: sys.Addr) -> long {
    var position = 0L
    if negative {
        nl_float_put(out, 0L, 45L)
        position = 1L
    }
    if count <= k && k <= 21L {
        for index in 0L..count { nl_float_put(out, position + index, 48L + (long)sys.load8(digits, index)) }
        position += count
        for index in 0L..(k - count) { nl_float_put(out, position + index, 48L) }
        position += k - count
    } else if k > 0L && k <= 21L {
        for index in 0L..k { nl_float_put(out, position + index, 48L + (long)sys.load8(digits, index)) }
        nl_float_put(out, position + k, 46L)
        for index in k..count { nl_float_put(out, position + 1L + index, 48L + (long)sys.load8(digits, index)) }
        position += count + 1L
    } else if k > -6L && k <= 0L {
        nl_float_put(out, position, 48L)
        nl_float_put(out, position + 1L, 46L)
        position += 2L
        for index in 0L..(0L - k) { nl_float_put(out, position + index, 48L) }
        position += 0L - k
        for index in 0L..count { nl_float_put(out, position + index, 48L + (long)sys.load8(digits, index)) }
        position += count
    } else {
        nl_float_put(out, position, 48L + (long)sys.load8(digits, 0L))
        position += 1L
        if count > 1L {
            nl_float_put(out, position, 46L)
            for index in 1L..count { nl_float_put(out, position + index, 48L + (long)sys.load8(digits, index)) }
            position += count
        }
        nl_float_put(out, position, 101L)
        let exponent = k - 1L
        nl_float_put(out, position + 1L, if exponent < 0L { 45L } else { 43L })
        position += 2L
        let magnitude = if exponent < 0L { 0L - exponent } else { exponent }
        if magnitude >= 100L {
            nl_float_put(out, position, 48L + magnitude / 100L)
            position += 1L
        }
        if magnitude >= 10L {
            nl_float_put(out, position, 48L + (magnitude / 10L) % 10L)
            position += 1L
        }
        nl_float_put(out, position, 48L + magnitude % 10L)
        position += 1L
    }
    position
}

// The shortest text of the double (kind 0) or float (kind 1) with the given bits. scratch: 2112 bytes.
fn nl_float_shortest(bits: long, kind: long, scratch: sys.Addr, out: sys.Addr) -> long {
    let wide = kind == 0L
    let fraction_bits = if wide { 52L } else { 23L }
    let exponent_bits = if wide { 11L } else { 8L }
    let bias = if wide { 1023L } else { 127L }
    let negative = ((bits >> (fraction_bits + exponent_bits)) & 1L) != 0L
    let exponent_field = (bits >> fraction_bits) & ((1L << exponent_bits) - 1L)
    let fraction = bits & ((1L << fraction_bits) - 1L)
    if exponent_field == (1L << exponent_bits) - 1L {
        if fraction != 0L {
            nl_float_put(out, 0L, 78L)
            nl_float_put(out, 1L, 97L)
            nl_float_put(out, 2L, 78L)
            return 3L
        }
        return nl_float_put_infinity(out, negative)
    }
    let hidden = 1L << fraction_bits
    let minimum_exponent = 1L - bias - fraction_bits
    var mantissa = fraction
    var exponent = minimum_exponent
    if exponent_field != 0L {
        mantissa = fraction + hidden
        exponent = exponent_field - bias - fraction_bits
    }
    if mantissa == 0L {
        nl_float_put(out, 0L, 48L)
        return 1L
    }
    // v = mantissa * 2^exponent; the rounding interval is [v - m-/s/2, v + m+/s/2], inclusive when mantissa is even
    let even = (mantissa & 1L) == 0L
    let wide_gap = mantissa == hidden && exponent_field > 1L
    let stride = 400L
    let r = nl_big_at(scratch, 0L, stride)
    let s = nl_big_at(scratch, 1L, stride)
    let plus = nl_big_at(scratch, 2L, stride)
    let minus = nl_big_at(scratch, 3L, stride)
    let t = nl_big_at(scratch, 4L, stride)
    let digits = sys.offset(scratch, 5L * stride)
    nl_big_from(r, mantissa)
    if exponent >= 0L {
        if !wide_gap {
            nl_big_shl(r, exponent + 1L)
            nl_big_from(s, 2L)
            nl_big_from(plus, 1L)
            nl_big_shl(plus, exponent)
            nl_big_from(minus, 1L)
            nl_big_shl(minus, exponent)
        } else {
            nl_big_shl(r, exponent + 2L)
            nl_big_from(s, 4L)
            nl_big_from(plus, 1L)
            nl_big_shl(plus, exponent + 1L)
            nl_big_from(minus, 1L)
            nl_big_shl(minus, exponent)
        }
    } else {
        if !wide_gap {
            nl_big_shl(r, 1L)
            nl_big_from(s, 1L)
            nl_big_shl(s, 1L - exponent)
            nl_big_from(plus, 1L)
            nl_big_from(minus, 1L)
        } else {
            nl_big_shl(r, 2L)
            nl_big_from(s, 1L)
            nl_big_shl(s, 2L - exponent)
            nl_big_from(plus, 2L)
            nl_big_from(minus, 1L)
        }
    }
    // k: the smallest integer with (v + m+/2) < 10^k (<= 10^k when the upper end is excluded). The estimate
    // ceil((bit_length - 1 + exponent) * log10(2)) from below is at most one too small; the loops fix either side.
    let x = nl_float_bit_length(mantissa) + exponent - 1L
    let product = x * 301029995663L
    var k = if product > 0L { (product + 999999999999L) / 1000000000000L } else { product / 1000000000000L }
    if k >= 0L {
        nl_big_mul_pow10(s, k)
    } else {
        nl_big_mul_pow10(r, 0L - k)
        nl_big_mul_pow10(plus, 0L - k)
        nl_big_mul_pow10(minus, 0L - k)
    }
    for step in 0L..4L {
        nl_big_copy(t, r)
        nl_big_add(t, plus)
        let compared = nl_big_cmp(t, s)
        if (even && compared >= 0L) || (!even && compared > 0L) {
            nl_big_mul_small(s, 10L)
            k += 1L
        } else { break }
    }
    for step in 0L..4L {
        nl_big_copy(t, r)
        nl_big_add(t, plus)
        nl_big_mul_small(t, 10L)
        let compared = nl_big_cmp(t, s)
        if (even && compared < 0L) || (!even && compared <= 0L) {
            nl_big_mul_small(r, 10L)
            nl_big_mul_small(plus, 10L)
            nl_big_mul_small(minus, 10L)
            k -= 1L
        } else { break }
    }
    var count = 0L
    for step in 0L..40L {
        nl_big_mul_small(r, 10L)
        nl_big_mul_small(plus, 10L)
        nl_big_mul_small(minus, 10L)
        var digit = 0L
        for subtractions in 0L..10L {
            if nl_big_cmp(r, s) < 0L { break }
            nl_big_sub(r, s)
            digit += 1L
        }
        let low = nl_big_cmp(r, minus)
        let low_stop = if even { low <= 0L } else { low < 0L }
        nl_big_copy(t, r)
        nl_big_add(t, plus)
        let high = nl_big_cmp(t, s)
        let high_stop = if even { high >= 0L } else { high > 0L }
        if !low_stop && !high_stop {
            sys.store8(digits, count, (int)digit)
            count += 1L
            continue
        }
        var last = digit
        if !low_stop && high_stop { last = digit + 1L }
        else if low_stop && high_stop {
            nl_big_copy(t, r)
            nl_big_mul_small(t, 2L)
            let half = nl_big_cmp(t, s)
            if half > 0L || (half == 0L && digit % 2L == 1L) { last = digit + 1L }
        } else { () }
        sys.store8(digits, count, (int)last)
        count += 1L
        break
    }
    // a final digit of 10 carries into the digits before it
    if (long)sys.load8(digits, count - 1L) == 10L {
        var index = count - 1L
        for step in 0L..40L {
            sys.store8(digits, index, 0)
            if index == 0L {
                sys.store8(digits, 0L, 1)
                k += 1L
                break
            }
            let before = (long)sys.load8(digits, index - 1L) + 1L
            sys.store8(digits, index - 1L, (int)before)
            if before < 10L { break }
            index -= 1L
        }
    }
    for step in 0L..40L {
        if count <= 1L || sys.load8(digits, count - 1L) != 0 { break }
        count -= 1L
    }
    nl_float_layout(digits, count, k, negative, out)
}

// The malformed-text answer of nl_float_parse: the quiet-NaN pattern, which no plain double holds.
fn nl_float_parse_bad() -> long { 9221120237041090560L }

fn nl_float_signed(bits: long, negative: bool) -> long {
    if negative { bits + (-9223372036854775807L - 1L) } else { bits }
}

fn nl_float_is_digit(value: int) -> bool { value >= 48 && value <= 57 }

// The bits of the double nearest to the decimal text data[0..count): [+-] digits [. digits] [e|E [+-] digits], or
// [+-]Infinity. Digits beyond the 768th only matter as "something nonzero follows" (no exact halfway case has more
// than 767 significant digits). scratch: 3648 bytes.
fn nl_float_parse(data: sys.Addr, count: long, scratch: sys.Addr) -> long {
    if count <= 0L { return nl_float_parse_bad() }
    var cursor = 0L
    var negative = false
    let first = sys.load8(data, 0L)
    if first == 45 || first == 43 {
        negative = first == 45
        cursor = 1L
    }
    if cursor >= count { return nl_float_parse_bad() }
    if count - cursor == 8L {
        if sys.load8(data, cursor) == 73 && sys.load8(data, cursor + 1L) == 110 && sys.load8(data, cursor + 2L) == 102 &&
            sys.load8(data, cursor + 3L) == 105 && sys.load8(data, cursor + 4L) == 110 && sys.load8(data, cursor + 5L) == 105 &&
            sys.load8(data, cursor + 6L) == 116 && sys.load8(data, cursor + 7L) == 121 {
            return nl_float_signed(9218868437227405312L, negative)
        }
    }
    let stride = 1216L
    let n = nl_big_at(scratch, 0L, stride)
    let d = nl_big_at(scratch, 1L, stride)
    let s = nl_big_at(scratch, 2L, stride)
    nl_big_set_len(n, 0L)
    var accumulator = 0L
    var accumulated = 0L
    var kept = 0L
    var sticky = false
    var exponent = 0L
    var seen_digit = false
    var seen_point = false
    for step in 0L..count {
        if cursor >= count { break }
        let c = sys.load8(data, cursor)
        if nl_float_is_digit(c) {
            seen_digit = true
            let digit = (long)(c - 48)
            if kept < 768L {
                accumulator = accumulator * 10L + digit
                accumulated += 1L
                if kept > 0L || digit != 0L { kept += 1L }
                if seen_point { exponent -= 1L }
                if accumulated == 9L {
                    nl_big_mul_small(n, 1000000000L)
                    nl_big_add_small(n, accumulator)
                    accumulator = 0L
                    accumulated = 0L
                }
            } else {
                if digit != 0L { sticky = true }
                if !seen_point { exponent += 1L }
            }
        } else if c == 46 {
            if seen_point { return nl_float_parse_bad() }
            seen_point = true
        } else { break }
        cursor += 1L
    }
    if !seen_digit { return nl_float_parse_bad() }
    nl_big_mul_small(n, nl_big_pow10_small(accumulated))
    nl_big_add_small(n, accumulator)
    if cursor < count {
        let marker = sys.load8(data, cursor)
        if marker != 101 && marker != 69 { return nl_float_parse_bad() }
        cursor += 1L
        var exponent_negative = false
        if cursor < count {
            let sign = sys.load8(data, cursor)
            if sign == 45 || sign == 43 {
                exponent_negative = sign == 45
                cursor += 1L
            }
        }
        if cursor >= count { return nl_float_parse_bad() }
        var written = 0L
        for step in 0L..count {
            if cursor >= count { break }
            let c = sys.load8(data, cursor)
            if !nl_float_is_digit(c) { return nl_float_parse_bad() }
            if written < 100000L { written = written * 10L + (long)(c - 48) }
            cursor += 1L
        }
        exponent += if exponent_negative { 0L - written } else { written }
    }
    if sticky {
        nl_big_mul_small(n, 10L)
        nl_big_add_small(n, 1L)
        exponent -= 1L
        kept += 1L
    }
    if nl_big_len(n) == 0L { return nl_float_signed(0L, negative) }
    // value = n * 10^exponent, with kept significant digits in n
    let magnitude = kept + exponent
    if magnitude >= 310L { return nl_float_signed(9218868437227405312L, negative) }
    if magnitude <= -324L { return nl_float_signed(0L, negative) }
    nl_big_from(d, 1L)
    if exponent >= 0L { nl_big_mul_pow10(n, exponent) } else { nl_big_mul_pow10(d, 0L - exponent) }
    // q = value / 2^(e2 - 1) with about 54 or 55 bits, from exact big-integer long division
    var e2 = nl_big_bit_length(n) - nl_big_bit_length(d) - 53L
    if e2 < -1074L { e2 = -1074L }
    let shift = e2 - 1L
    if shift >= 0L { nl_big_shl(d, shift) } else { nl_big_shl(n, 0L - shift) }
    nl_big_copy(s, d)
    nl_big_shl(s, 54L)
    var quotient = 0L
    for step in 0L..55L {
        if nl_big_cmp(n, s) >= 0L {
            nl_big_sub(n, s)
            quotient += 1L << (54L - step)
        }
        nl_big_shr1(s)
    }
    let remainder_nonzero = nl_big_len(n) != 0L
    let drop = if quotient >= 18014398509481984L { 2L } else { 1L }
    var mantissa = quotient >> drop
    let tail = quotient & ((1L << drop) - 1L)
    let half = 1L << (drop - 1L)
    var result_exponent = e2 - 1L + drop
    if tail > half || (tail == half && (remainder_nonzero || (mantissa & 1L) == 1L)) { mantissa += 1L }
    if mantissa == 9007199254740992L {
        mantissa = 4503599627370496L
        result_exponent += 1L
    }
    if mantissa < 4503599627370496L { return nl_float_signed(mantissa, negative) }
    let field = result_exponent + 1075L
    if field >= 2047L { return nl_float_signed(9218868437227405312L, negative) }
    nl_float_signed((field << 52) + (mantissa - 4503599627370496L), negative)
}
