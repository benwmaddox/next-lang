const FORMAT_TEXT_NONE: long = 0L
const FORMAT_TEXT_STR: long = 1L
const FORMAT_TEXT_HEX: long = 2L
const FORMAT_TEXT_BIN: long = 3L
const FORMAT_TEXT_PAD: long = 4L
const FORMAT_TEXT_PAD_RIGHT: long = 5L
const FORMAT_TEXT_PAD_ZERO: long = 6L
const FORMAT_TEXT_ASCII_UPPER: long = 7L
const FACT_FORMAT_TEXT: long = 16L

fn format_text_builtin_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
) -> long {
    if node < 0L || node >= compiler.facts.count() { return FORMAT_TEXT_NONE }
    let callee_token = tables.nodes[node].token
    if token_is_word_at(source, tokens, files, file_index, callee_token, "str") {
        FORMAT_TEXT_STR
    } else if token_is_word_at(source, tokens, files, file_index, callee_token, "str_hex") { FORMAT_TEXT_HEX }
    else if token_is_word_at(source, tokens, files, file_index, callee_token, "str_bin") { FORMAT_TEXT_BIN }
    else if token_is_word_at(source, tokens, files, file_index, callee_token, "pad") { FORMAT_TEXT_PAD }
    else if token_is_word_at(source, tokens, files, file_index, callee_token, "pad_right") { FORMAT_TEXT_PAD_RIGHT }
    else if token_is_word_at(source, tokens, files, file_index, callee_token, "pad_zero") { FORMAT_TEXT_PAD_ZERO }
    else if token_is_word_at(source, tokens, files, file_index, callee_token, "ascii_upper") { FORMAT_TEXT_ASCII_UPPER }
    else { FORMAT_TEXT_NONE }
}

fn format_text_digit_count(value: long, radix: long) -> long {
    var remaining = value
    if remaining > 0L { remaining = 0L - remaining }
    var digits = 1L
    remaining = remaining / radix
    for step in 0L..64L {
        if remaining == 0L { break }
        digits += 1L
        remaining = remaining / radix
    }
    digits
}

fn format_text_number_maximum(tables: ParseTables, compiler: CompilerTables, node: long, ty: long, radix: long) -> long {
    let value = evaluate_collection_capacity(tables, compiler, node, 0L)
    if value.constant && value.valid {
        format_text_digit_count(value.value, radix) + if value.value < 0L { 1L } else { 0L }
    } else if ty == TY_BYTE {
        format_text_digit_count(255L, radix)
    } else {
        let minimum = if ty == TY_INT { -2147483648L } else { -9223372036854775807L - 1L }
        format_text_digit_count(minimum, radix) + 1L
    }
}

fn format_text_width_maximum(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    call_node: long,
    width_node: long,
) -> long {
    let width_type = compiler.facts[width_node].ty
    if width_type != TY_INT && width_type != TY_LONG {
        fail_at_message(env, files, compiler, file_index, tables.nodes[width_node].start,
            "padding width must be an int or long constant; use a nonnegative value")
    }
    let value = evaluate_collection_capacity(tables, compiler, width_node, 0L)
    if !value.constant {
        fail_at_message(env, files, compiler, file_index, tables.nodes[width_node].start,
            "padding width must be a nonnegative constant or refined long; use a long 0..=N refinement")
    }
    if !value.valid {
        fail_at_message(env, files, compiler, file_index, tables.nodes[width_node].start,
            "padding width maximum must fit long; reduce it")
    }
    if value.value < 0L {
        fail_at_message(env, files, compiler, file_index, tables.nodes[width_node].start,
            "padding width must be a nonnegative constant or refined long; use a long 0..=N refinement")
    }
    let _ = call_node
    value.value
}

fn format_text_numeric_type(ty: long) -> bool { ty == TY_INT || ty == TY_LONG || ty == TY_BYTE }

