// C-runtime capabilities needed by the self-hosted compiler.
const C_METHOD_NONE: long = 0L
const C_METHOD_ENV_ARGS: long = 3001L
const C_METHOD_ENV_EXIT: long = 3002L
const C_METHOD_ARGS_COUNT: long = 3003L
const C_METHOD_ARGS_GET: long = 3004L
const C_METHOD_ARG_LENGTH: long = 3005L
const C_METHOD_ARG_BYTE: long = 3006L
const C_METHOD_FS_LIST: long = 3007L
const C_METHOD_FS_JOIN: long = 3008L
const C_METHOD_FS_READ: long = 3009L
const C_METHOD_FS_WRITE: long = 3010L
const C_METHOD_OUT_WRITE: long = 3011L

fn emit_context_runtime_symbol(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    core_name: Ascii max 64,
    c_name: Ascii max 64,
) {
    ir_push_byte(compiler, ir, 64)
    if compiler.c_runtime { ir_write_ascii(compiler, ir, c_name) }
    else { ir_write_ascii(compiler, ir, core_name) }
}

fn c_runtime_environment_field_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    token: long,
) -> long {
    if !compiler.c_runtime { return 0L }
    if token_is_word_at(source, tokens, files, file_index, token, "fs") { 1L }
    else if token_is_word_at(source, tokens, files, file_index, token, "out") { 2L }
    else if token_is_word_at(source, tokens, files, file_index, token, "err") { 3L }
    else { 0L }
}

fn c_runtime_environment_field_type(field_kind: long) -> long {
    if field_kind == 1L { TY_FS }
    else if field_kind == 2L || field_kind == 3L { TY_OUT }
    else { -1L }
}

fn emit_c_runtime_environment_field(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let receiver = compiler.child_first[node]
    ir_write_ascii(compiler, ir, "  %v")
    ir_write_number(compiler, ir, node)
    if compiler.facts[node].literal == 1L {
        ir_write_ascii(compiler, ir, " = call ptr @nl_env_fs(ptr ")
        ir_write_value_ref(compiler, ir, receiver)
        ir_write_ascii(compiler, ir, ")\n")
    } else {
        ir_write_ascii(compiler, ir, " = call ptr @nl_env_out(ptr ")
        ir_write_value_ref(compiler, ir, receiver)
        ir_write_ascii(compiler, ir, if compiler.facts[node].literal == 2L { ", i32 1)\n" } else { ", i32 2)\n" })
    }
}

fn emit_c_main_function(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    config: MemoryConfig,
    entry: long,
) {
    let entry_file = if entry >= 0L { compiler.functions[entry].file } else { 0L }
    let entry_name = files[entry_file].name
    ir_write_ascii(compiler, ir, "define i32 @main(i32 %argc, ptr %argv, ptr %envp, ptr %auxv) {\nentry:\n  %nl.ctx = call ptr @nl_context_create(i64 4096, i64 ")
    ir_write_number(compiler, ir, config.recursion_budget)
    ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds ([")
    ir_write_number(compiler, ir, entry_name.count() + 1L)
    ir_write_ascii(compiler, ir, " x i8], ptr @.nl.file.")
    ir_write_number(compiler, ir, entry_file)
    ir_write_ascii(compiler, ir, ", i64 0, i64 0))\n  %nl.env = call ptr @nl_env_create(i32 %argc, ptr %argv, i32 ")
    ir_write_number(compiler, ir, config.capability_mask)
    ir_write_ascii(compiler, ir, ")\n")
    for file_index in 0L..files.count() {
        ir_write_ascii(compiler, ir, "  call void @nl_register_file(i32 ")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.file.")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0))\n")
    }
    ir_write_ascii(compiler, ir, "  %nl.top = call i64 @nl_context_base_offset(ptr %nl.ctx)\n")
    if compiler.tests.count() > 0L {
        ir_write_ascii(compiler, ir, "  %nl.selected = call i32 @nl_test_selected_index()\n  switch i32 %nl.selected, label %nl.program [\n")
        for test_index in 0L..compiler.tests.count() {
            ir_write_ascii(compiler, ir, "    i32 ")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ", label %nl.test.run.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for test_index in 0L..compiler.tests.count() {
            ir_write_ascii(compiler, ir, "nl.test.run.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ":\n  call void @nl_set_test_mode()\n  %nl.test.result.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, " = call i32 @nl_fn_")
            ir_write_number(compiler, ir, compiler.functions.count() + test_index)
            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top)\n  call void @nl_env_destroy(ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 %nl.test.result.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "nl.program:\n")
    }
    if entry >= 0L {
        ir_write_ascii(compiler, ir, "  call void @nl_fn_")
        ir_write_number(compiler, ir, entry)
        if compiler.functions[entry].param_count == 1L {
            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top, ptr %nl.env)\n")
        } else { ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top)\n") }
    }
    ir_write_ascii(compiler, ir, "  call void @nl_env_destroy(ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 0\n}\n")
}

