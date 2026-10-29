// E3a1 begin: shared compiler integration.
fn emit_aggregate_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let field_index = compiler.facts[node].literal
    let field = compiler.struct_fields[field_index]
    let receiver = compiler.child_first[node]
    if emit_collection_field_path_address(tables, compiler, ir, node, node) { return }
    if emit_parameter_field_path_address(tables, compiler, ir, node, node) { return }
    if tables.nodes[receiver].kind == NodeKind.Name {
        let binding = compiler.facts[receiver].binding
        if compiler.bindings[binding].parameter { emit_layout_address(compiler, ir, node, compiler_location(compiler, 3L, binding, field.offset)) }
        else { emit_layout_address(compiler, ir, node, compiler_location(compiler, 1L, binding, field.offset)) }
    } else if tables.nodes[receiver].kind == NodeKind.Field {
        emit_layout_address(compiler, ir, node, compiler_location(compiler, 2L, receiver, field.offset))
    } else {
        emit_layout_address(compiler, ir, node, compiler_location(compiler, 0L, receiver, field.offset))
    }
}
// E3a1 end

fn emit_field_path_value(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    compiler.type_walk.clear()
    var current = node
    for path_step in 0L..MAX_TREE_NODES {
        if current < 0L || tables.nodes[current].kind != NodeKind.Field { break }
        compiler.type_walk.push(TypeWalkFrame { type_index: current, field_index: -1L, size: 0L, align: 0L, case_index: 0L, max_size: 0L }).unwrap()
        current = compiler.child_first[current]
    }
    for path_index in 0L..compiler.type_walk.count() {
        let field_node = compiler.type_walk[compiler.type_walk.count() - path_index - 1L].type_index
        emit_aggregate_address(tables, compiler, ir, field_node)
        let field_ty = compiler.facts[field_node].ty
        if field_node == node && !is_aggregate_type(compiler, field_ty) && field_ty != TY_UNIT {
            emit_load_scalar(compiler, ir, field_node, field_ty)
        }
    }
    compiler.type_walk.clear()
}

// E3a1 begin: shared compiler integration.
fn emit_aggregate_copy(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    destination: StorageLocation,
    source: StorageLocation,
) {
    if type_kind(compiler, type_id) == TYPE_KIND_TEXT && text_read_view_binding(compiler, source) >= 0L {
        emit_text_read_view_copy(compiler, ir, type_id, destination, source)
        return
    }
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
    ir_write_ascii(compiler, ir, "  call void ")
    emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY)
    ir_push_byte(compiler, ir, 40)
    ir_write_ascii(compiler, ir, "ptr %nl.ctx, ptr ")
    emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", ")
    ir_write_ascii(compiler, ir, "ptr ")
    emit_location_pointer_reference(compiler, ir, source, source_pointer)
    ir_write_ascii(compiler, ir, ")\n")
    emit_text_assert_storage(compiler, ir, type_id, destination)
}
// E3a1 end

fn emit_aggregate_copy_to_place(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    destination_node: long,
    source_node: long,
    fallback_destination: StorageLocation,
) {
    let destination = place_storage_location(tables, compiler, destination_node)
    if destination.index_node != -1L && destination.copies > 0L && type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
        let base = compiler_location(compiler, destination.anchor_kind, destination.anchor_node, 0L)
        let destination_pointer = emit_location_pointer_materialization(compiler, ir, base)
        let source_kind = aggregate_source_kind(tables, compiler, source_node)
        let source_id = aggregate_source_id(tables, compiler, source_node)
        let source = aggregate_source_location(compiler, source_kind, source_id)
        let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
        emit_collection_store_element_fields(compiler, ir, type_id, destination.index_stride, 0L,
            destination.index_node, destination.byte_offset, 0L, base, source, destination_pointer, source_pointer)
    } else {
        let source_kind = aggregate_source_kind(tables, compiler, source_node)
        let source_id = aggregate_source_id(tables, compiler, source_node)
        emit_aggregate_copy(compiler, ir, type_id, fallback_destination, aggregate_source_location(compiler, source_kind, source_id))
    }
}

