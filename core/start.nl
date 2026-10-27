fn state_envp() -> long { 131088L }
fn state_auxv() -> long { 131096L }
fn state_page_size() -> long { 131104L }
fn state_print_fd() -> long { 131112L }
fn state_test_mode() -> long { 131116L }
fn state_root_fd() -> long { 131120L }
fn state_out_terminal() -> long { 131124L }
fn state_err_terminal() -> long { 131128L }
fn state_shared_terminal() -> long { 131132L }
fn state_last_stream() -> long { 131136L }
fn state_file_table() -> long { 131144L }
fn state_sigaction() -> long { 139344L }

fn auxiliary_value(auxv: sys.Addr, wanted: long) -> long {
    for index in 0L..4096L {
        let kind = sys.load64(auxv, index * 16L)
        if kind == 0L { return 0L }
        if kind == wanted { return sys.load64(auxv, index * 16L + 8L) }
    }
    0L
}

fn count_entries(values: sys.Addr) -> long {
    for index in 0L..1048576L {
        if sys.is_null(sys.load_addr(values, index * 8L)) { return index }
    }
    0L
}

// E3a1 begin: file names and lengths arrive as a static descriptor table.
fn nl_register_files(first_file_id: int, table: sys.Addr, file_count: int) {
    let state = sys.state()
    for index in 0L..(long)file_count {
        let file_id = (long)first_file_id + index
        if file_id >= 0L && file_id < 1024L {
            let table_offset = index * 16L
            let name = sys.load_addr(table, table_offset)
            let name_length = sys.load64(table, table_offset + 8L)
            let state_offset = state_file_table() + file_id * 16L
            sys.store_addr(state, state_offset, name)
            sys.store64(state, state_offset + 8L, name_length)
        }
    }
}
// E3a1 end

// E3a1 begin: startup carries auxv directly into context creation.
fn nl_core_start(initial: sys.Addr) -> never {
    let argc = sys.load64(initial, 0L)
    let argv = sys.offset(initial, 8L)
    let envp = sys.offset(argv, (argc + 1L) * 8L)
    let auxv = sys.offset(envp, (count_entries(envp) + 1L) * 8L)
    let status = sys.call_main((int)argc, argv, envp, auxv)
    sys.exit_group(status)
}
// E3a1 end

// E3a1 begin: process initialization receives the job context and test hooks.
fn nl_core_init(argc: int, argv: sys.Addr, envp: sys.Addr, auxv: sys.Addr) {
    let state = sys.state()
    sys.store_addr(state, state_envp(), envp)
    sys.store_addr(state, state_auxv(), auxv)
    sys.store64(state, state_page_size(), auxiliary_value(auxv, 6L))
    sys.store32(state, state_print_fd(), 1)
    sys.store32(state, state_test_mode(), 0)
    sys.store32(state, state_root_fd(), -1)
    sys.store64(state, 131072L, 0L)
    sys.store64(state, 131080L, 0L)
    sys.store32(state, state_out_terminal(), -1)
    sys.store32(state, state_err_terminal(), -1)
    sys.store32(state, state_shared_terminal(), -1)
    sys.store32(state, state_last_stream(), -1)
    let action = sys.offset(state, state_sigaction())
    sys.fill_bulk(action, 0, 32L)
    sys.store64(action, 0L, 1L)
    let ignored = sigaction(13, action, sys.null(), 8L)
    if ignored.is_err() {
        write_z(2, sys.lit(b"nlc: data stack startup failure: could not ignore SIGPIPE\n"))
        sys.exit_group(1)
    }
}
// E3a1 end

fn find_environment(key: sys.Addr, key_length: long) -> sys.Addr {
    let envp = sys.load_addr(sys.state(), state_envp())
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