fn c_runtime_method_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    token: long,
    receiver_type: long,
) -> long {
    if !compiler.c_runtime { return C_METHOD_NONE }
    if receiver_type == TY_ENV {
        if token_is_word_at(source, tokens, files, file_index, token, "args") { C_METHOD_ENV_ARGS }
        else if token_is_word_at(source, tokens, files, file_index, token, "exit") { C_METHOD_ENV_EXIT }
        else { C_METHOD_NONE }
    } else if receiver_type == TY_ARGS {
        if token_is_word_at(source, tokens, files, file_index, token, "count") { C_METHOD_ARGS_COUNT }
        else if token_is_word_at(source, tokens, files, file_index, token, "get") { C_METHOD_ARGS_GET }
        else { C_METHOD_NONE }
    } else if receiver_type == TY_ARG {
        if token_is_word_at(source, tokens, files, file_index, token, "count") ||
            token_is_word_at(source, tokens, files, file_index, token, "len") { C_METHOD_ARG_LENGTH }
        else if token_is_word_at(source, tokens, files, file_index, token, "get") { C_METHOD_ARG_BYTE }
        else { C_METHOD_NONE }
    } else if receiver_type == TY_FS {
        if token_is_word_at(source, tokens, files, file_index, token, "list_with_extension") { C_METHOD_FS_LIST }
        else if token_is_word_at(source, tokens, files, file_index, token, "join") { C_METHOD_FS_JOIN }
        else if token_is_word_at(source, tokens, files, file_index, token, "read") { C_METHOD_FS_READ }
        else if token_is_word_at(source, tokens, files, file_index, token, "write") { C_METHOD_FS_WRITE }
        else { C_METHOD_NONE }
    } else if receiver_type == TY_OUT && token_is_word_at(source, tokens, files, file_index, token, "write") {
        C_METHOD_OUT_WRITE
    } else { C_METHOD_NONE }
}

fn c_runtime_child_expected(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    method_token: long,
    receiver_type: long,
    argument_index: long,
) -> long {
    let method = c_runtime_method_kind(source, tokens, files, compiler, file_index, method_token, receiver_type)
    if method == C_METHOD_ENV_EXIT && argument_index == 0L { TY_INT }
    else if (method == C_METHOD_ARGS_GET || method == C_METHOD_ARG_BYTE) && argument_index == 0L { TY_LONG }
    else { -1L }
}

fn c_runtime_io_error_type(compiler: CompilerTables) -> long {
    builtin_synthetic_type_id(compiler, -4L)
}

fn c_runtime_io_result_type(compiler: write CompilerTables, file_index: long, node: long) -> long {
    let error_type = c_runtime_io_error_type(compiler)
    if error_type < 0L { return -1L }
    let result_type = intern_sum_type(compiler, TYPE_KIND_RESULT, TY_UNIT, error_type, file_index, node, -1L, -1L)
    if sum_layout_has_invalid_overflow(compiler, result_type) { -1L } else { result_type }
}

fn c_runtime_writable_argument(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    if !is_assignable_place(tables, node) { return false }
    let binding = place_root_binding(tables, compiler, node)
    binding >= 0L && binding < compiler.bindings.count() &&
        (compiler.bindings[binding].mutable || binding_is_write_parameter(compiler, binding) || binding_is_grow_parameter(compiler, binding))
}