fn emit_type_helper_symbol(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    operation: long,
) {
    if !is_aggregate_type(compiler, type_id) || !has_type_helper(compiler, type_id, operation) {
        compiler.ir_overflow = true
        return
    }
    if operation == HELPER_COPY {
        if compiler.core_mode { ir_write_ascii(compiler, ir, "@nl.core.copy.") } else { ir_write_ascii(compiler, ir, "@nl.copy.") }
    }
    else if operation == HELPER_EQUAL {
        if compiler.core_mode { ir_write_ascii(compiler, ir, "@nl.core.eq.") } else { ir_write_ascii(compiler, ir, "@nl.eq.") }
    }
    else if operation == HELPER_PRINT {
        if compiler.core_mode { ir_write_ascii(compiler, ir, "@nl.core.print.") } else { ir_write_ascii(compiler, ir, "@nl.print.") }
    }
    else if operation == HELPER_FILL {
        if compiler.core_mode { ir_write_ascii(compiler, ir, "@nl.core.fill.") } else { ir_write_ascii(compiler, ir, "@nl.fill.") }
    }
    else { compiler.ir_overflow = true }
    ir_write_number(compiler, ir, type_id)
}

fn emit_default_field_helper_symbol(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    field_index: long,
) {
    if !has_type_helper(compiler, type_id, HELPER_DEFAULT) { compiler.ir_overflow = true }
    if compiler.core_mode { ir_write_ascii(compiler, ir, "@nl.core.default.") } else { ir_write_ascii(compiler, ir, "@nl.default.") }
    ir_write_number(compiler, ir, type_id)
    ir_push_byte(compiler, ir, 46)
    ir_write_number(compiler, ir, field_index)
}