fn format_text_check_capacity(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    node: long,
    kind: long,
    max_bytes: long,
    max_codepoints: long,
) {
    if kind == TYPE_KIND_ASCII {
        if max_bytes < 0L || max_bytes > MAX_VALUE_SIZE - 8L {
            fail_at_message(env, files, compiler, file_index, node,
                "formatted Ascii maximum exceeds the supported value size; reduce a value or width")
        }
    } else if kind == TYPE_KIND_TEXT {
        if max_bytes < 0L || max_bytes > MAX_VALUE_SIZE - 16L ||
            max_codepoints < 0L || max_codepoints > MAX_VALUE_SIZE - 16L {
            fail_at_message(env, files, compiler, file_index, node,
                "formatted Text maximum exceeds the supported value size; reduce a value or width")
        }
    } else {
        fail_at_message(env, files, compiler, file_index, node,
            "formatted text result has an unsupported type")
    }
}

fn check_format_text_builtin(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    node: long,
    expected: long,
) -> long {
    let kind = format_text_builtin_kind(source, tokens, files, tables, compiler, file_index, node)
    let argument_count = count_children(tables, compiler, node)
    let wants_two = kind == FORMAT_TEXT_PAD || kind == FORMAT_TEXT_PAD_RIGHT || kind == FORMAT_TEXT_PAD_ZERO
    let expected_argument_count = if wants_two { 2L } else { 1L }
    if argument_count != expected_argument_count {
        let name = if kind == FORMAT_TEXT_STR { "str" }
            else if kind == FORMAT_TEXT_HEX { "str_hex" }
            else if kind == FORMAT_TEXT_BIN { "str_bin" }
            else if kind == FORMAT_TEXT_PAD { "pad" }
            else if kind == FORMAT_TEXT_PAD_RIGHT { "pad_right" }
            else if kind == FORMAT_TEXT_PAD_ZERO { "pad_zero" }
            else { "ascii_upper" }
        let expected_count = if wants_two { "two" } else { "one" }
        fail_at_message(env, files, compiler, file_index, tables.nodes[node].start,
            name + " takes " + expected_count + " argument(s)")
    }
    let argument = compiler.child_first[node]
    let argument_type = compiler.facts[argument].ty
    var result_type = -1L
    if kind == FORMAT_TEXT_STR || kind == FORMAT_TEXT_HEX || kind == FORMAT_TEXT_BIN {
        if !format_text_numeric_type(argument_type) {
            let name = if kind == FORMAT_TEXT_STR { "str" }
                else if kind == FORMAT_TEXT_HEX { "str_hex" }
                else { "str_bin" }
            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start,
                name + " needs int, long, or byte; found " + type_name_or_fallback(argument_type))
        }
        let radix = if kind == FORMAT_TEXT_HEX { 16L } else if kind == FORMAT_TEXT_BIN { 2L } else { 10L }
        let maximum = format_text_number_maximum(tables, compiler, argument, argument_type, radix)
        format_text_check_capacity(env, files, compiler, file_index, tables.nodes[node].start,
            TYPE_KIND_ASCII, maximum, 0L)
        result_type = intern_text_type(compiler, TYPE_KIND_ASCII, maximum, 0L, file_index, node, -1L, -1L)
    } else if kind == FORMAT_TEXT_ASCII_UPPER {
        if type_kind(compiler, argument_type) != TYPE_KIND_ASCII {
            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start,
                "ascii_upper needs Ascii; found " + type_name_or_fallback(argument_type))
        }
        result_type = argument_type
    } else if kind == FORMAT_TEXT_PAD || kind == FORMAT_TEXT_PAD_RIGHT {
        let argument_kind = type_kind(compiler, argument_type)
        if argument_kind != TYPE_KIND_ASCII && argument_kind != TYPE_KIND_TEXT {
            let name = if kind == FORMAT_TEXT_PAD { "pad" } else { "pad_right" }
            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start,
                name + " needs an Ascii or Text value; found " + type_name_or_fallback(argument_type))
        }
        let width_node = compiler.child_next[argument]
        let width_maximum = format_text_width_maximum(env, files, tables, compiler, file_index, node, width_node)
        if argument_kind == TYPE_KIND_ASCII {
            let maximum = if text_max_bytes(compiler, argument_type) > width_maximum {
                text_max_bytes(compiler, argument_type)
            } else { width_maximum }
            format_text_check_capacity(env, files, compiler, file_index, tables.nodes[node].start,
                TYPE_KIND_ASCII, maximum, 0L)
            result_type = intern_text_type(compiler, TYPE_KIND_ASCII, maximum, 0L, file_index, node, -1L, -1L)
        } else {
            let points = if text_max_codepoints(compiler, argument_type) > width_maximum {
                text_max_codepoints(compiler, argument_type)
            } else { width_maximum }
            let bytes = text_max_bytes(compiler, argument_type)
            if width_maximum > MAX_VALUE_SIZE - 16L ||
                bytes > MAX_VALUE_SIZE - 16L - width_maximum {
                fail_at_message(env, files, compiler, file_index, tables.nodes[node].start,
                    "padding Text byte maximum overflows long; reduce an operand maximum")
            }
            let padded_bytes = bytes + width_maximum
            let maximum = if padded_bytes > points { padded_bytes } else { points }
            format_text_check_capacity(env, files, compiler, file_index, tables.nodes[node].start,
                TYPE_KIND_TEXT, maximum, points)
            result_type = intern_text_type(compiler, TYPE_KIND_TEXT, maximum, points, file_index, node, -1L, -1L)
        }
    } else if kind == FORMAT_TEXT_PAD_ZERO {
        if !format_text_numeric_type(argument_type) {
            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start,
                "pad_zero needs int, long, or byte; found " + type_name_or_fallback(argument_type))
        }
        let width_node = compiler.child_next[argument]
        let width_maximum = format_text_width_maximum(env, files, tables, compiler, file_index, node, width_node)
        let formatted = format_text_number_maximum(tables, compiler, argument, argument_type, 10L)
        let maximum = if formatted > width_maximum { formatted } else { width_maximum }
        format_text_check_capacity(env, files, compiler, file_index, tables.nodes[node].start,
            TYPE_KIND_ASCII, maximum, 0L)
        result_type = intern_text_type(compiler, TYPE_KIND_ASCII, maximum, 0L, file_index, node, -1L, -1L)
    } else { compiler.table_failed = true }

    if result_type < 0L {
        fail_at_message(env, files, compiler, file_index, tables.nodes[node].start,
            "formatted text result exceeds the supported value size")
    }
    if expected >= 0L && expected != result_type {
        require_type(env, files, compiler, file_index, node, expected, result_type, tables)
    }
    result_type
}

