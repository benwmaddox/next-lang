// E3a1 begin
// This declaration is the single source of context field layout. Its first
// fifteen fields match the offset-mode prefix in runtime/nl_runtime.c.
struct DataStackContext {
    header_mapping: sys.Addr
    header_bytes: long
    mapping: sys.Addr
    mapping_bytes: long
    reservation_bytes: long
    peak_used_bytes: long
    entry_name: sys.Addr
    base: sys.Addr
    top: sys.Addr
    limit: sys.Addr
    top_offset: long
    growth_count: long
    relocation_count: long
    growth_nanoseconds: long
    poison_records: sys.Addr
    pin_count: long
    initial_size: long
    poison_count: long
    core_state: sys.Addr
    entry_name_length: long
    clock_seconds: long
    clock_nanoseconds: long
}

fn core_state_bytes() -> long { 151552L }
fn stack_poison_record_bytes() -> long { 16L }
fn stack_poison_record_capacity() -> long { 64L }
fn stack_default_bytes() -> long { 262144L }

fn startup_write_all(fd: int, bytes: sys.Addr, count: long) -> bool {
    var written = 0L
    for attempt in 0L..1000000L {
        if written >= count { return true }
        let result = sys.write(fd, sys.offset(bytes, written), count - written)
        if sys.is_error(result) {
            if result != -4L { return false }
        } else if result == 0L {
            return false
        } else {
            written += result
        }
    }
    written >= count
}

fn startup_write_z(fd: int, bytes: sys.Addr) -> bool {
    for length in 0L..16777216L {
        if sys.load8(bytes, length) == 0 { return startup_write_all(fd, bytes, length) }
    }
    false
}

fn startup_write_digit(fd: int, digit: long) {
    let bytes = if digit == 0L { sys.lit(b"0") }
        else if digit == 1L { sys.lit(b"1") }
        else if digit == 2L { sys.lit(b"2") }
        else if digit == 3L { sys.lit(b"3") }
        else if digit == 4L { sys.lit(b"4") }
        else if digit == 5L { sys.lit(b"5") }
        else if digit == 6L { sys.lit(b"6") }
        else if digit == 7L { sys.lit(b"7") }
        else if digit == 8L { sys.lit(b"8") }
        else { sys.lit(b"9") }
    let _ = startup_write_all(fd, bytes, 1L)
}

fn startup_write_number(fd: int, value: long) {
    if value < 0L { let _ = startup_write_all(fd, sys.lit(b"-"), 1L) }
    let number = if value < 0L { 0L - value } else { value }
    var power = 1L
    for index in 0L..19L {
        if power > number / 10L { break }
        power *= 10L
    }
    var rest = number
    for index in 0L..20L {
        startup_write_digit(fd, rest / power)
        rest = rest % power
        if power == 1L { break }
        power /= 10L
    }
}

fn write_context_startup_failure(entry_name: sys.Addr, entry_name_length: long, bytes: long, reason: sys.Addr) -> never {
    let prefix_written = startup_write_z(2, sys.lit(b"nlc: data stack startup failure for entry '"))
    if sys.is_null(entry_name) { let unknown_written = startup_write_z(2, sys.lit(b"<unknown>")) }
    else { let name_written = startup_write_all(2, entry_name, entry_name_length) }
    let reservation_written = startup_write_z(2, sys.lit(b"' (reservation "))
    startup_write_number(2, bytes)
    let suffix_written = startup_write_z(2, sys.lit(b" bytes): "))
    let reason_written = startup_write_z(2, reason)
    let newline_written = startup_write_z(2, sys.lit(b"\n"))
    sys.exit_group(1)
}

fn find_environment_in(envp: sys.Addr, key: sys.Addr, key_length: long) -> sys.Addr {
    for index in 0L..1048576L {
        let entry = sys.load_addr(envp, index * 8L)
        if sys.is_null(entry) { return sys.null() }
        var matches = true
        for byte_index in 0L..key_length {
            if sys.load8(entry, byte_index) != sys.load8(key, byte_index) { matches = false }
        }
        if matches && sys.load8(entry, key_length) == 61 {
            return sys.offset(entry, key_length + 1L)
        }
    }
    sys.null()
}