// E3a1 begin: shared compiler integration.
fn emit_type_helper_call_one(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    operation: long,
    operand: StorageLocation,
    pointer: long,
) {
    let text_view_binding = text_read_view_binding(compiler, operand)
    if operation == HELPER_PRINT && type_kind(compiler, type_id) == TYPE_KIND_TEXT && text_view_binding >= 0L {
        emit_context_runtime_symbol(compiler, ir, "nl_print_ascii", "nlc_print_ascii")
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr ")
        emit_location_pointer_reference(compiler, ir, operand, pointer)
        ir_write_ascii(compiler, ir, ", i64 %arg.copies."); ir_write_number(compiler, ir, text_view_binding); ir_push_byte(compiler, ir, 41)
        return
    }
    emit_type_helper_symbol(compiler, ir, type_id, operation)
    ir_push_byte(compiler, ir, 40)
    ir_write_ascii(compiler, ir, "ptr %nl.ctx, ")
    ir_write_ascii(compiler, ir, "ptr ")
    emit_location_pointer_reference(compiler, ir, operand, pointer)
    ir_push_byte(compiler, ir, 41)
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_type_helper_call_two(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    operation: long,
    first: StorageLocation,
    second: StorageLocation,
    first_pointer: long,
    second_pointer: long,
) {
    emit_type_helper_symbol(compiler, ir, type_id, operation)
    ir_push_byte(compiler, ir, 40)
    ir_write_ascii(compiler, ir, "ptr %nl.ctx, ")
    ir_write_ascii(compiler, ir, "ptr ")
    emit_location_pointer_reference(compiler, ir, first, first_pointer)
    ir_write_ascii(compiler, ir, ", ")
    ir_write_ascii(compiler, ir, "ptr ")
    emit_location_pointer_reference(compiler, ir, second, second_pointer)
    ir_push_byte(compiler, ir, 41)
}
// E3a1 end

fn is_enum_case_field(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    if node < 0L || node >= tables.nodes.count() ||
        tables.nodes[node].kind != NodeKind.Field ||
        compiler.facts[node].binding >= 0L ||
        type_kind(compiler, compiler.facts[node].ty) != TYPE_KIND_ENUM {
        return false
    }
    // A qualified case keeps its type-name receiver unevaluated. A field
    // read from a temporary can also have no binding, so binding alone is
    // not enough to classify an enum-valued field as a constructor.
    let receiver = compiler.child_first[node]
    receiver >= 0L && tables.nodes[receiver].kind == NodeKind.Name &&
        compiler.facts[receiver].binding < 0L && compiler.facts[receiver].ty < 0L
}

fn aggregate_source_kind(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    if is_enum_case_field(tables, compiler, node) { 0L }
    else if tables.nodes[node].kind == NodeKind.Field { 3L }
    else if tables.nodes[node].kind == NodeKind.Name {
        let binding = compiler.facts[node].binding
        if binding < 0L { 0L }
        else if binding_is_view(compiler, binding) { 0L }
        else if compiler.bindings[binding].parameter { 2L } else { 1L }
    } else { 0L }
}

fn aggregate_source_id(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    if tables.nodes[node].kind == NodeKind.Name && binding_is_view(compiler, compiler.facts[node].binding) { node }
    else if tables.nodes[node].kind == NodeKind.Name && compiler.facts[node].binding >= 0L { compiler.facts[node].binding }
    else { node }
}

fn aggregate_source_location_for_node(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> StorageLocation {
    let kind = aggregate_source_kind(tables, compiler, node)
    let source_id = aggregate_source_id(tables, compiler, node)
    aggregate_source_location(compiler, kind, source_id)
}

fn emit_store_scalar(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    ty: long,
    value_node: long,
) {
    if ty == TY_BOOL {
        ir_write_ascii(compiler, ir, "  %bool.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, " to i8\n  store i8 %bool.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1")
    } else {
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1")
    }
    emit_program_storage_tbaa(compiler, ir)
    ir_push_byte(compiler, ir, 10)
}

// Recompute a place pointer after evaluating the assignment value. A call on
// the right hand side can grow the data stack and move every stack slot, so an
// address emitted while evaluating the left hand side is only for reading.
recursive fn emit_late_place_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) -> long {
    let address_id = MAX_TREE_NODES * 1024L + next_location_serial(ir) * MAX_TREE_NODES + node
    if tables.nodes[node].kind == NodeKind.Field {
        if emit_collection_field_path_address(tables, compiler, ir, node, address_id) { return address_id }
        if emit_parameter_field_path_address(tables, compiler, ir, node, address_id) { return address_id }
    }
    if tables.nodes[node].kind == NodeKind.Index {
        let collection = compiler.child_first[node]
        let index_node = if collection >= 0L { compiler.child_next[collection] } else { -1L }
        if collection >= 0L && index_node >= 0L && tables.nodes[collection].kind == NodeKind.Field {
            let collection_address = emit_late_place_address(tables, compiler, ir, collection)
            let base = compiler_location(compiler, 2L, collection_address, 0L)
            let pointer = emit_location_pointer_materialization(compiler, ir, base)
            let type_id = compiler.facts[collection].ty
            let element_type = collection_element_type(compiler, type_id)
            let stride = value_type_size(compiler, element_type)
            let base_offset = collection_element_base_offset(compiler, type_id)
            if stride < 0L || base_offset < 0L { compiler.ir_overflow = true; return address_id }
            ir_write_ascii(compiler, ir, "  %late.place.index."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = mul i64 "); ir_write_value_ref(compiler, ir, index_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "  %late.place.offset."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = add i64 %late.place.index."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
            emit_location_pointer_reference(compiler, ir, base, pointer)
            ir_write_ascii(compiler, ir, ", i64 %late.place.offset."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
            return address_id
        }
    }
    if tables.nodes[node].kind == NodeKind.Index {
        // An element of a list or array of text lives in one contiguous run, so its address is the
        // collection's base plus index * element size.
        let text_collection = compiler.child_first[node]
        let text_index = if text_collection >= 0L { compiler.child_next[text_collection] } else { -1L }
        if text_collection >= 0L && text_index >= 0L && tables.nodes[text_collection].kind == NodeKind.Name {
            let text_collection_type = compiler.facts[text_collection].ty
            let text_element = collection_element_type(compiler, text_collection_type)
            if collection_text_leaf(type_kind(compiler, text_element)) {
                let text_stride = value_type_size(compiler, text_element)
                let text_base_offset = collection_element_base_offset(compiler, text_collection_type)
                if text_stride < 0L || text_base_offset < 0L { compiler.ir_overflow = true; return address_id }
                let text_base = collection_value_location(tables, compiler, text_collection)
                let text_pointer = emit_location_pointer_materialization(compiler, ir, text_base)
                ir_write_ascii(compiler, ir, "  %late.text.index."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = mul i64 ")
                ir_write_value_ref(compiler, ir, text_index); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, text_stride)
                ir_write_ascii(compiler, ir, "\n  %late.text.offset."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = add i64 %late.text.index.")
                ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, text_base_offset)
                ir_write_ascii(compiler, ir, "\n  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
                emit_location_pointer_reference(compiler, ir, text_base, text_pointer)
                ir_write_ascii(compiler, ir, ", i64 %late.text.offset."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
                return address_id
            }
        }
    }
    let location = place_storage_location(tables, compiler, node)
    if location.copies != 1L { compiler.ir_overflow = true; return address_id }
    let base = StorageLocation {
        origin: location.origin,
        anchor_kind: location.anchor_kind,
        anchor_node: location.anchor_node,
        byte_offset: 0L,
        copies: 1L,
        index: 0L,
        index_node: -1L,
        index_stride: 0L,
    }
    let pointer = emit_location_pointer_materialization(compiler, ir, base)
    if location.index_node != -1L {
        if location.index_stride <= 0L { compiler.ir_overflow = true; return address_id }
        ir_write_ascii(compiler, ir, "  %late.place.index."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = mul i64 ")
        emit_location_index_value(compiler, ir, location)
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.index_stride); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %late.place.offset."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_write_ascii(compiler, ir, ", %late.place.index."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, base, pointer)
        ir_write_ascii(compiler, ir, ", i64 %late.place.offset."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
    } else {
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, base, pointer)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
    }
    address_id
}

fn emit_store_scalar_to_place(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    ty: long,
    value_node: long,
) {
    let address_id = emit_late_place_address(tables, compiler, ir, node)
    if ty == TY_BOOL {
        ir_write_ascii(compiler, ir, "  %late.bool.store."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, " to i8\n  store i8 %late.bool.store."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", align 1")
    } else {
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", align 1")
    }
    emit_program_storage_tbaa(compiler, ir)
    ir_push_byte(compiler, ir, 10)
}

fn emit_load_scalar(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    ty: long,
) {
    if ty == TY_BOOL {
        ir_write_ascii(compiler, ir, "  %bool.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i8 %bool.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i1\n")
    } else {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    }
}

fn ir_write_token_text(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    file_index: long,
    token: long,
) {
    let start = files[file_index].base + tokens[token].start
    for index in 0L..tokens[token].length { ir_push_byte(compiler, ir, source[start + index]) }
}

// E3a1 begin: shared compiler integration.
fn core_external_symbol(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    token: long,
) -> bool {
    token_is_word_at(source, tokens, files, file_index, token, "nl_core_start") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_core_init") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_create") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_base_offset") ||
    // E3a1 subsection
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_current_base") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_current_limit") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_reservation_bytes") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_set_top_offset") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_note_peak") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_set_entry_name") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_stack_grow") ||
    // E3a1 subsection end
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_destroy") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_env_create") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_env_destroy") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_register_files") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_test_selected_index") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_set_test_mode") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_int") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_long") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_bool") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_int_raw") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_long_raw") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_bool_raw") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_ascii") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_newline") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_fail") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_expect_fail_compare") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_expect_fail_bool") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_expect_fail_header") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_expect_fail_left") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_expect_fail_right") ||
    token_is_word_at(source, tokens, files, file_index, token, "memcpy") ||
    token_is_word_at(source, tokens, files, file_index, token, "memmove") ||
    token_is_word_at(source, tokens, files, file_index, token, "memset") ||
    token_is_word_at(source, tokens, files, file_index, token, "memcmp") ||
    token_is_word_at(source, tokens, files, file_index, token, "bcmp")
}
// E3a1 end

