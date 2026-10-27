struct Errno {
    number: int
}

fn result_errno(raw: long) -> Errno {
    Errno { number: (int)(0L - raw) }
}

fn write(fd: int, data: sys.Addr, byte_count: long) -> Result<long, Errno> {
    let raw = nl_core_sys_write(fd, data, byte_count)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}

fn map(address: sys.Addr, length: long, protection: int, flags: int, fd: int, offset: long) -> Result<long, Errno> {
    let raw = sys.map(address, length, protection, flags, fd, offset)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}

fn protect(address: sys.Addr, length: long, protection: int) -> Result<long, Errno> {
    let raw = sys.protect(address, length, protection)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}

fn ioctl(fd: int, request: long, argument: sys.Addr) -> Result<long, Errno> {
    let raw = sys.ioctl(fd, request, argument)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}

fn statx(fd: int, path: sys.Addr, flags: int, mask: int, output: sys.Addr) -> Result<long, Errno> {
    let raw = sys.statx(fd, path, flags, mask, output)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}

fn sigaction(signal: int, action: sys.Addr, old_action: sys.Addr, size: long) -> Result<long, Errno> {
    let raw = sys.sigaction(signal, action, old_action, size)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}

fn openat(directory: int, path: sys.Addr, flags: int, mode: int) -> Result<long, Errno> {
    let raw = sys.openat(directory, path, flags, mode)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}

fn close(fd: int) -> Result<long, Errno> {
    let raw = sys.close(fd)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}

fn remap(address: sys.Addr, old_length: long, new_length: long, flags: int, new_address: sys.Addr) -> Result<long, Errno> {
    let raw = sys.remap(address, old_length, new_length, flags, new_address)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}

fn unmap(address: sys.Addr, length: long) -> Result<long, Errno> {
    let raw = sys.unmap(address, length)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}

fn clock_gettime(clock: int, output: sys.Addr) -> Result<long, Errno> {
    let raw = sys.clock_gettime(clock, output)
    if sys.is_error(raw) { return err(result_errno(raw)) }
    ok(raw)
}
