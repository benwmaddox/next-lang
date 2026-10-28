fn text_type_syntax_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    syntax: Node,
) -> long {
    if token_is_word_at(source, tokens, files, file_index, syntax.token, "Ascii") { TYPE_KIND_ASCII }
    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "Text") { TYPE_KIND_TEXT }
    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "Bytes") { TYPE_KIND_BYTES }
    else { 0L }
}

fn decoded_text_is_ascii(value: Bytes max 16777217) -> bool {
    for index in 0L..value.count() {
        if value[index] >= 128 { return false }
    }
    true
}

fn decoded_text_codepoints(value: Bytes max 16777217) -> long {
    var count = 0L
    for index in 0L..value.count() {
        if value[index] < 128 || value[index] >= 192 { count += 1L }
    }
    count
}

fn text_expression_may_call(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    if node < 0L || node >= tables.nodes.count() { return false }
    let first = node - tables.nodes[node].subtree + 1L
    for child in first..node + 1L {
        let kind = tables.nodes[child].kind
        if kind == NodeKind.Call || kind == NodeKind.MethodCall { return true }
    }
    false
}

fn text_method_needs_receiver_metrics_capture(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> bool {
    if node < 0L || node >= tables.nodes.count() || tables.nodes[node].kind != NodeKind.MethodCall {
        return false
    }
    let receiver = compiler.child_first[node]
    if receiver < 0L ||
        (tables.nodes[receiver].kind != NodeKind.Name && tables.nodes[receiver].kind != NodeKind.Field) ||
        !is_aggregate_type(compiler, compiler.facts[receiver].ty) {
        return false
    }
    let kind = type_kind(compiler, compiler.facts[receiver].ty)
    if kind != TYPE_KIND_ASCII && kind != TYPE_KIND_TEXT && kind != TYPE_KIND_BYTES { return false }
    var argument = compiler.child_next[receiver]
    for step in 0L..tables.nodes.count() {
        if argument < 0L { break }
        if region_subtree_has_effect(tables, argument, argument) { return true }
        argument = compiler.child_next[argument]
    }
    false
}

fn text_method_receiver_location(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> StorageLocation {
    let receiver = compiler.child_first[node]
    aggregate_source_location(compiler,
        aggregate_source_kind(tables, compiler, receiver), aggregate_source_id(tables, compiler, receiver))
}

fn text_type_capacity_error(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    node: long,
    kind: long,
    overflow: bool,
) -> never {
    if kind == TYPE_KIND_ASCII {
        fail_at_message(env, files, compiler, file_index, node,
            if overflow { "Ascii maximum overflows long; reduce the byte count" }
            else { "Ascii maximum cannot be negative; use zero or a positive byte count" })
    } else if kind == TYPE_KIND_BYTES {
        fail_at_message(env, files, compiler, file_index, node,
            "Bytes maximum must fit a nonnegative long; reduce the byte count")
    } else {
        fail_at_message(env, files, compiler, file_index, node,
            if overflow { "Text byte maximum overflows long; reduce the code-point maximum" }
            else { "Text maxima must fit nonnegative longs; reduce the code-point or byte maximum" })
    }
}

fn is_bytes_view_value(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    node >= 0L && node < tables.nodes.count() && tables.nodes[node].kind == NodeKind.MethodCall &&
        compiler.facts[node].literal == TEXT_METHOD_BYTES
}

fn text_type_matches(compiler: CompilerTables, kind: long, max_bytes: long, max_codepoints: long) -> long {
    for type_id in 0L..type_count(compiler) {
        let record = type_record(compiler, type_id)
        if type_record_kind(record) == kind && record.field_start == max_bytes && record.field_count == max_codepoints {
            return type_id
        }
    }
    -1L
}

fn intern_text_type(
    compiler: write CompilerTables,
    kind: long,
    max_bytes: long,
    max_codepoints: long,
    file_index: long,
    node: long,
    name_id: long,
    name_token: long,
) -> long {
    let existing = text_type_matches(compiler, kind, max_bytes, max_codepoints)
    if existing >= 0L { return existing }
    if (kind != TYPE_KIND_ASCII && kind != TYPE_KIND_TEXT && kind != TYPE_KIND_BYTES) || max_bytes < 0L {
        compiler.table_failed = true
        return -1L
    }
    let header_size = if kind == TYPE_KIND_TEXT { 16L } else { 8L }
    if max_bytes > MAX_VALUE_SIZE - header_size {
        compiler.table_failed = true
        return -1L
    }
    let size = max_bytes + header_size
    let type_id = compiler.type_records.count()
    compiler.type_records.push(TypeRecord {
        kind_state: kind * 16L + 2L,
        name_id,
        name_token,
        node,
        file: file_index,
        field_start: max_bytes,
        field_count: max_codepoints,
        size,
        align: 8L,
        helper_mask: 0L,
    }).unwrap()
    type_id
}

fn text_max_bytes(compiler: CompilerTables, type_id: long) -> long {
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_ASCII || kind == TYPE_KIND_TEXT || kind == TYPE_KIND_BYTES {
        type_record(compiler, type_id).field_start
    } else { -1L }
}

fn text_max_codepoints(compiler: CompilerTables, type_id: long) -> long {
    if type_kind(compiler, type_id) == TYPE_KIND_TEXT { type_record(compiler, type_id).field_count }
    else if type_kind(compiler, type_id) == TYPE_KIND_ASCII { type_record(compiler, type_id).field_start }
    else { -1L }
}

fn text_data_offset(compiler: CompilerTables, type_id: long) -> long {
    if type_kind(compiler, type_id) == TYPE_KIND_TEXT { 16L }
    else if type_kind(compiler, type_id) == TYPE_KIND_ASCII || type_kind(compiler, type_id) == TYPE_KIND_BYTES { 8L }
    else { -1L }
}

const TEXT_METHOD_LEN: long = 2001L
const TEXT_METHOD_BYTE_LEN: long = 2002L
const TEXT_METHOD_SLICE: long = 2003L
const TEXT_METHOD_BYTES: long = 2004L
const TEXT_METHOD_CONTAINS: long = 2005L
const TEXT_METHOD_STARTS_WITH: long = 2006L
const TEXT_METHOD_VALIDATE_UTF8: long = 2007L
const TEXT_METHOD_TO_TEXT: long = 2008L
const TEXT_METHOD_TO_ASCII: long = 2009L
const TEXT_METHOD_EMPTY: long = 2010L

fn text_empty_constructor_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    scope: long,
    node: long,
) -> long {
    if node < 0L || node >= tables.nodes.count() || tables.nodes[node].kind != NodeKind.MethodCall ||
        !token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "empty") { return 0L }
    let receiver = compiler.child_first[node]
    if receiver < 0L || tables.nodes[receiver].kind != NodeKind.Name { return 0L }
    let receiver_token = tables.nodes[receiver].token
    if find_binding_in_scope(compiler, scope, compiler.token_name_ids[receiver_token]) >= 0L { return 0L }
    if token_is_word_at(source, tokens, files, file_index, receiver_token, "Ascii") { TYPE_KIND_ASCII }
    else if token_is_word_at(source, tokens, files, file_index, receiver_token, "Text") { TYPE_KIND_TEXT }
    else if token_is_word_at(source, tokens, files, file_index, receiver_token, "Bytes") { TYPE_KIND_BYTES }
    else { 0L }
}

