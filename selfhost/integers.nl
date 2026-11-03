// uint, ulong, ushort, short, sbyte: arithmetic, comparisons, shifts and casts (C runtime only).
//
// uint and ulong are unsigned 32 and 64 bit, held in i32 and i64 registers as bit patterns. ushort, short and sbyte are held in
// 32-bit registers with the value always in range (ushort zero-extended, short and sbyte sign-extended). Arithmetic is checked:
// uint and ulong use the unsigned overflow intrinsics (so `0u - 1u` fails); the narrow types compute in 64 bits and fail when the
// result leaves the type's range. The wrapping operators `+%`, `-%` and `*%` wrap at the type's width. Every emitter here writes
// its result to %v<node>.

const FAILURE_UNSIGNED_ADD: long = 28L
const FAILURE_UNSIGNED_SUB: long = 29L
const FAILURE_UNSIGNED_MUL: long = 30L
const FAILURE_NARROW_RANGE: long = 31L

fn int_type_signed(ty: long) -> bool { ty == TY_INT || ty == TY_LONG || ty == TY_SHORT || ty == TY_SBYTE }
fn int_type_narrow(ty: long) -> bool { ty == TY_USHORT || ty == TY_SHORT || ty == TY_SBYTE }
fn int_type_wide64(ty: long) -> bool { ty == TY_LONG || ty == TY_ULONG }

// the width of the type in bits, which bounds a shift count
fn int_type_bits(ty: long) -> long {
    if ty == TY_LONG || ty == TY_ULONG { 64L }
    else if ty == TY_USHORT || ty == TY_SHORT { 16L }
    else if ty == TY_SBYTE || ty == TY_BYTE { 8L }
    else { 32L }
}

fn int_type_low(ty: long) -> long {
    if ty == TY_INT { -2147483648L }
    else if ty == TY_SHORT { -32768L }
    else if ty == TY_SBYTE { -128L }
    else if ty == TY_LONG { -9223372036854775807L - 1L }
    else { 0L }
}

fn int_type_high(ty: long) -> long {
    if ty == TY_INT { 2147483647L }
    else if ty == TY_UINT { 4294967295L }
    else if ty == TY_USHORT { 65535L }
    else if ty == TY_SHORT { 32767L }
    else if ty == TY_SBYTE { 127L }
    else if ty == TY_BYTE { 255L }
    else { 9223372036854775807L }
}

fn int_w(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, text: Ascii max 256) { ir_write_ascii(compiler, ir, text) }
fn int_n(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: long) { ir_write_number(compiler, ir, value) }

// Branch to a failure when %nf.<tag>.<node> is true.
fn emit_int_failure(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    tag: long,
    kind: long,
) {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].anchor, compiler)
    int_w(compiler, ir, "  br i1 %nf."); int_n(compiler, ir, tag); int_w(compiler, ir, "."); int_n(compiler, ir, node)
    int_w(compiler, ir, ", label %nf.fail."); int_n(compiler, ir, tag); int_w(compiler, ir, "."); int_n(compiler, ir, node)
    int_w(compiler, ir, ", label %nf.ok."); int_n(compiler, ir, tag); int_w(compiler, ir, "."); int_n(compiler, ir, node)
    int_w(compiler, ir, "\nnf.fail."); int_n(compiler, ir, tag); int_w(compiler, ir, "."); int_n(compiler, ir, node); int_w(compiler, ir, ":\n")
    if compiler.memory_closure { int_w(compiler, ir, "  call void @llvm.trap()\n  unreachable\n") }
    else {
        int_w(compiler, ir, "  call void ")
        emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail")
        int_w(compiler, ir, "(ptr %nl.ctx, i32 "); int_n(compiler, ir, kind); int_w(compiler, ir, ", i32 "); int_n(compiler, ir, file_index + compiler_file_id_base(compiler))
        int_w(compiler, ir, ", i32 "); int_n(compiler, ir, position.line); int_w(compiler, ir, ", i32 "); int_n(compiler, ir, position.col); int_w(compiler, ir, ")\n  unreachable\n")
    }
    int_w(compiler, ir, "nf.ok."); int_n(compiler, ir, tag); int_w(compiler, ir, "."); int_n(compiler, ir, node); int_w(compiler, ir, ":\n")
}

