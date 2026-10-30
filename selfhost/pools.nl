// A pool is a list-like collection with a 16-byte header (the count of slots in use, then the capacity) and
// the elements as plain records after it. An id is the slot number; the slot's generation lives in the high
// 32 bits and is always zero until slots can be removed and reused, so a valid id is a count-bounded slot.

// A pool parameter written with a capacity parameter accepts a pool of the same elements and any capacity.
fn pool_accepts_any_capacity(compiler: CompilerTables, actual: long, expected: long) -> bool {
    type_kind(compiler, expected) == TYPE_KIND_POOL && type_kind(compiler, actual) == TYPE_KIND_POOL &&
        collection_capacity(compiler, expected) == POOL_ANY_CAPACITY &&
        collection_element_type(compiler, expected) == collection_element_type(compiler, actual)
}

// `pool.get(id)`: the element as an Option. The element is copied into the option's payload.
fn emit_pool_get(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    location: StorageLocation,
    pointer_serial: long,
    element: long,
    stride: long,
    base_offset: long,
) {
    let receiver = compiler.child_first[node]
    let argument = compiler.child_next[receiver]
    let result_type = compiler.facts[node].ty
    let payload = sum_payload_record(compiler, result_type, 0L, 0L)
    let address = enum_temporary_address(node, MAX_TREE_NODES * 3L + 4L)
    emit_layout_address(compiler, ir, address, storage_location_with_offset(aggregate_destination_location(compiler, 0L, node), payload.offset))
    ir_write_ascii(compiler, ir, "  %pool.get.count."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial)
    ir_write_ascii(compiler, ir, ", align 1\n  %pool.get.found."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ult i64 "); ir_write_value_ref(compiler, ir, argument)
    ir_write_ascii(compiler, ir, ", %pool.get.count."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br i1 %pool.get.found."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %pool.get.some."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %pool.get.none."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\npool.get.some."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %pool.get.bytes."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = mul i64 "); ir_write_value_ref(compiler, ir, argument)
    ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, "\n  %pool.get.offset."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = add i64 %pool.get.bytes."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset)
    ir_write_ascii(compiler, ir, "\n  %pool.get.source."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial)
    ir_write_ascii(compiler, ir, ", i64 %pool.get.offset."); ir_write_number(compiler, ir, node)
    if is_aggregate_type(compiler, element) {
        ir_write_ascii(compiler, ir, "\n  %pool.get.copy."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call ptr @nl.mem.copy(ptr %addr."); ir_write_number(compiler, ir, address)
        ir_write_ascii(compiler, ir, ", ptr %pool.get.source."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, stride)
        ir_write_ascii(compiler, ir, ")\n")
    } else if element == TY_BOOL {
        ir_write_ascii(compiler, ir, "\n  %pool.get.byte."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = load i8, ptr %pool.get.source."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", align 1\n  store i8 %pool.get.byte."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address)
        ir_write_ascii(compiler, ir, ", align 1\n")
    } else {
        ir_write_ascii(compiler, ir, "\n  %pool.get.value."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(element))
        ir_write_ascii(compiler, ir, ", ptr %pool.get.source."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, llvm_type_name(element))
        ir_write_ascii(compiler, ir, " %pool.get.value."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address)
        ir_write_ascii(compiler, ir, ", align 1\n")
    }
    emit_sum_tag_store(compiler, ir, node, 0L)
    ir_write_ascii(compiler, ir, "  br label %pool.get.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\npool.get.none."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n")
    emit_sum_tag_store(compiler, ir, node, 1L)
    ir_write_ascii(compiler, ir, "  br label %pool.get.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\npool.get.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n")
}

// Whether a value of this type holds a pool, directly or in a struct field.
recursive fn type_contains_pool(compiler: CompilerTables, type_id: long, depth: long) -> bool {
    if depth > 16L || type_id < 0L || type_id >= type_count(compiler) { return false }
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_POOL { return true }
    if kind == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_offset in 0L..record.field_count {
            if type_contains_pool(compiler, compiler.struct_fields[record.field_start + field_offset].ty, depth + 1L) { return true }
        }
    }
    false
}
