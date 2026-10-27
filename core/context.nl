fn stack_default_bytes() -> long { 262144L }

fn write_context_startup_failure(entry_name: sys.Addr, reservation_bytes: long, reason: sys.Addr) -> never {
    write_z(2, sys.lit(b"nlc: data stack startup failure for entry '"))
    if sys.is_null(entry_name) { write_z(2, sys.lit(b"<unknown>")) }
    else { write_z(2, entry_name) }
    write_z(2, sys.lit(b"' (reservation "))
    write_number(2, reservation_bytes)
    write_z(2, sys.lit(b" bytes): "))
    write_z(2, reason)
    write_z(2, sys.lit(b"\n"))
    sys.exit_group(1)
}

fn nl_context_create(requested_bytes: long, requested_recursion_budget: long, entry_name: sys.Addr) -> sys.Addr {
    let page_size = sys.load64(sys.state(), state_page_size())
    if page_size <= 0L {
        write_context_startup_failure(entry_name, requested_bytes, sys.lit(b"could not determine the system page size"))
    }
    var reservation_bytes = stack_default_bytes()
    let prealloc = find_environment(sys.lit(b"NLC_STACK_PREALLOC"), 18L)
    if !sys.is_null(prealloc) && sys.load8(prealloc, 0L) == 49 && sys.load8(prealloc, 1L) == 0 {
        reservation_bytes = requested_bytes
    }
    if reservation_bytes <= 0L { write_context_startup_failure(entry_name, reservation_bytes, sys.lit(b"computed data stack reservation is zero")) }
    if reservation_bytes > 9223372036854775807L - (page_size - 1L) {
        write_context_startup_failure(entry_name, reservation_bytes, sys.lit(b"requested reservation is too large"))
    }
    reservation_bytes = ((reservation_bytes + page_size - 1L) / page_size) * page_size
    if page_size > 4611686018427387903L || reservation_bytes > 9223372036854775807L - 2L * page_size {
        write_context_startup_failure(entry_name, reservation_bytes, sys.lit(b"requested reservation is too large"))
    }
    let total = reservation_bytes + 2L * page_size
    let raw = map(sys.null(), total, 0, 16418, -1, 0L)
    if raw.is_err() { write_context_startup_failure(entry_name, reservation_bytes, sys.lit(b"could not reserve the requested address range")) }
    let mapping = sys.from_raw(raw.unwrap())
    let header = protect(mapping, page_size, 3)
    let base = sys.offset(mapping, page_size)
    let stack = protect(base, reservation_bytes, 3)
    if header.is_err() || stack.is_err() {
        write_context_startup_failure(entry_name, reservation_bytes, sys.lit(b"could not enable writable data stack pages"))
    }
    let _ = requested_recursion_budget
    base
}

fn nl_context_base_offset(context: sys.Addr) -> long {
    let _ = context
    0L
}

fn nl_context_destroy(context: sys.Addr) {
    let _ = context
    if !nl_core_flush_all() { nl_fail(20, -1, 0, 0) }
}
