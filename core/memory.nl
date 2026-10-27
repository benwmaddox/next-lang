fn copy_forward(dst: sys.Addr, src: sys.Addr, byte_count: long) {
    if byte_count >= 2048L {
        sys.copy_forward_bulk(dst, src, byte_count)
        return
    }
    let vectors = byte_count / 16L
    let groups = vectors / 4L
    for group in 0L..groups {
        let offset = group * 64L
        sys.copy_16(sys.offset(dst, offset), sys.offset(src, offset))
        sys.copy_16(sys.offset(dst, offset + 16L), sys.offset(src, offset + 16L))
        sys.copy_16(sys.offset(dst, offset + 32L), sys.offset(src, offset + 32L))
        sys.copy_16(sys.offset(dst, offset + 48L), sys.offset(src, offset + 48L))
    }
    for index in groups * 4L..vectors {
        let offset = index * 16L
        sys.copy_16(sys.offset(dst, offset), sys.offset(src, offset))
    }
    for index in vectors * 16L..byte_count {
        sys.store8(dst, index, sys.load8(src, index))
    }
}

fn copy_backward(dst: sys.Addr, src: sys.Addr, byte_count: long) {
    for index in 0L..byte_count {
        let position = byte_count - index - 1L
        sys.store8(dst, position, sys.load8(src, position))
    }
}

fn memcpy(dst: sys.Addr, src: sys.Addr, byte_count: long) -> sys.Addr {
    if byte_count >= 2048L {
        sys.copy_forward_bulk(dst, src, byte_count)
        return dst
    }
    if byte_count < 8L {
        if byte_count > 0L { sys.store8(dst, 0L, sys.load8(src, 0L)) }
        if byte_count > 1L { sys.store8(dst, 1L, sys.load8(src, 1L)) }
        if byte_count > 2L { sys.store8(dst, 2L, sys.load8(src, 2L)) }
        if byte_count > 3L { sys.store8(dst, 3L, sys.load8(src, 3L)) }
        if byte_count > 4L { sys.store8(dst, 4L, sys.load8(src, 4L)) }
        if byte_count > 5L { sys.store8(dst, 5L, sys.load8(src, 5L)) }
        if byte_count > 6L { sys.store8(dst, 6L, sys.load8(src, 6L)) }
        return dst
    }
    if byte_count < 16L {
        let first = sys.load64(src, 0L)
        let last = sys.load64(src, byte_count - 8L)
        sys.store64(dst, 0L, first)
        sys.store64(dst, byte_count - 8L, last)
        return dst
    }
    let last = byte_count - 16L
    if byte_count <= 32L {
        sys.copy_16(dst, src)
        sys.copy_16(sys.offset(dst, last), sys.offset(src, last))
        return dst
    }
    if byte_count <= 48L {
        sys.copy_16(dst, src)
        sys.copy_16(sys.offset(dst, 16L), sys.offset(src, 16L))
        sys.copy_16(sys.offset(dst, last), sys.offset(src, last))
        return dst
    }
    if byte_count <= 64L {
        sys.copy_16(dst, src)
        sys.copy_16(sys.offset(dst, 16L), sys.offset(src, 16L))
        sys.copy_16(sys.offset(dst, 32L), sys.offset(src, 32L))
        sys.copy_16(sys.offset(dst, last), sys.offset(src, last))
        return dst
    }
    let vectors = byte_count / 16L
    let groups = vectors / 4L
    for group in 0L..groups {
        let offset = group * 64L
        sys.copy_16(sys.offset(dst, offset), sys.offset(src, offset))
        sys.copy_16(sys.offset(dst, offset + 16L), sys.offset(src, offset + 16L))
        sys.copy_16(sys.offset(dst, offset + 32L), sys.offset(src, offset + 32L))
        sys.copy_16(sys.offset(dst, offset + 48L), sys.offset(src, offset + 48L))
    }
    for index in groups * 4L..vectors {
        let offset = index * 16L
        sys.copy_16(sys.offset(dst, offset), sys.offset(src, offset))
    }
    for index in vectors * 16L..byte_count {
        sys.store8(dst, index, sys.load8(src, index))
    }
    dst
}

fn memmove(dst: sys.Addr, src: sys.Addr, byte_count: long) -> sys.Addr {
    let distance = sys.distance(src, dst)
    if distance > 0L && distance < byte_count { copy_backward(dst, src, byte_count) }
    else { copy_forward(dst, src, byte_count) }
    dst
}

fn memset(dst: sys.Addr, value: int, byte_count: long) -> sys.Addr {
    if byte_count >= 2048L {
        sys.fill_bulk(dst, value, byte_count)
        return dst
    }
    if byte_count < 8L {
        if byte_count > 0L { sys.store8(dst, 0L, value) }
        if byte_count > 1L { sys.store8(dst, 1L, value) }
        if byte_count > 2L { sys.store8(dst, 2L, value) }
        if byte_count > 3L { sys.store8(dst, 3L, value) }
        if byte_count > 4L { sys.store8(dst, 4L, value) }
        if byte_count > 5L { sys.store8(dst, 5L, value) }
        if byte_count > 6L { sys.store8(dst, 6L, value) }
        return dst
    }
    if byte_count < 16L {
        let repeated = sys.repeat_byte(value)
        sys.store64(dst, 0L, repeated)
        if byte_count > 8L { sys.store8(dst, 8L, value) }
        if byte_count > 9L { sys.store8(dst, 9L, value) }
        if byte_count > 10L { sys.store8(dst, 10L, value) }
        if byte_count > 11L { sys.store8(dst, 11L, value) }
        if byte_count > 12L { sys.store8(dst, 12L, value) }
        if byte_count > 13L { sys.store8(dst, 13L, value) }
        if byte_count > 14L { sys.store8(dst, 14L, value) }
        return dst
    }
    let repeated = sys.repeat_byte(value)
    let last = byte_count - 16L
    if byte_count <= 32L {
        sys.fill_16(dst, repeated)
        sys.fill_16(sys.offset(dst, last), repeated)
        return dst
    }
    if byte_count <= 48L {
        sys.fill_16(dst, repeated)
        sys.fill_16(sys.offset(dst, 16L), repeated)
        sys.fill_16(sys.offset(dst, last), repeated)
        return dst
    }
    if byte_count <= 64L {
        sys.fill_16(dst, repeated)
        sys.fill_16(sys.offset(dst, 16L), repeated)
        sys.fill_16(sys.offset(dst, 32L), repeated)
        sys.fill_16(sys.offset(dst, last), repeated)
        return dst
    }
    let vectors = byte_count / 16L
    let groups = vectors / 4L
    for group in 0L..groups {
        let offset = group * 64L
        sys.fill_16(sys.offset(dst, offset), repeated)
        sys.fill_16(sys.offset(dst, offset + 16L), repeated)
        sys.fill_16(sys.offset(dst, offset + 32L), repeated)
        sys.fill_16(sys.offset(dst, offset + 48L), repeated)
    }
    for index in groups * 4L..vectors { sys.fill_16(sys.offset(dst, index * 16L), repeated) }
    for index in vectors * 16L..byte_count { sys.store8(dst, index, value) }
    dst
}

fn memcmp(left: sys.Addr, right: sys.Addr, byte_count: long) -> int {
    for index in 0L..byte_count {
        let a = sys.load8(left, index)
        let b = sys.load8(right, index)
        if a < b { return -1 }
        if a > b { return 1 }
    }
    0
}

fn bcmp(left: sys.Addr, right: sys.Addr, byte_count: long) -> int {
    memcmp(left, right, byte_count)
}