fn context_header_bytes(page_size: long) -> long {
    let required = sys.context_size() + stack_poison_record_bytes() * stack_poison_record_capacity()
    if required > 9223372036854775807L - (page_size - 1L) { return -1L }
    ((required + page_size - 1L) / page_size) * page_size
}

fn nl_context_create(
    requested_bytes: long,
    requested_recursion_budget: long,
    entry_table: sys.Addr,
    entry_index: long,
    envp: sys.Addr,
    auxv: sys.Addr,
) -> sys.Addr {
    let entry_offset = entry_index * 16L
    let entry_name = sys.load_addr(entry_table, entry_offset)
    let entry_name_length = sys.load64(entry_table, entry_offset + 8L)
    let page_size = auxiliary_value(auxv, 6L)
    if page_size <= 0L {
        write_context_startup_failure(entry_name, entry_name_length, requested_bytes, sys.lit(b"could not determine the system page size"))
    }
    var bytes = stack_default_bytes()
    let prealloc = find_environment_in(envp, sys.lit(b"NLC_STACK_PREALLOC"), 18L)
    if !sys.is_null(prealloc) && sys.load8(prealloc, 0L) == 49 && sys.load8(prealloc, 1L) == 0 {
        bytes = requested_bytes
    }
    let force_move = find_environment_in(envp, sys.lit(b"NLC_TEST_STACK_FORCE_MOVE"), 25L)
    if sys.is_test_build() && !sys.is_null(force_move) && sys.load8(force_move, 0L) == 49 && sys.load8(force_move, 1L) == 0 {
        bytes = page_size
    }
    if bytes <= 0L { write_context_startup_failure(entry_name, entry_name_length, bytes, sys.lit(b"computed data stack reservation is zero")) }
    if bytes > 9223372036854775807L - (page_size - 1L) {
        write_context_startup_failure(entry_name, entry_name_length, bytes, sys.lit(b"requested reservation is too large"))
    }
    bytes = ((bytes + page_size - 1L) / page_size) * page_size
    if page_size > 4611686018427387903L || bytes > 9223372036854775807L - 2L * page_size {
        write_context_startup_failure(entry_name, entry_name_length, bytes, sys.lit(b"requested reservation is too large"))
    }
    let header_bytes = context_header_bytes(page_size)
    if header_bytes <= 0L { write_context_startup_failure(entry_name, entry_name_length, bytes, sys.lit(b"requested reservation is too large")) }
    let header_raw = sys.map(sys.null(), header_bytes, 3, 16418, -1, 0L)
    if sys.is_error(header_raw) { write_context_startup_failure(entry_name, entry_name_length, bytes, sys.lit(b"could not reserve the requested address range")) }
    let context = sys.from_raw(header_raw)
    let stack_total = bytes + page_size
    let stack_raw = sys.map(sys.null(), stack_total, 0, 16418, -1, 0L)
    if sys.is_error(stack_raw) {
        let _header_cleanup = sys.unmap(context, header_bytes)
        write_context_startup_failure(entry_name, entry_name_length, bytes, sys.lit(b"could not reserve the requested address range"))
    }
    let base = sys.from_raw(stack_raw)
    let writable = sys.protect(base, bytes, 3)
    if sys.is_error(writable) {
        let _stack_cleanup = sys.unmap(base, stack_total)
        let _header_cleanup = sys.unmap(context, header_bytes)
        write_context_startup_failure(entry_name, entry_name_length, bytes, sys.lit(b"could not enable writable data stack pages"))
    }
    let state_raw = sys.map(sys.null(), core_state_bytes(), 3, 16418, -1, 0L)
    if sys.is_error(state_raw) {
        let _stack_cleanup = sys.unmap(base, stack_total)
        let _header_cleanup = sys.unmap(context, header_bytes)
        write_context_startup_failure(entry_name, entry_name_length, bytes, sys.lit(b"could not reserve the requested address range"))
    }
    let state = sys.from_raw(state_raw)
    let _cleared = sys.fill_bulk(context, 0, sys.context_size())
    let poison_records = sys.offset(context, sys.context_size())
    let limit = sys.offset(base, bytes)
    sys.store_addr(context, sys.context_offset(0L), context)
    sys.store64(context, sys.context_offset(1L), header_bytes)
    sys.store_addr(context, sys.context_offset(2L), base)
    sys.store64(context, sys.context_offset(3L), stack_total)
    sys.store64(context, sys.context_offset(4L), bytes)
    sys.store64(context, sys.context_offset(5L), 0L)
    sys.store_addr(context, sys.context_offset(6L), entry_name)
    sys.store_addr(context, sys.context_offset(7L), base)
    sys.store_addr(context, sys.context_offset(8L), base)
    sys.store_addr(context, sys.context_offset(9L), limit)
    sys.store64(context, sys.context_offset(10L), 0L)
    sys.store64(context, sys.context_offset(11L), 0L)
    sys.store64(context, sys.context_offset(12L), 0L)
    sys.store64(context, sys.context_offset(13L), 0L)
    sys.store_addr(context, sys.context_offset(14L), poison_records)
    sys.store64(context, sys.context_offset(15L), 0L)
    sys.store64(context, sys.context_offset(16L), bytes)
    sys.store64(context, sys.context_offset(17L), 0L)
    sys.store_addr(context, sys.context_offset(18L), state)
    sys.store64(context, sys.context_offset(19L), entry_name_length)
    let _budget = requested_recursion_budget
    context
}