fn emit_format_text_numeric_i64(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    argument: long,
) {
    let ty = compiler.facts[argument].ty
    ir_write_ascii(compiler, ir, "  %text.format.number."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ")
    if ty == TY_LONG {
        ir_write_ascii(compiler, ir, "add i64 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", 0\n")
    } else if ty == TY_BYTE {
        ir_write_ascii(compiler, ir, "zext i32 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n")
    } else if ty == TY_INT {
        ir_write_ascii(compiler, ir, "sext i32 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n")
    } else { compiler.ir_overflow = true }
}

fn emit_format_text_width_i64(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    argument: long,
) {
    let ty = compiler.facts[argument].ty
    ir_write_ascii(compiler, ir, "  %text.format.width."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ")
    if ty == TY_LONG {
        ir_write_ascii(compiler, ir, "add i64 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", 0\n")
    } else if ty == TY_INT {
        ir_write_ascii(compiler, ir, "sext i32 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n")
    } else { compiler.ir_overflow = true }
}

fn emit_format_text_store_length(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    destination: StorageLocation,
    pointer: long,
) {
    ir_write_ascii(compiler, ir, "  %text.format.output.length.addr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer)
    ir_write_ascii(compiler, ir, ", i64 0\n  store i64 %text.format.written."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %text.format.output.length.addr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
}

fn emit_format_text_builtin(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    is_test: bool,
    kind: long,
) {
    let argument = compiler.child_first[node]
    let argument_type = compiler.facts[argument].ty
    let result_type = compiler.facts[node].ty
    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    let output_data_offset = text_data_offset(compiler, result_type)
    ir_write_ascii(compiler, ir, "  %text.format.output.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, output_data_offset); ir_push_byte(compiler, ir, 10)

    if kind == FORMAT_TEXT_ASCII_UPPER {
        let source_location = aggregate_destination_location(compiler, 0L, argument)
        let source_pointer = emit_location_pointer_materialization(compiler, ir, source_location)
        emit_text_source_length(compiler, ir, source_location, source_pointer, node, "format.src")
        let source_data_offset = text_location_data_offset(compiler, argument_type, source_location)
        ir_write_ascii(compiler, ir, "  %text.format.source.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, source_data_offset); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %text.format.written."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i64 @nl_core_nl_text_format_ascii_upper(ptr %nl.ctx, ptr %text.format.source.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.format.src.length."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr %text.format.output.data."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 41); ir_push_byte(compiler, ir, 10)
    } else if kind == FORMAT_TEXT_STR || kind == FORMAT_TEXT_HEX || kind == FORMAT_TEXT_BIN {
        emit_format_text_numeric_i64(compiler, ir, node, argument)
        let radix = if kind == FORMAT_TEXT_HEX { 16L } else if kind == FORMAT_TEXT_BIN { 2L } else { 10L }
        ir_write_ascii(compiler, ir, "  %text.format.written."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i64 @nl_core_nl_text_format_number(ptr %nl.ctx, i64 %text.format.number."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, radix)
        ir_write_ascii(compiler, ir, ", ptr %text.format.output.data."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 41); ir_push_byte(compiler, ir, 10)
    } else if kind == FORMAT_TEXT_PAD_ZERO {
        let width_node = compiler.child_next[argument]
        emit_format_text_numeric_i64(compiler, ir, node, argument)
        emit_format_text_width_i64(compiler, ir, node, width_node)
        ir_write_ascii(compiler, ir, "  %text.format.written."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i64 @nl_core_nl_text_format_pad_zero(ptr %nl.ctx, i64 %text.format.number."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.format.width."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr %text.format.output.data."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 41); ir_push_byte(compiler, ir, 10)
    } else if kind == FORMAT_TEXT_PAD || kind == FORMAT_TEXT_PAD_RIGHT {
        let width_node = compiler.child_next[argument]
        let source_location = aggregate_destination_location(compiler, 0L, argument)
        let source_pointer = emit_location_pointer_materialization(compiler, ir, source_location)
        emit_text_source_length(compiler, ir, source_location, source_pointer, node, "format.src")
        emit_text_source_points(compiler, ir, argument_type, source_location, source_pointer, node, "format.src")
        let source_data_offset = text_location_data_offset(compiler, argument_type, source_location)
        ir_write_ascii(compiler, ir, "  %text.format.source.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, source_data_offset); ir_push_byte(compiler, ir, 10)
        emit_format_text_width_i64(compiler, ir, node, width_node)
        ir_write_ascii(compiler, ir, "  %text.format.written."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i64 @nl_core_nl_text_format_pad(ptr %nl.ctx, ptr %text.format.source.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.format.src.length."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.format.src.points."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.format.width."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, if kind == FORMAT_TEXT_PAD { ", i1 true, ptr %text.format.output.data." } else { ", i1 false, ptr %text.format.output.data." })
        ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 41); ir_push_byte(compiler, ir, 10)
        if type_kind(compiler, result_type) == TYPE_KIND_TEXT {
            ir_write_ascii(compiler, ir, "  %text.format.output.points.addr."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
            ir_write_ascii(compiler, ir, ", i64 8\n  %text.format.width.greater."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = icmp sgt i64 %text.format.width."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ", %text.format.src.points."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, "\n  %text.format.output.points."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = select i1 %text.format.width.greater."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ", i64 %text.format.width."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ", i64 %text.format.src.points."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, "\n  store i64 %text.format.output.points."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ", ptr %text.format.output.points.addr."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        }
    } else { compiler.ir_overflow = true }

    emit_format_text_store_length(compiler, ir, node, destination, destination_pointer)
    if (is_test || compiler.test_build) && type_kind(compiler, result_type) == TYPE_KIND_TEXT {
        ir_write_ascii(compiler, ir, "  call void @nl_core_nl_text_assert_valid(ptr %nl.ctx, ptr %text.format.output.data."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %text.format.written."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 41); ir_push_byte(compiler, ir, 10)
    }
}