fn emit_text_empty_value(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    is_test: bool,
) {
    let ty = compiler.facts[node].ty
    let kind = type_kind(compiler, ty)
    let destination = aggregate_destination_location(compiler, 0L, node)
    let pointer = emit_location_pointer_materialization(compiler, ir, destination)
    ir_write_ascii(compiler, ir, "  %text.empty.length.addr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer)
    ir_write_ascii(compiler, ir, ", i64 0\n  store i64 0, ptr %text.empty.length.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1")
    emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
    if kind == TYPE_KIND_TEXT {
        ir_write_ascii(compiler, ir, "  %text.empty.points.addr."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer)
        ir_write_ascii(compiler, ir, ", i64 8\n  store i64 0, ptr %text.empty.points.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1")
        emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        if is_test {
            ir_write_ascii(compiler, ir, "  %text.empty.data."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer)
            ir_write_ascii(compiler, ir, ", i64 16\n  call void @nl_core_nl_text_assert_valid(ptr %nl.ctx, ptr %text.empty.data."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ", i64 0)\n")
        }
    }
}

fn emit_text_bytes_view(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    is_test: bool,
) {
    ir_write_ascii(compiler, ir, "  br label %text.bytes.init."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.bytes.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    let receiver = compiler.child_first[node]
    let receiver_ty = compiler.facts[receiver].ty
    let source = text_method_receiver_location(tables, compiler, node)
    let destination = aggregate_destination_location(compiler, 0L, node)
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    let maximum = text_max_bytes(compiler, receiver_ty)
    if maximum < 0L { compiler.ir_overflow = true; return }
    emit_text_source_length(compiler, ir, source, source_pointer, node, "bytes")
    ir_write_ascii(compiler, ir, ", align 1\n  %text.bytes.length.dst."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 0\n  store i64 %text.bytes.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %text.bytes.length.dst."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %text.bytes.source.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source, source_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, text_location_data_offset(compiler, receiver_ty, source))
    ir_write_ascii(compiler, ir, "\n  %text.bytes.destination.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 8\n  br label %text.bytes.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.bytes.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.bytes.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = phi i64 [ 0, %text.bytes.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ], [ %text.bytes.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.bytes.increment."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " ]\n  %text.bytes.more."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ult i64 %text.bytes.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.bytes.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br i1 %text.bytes.more."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.bytes.body."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.bytes.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.bytes.body."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.bytes.src.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.bytes.source.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %text.bytes.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.bytes.value."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i8, ptr %text.bytes.src.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", align 1\n  %text.bytes.dst.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.bytes.destination.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %text.bytes.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  store i8 %text.bytes.value."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %text.bytes.dst.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", align 1\n  br label %text.bytes.increment."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.bytes.increment."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.bytes.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = add i64 %text.bytes.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", 1\n  br label %text.bytes.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.bytes.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if maximum < 0L { compiler.ir_overflow = true }
}

fn emit_text_literal_value(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    is_test: bool,
) {
    let syntax = tables.nodes[node]
    let kind = type_kind(compiler, compiler.facts[node].ty)
    var literal: Bytes max 16777217 = Bytes.empty()
    if syntax.kind == NodeKind.BytesLiteral {
        literal = decode_string_token(source, tokens, files[file_index].base, syntax.extra, true)
    } else {
        literal = decode_string_token(source, tokens, files[file_index].base, syntax.token, false)
    }
    if compiler.core_mode {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr ["); ir_write_number(compiler, ir, literal.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8], ptr "); emit_text_literal_global_reference(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0\n")
        return
    }
    let data_offset = text_data_offset(compiler, compiler.facts[node].ty)
    let points = if kind == TYPE_KIND_TEXT { decoded_text_codepoints(literal) } else { 0L }
    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    if kind == TYPE_KIND_TEXT {
        ir_write_ascii(compiler, ir, "  %text.literal.byte.length.addr."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
        ir_write_ascii(compiler, ir, ", i64 0\n  store i64 "); ir_write_number(compiler, ir, literal.count())
        ir_write_ascii(compiler, ir, ", ptr %text.literal.byte.length.addr."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %text.literal.point.length.addr."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
        ir_write_ascii(compiler, ir, ", i64 8\n  store i64 "); ir_write_number(compiler, ir, points)
        ir_write_ascii(compiler, ir, ", ptr %text.literal.point.length.addr."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    } else {
        ir_write_ascii(compiler, ir, "  %text.literal.length.addr."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
        ir_write_ascii(compiler, ir, ", i64 0\n  store i64 "); ir_write_number(compiler, ir, literal.count())
        ir_write_ascii(compiler, ir, ", ptr %text.literal.length.addr."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    }
    ir_write_ascii(compiler, ir, "  %text.literal.source.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr ["); ir_write_number(compiler, ir, literal.count() + 1L)
    ir_write_ascii(compiler, ir, " x i8], ptr "); emit_text_literal_global_reference(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 0, i64 0\n  %text.literal.destination.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, data_offset)
    ir_write_ascii(compiler, ir, "\n  br label %text.literal.entry."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.literal.entry."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  br label %text.literal.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.literal.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.literal.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = phi i64 [ 0, %text.literal.entry."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " ], [ %text.literal.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.literal.increment."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " ]\n  %text.literal.more."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ult i64 %text.literal.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, literal.count())
    ir_write_ascii(compiler, ir, "\n  br i1 %text.literal.more."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.literal.body."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.literal.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.literal.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %text.literal.src."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.literal.source.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %text.literal.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.literal.dst."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.literal.destination.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %text.literal.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.literal.value."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i8, ptr %text.literal.src."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", align 1\n  store i8 %text.literal.value."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %text.literal.dst."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", align 1\n  br label %text.literal.increment."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.literal.increment."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.literal.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = add i64 %text.literal.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", 1\n  br label %text.literal.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.literal.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if is_test && kind == TYPE_KIND_TEXT {
        ir_write_ascii(compiler, ir, "  %text.literal.assert.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
        ir_write_ascii(compiler, ir, ", i64 16\n  call void @nl_core_nl_text_assert_valid(ptr %nl.ctx, ptr %text.literal.assert.data.")
        ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, literal.count()); ir_push_byte(compiler, ir, 41); ir_push_byte(compiler, ir, 10)
    }
}

fn emit_text_literal_global_reference(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    ir_write_ascii(compiler, ir, if compiler.core_mode { "@.nl.core.literal." } else { "@.nl.literal." })
    ir_write_number(compiler, ir, node)
}

fn emit_text_bytes_literal_element(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    collection_node: long,
    lane: long,
    value_node: long,
    cached_pointer: long,
) -> long {
    let destination = aggregate_destination_location(compiler, 0L, collection_node)
    let pointer = if cached_pointer < 0L { emit_location_pointer_materialization(compiler, ir, destination) } else { cached_pointer }
    ir_write_ascii(compiler, ir, "  %text.bytes.literal.address."); ir_write_number(compiler, ir, collection_node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, lane)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, 8L + lane)
    ir_write_ascii(compiler, ir, "\n  %text.bytes.literal.value."); ir_write_number(compiler, ir, collection_node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, lane)
    ir_write_ascii(compiler, ir, " = trunc i32 "); ir_write_value_ref(compiler, ir, value_node)
    ir_write_ascii(compiler, ir, " to i8\n  store i8 %text.bytes.literal.value."); ir_write_number(compiler, ir, collection_node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, lane)
    ir_write_ascii(compiler, ir, ", ptr %text.bytes.literal.address."); ir_write_number(compiler, ir, collection_node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, lane); ir_write_ascii(compiler, ir, ", align 1\n")
    pointer
}

fn emit_text_type_helpers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, kind: long) {
    for type_id in 0L..type_count(compiler) {
        if type_kind(compiler, type_id) != kind { continue }
        let data_offset = text_data_offset(compiler, type_id)
        if has_type_helper(compiler, type_id, HELPER_COPY) {
            ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY)
            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr %nl.p4, ptr %nl.p5) {\nentry:\n")
            if kind == TYPE_KIND_BYTES {
                ir_write_ascii(compiler, ir, "  %text.copy.same."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, " = icmp eq ptr %nl.p4, %nl.p5\n  br i1 %text.copy.same."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, ", label %text.copy.done."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, ", label %text.copy.body."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, "\ntext.copy.body."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n")
            }
            ir_write_ascii(compiler, ir, "  %text.copy.length.src."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = load i64, ptr %nl.p5, align 1\n  store i64 %text.copy.length.src."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", ptr %nl.p4, align 1\n")
            if kind == TYPE_KIND_TEXT {
                ir_write_ascii(compiler, ir, "  %text.copy.points.src."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.p5, i64 8\n  %text.copy.points."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, " = load i64, ptr %text.copy.points.src."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, ", align 1\n  %text.copy.points.dst."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.p4, i64 8\n  store i64 %text.copy.points."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, ", ptr %text.copy.points.dst."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 10)
            }
            ir_write_ascii(compiler, ir, "  %text.copy.source.data."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.p5, i64 "); ir_write_number(compiler, ir, data_offset)
            ir_write_ascii(compiler, ir, "\n  %text.copy.destination.data."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.p4, i64 "); ir_write_number(compiler, ir, data_offset)
            ir_write_ascii(compiler, ir, "\n  %text.copy.call."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %text.copy.destination.data."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", ptr %text.copy.source.data."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", i64 %text.copy.length.src."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ")\n  ret void\n")
            if kind == TYPE_KIND_BYTES {
                ir_write_ascii(compiler, ir, "text.copy.done."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret void\n")
            }
            ir_write_ascii(compiler, ir, "}\n\n")
        }
        if has_type_helper(compiler, type_id, HELPER_EQUAL) {
            ir_write_ascii(compiler, ir, "define internal i1 "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_EQUAL)
            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr %nl.p6, ptr %nl.p7) {\nentry:\n  %text.eq.left.length.addr."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.p6, i64 0\n  %text.eq.right.length.addr."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.p7, i64 0\n  %text.eq.left.length."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = load i64, ptr %text.eq.left.length.addr."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", align 1\n  %text.eq.right.length."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = load i64, ptr %text.eq.right.length.addr."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", align 1\n  %text.eq.length.equal."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = icmp eq i64 %text.eq.left.length."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", %text.eq.right.length."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, "\n  br i1 %text.eq.length.equal."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", label %text.eq.cond."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", label %text.eq.false."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, "\ntext.eq.cond."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ":\n  %text.eq.index."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = phi i64 [ 0, %entry ], [ %text.eq.next."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", %text.eq.step."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " ]\n  %text.eq.more."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = icmp ult i64 %text.eq.index."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", %text.eq.left.length."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, "\n  br i1 %text.eq.more."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", label %text.eq.body."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", label %text.eq.true."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, "\ntext.eq.body."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ":\n  %text.eq.left.pointer."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.p6, i64 "); ir_write_number(compiler, ir, data_offset)
            ir_write_ascii(compiler, ir, "\n  %text.eq.right.pointer."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.p7, i64 "); ir_write_number(compiler, ir, data_offset)
            ir_write_ascii(compiler, ir, "\n  %text.eq.left.byte.pointer."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.eq.left.pointer."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", i64 %text.eq.index."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, "\n  %text.eq.right.byte.pointer."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.eq.right.pointer."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", i64 %text.eq.index."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, "\n  %text.eq.left.byte."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = load i8, ptr %text.eq.left.byte.pointer."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", align 1\n  %text.eq.right.byte."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = load i8, ptr %text.eq.right.byte.pointer."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", align 1\n  %text.eq.byte.equal."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = icmp eq i8 %text.eq.left.byte."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", %text.eq.right.byte."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, "\n  br i1 %text.eq.byte.equal."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", label %text.eq.step."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", label %text.eq.false."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, "\ntext.eq.step."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ":\n  %text.eq.next."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = add i64 %text.eq.index."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", 1\n  br label %text.eq.cond."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, "\ntext.eq.false."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret i1 false\n")
            ir_write_ascii(compiler, ir, "text.eq.true."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret i1 true\n}\n\n")
        }
        if has_type_helper(compiler, type_id, HELPER_PRINT) {
            ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_PRINT)
            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr %nl.p8) {\nentry:\n  %text.print.length.addr."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.p8, i64 0\n  %text.print.length."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = load i64, ptr %text.print.length.addr."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", align 1\n  %text.print.data."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.p8, i64 "); ir_write_number(compiler, ir, data_offset)
            ir_write_ascii(compiler, ir, "\n  call void @nl_print_ascii(ptr %nl.ctx, ptr %text.print.data."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", i64 %text.print.length."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ")\n  ret void\n}\n\n")
        }
    }
}

fn emit_ascii_search(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    is_prefix: bool,
) {
    ir_write_ascii(compiler, ir, "  br label %ascii.search.init."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.search.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    let receiver = compiler.child_first[node]
    let needle = compiler.child_next[receiver]
    let receiver_location = text_method_receiver_location(tables, compiler, node)
    let needle_location = aggregate_source_location(compiler,
        aggregate_source_kind(tables, compiler, needle), aggregate_source_id(tables, compiler, needle))
    let receiver_pointer = emit_location_pointer_materialization(compiler, ir, receiver_location)
    let needle_pointer = emit_location_pointer_materialization(compiler, ir, needle_location)
    ir_write_ascii(compiler, ir, "  %ascii.search.hay.length."); ir_write_number(compiler, ir, node)
    if text_method_needs_receiver_metrics_capture(tables, compiler, node) {
        ir_write_ascii(compiler, ir, " = add i64 %text.receiver.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
    } else {
        ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, receiver_location, receiver_pointer)
        ir_write_ascii(compiler, ir, ", align 1\n")
    }
    ir_write_ascii(compiler, ir, "  %ascii.search.needle.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, needle_location, needle_pointer)
    ir_write_ascii(compiler, ir, ", align 1\n  %ascii.search.too.long."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ugt i64 %ascii.search.needle.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %ascii.search.hay.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %ascii.search.last."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = sub i64 %ascii.search.hay.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %ascii.search.needle.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br i1 %ascii.search.too.long."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %ascii.search.false."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %ascii.search.outer.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.search.outer.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %ascii.search.candidate."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = phi i64 [ 0, %ascii.search.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ], [ %ascii.search.candidate.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %ascii.search.outer.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " ]\n  %ascii.search.candidate.more."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ule i64 %ascii.search.candidate."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", "); if is_prefix { ir_write_ascii(compiler, ir, "0") }
    else { ir_write_ascii(compiler, ir, "%ascii.search.last."); ir_write_number(compiler, ir, node) }
    ir_write_ascii(compiler, ir, "\n  br i1 %ascii.search.candidate.more."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %ascii.search.inner.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %ascii.search.false."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.search.inner.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %ascii.search.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = phi i64 [ 0, %ascii.search.outer.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " ], [ %ascii.search.index.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %ascii.search.inner.step."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " ]\n  %ascii.search.index.more."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ult i64 %ascii.search.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %ascii.search.needle.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br i1 %ascii.search.index.more."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %ascii.search.inner.body."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %ascii.search.true."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.search.inner.body."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %ascii.search.hay.offset."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = add i64 %ascii.search.candidate."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %ascii.search.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %ascii.search.hay.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, receiver_location, receiver_pointer)
    ir_write_ascii(compiler, ir, ", i64 8\n  %ascii.search.needle.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, needle_location, needle_pointer)
    ir_write_ascii(compiler, ir, ", i64 8\n  %ascii.search.hay.byte.ptr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %ascii.search.hay.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %ascii.search.hay.offset."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %ascii.search.needle.byte.ptr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %ascii.search.needle.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %ascii.search.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %ascii.search.hay.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i8, ptr %ascii.search.hay.byte.ptr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", align 1\n  %ascii.search.needle.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i8, ptr %ascii.search.needle.byte.ptr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", align 1\n  %ascii.search.same."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp eq i8 %ascii.search.hay.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %ascii.search.needle.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br i1 %ascii.search.same."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %ascii.search.inner.step."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %ascii.search.outer.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.search.inner.step."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %ascii.search.index.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = add i64 %ascii.search.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", 1\n  br label %ascii.search.inner.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.search.outer.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %ascii.search.candidate.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = add i64 %ascii.search.candidate."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", 1\n  br label %ascii.search.outer.cond."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.search.true."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  br label %ascii.search.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.search.false."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  br label %ascii.search.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.search.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = phi i1 [ true, %ascii.search.true."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " ], [ false, %ascii.search.false."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ]\n")
}

fn emit_text_slice(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    is_test: bool,
) {
    let receiver = compiler.child_first[node]
    let start_node = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
    let end_node = if start_node >= 0L { compiler.child_next[start_node] } else { -1L }
    if receiver < 0L || start_node < 0L || end_node < 0L { compiler.ir_overflow = true; return }
    let receiver_ty = compiler.facts[receiver].ty
    let receiver_kind = type_kind(compiler, receiver_ty)
    let is_text = receiver_kind == TYPE_KIND_TEXT
    let source_location = text_method_receiver_location(tables, compiler, node)
    let destination_location = aggregate_destination_location(compiler, 0L, node)
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source_location)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination_location)
    let source_data_offset = text_location_data_offset(compiler, receiver_ty, source_location)
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[receiver].start, compiler)
    var inclusive = false
    for token_index in files[file_index].first_token..files[file_index].first_token + files[file_index].token_count {
        let token = tokens[token_index]
        if token.kind == TokenKind.RangeInclusive && token.start >= tables.nodes[start_node].end &&
            token.start < tables.nodes[end_node].start { inclusive = true }
    }
    if is_text {
        emit_text_method_source_points(tables, compiler, ir, receiver_ty, source_location, source_pointer, node, "slice")
        ir_write_ascii(compiler, ir, "  %text.slice.live."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = add i64 %text.slice.points."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
    } else {
        emit_text_method_source_length(tables, compiler, ir, source_location, source_pointer, node, "slice")
        ir_write_ascii(compiler, ir, "  %text.slice.live."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = add i64 %text.slice.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
    }
    ir_write_ascii(compiler, ir, "  %text.slice.start.negative."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp slt i64 "); ir_write_value_ref(compiler, ir, start_node); ir_write_ascii(compiler, ir, ", 0\n")
    ir_write_ascii(compiler, ir, "  %text.slice.end.negative."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp slt i64 "); ir_write_value_ref(compiler, ir, end_node); ir_write_ascii(compiler, ir, ", 0\n")
    if inclusive {
        ir_write_ascii(compiler, ir, "  %text.slice.end.max."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = icmp eq i64 "); ir_write_value_ref(compiler, ir, end_node)
        ir_write_ascii(compiler, ir, ", 9223372036854775807\n  %text.slice.end.exclusive."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = add i64 "); ir_write_value_ref(compiler, ir, end_node); ir_write_ascii(compiler, ir, ", 1\n")
    } else {
        ir_write_ascii(compiler, ir, "  %text.slice.end.max."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = icmp eq i1 false, true\n  %text.slice.end.exclusive."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = add i64 "); ir_write_value_ref(compiler, ir, end_node); ir_write_ascii(compiler, ir, ", 0\n")
    }
    ir_write_ascii(compiler, ir, "  %text.slice.start.high."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ugt i64 "); ir_write_value_ref(compiler, ir, start_node)
    ir_write_ascii(compiler, ir, ", %text.slice.live."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.slice.end.high."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ugt i64 %text.slice.end.exclusive."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.slice.live."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.slice.reversed."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ugt i64 "); ir_write_value_ref(compiler, ir, start_node)
    ir_write_ascii(compiler, ir, ", %text.slice.end.exclusive."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.slice.bad0."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = or i1 %text.slice.start.negative."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.slice.end.negative."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.slice.bad1."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = or i1 %text.slice.start.high."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.slice.end.high."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.slice.bad2."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = or i1 %text.slice.reversed."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.slice.end.max."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.slice.bad."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = or i1 %text.slice.bad0."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.slice.bad1."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.slice.invalid."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = or i1 %text.slice.bad."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.slice.bad2."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br i1 %text.slice.invalid."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.slice.fail."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.slice.valid."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.slice.fail."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  call void @nl_fail(ptr %nl.ctx, i32 16, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler))
    ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col)
    ir_write_ascii(compiler, ir, ")\n  unreachable\ntext.slice.valid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")

    if is_text {
        ir_write_ascii(compiler, ir, "  %text.slice.start.byte.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n")
        ir_write_ascii(compiler, ir, "  %text.slice.end.byte.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n  store i64 0, ptr %text.slice.start.byte.slot."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", align 8\n  store i64 0, ptr %text.slice.end.byte.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n")
        ir_write_ascii(compiler, ir, "  %text.slice.source.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, source_data_offset)
        ir_write_ascii(compiler, ir, "\n  br label %text.slice.point.cond."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, "\ntext.slice.point.cond."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ":\n  %text.slice.point."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = phi i64 [ 0, %text.slice.valid."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " ], [ %text.slice.point.next."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", %text.slice.point.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ]\n  %text.slice.byte."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = phi i64 [ 0, %text.slice.valid."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " ], [ %text.slice.byte.next."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", %text.slice.point.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ]\n")
        ir_write_ascii(compiler, ir, "  %text.slice.at.start."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i64 %text.slice.point."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, start_node)
        ir_write_ascii(compiler, ir, "\n  %text.slice.old.start."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr %text.slice.start.byte.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n  %text.slice.selected.start."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 %text.slice.at.start."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.slice.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.slice.old.start."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  store i64 %text.slice.selected.start."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %text.slice.start.byte.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n")
        ir_write_ascii(compiler, ir, "  %text.slice.at.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i64 %text.slice.point."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %text.slice.end.exclusive."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %text.slice.old.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr %text.slice.end.byte.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n  %text.slice.selected.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 %text.slice.at.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.slice.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.slice.old.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  store i64 %text.slice.selected.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %text.slice.end.byte.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n")
        ir_write_ascii(compiler, ir, "  %text.slice.points.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ult i64 %text.slice.point."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %text.slice.end.exclusive."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  br i1 %text.slice.points.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %text.slice.point.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %text.slice.point.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ntext.slice.point.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        ir_write_ascii(compiler, ir, "  %text.slice.point.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.slice.source.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.slice.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %text.slice.lead."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i8, ptr %text.slice.point.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  %text.slice.lead.unsigned."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i8 %text.slice.lead."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i32\n  %text.slice.one."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ult i32 %text.slice.lead.unsigned."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 128\n  %text.slice.two."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ult i32 %text.slice.lead.unsigned."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 224\n  %text.slice.three."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ult i32 %text.slice.lead.unsigned."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 240\n  %text.slice.width12."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 %text.slice.one."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 1, i64 2\n  %text.slice.width."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 %text.slice.two."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.slice.width12."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 3\n  %text.slice.width4."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 %text.slice.three."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.slice.width."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 4\n  %text.slice.byte.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %text.slice.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %text.slice.width4."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %text.slice.point.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %text.slice.point."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  br label %text.slice.point.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ntext.slice.point.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        ir_write_ascii(compiler, ir, "  %text.slice.start.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr %text.slice.start.byte.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n  %text.slice.end.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr %text.slice.end.byte.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n")
    } else {
        ir_write_ascii(compiler, ir, "  %text.slice.start.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_value_ref(compiler, ir, start_node); ir_write_ascii(compiler, ir, ", 0\n  %text.slice.end.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %text.slice.end.exclusive."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
    }
    ir_write_ascii(compiler, ir, "  %text.slice.byte.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sub i64 %text.slice.end.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %text.slice.start.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %text.slice.destination.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination_location, destination_pointer); ir_write_ascii(compiler, ir, ", i64 0\n  store i64 %text.slice.byte.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %text.slice.destination.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    if is_text {
        ir_write_ascii(compiler, ir, "  %text.slice.destination.points."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination_location, destination_pointer); ir_write_ascii(compiler, ir, ", i64 8\n  %text.slice.point.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sub i64 %text.slice.end.exclusive."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, start_node); ir_write_ascii(compiler, ir, "\n  store i64 %text.slice.point.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %text.slice.destination.points."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    }
    ir_write_ascii(compiler, ir, "  %text.slice.source.start."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, source_data_offset); ir_write_ascii(compiler, ir, "\n  %text.slice.destination.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination_location, destination_pointer); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, text_data_offset(compiler, compiler.facts[node].ty)); ir_write_ascii(compiler, ir, "\n")
    ir_write_ascii(compiler, ir, "  br label %text.slice.copy.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ntext.slice.copy.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  br label %text.slice.copy.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ntext.slice.copy.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %text.slice.copy.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = phi i64 [ 0, %text.slice.copy.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ], [ %text.slice.copy.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %text.slice.copy.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ]\n  %text.slice.copy.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ult i64 %text.slice.copy.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %text.slice.byte.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  br i1 %text.slice.copy.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %text.slice.copy.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %text.slice.copy.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ntext.slice.copy.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %text.slice.copy.src.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %text.slice.start.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %text.slice.copy.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %text.slice.copy.src."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.slice.source.start."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.slice.copy.src.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %text.slice.copy.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i8, ptr %text.slice.copy.src."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  %text.slice.copy.dst."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.slice.destination.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.slice.copy.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  store i8 %text.slice.copy.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %text.slice.copy.dst."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  %text.slice.copy.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %text.slice.copy.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  br label %text.slice.copy.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ntext.slice.copy.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if is_test && is_text {
        ir_write_ascii(compiler, ir, "  call void @nl_core_nl_text_assert_valid(ptr %nl.ctx, ptr %text.slice.destination.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.slice.byte.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
    }
    if source.count() < 0L || tokens.count() < 0L { compiler.ir_overflow = true }
}

fn text_method_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    method_token: long,
    receiver_kind: long,
) -> long {
    if (receiver_kind == TYPE_KIND_ASCII || receiver_kind == TYPE_KIND_TEXT || receiver_kind == TYPE_KIND_BYTES) &&
        token_is_word_at(source, tokens, files, file_index, method_token, "len") { TEXT_METHOD_LEN }
    else if receiver_kind == TYPE_KIND_BYTES && token_is_word_at(source, tokens, files, file_index, method_token, "count") { TEXT_METHOD_LEN }
    else if receiver_kind == TYPE_KIND_TEXT && token_is_word_at(source, tokens, files, file_index, method_token, "byte_len") { TEXT_METHOD_BYTE_LEN }
    else if (receiver_kind == TYPE_KIND_ASCII || receiver_kind == TYPE_KIND_TEXT || receiver_kind == TYPE_KIND_BYTES) &&
        token_is_word_at(source, tokens, files, file_index, method_token, "slice") { TEXT_METHOD_SLICE }
    else if (receiver_kind == TYPE_KIND_ASCII || receiver_kind == TYPE_KIND_TEXT) &&
        token_is_word_at(source, tokens, files, file_index, method_token, "bytes") { TEXT_METHOD_BYTES }
    else if receiver_kind == TYPE_KIND_ASCII && token_is_word_at(source, tokens, files, file_index, method_token, "contains") { TEXT_METHOD_CONTAINS }
    else if receiver_kind == TYPE_KIND_ASCII && token_is_word_at(source, tokens, files, file_index, method_token, "starts_with") { TEXT_METHOD_STARTS_WITH }
    else if receiver_kind == TYPE_KIND_BYTES && token_is_word_at(source, tokens, files, file_index, method_token, "validate_utf8") { TEXT_METHOD_VALIDATE_UTF8 }
    else if receiver_kind == TYPE_KIND_BYTES && token_is_word_at(source, tokens, files, file_index, method_token, "to_text") { TEXT_METHOD_TO_TEXT }
    else if (receiver_kind == TYPE_KIND_TEXT || receiver_kind == TYPE_KIND_BYTES) && token_is_word_at(source, tokens, files, file_index, method_token, "to_ascii") { TEXT_METHOD_TO_ASCII }
    else { 0L }
}

fn emit_text_method_call(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    is_test: bool,
) {
    let receiver = compiler.child_first[node]
    if receiver < 0L { compiler.ir_overflow = true; return }
    let ty = compiler.facts[receiver].ty
    let kind = type_kind(compiler, ty)
    let method = text_method_kind(source, tokens, files, file_index, tables.nodes[node].token, kind)
    if method == TEXT_METHOD_LEN || method == TEXT_METHOD_BYTE_LEN {
        let location = text_method_receiver_location(tables, compiler, node)
        let pointer = emit_location_pointer_materialization(compiler, ir, location)
        if method == TEXT_METHOD_LEN && kind == TYPE_KIND_TEXT {
            emit_text_source_points(compiler, ir, ty, location, pointer, node, "method")
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = add i64 %text.method.points."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
        } else {
            emit_text_source_length(compiler, ir, location, pointer, node, "method")
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = add i64 %text.method.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
        }
    } else if method == TEXT_METHOD_SLICE {
        emit_text_slice(source, files, tokens, tables, compiler, ir, node, file_index, is_test)
    } else if method == TEXT_METHOD_BYTES {
        emit_text_bytes_view(tables, compiler, ir, node, is_test)
    } else if method == TEXT_METHOD_CONTAINS || method == TEXT_METHOD_STARTS_WITH {
        emit_ascii_search(tables, compiler, ir, node, method == TEXT_METHOD_STARTS_WITH)
    } else if method == TEXT_METHOD_VALIDATE_UTF8 || method == TEXT_METHOD_TO_TEXT || method == TEXT_METHOD_TO_ASCII {
        emit_text_conversion(tables, compiler, ir, node, method, is_test)
    } else { compiler.ir_overflow = true }
}

fn emit_text_conversion(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    method: long,
    is_test: bool,
) {
    let receiver = compiler.child_first[node]
    let receiver_ty = compiler.facts[receiver].ty
    let receiver_kind = type_kind(compiler, receiver_ty)
    let result_ty = compiler.facts[node].ty
    let source = text_method_receiver_location(tables, compiler, node)
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    let source_length = text_max_bytes(compiler, receiver_ty)
    let source_data_offset = text_location_data_offset(compiler, receiver_ty, source)
    let error_payload = sum_payload_record(compiler, result_ty, 1L, 0L)
    let error_ty = error_payload.ty
    let error_offset = error_payload.offset
    emit_text_source_length(compiler, ir, source, source_pointer, node, "convert")
    ir_write_ascii(compiler, ir, "  %text.convert.source.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source, source_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, source_data_offset); ir_push_byte(compiler, ir, 10)
    if receiver_kind == TYPE_KIND_BYTES && method != TEXT_METHOD_TO_ASCII {
        ir_write_ascii(compiler, ir, "  %text.convert.utf8.offset."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i64 @nl_core_utf8_error_offset(ptr %nl.ctx, ptr %text.convert.source.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.convert.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
        ir_write_ascii(compiler, ir, "  %text.convert.utf8.valid."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = icmp eq i64 %text.convert.utf8.offset."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", %text.convert.length."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, "\n  br i1 %text.convert.utf8.valid."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", label %text.convert.valid."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", label %text.convert.invalid."); ir_write_number(compiler, ir, node)
    } else {
        ir_write_ascii(compiler, ir, "  br label %text.convert.valid."); ir_write_number(compiler, ir, node)
    }
    ir_write_ascii(compiler, ir, "\ntext.convert.invalid."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n")
    emit_text_result_tag(compiler, ir, node, destination, destination_pointer, 1L, 1L)
    if method == TEXT_METHOD_TO_ASCII {
        emit_text_result_error_enum(compiler, ir, node, destination, destination_pointer, error_offset, 0L)
    } else if method == TEXT_METHOD_VALIDATE_UTF8 || method == TEXT_METHOD_TO_TEXT {
        emit_text_result_error_offset(compiler, ir, node, destination, destination_pointer, error_offset)
    } else { () }
    ir_write_ascii(compiler, ir, "  br label %text.convert.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.convert.valid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if method == TEXT_METHOD_TO_ASCII {
        ir_write_ascii(compiler, ir, "  %text.convert.ascii.offset."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i64 @nl_core_non_ascii_offset(ptr %nl.ctx, ptr %text.convert.source.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.convert.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
        ir_write_ascii(compiler, ir, "  %text.convert.ascii.valid."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = icmp eq i64 %text.convert.ascii.offset."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", %text.convert.length."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, "\n  br i1 %text.convert.ascii.valid."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", label %text.convert.success."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", label %text.convert.nonascii."); ir_write_number(compiler, ir, node)
    } else {
        ir_write_ascii(compiler, ir, "  br label %text.convert.success."); ir_write_number(compiler, ir, node)
    }
    ir_write_ascii(compiler, ir, "\ntext.convert.nonascii."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    emit_text_result_tag(compiler, ir, node, destination, destination_pointer, 1L, 2L)
    emit_text_result_error_enum(compiler, ir, node, destination, destination_pointer, error_offset, 1L)
    ir_write_ascii(compiler, ir, "  br label %text.convert.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.convert.success."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    emit_text_result_tag(compiler, ir, node, destination, destination_pointer, 0L, 3L)
    if method == TEXT_METHOD_TO_TEXT {
        let value_payload = sum_payload_record(compiler, result_ty, 0L, 0L)
        let value_offset = value_payload.offset
        ir_write_ascii(compiler, ir, "  %text.convert.value."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, value_offset); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %text.convert.value.length."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.convert.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 0\n  store i64 %text.convert.length."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr %text.convert.value.length."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %text.convert.value.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.convert.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 16\n")
        ir_write_ascii(compiler, ir, "  %text.convert.value.points."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i64 @nl_core_nl_text_codepoint_count_trusted(ptr %nl.ctx, ptr %text.convert.source.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.convert.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
        ir_write_ascii(compiler, ir, "  %text.convert.value.points.addr."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.convert.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 8\n  store i64 %text.convert.value.points."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr %text.convert.value.points.addr."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %text.convert.copy."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %text.convert.value.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr %text.convert.source.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.convert.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
        if is_test {
            ir_write_ascii(compiler, ir, "  call void @nl_core_nl_text_assert_valid(ptr %nl.ctx, ptr %text.convert.value.data."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ", i64 %text.convert.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
        } else { () }
    } else if method == TEXT_METHOD_TO_ASCII {
        let value_payload = sum_payload_record(compiler, result_ty, 0L, 0L)
        let value_offset = value_payload.offset
        ir_write_ascii(compiler, ir, "  %text.convert.value."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, value_offset); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %text.convert.value.length."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.convert.value."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 0\n  store i64 %text.convert.length."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr %text.convert.value.length."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %text.convert.value.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.convert.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 8\n")
        ir_write_ascii(compiler, ir, "  %text.convert.copy."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %text.convert.value.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr %text.convert.source.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.convert.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
    } else { () }
    ir_write_ascii(compiler, ir, "  br label %text.convert.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.convert.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if source_length < 0L || error_ty < 0L { compiler.ir_overflow = true } else { () }
}

fn emit_text_result_tag(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    destination: StorageLocation,
    pointer: long,
    tag: long,
    path: long,
) {
    ir_write_ascii(compiler, ir, "  %text.convert.tag.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, path)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer)
    ir_write_ascii(compiler, ir, ", i64 0\n  %text.convert.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, path)
    ir_write_ascii(compiler, ir, " = add i32 0, "); ir_write_number(compiler, ir, tag)
    ir_write_ascii(compiler, ir, "\n  store i32 %text.convert.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, path)
    ir_write_ascii(compiler, ir, ", ptr %text.convert.tag.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, path); ir_push_byte(compiler, ir, 10)
}

fn emit_text_result_error_offset(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    destination: StorageLocation,
    pointer: long,
    error_offset: long,
) {
    let result_ty = compiler.facts[node].ty
    let payload_offset = sum_payload_record(compiler, result_ty, 1L, 0L).offset
    ir_write_ascii(compiler, ir, "  %text.convert.error.offset.addr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, payload_offset)
    ir_write_ascii(compiler, ir, "\n  store i64 %text.convert.utf8.offset."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %text.convert.error.offset.addr."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    let _ = error_offset
}

fn emit_text_result_error_enum(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    destination: StorageLocation,
    pointer: long,
    unused_offset: long,
    tag: long,
) {
    let result_ty = compiler.facts[node].ty
    let payload_offset = sum_payload_record(compiler, result_ty, 1L, 0L).offset
    ir_write_ascii(compiler, ir, "  %text.convert.error.tag.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, tag)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, payload_offset)
    ir_write_ascii(compiler, ir, "\n  %text.convert.error.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, tag)
    ir_write_ascii(compiler, ir, " = add i32 0, "); ir_write_number(compiler, ir, tag)
    ir_write_ascii(compiler, ir, "\n  store i32 %text.convert.error.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, tag)
    ir_write_ascii(compiler, ir, ", ptr %text.convert.error.tag.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, tag); ir_push_byte(compiler, ir, 10)
    let _ = unused_offset
}

fn emit_ascii_fit(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let value_node = compiler.child_first[node]
    let target_ty = sum_payload_record(compiler, compiler.facts[node].ty, 0L, 0L).ty
    let source = aggregate_source_location(compiler,
        aggregate_source_kind(tables, compiler, value_node), aggregate_source_id(tables, compiler, value_node))
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    let limit = text_max_bytes(compiler, target_ty)
    ir_write_ascii(compiler, ir, "  %ascii.fit.length.addr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source, source_pointer)
    ir_write_ascii(compiler, ir, ", i64 0\n  %ascii.fit.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i64, ptr %ascii.fit.length.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    ir_write_ascii(compiler, ir, "  %ascii.fit.fits."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ule i64 %ascii.fit.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, limit)
    ir_write_ascii(compiler, ir, "\n  br i1 %ascii.fit.fits."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %ascii.fit.some."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %ascii.fit.none."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.fit.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    ir_write_ascii(compiler, ir, "  %ascii.fit.some.tag.addr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 0\n  store i32 0, ptr %ascii.fit.some.tag.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    let payload = sum_payload_record(compiler, compiler.facts[node].ty, 0L, 0L)
    ir_write_ascii(compiler, ir, "  %ascii.fit.some.value."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, payload.offset)
    ir_write_ascii(compiler, ir, "\n  store i64 %ascii.fit.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %ascii.fit.some.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    ir_write_ascii(compiler, ir, "  %ascii.fit.source.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source, source_pointer); ir_write_ascii(compiler, ir, ", i64 8\n")
    ir_write_ascii(compiler, ir, "  %ascii.fit.destination.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %ascii.fit.some.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 8\n")
    ir_write_ascii(compiler, ir, "  %ascii.fit.copy."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %ascii.fit.destination.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %ascii.fit.source.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %ascii.fit.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n  br label %ascii.fit.end."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.fit.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    ir_write_ascii(compiler, ir, "  %ascii.fit.none.tag.addr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 0\n  store i32 1, ptr %ascii.fit.none.tag.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  br label %ascii.fit.end."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nascii.fit.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
}

fn emit_ascii_cast(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    source_node: long,
    target_ty: long,
) {
    let source_ty = compiler.facts[source_node].ty
    let source_location = aggregate_source_location(compiler,
        aggregate_source_kind(tables, compiler, source_node), aggregate_source_id(tables, compiler, source_node))
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source_location)
    emit_text_source_length(compiler, ir, source_location, source_pointer, node, "cast")
    let target_maximum = text_max_bytes(compiler, target_ty)
    ir_write_ascii(compiler, ir, "  %text.cast.fits."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ule i64 %text.cast.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, target_maximum)
    ir_write_ascii(compiler, ir, "\n  br i1 %text.cast.fits."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.cast.good."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.cast.fail."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.cast.fail."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  call void @nl_fail(ptr %nl.ctx, i32 10, i32 ")
    ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler))
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].start, compiler)
    ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line)
    ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col)
    ir_write_ascii(compiler, ir, ")\n  unreachable\ntext.cast.good."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")

    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    ir_write_ascii(compiler, ir, "  %text.cast.length.addr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 0\n  store i64 %text.cast.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %text.cast.length.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1")
    emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %text.cast.source.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, text_location_data_offset(compiler, source_ty, source_location))
    ir_write_ascii(compiler, ir, "\n  %text.cast.destination.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, text_data_offset(compiler, target_ty)); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %text.cast.copy."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %text.cast.destination.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %text.cast.source.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %text.cast.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
}

fn text_width_fits(compiler: CompilerTables, actual: long, expected: long) -> bool {
    let actual_kind = type_kind(compiler, actual)
    let expected_kind = type_kind(compiler, expected)
    let actual_bytes = text_max_bytes(compiler, actual)
    let expected_bytes = text_max_bytes(compiler, expected)
    if actual_kind == TYPE_KIND_ASCII && expected_kind == TYPE_KIND_ASCII {
        actual_bytes <= expected_bytes
    } else if actual_kind == TYPE_KIND_BYTES && expected_kind == TYPE_KIND_BYTES {
        actual_bytes <= expected_bytes
    } else if actual_kind == TYPE_KIND_TEXT && expected_kind == TYPE_KIND_TEXT {
        actual_bytes <= expected_bytes && text_max_codepoints(compiler, actual) <= text_max_codepoints(compiler, expected)
    } else { false }
}

fn text_read_argument_fits(compiler: CompilerTables, expected: long, actual: long) -> bool {
    if text_width_fits(compiler, actual, expected) { return true }
    type_kind(compiler, expected) == TYPE_KIND_TEXT && type_kind(compiler, actual) == TYPE_KIND_ASCII &&
        text_max_bytes(compiler, actual) <= text_max_bytes(compiler, expected) &&
        text_max_bytes(compiler, actual) <= text_max_codepoints(compiler, expected)
}

fn text_read_view_binding(compiler: CompilerTables, location: StorageLocation) -> long {
    if location.anchor_kind != 3L { return -1L }
    let binding = location.anchor_node
    if binding >= 0L && binding < compiler.bindings.count() && compiler.bindings[binding].parameter &&
        !compiler.bindings[binding].mutable && type_kind(compiler, compiler.bindings[binding].ty) == TYPE_KIND_TEXT {
        binding
    } else { -1L }
}

fn text_location_data_offset(compiler: CompilerTables, type_id: long, location: StorageLocation) -> long {
    if text_read_view_binding(compiler, location) >= 0L { 0L }
    else { text_data_offset(compiler, type_id) }
}

fn emit_text_source_length(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    location: StorageLocation,
    pointer: long,
    node: long,
    label: Ascii max 24,
) {
    let binding = text_read_view_binding(compiler, location)
    ir_write_ascii(compiler, ir, "  %text."); ir_write_ascii(compiler, ir, label); ir_write_ascii(compiler, ir, ".length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ")
    if binding >= 0L {
        ir_write_ascii(compiler, ir, "add i64 %arg.copies."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", 0\n")
    } else {
        ir_write_ascii(compiler, ir, "load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", align 1\n")
    }
}

fn emit_text_source_points(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    location: StorageLocation,
    pointer: long,
    node: long,
    label: Ascii max 24,
) {
    let binding = text_read_view_binding(compiler, location)
    if binding < 0L && type_kind(compiler, type_id) == TYPE_KIND_TEXT {
        ir_write_ascii(compiler, ir, "  %text."); ir_write_ascii(compiler, ir, label); ir_write_ascii(compiler, ir, ".points.addr."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer)
        ir_write_ascii(compiler, ir, ", i64 8\n")
    }
    ir_write_ascii(compiler, ir, "  %text."); ir_write_ascii(compiler, ir, label); ir_write_ascii(compiler, ir, ".points."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ")
    if binding >= 0L {
        ir_write_ascii(compiler, ir, "add i64 %arg.index."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", 0\n")
    } else if type_kind(compiler, type_id) == TYPE_KIND_TEXT {
        ir_write_ascii(compiler, ir, "load i64, ptr %text."); ir_write_ascii(compiler, ir, label); ir_write_ascii(compiler, ir, ".points.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    } else {
        ir_write_ascii(compiler, ir, "add i64 %text."); ir_write_ascii(compiler, ir, label); ir_write_ascii(compiler, ir, ".length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
    }
}

// A Stage-0 method receiver evaluates to a descriptor before its arguments:
// the descriptor's pointer and metrics are captured, while its payload bytes
// remain borrowed from the original place. Preserve that split when a later
// argument mutates the receiver: capture only length/points here, then resolve
// the receiver's location again after argument evaluation for the payload.
fn emit_text_method_receiver_metrics(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    if !text_method_needs_receiver_metrics_capture(tables, compiler, node) { return }
    let receiver = compiler.child_first[node]
    if receiver < 0L { compiler.ir_overflow = true; return }
    let type_id = compiler.facts[receiver].ty
    let location = aggregate_source_location(compiler,
        aggregate_source_kind(tables, compiler, receiver), aggregate_source_id(tables, compiler, receiver))
    let pointer = if text_read_view_binding(compiler, location) >= 0L { -1L }
        else { emit_location_pointer_materialization(compiler, ir, location) }
    emit_text_source_length(compiler, ir, location, pointer, node, "receiver")
    emit_text_source_points(compiler, ir, type_id, location, pointer, node, "receiver")
}

fn emit_text_method_source_length(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    location: StorageLocation,
    pointer: long,
    node: long,
    label: Ascii max 24,
) {
    if text_method_needs_receiver_metrics_capture(tables, compiler, node) {
        ir_write_ascii(compiler, ir, "  %text."); ir_write_ascii(compiler, ir, label); ir_write_ascii(compiler, ir, ".length."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = add i64 %text.receiver.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
    } else {
        emit_text_source_length(compiler, ir, location, pointer, node, label)
    }
}

fn emit_text_method_source_points(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    location: StorageLocation,
    pointer: long,
    node: long,
    label: Ascii max 24,
) {
    if text_method_needs_receiver_metrics_capture(tables, compiler, node) {
        ir_write_ascii(compiler, ir, "  %text."); ir_write_ascii(compiler, ir, label); ir_write_ascii(compiler, ir, ".points."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = add i64 %text.receiver.points."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
    } else {
        emit_text_source_points(compiler, ir, type_id, location, pointer, node, label)
    }
}

fn text_parameter_data_location(compiler: CompilerTables, type_id: long, location: StorageLocation) -> StorageLocation {
    StorageLocation {
        origin: location.origin,
        anchor_kind: location.anchor_kind,
        anchor_node: location.anchor_node,
        byte_offset: location.byte_offset + text_location_data_offset(compiler, type_id, location),
        copies: 1L,
        index: 0L,
        index_node: -1L,
        index_stride: 0L,
    }
}

fn prepare_text_parameter_descriptor(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    location: StorageLocation,
    node: long,
) {
    let kind = type_kind(compiler, type_id)
    if kind != TYPE_KIND_ASCII && kind != TYPE_KIND_TEXT { compiler.ir_overflow = true; return }
    let view_binding = text_read_view_binding(compiler, location)
    let pointer = if view_binding >= 0L { -1L } else { emit_location_pointer_materialization(compiler, ir, location) }
    emit_text_source_length(compiler, ir, location, pointer, node, "argument")
    emit_text_source_points(compiler, ir, type_id, location, pointer, node, "argument")
    let data_location = text_parameter_data_location(compiler, type_id, location)
    emit_prepare_location_descriptor(compiler, ir, data_location, false, node)
}

fn emit_text_parameter_descriptor(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    location: StorageLocation,
    node: long,
) {
    let data_location = text_parameter_data_location(compiler, type_id, location)
    emit_location_descriptor_argument(compiler, ir, data_location, false, node)
    ir_write_ascii(compiler, ir, ", i64 %text.argument.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %text.argument.points."); ir_write_number(compiler, ir, node)
}

fn emit_text_parameter_argument(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    use_snapshot: bool,
) {
    let type_id = compiler.facts[node].ty
    let location = if use_snapshot { compiler_location(compiler, 0L, node, 0L) }
        else { aggregate_source_location(compiler,
            aggregate_source_kind(tables, compiler, node), aggregate_source_id(tables, compiler, node)) }
    emit_text_parameter_descriptor(compiler, ir, type_id, location, node)
}

fn emit_text_read_view_copy(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    destination: StorageLocation,
    source: StorageLocation,
) {
    let binding = text_read_view_binding(compiler, source)
    if type_kind(compiler, type_id) != TYPE_KIND_TEXT || binding < 0L { compiler.ir_overflow = true; return }
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
    let serial = next_location_serial(ir)
    ir_write_ascii(compiler, ir, "  %text.view.copy.length.addr."); ir_write_number(compiler, ir, serial)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 0\n  store i64 %arg.copies."); ir_write_number(compiler, ir, binding)
    ir_write_ascii(compiler, ir, ", ptr %text.view.copy.length.addr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1\n")
    ir_write_ascii(compiler, ir, "  %text.view.copy.points.addr."); ir_write_number(compiler, ir, serial)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 8\n  store i64 %arg.index."); ir_write_number(compiler, ir, binding)
    ir_write_ascii(compiler, ir, ", ptr %text.view.copy.points.addr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1\n")
    ir_write_ascii(compiler, ir, "  %text.view.copy.data."); ir_write_number(compiler, ir, serial)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 16\n  %text.view.copy.call."); ir_write_number(compiler, ir, serial)
    ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %text.view.copy.data."); ir_write_number(compiler, ir, serial)
    ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, source, source_pointer)
    ir_write_ascii(compiler, ir, ", i64 %arg.copies."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ")\n")
    emit_text_assert_storage(compiler, ir, type_id, destination)
}

fn emit_text_assert_storage(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    location: StorageLocation,
) {
    if !compiler.test_build || type_kind(compiler, type_id) != TYPE_KIND_TEXT { return }
    let node = next_location_serial(ir)
    let pointer = emit_location_pointer_materialization(compiler, ir, location)
    emit_text_source_length(compiler, ir, location, pointer, node, "assert")
    ir_write_ascii(compiler, ir, "  %text.assert.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer)
    ir_write_ascii(compiler, ir, ", i64 16\n  call void @nl_core_nl_text_assert_valid(ptr %nl.ctx, ptr %text.assert.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %text.assert.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
}

fn is_text_concatenation(compiler: CompilerTables, left: long, right: long) -> bool {
    let left_kind = type_kind(compiler, left)
    let right_kind = type_kind(compiler, right)
    if left_kind == TYPE_KIND_BYTES || right_kind == TYPE_KIND_BYTES {
        left_kind == TYPE_KIND_BYTES && right_kind == TYPE_KIND_BYTES
    } else {
        (left_kind == TYPE_KIND_ASCII || left_kind == TYPE_KIND_TEXT) &&
            (right_kind == TYPE_KIND_ASCII || right_kind == TYPE_KIND_TEXT)
    }
}

fn is_text_comparable(compiler: CompilerTables, left: long, right: long) -> bool {
    let left_kind = type_kind(compiler, left)
    let right_kind = type_kind(compiler, right)
    (left_kind == TYPE_KIND_ASCII && (right_kind == TYPE_KIND_ASCII || right_kind == TYPE_KIND_TEXT)) ||
        (left_kind == TYPE_KIND_TEXT && (right_kind == TYPE_KIND_ASCII || right_kind == TYPE_KIND_TEXT)) ||
        (left_kind == TYPE_KIND_BYTES && right_kind == TYPE_KIND_BYTES)
}

fn text_concat_left_needs_snapshot(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> bool {
    let left = compiler.child_first[node]
    let right = if left >= 0L { compiler.child_next[left] } else { -1L }
    if left < 0L || right < 0L ||
        (tables.nodes[left].kind != NodeKind.Name && tables.nodes[left].kind != NodeKind.Field) ||
        !is_text_concatenation(compiler, compiler.facts[left].ty, compiler.facts[right].ty) {
        return false
    }
    region_subtree_has_effect(tables, right, right)
}

fn text_compare_left_needs_snapshot(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> bool {
    let left = compiler.child_first[node]
    let right = if left >= 0L { compiler.child_next[left] } else { -1L }
    left >= 0L && right >= 0L &&
        (tables.nodes[left].kind == NodeKind.Name || tables.nodes[left].kind == NodeKind.Field) &&
        region_subtree_has_effect(tables, right, right)
}

fn emit_text_copy_range(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    part: long,
    source: StorageLocation,
    source_pointer: long,
    source_offset: long,
    destination: StorageLocation,
    destination_pointer: long,
    destination_data_offset: long,
    destination_offset_is_left_length: bool,
    length_part: long,
) {
    ir_write_ascii(compiler, ir, "  %text.concat.source.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source, source_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, source_offset)
    ir_write_ascii(compiler, ir, "\n  %text.concat.destination.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, destination_data_offset)
    ir_write_ascii(compiler, ir, "\n  br label %text.concat.copy.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, "\ntext.concat.copy.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part); ir_write_ascii(compiler, ir, ":\n  br label %text.concat.copy.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, "\ntext.concat.copy.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, ":\n  %text.concat.copy.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " = phi i64 [ 0, %text.concat.copy.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " ], [ %text.concat.copy.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, ", %text.concat.copy.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " ]\n  %text.concat.copy.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " = icmp ult i64 %text.concat.copy.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, ", %text.concat."); ir_write_ascii(compiler, ir, if length_part == 0L { "left.length." } else { "right.length." }); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br i1 %text.concat.copy.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, ", label %text.concat.copy.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, ", label %text.concat.copy.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, "\ntext.concat.copy.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, ":\n  %text.concat.copy.source.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.concat.source.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, ", i64 %text.concat.copy.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, "\n  %text.concat.copy.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " = load i8, ptr %text.concat.copy.source.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part); ir_write_ascii(compiler, ir, ", align 1\n  %text.concat.copy.destination.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " = add i64 ")
    if destination_offset_is_left_length { ir_write_ascii(compiler, ir, "%text.concat.left.length."); ir_write_number(compiler, ir, node) }
    else { ir_write_ascii(compiler, ir, "0") }
    ir_write_ascii(compiler, ir, ", %text.concat.copy.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, "\n  %text.concat.copy.destination.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %text.concat.destination.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, ", i64 %text.concat.copy.destination.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, "\n  store i8 %text.concat.copy.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, ", ptr %text.concat.copy.destination.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part); ir_write_ascii(compiler, ir, ", align 1\n  %text.concat.copy.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, " = add i64 %text.concat.copy.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, ", 1\n  br label %text.concat.copy.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part)
    ir_write_ascii(compiler, ir, "\ntext.concat.copy.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, part); ir_write_ascii(compiler, ir, ":\n")
}

fn emit_text_concat(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    is_test: bool,
) {
    let left = compiler.child_first[node]
    let right = if left >= 0L { compiler.child_next[left] } else { -1L }
    if left < 0L || right < 0L { compiler.ir_overflow = true; return }
    let left_ty = compiler.facts[left].ty
    let right_ty = compiler.facts[right].ty
    let result_ty = compiler.facts[node].ty
    let result_kind = type_kind(compiler, result_ty)
    let left_location = if text_concat_left_needs_snapshot(tables, compiler, node) {
        compiler_location(compiler, 0L, left, 0L)
    } else {
        aggregate_source_location(compiler, aggregate_source_kind(tables, compiler, left), aggregate_source_id(tables, compiler, left))
    }
    let right_location = aggregate_source_location(compiler, aggregate_source_kind(tables, compiler, right), aggregate_source_id(tables, compiler, right))
    let destination = aggregate_destination_location(compiler, 0L, node)
    let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
    let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    for operand in 0L..2L {
        let location = if operand == 0L { left_location } else { right_location }
        let pointer = if operand == 0L { left_pointer } else { right_pointer }
        let operand_ty = if operand == 0L { left_ty } else { right_ty }
        let label = if operand == 0L { "concat.left" } else { "concat.right" }
        emit_text_source_length(compiler, ir, location, pointer, node, label)
        if result_kind == TYPE_KIND_TEXT {
            emit_text_source_points(compiler, ir, operand_ty, location, pointer, node, label)
        }
    }
    ir_write_ascii(compiler, ir, "  %text.concat.length.total."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %text.concat.left.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %text.concat.right.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.concat.length.destination."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer); ir_write_ascii(compiler, ir, ", i64 0\n  store i64 %text.concat.length.total."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %text.concat.length.destination."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    if result_kind == TYPE_KIND_TEXT {
        ir_write_ascii(compiler, ir, "  %text.concat.points.total."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %text.concat.left.points."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %text.concat.right.points."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, "\n  %text.concat.points.destination."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer); ir_write_ascii(compiler, ir, ", i64 8\n  store i64 %text.concat.points.total."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %text.concat.points.destination."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    }
    let destination_data_offset = text_data_offset(compiler, result_ty)
    emit_text_copy_range(compiler, ir, node, 0L, left_location, left_pointer, text_location_data_offset(compiler, left_ty, left_location),
        destination, destination_pointer, destination_data_offset, false, 0L)
    emit_text_copy_range(compiler, ir, node, 1L, right_location, right_pointer, text_location_data_offset(compiler, right_ty, right_location),
        destination, destination_pointer, destination_data_offset, true, 1L)
    if is_test && result_kind == TYPE_KIND_TEXT {
        ir_write_ascii(compiler, ir, "  %text.concat.test.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, destination_data_offset)
        ir_write_ascii(compiler, ir, "\n  call void @nl_core_nl_text_assert_valid(ptr %nl.ctx, ptr %text.concat.test.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %text.concat.length.total."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
    }
}

fn emit_text_compare(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    operation: long,
) {
    let left = compiler.child_first[node]
    let right = if left >= 0L { compiler.child_next[left] } else { -1L }
    if left < 0L || right < 0L { compiler.ir_overflow = true; return }
    let left_ty = compiler.facts[left].ty
    let right_ty = compiler.facts[right].ty
    let left_location = if text_compare_left_needs_snapshot(tables, compiler, node) { compiler_location(compiler, 0L, left, 0L) }
        else { aggregate_source_location(compiler, aggregate_source_kind(tables, compiler, left), aggregate_source_id(tables, compiler, left)) }
    let right_location = aggregate_source_location(compiler, aggregate_source_kind(tables, compiler, right), aggregate_source_id(tables, compiler, right))
    let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
    let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
    let left_data_offset = text_location_data_offset(compiler, left_ty, left_location)
    let right_data_offset = text_location_data_offset(compiler, right_ty, right_location)
    let left_data_location = StorageLocation { origin: left_location.origin, anchor_kind: left_location.anchor_kind, anchor_node: left_location.anchor_node, byte_offset: left_location.byte_offset + left_data_offset, copies: left_location.copies, index: left_location.index, index_node: left_location.index_node, index_stride: left_location.index_stride }
    let right_data_location = StorageLocation { origin: right_location.origin, anchor_kind: right_location.anchor_kind, anchor_node: right_location.anchor_node, byte_offset: right_location.byte_offset + right_data_offset, copies: right_location.copies, index: right_location.index, index_node: right_location.index_node, index_stride: right_location.index_stride }
    let left_data = emit_location_pointer_materialization(compiler, ir, left_data_location)
    let right_data = emit_location_pointer_materialization(compiler, ir, right_data_location)
    emit_text_source_length(compiler, ir, left_location, left_pointer, node, "compare.left")
    emit_text_source_length(compiler, ir, right_location, right_pointer, node, "compare.right")
    ir_write_ascii(compiler, ir, "  %text.compare.left.short."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ule i64 %text.compare.left.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.compare.right.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.compare.minimum."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = select i1 %text.compare.left.short."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %text.compare.left.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %text.compare.right.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br label %text.compare.init."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.compare.init."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  br label %text.compare.loop."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.compare.loop."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.compare.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = phi i64 [ 0, %text.compare.init."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " ], [ %text.compare.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.compare.advance."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " ]\n  %text.compare.more."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ult i64 %text.compare.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.compare.minimum."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br i1 %text.compare.more."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.compare.body."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.compare.lengths."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.compare.body."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.compare.left.byte.ptr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, left_data_location, left_data)
    ir_write_ascii(compiler, ir, ", i64 %text.compare.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.compare.right.byte.ptr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, right_data_location, right_data)
    ir_write_ascii(compiler, ir, ", i64 %text.compare.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.compare.left.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i8, ptr %text.compare.left.byte.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    ir_write_ascii(compiler, ir, "  %text.compare.right.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i8, ptr %text.compare.right.byte.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    ir_write_ascii(compiler, ir, "  %text.compare.byte.same."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp eq i8 %text.compare.left.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.compare.right.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br i1 %text.compare.byte.same."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.compare.advance."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %text.compare.different."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.compare.different."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.compare.byte.less."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ult i8 %text.compare.left.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.compare.right.byte."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.compare.first.result."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = select i1 %text.compare.byte.less."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i32 -1, i32 1\n  br label %text.compare.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.compare.advance."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.compare.next."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = add i64 %text.compare.index."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", 1\n  br label %text.compare.loop."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.compare.lengths."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.compare.length.less."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ult i64 %text.compare.left.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.compare.right.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.compare.length.greater."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ugt i64 %text.compare.left.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.compare.right.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %text.compare.length.result."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = select i1 %text.compare.length.less."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i32 -1, i32 0\n  %text.compare.length.final."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = select i1 %text.compare.length.greater."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i32 1, i32 %text.compare.length.result."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  br label %text.compare.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\ntext.compare.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n  %text.compare.result."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = phi i32 [ %text.compare.first.result."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.compare.different."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " ], [ %text.compare.length.final."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %text.compare.lengths."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ]\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ")
    ir_write_ascii(compiler, ir, if operation == 8L { "eq" } else if operation == 9L { "ne" } else if operation == 10L { "slt" } else if operation == 11L { "sle" } else if operation == 12L { "sgt" } else { "sge" })
    ir_write_ascii(compiler, ir, " i32 %text.compare.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
}

fn intern_text_type_syntax(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    node: long,
) -> long {
    let syntax = tables.nodes[node]
    let kind = text_type_syntax_kind(source, tokens, files, file_index, syntax)
    if kind == 0L { return -1L }
    let argument_count = syntax.meta1 & 2097151L
    let constant_count = (syntax.meta1 >> 21L) & 2097151L
    if argument_count != 0L || (syntax.flags & FLAG_RANGE) != 0L { return -1L }

    var child = compiler.child_first[node]
    for argument_step in 0L..argument_count { if child >= 0L { child = compiler.child_next[child] } }
    var first_max = -1L
    var second_max = -1L
    if constant_count > 0L {
        first_max = child
        child = if child >= 0L { compiler.child_next[child] } else { -1L }
    }
    if constant_count > 1L {
        second_max = child
        child = if child >= 0L { compiler.child_next[child] } else { -1L }
    }

    if kind == TYPE_KIND_ASCII || kind == TYPE_KIND_BYTES {
        if constant_count == 0L {
            fail_at_message(env, files, compiler, file_index, syntax.start,
                if kind == TYPE_KIND_ASCII { "Ascii needs a bound; write 'Ascii max N'" }
                else { "Bytes needs a bound; write 'Bytes max N'" })
        }
        if constant_count != 1L { return -1L }
        let evaluated = evaluate_collection_capacity(tables, compiler, first_max, 0L)
        if !evaluated.constant {
            fail_at_message(env, files, compiler, file_index,
                if first_max >= 0L { tables.nodes[first_max].start } else { syntax.start },
                "maximum must be a constant integer expression")
        }
        if !evaluated.valid { text_type_capacity_error(env, files, compiler, file_index, syntax.start, kind, true) }
        if evaluated.value < 0L { text_type_capacity_error(env, files, compiler, file_index, tables.nodes[first_max].start, kind, false) }
        if evaluated.value > MAX_VALUE_SIZE - 8L { text_type_capacity_error(env, files, compiler, file_index, syntax.start, kind, true) }
        let name_id = compiler.token_name_ids[syntax.token]
        intern_text_type(compiler, kind, evaluated.value, 0L, file_index, node, name_id, syntax.token)
    } else {
        if constant_count == 0L {
            fail_at_message(env, files, compiler, file_index, syntax.start,
                "Text needs a bound; write 'Text max N' or 'Text bytes max N'")
        }
        if constant_count > 2L { return -1L }
        let first = evaluate_collection_capacity(tables, compiler, first_max, 0L)
        if !first.constant {
            fail_at_message(env, files, compiler, file_index, tables.nodes[first_max].start,
                "maximum must be a constant integer expression")
        }
        if !first.valid { text_type_capacity_error(env, files, compiler, file_index, syntax.start, kind, true) }
        var max_codepoints = first.value
        var max_bytes = 0L
        if (syntax.flags & FLAG_TYPE_TEXT_BYTES) != 0L {
            max_bytes = first.value
        } else if second_max >= 0L {
            let second = evaluate_collection_capacity(tables, compiler, second_max, 0L)
            if !second.constant { fail_at_message(env, files, compiler, file_index, tables.nodes[second_max].start, "maximum must be a constant integer expression") }
            if !second.valid { text_type_capacity_error(env, files, compiler, file_index, syntax.start, kind, true) }
            max_bytes = second.value
        } else {
            if max_codepoints > MAX_VALUE_SIZE / 4L { text_type_capacity_error(env, files, compiler, file_index, tables.nodes[first_max].start, kind, true) }
            max_bytes = max_codepoints * 4L
        }
        if max_codepoints < 0L || max_bytes < 0L {
            text_type_capacity_error(env, files, compiler, file_index, syntax.start, kind, false)
        }
        let name_id = compiler.token_name_ids[syntax.token]
        if max_bytes > MAX_VALUE_SIZE - 16L {
            text_type_capacity_error(env, files, compiler, file_index, syntax.start, kind, true)
        }
        intern_text_type(compiler, kind, max_bytes, max_codepoints, file_index, node, name_id, syntax.token)
    }
}
