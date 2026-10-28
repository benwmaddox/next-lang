const PARSE_NUMBER_NONE: long = 0L
const PARSE_NUMBER_INT: long = 3001L
const PARSE_NUMBER_LONG: long = 3002L
const PARSE_NUMBER_INT_RADIX: long = 3003L
const PARSE_NUMBER_LONG_RADIX: long = 3004L
const PARSE_NUMBER_INT_LITERAL: long = 3005L

fn parse_number_method_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    method_token: long,
) -> long {
    if token_is_word_at(source, tokens, files, file_index, method_token, "parse_int") { PARSE_NUMBER_INT }
    else if token_is_word_at(source, tokens, files, file_index, method_token, "parse_long") { PARSE_NUMBER_LONG }
    else if token_is_word_at(source, tokens, files, file_index, method_token, "parse_int_radix") { PARSE_NUMBER_INT_RADIX }
    else if token_is_word_at(source, tokens, files, file_index, method_token, "parse_long_radix") { PARSE_NUMBER_LONG_RADIX }
    else if token_is_word_at(source, tokens, files, file_index, method_token, "parse_int_literal") { PARSE_NUMBER_INT_LITERAL }
    else { PARSE_NUMBER_NONE }
}

fn parse_number_method_name(kind: long) -> Ascii max 32 {
    if kind == PARSE_NUMBER_INT { "parse_int" }
    else if kind == PARSE_NUMBER_LONG { "parse_long" }
    else if kind == PARSE_NUMBER_INT_RADIX { "parse_int_radix" }
    else if kind == PARSE_NUMBER_LONG_RADIX { "parse_long_radix" }
    else { "parse_int_literal" }
}

fn check_parse_number_method(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    node: long,
    expected: long,
) -> bool {
    let syntax = tables.nodes[node]
    let kind = parse_number_method_kind(source, tokens, files, file_index, syntax.token)
    if kind == PARSE_NUMBER_NONE { return false }
    let method_name = parse_number_method_name(kind)
    let receiver = compiler.child_first[node]
    if receiver < 0L {
        let message: Ascii max 160 = method_name + " needs an Ascii, Text, or Bytes value"
        fail_at_message(env, files, compiler, file_index, syntax.anchor, message)
    }
    let receiver_type = compiler.facts[receiver].ty
    let receiver_kind = type_kind(compiler, receiver_type)
    if receiver_kind != TYPE_KIND_ASCII && receiver_kind != TYPE_KIND_TEXT && receiver_kind != TYPE_KIND_BYTES {
        let message: Ascii max 160 = type_name_or_fallback(receiver_type) + "." + method_name + " needs an Ascii, Text, or Bytes value"
        fail_at_message(env, files, compiler, file_index, syntax.anchor, message)
    }

    let radix_method = kind == PARSE_NUMBER_INT_RADIX || kind == PARSE_NUMBER_LONG_RADIX
    let argument_count = count_children(tables, compiler, node) - 1L
    if radix_method {
        if argument_count != 1L {
            let message: Ascii max 160 = method_name + "(radix) takes one constant radix"
            fail_at_message(env, files, compiler, file_index, syntax.start, message)
        }
    } else if argument_count != 0L {
        let message: Ascii max 160 = method_name + "() takes no arguments"
        fail_at_message(env, files, compiler, file_index, syntax.start, message)
    } else { () }

    var radix = 10L
    if radix_method {
        let argument = compiler.child_next[receiver]
        if argument < 0L {
            let message: Ascii max 160 = method_name + "(radix) takes one constant radix"
            fail_at_message(env, files, compiler, file_index, syntax.start, message)
        }
        let value = evaluate_collection_capacity(tables, compiler, argument, 0L)
        if !value.constant || !value.valid {
            let message: Ascii max 160 = method_name + " needs a constant radix of 2, 8, 10, or 16"
            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, message)
        }
        if value.value != 2L && value.value != 8L && value.value != 10L && value.value != 16L {
            let message: Ascii max 160 = method_name + " supports only 2, 8, 10, or 16"
            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, message)
        }
        radix = value.value
    } else { () }

    let target_type = if kind == PARSE_NUMBER_INT || kind == PARSE_NUMBER_INT_RADIX { TY_INT } else { TY_LONG }
    let result_type = intern_sum_type(compiler, TYPE_KIND_OPTION, target_type, -1L, file_index, node, -1L, -1L)
    if result_type < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "Option type for integer parsing is unavailable") }
    if expected >= 0L && expected != result_type { require_type(env, files, compiler, file_index, node, expected, result_type, tables) }
    compiler.facts[node] = NodeFact {
        ty: result_type,
        flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER },
        binding: -1L,
        function: -1L,
        literal: radix,
    }
    true
}

fn emit_parse_number_method(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let kind = parse_number_method_kind(source, tokens, files, file_index, tables.nodes[node].token)
    let receiver = compiler.child_first[node]
    if kind == PARSE_NUMBER_NONE || receiver < 0L {
        compiler.ir_overflow = true
        return
    }
    let receiver_type = compiler.facts[receiver].ty
    let target_type = sum_case_payload_type(compiler, compiler.facts[node].ty, 0L, 0L)
    let target_bits = if target_type == TY_INT { 32L } else if target_type == TY_LONG { 64L } else { -1L }
    let data_offset = text_data_offset(compiler, receiver_type)
    if target_bits < 0L || data_offset < 0L { compiler.ir_overflow = true; return }

    let source_location = text_method_receiver_location(tables, compiler, node)
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source_location)
    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    let source_data_offset = text_location_data_offset(compiler, receiver_type, source_location)
    let radix = compiler.facts[node].literal
    emit_text_source_length(compiler, ir, source_location, source_pointer, node, "parse")
    ir_write_ascii(compiler, ir, "  %number.parse.source."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, source_data_offset); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  call void @nl_core_parse_integer_option(ptr %nl.ctx, ptr %number.parse.source."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %text.parse.length."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, radix)
    ir_write_ascii(compiler, ir, ", i1 "); ir_write_number(compiler, ir, if kind == PARSE_NUMBER_INT_LITERAL { 1L } else { 0L })
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, target_bits)
    ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer); ir_write_ascii(compiler, ir, ")\n")
}
