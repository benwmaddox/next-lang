fn output_capacity() -> long { 65536L }
fn output_lengths() -> long { 131072L }
fn output_buffer(stream: int) -> long { if stream == 0 { 0L } else { 65536L } }
fn output_length_slot(stream: int) -> long { output_lengths() + (long)stream * 8L }
fn output_fd(stream: int) -> int { if stream == 0 { 1 } else { 2 } }
fn output_scratch() -> long { 139392L }
fn write_fault_calls() -> long { 140000L }
fn write_fault_nth() -> long { 140008L }
fn write_fault_kind() -> long { 140016L }
fn write_fault_value() -> long { 140024L }
fn write_fault_second_nth() -> long { 140032L }
fn write_fault_second_kind() -> long { 140040L }
fn write_fault_second_value() -> long { 140048L }

fn nl_core_sys_write(fd: int, data: sys.Addr, byte_count: long) -> long {
    let state = sys.state()
    if sys.load32(state, state_test_mode()) == 0 { return sys.write(fd, data, byte_count) }
    let nth = sys.load64(state, write_fault_nth())
    if nth <= 0L { return sys.write(fd, data, byte_count) }
    let call_number = sys.load64(state, write_fault_calls()) + 1L
    sys.store64(state, write_fault_calls(), call_number)
    let second_nth = sys.load64(state, write_fault_second_nth())
    if call_number != nth && call_number != second_nth { return sys.write(fd, data, byte_count) }
    var kind = sys.load32(state, write_fault_kind())
    var value = sys.load64(state, write_fault_value())
    if call_number == second_nth {
        kind = sys.load32(state, write_fault_second_kind())
        value = sys.load64(state, write_fault_second_value())
    }
    if kind == 1 {
        let short_count = if value < byte_count { value } else { byte_count }
        return sys.write(fd, data, short_count)
    }
    if kind == 2 && value > 0L { return 0L - value }
    sys.write(fd, data, byte_count)
}

fn output_terminal(stream: int) -> bool {
    let state = sys.state()
    let offset = if stream == 0 { state_out_terminal() } else { state_err_terminal() }
    let cached = sys.load32(state, offset)
    if cached >= 0 { return cached != 0 }
    let result = ioctl(output_fd(stream), 21505L, sys.offset(state, output_scratch()))
    let terminal = result.is_ok() && result.unwrap() == 0L
    sys.store32(state, offset, if terminal { 1 } else { 0 })
    terminal
}

fn output_shared_terminal() -> bool {
    let state = sys.state()
    let cached = sys.load32(state, state_shared_terminal())
    if cached >= 0 { return cached != 0 }
    var same = output_terminal(0) && output_terminal(1)
    if same {
        let out_stat = statx(1, sys.lit(b""), 4096, 256, sys.offset(state, output_scratch()))
        if out_stat.is_err() { same = false }
        else if out_stat.unwrap() != 0L { same = false }
        else { () }
    }
    if same {
        let err_stat = statx(2, sys.lit(b""), 4096, 256, sys.offset(state, output_scratch() + 256L))
        if err_stat.is_err() { same = false }
        else if err_stat.unwrap() != 0L { same = false }
        else { () }
    }
    if same {
        same = sys.load64(state, output_scratch() + 32L) == sys.load64(state, output_scratch() + 256L + 32L) &&
            sys.load32(state, output_scratch() + 136L) == sys.load32(state, output_scratch() + 256L + 136L) &&
            sys.load32(state, output_scratch() + 140L) == sys.load32(state, output_scratch() + 256L + 140L)
    }
    sys.store32(state, state_shared_terminal(), if same { 1 } else { 0 })
    same
}

fn output_flush_index(stream: int) -> bool {
    let state = sys.state()
    let buffer = output_buffer(stream)
    let length_slot = output_length_slot(stream)
    let length = sys.load64(state, length_slot)
    var written = 0L
    for attempt in 0L..1000000L {
        if written >= length {
            sys.store64(state, length_slot, 0L)
            return true
        }
        match write(output_fd(stream), sys.offset(state, buffer + written), length - written) {
            ok(written_count) => {
                if written_count == 0L {
                    let remaining = length - written
                    let _moved = memmove(sys.offset(state, buffer), sys.offset(state, buffer + written), remaining)
                    sys.store64(state, length_slot, remaining)
                    return false
                }
                written += written_count
            }
            err(error) => {
                if error.number != 4 {
                    let remaining = length - written
                    let _moved = memmove(sys.offset(state, buffer), sys.offset(state, buffer + written), remaining)
                    sys.store64(state, length_slot, remaining)
                    return false
                }
            }
        }
    }
    let remaining = length - written
    let _moved = memmove(sys.offset(state, buffer), sys.offset(state, buffer + written), remaining)
    sys.store64(state, length_slot, remaining)
    false
}

