// double: a 64-bit IEEE number, on the C runtime only. A plain double never holds NaN: an operation that
// would produce one (0.0 / 0.0, inf - inf) fails the job at that line, as an integer overflow does.
// Infinities are allowed. Literals are kept as written and rounded to the nearest double by LLVM.
// Conversions are written as casts: (double)n for an int or long, (long)d / (int)d / (byte)d the other
// way, which truncate toward zero and fail when the result does not fit. `n.to_double()` is the short
// form of the widening cast, `ascii.parse_double()` gives an Option<double>, and `str_fixed(x, n)` is
// the text of x with n digits after the point (Rust's {:.n}).

const FACT_DOUBLE_METHOD: long = 8192L
const DOUBLE_METHOD_TO_DOUBLE: long = 1L
const DOUBLE_METHOD_PARSE: long = 2L
const FAILURE_NAN: long = 22L
const FAILURE_FIXED_TEXT: long = 24L
const FIXED_TEXT_MAXIMUM: long = 64L

fn double_method_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    token: long,
    receiver_ty: long,
) -> long {
    if !compiler.c_runtime { return 0L }
    if token_is_word_at(source, tokens, files, file_index, token, "to_double") &&
        (receiver_ty == TY_INT || receiver_ty == TY_LONG || receiver_ty == TY_BYTE) { return DOUBLE_METHOD_TO_DOUBLE }
    if token_is_word_at(source, tokens, files, file_index, token, "parse_double") &&
        type_kind(compiler, receiver_ty) == TYPE_KIND_ASCII { return DOUBLE_METHOD_PARSE }
    0L
}

// The literal as written, without digit separators.
fn emit_float_literal(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let token = tables.nodes[node].token
    let start = files[file_index].base + tokens[token].start
    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = fadd double 0.0, ")
    for offset in 0L..tokens[token].length {
        let value = source[start + offset]
        if value != 95 { ir_push_byte(compiler, ir, value) }
    }
    ir_push_byte(compiler, ir, 10)
}

// The failure when the double in %value_name is NaN. The flag is %ov.flag.<node> for emit_runtime_failure.
fn emit_double_nan_check(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    value_ref_node: long,
) {
    ir_write_ascii(compiler, ir, "  %ov.flag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = fcmp uno double %v")
    ir_write_number(compiler, ir, value_ref_node); ir_write_ascii(compiler, ir, ", %v"); ir_write_number(compiler, ir, value_ref_node); ir_push_byte(compiler, ir, 10)
    emit_runtime_failure(files, tables, compiler, ir, node, file_index, FAILURE_NAN)
}

// + - * / and comparisons on two doubles.
fn emit_double_binary(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    op: long,
    left: long,
    right: long,
) {
    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ")
    if op <= 3L {
        if op == 0L { ir_write_ascii(compiler, ir, "fadd double ") }
        else if op == 1L { ir_write_ascii(compiler, ir, "fsub double ") }
        else if op == 2L { ir_write_ascii(compiler, ir, "fmul double ") }
        else { ir_write_ascii(compiler, ir, "fdiv double ") }
    } else {
        if op == 8L { ir_write_ascii(compiler, ir, "fcmp oeq double ") }
        else if op == 9L { ir_write_ascii(compiler, ir, "fcmp une double ") }
        else if op == 10L { ir_write_ascii(compiler, ir, "fcmp olt double ") }
        else if op == 11L { ir_write_ascii(compiler, ir, "fcmp ole double ") }
        else if op == 12L { ir_write_ascii(compiler, ir, "fcmp ogt double ") }
        else { ir_write_ascii(compiler, ir, "fcmp oge double ") }
    }
    ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_push_byte(compiler, ir, 10)
    if op <= 3L { emit_double_nan_check(files, tables, compiler, ir, node, file_index, node) }
}

fn emit_double_negate(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long, operand: long) {
    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = fneg double "); ir_write_value_ref(compiler, ir, operand); ir_push_byte(compiler, ir, 10)
}

