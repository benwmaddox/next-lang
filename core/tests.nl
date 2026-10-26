fn nl_test_selected_index() -> int {
    let value = find_environment(sys.lit(b"NLC_TEST_INDEX"), 14L)
    if sys.is_null(value) { return -1 }
    var at = 0L
    for index in 0L..16777216L {
        let byte = sys.load8(value, at)
        if byte == 32 || (byte >= 9 && byte <= 13) { at += 1L }
        else { break }
    }
    var negative = false
    if sys.load8(value, at) == 43 { at += 1L }
    else if sys.load8(value, at) == 45 { negative = true; at += 1L }
    var number = 0L
    var digits = 0L
    var too_large = false
    for index in 0L..16777216L {
        let byte = sys.load8(value, at)
        if byte == 0 { break }
        if byte < 48 || byte > 57 { return -1 }
        digits += 1L
        let digit = (long)byte - 48L
        if number > 214748364L || (number == 214748364L && digit > 7L) { too_large = true }
        else if !too_large { number = number * 10L + digit }
        at += 1L
    }
    if digits == 0L || sys.load8(value, at) != 0 || too_large { return -1 }
    if negative && number != 0L { return -1 }
    (int)number
}

fn nl_set_test_mode() {
    sys.store32(sys.state(), 131116L, 1)
}

fn nl_test_configure_write_fault(nth: long, kind: int, value: long) {
    let state = sys.state()
    sys.store32(state, state_test_mode(), 1)
    sys.store64(state, write_fault_calls(), 0L)
    sys.store64(state, write_fault_nth(), nth)
    sys.store32(state, write_fault_kind(), kind)
    sys.store64(state, write_fault_value(), value)
    sys.store64(state, write_fault_second_nth(), 0L)
    sys.store32(state, write_fault_second_kind(), 0)
    sys.store64(state, write_fault_second_value(), 0L)
}

fn nl_test_configure_write_fault_sequence(first_kind: int, first_value: long, second_kind: int, second_value: long) {
    let state = sys.state()
    sys.store32(state, state_test_mode(), 1)
    sys.store64(state, write_fault_calls(), 0L)
    sys.store64(state, write_fault_nth(), 1L)
    sys.store32(state, write_fault_kind(), first_kind)
    sys.store64(state, write_fault_value(), first_value)
    sys.store64(state, write_fault_second_nth(), 2L)
    sys.store32(state, write_fault_second_kind(), second_kind)
    sys.store64(state, write_fault_second_value(), second_value)
}

fn nl_test_clear_write_fault() {
    let state = sys.state()
    sys.store64(state, write_fault_calls(), 0L)
    sys.store64(state, write_fault_nth(), 0L)
    sys.store32(state, write_fault_kind(), 0)
    sys.store64(state, write_fault_value(), 0L)
    sys.store64(state, write_fault_second_nth(), 0L)
    sys.store32(state, write_fault_second_kind(), 0)
    sys.store64(state, write_fault_second_value(), 0L)
}