fn nl_context_base_offset() -> long { 0L }

fn nl_context_current_base() -> sys.Addr {
    sys.load_addr(sys.context(), sys.context_offset(7L))
}

fn nl_context_current_limit() -> sys.Addr {
    sys.load_addr(sys.context(), sys.context_offset(9L))
}

fn nl_context_reservation_bytes() -> long {
    sys.load64(sys.context(), sys.context_offset(4L))
}

fn nl_context_set_top_offset(value: long) {
    sys.store64(sys.context(), sys.context_offset(10L), value)
    sys.store_addr(sys.context(), sys.context_offset(8L), sys.offset(nl_context_current_base(), value))
}

fn nl_context_note_peak(value: long) {
    let context = sys.context()
    if value > sys.load64(context, sys.context_offset(5L)) {
        sys.store64(context, sys.context_offset(5L), value)
    }
}

fn nl_context_set_entry_name(entry_table: sys.Addr, entry_index: long) {
    let context = sys.context()
    let entry_offset = entry_index * 16L
    let entry_name = sys.load_addr(entry_table, entry_offset)
    let entry_name_length = sys.load64(entry_table, entry_offset + 8L)
    sys.store_addr(context, sys.context_offset(6L), entry_name)
    sys.store64(context, sys.context_offset(19L), entry_name_length)
}

fn nl_context_destroy() {
    let context = sys.context()
    if !nl_core_flush_all() { nl_fail(20, -1, 0, 0) }
    if nl_stack_stats_enabled() { nl_stack_print_stats(context) }
    let mapping = sys.load_addr(context, sys.context_offset(2L))
    let mapping_bytes = sys.load64(context, sys.context_offset(3L))
    let _stack = sys.unmap(mapping, mapping_bytes)
    let state = sys.load_addr(context, sys.context_offset(18L))
    let _state = sys.unmap(state, core_state_bytes())
    let header = sys.load_addr(context, sys.context_offset(0L))
    let header_bytes = sys.load64(context, sys.context_offset(1L))
    let _header = sys.unmap(header, header_bytes)
}
// E3a1 end