// Casts between doubles and the integer types.
fn emit_double_cast(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    operand: long,
    source_ty: long,
    target_ty: long,
) {
    if source_ty == target_ty {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = fadd double 0.0, "); ir_write_value_ref(compiler, ir, operand); ir_push_byte(compiler, ir, 10)
        return
    }
    if target_ty == TY_DOUBLE {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sitofp "); ir_write_ascii(compiler, ir, llvm_type_name(source_ty))
        ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, operand); ir_write_ascii(compiler, ir, " to double\n")
        return
    }
    // double to an integer: truncate toward zero, then fail unless the result fits
    let low: Ascii max 32 = if target_ty == TY_LONG { "-9.223372036854775808e18" } else if target_ty == TY_INT { "-2147483648.0" } else { "0.0" }
    let high: Ascii max 32 = if target_ty == TY_LONG { "9.223372036854775808e18" } else if target_ty == TY_INT { "2147483648.0" } else { "256.0" }
    ir_write_ascii(compiler, ir, "  %cast.trunc."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call double @llvm.trunc.f64(double "); ir_write_value_ref(compiler, ir, operand)
    ir_write_ascii(compiler, ir, ")\n  %cast.low."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = fcmp oge double %cast.trunc."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ")
    ir_write_ascii(compiler, ir, low)
    ir_write_ascii(compiler, ir, "\n  %cast.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = fcmp olt double %cast.trunc."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ")
    ir_write_ascii(compiler, ir, high)
    ir_write_ascii(compiler, ir, "\n  %cast.fits."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = and i1 %cast.low."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %cast.high."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %ov.flag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = xor i1 %cast.fits."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", true\n")
    emit_runtime_failure(files, tables, compiler, ir, node, file_index, 10L)
    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = fptosi double %cast.trunc."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to ")
    ir_write_ascii(compiler, ir, llvm_type_name(target_ty)); ir_push_byte(compiler, ir, 10)
}

// x += y, -=, *=, /= on a double local, field or element.
fn emit_double_compound(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    target: long,
    binding: long,
    value: long,
    place_target: bool,
    op: long,
) {
    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ")
    if op == 1L { ir_write_ascii(compiler, ir, "fadd double %v") }
    else if op == 2L { ir_write_ascii(compiler, ir, "fsub double %v") }
    else if op == 3L { ir_write_ascii(compiler, ir, "fmul double %v") }
    else { ir_write_ascii(compiler, ir, "fdiv double %v") }
    ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, value); ir_push_byte(compiler, ir, 10)
    emit_double_nan_check(files, tables, compiler, ir, node, file_index, node)
    let address_id = if place_target { emit_late_place_address(tables, compiler, ir, target) } else { -1L }
    ir_write_ascii(compiler, ir, "  store double %v"); ir_write_number(compiler, ir, node)
    if place_target { ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", align 1") }
    else { ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1") }
    emit_program_storage_tbaa(compiler, ir)
    ir_push_byte(compiler, ir, 10)
}

// n.to_double() and ascii.parse_double()
fn emit_double_method(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    method: long,
) {
    let receiver = compiler.child_first[node]
    if method == DOUBLE_METHOD_TO_DOUBLE {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sitofp "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[receiver].ty))
        ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, receiver); ir_write_ascii(compiler, ir, " to double\n")
        return
    }
    // parse_double: Option<double>, none when the text is not a finite number
    let receiver_ty = compiler.facts[receiver].ty
    let location = text_method_receiver_location(tables, compiler, ir, node)
    let pointer = emit_location_pointer_materialization(compiler, ir, location)
    let data_offset = text_location_data_offset(compiler, receiver_ty, location)
    let result_type = compiler.facts[node].ty
    let payload = sum_payload_record(compiler, result_type, 0L, 0L)
    let address = enum_temporary_address(node, MAX_TREE_NODES * 3L + 2L)
    emit_layout_address(compiler, ir, address, storage_location_with_offset(aggregate_destination_location(compiler, 0L, node), payload.offset))
    ir_write_ascii(compiler, ir, "  %parse.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer)
    ir_write_ascii(compiler, ir, ", align 1\n  %parse.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, data_offset)
    ir_write_ascii(compiler, ir, "\n  %parse.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i1 @nl_parse_double(ptr %parse.data."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %parse.length."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address)
    ir_write_ascii(compiler, ir, ")\n  br i1 %parse.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %parse.some."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %parse.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nparse.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    emit_sum_tag_store(compiler, ir, node, 0L)
    ir_write_ascii(compiler, ir, "  br label %parse.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nparse.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    emit_sum_tag_store(compiler, ir, node, 1L)
    ir_write_ascii(compiler, ir, "  br label %parse.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nparse.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
}
