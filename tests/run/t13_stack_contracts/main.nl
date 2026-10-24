struct Nested { values: list<long, 600> = list {} }

fn make_nested() -> Nested[2] {
    var rows: Nested[2] = fill(Nested {})
    discard rows[1L].values.push(73L)
    return rows
}

fn identity(values: list<long, 8192>) -> list<long, 8192> {
    values
}

fn write_nested(value: write Nested) {
    discard value.values.push(5L)
}

fn possibly_alias(left: Nested[2], right: Nested[2]) -> long {
    left[0L].values.count() + right[0L].values.count()
}

fn sort_large() {
    var values: list<long, 100000> = list {}
    for i: long in 0L..100000L {
        discard values.push(100000L - i)
    }
    sort(values)
    print(values[0L])
    print(values[99999L])
}

fn consume(value: long) {}

fn indirect_large_target() -> long {
    let scratch: long[1024] = fill(0L)
    scratch[0L]
}

fn call_indirect(callback: fn() -> long) -> long {
    callback()
}

fn copy_large(value: long[1024]) -> long[1024] {
    value
}

fn maybe_copy(value: Option<long[1024]>) -> Option<long[1024]> {
    value?.copy_large()
}

fn maybe_try_copy(value: Option<long[1024]>) -> Option<long[1024]> {
    some(value?)
}

fn no_stack_loop() {
    for i: long in 0L..10L {
        let next = i + 1L
        consume(next)
    }
}

fn outer_survives_loop() {
    var outer: list<long, 1024> = list {}
    discard outer.push(88L)
    for i: long in 0L..20L {
        let scratch: long[1024] = fill(i)
        consume(scratch[0L])
    }
    print(outer[0L])
}

fn main() {
    var input: list<long, 8192> = list {}
    discard input.push(41L)
    let copied = identity(input)
    print(copied[0L])

    let nested = make_nested()
    print(nested[1L].values[0L])

    var megabyte: list<long, 131072> = list {}
    discard megabyte.push(7L)
    print(megabyte[0L])

    sort_large()
    outer_survives_loop()
    no_stack_loop()
    print(call_indirect(indirect_large_target))
    var items: long[1024] = fill(0L)
    items[0L] = 77L
    let optional_items: Option<long[1024]> = some(items)
    let copied_optional = maybe_copy(optional_items)
    print(match copied_optional {
        some(copied) => copied[0L],
        none => -1L
    })
    let absent_copied = maybe_copy(none)
    print(match absent_copied {
        some(absent) => absent[0L],
        none => -1L
    })
    let tried_optional = maybe_try_copy(optional_items)
    print(match tried_optional {
        some(tried) => tried[0L],
        none => -1L
    })
    let absent_optional = maybe_try_copy(none)
    print(match absent_optional {
        some(absent) => absent[0L],
        none => -1L
    })
    let coalesced: long[1024] = absent_optional ?? fill(9L)
    print(coalesced[0L])
}
