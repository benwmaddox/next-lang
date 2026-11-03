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

// `pool.set(id, value)`: overwrite the element at an id in place. The result is a bool: true when the id names a
// slot in use (the value was stored), false when it does not (nothing changes).
fn emit_pool_set(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    location: StorageLocation,
    pointer_serial: long,
    element: long,
    stride: long,
    base_offset: long,
    id_argument: long,
    value_argument: long,
) {
    ir_write_ascii(compiler, ir, "  %pool.set.count."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial)
    ir_write_ascii(compiler, ir, ", align 1\n  %pool.set.found."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ult i64 "); ir_write_value_ref(compiler, ir, id_argument)
    ir_write_ascii(compiler, ir, ", %pool.set.count."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br i1 %pool.set.found."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %pool.set.store."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %pool.set.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\npool.set.store."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n")
    if is_aggregate_type(compiler, element) {
        let source_location = aggregate_source_location_for_node(tables, compiler, value_argument)
        let source_pointer = emit_location_pointer_materialization(compiler, ir, source_location)
        emit_collection_store_dynamic_fields(compiler, ir, element, stride, base_offset, 0L,
            location, pointer_serial, source_location, source_pointer, 2L, id_argument)
    } else {
        ir_write_ascii(compiler, ir, "  %pool.set.bytes."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = mul i64 "); ir_write_value_ref(compiler, ir, id_argument)
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride)
        ir_write_ascii(compiler, ir, "\n  %pool.set.offset."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = add i64 %pool.set.bytes."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset)
        ir_write_ascii(compiler, ir, "\n  %pool.set.ptr."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial)
        ir_write_ascii(compiler, ir, ", i64 %pool.set.offset."); ir_write_number(compiler, ir, node)
        if element == TY_BOOL {
            ir_write_ascii(compiler, ir, "\n  %pool.set.bool."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value_argument)
            ir_write_ascii(compiler, ir, " to i8\n  store i8 %pool.set.bool."); ir_write_number(compiler, ir, node)
        } else {
            ir_write_ascii(compiler, ir, "\n  store "); ir_write_ascii(compiler, ir, llvm_type_name(element))
            ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_argument)
        }
        ir_write_ascii(compiler, ir, ", ptr %pool.set.ptr."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
    }
    ir_write_ascii(compiler, ir, "  br label %pool.set.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\npool.set.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = and i1 %pool.set.found."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", true\n")
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

// The copy helper of a pool type copies only the 16-byte header (count and capacity). A pool is never copied
// with elements: the checker allows a pool to be copied only from a `pool {}` literal, which is empty.
fn emit_pool_copy_helpers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    for type_id in 0L..type_count(compiler) {
        if type_kind(compiler, type_id) != TYPE_KIND_POOL || !has_type_helper(compiler, type_id, HELPER_COPY) { continue }
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr %nl.dest, ptr %nl.source) {\nentry:\n  %pool.copy.count = load i64, ptr %nl.source, align 1\n")
        ir_write_ascii(compiler, ir, "  store i64 %pool.copy.count, ptr %nl.dest, align 1\n")
        ir_write_ascii(compiler, ir, "  %pool.copy.source.cap = getelementptr i8, ptr %nl.source, i64 8\n")
        ir_write_ascii(compiler, ir, "  %pool.copy.cap = load i64, ptr %pool.copy.source.cap, align 1\n")
        ir_write_ascii(compiler, ir, "  %pool.copy.dest.cap = getelementptr i8, ptr %nl.dest, i64 8\n")
        ir_write_ascii(compiler, ir, "  store i64 %pool.copy.cap, ptr %pool.copy.dest.cap, align 1\n")
        if type_is_arena(compiler, type_id) {
            // the arena's open-builder mark travels with its header (an arena literal copies a closed one)
            ir_write_ascii(compiler, ir, "  %pool.copy.source.mark = getelementptr i8, ptr %nl.source, i64 16\n  %pool.copy.mark = load i64, ptr %pool.copy.source.mark, align 1\n  %pool.copy.dest.mark = getelementptr i8, ptr %nl.dest, i64 16\n  store i64 %pool.copy.mark, ptr %pool.copy.dest.mark, align 1\n")
        }
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}