fn nl_core_flush_all() -> bool {
    let shared = output_shared_terminal()
    let state = sys.state()
    var first = 0
    var second = 1
    if shared && sys.load64(state, output_length_slot(0)) != 0L && sys.load64(state, output_length_slot(1)) != 0L {
        if sys.load32(state, state_last_stream()) == 0 {
            first = 1
            second = 0
        }
    }
    let first_ok = output_flush_index(first)
    let second_ok = output_flush_index(second)
    first_ok && second_ok
}

fn nl_core_output_write(fd: int, data: sys.Addr, byte_count: long) -> bool {
    if fd != 1 && fd != 2 { return write_all(fd, data, byte_count) }
    let stream = if fd == 1 { 0 } else { 1 }
    let other = if stream == 0 { 1 } else { 0 }
    let shared = output_shared_terminal()
    let state = sys.state()
    if shared && sys.load64(state, output_length_slot(other)) != 0L {
        if !output_flush_index(other) { return false }
    }
    let line_buffered = output_terminal(stream)
    let capacity = output_capacity()
    let buffer = output_buffer(stream)
    let length_slot = output_length_slot(stream)
    var consumed = 0L
    for attempt in 0L..1000000L {
        if consumed >= byte_count { return true }
        var length = sys.load64(state, length_slot)
        var available = capacity - length
        if available == 0L {
            if !output_flush_index(stream) { return false }
            length = 0L
            available = capacity
        }
        var amount = byte_count - consumed
        if amount > available { amount = available }
        var line_end = -1L
        if line_buffered {
            for index in 0L..amount {
                if sys.load8(data, consumed + index) == 10 {
                    line_end = index
                    break
                }
            }
        }
        var flush_line = false
        if line_end >= 0L {
            amount = line_end + 1L
            flush_line = true
        }
        for index in 0L..amount {
            sys.store8(state, buffer + length + index, sys.load8(data, consumed + index))
        }
        length += amount
        consumed += amount
        sys.store64(state, length_slot, length)
        sys.store32(state, state_last_stream(), stream)
        if flush_line && !output_flush_index(stream) { return false }
    }
    consumed >= byte_count
}

fn nl_print_int(value: int) {
    let scratch = sys.offset(sys.state(), output_scratch() + 512L)
    let byte_count = decimal_bytes((long)value, scratch)
    sys.store8(scratch, byte_count, 10)
    if !nl_core_output_write((int)sys.load32(sys.state(), state_print_fd()), scratch, byte_count + 1L) { nl_fail(20, -1, 0, 0) }
}

fn nl_print_long(value: long) {
    let scratch = sys.offset(sys.state(), output_scratch() + 512L)
    let byte_count = decimal_bytes(value, scratch)
    sys.store8(scratch, byte_count, 10)
    if !nl_core_output_write((int)sys.load32(sys.state(), state_print_fd()), scratch, byte_count + 1L) { nl_fail(20, -1, 0, 0) }
}

fn nl_print_bool(value: bool) {
    let data = if value { sys.lit(b"true\n") } else { sys.lit(b"false\n") }
    let byte_count = if value { 5L } else { 6L }
    if !nl_core_output_write((int)sys.load32(sys.state(), state_print_fd()), data, byte_count) { nl_fail(20, -1, 0, 0) }
}

fn nl_print_ascii(data: sys.Addr, byte_count: long) {
    if !nl_core_output_write((int)sys.load32(sys.state(), state_print_fd()), data, byte_count) { nl_fail(20, -1, 0, 0) }
}

fn nl_print_newline() {
    nl_print_ascii(sys.lit(b"\n"), 1L)
}

fn nl_print_int_raw(value: int) {
    let scratch = sys.offset(sys.state(), output_scratch() + 512L)
    let byte_count = decimal_bytes((long)value, scratch)
    if !nl_core_output_write((int)sys.load32(sys.state(), state_print_fd()), scratch, byte_count) { nl_fail(20, -1, 0, 0) }
}

fn nl_print_long_raw(value: long) {
    let scratch = sys.offset(sys.state(), output_scratch() + 512L)
    let byte_count = decimal_bytes(value, scratch)
    if !nl_core_output_write((int)sys.load32(sys.state(), state_print_fd()), scratch, byte_count) { nl_fail(20, -1, 0, 0) }
}

fn nl_print_bool_raw(value: bool) {
    let data = if value { sys.lit(b"true") } else { sys.lit(b"false") }
    let byte_count = if value { 4L } else { 5L }
    if !nl_core_output_write((int)sys.load32(sys.state(), state_print_fd()), data, byte_count) { nl_fail(20, -1, 0, 0) }
}
