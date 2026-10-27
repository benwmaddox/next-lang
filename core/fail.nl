// E3a1 begin: file names in the context state carry explicit byte lengths.
fn file_name(file_id: int) -> sys.Addr {
    if file_id < 0 || file_id >= 1024 { return sys.lit(b"<source>") }
    let name = sys.load_addr(sys.state(), state_file_table() + (long)file_id * 16L)
    if sys.is_null(name) { sys.lit(b"<source>") } else { name }
}

fn file_name_length(file_id: int) -> long {
    if file_id < 0 || file_id >= 1024 { return 8L }
    let state = sys.state()
    let offset = state_file_table() + (long)file_id * 16L
    if sys.is_null(sys.load_addr(state, offset)) { 8L }
    else { sys.load64(state, offset + 8L) }
}
// E3a1 end

fn failure_message(kind: int) -> sys.Addr {
    if kind == 1 { sys.lit(b"overflow in int addition") }
    else if kind == 2 { sys.lit(b"overflow in int subtraction") }
    else if kind == 3 { sys.lit(b"overflow in int multiplication") }
    else if kind == 4 { sys.lit(b"overflow in int negation") }
    else if kind == 5 { sys.lit(b"overflow in long addition") }
    else if kind == 6 { sys.lit(b"overflow in long subtraction") }
    else if kind == 7 { sys.lit(b"overflow in long multiplication") }
    else if kind == 8 { sys.lit(b"overflow in long negation") }
    else if kind == 9 { sys.lit(b"divide by zero") }
    else if kind == 10 { sys.lit(b"bad cast") }
    else if kind == 11 { sys.lit(b"bad shift") }
    else if kind == 12 { sys.lit(b"overflow in int division") }
    else if kind == 13 { sys.lit(b"overflow in long division") }
    else if kind == 14 { sys.lit(b"unwrap called on none") }
    else if kind == 15 { sys.lit(b"unwrap called on err") }
    else if kind == 16 { sys.lit(b"index out of range") }
    else if kind == 17 { sys.lit(b"binary_search requires sorted input") }
    else if kind == 18 { sys.lit(b"data stack exhausted") }
    else if kind == 19 { sys.lit(b"recursion budget exhausted") }
    else if kind == 20 { sys.lit(b"standard output write failed") }
    else if kind == 21 { sys.lit(b"clamp lower bound is greater than its upper bound") }
    else if kind == 23 { sys.lit(b"loop step budget exhausted") }
    else { sys.lit(b"runtime failure") }
}

// E3a1 begin: hooks receive context and print static-table names by length.
fn nl_fail(kind: int, file_id: int, line: int, col: int) -> never {
    let _flush = nl_core_flush_all()
    let _file = write_all(2, file_name(file_id), file_name_length(file_id))
    write_z(2, sys.lit(b":"))
    write_number(2, (long)line)
    write_z(2, sys.lit(b":"))
    write_number(2, (long)col)
    write_z(2, sys.lit(b": "))
    write_z(2, failure_message(kind))
    write_z(2, sys.lit(b"\n"))
    if nl_stack_stats_enabled() { nl_stack_print_stats(sys.context()) }
    let test_mode = sys.load32(sys.state(), 131116L) != 0
    if test_mode { sys.exit_group(70) } else { sys.exit_group(1) }
}

fn nl_expect_fail_compare(file_id: int, line: int, col: int, source: sys.Addr, source_length: long, left: long, right: long, is_bool: int) {
    let _flush = nl_core_flush_all()
    write_z(1, sys.lit(b"  "))
    let _file = write_all(1, file_name(file_id), file_name_length(file_id))
    write_z(1, sys.lit(b":"))
    write_number(1, (long)line)
    write_z(1, sys.lit(b":"))
    write_number(1, (long)col)
    write_z(1, sys.lit(b": "))
    let _source = write_all(1, source, source_length)
    write_z(1, sys.lit(b"\n    left:  "))
    if is_bool != 0 { write_bool(1, left != 0L) } else { write_number(1, left) }
    write_z(1, sys.lit(b"\n    right: "))
    if is_bool != 0 { write_bool(1, right != 0L) } else { write_number(1, right) }
    let _last_write = write_z(1, sys.lit(b"\n"))
}

fn nl_expect_fail_header(file_id: int, line: int, col: int, source: sys.Addr, source_length: long) {
    let _flush = nl_core_flush_all()
    write_z(1, sys.lit(b"  "))
    let _file = write_all(1, file_name(file_id), file_name_length(file_id))
    write_z(1, sys.lit(b":"))
    write_number(1, (long)line)
    write_z(1, sys.lit(b":"))
    write_number(1, (long)col)
    write_z(1, sys.lit(b": "))
    let _source = write_all(1, source, source_length)
    let _last_write = write_z(1, sys.lit(b"\n"))
}

fn nl_expect_fail_left() {
    let _flush = nl_core_flush_all()
    let _last_write = write_z(1, sys.lit(b"    left:  "))
}

fn nl_expect_fail_right() {
    let _flush = nl_core_flush_all()
    let _last_write = write_z(1, sys.lit(b"    right: "))
}

fn nl_expect_fail_bool(file_id: int, line: int, col: int, source: sys.Addr, source_length: long) {
    let _flush = nl_core_flush_all()
    write_z(1, sys.lit(b"  "))
    let _file = write_all(1, file_name(file_id), file_name_length(file_id))
    write_z(1, sys.lit(b":"))
    write_number(1, (long)line)
    write_z(1, sys.lit(b":"))
    write_number(1, (long)col)
    write_z(1, sys.lit(b": "))
    let _source = write_all(1, source, source_length)
    let _last_write = write_z(1, sys.lit(b"\n    value: false\n"))
}
// E3a1 end