// %<name>.<node> = the 32-bit register value `source` brought back into the narrow type's range by wrapping.
fn emit_int_wrap_narrow(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long, ty: long, source_name: Ascii max 32, result_name: Ascii max 32) {
    if ty == TY_USHORT {
        int_w(compiler, ir, "  "); int_w(compiler, ir, result_name); int_n(compiler, ir, node); int_w(compiler, ir, " = and i32 "); int_w(compiler, ir, source_name); int_n(compiler, ir, node); int_w(compiler, ir, ", 65535\n")
    } else {
        let shift: Ascii max 4 = if ty == TY_SHORT { "16" } else { "24" }
        int_w(compiler, ir, "  %wrap.shl."); int_n(compiler, ir, node); int_w(compiler, ir, " = shl i32 "); int_w(compiler, ir, source_name); int_n(compiler, ir, node); int_w(compiler, ir, ", "); int_w(compiler, ir, shift)
        int_w(compiler, ir, "\n  "); int_w(compiler, ir, result_name); int_n(compiler, ir, node); int_w(compiler, ir, " = ashr i32 %wrap.shl."); int_n(compiler, ir, node); int_w(compiler, ir, ", "); int_w(compiler, ir, shift); int_w(compiler, ir, "\n")
    }
}

// op: 0 + 1 - 2 * 3 / 4 % 5 +% 6 -% 7 *% 8 == 9 != 10 < 11 <= 12 > 13 >= 16 & 17 | 18 ^ 19 << 20 >>
fn emit_new_int_binary(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    op: long,
    left: long,
    right: long,
    ty: long,
) {
    let llty = llvm_type_name(ty)
    let signed = int_type_signed(ty)
    let narrow = int_type_narrow(ty)
    if op >= 8L && op <= 13L {
        int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp ")
        if op == 8L { int_w(compiler, ir, "eq ") }
        else if op == 9L { int_w(compiler, ir, "ne ") }
        else {
            int_w(compiler, ir, if signed { "s" } else { "u" })
            if op == 10L { int_w(compiler, ir, "lt ") } else if op == 11L { int_w(compiler, ir, "le ") } else if op == 12L { int_w(compiler, ir, "gt ") } else { int_w(compiler, ir, "ge ") }
        }
        int_w(compiler, ir, llty); int_w(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); int_w(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); int_w(compiler, ir, "\n")
        return
    }
    if op >= 16L && op <= 18L {
        int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = ")
        int_w(compiler, ir, if op == 16L { "and " } else if op == 17L { "or " } else { "xor " })
        int_w(compiler, ir, llty); int_w(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); int_w(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); int_w(compiler, ir, "\n")
        return
    }
    if op == 19L || op == 20L {
        // a count at or above the width (or negative) fails; for the narrow types the shift happens in 32 bits and a left shift wraps
        int_w(compiler, ir, "  %nf.1."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp ugt "); int_w(compiler, ir, llty); int_w(compiler, ir, " "); ir_write_value_ref(compiler, ir, right)
        int_w(compiler, ir, ", "); int_n(compiler, ir, int_type_bits(ty) - 1L); int_w(compiler, ir, "\n")
        emit_int_failure(files, tables, compiler, ir, node, file_index, 1L, 11L)
        let shift_result: Ascii max 8 = if op == 19L { "shl " } else if signed { "ashr " } else { "lshr " }
        if narrow && op == 19L {
            int_w(compiler, ir, "  %shift.raw."); int_n(compiler, ir, node); int_w(compiler, ir, " = shl i32 "); ir_write_value_ref(compiler, ir, left); int_w(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); int_w(compiler, ir, "\n")
            emit_int_wrap_narrow(compiler, ir, node, ty, "%shift.raw.", "%v")
        } else {
            int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = "); int_w(compiler, ir, shift_result); int_w(compiler, ir, llty); int_w(compiler, ir, " ")
            ir_write_value_ref(compiler, ir, left); int_w(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); int_w(compiler, ir, "\n")
        }
        return
    }
    if op == 3L || op == 4L {
        int_w(compiler, ir, "  %nf.1."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp eq "); int_w(compiler, ir, llty); int_w(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); int_w(compiler, ir, ", 0\n")
        emit_int_failure(files, tables, compiler, ir, node, file_index, 1L, 9L)
        let division: Ascii max 8 = if op == 3L { if signed { "sdiv " } else { "udiv " } } else if signed { "srem " } else { "urem " }
        int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = "); int_w(compiler, ir, division); int_w(compiler, ir, llty); int_w(compiler, ir, " ")
        ir_write_value_ref(compiler, ir, left); int_w(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); int_w(compiler, ir, "\n")
        if op == 3L && (ty == TY_SHORT || ty == TY_SBYTE) {
            // the one overflowing division: the most negative value divided by -1
            int_w(compiler, ir, "  %nf.2."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp sgt i32 %v"); int_n(compiler, ir, node); int_w(compiler, ir, ", "); int_n(compiler, ir, int_type_high(ty)); int_w(compiler, ir, "\n")
            emit_int_failure(files, tables, compiler, ir, node, file_index, 2L, FAILURE_NARROW_RANGE)
        }
        return
    }
    // + - * and their wrapping forms
    let wrapping = op >= 5L
    let base_op = if wrapping { op - 5L } else { op }
    let mnemonic: Ascii max 8 = if base_op == 0L { "add" } else if base_op == 1L { "sub" } else { "mul" }
    if !narrow {
        if wrapping {
            int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = "); int_w(compiler, ir, mnemonic); int_w(compiler, ir, " "); int_w(compiler, ir, llty); int_w(compiler, ir, " ")
            ir_write_value_ref(compiler, ir, left); int_w(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); int_w(compiler, ir, "\n")
        } else {
            int_w(compiler, ir, "  %ov.pair."); int_n(compiler, ir, node); int_w(compiler, ir, " = call { "); int_w(compiler, ir, llty); int_w(compiler, ir, ", i1 } @llvm.u"); int_w(compiler, ir, mnemonic)
            int_w(compiler, ir, ".with.overflow."); int_w(compiler, ir, llty); int_w(compiler, ir, "("); int_w(compiler, ir, llty); int_w(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); int_w(compiler, ir, ", "); int_w(compiler, ir, llty); int_w(compiler, ir, " "); ir_write_value_ref(compiler, ir, right)
            int_w(compiler, ir, ")\n  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = extractvalue { "); int_w(compiler, ir, llty); int_w(compiler, ir, ", i1 } %ov.pair."); int_n(compiler, ir, node)
            int_w(compiler, ir, ", 0\n  %nf.1."); int_n(compiler, ir, node); int_w(compiler, ir, " = extractvalue { "); int_w(compiler, ir, llty); int_w(compiler, ir, ", i1 } %ov.pair."); int_n(compiler, ir, node); int_w(compiler, ir, ", 1\n")
            emit_int_failure(files, tables, compiler, ir, node, file_index, 1L, FAILURE_UNSIGNED_ADD + base_op)
        }
        return
    }
    if wrapping {
        int_w(compiler, ir, "  %wrap.raw."); int_n(compiler, ir, node); int_w(compiler, ir, " = "); int_w(compiler, ir, mnemonic); int_w(compiler, ir, " i32 ")
        ir_write_value_ref(compiler, ir, left); int_w(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); int_w(compiler, ir, "\n")
        emit_int_wrap_narrow(compiler, ir, node, ty, "%wrap.raw.", "%v")
        return
    }
    // narrow, checked: widen both to 64 bits, compute, and fail when the result leaves the range
    let extension: Ascii max 8 = if signed { "sext" } else { "zext" }
    int_w(compiler, ir, "  %nl."); int_n(compiler, ir, node); int_w(compiler, ir, " = "); int_w(compiler, ir, extension); int_w(compiler, ir, " i32 "); ir_write_value_ref(compiler, ir, left); int_w(compiler, ir, " to i64\n")
    int_w(compiler, ir, "  %nr."); int_n(compiler, ir, node); int_w(compiler, ir, " = "); int_w(compiler, ir, extension); int_w(compiler, ir, " i32 "); ir_write_value_ref(compiler, ir, right); int_w(compiler, ir, " to i64\n")
    int_w(compiler, ir, "  %nres."); int_n(compiler, ir, node); int_w(compiler, ir, " = "); int_w(compiler, ir, mnemonic); int_w(compiler, ir, " i64 %nl."); int_n(compiler, ir, node); int_w(compiler, ir, ", %nr."); int_n(compiler, ir, node); int_w(compiler, ir, "\n")
    int_w(compiler, ir, "  %nlow."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp slt i64 %nres."); int_n(compiler, ir, node); int_w(compiler, ir, ", "); int_n(compiler, ir, int_type_low(ty))
    int_w(compiler, ir, "\n  %nhigh."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp sgt i64 %nres."); int_n(compiler, ir, node); int_w(compiler, ir, ", "); int_n(compiler, ir, int_type_high(ty))
    int_w(compiler, ir, "\n  %nf.1."); int_n(compiler, ir, node); int_w(compiler, ir, " = or i1 %nlow."); int_n(compiler, ir, node); int_w(compiler, ir, ", %nhigh."); int_n(compiler, ir, node); int_w(compiler, ir, "\n")
    emit_int_failure(files, tables, compiler, ir, node, file_index, 1L, FAILURE_NARROW_RANGE)
    int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = trunc i64 %nres."); int_n(compiler, ir, node); int_w(compiler, ir, " to i32\n")
}

// x op= y for the new integer types. op is the compound code: 1 += 2 -= 3 *= 4 /= 5 %= 6 <<= 7 >>= 8 &= 9 |= 10 ^=
fn emit_new_int_compound(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    target: long,
    binding: long,
    value: long,
    ty: long,
    op: long,
    place_target: bool,
) {
    let binary_op = if op >= 11L { op - 6L } else if op <= 5L { op - 1L } else if op == 6L { 20L } else if op == 7L { 19L } else if op == 8L { 16L } else if op == 9L { 17L } else { 18L }
    emit_new_int_binary(files, tables, compiler, ir, node, file_index, binary_op, target, value, ty)
    let address_id = if place_target { emit_late_place_address(tables, compiler, ir, target) } else { -1L }
    int_w(compiler, ir, "  store "); int_w(compiler, ir, llvm_type_name(ty)); int_w(compiler, ir, " %v"); int_n(compiler, ir, node)
    if place_target { int_w(compiler, ir, ", ptr %addr."); int_n(compiler, ir, address_id); int_w(compiler, ir, ", align 1") }
    else { int_w(compiler, ir, ", ptr %local."); int_n(compiler, ir, binding); int_w(compiler, ir, ", align 1") }
    emit_program_storage_tbaa(compiler, ir)
    ir_push_byte(compiler, ir, 10)
}

// A cast between two integer types (int, long, byte and the five new ones), at least one of them new. Checked: fails (kind 10)
// when the value does not fit the target, so `(uint)(-1)` fails; low_bits keeps the low bits.
fn emit_new_int_cast(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    operand: long,
    source_ty: long,
    target_ty: long,
    low_bits: bool,
) {
    let source_signed = int_type_signed(source_ty)
    // %cw = the value widened to 64 bits (a ulong stays a bit pattern)
    if int_type_wide64(source_ty) {
        int_w(compiler, ir, "  %cw."); int_n(compiler, ir, node); int_w(compiler, ir, " = add i64 0, "); ir_write_value_ref(compiler, ir, operand); int_w(compiler, ir, "\n")
    } else {
        int_w(compiler, ir, "  %cw."); int_n(compiler, ir, node); int_w(compiler, ir, if source_signed { " = sext i32 " } else { " = zext i32 " }); ir_write_value_ref(compiler, ir, operand); int_w(compiler, ir, " to i64\n")
    }
    if !low_bits && source_ty != target_ty {
        var have_check = true
        if target_ty == TY_ULONG {
            if source_signed { int_w(compiler, ir, "  %nf.1."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp slt i64 %cw."); int_n(compiler, ir, node); int_w(compiler, ir, ", 0\n") } else { have_check = false }
        } else if target_ty == TY_LONG {
            if source_ty == TY_ULONG { int_w(compiler, ir, "  %nf.1."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp slt i64 %cw."); int_n(compiler, ir, node); int_w(compiler, ir, ", 0\n") } else { have_check = false }
        } else if source_ty == TY_ULONG {
            int_w(compiler, ir, "  %nf.1."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp ugt i64 %cw."); int_n(compiler, ir, node); int_w(compiler, ir, ", "); int_n(compiler, ir, int_type_high(target_ty)); int_w(compiler, ir, "\n")
        } else {
            int_w(compiler, ir, "  %clow."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp slt i64 %cw."); int_n(compiler, ir, node); int_w(compiler, ir, ", "); int_n(compiler, ir, int_type_low(target_ty))
            int_w(compiler, ir, "\n  %chigh."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp sgt i64 %cw."); int_n(compiler, ir, node); int_w(compiler, ir, ", "); int_n(compiler, ir, int_type_high(target_ty))
            int_w(compiler, ir, "\n  %nf.1."); int_n(compiler, ir, node); int_w(compiler, ir, " = or i1 %clow."); int_n(compiler, ir, node); int_w(compiler, ir, ", %chigh."); int_n(compiler, ir, node); int_w(compiler, ir, "\n")
        }
        if have_check { emit_int_failure(files, tables, compiler, ir, node, file_index, 1L, 10L) }
    }
    if int_type_wide64(target_ty) {
        int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = add i64 0, %cw."); int_n(compiler, ir, node); int_w(compiler, ir, "\n")
    } else if low_bits && target_ty != TY_INT && target_ty != TY_UINT {
        int_w(compiler, ir, "  %cn."); int_n(compiler, ir, node); int_w(compiler, ir, " = trunc i64 %cw."); int_n(compiler, ir, node); int_w(compiler, ir, " to i32\n")
        if target_ty == TY_BYTE {
            int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = and i32 %cn."); int_n(compiler, ir, node); int_w(compiler, ir, ", 255\n")
        } else { emit_int_wrap_narrow(compiler, ir, node, target_ty, "%cn.", "%v") }
    } else {
        int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = trunc i64 %cw."); int_n(compiler, ir, node); int_w(compiler, ir, " to i32\n")
    }
}

// ~x and -x for the new integer types (unary minus is rejected for the unsigned ones in the checker).
fn emit_new_int_unary(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    operand: long,
    ty: long,
    is_not: bool,
) {
    let llty = llvm_type_name(ty)
    if is_not {
        if ty == TY_USHORT {
            int_w(compiler, ir, "  %not.raw."); int_n(compiler, ir, node); int_w(compiler, ir, " = xor i32 "); ir_write_value_ref(compiler, ir, operand); int_w(compiler, ir, ", -1\n")
            emit_int_wrap_narrow(compiler, ir, node, ty, "%not.raw.", "%v")
        } else {
            int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = xor "); int_w(compiler, ir, llty); int_w(compiler, ir, " "); ir_write_value_ref(compiler, ir, operand); int_w(compiler, ir, ", -1\n")
        }
        return
    }
    int_w(compiler, ir, "  %nf.1."); int_n(compiler, ir, node); int_w(compiler, ir, " = icmp eq i32 "); ir_write_value_ref(compiler, ir, operand); int_w(compiler, ir, ", "); int_n(compiler, ir, int_type_low(ty)); int_w(compiler, ir, "\n")
    emit_int_failure(files, tables, compiler, ir, node, file_index, 1L, FAILURE_NARROW_RANGE)
    int_w(compiler, ir, "  %v"); int_n(compiler, ir, node); int_w(compiler, ir, " = sub i32 0, "); ir_write_value_ref(compiler, ir, operand); int_w(compiler, ir, "\n")
}

// The C runtime function that prints a scalar of this type without a newline, and its adapter.
fn print_raw_name(ty: long) -> Ascii max 32 {
    if ty == TY_LONG { "nl_print_long_raw" } else if ty == TY_UINT { "nl_print_uint_raw" } else if ty == TY_ULONG { "nl_print_ulong_raw" } else { "nl_print_int_raw" }
}

fn print_raw_nlc_name(ty: long) -> Ascii max 32 {
    if ty == TY_LONG { "nlc_print_long_raw" } else if ty == TY_UINT { "nlc_print_uint_raw" } else if ty == TY_ULONG { "nlc_print_ulong_raw" } else { "nlc_print_int_raw" }
}
