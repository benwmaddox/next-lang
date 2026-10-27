fn nl_env_create(argc: int, argv: sys.Addr, capabilities: int) -> sys.Addr {
    if argc > 65 {
        write_z(2, sys.lit(b"nlc: startup argument failure: more than 64 program arguments were supplied\n"))
        sys.exit_group(1)
    }
    for argument_index in 1..argc {
        let index: long = (long)argument_index
        let argument = sys.load_addr(argv, index * 8L)
        var found_end = false
        for length in 0L..4097L {
            if sys.load8(argument, length) == 0 {
                found_end = true
                break
            }
        }
        if !found_end {
            write_z(2, sys.lit(b"nlc: startup argument failure: a program argument is longer than 4096 bytes\n"))
            sys.exit_group(1)
        }
    }
    let root = openat(-100, sys.lit(b"."), 2625536, 0)
    if root.is_err() {
        write_z(2, sys.lit(b"nlc: data stack startup failure: cannot open the file-system root\n"))
        sys.exit_group(1)
    }
    sys.store32(sys.state(), state_root_fd(), (int)root.unwrap())
    let _ = capabilities
    sys.state()
}

fn nl_env_destroy(environment: sys.Addr) {
    let _ = environment
    let fd = sys.load32(sys.state(), state_root_fd())
    if fd >= 0 { let _closed = close(fd) }
}
