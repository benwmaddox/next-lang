fn state_scratch() -> long { 139392L }

fn decimal_bytes(value: long, output: sys.Addr) -> long {
    var n = value
    if n > 0L { n = 0L - n }
    var digits = 1L
    var rest = n / 10L
    for index in 0L..19L {
        if rest == 0L { break }
        digits += 1L
        rest = rest / 10L
    }
    var first = 0L
    if value < 0L {
        sys.store8(output, 0L, 45)
        first = 1L
    }
    var place = first + digits - 1L
    for index in 0L..digits {
        sys.store8(output, place, (int)(48L - n % 10L))
        n = n / 10L
        place -= 1L
    }
    first + digits
}

fn write_all(fd: int, bytes: sys.Addr, count: long) -> bool {
    var written = 0L
    for attempt in 0L..1000000L {
        if written >= count { return true }
        match write(fd, sys.offset(bytes, written), count - written) {
            ok(amount) => {
                if amount == 0L { return false }
                written += amount
            }
            err(error) => {
                if error.number != 4 { return false }
            }
        }
    }
    written >= count
}

fn write_z(fd: int, value: sys.Addr) -> bool {
    var length = 0L
    for index in 0L..16777216L {
        if sys.load8(value, index) == 0 { length = index; break }
    }
    write_all(fd, value, length)
}

fn write_number(fd: int, value: long) -> bool {
    let output = sys.offset(sys.state(), state_scratch())
    let count = decimal_bytes(value, output)
    write_all(fd, output, count)
}

fn write_bool(fd: int, value: bool) -> bool {
    if value { write_z(fd, sys.lit(b"true")) }
    else { write_z(fd, sys.lit(b"false")) }
}
