// E3a1 begin
fn stack_context_mapping() -> long { 2L }
fn stack_context_mapping_bytes() -> long { 3L }
fn stack_context_reservation() -> long { 4L }
fn stack_context_peak() -> long { 5L }
fn stack_context_base() -> long { 7L }
fn stack_context_top() -> long { 8L }
fn stack_context_limit() -> long { 9L }
fn stack_context_top_offset() -> long { 10L }
fn stack_context_growth_count() -> long { 11L }
fn stack_context_relocation_count() -> long { 12L }
fn stack_context_growth_nanoseconds() -> long { 13L }
fn stack_context_poison_records() -> long { 14L }
fn stack_context_pin_count() -> long { 15L }
fn stack_context_initial_size() -> long { 16L }
fn stack_context_poison_count() -> long { 17L }
fn stack_context_clock_seconds() -> long { 20L }

fn stack_environment_is_one(key: sys.Addr, key_length: long) -> bool {
    let value = find_environment(key, key_length)
    !sys.is_null(value) && sys.load8(value, 0L) == 49 && sys.load8(value, 1L) == 0
}

fn nl_stack_verify_enabled() -> bool {
    stack_environment_is_one(sys.lit(b"NLC_STACK_VERIFY"), 16L)
}

fn nl_stack_stats_enabled() -> bool {
    stack_environment_is_one(sys.lit(b"NLC_STACK_STATS"), 15L)
}

fn nl_stack_test_two_phase_enabled() -> bool {
    stack_environment_is_one(sys.lit(b"NLC_TEST_STACK_TWO_PHASE"), 24L)
}

fn nl_stack_test_grow_enabled() -> bool {
    stack_environment_is_one(sys.lit(b"NLC_TEST_STACK_GROW"), 19L)
}

fn nl_stack_test_pin_enabled() -> bool {
    stack_environment_is_one(sys.lit(b"NLC_TEST_STACK_PIN_REFUSAL"), 26L)
}

fn nl_stack_test_poison_full_enabled() -> bool {
    stack_environment_is_one(sys.lit(b"NLC_TEST_STACK_POISON_FULL"), 26L)
}

fn nl_stack_clock_nanoseconds(context: sys.Addr) -> long {
    let timespec = sys.offset(context, sys.context_offset(stack_context_clock_seconds()))
    let clock_status = match clock_gettime(1, timespec) {
        ok(status) => status,
        err(_) => return 0L,
    }
    if clock_status != 0L { return 0L }
    let seconds = sys.load64(context, sys.context_offset(stack_context_clock_seconds()))
    let nanoseconds = sys.load64(context, sys.context_offset(stack_context_clock_seconds() + 1L))
    seconds * 1000000000L + nanoseconds
}

fn nl_stack_grow(needed_bytes: long, file_id: int, line: int, col: int) {
    let context = sys.context()
    let old_bytes = sys.load64(context, sys.context_offset(stack_context_reservation()))
    if needed_bytes <= old_bytes { return }
    if sys.load64(context, sys.context_offset(stack_context_pin_count())) > 0L {
        nl_fail(18, file_id, line, col)
    }
    let page_size = sys.load64(sys.state(), state_page_size())
    if page_size <= 0L { nl_fail(18, file_id, line, col) }
    let verify = nl_stack_verify_enabled()
    let poison_count = sys.load64(context, sys.context_offset(stack_context_poison_count()))
    if verify && poison_count >= stack_poison_record_capacity() { nl_fail(18, file_id, line, col) }
    var new_bytes = old_bytes
    for doubling in 0L..64L {
        if new_bytes >= needed_bytes { break }
        if new_bytes > 4611686018427387903L {
            new_bytes = needed_bytes
            break
        }
        new_bytes *= 2L
    }
    if new_bytes < needed_bytes { new_bytes = needed_bytes }
    if new_bytes > 9223372036854775807L - (page_size - 1L) { nl_fail(18, file_id, line, col) }
    new_bytes = ((new_bytes + page_size - 1L) / page_size) * page_size
    if new_bytes > 9223372036854775807L - page_size { nl_fail(18, file_id, line, col) }
    let new_mapping_bytes = new_bytes + page_size
    let target = match map(sys.null(), new_mapping_bytes, 0, 16418, -1, 0L) {
        ok(address) => sys.from_raw(address),
        err(_) => nl_fail(18, file_id, line, col),
    }
    let old_base = sys.load_addr(context, sys.context_offset(stack_context_base()))
    let top_offset = sys.load64(context, sys.context_offset(stack_context_top_offset()))
    let start = nl_stack_clock_nanoseconds(context)
    let moved_raw = remap(old_base, old_bytes, new_bytes, 3, target)
    let finish = nl_stack_clock_nanoseconds(context)
    let moved = match moved_raw {
        ok(address) => sys.from_raw(address),
        err(_) => {
            let _target_cleanup = unmap(target, new_mapping_bytes)
            nl_fail(18, file_id, line, col)
        },
    }
    let old_total = old_bytes + page_size
    let old_guard = sys.offset(old_base, old_bytes)
    let guard_unmapped = unmap(old_guard, page_size)
    if guard_unmapped.is_err() { nl_fail(18, file_id, line, col) }
    if verify {
        let poison_address = map(old_base, old_total, 0, 16434, -1, 0L)
        if poison_address.is_err() { nl_fail(18, file_id, line, col) }
        let records = sys.load_addr(context, sys.context_offset(stack_context_poison_records()))
        let record = sys.offset(records, poison_count * stack_poison_record_bytes())
        sys.store_addr(record, 0L, old_base)
        sys.store64(record, 8L, old_total)
        sys.store64(context, sys.context_offset(stack_context_poison_count()), poison_count + 1L)
    }
    let limit = sys.offset(moved, new_bytes)
    let top = sys.offset(moved, top_offset)
    sys.store_addr(context, sys.context_offset(stack_context_mapping()), moved)
    sys.store64(context, sys.context_offset(stack_context_mapping_bytes()), new_mapping_bytes)
    sys.store64(context, sys.context_offset(stack_context_reservation()), new_bytes)
    sys.store_addr(context, sys.context_offset(stack_context_base()), moved)
    sys.store_addr(context, sys.context_offset(stack_context_top()), top)
    sys.store_addr(context, sys.context_offset(stack_context_limit()), limit)
    sys.store64(context, sys.context_offset(stack_context_growth_count()), sys.load64(context, sys.context_offset(stack_context_growth_count())) + 1L)
    // The target range is mapped while the old one is still occupied, so a
    // fixed remap always changes the address.
    sys.store64(context, sys.context_offset(stack_context_relocation_count()), sys.load64(context, sys.context_offset(stack_context_relocation_count())) + 1L)
    if finish >= start {
        let elapsed = finish - start
        let accumulated = sys.load64(context, sys.context_offset(stack_context_growth_nanoseconds()))
        sys.store64(context, sys.context_offset(stack_context_growth_nanoseconds()), accumulated + elapsed)
    }
    if needed_bytes > sys.load64(context, sys.context_offset(stack_context_peak())) {
        sys.store64(context, sys.context_offset(stack_context_peak()), needed_bytes)
    }
}