fn c_runtime_check_method(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    node: long,
    scope: long,
    receiver_type: long,
    expected: long,
) -> long {
    let method_token = tables.nodes[node].token
    let method = c_runtime_method_kind(source, tokens, files, compiler, file_index, method_token, receiver_type)
    if method == C_METHOD_NONE { return -1L }
    let actual_count = count_children(tables, compiler, node) - 1L
    let wanted_count = if method == C_METHOD_ENV_ARGS || method == C_METHOD_ARGS_COUNT || method == C_METHOD_ARG_LENGTH { 0L }
        else if method == C_METHOD_ENV_EXIT || method == C_METHOD_ARGS_GET || method == C_METHOD_ARG_BYTE || method == C_METHOD_OUT_WRITE { 1L }
        else if method == C_METHOD_FS_LIST { 3L } else { 2L }
    if actual_count != wanted_count {
        fail_at_message(env, files, compiler, file_index, tables.nodes[node].start, "C-runtime capability method has the wrong number of arguments")
    }
    let first = child_at(tables, compiler, node, 1L)
    let second = child_at(tables, compiler, node, 2L)
    let third = child_at(tables, compiler, node, 3L)
    var result_type = TY_UNIT
    if method == C_METHOD_ENV_ARGS {
        result_type = TY_ARGS
    } else if method == C_METHOD_ENV_EXIT {
        require_type(env, files, compiler, file_index, first, TY_INT, compiler.facts[first].ty, tables)
        result_type = TY_NEVER
    } else if method == C_METHOD_ARGS_COUNT {
        result_type = TY_LONG
    } else if method == C_METHOD_ARGS_GET {
        require_type(env, files, compiler, file_index, first, TY_LONG, compiler.facts[first].ty, tables)
        result_type = intern_sum_type(compiler, TYPE_KIND_OPTION, TY_ARG, -1L, file_index, node, -1L, -1L)
    } else if method == C_METHOD_ARG_LENGTH {
        result_type = TY_LONG
    } else if method == C_METHOD_ARG_BYTE {
        require_type(env, files, compiler, file_index, first, TY_LONG, compiler.facts[first].ty, tables)
        result_type = intern_sum_type(compiler, TYPE_KIND_OPTION, TY_BYTE, -1L, file_index, node, -1L, -1L)
    } else if method == C_METHOD_FS_LIST {
        if compiler.facts[first].ty != TY_ARG {
            fail_at_message(env, files, compiler, file_index, tables.nodes[first].start, "Fs.list_with_extension needs an Arg directory")
        }
        let extension_kind = type_kind(compiler, compiler.facts[second].ty)
        if extension_kind != TYPE_KIND_ASCII && extension_kind != TYPE_KIND_TEXT && extension_kind != TYPE_KIND_BYTES {
            fail_at_message(env, files, compiler, file_index, tables.nodes[second].start, "Fs.list_with_extension needs a bounded text extension")
        }
        let entry_type = builtin_synthetic_type_id(compiler, -7L)
        let output_type = compiler.facts[third].ty
        if type_kind(compiler, output_type) != TYPE_KIND_LIST || collection_element_type(compiler, output_type) != entry_type ||
            collection_capacity(compiler, output_type) > 4096L {
            fail_at_message(env, files, compiler, file_index, tables.nodes[third].start, "Fs.list_with_extension needs a bounded list<DirEntry, N> with N at most 4096")
        }
        if !c_runtime_writable_argument(tables, compiler, third) {
            fail_at_message(env, files, compiler, file_index, tables.nodes[third].start, "Fs.list_with_extension needs a writable directory-entry list")
        }
        if active_view_overlaps_place(tables, compiler, scope, third) {
            fail_at_message(env, files, compiler, file_index, tables.nodes[third].start, "cannot replace storage that contains a live collection view")
        }
        result_type = c_runtime_io_result_type(compiler, file_index, node)
    } else if method == C_METHOD_FS_JOIN {
        let path_type = collection_type_matches(compiler, TYPE_KIND_LIST, TY_BYTE, 4096L)
        let dir_type = compiler.facts[first].ty
        let name_type = compiler.facts[second].ty
        let dir_is_ascii = type_kind(compiler, dir_type) == TYPE_KIND_ASCII
        let name_is_ascii = type_kind(compiler, name_type) == TYPE_KIND_ASCII
        if dir_type != TY_ARG && dir_type != path_type && !dir_is_ascii {
            fail_at_message(env, files, compiler, file_index, tables.nodes[first].start, "Fs.join needs an Arg, Path, or Ascii directory")
        }
        if name_type != TY_ARG && name_type != path_type && !name_is_ascii {
            fail_at_message(env, files, compiler, file_index, tables.nodes[second].start, "Fs.join needs an Arg, Path, or Ascii name")
        }
        let error_type = c_runtime_io_error_type(compiler)
        if error_type < 0L { return -1L }
        result_type = intern_sum_type(compiler, TYPE_KIND_RESULT, path_type, error_type, file_index, node, -1L, -1L)
    } else if method == C_METHOD_FS_READ {
        let path_type = collection_type_matches(compiler, TYPE_KIND_LIST, TY_BYTE, 4096L)
        if compiler.facts[first].ty != path_type {
            fail_at_message(env, files, compiler, file_index, tables.nodes[first].start, "Fs.read needs a Path")
        }
        if type_kind(compiler, compiler.facts[second].ty) != TYPE_KIND_BYTES {
            fail_at_message(env, files, compiler, file_index, tables.nodes[second].start, "Fs.read needs a Bytes destination")
        }
        if !c_runtime_writable_argument(tables, compiler, second) {
            fail_at_message(env, files, compiler, file_index, tables.nodes[second].start, "Fs.read needs a writable Bytes destination")
        }
        if active_view_overlaps_place(tables, compiler, scope, second) {
            fail_at_message(env, files, compiler, file_index, tables.nodes[second].start, "cannot replace storage that contains a live collection view")
        }
        result_type = c_runtime_io_result_type(compiler, file_index, node)
    } else if method == C_METHOD_FS_WRITE {
        let path_type = collection_type_matches(compiler, TYPE_KIND_LIST, TY_BYTE, 4096L)
        if compiler.facts[first].ty != TY_ARG && compiler.facts[first].ty != path_type {
            fail_at_message(env, files, compiler, file_index, tables.nodes[first].start, "Fs.write needs an Arg or Path destination")
        }
        if type_kind(compiler, compiler.facts[second].ty) != TYPE_KIND_BYTES {
            fail_at_message(env, files, compiler, file_index, tables.nodes[second].start, "Fs.write needs Bytes data")
        }
        result_type = c_runtime_io_result_type(compiler, file_index, node)
    } else if method == C_METHOD_OUT_WRITE {
        let data_type = compiler.facts[first].ty
        if data_type != TY_ARG && type_kind(compiler, data_type) != TYPE_KIND_ASCII &&
            type_kind(compiler, data_type) != TYPE_KIND_TEXT && type_kind(compiler, data_type) != TYPE_KIND_BYTES {
            fail_at_message(env, files, compiler, file_index, tables.nodes[first].start, "Out.write needs an Arg or bounded text value")
        }
        result_type = c_runtime_io_result_type(compiler, file_index, node)
    } else { return -1L }
    if result_type < 0L || sum_layout_has_invalid_overflow(compiler, result_type) {
        fail_at_message(env, files, compiler, file_index, tables.nodes[node].start, "C-runtime capability result type exceeds compiler capacity")
    }
    if expected >= 0L && expected != result_type {
        require_type(env, files, compiler, file_index, node, expected, result_type, tables)
    }
    result_type
}