fn stack_write(context: sys.Addr, fd: int, offset: long, byte_count: long) -> Result<long, Errno> {
    write(fd, sys.stack_addr(context, offset), byte_count)
}

fn stack_load8(context: sys.Addr, offset: long) -> int {
    sys.stack_load8(context, offset)
}

fn stack_store8(context: sys.Addr, offset: long, value: int) {
    sys.stack_store8(context, offset, value)
}

fn nl_stack_test_grow_once() {
    let context = sys.context()
    let old_bytes = sys.load64(context, sys.context_offset(stack_context_reservation()))
    nl_stack_grow(old_bytes + 1L, -1, 0, 0)
    if nl_stack_verify_enabled() &&
        sys.load64(context, sys.context_offset(stack_context_poison_count())) != 1L {
        nl_fail(18, -1, 0, 0)
    }
}

fn nl_stack_test_force_count() -> long {
    nl_stack_test_grow_once()
    1L
}

fn nl_stack_test_two_phase() {
    let context = sys.context()
    stack_store8(context, 0L, 88)
    match write(1, sys.stack_addr(context, 0L), nl_stack_test_force_count()) {
        ok(written_count) => if written_count != 1L { nl_fail(18, -1, 0, 0) },
        err(_) => nl_fail(18, -1, 0, 0),
    }
}

fn nl_stack_test_pin_refusal() {
    let context = sys.context()
    let old_bytes = sys.load64(context, sys.context_offset(stack_context_reservation()))
    sys.store64(context, sys.context_offset(stack_context_pin_count()), 1L)
    nl_stack_grow(old_bytes + 1L, -1, 0, 0)
    sys.store64(context, sys.context_offset(stack_context_pin_count()), 0L)
    nl_fail(18, -1, 0, 0)
}

fn nl_stack_test_poison_table_full() {
    let context = sys.context()
    let old_bytes = sys.load64(context, sys.context_offset(stack_context_reservation()))
    sys.store64(context, sys.context_offset(stack_context_poison_count()), stack_poison_record_capacity())
    nl_stack_grow(old_bytes + 1L, -1, 0, 0)
    nl_fail(18, -1, 0, 0)
}

fn nl_stack_test_bootstrap() {
    if !sys.is_test_build() { return }
    if nl_stack_test_pin_enabled() { nl_stack_test_pin_refusal() }
    else if nl_stack_test_poison_full_enabled() { nl_stack_test_poison_table_full() }
    else if nl_stack_test_two_phase_enabled() { nl_stack_test_two_phase() }
    else if nl_stack_test_grow_enabled() { nl_stack_test_grow_once() }
}

fn nl_stack_print_stats(context: sys.Addr) {
    let name = sys.load_addr(context, sys.context_offset(6L))
    let name_length = sys.load64(context, sys.context_offset(19L))
    let _p0 = write_all(2, sys.lit(b"nl offset stack entry '"), 23L)
    let _p1 = write_all(2, name, name_length)
    let _p2 = write_all(2, sys.lit(b"': initial="), 11L)
    let _p3 = write_number(2, sys.load64(context, sys.context_offset(stack_context_initial_size())))
    let _p4 = write_all(2, sys.lit(b" reserved="), 10L)
    let _p5 = write_number(2, sys.load64(context, sys.context_offset(stack_context_reservation())))
    let _p6 = write_all(2, sys.lit(b" peak_used="), 11L)
    let _p7 = write_number(2, sys.load64(context, sys.context_offset(stack_context_peak())))
    let _p8 = write_all(2, sys.lit(b" growths="), 9L)
    let _p9 = write_number(2, sys.load64(context, sys.context_offset(stack_context_growth_count())))
    let _p10 = write_all(2, sys.lit(b" relocations="), 13L)
    let _p11 = write_number(2, sys.load64(context, sys.context_offset(stack_context_relocation_count())))
    let _p12 = write_all(2, sys.lit(b" growth_ns="), 11L)
    let _p13 = write_number(2, sys.load64(context, sys.context_offset(stack_context_growth_nanoseconds())))
    let _p14 = write_all(2, sys.lit(b"\n"), 1L)
}
// E3a1 end