fn emit_c_join_ascii_descriptor_storage(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    label: Ascii max 8,
) {
    ir_write_ascii(compiler, ir, "  %c.join.descriptor.")
    ir_write_ascii(compiler, ir, label)
    ir_write_ascii(compiler, ir, ".")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = alloca [16 x i8], align 8\n")
}

fn emit_c_runtime_method_storage(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    if !compiler.c_runtime || tables.nodes[node].kind != NodeKind.MethodCall { return }
    let receiver = compiler.child_first[node]
    if receiver < 0L { return }
    let method = c_runtime_method_kind(source, tokens, files, compiler, file_index, tables.nodes[node].token, compiler.facts[receiver].ty)
    if method == C_METHOD_FS_JOIN {
        let dir = child_at(tables, compiler, node, 1L)
        let name = child_at(tables, compiler, node, 2L)
        if type_kind(compiler, compiler.facts[dir].ty) == TYPE_KIND_ASCII {
            emit_c_join_ascii_descriptor_storage(compiler, ir, node, "dir")
        }
        if type_kind(compiler, compiler.facts[name].ty) == TYPE_KIND_ASCII {
            emit_c_join_ascii_descriptor_storage(compiler, ir, node, "name")
        }
        return
    }
    let data_argument = if method == C_METHOD_FS_WRITE { child_at(tables, compiler, node, 2L) }
        else if method == C_METHOD_OUT_WRITE { child_at(tables, compiler, node, 1L) }
        else { -1L }
    if data_argument >= 0L && compiler.facts[data_argument].ty != TY_ARG {
        ir_write_ascii(compiler, ir, "  %c.raw.descriptor."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = alloca [16 x i8], align 8\n")
    }
}

fn emit_c_raw_descriptor(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    value: long,
) {
    let value_type = compiler.facts[value].ty
    let location = c_runtime_argument_source_location(tables, compiler, ir, value)
    let pointer = emit_location_pointer_materialization(compiler, ir, location)
    let data_offset = text_location_data_offset(compiler, value_type, location)
    emit_text_source_length(compiler, ir, location, pointer, node, "c.raw")
    ir_write_ascii(compiler, ir, "  %c.raw.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, data_offset); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %c.raw.descriptor.pointer."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr inbounds [16 x i8], ptr %c.raw.descriptor.")
    ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 0, i64 0\n")
    ir_write_ascii(compiler, ir, "  store ptr %c.raw.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %c.raw.descriptor.pointer."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n")
    ir_write_ascii(compiler, ir, "  %c.raw.length.pointer."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr inbounds i8, ptr %c.raw.descriptor.pointer."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 8\n")
    ir_write_ascii(compiler, ir, "  store i64 %text.c.raw.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %c.raw.length.pointer."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n")
}

fn c_runtime_argument_source_location(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) -> StorageLocation {
    if node >= 0L && node < tables.nodes.count() && tables.nodes[node].kind == NodeKind.Field &&
        type_kind(compiler, compiler.facts[node].ty) == TYPE_KIND_BYTES &&
        place_root_binding(tables, compiler, node) >= 0L {
        let address_id = emit_late_place_address(tables, compiler, ir, node)
        native_location(2L, address_id, 0L)
    } else {
        direct_call_argument_source_location(tables, compiler, node)
    }
}

fn c_runtime_writable_parameter_binding(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    if node < 0L || node >= tables.nodes.count() || tables.nodes[node].kind != NodeKind.Name { return -1L }
    let binding = compiler.facts[node].binding
    if binding >= 0L && binding < compiler.bindings.count() && compiler.bindings[binding].parameter &&
        !binding_is_view(compiler, binding) && is_aggregate_type(compiler, compiler.bindings[binding].ty) &&
        (binding_is_write_parameter(compiler, binding) || binding_is_grow_parameter(compiler, binding)) {
        binding
    } else { -1L }
}

fn c_runtime_indexed_writable_bytes_location(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    location: StorageLocation,
) -> StorageLocation {
    if location.copies <= 1L || location.index_node == -1L || location.index_stride <= 0L {
        return location
    }
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
    let address_id = MAX_TREE_NODES * 1024L + next_location_serial(ir) * MAX_TREE_NODES + node
    ir_write_ascii(compiler, ir, "  %c.write.bytes.index."); ir_write_number(compiler, ir, address_id)
    ir_write_ascii(compiler, ir, " = mul i64 "); emit_location_index_value(compiler, ir, location)
    ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.index_stride); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %c.write.bytes.offset."); ir_write_number(compiler, ir, address_id)
    ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, location.byte_offset)
    ir_write_ascii(compiler, ir, ", %c.write.bytes.index."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, base, pointer)
    ir_write_ascii(compiler, ir, ", i64 %c.write.bytes.offset."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
    native_location(2L, address_id, 0L)
}

fn c_runtime_writable_output_location(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) -> StorageLocation {
    let type_id = compiler.facts[node].ty
    let binding = c_runtime_writable_parameter_binding(tables, compiler, node)
    if type_kind(compiler, type_id) == TYPE_KIND_BYTES && tables.nodes[node].kind == NodeKind.Field &&
        place_root_binding(tables, compiler, node) >= 0L {
        return c_runtime_argument_source_location(tables, compiler, ir, node)
    }
    if binding >= 0L && type_kind(compiler, type_id) == TYPE_KIND_BYTES {
        let base = compiler_location(compiler, 3L, binding, 0L)
        let pointer = emit_location_pointer_materialization(compiler, ir, base)
        let stride = value_type_size(compiler, type_id)
        let address_id = MAX_TREE_NODES * 1024L + next_location_serial(ir) * MAX_TREE_NODES + node
        ir_write_ascii(compiler, ir, "  %c.write.bytes.offset."); ir_write_number(compiler, ir, address_id)
        ir_write_ascii(compiler, ir, " = mul i64 %arg.index."); ir_write_number(compiler, ir, binding)
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, base, pointer)
        ir_write_ascii(compiler, ir, ", i64 %c.write.bytes.offset."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
        return native_location(2L, address_id, 0L)
    }
    if binding >= 0L && type_kind(compiler, type_id) == TYPE_KIND_LIST &&
        is_c_runtime_dir_entry_type(compiler, collection_element_type(compiler, type_id)) {
        return compiler_location(compiler, 3L, binding, 0L)
    }
    let location = place_storage_location(tables, compiler, node)
    if type_kind(compiler, type_id) == TYPE_KIND_BYTES {
        return c_runtime_indexed_writable_bytes_location(compiler, ir, node, location)
    }
    location
}

fn emit_c_join_ascii_descriptor(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    label: Ascii max 8,
    value: long,
) {
    let value_type = compiler.facts[value].ty
    let location = c_runtime_argument_source_location(tables, compiler, ir, value)
    let pointer = emit_location_pointer_materialization(compiler, ir, location)
    let data_offset = text_location_data_offset(compiler, value_type, location)
    let length_label: Ascii max 24 = "c.join." + label
    emit_text_source_length(compiler, ir, location, pointer, node, length_label)
    ir_write_ascii(compiler, ir, "  %c.join.data.")
    ir_write_ascii(compiler, ir, label)
    ir_write_ascii(compiler, ir, ".")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
    emit_location_pointer_reference(compiler, ir, location, pointer)
    ir_write_ascii(compiler, ir, ", i64 ")
    ir_write_number(compiler, ir, data_offset)
    ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %c.join.descriptor.pointer.")
    ir_write_ascii(compiler, ir, label)
    ir_write_ascii(compiler, ir, ".")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr inbounds [16 x i8], ptr %c.join.descriptor.")
    ir_write_ascii(compiler, ir, label)
    ir_write_ascii(compiler, ir, ".")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 0, i64 0\n  store ptr %c.join.data.")
    ir_write_ascii(compiler, ir, label)
    ir_write_ascii(compiler, ir, ".")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %c.join.descriptor.pointer.")
    ir_write_ascii(compiler, ir, label)
    ir_write_ascii(compiler, ir, ".")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", align 8\n  %c.join.length.pointer.")
    ir_write_ascii(compiler, ir, label)
    ir_write_ascii(compiler, ir, ".")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr inbounds i8, ptr %c.join.descriptor.pointer.")
    ir_write_ascii(compiler, ir, label)
    ir_write_ascii(compiler, ir, ".")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 8\n  store i64 %text.")
    ir_write_ascii(compiler, ir, length_label)
    ir_write_ascii(compiler, ir, ".length.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %c.join.length.pointer.")
    ir_write_ascii(compiler, ir, label)
    ir_write_ascii(compiler, ir, ".")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", align 8\n")
}

fn emit_c_runtime_method_call(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let receiver = compiler.child_first[node]
    if receiver < 0L { compiler.ir_overflow = true; return }
    let method = compiler.facts[node].literal
    let first = child_at(tables, compiler, node, 1L)
    let second = child_at(tables, compiler, node, 2L)
    let third = child_at(tables, compiler, node, 3L)
    if method == C_METHOD_ENV_ARGS {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call ptr @nl_env_args(ptr "); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, ")\n")
    } else if method == C_METHOD_ENV_EXIT {
        ir_write_ascii(compiler, ir, "  call void @nl_env_exit(i32 "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ")\n  unreachable\n")
    } else if method == C_METHOD_ARGS_COUNT {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i64 @nl_args_count(ptr "); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, ")\n")
    } else if method == C_METHOD_ARGS_GET {
        let result_location = aggregate_destination_location(compiler, 0L, node)
        let result_pointer = emit_location_pointer_materialization(compiler, ir, result_location)
        ir_write_ascii(compiler, ir, "  %c.arg.value."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call ptr @nl_args_get(ptr "); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ")\n")
        ir_write_ascii(compiler, ir, "  %c.arg.present."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = icmp ne ptr %c.arg.value."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 44); ir_write_ascii(compiler, ir, " null\n  %c.arg.tag."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = select i1 %c.arg.present."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i32 0, i32 1\n  store i32 %c.arg.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr ")
        emit_location_pointer_reference(compiler, ir, result_location, result_pointer); ir_write_ascii(compiler, ir, ", align 1\n")
        ir_write_ascii(compiler, ir, "  %c.arg.payload."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr inbounds i8, ptr "); emit_location_pointer_reference(compiler, ir, result_location, result_pointer); ir_write_ascii(compiler, ir, ", i64 8\n  %c.arg.payload.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 %c.arg.present."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %c.arg.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr null\n  store ptr %c.arg.payload.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %c.arg.payload."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    } else if method == C_METHOD_ARG_LENGTH {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i64 @nl_arg_length(ptr "); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, ")\n")
    } else if method == C_METHOD_ARG_BYTE {
        let result_location = aggregate_destination_location(compiler, 0L, node)
        let result_pointer = emit_location_pointer_materialization(compiler, ir, result_location)
        ir_write_ascii(compiler, ir, "  %c.arg.byte."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i32 @nl_arg_byte(ptr "); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ")\n  %c.arg.byte.present."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sge i32 %c.arg.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n  %c.arg.byte.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 %c.arg.byte.present."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i32 0, i32 1\n  store i32 %c.arg.byte.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, result_location, result_pointer); ir_write_ascii(compiler, ir, ", align 1\n")
        ir_write_ascii(compiler, ir, "  %c.arg.byte.payload."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr inbounds i8, ptr "); emit_location_pointer_reference(compiler, ir, result_location, result_pointer); ir_write_ascii(compiler, ir, ", i64 4\n  %c.arg.byte.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 %c.arg.byte.present."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i32 %c.arg.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i32 0\n  store i32 %c.arg.byte.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %c.arg.byte.payload."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    } else if method == C_METHOD_FS_LIST {
        let extension_type = compiler.facts[second].ty
        let extension_location = c_runtime_argument_source_location(tables, compiler, ir, second)
        let extension_pointer = emit_location_pointer_materialization(compiler, ir, extension_location)
        let extension_data_offset = text_location_data_offset(compiler, extension_type, extension_location)
        emit_text_source_length(compiler, ir, extension_location, extension_pointer, node, "c.extension")
        ir_write_ascii(compiler, ir, "  %c.extension.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, extension_location, extension_pointer); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, extension_data_offset); ir_push_byte(compiler, ir, 10)
        let output_location = c_runtime_writable_output_location(tables, compiler, ir, third)
        let output_pointer = emit_location_pointer_materialization(compiler, ir, output_location)
        let result_location = aggregate_destination_location(compiler, 0L, node)
        let result_pointer = emit_location_pointer_materialization(compiler, ir, result_location)
        ir_write_ascii(compiler, ir, "  call void @nlc_fs_list_with_extension(ptr %nl.ctx, ptr "); ir_write_value_ref(compiler, ir, receiver)
        ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ", i32 1, i64 0, ptr %c.extension.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.c.extension.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, output_location, output_pointer); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, collection_capacity(compiler, compiler.facts[third].ty)); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, result_location, result_pointer); ir_write_ascii(compiler, ir, ")\n")
    } else if method == C_METHOD_FS_JOIN {
        let path_type = collection_type_matches(compiler, TYPE_KIND_LIST, TY_BYTE, 4096L)
        let dir_type = compiler.facts[first].ty
        let name_type = compiler.facts[second].ty
        let dir_is_ascii = type_kind(compiler, dir_type) == TYPE_KIND_ASCII
        let name_is_ascii = type_kind(compiler, name_type) == TYPE_KIND_ASCII
        var dir_kind = 0L
        var dir_capacity = 0L
        var dir_pointer = -1L
        var dir_location = native_location(0L, -1L, 0L)
        if dir_type == TY_ARG {
            dir_kind = 1L
        } else if dir_is_ascii {
            dir_kind = 2L
            dir_capacity = text_max_bytes(compiler, dir_type)
            emit_c_join_ascii_descriptor(tables, compiler, ir, node, "dir", first)
        } else {
            dir_capacity = collection_capacity(compiler, dir_type)
            dir_location = c_runtime_argument_source_location(tables, compiler, ir, first)
            dir_pointer = emit_location_pointer_materialization(compiler, ir, dir_location)
        }
        var name_kind = 0L
        var name_capacity = 0L
        var name_pointer = -1L
        var name_location = native_location(0L, -1L, 0L)
        if name_type == TY_ARG {
            name_kind = 1L
        } else if name_is_ascii {
            name_kind = 2L
            name_capacity = text_max_bytes(compiler, name_type)
            emit_c_join_ascii_descriptor(tables, compiler, ir, node, "name", second)
        } else {
            name_capacity = collection_capacity(compiler, name_type)
            name_location = c_runtime_argument_source_location(tables, compiler, ir, second)
            name_pointer = emit_location_pointer_materialization(compiler, ir, name_location)
        }
        let result_location = aggregate_destination_location(compiler, 0L, node)
        let result_pointer = emit_location_pointer_materialization(compiler, ir, result_location)
        ir_write_ascii(compiler, ir, "  call void @nlc_fs_join(ptr %nl.ctx, ptr "); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, ", ptr ")
        if dir_kind == 1L { ir_write_value_ref(compiler, ir, first) }
        else if dir_kind == 2L { ir_write_ascii(compiler, ir, "%c.join.descriptor.pointer.dir."); ir_write_number(compiler, ir, node) }
        else { emit_location_pointer_reference(compiler, ir, dir_location, dir_pointer) }
        ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, dir_kind); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, dir_capacity); ir_write_ascii(compiler, ir, ", ptr ")
        if name_kind == 1L { ir_write_value_ref(compiler, ir, second) }
        else if name_kind == 2L { ir_write_ascii(compiler, ir, "%c.join.descriptor.pointer.name."); ir_write_number(compiler, ir, node) }
        else { emit_location_pointer_reference(compiler, ir, name_location, name_pointer) }
        ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, name_kind); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, name_capacity); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, result_location, result_pointer); ir_write_ascii(compiler, ir, ")\n")
    } else if method == C_METHOD_FS_READ {
        let path_location = c_runtime_argument_source_location(tables, compiler, ir, first)
        let path_pointer = emit_location_pointer_materialization(compiler, ir, path_location)
        let destination_location = c_runtime_writable_output_location(tables, compiler, ir, second)
        let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination_location)
        let result_location = aggregate_destination_location(compiler, 0L, node)
        let result_pointer = emit_location_pointer_materialization(compiler, ir, result_location)
        ir_write_ascii(compiler, ir, "  %c.fs.read.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr inbounds i8, ptr "); emit_location_pointer_reference(compiler, ir, destination_location, destination_pointer); ir_write_ascii(compiler, ir, ", i64 8\n")
        ir_write_ascii(compiler, ir, "  call void @nl_fs_read_string(ptr "); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, path_location, path_pointer); ir_write_ascii(compiler, ir, ", i32 0, i64 4096, ptr %c.fs.read.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, text_max_bytes(compiler, compiler.facts[second].ty)); ir_write_ascii(compiler, ir, ", i32 0, i64 0, ptr "); emit_location_pointer_reference(compiler, ir, destination_location, destination_pointer); ir_write_ascii(compiler, ir, ", ptr null, ptr "); emit_location_pointer_reference(compiler, ir, result_location, result_pointer); ir_write_ascii(compiler, ir, ")\n")
    } else if method == C_METHOD_FS_WRITE {
        let path_type = collection_type_matches(compiler, TYPE_KIND_LIST, TY_BYTE, 4096L)
        let path_is_arg = compiler.facts[first].ty == TY_ARG
        let path_location = if path_is_arg { native_location(0L, -1L, 0L) } else { c_runtime_argument_source_location(tables, compiler, ir, first) }
        let path_pointer = if path_is_arg { -1L } else { emit_location_pointer_materialization(compiler, ir, path_location) }
        let result_location = aggregate_destination_location(compiler, 0L, node)
        let result_pointer = emit_location_pointer_materialization(compiler, ir, result_location)
        emit_c_raw_descriptor(tables, compiler, ir, node, second)
        ir_write_ascii(compiler, ir, "  call void @nl_fs_write(ptr "); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, ", ptr ")
        if path_is_arg { ir_write_value_ref(compiler, ir, first) } else { emit_location_pointer_reference(compiler, ir, path_location, path_pointer) }
        ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, if path_is_arg { 1L } else { 0L }); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, if path_is_arg { 0L } else { collection_capacity(compiler, path_type) }); ir_write_ascii(compiler, ir, ", ptr %c.raw.descriptor.pointer."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i32 2, i64 "); ir_write_number(compiler, ir, text_max_bytes(compiler, compiler.facts[second].ty)); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, result_location, result_pointer); ir_write_ascii(compiler, ir, ")\n")
    } else if method == C_METHOD_OUT_WRITE {
        let result_location = aggregate_destination_location(compiler, 0L, node)
        let result_pointer = emit_location_pointer_materialization(compiler, ir, result_location)
        let data_type = compiler.facts[first].ty
        if data_type == TY_ARG {
            ir_write_ascii(compiler, ir, "  call void @nl_out_write(ptr "); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ", i32 1, i64 0, i32 0, ptr "); emit_location_pointer_reference(compiler, ir, result_location, result_pointer); ir_write_ascii(compiler, ir, ")\n")
        } else {
            emit_c_raw_descriptor(tables, compiler, ir, node, first)
            ir_write_ascii(compiler, ir, "  call void @nl_out_write(ptr "); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, ", ptr %c.raw.descriptor.pointer."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i32 2, i64 "); ir_write_number(compiler, ir, text_max_bytes(compiler, data_type)); ir_write_ascii(compiler, ir, ", i32 0, ptr "); emit_location_pointer_reference(compiler, ir, result_location, result_pointer); ir_write_ascii(compiler, ir, ")\n")
        }
    } else { compiler.ir_overflow = true }
}
