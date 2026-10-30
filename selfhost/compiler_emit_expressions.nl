// E3a1 begin: core helpers carry the job context unless they create it or
// are freestanding memory/startup primitives.
fn core_function_has_context(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    function: FunctionRecord,
) -> bool {
    files[function.file].name != b"memory.nl" &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "nl_context_create") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "map") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "protect") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "unmap") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "nl_core_start") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "auxiliary_value") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "count_entries") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "startup_write_all") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "startup_write_z") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "startup_write_digit") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "startup_write_number") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "write_context_startup_failure") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "find_environment_in") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "startup_string_length") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "context_header_bytes") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "core_state_bytes") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "stack_poison_record_bytes") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "stack_poison_record_capacity") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "stack_default_bytes")
}
// E3a1 end

fn ir_write_core_function_symbol(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    function: FunctionRecord,
    function_id: long,
) {
    if !compiler.core_mode {
        ir_write_ascii(compiler, ir, "@nl_fn_")
        ir_write_number(compiler, ir, function_id)
        return
    }
    if !core_external_symbol(source, tokens, files, function.file, function.name_token) {
        ir_write_ascii(compiler, ir, "@nl_core_")
    } else {
        ir_push_byte(compiler, ir, 64)
    }
    ir_write_token_text(source, files, tokens, compiler, ir, function.file, function.name_token)
}

// E3a1 begin: shared compiler integration.
fn emit_runtime_failure(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    kind: long,
) {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].anchor, compiler)
    ir_write_ascii(compiler, ir, "  br i1 %ov.flag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %ov.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %ov.ok."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nov.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if compiler.memory_closure { ir_write_ascii(compiler, ir, "  call void @llvm.trap()\n  unreachable\n") }
    else {
        ir_write_ascii(compiler, ir, "  call void ")
        emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail")
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 "); ir_write_number(compiler, ir, kind); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\n")
    }
    ir_write_ascii(compiler, ir, "ov.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_checked_division(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    left: long,
    right: long,
    ty: long,
    is_remainder: bool,
) {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].anchor, compiler)
    let llvm_ty = llvm_type_name(ty)
    ir_write_ascii(compiler, ir, "  %div.zero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", 0\n  br i1 %div.zero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.zero.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.nonzero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ndiv.zero.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 9, i32 "); ir_write_number(compiler, ir, file_index); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\ndiv.nonzero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    let minimum = if ty == TY_INT { "-2147483648" } else { "-9223372036854775808" }
    let overflow_kind = if ty == TY_INT { 12L } else { 13L }
    ir_write_ascii(compiler, ir, "  %div.min."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, minimum); ir_write_ascii(compiler, ir, "\n  %div.minusone."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", -1\n  %div.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = and i1 %div.min."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %div.minusone."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
    if is_remainder {
        ir_write_ascii(compiler, ir, "  br i1 %div.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %rem.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %rem.compute."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nrem.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  store "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " 0, ptr %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  br label %rem.join."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nrem.compute."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %rem.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = srem "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, "\n  store "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " %rem.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  br label %rem.join."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nrem.join."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, ", ptr %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    } else {
        ir_write_ascii(compiler, ir, "  br i1 %div.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.overflow."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.safe."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ndiv.overflow."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 "); ir_write_number(compiler, ir, overflow_kind); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, file_index); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\ndiv.safe."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sdiv "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, "\n")
    }
}
// E3a1 end

fn emit_checked_shift(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    left: long,
    right: long,
    ty: long,
    is_left: bool,
) {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].anchor, compiler)
    let llvm_ty = llvm_type_name(ty)
    let width = if ty == TY_INT { 32L } else { 64L }
    ir_write_ascii(compiler, ir, "  %shift.negative."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp slt "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", 0\n  %shift.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sge "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, width); ir_write_ascii(compiler, ir, "\n  %shift.bad."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i1 %shift.negative."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %shift.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  br i1 %shift.bad."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %shift.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %shift.good."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nshift.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 11, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\nshift.good."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ");
    if is_left { ir_write_ascii(compiler, ir, "shl ") } else { ir_write_ascii(compiler, ir, "ashr ") }
    ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_push_byte(compiler, ir, 10)
}

fn emit_compound_assignment(
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
) {
    if op == 1L && type_kind(compiler, ty) == TYPE_KIND_ASCII {
        emit_ascii_append_assignment(tables, compiler, ir, node, target, binding, value)
        return
    }
    let field_target = tables.nodes[target].kind == NodeKind.Field
    let place_target = field_target || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, binding) || binding_is_view(compiler, binding)
    if !place_target { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
    if ty == TY_DOUBLE {
        emit_double_compound(files, tables, compiler, ir, node, file_index, target, binding, value, place_target, op)
        return
    }
    if op == 1L || op == 2L || op == 3L {
        let binary_op = op - 1L
        ir_write_ascii(compiler, ir, "  %ov.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } @llvm.s")
        if binary_op == 0L { ir_write_ascii(compiler, ir, "add") } else if binary_op == 1L { ir_write_ascii(compiler, ir, "sub") } else { ir_write_ascii(compiler, ir, "mul") }
        ir_write_ascii(compiler, ir, ".with.overflow."); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ")\n")
        ir_write_ascii(compiler, ir, "  %asgn.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n  %ov.flag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n")
        let failure_kind = if ty == TY_INT { binary_op + 1L } else { binary_op + 5L }
        emit_runtime_failure(files, tables, compiler, ir, node, file_index, failure_kind)
        let address_id = if place_target { emit_late_place_address(tables, compiler, ir, target) } else { -1L }
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %asgn.value."); ir_write_number(compiler, ir, node)
        if place_target { ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", align 1") }
        else { ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1") }
        emit_program_storage_tbaa(compiler, ir)
        ir_push_byte(compiler, ir, 10)
    } else {
        if op == 4L || op == 5L { emit_checked_division(files, tables, compiler, ir, node, file_index, target, value, ty, op == 5L) }
        else if op == 6L || op == 7L { emit_checked_shift(files, tables, compiler, ir, node, file_index, target, value, ty, op == 7L) }
        else {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ")
            if op == 8L { ir_write_ascii(compiler, ir, "and ") }
            else if op == 9L { ir_write_ascii(compiler, ir, "or ") }
            else { ir_write_ascii(compiler, ir, "xor ") }
            ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, value); ir_push_byte(compiler, ir, 10)
        }
        let address_id = if place_target { emit_late_place_address(tables, compiler, ir, target) } else { -1L }
        if place_target {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", align 1")
        } else {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1")
        }
        emit_program_storage_tbaa(compiler, ir)
        ir_push_byte(compiler, ir, 10)
    }
}

fn core_syscall_number(operation: long) -> long {
    if operation == SYS_WRITE { 1L }
    else if operation == SYS_EXIT_GROUP { 231L }
    else if operation == SYS_MAP { 9L }
    else if operation == SYS_PROTECT { 10L }
    else if operation == SYS_IOCTL { 16L }
    else if operation == SYS_STATX { 332L }
    else if operation == SYS_SIGACTION { 13L }
    else if operation == SYS_OPENAT { 257L }
    else if operation == SYS_CLOSE { 3L }
    // E3a1 begin
    else if operation == SYS_REMAP { 25L }
    else if operation == SYS_UNMAP { 11L }
    else if operation == SYS_CLOCK_GETTIME { 228L }
    // E3a1 end
    else { -1L }
}

// E3a1 begin: these helpers read the one core declaration and never mirror
// byte offsets in compiler source.
fn context_struct_index(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
) -> long {
    for type_index in 0L..struct_type_count(compiler) {
        let record = struct_record(compiler, type_index)
        if token_is_word_at(source, tokens, files, record.file, record.name_token, "DataStackContext") {
            return type_index
        }
    }
    -1L
}

fn context_core_state_field_index(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
) -> long {
    let context_index = context_struct_index(source, tokens, files, compiler)
    if context_index < 0L { return -1L }
    let record = struct_record(compiler, context_index)
    for field_offset in 0L..record.field_count {
        let field_index = record.field_start + field_offset
        if token_is_word_at(source, tokens, files, record.file, compiler.struct_fields[field_index].name_token, "core_state") {
            return field_offset
        }
    }
    -1L
}

fn context_base_field_index(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
) -> long {
    let context_index = context_struct_index(source, tokens, files, compiler)
    if context_index < 0L { return -1L }
    let record = struct_record(compiler, context_index)
    for field_offset in 0L..record.field_count {
        let field_index = record.field_start + field_offset
        if token_is_word_at(source, tokens, files, record.file, compiler.struct_fields[field_index].name_token, "base") {
            return field_offset
        }
    }
    -1L
}

fn context_field_offset(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    field_index: long,
) -> long {
    let context_index = context_struct_index(source, tokens, files, compiler)
    if context_index < 0L { return -1L }
    let record = struct_record(compiler, context_index)
    if field_index < 0L || field_index >= record.field_count { return -1L }
    compiler.struct_fields[record.field_start + field_index].offset
}

fn is_stack_address_node(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    file_index: long,
) -> bool {
    tables.nodes[node].kind == NodeKind.MethodCall &&
        is_core_sys_receiver(source, tokens, files, tables, compiler, node, file_index) &&
        core_sys_operation(source, tokens, files, file_index, tables.nodes[node].token) == SYS_STACK_ADDR
}

fn is_context_base_load(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    file_index: long,
) -> bool {
    if !compiler.core_mode { return false }
    for function_id in 0L..compiler.functions.count() {
        let function = compiler.functions[function_id]
        if function.file != file_index || !token_is_word_at(source, tokens, files, function.file, function.name_token, "nl_context_current_base") { continue }
        let body = function.body
        let first = body - tables.nodes[body].subtree + 1L
        if node >= first && node <= body { return true }
    }
    false
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_sys_method(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let syntax = tables.nodes[node]
    let operation = core_sys_operation(source, tokens, files, file_index, syntax.token)
    let collection_operation = compiler.facts[node].literal
    if (compiler.facts[node].flags & FACT_DOUBLE_METHOD) != 0L {
        emit_double_method(tables, compiler, ir, node, collection_operation)
        return
    }
    if collection_operation >= COLLECTION_METHOD_LEN && collection_operation <= COLLECTION_METHOD_MAP_CONTAINS {
        emit_collection_method(source, files, tables, compiler, ir, node, file_index, collection_operation)
        return
    }
    let receiver = compiler.child_first[node]
    var first_arg = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
    if operation == SYS_NULL {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = inttoptr i64 0 to ptr\n")
        return
    }
    // E3a1 subsection
    if operation == SYS_IS_TEST_BUILD {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i1 0, ")
        ir_write_ascii(compiler, ir, if compiler_test_build(compiler) { "true\n" } else { "false\n" })
        return
    }
    if operation == SYS_CONTEXT {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.ctx, i64 0\n")
        return
    }
    if operation == SYS_CONTEXT_OFFSET {
        let field_arg = first_arg
        let context_index = context_struct_index(source, tokens, files, compiler)
        if context_index < 0L { compiler.ir_overflow = true; return }
        let context_record = struct_record(compiler, context_index)
        if tables.nodes[field_arg].kind == NodeKind.Integer {
            let field_index = compiler.facts[field_arg].literal
            let byte_offset = context_field_offset(source, tokens, files, compiler, field_index)
            if byte_offset < 0L { compiler.ir_overflow = true; return }
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_number(compiler, ir, byte_offset); ir_write_ascii(compiler, ir, "\n")
        } else {
            for field_index in 0L..context_record.field_count {
                let byte_offset = context_field_offset(source, tokens, files, compiler, field_index)
                ir_write_ascii(compiler, ir, "  %sys.context.offset.match."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = icmp eq i64 "); ir_write_value_ref(compiler, ir, field_arg); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\n  %sys.context.offset.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = select i1 %sys.context.offset.match."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, byte_offset); ir_write_ascii(compiler, ir, ", i64 ")
                if field_index == 0L { ir_write_ascii(compiler, ir, "-1\n") }
                else { ir_write_ascii(compiler, ir, "%sys.context.offset.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, field_index - 1L); ir_write_ascii(compiler, ir, "\n") }
            }
            let last = context_record.field_count - 1L
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 true, i64 %sys.context.offset.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, last); ir_write_ascii(compiler, ir, ", i64 %sys.context.offset.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, last); ir_write_ascii(compiler, ir, "\n")
        }
        return
    }
    if operation == SYS_CONTEXT_SIZE {
        let context_index = context_struct_index(source, tokens, files, compiler)
        if context_index < 0L { compiler.ir_overflow = true; return }
        let context_type = struct_type_id(compiler, context_index)
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_number(compiler, ir, value_type_size(compiler, context_type)); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_STACK_ADDR {
        let context_arg = first_arg
        let offset_arg = compiler.child_next[context_arg]
        let base_field = context_base_field_index(source, tokens, files, compiler)
        let base_offset = context_field_offset(source, tokens, files, compiler, base_field)
        if base_offset < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %sys.stack.addr.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, context_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n")
        ir_write_ascii(compiler, ir, "  %sys.stack.addr.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load ptr, ptr %sys.stack.addr.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n")
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %sys.stack.addr.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_STACK_LOAD8 || operation == SYS_STACK_STORE8 {
        let context_arg = first_arg
        let offset_arg = compiler.child_next[context_arg]
        let base_field = context_base_field_index(source, tokens, files, compiler)
        let base_offset = context_field_offset(source, tokens, files, compiler, base_field)
        if base_offset < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %sys.stack.base.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, context_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %sys.stack.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load ptr, ptr %sys.stack.base.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n  %sys.stack.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %sys.stack.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n")
        if operation == SYS_STACK_LOAD8 {
            ir_write_ascii(compiler, ir, "  %sys.stack.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i8, ptr %sys.stack.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i8 %sys.stack.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i32\n")
        } else {
            let value_arg = compiler.child_next[offset_arg]
            ir_write_ascii(compiler, ir, "  %sys.stack.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i32 "); ir_write_value_ref(compiler, ir, value_arg); ir_write_ascii(compiler, ir, " to i8\n  store i8 %sys.stack.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %sys.stack.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        return
    }
    // E3a1 subsection end
    if operation == SYS_STATE {
        let field_index = context_core_state_field_index(source, tokens, files, compiler)
        let byte_offset = context_field_offset(source, tokens, files, compiler, field_index)
        if byte_offset < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %sys.state.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.ctx, i64 "); ir_write_number(compiler, ir, byte_offset); ir_write_ascii(compiler, ir, "\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load ptr, ptr %sys.state.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n")
        return
    }
    if operation == SYS_LIT {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", i64 0\n")
        return
    }
    if operation == SYS_IS_NULL {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", null\n")
        return
    }
    if operation == SYS_OFFSET {
        let offset_arg = compiler.child_next[first_arg]
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_DISTANCE {
        let to_arg = compiler.child_next[first_arg]
        ir_write_ascii(compiler, ir, "  %sys.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ptrtoint ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, " to i64\n  %sys.addr2."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ptrtoint ptr "); ir_write_value_ref(compiler, ir, to_arg); ir_write_ascii(compiler, ir, " to i64\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sub i64 %sys.addr2."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %sys.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_FROM_RAW {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = inttoptr i64 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, " to ptr\n")
        return
    }
    if operation == SYS_LOAD8 || operation == SYS_LOAD32 || operation == SYS_LOAD64 || operation == SYS_LOAD_ADDR {
        let offset_arg = compiler.child_next[first_arg]
        ir_write_ascii(compiler, ir, "  %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n")
        let value_type = if operation == SYS_LOAD8 { "i8" } else if operation == SYS_LOAD32 { "i32" } else if operation == SYS_LOAD64 { "i64" } else { "ptr" }
        ir_write_ascii(compiler, ir, "  %sys.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, value_type); ir_write_ascii(compiler, ir, ", ptr %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1")
        if operation == SYS_LOAD_ADDR && is_context_base_load(source, files, tokens, tables, compiler, node, file_index) {
            ir_write_ascii(compiler, ir, ", !tbaa !9002")
        }
        ir_push_byte(compiler, ir, 10)
        if operation == SYS_LOAD8 {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i8 %sys.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i32\n")
        } else {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 true, "); ir_write_ascii(compiler, ir, value_type); ir_write_ascii(compiler, ir, " %sys.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, value_type); ir_write_ascii(compiler, ir, " %sys.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        }
        return
    }
    if operation == SYS_STORE8 || operation == SYS_STORE32 || operation == SYS_STORE64 || operation == SYS_STORE_ADDR {
        let offset_arg = compiler.child_next[first_arg]
        let value_arg = compiler.child_next[offset_arg]
        let value_type = if operation == SYS_STORE8 { "i8" } else if operation == SYS_STORE32 { "i32" } else if operation == SYS_STORE64 { "i64" } else { "ptr" }
        ir_write_ascii(compiler, ir, "  %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n")
        if operation == SYS_STORE8 {
            ir_write_ascii(compiler, ir, "  %sys.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i32 "); ir_write_value_ref(compiler, ir, value_arg); ir_write_ascii(compiler, ir, " to i8\n  store i8 %sys.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
        } else {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, value_type); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_arg); ir_write_ascii(compiler, ir, ", ptr %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        return
    }
    if operation == SYS_IS_ERROR {
        ir_write_ascii(compiler, ir, "  %sys.err.lo."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sge i64 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", -4095\n  %sys.err.hi."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sle i64 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", -1\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = and i1 %sys.err.lo."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %sys.err.hi."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_REPEAT_BYTE {
        ir_write_ascii(compiler, ir, "  %sys.repeat.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i32 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, " to i8\n  %sys.repeat.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i8 %sys.repeat.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i64\n  %sys.repeat.shift8."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = shl i64 %sys.repeat.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 8\n  %sys.repeat.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i64 %sys.repeat.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %sys.repeat.shift8."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %sys.repeat.shift16."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = shl i64 %sys.repeat.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 16\n  %sys.repeat.word."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i64 %sys.repeat.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %sys.repeat.shift16."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %sys.repeat.shift32."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = shl i64 %sys.repeat.word."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 32\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i64 %sys.repeat.word."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %sys.repeat.shift32."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_COPY_16 {
        let src_arg = compiler.child_next[first_arg]
        ir_write_ascii(compiler, ir, "  %sys.copy16.src."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load <16 x i8>, ptr "); ir_write_value_ref(compiler, ir, src_arg); ir_write_ascii(compiler, ir, ", align 1\n  store <16 x i8> %sys.copy16.src."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", align 1\n")
        return
    }
    if operation == SYS_FILL_16 {
        let value_arg = compiler.child_next[first_arg]
        ir_write_ascii(compiler, ir, "  %sys.fill16.half."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = bitcast i64 "); ir_write_value_ref(compiler, ir, value_arg); ir_write_ascii(compiler, ir, " to <8 x i8>\n  %sys.fill16.vector."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = shufflevector <8 x i8> %sys.fill16.half."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", <8 x i8> %sys.fill16.half."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", <16 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>\n  store <16 x i8> %sys.fill16.vector."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", align 1\n")
        return
    }
    if operation == SYS_COPY_FORWARD_BULK {
        let src_arg = compiler.child_next[first_arg]
        let n_arg = compiler.child_next[src_arg]
        ir_write_ascii(compiler, ir, "  %sys.bulk.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call { ptr, ptr, i64 } asm sideeffect \"rep movsb\", \"={di},={si},={cx},0,1,2,~{memory},~{dirflag}\"(ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, src_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, n_arg); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    if operation == SYS_FILL_BULK {
        let value_arg = compiler.child_next[first_arg]
        let n_arg = compiler.child_next[value_arg]
        ir_write_ascii(compiler, ir, "  %sys.fill."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i32 "); ir_write_value_ref(compiler, ir, value_arg); ir_write_ascii(compiler, ir, " to i8\n  %sys.bulk.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call { ptr, i64 } asm sideeffect \"rep stosb\", \"={di},={cx},0,{ax},1,~{memory},~{dirflag}\"(ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", i8 %sys.fill."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, n_arg); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    if operation == SYS_CALL_MAIN {
        let argv_arg = compiler.child_next[first_arg]
        let envp_arg = compiler.child_next[argv_arg]
        let auxv_arg = compiler.child_next[envp_arg]
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i32 @main(i32 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, argv_arg); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, envp_arg); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, auxv_arg); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    let argument_count = core_sys_argument_count(operation)
    let syscall = core_syscall_number(operation)
    for argument_index in 0L..argument_count {
        let argument = child_at(tables, compiler, node, argument_index + 1L)
        let ty = core_sys_argument_type(operation, argument_index)
        if !is_stack_address_node(source, tokens, files, tables, compiler, argument, file_index) {
            ir_write_ascii(compiler, ir, "  %sys.arg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = ")
            if ty == TY_ADDR { ir_write_ascii(compiler, ir, "ptrtoint ptr "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n") }
            else if ty == TY_INT { ir_write_ascii(compiler, ir, "sext i32 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n") }
            else if ty == TY_BOOL { ir_write_ascii(compiler, ir, "zext i1 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n") }
            else { ir_write_ascii(compiler, ir, "add i64 0, "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, "\n") }
        }
    }
    // Derive stack addresses only after all argument expressions have run.
    // There is no call between these reloads and the raw syscall below.
    for argument_index in 0L..argument_count {
        let argument = child_at(tables, compiler, node, argument_index + 1L)
        if !is_stack_address_node(source, tokens, files, tables, compiler, argument, file_index) { continue }
        let address_receiver = compiler.child_first[argument]
        let context_arg = compiler.child_next[address_receiver]
        let offset_arg = compiler.child_next[context_arg]
        let base_field = context_base_field_index(source, tokens, files, compiler)
        let base_offset = context_field_offset(source, tokens, files, compiler, base_field)
        if base_offset < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %sys.stack.addr.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, context_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %sys.stack.addr.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = load ptr, ptr %sys.stack.addr.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, ", align 8\n  %sys.stack.addr.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %sys.stack.addr.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n  %sys.arg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = ptrtoint ptr %sys.stack.addr.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " to i64\n")
    }
    if operation == SYS_EXIT_GROUP { ir_write_ascii(compiler, ir, "  ") }
    else { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ") }
    ir_write_ascii(compiler, ir, "call i64 @nl.sys.call"); ir_write_number(compiler, ir, argument_count); ir_write_ascii(compiler, ir, "(i64 "); ir_write_number(compiler, ir, syscall)
    for argument_index in 0L..argument_count {
        ir_write_ascii(compiler, ir, ", i64 %sys.arg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index)
    }
    ir_write_ascii(compiler, ir, ")\n")
    if operation == SYS_EXIT_GROUP { ir_write_ascii(compiler, ir, "  unreachable\n") }
}
// E3a1 end

fn enum_temporary_address(node: long, part: long) -> long {
    // The stride exceeds the largest part (MAX_TREE_NODES * 80 + 6), so two nodes never share an id.
    1000000000000L + node * (MAX_TREE_NODES * 100L) + part
}

fn emit_enum_tag_store(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    tag: long,
) {
    let address = enum_temporary_address(node, 0L)
    emit_layout_address(compiler, ir, address, aggregate_destination_location(compiler, 0L, node))
    ir_write_ascii(compiler, ir, "  %enum.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i32 0, "); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, "\n  store i32 %enum.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n")
}

fn emit_sum_tag_store(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    tag: long,
) {
    let address = enum_temporary_address(node, MAX_TREE_NODES * 2L + tag)
    emit_layout_address(compiler, ir, address, aggregate_destination_location(compiler, 0L, node))
    ir_write_ascii(compiler, ir, "  %sum.tag."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, " = add i32 0, "); ir_write_number(compiler, ir, tag)
    ir_write_ascii(compiler, ir, "\n  store i32 %sum.tag."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n")
}

fn emit_enum_constructor_payload(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    constructor: long,
    case_index: long,
    payload_index: long,
    value_node: long,
) {
    let case = compiler.enum_cases[case_index]
    let payload = compiler.enum_payloads[case.payload_start + payload_index]
    if payload.ty == TY_UNIT { return }
    let address = enum_temporary_address(constructor, payload_index + 1L)
    emit_layout_address(compiler, ir, address, storage_location_with_offset(aggregate_destination_location(compiler, 0L, constructor), payload.offset))
    if is_aggregate_type(compiler, payload.ty) {
        let source_kind = aggregate_source_kind(tables, compiler, value_node)
        let source_node = aggregate_source_id(tables, compiler, value_node)
        emit_aggregate_copy(compiler, ir, payload.ty, compiler_location(compiler, 2L, address, 0L), aggregate_source_location(compiler, source_kind, source_node))
    } else {
        emit_store_scalar(compiler, ir, address, payload.ty, value_node)
    }
}

fn emit_sum_constructor_payload(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    constructor: long,
    payload_index: long,
    value_node: long,
) {
    let type_id = compiler.facts[constructor].ty
    let tag = compiler.facts[constructor].literal
    let payload = sum_payload_record(compiler, type_id, tag, payload_index)
    if payload.ty == TY_UNIT { return }
    let address = enum_temporary_address(constructor, MAX_TREE_NODES + payload_index + 1L)
    emit_layout_address(compiler, ir, address, storage_location_with_offset(aggregate_destination_location(compiler, 0L, constructor), payload.offset))
    if is_aggregate_type(compiler, payload.ty) {
        let source_kind = aggregate_source_kind(tables, compiler, value_node)
        let source_node = aggregate_source_id(tables, compiler, value_node)
        emit_aggregate_copy(compiler, ir, payload.ty, compiler_location(compiler, 2L, address, 0L), aggregate_source_location(compiler, source_kind, source_node))
    } else {
        emit_store_scalar(compiler, ir, address, payload.ty, value_node)
    }
}

fn emit_match_payload_bindings(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    match_node: long,
    arm: long,
) {
    let scrutinee = compiler.child_first[match_node]
    let pattern = compiler.child_first[arm]
    if tables.nodes[pattern].kind != NodeKind.CasePattern { return }
    let source_kind = aggregate_source_kind(tables, compiler, scrutinee)
    let source_node = aggregate_source_id(tables, compiler, scrutinee)
    let matched_ty = compiler.facts[scrutinee].ty
    let generic_sum = type_kind(compiler, matched_ty) == TYPE_KIND_OPTION || type_kind(compiler, matched_ty) == TYPE_KIND_RESULT
    let case_index = compiler.facts[pattern].binding
    if !generic_sum && case_index < 0L { return }
    let case = if generic_sum { EnumCaseRecord { owner: -1L, name_id: -1L, name_token: -1L, node: -1L, payload_start: -1L, payload_count: sum_case_payload_count(compiler, matched_ty, compiler.facts[pattern].literal), tag: compiler.facts[pattern].literal } } else { compiler.enum_cases[case_index] }
    var binding_node = compiler.child_first[pattern]
    for payload_index in 0L..case.payload_count {
        if binding_node < 0L { break }
        let payload = if generic_sum { sum_payload_record(compiler, matched_ty, compiler.facts[pattern].literal, payload_index) }
            else { compiler.enum_payloads[case.payload_start + payload_index] }
        if tables.nodes[binding_node].kind == NodeKind.PatternBinding {
            let binding = compiler.facts[binding_node].binding
            let source_address = aggregate_source_location(compiler, source_kind, source_node)
            emit_layout_address(compiler, ir, binding_node, storage_location_with_offset(source_address, payload.offset))
            if payload.ty != TY_UNIT {
                if is_aggregate_type(compiler, payload.ty) {
                    emit_aggregate_copy(compiler, ir, payload.ty, aggregate_destination_location(compiler, 1L, binding), aggregate_source_location(compiler, 3L, binding_node))
                } else if payload.ty == TY_BOOL {
                    ir_write_ascii(compiler, ir, "  %match.bool."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, ", align 1\n  store i8 %match.bool."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                } else {
                    ir_write_ascii(compiler, ir, "  %match.payload."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty)); ir_write_ascii(compiler, ir, " %match.payload."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                }
            }
        }
        binding_node = compiler.child_next[binding_node]
    }
}

fn emit_sum_payload_transfer(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    payload_ty: long,
    source: StorageLocation,
    source_offset: long,
    destination: StorageLocation,
    destination_offset: long,
    address_seed: long,
) {
    if payload_ty == TY_UNIT { return }
    let source_address = address_seed * 2L
    let destination_address = source_address + 1L
    let source_location = StorageLocation { origin: source.origin, anchor_kind: source.anchor_kind, anchor_node: source.anchor_node, byte_offset: source.byte_offset + source_offset, copies: source.copies, index: source.index, index_node: source.index_node, index_stride: source.index_stride }
    let destination_location = StorageLocation { origin: destination.origin, anchor_kind: destination.anchor_kind, anchor_node: destination.anchor_node, byte_offset: destination.byte_offset + destination_offset, copies: destination.copies, index: destination.index, index_node: destination.index_node, index_stride: destination.index_stride }
    emit_layout_address(compiler, ir, source_address, source_location)
    emit_layout_address(compiler, ir, destination_address, destination_location)
    if is_aggregate_type(compiler, payload_ty) {
        emit_aggregate_copy(compiler, ir, payload_ty, compiler_location(compiler, 2L, destination_address, 0L), compiler_location(compiler, 2L, source_address, 0L))
    } else {
        let storage_type: Ascii max 8 = if payload_ty == TY_BOOL { "i8" } else { llvm_type_name(payload_ty) }
        ir_write_ascii(compiler, ir, "  %sum.transfer.value."); ir_write_number(compiler, ir, address_seed)
        ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type)
        ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address)
        ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage_type)
        ir_write_ascii(compiler, ir, " %sum.transfer.value."); ir_write_number(compiler, ir, address_seed)
        ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, destination_address)
        ir_write_ascii(compiler, ir, ", align 1\n")
    }
}

fn emit_sum_payload_to_expression(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    payload_ty: long,
    source: StorageLocation,
    source_offset: long,
    address_seed: long,
) {
    if payload_ty == TY_UNIT { return }
    if is_aggregate_type(compiler, payload_ty) {
        emit_sum_payload_transfer(compiler, ir, payload_ty, source, source_offset, aggregate_destination_location(compiler, 0L, node), 0L, address_seed)
    } else {
        let source_address = address_seed * 2L
        let source_location = StorageLocation { origin: source.origin, anchor_kind: source.anchor_kind, anchor_node: source.anchor_node, byte_offset: source.byte_offset + source_offset, copies: source.copies, index: source.index, index_node: source.index_node, index_stride: source.index_stride }
        emit_layout_address(compiler, ir, source_address, source_location)
        if payload_ty == TY_BOOL {
            ir_write_ascii(compiler, ir, "  %sum.value.byte."); ir_write_number(compiler, ir, address_seed)
            ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, source_address)
            ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = trunc i8 %sum.value.byte."); ir_write_number(compiler, ir, address_seed); ir_write_ascii(compiler, ir, " to i1\n")
        } else {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(payload_ty))
            ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address)
            ir_write_ascii(compiler, ir, ", align 1\n")
        }
    }
}

fn emit_sum_payload_to_coalesce(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    payload_ty: long,
    source: StorageLocation,
    source_offset: long,
    address_seed: long,
) {
    if payload_ty == TY_UNIT { return }
    if is_aggregate_type(compiler, payload_ty) {
        emit_sum_payload_transfer(compiler, ir, payload_ty, source, source_offset, aggregate_destination_location(compiler, 0L, node), 0L, address_seed)
    } else {
        let source_address = address_seed * 2L
        let source_location = StorageLocation { origin: source.origin, anchor_kind: source.anchor_kind, anchor_node: source.anchor_node, byte_offset: source.byte_offset + source_offset, copies: source.copies, index: source.index, index_node: source.index_node, index_stride: source.index_stride }
        emit_layout_address(compiler, ir, source_address, source_location)
        if payload_ty == TY_BOOL {
            ir_write_ascii(compiler, ir, "  %coalesce.some.byte."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, source_address)
            ir_write_ascii(compiler, ir, ", align 1\n  %coalesce.some.value."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = trunc i8 %coalesce.some.byte."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " to i1\n  store i1 %coalesce.some.value."); ir_write_number(compiler, ir, node)
        } else {
            ir_write_ascii(compiler, ir, "  %coalesce.some.value."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(payload_ty))
            ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address)
            ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, llvm_type_name(payload_ty)); ir_push_byte(compiler, ir, 32)
            ir_write_ascii(compiler, ir, "%coalesce.some.value."); ir_write_number(compiler, ir, node)
        }
        ir_write_ascii(compiler, ir, ", ptr %coalesce.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    }
}

fn emit_option_result_method(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let receiver = compiler.child_first[node]
    let receiver_ty = compiler.facts[receiver].ty
    let receiver_kind = type_kind(compiler, receiver_ty)
    let receiver_source = aggregate_source_location_for_node(tables, compiler, receiver)
    let tag_address = enum_temporary_address(node, MAX_TREE_NODES + 5L)
    emit_layout_address(compiler, ir, tag_address, receiver_source)
    ir_write_ascii(compiler, ir, "  %method.tag."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address); ir_write_ascii(compiler, ir, ", align 1\n")
    let is_some = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "is_some")
    let is_none = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "is_none")
    let is_ok = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "is_ok")
    let is_err = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "is_err")
    let is_ok_method = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "ok")
    let is_unwrap = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "unwrap")
    if is_some || is_ok {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i32 %method.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
    } else if is_none || is_err {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i32 %method.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n")
    } else if is_unwrap {
        let failure_kind = if receiver_kind == TYPE_KIND_OPTION { 14L } else { 15L }
        let failure_position = position_for_offset(file_index, files[file_index].base + tables.nodes[receiver].start, compiler)
        ir_write_ascii(compiler, ir, "  %unwrap.is.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i32 %method.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  br i1 %unwrap.is.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %unwrap.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %unwrap.success."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nunwrap.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 "); ir_write_number(compiler, ir, failure_kind); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, failure_position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, failure_position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\nunwrap.success."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        let payload = sum_payload_record(compiler, receiver_ty, 0L, 0L)
        emit_sum_payload_to_expression(compiler, ir, node, payload.ty, receiver_source, payload.offset, enum_temporary_address(node, MAX_TREE_NODES + 6L))
    } else if is_ok_method {
        let result_ty = compiler.facts[node].ty
        ir_write_ascii(compiler, ir, "  %method.is.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i32 %method.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n  br i1 %method.is.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %method.ok.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %method.ok.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmethod.ok.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_sum_tag_store(compiler, ir, node, 0L)
        let source_payload = sum_payload_record(compiler, receiver_ty, 0L, 0L)
        let destination_payload = sum_payload_record(compiler, result_ty, 0L, 0L)
        emit_sum_payload_transfer(compiler, ir, source_payload.ty, receiver_source, source_payload.offset, aggregate_destination_location(compiler, 0L, node), destination_payload.offset, enum_temporary_address(node, MAX_TREE_NODES + 7L))
        ir_write_ascii(compiler, ir, "  br label %method.ok.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmethod.ok.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_sum_tag_store(compiler, ir, node, 1L)
        ir_write_ascii(compiler, ir, "  br label %method.ok.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmethod.ok.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    } else { compiler.ir_overflow = true }
}

fn match_wildcard_ordinal(tables: ParseTables, compiler: CompilerTables, first_arm: long, first_ordinal: long, match_node: long) -> long {
    var scan = first_arm
    var ordinal = first_ordinal
    for step in 0L..tables.nodes[match_node].subtree {
        if scan < 0L { break }
        let pattern = compiler.child_first[scan]
        if pattern >= 0L && tables.nodes[pattern].kind == NodeKind.WildcardPattern { return ordinal }
        scan = compiler.child_next[scan]
        ordinal += 1L
    }
    -1L
}

fn optional_payload_location(base: StorageLocation, payload_offset: long) -> StorageLocation {
    storage_location_with_offset(base, payload_offset)
}

fn emit_optional_call_invoke(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let receiver = compiler.child_first[node]
    let target_id = compiler.facts[node].function
    if receiver < 0L || target_id < 0L { compiler.ir_overflow = true; return }
    let target = compiler.functions[target_id]
    let receiver_type = compiler.facts[receiver].ty
    let receiver_payload = sum_payload_record(compiler, receiver_type, 0L, 0L)
    let receiver_source_kind = aggregate_source_kind(tables, compiler, receiver)
    let receiver_source_node = aggregate_source_id(tables, compiler, receiver)
    let receiver_source = aggregate_source_location(compiler, receiver_source_kind, receiver_source_node)
    let receiver_parameter = compiler.parameters[target.param_start]
    let receiver_value = if is_aggregate_type(compiler, receiver_parameter.ty) {
        native_location(10L, node, 0L)
    } else {
        optional_payload_location(receiver_source, receiver_payload.offset)
    }
    let result_type = target.result_ty
    let wraps_result = type_kind(compiler, result_type) != TYPE_KIND_OPTION
    let aggregate_result = is_aggregate_type(compiler, result_type)
    var destination = aggregate_destination_location(compiler, 0L, node)
    if wraps_result {
        let output_payload = sum_payload_record(compiler, compiler.facts[node].ty, 0L, 0L)
        destination = optional_payload_location(destination, output_payload.offset)
    }
    emit_current_top_load(compiler, ir, node)
    let receiver_descriptor = MAX_TREE_NODES * 5L + node
    if aggregate_result { emit_prepare_location_descriptor(compiler, ir, destination, true, node) }
    if receiver_parameter.ty != TY_UNIT && is_aggregate_type(compiler, receiver_parameter.ty) {
        if parameter_uses_text_read_view(compiler, receiver_parameter) {
            prepare_text_parameter_descriptor(compiler, ir, receiver_payload.ty, receiver_value, node)
        } else {
            emit_prepare_location_descriptor(compiler, ir, receiver_value, true, receiver_descriptor)
        }
    } else { () }
    var argument = compiler.child_next[receiver]
    for argument_index in 1L..target.param_count {
        let parameter = compiler.parameters[target.param_start + argument_index]
        if argument < 0L { compiler.ir_overflow = true; return }
        if parameter.ty != TY_UNIT && is_aggregate_type(compiler, parameter.ty) {
            let use_snapshot = direct_call_argument_needs_snapshot(tables, compiler, node, argument)
            let argument_location = if use_snapshot { aggregate_destination_location(compiler, 0L, argument) }
                else { aggregate_source_location_for_node(tables, compiler, argument) }
            if parameter_uses_text_read_view(compiler, parameter) {
                let argument_type = compiler.facts[argument].ty
                prepare_text_parameter_descriptor(compiler, ir, argument_type, argument_location, argument)
            } else {
                emit_prepare_location_descriptor(compiler, ir, argument_location, descriptor_geometry(compiler, parameter.ty), argument)
            }
        }
        argument = compiler.child_next[argument]
    }
    ir_write_ascii(compiler, ir, "  ")
    if !aggregate_result && result_type != TY_UNIT && result_type != TY_NEVER {
        ir_write_ascii(compiler, ir, "%optional.call.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ")
    }
    ir_write_ascii(compiler, ir, "call ")
    if aggregate_result || result_type == TY_UNIT || result_type == TY_NEVER { ir_write_ascii(compiler, ir, "void") }
    else { ir_write_ascii(compiler, ir, llvm_type_name(result_type)) }
    ir_write_ascii(compiler, ir, " @nl_fn_"); ir_write_number(compiler, ir, target_id); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 "); emit_current_top_reference(compiler, ir, node)
    if aggregate_result {
        ir_write_ascii(compiler, ir, ", ")
        emit_hidden_destination_argument(compiler, ir, destination)
    }
    if receiver_parameter.ty != TY_UNIT {
        ir_write_ascii(compiler, ir, ", ")
        if is_aggregate_type(compiler, receiver_parameter.ty) {
            if parameter_uses_text_read_view(compiler, receiver_parameter) {
                emit_text_parameter_descriptor(compiler, ir, receiver_payload.ty, receiver_value, node)
            } else {
                emit_location_descriptor_argument(compiler, ir, receiver_value, true, receiver_descriptor)
            }
        } else {
            ir_write_ascii(compiler, ir, llvm_type_name(receiver_parameter.ty)); ir_write_ascii(compiler, ir, " %optional.call.receiver."); ir_write_number(compiler, ir, node)
        }
    }
    argument = compiler.child_next[receiver]
    for argument_index in 1L..target.param_count {
        let parameter = compiler.parameters[target.param_start + argument_index]
        if argument < 0L { compiler.ir_overflow = true; return }
        if parameter.ty != TY_UNIT {
            ir_write_ascii(compiler, ir, ", ")
            if is_aggregate_type(compiler, parameter.ty) {
                let use_snapshot = direct_call_argument_needs_snapshot(tables, compiler, node, argument)
                let argument_location = if use_snapshot { aggregate_destination_location(compiler, 0L, argument) }
                    else { aggregate_source_location_for_node(tables, compiler, argument) }
                if parameter_uses_text_read_view(compiler, parameter) {
                    let argument_type = compiler.facts[argument].ty
                    emit_text_parameter_descriptor(compiler, ir, argument_type, argument_location, argument)
                } else {
                    emit_location_descriptor_argument(compiler, ir, argument_location, descriptor_geometry(compiler, parameter.ty), argument)
                    emit_plain_geometry_tail(compiler, ir, parameter.ty)
                }
            } else {
                ir_write_ascii(compiler, ir, llvm_type_name(parameter.ty)); ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, argument)
            }
        }
        argument = compiler.child_next[argument]
    }
    ir_write_ascii(compiler, ir, ")\n")
    if result_type == TY_NEVER { ir_write_ascii(compiler, ir, "  unreachable\n"); return }
    if wraps_result {
        if aggregate_result || result_type == TY_UNIT {
            emit_sum_tag_store(compiler, ir, node, 0L)
        } else {
            let address = enum_temporary_address(node, MAX_TREE_NODES * 80L + 2L)
            emit_layout_address(compiler, ir, address, destination)
            if result_type == TY_BOOL {
                ir_write_ascii(compiler, ir, "  %optional.call.bool."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i1 %optional.call.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i8\n  store i8 %optional.call.bool."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n")
            } else {
                ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(result_type)); ir_write_ascii(compiler, ir, " %optional.call.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n")
            }
            emit_sum_tag_store(compiler, ir, node, 0L)
        }
    }
}

fn emit_optional_call_start(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) -> bool {
    let receiver = compiler.child_first[node]
    let receiver_type = compiler.facts[receiver].ty
    let receiver_payload = sum_payload_record(compiler, receiver_type, 0L, 0L)
    let receiver_source = aggregate_source_location_for_node(tables, compiler, receiver)
    let tag_address = enum_temporary_address(node, MAX_TREE_NODES * 80L + 3L)
    emit_layout_address(compiler, ir, tag_address, receiver_source)
    ir_write_ascii(compiler, ir, "  %optional.call.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address)
    ir_write_ascii(compiler, ir, ", align 1\n  %optional.call.present."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i32 %optional.call.tag."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", 0\n  br i1 %optional.call.present."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %optional.call.some."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %optional.call.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\noptional.call.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    emit_sum_tag_store(compiler, ir, node, 1L)
    ir_write_ascii(compiler, ir, "  br label %optional.call.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\noptional.call.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if compiler.facts[node].literal == -2L {
        let source_payload = optional_payload_location(receiver_source, receiver_payload.offset)
        let source_address = enum_temporary_address(node, MAX_TREE_NODES * 80L + 4L)
        emit_layout_address(compiler, ir, source_address, source_payload)
        ir_write_ascii(compiler, ir, "  %optional.call.int."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n  %optional.call.long."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sext i32 %optional.call.int."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i64\n")
        let output_payload = sum_payload_record(compiler, compiler.facts[node].ty, 0L, 0L)
        let output_address = enum_temporary_address(node, MAX_TREE_NODES * 80L + 5L)
        emit_layout_address(compiler, ir, output_address, optional_payload_location(aggregate_destination_location(compiler, 0L, node), output_payload.offset))
        ir_write_ascii(compiler, ir, "  store i64 %optional.call.long."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, output_address); ir_write_ascii(compiler, ir, ", align 1\n")
        emit_sum_tag_store(compiler, ir, node, 0L)
        ir_write_ascii(compiler, ir, "  br label %optional.call.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\noptional.call.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        true
    } else {
        let target_id = compiler.facts[node].function
        if target_id >= 0L {
            let target = compiler.functions[target_id]
            let receiver_parameter = compiler.parameters[target.param_start]
            if receiver_parameter.ty != TY_UNIT {
                let payload_receiver_source = aggregate_source_location_for_node(tables, compiler, receiver)
                let source_payload = optional_payload_location(payload_receiver_source, receiver_payload.offset)
                if is_aggregate_type(compiler, receiver_parameter.ty) {
                    let receiver_storage_ty = if parameter_uses_text_read_view(compiler, receiver_parameter) { receiver_payload.ty }
                        else { receiver_parameter.ty }
                    emit_aggregate_copy(compiler, ir, receiver_storage_ty, native_location(10L, node, 0L), source_payload)
                } else {
                    let source_address = enum_temporary_address(node, MAX_TREE_NODES * 80L + 6L)
                    emit_layout_address(compiler, ir, source_address, source_payload)
                    if receiver_parameter.ty == TY_BOOL {
                        ir_write_ascii(compiler, ir, "  %optional.call.receiver.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n  %optional.call.receiver."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i8 %optional.call.receiver.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i1\n")
                    } else {
                        ir_write_ascii(compiler, ir, "  %optional.call.receiver."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(receiver_parameter.ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n")
                    }
                }
            }
        }
        false
    }
}



// E3a1 begin: shared compiler integration.
recursive fn emit_expr_linear(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    return_ty: long,
    is_test: bool,
) {
    let base_depth = compiler.expr_work.count()
    compiler.expr_work.push(EmitExprFrame { node, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
    for emit_step in 0L..MAX_PARSE_WORK {
        if compiler.expr_work.count() <= base_depth { break }
        let frame_index = compiler.expr_work.count() - 1L
        var frame = compiler.expr_work[frame_index]
        let current = frame.node
        let syntax = tables.nodes[current]
        let kind = syntax.kind
        if frame.phase == 0L {
            if kind == NodeKind.Integer && compiler.facts[current].ty == TY_DOUBLE {
                emit_float_literal(source, files, tokens, tables, compiler, ir, current, file_index)
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Integer || kind == NodeKind.Bool {
                let ty = compiler.facts[current].ty
                let literal = compiler.facts[current].literal
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = add "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " 0, "); ir_write_number(compiler, ir, literal); ir_write_ascii(compiler, ir, "\n")
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Name {
                let ty = compiler.facts[current].ty
                let binding = compiler.facts[current].binding
                let case_tag = compiler.facts[current].literal
                if (compiler.facts[current].flags & FACT_CONSTANT_VALUE) != 0L {
                    ()
                } else if (compiler.facts[current].flags & FACT_CONSTANT_ARRAY) != 0L {
                    emit_array_constant_value(compiler, ir, current, file_index)
                } else if (compiler.facts[current].flags & FACT_CONSTANT_TEXT) != 0L {
                    let text_literal = compiler.facts[current].literal
                    emit_text_literal_value(source, files, tokens, tables, compiler, ir, current, text_literal, file_index, is_test || compiler.test_build)
                } else if is_sum_type(compiler, ty) && binding < 0L {
                    if type_kind(compiler, ty) == TYPE_KIND_ENUM { emit_enum_tag_store(compiler, ir, current, case_tag) }
                    else { emit_sum_tag_store(compiler, ir, current, case_tag) }
                } else if binding_is_view(compiler, binding) {
                    if !is_aggregate_type(compiler, ty) && ty != TY_UNIT {
                        let _ = emit_collection_view_name_address(tables, compiler, ir, current)
                        let view_loop = compiler.bindings[binding].node
                        let view_collection = compiler.child_first[view_loop]
                        let view_kind = type_kind(compiler, compiler.facts[view_collection].ty)
                        if ty == TY_BYTE && (view_kind == TYPE_KIND_ASCII || view_kind == TYPE_KIND_BYTES) {
                            ir_write_ascii(compiler, ir, "  %text.view.byte."); ir_write_number(compiler, ir, current)
                            ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, current)
                            ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, current)
                            ir_write_ascii(compiler, ir, " = zext i8 %text.view.byte."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " to i32\n")
                        } else { emit_load_scalar(compiler, ir, current, ty) }
                    } else if is_aggregate_type(compiler, ty) { emit_collection_gather_view_value(tables, compiler, ir, current) }
                    else { () }
                } else if ty == TY_UNIT { () }
                else if is_aggregate_type(compiler, ty) {
                    if compiler.emit_destination_node == current {
                        let source_kind = if compiler.bindings[binding].parameter { 2L } else { 1L }
                        emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 0L, current), aggregate_source_location(compiler, source_kind, binding))
                    } else { () }
                }
                else if binding_is_write_parameter(compiler, binding) {
                    emit_layout_address(compiler, ir, current, compiler_location(compiler, 3L, binding, 0L))
                    emit_load_scalar(compiler, ir, current, ty)
                }
                else if ty == TY_BOOL { ir_write_ascii(compiler, ir, "  %bool.load."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load i8, ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = trunc i8 %bool.load."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " to i1\n") }
                else { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Field {
                if is_enum_case_field(tables, compiler, current) {
                    let case_tag = compiler.facts[current].literal
                    emit_enum_tag_store(compiler, ir, current, case_tag)
                    match compiler.expr_work.pop() { some(_) => (), none => () }
                } else {
                    frame.child0 = compiler.child_first[current]
                    frame.phase = 1L
                    compiler.expr_work[frame_index] = frame
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.StructInit {
                frame.cursor = compiler.child_first[current]
                frame.phase = 50L
                compiler.expr_work[frame_index] = frame
            } else if kind == NodeKind.ArrayLiteral {
                frame.cursor = compiler.child_first[current]
                frame.auxiliary = 0L
                frame.child2 = -1L
                if type_kind(compiler, compiler.facts[current].ty) == TYPE_KIND_BYTES {
                    let destination = aggregate_destination_location(compiler, 0L, current)
                    frame.child2 = emit_location_pointer_materialization(compiler, ir, destination)
                    ir_write_ascii(compiler, ir, "  %text.bytes.literal.length.addr."); ir_write_number(compiler, ir, current)
                    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, frame.child2)
                    ir_write_ascii(compiler, ir, ", i64 0\n  store i64 "); ir_write_number(compiler, ir, count_children(tables, compiler, current))
                    ir_write_ascii(compiler, ir, ", ptr %text.bytes.literal.length.addr."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 10)
                }
                frame.phase = 72L
                compiler.expr_work[frame_index] = frame
            } else if kind == NodeKind.ListLiteral || kind == NodeKind.QueueLiteral || kind == NodeKind.MapLiteral || kind == NodeKind.PoolLiteral {
                let list_type = compiler.facts[current].ty
                emit_collection_zero_storage(compiler, ir, current, list_type, 0L)
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Index {
                frame.child0 = compiler.child_first[current]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.phase = 70L
                compiler.expr_work[frame_index] = frame
                if frame.child0 >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.ByteString || kind == NodeKind.BytesLiteral {
                emit_text_literal_value(source, files, tokens, tables, compiler, ir, current, current, file_index, is_test || compiler.test_build)
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Unary {
                frame.child0 = compiler.child_first[current]
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Binary {
                frame.child0 = compiler.child_first[current]
                frame.child1 = compiler.child_next[frame.child0]
                frame.phase = if syntax.flags == 21L { 40L } else { 1L }
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Call && (syntax.flags & FLAG_SYNTHETIC) != 0L {
                let ty = compiler.facts[current].ty
                if type_kind(compiler, ty) == TYPE_KIND_ARRAY || collection_kind_is_list(type_kind(compiler, ty)) {
                    emit_collection_zero_storage(compiler, ir, current, ty, 0L)
                } else if ty == TY_UNIT || ty == TY_NEVER { () }
                else { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = add "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " 0, 0\n") }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Call || kind == NodeKind.QualifiedCase {
                let is_constructor = compiler.facts[current].function < 0L && is_sum_type(compiler, compiler.facts[current].ty)
                frame.cursor = compiler.child_first[current]
                frame.phase = if is_constructor { 60L } else { 1L }
                frame.auxiliary = 0L
                compiler.expr_work[frame_index] = frame
            } else if kind == NodeKind.MethodCall {
                let receiver = compiler.child_first[current]
                let is_sys = is_core_sys_receiver(source, tokens, files, tables, compiler, current, file_index)
                let is_text_empty = compiler.facts[current].literal == TEXT_METHOD_EMPTY
                frame.child0 = receiver
                frame.cursor = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                if !is_sys && !is_text_empty && receiver >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: receiver, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.OptionalCall {
                let receiver = compiler.child_first[current]
                frame.child0 = receiver
                frame.phase = 90L
                compiler.expr_work[frame_index] = frame
                if receiver >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: receiver, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.Try {
                frame.child0 = compiler.child_first[current]
                frame.phase = 18L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Fit {
                frame.child0 = compiler.child_first[current]
                frame.phase = 2L
                compiler.expr_work[frame_index] = frame
                if frame.child0 >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.Cast {
                let type_node = compiler.child_first[current]
                frame.child0 = if type_node >= 0L { compiler.child_next[type_node] } else { -1L }
                frame.child1 = type_node
                frame.auxiliary = compiler.facts[current].ty
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                if frame.child0 >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.ToLong {
                frame.child0 = compiler.child_first[current]
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                if frame.child0 >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.If {
                frame.child0 = compiler.child_first[current]
                frame.child1 = compiler.child_next[frame.child0]
                frame.child2 = compiler.child_next[frame.child1]
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Match {
                frame.child0 = compiler.child_first[current]
                frame.cursor = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.auxiliary = 0L
                frame.phase = 30L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Block {
                // E3a1 subsection
                emit_region_scope_enter(files, tables, compiler, ir, current, file_index)
                // E3a1 subsection end
                frame.cursor = compiler.child_first[current]
                frame.child0 = node_last_child(tables, compiler, current)
                frame.phase = 10L
                compiler.expr_work[frame_index] = frame
            } else if kind == NodeKind.Return {
                frame.child0 = compiler.child_first[current]
                if frame.child0 >= 0L {
                    frame.phase = 17L
                    compiler.expr_work[frame_index] = frame
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                } else {
                    if is_test { lower_scope_exit(compiler, ir, -1L, EXIT_TEST_FAILURE, 0L, 0L, TY_UNIT, -1L) }
                    else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, TY_UNIT, -1L) }
                    match compiler.expr_work.pop() { some(_) => (), none => () }
                }
            } else if kind == NodeKind.LoopExit {
                let is_break = (syntax.flags & FLAG_VALUE) != 0L
                let loop = compiler.emit_loops[compiler.emit_loops.count() - 1L]
                // E3a1 subsection
                emit_region_loop_exit(tables, compiler, ir, loop.body, current)
                // E3a1 subsection end
                let target_kind = if tables.nodes[loop.node].kind == NodeKind.While { 1L } else { 0L }
                if is_break { lower_scope_exit(compiler, ir, -1L, EXIT_BREAK, target_kind, loop.node, TY_UNIT, -1L) }
                else { lower_scope_exit(compiler, ir, -1L, EXIT_CONTINUE, target_kind, loop.node, TY_UNIT, -1L) }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.Field && frame.phase == 1L {
            if compiler.c_runtime && compiler.facts[frame.child0].ty == TY_ENV {
                emit_c_runtime_environment_field(compiler, ir, current)
            } else {
                emit_aggregate_address(tables, compiler, ir, current)
                let ty = compiler.facts[current].ty
                if is_aggregate_type(compiler, ty) {
                    if compiler.emit_destination_node == current {
                        emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 0L, current), aggregate_source_location(compiler, 3L, current))
                    } else { () }
                } else if ty != TY_UNIT { emit_load_scalar(compiler, ir, current, ty) }
                else { () }
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Index && frame.phase == 70L {
            if frame.child0 >= 0L && (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if frame.child1 >= 0L {
                frame.phase = 71L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child1, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                compiler.ir_overflow = true
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.Index && frame.phase == 71L {
            if (compiler.facts[frame.child1].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else {
                emit_collection_index_address(files, tables, compiler, ir, current, file_index)
                let ty = compiler.facts[current].ty
                if is_aggregate_type(compiler, ty) {
                    if !collection_index_has_field_projection(tables, compiler, current) && !region_node_is_collection_method_receiver(tables, compiler, current) {
                        emit_collection_gather_index_value(tables, compiler, ir, current)
                    }
                }
                else if ty == TY_BYTE && (type_kind(compiler, compiler.facts[frame.child0].ty) == TYPE_KIND_BYTES || type_kind(compiler, compiler.facts[frame.child0].ty) == TYPE_KIND_ASCII) {
                    ir_write_ascii(compiler, ir, "  %text.index.byte."); ir_write_number(compiler, ir, current)
                    ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, current)
                    ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, current)
                    ir_write_ascii(compiler, ir, " = zext i8 %text.index.byte."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " to i32\n")
                }
                else if ty != TY_UNIT { emit_load_scalar(compiler, ir, current, ty) }
                else { () }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.ArrayLiteral && frame.phase == 72L {
            if frame.cursor >= 0L {
                let element = frame.cursor
                frame.cursor = compiler.child_next[element]
                if type_kind(compiler, compiler.facts[current].ty) == TYPE_KIND_BYTES &&
                    text_expression_may_call(tables, compiler, element) { frame.child2 = -1L }
                frame.child0 = element
                frame.phase = 73L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: element, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                let ty = compiler.facts[current].ty
                if collection_kind_is_list(type_kind(compiler, ty)) { emit_collection_zero_storage(compiler, ir, current, ty, frame.auxiliary) }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.ArrayLiteral && frame.phase == 73L {
            let element = frame.child0
            if (compiler.facts[element].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else {
                let collection_type = compiler.facts[current].ty
                if type_kind(compiler, collection_type) == TYPE_KIND_BYTES {
                    frame.child2 = emit_text_bytes_literal_element(compiler, ir, current, frame.auxiliary, element, frame.child2)
                } else {
                    emit_collection_literal_element(tables, compiler, ir, current, collection_type, frame.auxiliary, element)
                }
                frame.auxiliary += 1L
                frame.phase = 72L
                compiler.expr_work[frame_index] = frame
            }
        } else if kind == NodeKind.StructInit && frame.phase == 50L {
            let initializer = frame.cursor
            if initializer >= 0L {
                let value = compiler.child_first[initializer]
                frame.child0 = initializer
                frame.child1 = value
                frame.cursor = compiler.child_next[initializer]
                frame.phase = 51L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: value, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                let type_index = compiler.facts[current].literal
                let type_id = struct_type_id(compiler, type_index)
                if struct_has_defaults(compiler, type_index) {
                    let ty = struct_record(compiler, type_index)
                    var item_count = 0L
                    for field_offset in 0L..ty.field_count {
                        let field_index = ty.field_start + field_offset
                        var child = compiler.child_first[current]
                        for field_step in 0L..tables.nodes[current].subtree {
                            if child < 0L { break }
                            if compiler.facts[child].binding == field_index { item_count += 1L }
                            child = compiler.child_next[child]
                        }
                    }
                    // E3a1 subsection: materialize the current top after arguments.
                    emit_current_top_load(compiler, ir, current)
                    ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_FILL); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 "); emit_current_top_reference(compiler, ir, current); ir_write_ascii(compiler, ir, ", "); emit_location_descriptor_argument(compiler, ir, aggregate_destination_location(compiler, 0L, current), true, current); ir_write_ascii(compiler, ir, ", ptr @.nl.given."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, item_count); ir_write_ascii(compiler, ir, ")\n")
                    // E3a1 subsection end
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.StructInit && frame.phase == 51L {
            let initializer = frame.child0
            let value = frame.child1
            if (compiler.facts[value].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else {
                let field_index = compiler.facts[initializer].binding
                let field = compiler.struct_fields[field_index]
                // E3a1 subsection: region-backed aggregate destinations reload the base at use.
                let destination = aggregate_destination_location(compiler, 0L, current)
                emit_layout_address(compiler, ir, initializer, StorageLocation { origin: destination.origin, anchor_kind: destination.anchor_kind, anchor_node: destination.anchor_node, byte_offset: destination.byte_offset + field.offset, copies: destination.copies, index: destination.index, index_node: destination.index_node, index_stride: destination.index_stride })
                // E3a1 subsection end
                if is_aggregate_type(compiler, field.ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, value)
                    let source_node = aggregate_source_id(tables, compiler, value)
                    emit_aggregate_copy(compiler, ir, field.ty, aggregate_destination_location(compiler, 3L, initializer), aggregate_source_location(compiler, source_kind, source_node))
                } else if field.ty != TY_UNIT {
                    emit_store_scalar(compiler, ir, initializer, field.ty, value)
                } else { () }
                frame.phase = 50L
                compiler.expr_work[frame_index] = frame
            }
        } else if kind == NodeKind.Unary {
            let ty = compiler.facts[current].ty
            if syntax.flags == 1L {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = xor i1 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", true\n")
            } else if ty == TY_DOUBLE {
                emit_double_negate(compiler, ir, current, frame.child0)
            } else if syntax.flags == 2L {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = xor "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", -1\n")
            } else {
                ir_write_ascii(compiler, ir, "  %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = call { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } @llvm.ssub.with.overflow."); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " 0, "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ")\n")
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 0\n  %ov.flag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 1\n")
                let failure_kind = if ty == TY_INT { 4L } else { 8L }
                emit_runtime_failure(files, tables, compiler, ir, current, file_index, failure_kind)
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Fit && frame.phase == 2L {
            let target_ty = sum_payload_record(compiler, compiler.facts[current].ty, 0L, 0L).ty
            if target_ty == TY_BYTE { emit_byte_fit(compiler, ir, current) }
            else { emit_ascii_fit(tables, compiler, ir, current) }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Cast && frame.phase == 1L {
            let source_ty = compiler.facts[frame.child0].ty
            let target_ty = frame.auxiliary
            if source_ty == TY_DOUBLE || target_ty == TY_DOUBLE {
                emit_double_cast(files, tables, compiler, ir, current, file_index, frame.child0, source_ty, target_ty)
            } else if type_kind(compiler, target_ty) == TYPE_KIND_ASCII {
                emit_ascii_cast(files, tables, compiler, ir, current, file_index, frame.child0, target_ty)
            } else if source_ty == target_ty {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = add "); ir_write_ascii(compiler, ir, llvm_type_name(target_ty)); ir_write_ascii(compiler, ir, " 0, "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, "\n")
            } else if source_ty == TY_INT && target_ty == TY_LONG {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = sext i32 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i64\n")
            } else if source_ty == TY_BYTE && target_ty == TY_INT {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = add i32 0, "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, "\n")
            } else if target_ty == TY_BYTE {
                if (syntax.flags & FLAG_CAST_UNCHECKED) != 0L {
                    if source_ty == TY_LONG {
                        ir_write_ascii(compiler, ir, "  %cast.low8."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = and i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 255\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = trunc i64 %cast.low8."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " to i32\n")
                    } else {
                        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = and i32 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 255\n")
                    }
                } else {
                    let width: Ascii max 4 = if source_ty == TY_LONG { "i64" } else { "i32" }
                    ir_write_ascii(compiler, ir, "  %cast.low."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = icmp sge "); ir_write_ascii(compiler, ir, width); ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 0\n  %cast.high."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = icmp sle "); ir_write_ascii(compiler, ir, width); ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 255\n  %cast.ok."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = and i1 %cast.low."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", %cast.high."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\n  br i1 %cast.ok."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %cast.good."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %cast.fail."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\ncast.fail."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 10, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + syntax.start, compiler).line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + syntax.start, compiler).col); ir_write_ascii(compiler, ir, ")\n  unreachable\ncast.good."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = "); if source_ty == TY_LONG { ir_write_ascii(compiler, ir, "trunc i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i32\n") } else { ir_write_ascii(compiler, ir, "add i32 0, "); ir_write_value_ref(compiler, ir, frame.child0); ir_push_byte(compiler, ir, 10) }
                }
            } else if target_ty == TY_LONG && (source_ty == TY_BYTE || source_ty == TY_INT) {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = sext i32 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i64\n")
            } else {
                ir_write_ascii(compiler, ir, "  %cast.low."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = icmp sge i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", -2147483648\n  %cast.high."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = icmp sle i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 2147483647\n  %cast.ok."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = and i1 %cast.low."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", %cast.high."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\n  br i1 %cast.ok."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %cast.good."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %cast.fail."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\ncast.fail."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 10, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + syntax.start, compiler).line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + syntax.start, compiler).col); ir_write_ascii(compiler, ir, ")\n  unreachable\ncast.good."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = trunc i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i32\n")
            }
            if type_kind(compiler, target_ty) != TYPE_KIND_ASCII {
                let cast_range = written_type_range_node(tables, compiler, compiler.child_first[current])
                if cast_range >= 0L { emit_cast_range_check(files, tables, compiler, ir, current, file_index, cast_range, target_ty) }
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.ToLong && frame.phase == 1L {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = sext i32 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i64\n")
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Return && frame.phase == 17L {
            if is_aggregate_type(compiler, return_ty) {
                let source_kind = aggregate_source_kind(tables, compiler, frame.child0)
                let source_node = aggregate_source_id(tables, compiler, frame.child0)
                emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(compiler, 2L, 0L), aggregate_source_location(compiler, source_kind, source_node))
                lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L)
            } else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN_VALUE, 0L, 0L, return_ty, frame.child0) }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Try && frame.phase == 18L {
            let operand = frame.child0
            let operand_ty = compiler.facts[operand].ty
            let operand_kind = type_kind(compiler, operand_ty)
            let operand_source = aggregate_source_location_for_node(tables, compiler, operand)
            let tag_address = enum_temporary_address(current, MAX_TREE_NODES + 8L)
            emit_layout_address(compiler, ir, tag_address, operand_source)
            ir_write_ascii(compiler, ir, "  %try.tag."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address)
            ir_write_ascii(compiler, ir, ", align 1\n  %try.is.success."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, " = icmp eq i32 %try.tag."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", 0\n  br i1 %try.is.success."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", label %try.success."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", label %try.failure."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, "\ntry.success."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            let success = sum_payload_record(compiler, operand_ty, 0L, 0L)
            emit_sum_payload_to_expression(compiler, ir, current, success.ty, operand_source, success.offset, enum_temporary_address(current, MAX_TREE_NODES + 9L))
            ir_write_ascii(compiler, ir, "  br label %try.end."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, "\ntry.failure."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            let result_ty = return_ty
            let result_kind = type_kind(compiler, result_ty)
            let result_destination = if compiler.core_mode { compiler_location(compiler, 4L, 0L, 0L) } else { aggregate_destination_location(compiler, 2L, 0L) }
            let result_tag_address = enum_temporary_address(current, MAX_TREE_NODES + 10L)
            emit_layout_address(compiler, ir, result_tag_address, result_destination)
            ir_write_ascii(compiler, ir, "  %try.result.tag."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, " = add i32 0, 1\n  store i32 %try.result.tag."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, result_tag_address); ir_write_ascii(compiler, ir, ", align 1\n")
            if operand_kind == TYPE_KIND_RESULT && result_kind == TYPE_KIND_RESULT {
                let error = sum_payload_record(compiler, operand_ty, 1L, 0L)
                let destination_error = sum_payload_record(compiler, result_ty, 1L, 0L)
                emit_sum_payload_transfer(compiler, ir, error.ty, operand_source, error.offset, result_destination, destination_error.offset, enum_temporary_address(current, MAX_TREE_NODES + 11L))
            }
            lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, result_ty, -1L)
            ir_write_ascii(compiler, ir, "try.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Binary && frame.phase == 40L {
            let left = frame.child0
            let option_ty = compiler.facts[left].ty
            let left_source = aggregate_source_location_for_node(tables, compiler, left)
            let tag_address = enum_temporary_address(current, MAX_TREE_NODES + 2L)
            emit_layout_address(compiler, ir, tag_address, left_source)
            ir_write_ascii(compiler, ir, "  %coalesce.tag."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address)
            ir_write_ascii(compiler, ir, ", align 1\n  %coalesce.is.some."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, " = icmp eq i32 %coalesce.tag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 0\n  br i1 %coalesce.is.some."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", label %coalesce.some."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", label %coalesce.none."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, "\ncoalesce.some."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            let payload = sum_payload_record(compiler, option_ty, 0L, 0L)
            emit_sum_payload_to_coalesce(compiler, ir, current, payload.ty, left_source, payload.offset, enum_temporary_address(current, MAX_TREE_NODES + 3L))
            ir_write_ascii(compiler, ir, "  br label %coalesce.end."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, "\ncoalesce.none."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            frame.phase = 41L
            compiler.expr_work[frame_index] = frame
            compiler.expr_work.push(EmitExprFrame { node: frame.child1, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
        } else if kind == NodeKind.Binary && frame.phase == 41L {
            let result_ty = compiler.facts[current].ty
            let fallback = frame.child1
            if compiler.facts[fallback].ty != TY_NEVER {
                if is_aggregate_type(compiler, result_ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, fallback)
                    let source_node = aggregate_source_id(tables, compiler, fallback)
                    emit_aggregate_copy(compiler, ir, result_ty, aggregate_destination_location(compiler, 0L, current), aggregate_source_location(compiler, source_kind, source_node))
                } else if result_ty != TY_UNIT {
                    ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty)); ir_push_byte(compiler, ir, 32)
                    ir_write_value_ref(compiler, ir, fallback); ir_write_ascii(compiler, ir, ", ptr %coalesce.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n")
                } else { () }
                ir_write_ascii(compiler, ir, "  br label %coalesce.end."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 10)
            }
            ir_write_ascii(compiler, ir, "coalesce.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            if result_ty != TY_UNIT && !is_aggregate_type(compiler, result_ty) {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty))
                ir_write_ascii(compiler, ir, ", ptr %coalesce.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n")
            }
            match compiler.expr_work.pop() { some(_) => (), none() => () }
        } else if kind == NodeKind.Binary && frame.phase == 1L {
            let op = syntax.flags
            if op == 14L || op == 15L {
                ir_write_ascii(compiler, ir, "  br i1 "); ir_write_value_ref(compiler, ir, frame.child0)
                if op == 14L {
                    ir_write_ascii(compiler, ir, ", label %logic.rhs."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %logic.short."); ir_write_number(compiler, ir, current)
                } else {
                    ir_write_ascii(compiler, ir, ", label %logic.short."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %logic.rhs."); ir_write_number(compiler, ir, current)
                }
                ir_write_ascii(compiler, ir, "\nlogic.short."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  store i1 ")
                if op == 14L { ir_write_ascii(compiler, ir, "false") } else { ir_write_ascii(compiler, ir, "true") }
                ir_write_ascii(compiler, ir, ", ptr %logic.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n  br label %logic.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\nlogic.rhs."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            }
            let comparison_snapshot = op >= 8L && op <= 13L &&
                is_aggregate_type(compiler, compiler.facts[frame.child0].ty) &&
                (tables.nodes[frame.child0].kind == NodeKind.Name || tables.nodes[frame.child0].kind == NodeKind.Field) &&
                (!is_text_comparable(compiler, compiler.facts[frame.child0].ty, compiler.facts[frame.child1].ty) ||
                    region_subtree_has_effect(tables, frame.child1, frame.child1))
            if comparison_snapshot || text_concat_left_needs_snapshot(tables, compiler, current) {
                let ty = compiler.facts[frame.child0].ty
                let source_kind = aggregate_source_kind(tables, compiler, frame.child0)
                let source_node = aggregate_source_id(tables, compiler, frame.child0)
                emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 0L, frame.child0), aggregate_source_location(compiler, source_kind, source_node))
            }
            frame.phase = 2L
            compiler.expr_work[frame_index] = frame
            compiler.expr_work.push(EmitExprFrame { node: frame.child1, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
        } else if kind == NodeKind.Binary && frame.phase == 2L {
            let left = frame.child0
            let right = frame.child1
            let op = syntax.flags
            if compiler.facts[left].ty == TY_DOUBLE && op != 14L && op != 15L && op != 21L {
                emit_double_binary(files, tables, compiler, ir, current, file_index, op, left, right)
            } else if op == 14L || op == 15L {
                ir_write_ascii(compiler, ir, "  store i1 "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", ptr %logic.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n  br label %logic.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\nlogic.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load i1, ptr %logic.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n")
            } else if op >= 8L && op <= 13L && is_text_comparable(compiler, compiler.facts[left].ty, compiler.facts[right].ty) {
                emit_text_compare(tables, compiler, ir, current, op)
            } else if (op == 8L || op == 9L) && is_aggregate_type(compiler, compiler.facts[left].ty) {
                let ty = compiler.facts[left].ty
                let left_location = if tables.nodes[left].kind == NodeKind.Name || tables.nodes[left].kind == NodeKind.Field { compiler_location(compiler, 0L, left, 0L) }
                    else { aggregate_source_location_for_node(tables, compiler, left) }
                let right_location = aggregate_source_location_for_node(tables, compiler, right)
                let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
                let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
                ir_write_ascii(compiler, ir, "  %eq.value."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = call i1 ")
                emit_type_helper_call_two(compiler, ir, ty, HELPER_EQUAL, left_location, right_location, left_pointer, right_pointer)
                ir_push_byte(compiler, ir, 10)
                if op == 8L {
                    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = select i1 true, i1 %eq.value."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", i1 false\n")
                } else {
                    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = xor i1 %eq.value."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", true\n")
                }
            } else if op == 0L && is_text_concatenation(compiler, compiler.facts[left].ty, compiler.facts[right].ty) {
                emit_text_concat(tables, compiler, ir, current, is_test || compiler.test_build)
            } else if op == 0L || op == 1L || op == 2L {
                let ty = compiler.facts[left].ty
                let failure_kind = if ty == TY_INT { op + 1L } else { op + 5L }
                ir_write_ascii(compiler, ir, "  %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = call { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } @llvm.s")
                if op == 0L { ir_write_ascii(compiler, ir, "add") } else if op == 1L { ir_write_ascii(compiler, ir, "sub") } else { ir_write_ascii(compiler, ir, "mul") }
                ir_write_ascii(compiler, ir, ".with.overflow."); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ")\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 0\n  %ov.flag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 1\n")
                emit_runtime_failure(files, tables, compiler, ir, current, file_index, failure_kind)
            } else if op == 3L || op == 4L {
                let ty = compiler.facts[left].ty
                emit_checked_division(files, tables, compiler, ir, current, file_index, left, right, ty, op == 4L)
            } else if op == 19L || op == 20L {
                let ty = compiler.facts[left].ty
                emit_checked_shift(files, tables, compiler, ir, current, file_index, left, right, ty, op == 19L)
            } else if op == 16L || op == 17L || op == 18L {
                let ty = compiler.facts[left].ty
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = ")
                if op == 16L { ir_write_ascii(compiler, ir, "and ") }
                else if op == 17L { ir_write_ascii(compiler, ir, "or ") }
                else { ir_write_ascii(compiler, ir, "xor ") }
                ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_push_byte(compiler, ir, 10)
            } else {
                let operand_ty = compiler.facts[left].ty
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = ")
                if op == 0L { ir_write_ascii(compiler, ir, "add ") }
                else if op == 1L { ir_write_ascii(compiler, ir, "sub ") }
                else if op == 2L { ir_write_ascii(compiler, ir, "mul ") }
                else if op == 5L { ir_write_ascii(compiler, ir, "add ") }
                else if op == 6L { ir_write_ascii(compiler, ir, "sub ") }
                else if op == 7L { ir_write_ascii(compiler, ir, "mul ") }
                else if op == 3L { ir_write_ascii(compiler, ir, "sdiv ") }
                else if op == 4L { ir_write_ascii(compiler, ir, "srem ") }
                else if op == 8L { ir_write_ascii(compiler, ir, "icmp eq ") }
                else if op == 9L { ir_write_ascii(compiler, ir, "icmp ne ") }
                else if op == 10L { ir_write_ascii(compiler, ir, "icmp slt ") }
                else if op == 11L { ir_write_ascii(compiler, ir, "icmp sle ") }
                else if op == 12L { ir_write_ascii(compiler, ir, "icmp sgt ") }
                else { ir_write_ascii(compiler, ir, "icmp sge ") }
                ir_write_ascii(compiler, ir, llvm_type_name(operand_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, "\n")
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if (kind == NodeKind.Call || kind == NodeKind.QualifiedCase) && (frame.phase == 60L || frame.phase == 61L) {
            let is_generic_sum = type_kind(compiler, compiler.facts[current].ty) == TYPE_KIND_OPTION || type_kind(compiler, compiler.facts[current].ty) == TYPE_KIND_RESULT
            let case_index = enum_case_for_tag(compiler, compiler.facts[current].ty, compiler.facts[current].literal)
            if frame.phase == 61L {
                if (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) == 0L {
                    match compiler.expr_work.pop() { some(_) => (), none() => () }
                } else {
                    if is_generic_sum { emit_sum_constructor_payload(tables, compiler, ir, current, frame.child1, frame.child0) }
                    else { emit_enum_constructor_payload(tables, compiler, ir, current, case_index, frame.child1, frame.child0) }
                    frame.auxiliary += 1L
                    frame.phase = 60L
                    compiler.expr_work[frame_index] = frame
                }
            } else if frame.cursor >= 0L {
                let argument = frame.cursor
                let payload_index = frame.auxiliary
                frame.cursor = compiler.child_next[argument]
                frame.child0 = argument
                frame.child1 = payload_index
                frame.phase = 61L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: argument, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                let case_tag = compiler.facts[current].literal
                if is_generic_sum { emit_sum_tag_store(compiler, ir, current, case_tag) }
                else { emit_enum_tag_store(compiler, ir, current, case_tag) }
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            }
        } else if kind == NodeKind.Call {
            if frame.phase == 2L {
                let argument = frame.child0
                if (compiler.facts[argument].flags & FACT_FALLS_THROUGH) == 0L {
                    match compiler.expr_work.pop() { some(_) => (), none() => () }
                } else {
                    if direct_call_argument_needs_snapshot(tables, compiler, current, argument) {
                        let ty = compiler.facts[argument].ty
                        let source_kind = aggregate_source_kind(tables, compiler, argument)
                        let source_node = aggregate_source_id(tables, compiler, argument)
                        emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 0L, argument), aggregate_source_location(compiler, source_kind, source_node))
                    }
                    frame.child0 = -1L
                    frame.phase = 1L
                    compiler.expr_work[frame_index] = frame
                }
            } else if frame.phase == 1L && frame.child0 >= 0L && (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            } else if frame.cursor >= 0L {
                let argument = frame.cursor
                frame.cursor = compiler.child_next[argument]
                frame.phase = if is_aggregate_type(compiler, compiler.facts[argument].ty) { 2L } else { 1L }
                frame.child0 = argument
                compiler.expr_work[frame_index] = frame
                if direct_call_argument_is_write(tables, compiler, current, argument) &&
                    is_aggregate_type(compiler, compiler.facts[argument].ty) && tables.nodes[argument].kind == NodeKind.Name {
                    frame.child0 = -1L
                    frame.phase = 1L
                    compiler.expr_work[frame_index] = frame
                } else {
                    compiler.expr_work.push(EmitExprFrame { node: argument, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else {
                let is_print = token_is_word_at(source, tokens, files, file_index, syntax.token, "print")
                let is_fill = token_is_word_at(source, tokens, files, file_index, syntax.token, "fill") &&
                    compiler.facts[current].function < 0L
                let format_kind = if (compiler.facts[current].flags & FACT_FORMAT_TEXT) != 0L { compiler.facts[current].literal } else { FORMAT_TEXT_NONE }
                let first_arg = compiler.child_first[current]
                if format_kind != FORMAT_TEXT_NONE {
                    emit_format_text_builtin(source, files, tokens, tables, compiler, ir, current, file_index, is_test, format_kind)
                } else if is_print {
                    let arg_ty = compiler.facts[first_arg].ty
                    if is_aggregate_type(compiler, arg_ty) {
                        let location = aggregate_source_location_for_node(tables, compiler, first_arg)
                        let pointer = emit_location_pointer_materialization(compiler, ir, location)
                        ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_one(compiler, ir, arg_ty, HELPER_PRINT, location, pointer); ir_write_ascii(compiler, ir, "\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_newline", "nlc_print_newline"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n")
                    } else {
                        ir_write_ascii(compiler, ir, "  call void ")
                        if compiler.c_runtime && (arg_ty == TY_INT || arg_ty == TY_BYTE) {
                            emit_context_runtime_symbol(compiler, ir, "nl_print_int_raw", "nlc_print_int_raw")
                            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 ")
                        } else if compiler.c_runtime && arg_ty == TY_LONG {
                            emit_context_runtime_symbol(compiler, ir, "nl_print_long_raw", "nlc_print_long_raw")
                            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 ")
                        } else if compiler.c_runtime {
                            emit_context_runtime_symbol(compiler, ir, "nl_print_bool_raw", "nlc_print_bool_raw")
                            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i1 zeroext ")
                        } else if arg_ty == TY_INT || arg_ty == TY_BYTE {
                            ir_write_ascii(compiler, ir, "@nl_print_int(ptr %nl.ctx, i32 ")
                        } else if arg_ty == TY_LONG {
                            ir_write_ascii(compiler, ir, "@nl_print_long(ptr %nl.ctx, i64 ")
                        } else {
                            ir_write_ascii(compiler, ir, "@nl_print_bool(ptr %nl.ctx, i1 zeroext ")
                        }
                        ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ")\n")
                        if compiler.c_runtime {
                            ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_newline", "nlc_print_newline"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n")
                        }
                    }
                } else if (compiler.facts[current].flags & FACT_NUMERIC_BUILTIN) != 0L {
                    emit_numeric_builtin(files, tables, compiler, ir, current, file_index)
                } else if (compiler.facts[current].flags & FACT_SORT_BUILTIN) != 0L {
                    emit_sort_call(tables, compiler, ir, current)
                } else if is_fill {
                    let fill_type = compiler.facts[current].ty
                    emit_collection_fill_array(tables, compiler, ir, current, fill_type, first_arg)
                } else {
                    let target = compiler.facts[current].function
                    let function = compiler.functions[target]
                    let call_result_ty = function.result_ty
                    let aggregate_result = is_aggregate_type(compiler, call_result_ty)
                    // E3a1 subsection: reload top after argument evaluation; calls may grow the stack.
                    if !compiler.core_mode { emit_current_top_load(compiler, ir, current) }
                    // E3a1 subsection end
                    if !compiler.core_mode {
                        var prepared_argument = first_arg
                        for argument_index in 0L..function.param_count {
                            let parameter = compiler.parameters[function.param_start + argument_index]
                            if parameter.ty != TY_UNIT {
                                if (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
                                    let location = place_storage_location(tables, compiler, prepared_argument)
                                    let geometry = descriptor_geometry(compiler, parameter.ty)
                                    emit_prepare_location_descriptor(compiler, ir, location, geometry, prepared_argument)
                                } else if is_aggregate_type(compiler, parameter.ty) {
                                    if parameter_uses_text_read_view(compiler, parameter) {
                                        let argument_type = compiler.facts[prepared_argument].ty
                                        let use_snapshot = direct_call_text_view_needs_snapshot(tables, compiler, current, prepared_argument)
                                        let location = if use_snapshot { compiler_location(compiler, 0L, prepared_argument, 0L) }
                                            else { direct_call_argument_source_location(tables, compiler, prepared_argument) }
                                        prepare_text_parameter_descriptor(compiler, ir, argument_type, location, prepared_argument)
                                    } else {
                                        let location = if direct_call_argument_needs_snapshot(tables, compiler, current, prepared_argument) {
                                            aggregate_destination_location(compiler, 0L, prepared_argument)
                                        } else {
                                            direct_call_argument_source_location(tables, compiler, prepared_argument)
                                        }
                                        emit_prepare_location_descriptor(compiler, ir, location, descriptor_geometry(compiler, parameter.ty), prepared_argument)
                                    }
                                } else { () }
                            }
                            prepared_argument = compiler.child_next[prepared_argument]
                        }
                    }
                    if call_result_ty != TY_UNIT && call_result_ty != TY_NEVER && !aggregate_result { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = ") } else { ir_write_ascii(compiler, ir, "  ") }
                    ir_write_ascii(compiler, ir, "call ")
                    if aggregate_result || call_result_ty == TY_UNIT || call_result_ty == TY_NEVER { ir_write_ascii(compiler, ir, "void") }
                    else { ir_write_ascii(compiler, ir, llvm_type_name(call_result_ty)) }
                    ir_push_byte(compiler, ir, 32)
                    var wrote_argument = false
                    if compiler.core_mode {
                        ir_write_core_function_symbol(source, files, tokens, compiler, ir, function, target)
                        ir_push_byte(compiler, ir, 40)
                        wrote_argument = false
                        if core_function_has_context(source, tokens, files, function) {
                            ir_write_ascii(compiler, ir, "ptr %nl.ctx")
                            wrote_argument = true
                        }
                    } else {
                        // E3a1 subsection
                        ir_write_ascii(compiler, ir, "@nl_fn_"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 "); emit_current_top_reference(compiler, ir, current)
                        // E3a1 subsection end
                    }
                    if !compiler.core_mode { wrote_argument = true }
                    if aggregate_result {
                        if wrote_argument { ir_write_ascii(compiler, ir, ", ") }
                        emit_hidden_destination_argument(compiler, ir, aggregate_destination_location(compiler, 0L, current))
                        wrote_argument = true
                    }
                    var arg = first_arg
                    for arg_index in 0L..function.param_count {
                        let parameter = compiler.parameters[function.param_start + arg_index]
                        let param_ty = parameter.ty
                        if param_ty != TY_UNIT {
                            if wrote_argument { ir_write_ascii(compiler, ir, ", ") }
                            if (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
                                emit_location_descriptor_argument(compiler, ir, place_storage_location(tables, compiler, arg), descriptor_geometry(compiler, param_ty), arg)
                                emit_plain_geometry_tail(compiler, ir, param_ty)
                            } else if is_aggregate_type(compiler, param_ty) {
                                if parameter_uses_text_read_view(compiler, parameter) {
                                    let use_snapshot = direct_call_text_view_needs_snapshot(tables, compiler, current, arg)
                                    emit_text_parameter_argument(tables, compiler, ir, arg, use_snapshot)
                                } else {
                                    let location = if direct_call_argument_needs_snapshot(tables, compiler, current, arg) {
                                        aggregate_destination_location(compiler, 0L, arg)
                                    } else {
                                        direct_call_argument_source_location(tables, compiler, arg)
                                    }
                                    emit_location_descriptor_argument(compiler, ir, location, descriptor_geometry(compiler, param_ty), arg)
                                    emit_plain_geometry_tail(compiler, ir, param_ty)
                                }
                            } else {
                                ir_write_ascii(compiler, ir, llvm_type_name(param_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, arg)
                            }
                            wrote_argument = true
                        }
                        arg = compiler.child_next[arg]
                    }
                    ir_write_ascii(compiler, ir, ")\n")
                    if call_result_ty == TY_NEVER { ir_write_ascii(compiler, ir, "  unreachable\n") }
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.OptionalCall && frame.phase == 90L {
            let receiver = frame.child0
            if receiver < 0L || (compiler.facts[receiver].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            } else if emit_optional_call_start(tables, compiler, ir, current) {
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            } else {
                frame.cursor = compiler.child_next[receiver]
                frame.phase = 91L
                compiler.expr_work[frame_index] = frame
            }
        } else if kind == NodeKind.OptionalCall && frame.phase == 91L {
            if frame.cursor >= 0L {
                let argument = frame.cursor
                frame.cursor = compiler.child_next[argument]
                frame.child1 = argument
                frame.phase = 92L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: argument, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                emit_optional_call_invoke(tables, compiler, ir, current)
                if compiler.facts[current].ty != TY_NEVER {
                    ir_write_ascii(compiler, ir, "  br label %optional.call.end."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 10)
                }
                ir_write_ascii(compiler, ir, "optional.call.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            }
        } else if kind == NodeKind.OptionalCall && frame.phase == 92L {
            let argument = frame.child1
            if (compiler.facts[argument].flags & FACT_FALLS_THROUGH) == 0L {
                ir_write_ascii(compiler, ir, "optional.call.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            } else {
                if direct_call_argument_needs_snapshot(tables, compiler, current, argument) {
                    let argument_type = compiler.facts[argument].ty
                    let source_kind = aggregate_source_kind(tables, compiler, argument)
                    let source_node = aggregate_source_id(tables, compiler, argument)
                    emit_aggregate_copy(compiler, ir, argument_type, aggregate_destination_location(compiler, 0L, argument), aggregate_source_location(compiler, source_kind, source_node))
                }
                frame.child1 = -1L
                frame.phase = 91L
                compiler.expr_work[frame_index] = frame
            }
        } else if kind == NodeKind.MethodCall {
            if frame.cursor >= 0L {
                if frame.child2 < 0L && text_method_needs_receiver_metrics_capture(tables, compiler, current) {
                    emit_text_method_receiver_metrics(tables, compiler, ir, current)
                    frame.child2 = 0L
                }
                let argument = frame.cursor
                frame.cursor = compiler.child_next[argument]
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: argument, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                let receiver = compiler.child_first[current]
                let receiver_ty = compiler.facts[receiver].ty
                let receiver_kind = type_kind(compiler, receiver_ty)
                let c_method = c_runtime_method_kind(source, tokens, files, compiler, file_index, syntax.token, receiver_ty)
                if (compiler.facts[current].flags & FACT_DOUBLE_METHOD) != 0L {
                    let double_method = compiler.facts[current].literal
                    emit_double_method(tables, compiler, ir, current, double_method)
                } else if c_method != C_METHOD_NONE {
                    emit_c_runtime_method_call(tables, compiler, ir, current)
                } else if parse_number_method_kind(source, tokens, files, file_index, syntax.token) != PARSE_NUMBER_NONE {
                    emit_parse_number_method(source, files, tokens, tables, compiler, ir, current, file_index)
                } else if compiler.facts[current].literal == TEXT_METHOD_EMPTY {
                    emit_text_empty_value(compiler, ir, current, is_test || compiler.test_build)
                } else if receiver_kind == TYPE_KIND_ASCII || receiver_kind == TYPE_KIND_TEXT || receiver_kind == TYPE_KIND_BYTES {
                    emit_text_method_call(source, files, tokens, tables, compiler, ir, current, file_index, is_test || compiler.test_build)
                } else if is_sum_type(compiler, receiver_ty) && receiver_kind != TYPE_KIND_ENUM {
                    emit_option_result_method(source, files, tokens, tables, compiler, ir, current, file_index)
                } else {
                    emit_sys_method(source, files, tokens, tables, compiler, ir, current, file_index)
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.Match && frame.phase == 30L {
            let matched_type = compiler.facts[frame.child0].ty
            let wildcard_arm = match_wildcard_ordinal(tables, compiler, frame.cursor, frame.auxiliary, current)
            let default_arm = if wildcard_arm >= 0L { wildcard_arm } else { -1L }
            if is_sum_type(compiler, matched_type) {
                let source_kind = aggregate_source_kind(tables, compiler, frame.child0)
                let source_node = aggregate_source_id(tables, compiler, frame.child0)
                let source_location = aggregate_source_location(compiler, source_kind, source_node)
                let tag_address = enum_temporary_address(current, MAX_TREE_NODES)
                emit_layout_address(compiler, ir, tag_address, source_location)
                ir_write_ascii(compiler, ir, "  %match.tag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address); ir_write_ascii(compiler, ir, ", align 1\n  switch i32 %match.tag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %")
            } else {
                ir_write_ascii(compiler, ir, "  switch "); ir_write_ascii(compiler, ir, llvm_type_name(matched_type)); ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", label %")
            }
            if default_arm >= 0L { ir_write_ascii(compiler, ir, "match.arm."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, default_arm) }
            else { ir_write_ascii(compiler, ir, "match.invalid."); ir_write_number(compiler, ir, current) }
            ir_write_ascii(compiler, ir, " [\n")
            var scan = frame.cursor
            var ordinal = frame.auxiliary
            for arm_step in 0L..tables.nodes[current].subtree {
                if scan < 0L { break }
                let pattern = compiler.child_first[scan]
                if pattern >= 0L && tables.nodes[pattern].kind != NodeKind.WildcardPattern {
                    let fact = compiler.facts[pattern]
                    ir_write_ascii(compiler, ir, "    "); ir_write_ascii(compiler, ir, llvm_type_name(matched_type)); ir_push_byte(compiler, ir, 32)
                    if matched_type == TY_BOOL { if fact.literal == 1L { ir_write_ascii(compiler, ir, "true") } else { ir_write_ascii(compiler, ir, "false") } }
                    else { ir_write_number(compiler, ir, fact.literal) }
                    ir_write_ascii(compiler, ir, ", label %match.arm."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, ordinal); ir_push_byte(compiler, ir, 10)
                }
                scan = compiler.child_next[scan]
                ordinal += 1L
            }
            ir_write_ascii(compiler, ir, "  ]\n")
            if default_arm < 0L {
                ir_write_ascii(compiler, ir, "match.invalid."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  unreachable\n")
            }
            frame.phase = 32L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Match && frame.phase == 31L {
            let arm = frame.child1
            let body = frame.child2
            if compiler.facts[body].ty != TY_NEVER {
                let result_ty = compiler.facts[current].ty
                let tail = if (tables.nodes[body].flags & FLAG_HAS_TAIL) != 0L { node_last_child(tables, compiler, body) } else { -1L }
                if is_aggregate_type(compiler, result_ty) && tail >= 0L {
                    let source_kind = aggregate_source_kind(tables, compiler, tail)
                    let source_node = aggregate_source_id(tables, compiler, tail)
                    emit_aggregate_copy(compiler, ir, result_ty, aggregate_destination_location(compiler, 0L, current), aggregate_source_location(compiler, source_kind, source_node))
                }
                emit_region_scope_exit(tables, compiler, ir, arm)
                ir_write_ascii(compiler, ir, "  br label %match.arm.cont."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, frame.auxiliary); ir_push_byte(compiler, ir, 10)
                ir_write_ascii(compiler, ir, "match.arm.cont."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, frame.auxiliary); ir_write_ascii(compiler, ir, ":\n  br label %match.end."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 10)
            }
            frame.auxiliary += 1L
            frame.phase = 32L
            compiler.expr_work[frame_index] = frame
            let _ = arm
        } else if kind == NodeKind.Match && frame.phase == 32L {
            if frame.cursor >= 0L {
                let arm = frame.cursor
                let ordinal = frame.auxiliary
                let pattern = compiler.child_first[arm]
                let body = if pattern >= 0L { compiler.child_next[pattern] } else { -1L }
                ir_write_ascii(compiler, ir, "match.arm."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, ordinal); ir_write_ascii(compiler, ir, ":\n")
                emit_region_scope_enter(files, tables, compiler, ir, arm, file_index)
                emit_match_payload_bindings(tables, compiler, ir, current, arm)
                frame.cursor = compiler.child_next[arm]
                frame.child1 = arm
                frame.child2 = body
                frame.phase = 31L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: body, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if compiler.facts[current].ty != TY_NEVER {
                ir_write_ascii(compiler, ir, "match.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
                let result_ty = compiler.facts[current].ty
                if result_ty != TY_UNIT && !is_aggregate_type(compiler, result_ty) {
                    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = phi "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty)); ir_push_byte(compiler, ir, 32)
                    var scan = if compiler.child_first[current] >= 0L { compiler.child_next[compiler.child_first[current]] } else { -1L }
                    var ordinal = 0L
                    var wrote = false
                    for arm_step in 0L..tables.nodes[current].subtree {
                        if scan < 0L { break }
                        let pattern = compiler.child_first[scan]
                        let body = if pattern >= 0L { compiler.child_next[pattern] } else { -1L }
                        if body >= 0L && compiler.facts[body].ty != TY_NEVER {
                            if wrote { ir_write_ascii(compiler, ir, ", ") }
                            let tail = if (tables.nodes[body].flags & FLAG_HAS_TAIL) != 0L { node_last_child(tables, compiler, body) } else { -1L }
                            ir_write_ascii(compiler, ir, "[ "); ir_write_value_ref(compiler, ir, tail); ir_write_ascii(compiler, ir, ", %match.arm.cont."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, ordinal); ir_write_ascii(compiler, ir, " ]")
                            wrote = true
                        }
                        scan = compiler.child_next[scan]
                        ordinal += 1L
                    }
                    ir_push_byte(compiler, ir, 10)
                }
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            } else {
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            }
        } else if kind == NodeKind.If && frame.phase == 1L {
            ir_write_ascii(compiler, ir, "  br i1 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", label %if.expr.then."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %if.expr.")
            if frame.child2 >= 0L { ir_write_ascii(compiler, ir, "else.") } else { ir_write_ascii(compiler, ir, "end.") }
            ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\nif.expr.then."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            frame.phase = 2L
            frame.cursor = 0L
            frame.reachable = true
            compiler.expr_work[frame_index] = frame
            compiler.expr_work.push(EmitExprFrame { node: frame.child1, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: current, reachable: true }).unwrap()
        } else if kind == NodeKind.If && frame.phase == 2L {
            if frame.child2 >= 0L {
                ir_write_ascii(compiler, ir, "if.expr.else."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
                frame.phase = 3L
                frame.reachable = true
                compiler.expr_work[frame_index] = frame
                if tables.nodes[frame.child2].kind == NodeKind.If {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child2, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: current, reachable: true }).unwrap()
                } else {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child2, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: current, reachable: true }).unwrap()
                }
            } else {
                ir_write_ascii(compiler, ir, "if.expr.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
                if frame.auxiliary >= 0L {
                    lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L)
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
                if compiler.expr_work.count() > base_depth {
                    let parent_index = compiler.expr_work.count() - 1L
                    var parent = compiler.expr_work[parent_index]
                    if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = true }
                    compiler.expr_work[parent_index] = parent
                }
            }
        } else if kind == NodeKind.If && frame.phase == 3L {
            let then_falls = frame.cursor == 1L
            let else_falls = frame.reachable
            let any_falls = then_falls || else_falls
            let result_ty = compiler.facts[current].ty
            if any_falls { ir_write_ascii(compiler, ir, "if.expr.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n") }
            if any_falls && result_ty != TY_UNIT && result_ty != TY_NEVER {
                if !is_aggregate_type(compiler, result_ty) {
                    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty)); ir_write_ascii(compiler, ir, ", ptr %if.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n")
                }
            }
            if any_falls && frame.auxiliary >= 0L {
                if result_ty != TY_UNIT && result_ty != TY_NEVER {
                    if is_aggregate_type(compiler, result_ty) {
                        emit_aggregate_copy(compiler, ir, result_ty, aggregate_destination_location(compiler, 0L, frame.auxiliary), aggregate_source_location(compiler, 0L, current))
                    } else {
                        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, current); ir_write_ascii(compiler, ir, ", ptr %if.slot."); ir_write_number(compiler, ir, frame.auxiliary); ir_write_ascii(compiler, ir, ", align 1\n")
                    }
                }
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L)
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
            if compiler.expr_work.count() > base_depth {
                let parent_index = compiler.expr_work.count() - 1L
                var parent = compiler.expr_work[parent_index]
                if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = any_falls }
                compiler.expr_work[parent_index] = parent
            }
        } else if kind == NodeKind.Block && frame.phase == 10L {
            if !frame.reachable {
                match compiler.expr_work.pop() { some(_) => (), none => () }
                if compiler.expr_work.count() > base_depth {
                    let parent_index = compiler.expr_work.count() - 1L
                    var parent = compiler.expr_work[parent_index]
                    if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 2L { parent.cursor = 0L }
                    else if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = false }
                    else { () }
                    compiler.expr_work[parent_index] = parent
                }
            } else if frame.child2 < 0L {
                frame.child2 = 1L
                compiler.expr_work[frame_index] = frame
                let active_function_id = if compiler.work.count() > 0L { compiler.work[compiler.work.count() - 1L].function_id } else { -1L }
                let falls = emit_function_body(source, files, tokens, tables, compiler, ir, current, file_index, active_function_id, return_ty, is_test, false, true)
                frame = compiler.expr_work[frame_index]
                frame.reachable = falls
                frame.cursor = if (tables.nodes[current].flags & FLAG_HAS_TAIL) != 0L { frame.child0 } else { -1L }
                compiler.expr_work[frame_index] = frame
            } else if frame.cursor >= 0L && (frame.cursor != frame.child0 || (tables.nodes[current].flags & FLAG_HAS_TAIL) == 0L) {
                let statement = frame.cursor
                frame.cursor = compiler.child_next[statement]
                if tables.nodes[statement].kind == NodeKind.Let {
                    var value = -1L
                    var child = compiler.child_first[statement]
                    for child_step in 0L..tables.nodes[statement].subtree {
                        if child < 0L { break }
                        if tables.nodes[child].kind != NodeKind.Annotation { value = child }
                        child = compiler.child_next[child]
                    }
                    frame.child1 = statement
                    frame.child2 = value
                    frame.phase = 12L
                    compiler.expr_work[frame_index] = frame
                    compiler.expr_work.push(EmitExprFrame { node: value, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                } else if tables.nodes[statement].kind == NodeKind.Assign {
                    let target = compiler.child_first[statement]
                    frame.child1 = statement
                    frame.child2 = compiler.child_next[target]
                    frame.phase = 13L
                    compiler.expr_work[frame_index] = frame
                    if tables.nodes[target].kind == NodeKind.Field {
                        emit_field_path_value(tables, compiler, ir, target)
                    } else if binding_is_write_parameter(compiler, compiler.facts[target].binding) {
                        let binding = compiler.facts[target].binding
                        let parameter_type = compiler.facts[target].ty
                        let parameter_location = compiler_location(compiler, 3L, binding, 0L)
                        emit_layout_address(compiler, ir, target, parameter_location)
                        emit_load_scalar(compiler, ir, target, parameter_type)
                    } else { () }
                    compiler.expr_work.push(EmitExprFrame { node: frame.child2, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                } else if tables.nodes[statement].kind == NodeKind.ExpressionStatement {
                    let expression = compiler.child_first[statement]
                    if expression >= 0L {
                        frame.child1 = statement
                        frame.child2 = expression
                        frame.phase = 14L
                        compiler.expr_work[frame_index] = frame
                        compiler.expr_work.push(EmitExprFrame { node: expression, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                    } else { compiler.expr_work[frame_index] = frame }
                } else if tables.nodes[statement].kind == NodeKind.Expect {
                    let expression = compiler.child_first[statement]
                    frame.child1 = statement
                    frame.child2 = expression
                    frame.phase = 15L
                    compiler.expr_work[frame_index] = frame
                    compiler.expr_work.push(EmitExprFrame { node: expression, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                } else if tables.nodes[statement].kind == NodeKind.ReturnStatement {
                    let value = compiler.child_first[statement]
                    if value >= 0L {
                        frame.child1 = statement
                        frame.child2 = value
                        frame.phase = 16L
                        compiler.expr_work[frame_index] = frame
                        compiler.expr_work.push(EmitExprFrame { node: value, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                    } else {
                        if is_test { lower_scope_exit(compiler, ir, -1L, EXIT_TEST_FAILURE, 0L, 0L, TY_UNIT, -1L) }
                        else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, TY_UNIT, -1L) }
                        frame.reachable = false
                        frame.cursor = -1L
                        compiler.expr_work[frame_index] = frame
                    }
                } else if tables.nodes[statement].kind == NodeKind.BreakStatement || tables.nodes[statement].kind == NodeKind.ContinueStatement {
                    let loop = compiler.emit_loops[compiler.emit_loops.count() - 1L]
                    // E3a1 subsection
                    emit_region_loop_exit(tables, compiler, ir, loop.body, statement)
                    // E3a1 subsection end
                    let target_kind = if tables.nodes[loop.node].kind == NodeKind.While { 1L } else { 0L }
                    if tables.nodes[statement].kind == NodeKind.BreakStatement { lower_scope_exit(compiler, ir, -1L, EXIT_BREAK, target_kind, loop.node, TY_UNIT, -1L) }
                    else { lower_scope_exit(compiler, ir, -1L, EXIT_CONTINUE, target_kind, loop.node, TY_UNIT, -1L) }
                    frame.reachable = false
                    frame.cursor = -1L
                    compiler.expr_work[frame_index] = frame
                } else { compiler.expr_work[frame_index] = frame }
            } else if frame.child0 >= 0L && (tables.nodes[current].flags & FLAG_HAS_TAIL) != 0L {
                frame.phase = 11L
                frame.child1 = frame.child0
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                // E3a1 subsection
                emit_region_scope_exit(tables, compiler, ir, current)
                if frame.auxiliary >= 0L {
                    lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L)
                }
                // E3a1 subsection end
                match compiler.expr_work.pop() { some(_) => (), none => () }
                if compiler.expr_work.count() > base_depth {
                    let parent_index = compiler.expr_work.count() - 1L
                    var parent = compiler.expr_work[parent_index]
                    if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 2L { parent.cursor = if frame.reachable { 1L } else { 0L } }
                    else if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = frame.reachable }
                    else { () }
                    compiler.expr_work[parent_index] = parent
                }
            }
        } else if kind == NodeKind.Block && frame.phase == 11L {
            if compiler.facts[frame.child1].ty == TY_NEVER {
                frame.reachable = false
            } else if frame.auxiliary >= 0L && compiler.facts[frame.child1].ty != TY_UNIT &&
                (compiler.facts[frame.child1].flags & FACT_PROVEN_SUCCESS) == 0L {
                let parent = frame.auxiliary
                let tail_ty = compiler.facts[frame.child1].ty
                if is_aggregate_type(compiler, tail_ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, frame.child1)
                    let source_node = aggregate_source_id(tables, compiler, frame.child1)
                    emit_aggregate_copy(compiler, ir, tail_ty, aggregate_destination_location(compiler, 0L, parent), aggregate_source_location(compiler, source_kind, source_node))
                } else {
                    ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(tail_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, frame.child1); ir_write_ascii(compiler, ir, ", ptr %if.slot."); ir_write_number(compiler, ir, parent); ir_write_ascii(compiler, ir, ", align 1\n")
                }
            } else { () }
            // E3a1 subsection
            if frame.reachable { emit_region_scope_exit(tables, compiler, ir, current) }
            if frame.reachable && frame.auxiliary >= 0L {
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L)
            }
            // E3a1 subsection end
            match compiler.expr_work.pop() { some(_) => (), none => () }
            if compiler.expr_work.count() > base_depth {
                let parent_index = compiler.expr_work.count() - 1L
                var parent = compiler.expr_work[parent_index]
                if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 2L { parent.cursor = if frame.reachable { 1L } else { 0L } }
                else if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = frame.reachable }
                else { () }
                compiler.expr_work[parent_index] = parent
            }
        } else if kind == NodeKind.Block && frame.phase == 12L {
            let statement = frame.child1
            let value = frame.child2
            let binding = compiler.facts[statement].binding
            let ty = compiler.bindings[binding].ty
            if is_aggregate_type(compiler, ty) {
                let source_kind = aggregate_source_kind(tables, compiler, value)
                let source_node = aggregate_source_id(tables, compiler, value)
                emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 1L, binding), aggregate_source_location(compiler, source_kind, source_node))
            } else if ty == TY_BOOL {
                ir_write_ascii(compiler, ir, "  %block.bool."); ir_write_number(compiler, ir, statement); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %block.bool."); ir_write_number(compiler, ir, statement); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
            } else if ty != TY_UNIT {
                ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
            } else { () }
            frame.phase = 10L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Block && frame.phase == 13L {
            let statement = frame.child1
            let value = frame.child2
            let target = compiler.child_first[statement]
            let binding = compiler.facts[target].binding
            let ty = compiler.facts[target].ty
            let op = tables.nodes[statement].flags
            if op == 0L {
                if is_aggregate_type(compiler, ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, value)
                    let source_node = aggregate_source_id(tables, compiler, value)
                    let destination = assignment_destination(tables, compiler, ir, target, ty, binding)
                    emit_aggregate_copy(compiler, ir, ty, destination, aggregate_source_location(compiler, source_kind, source_node))
                } else if ty == TY_BOOL {
                    if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, binding) || binding_is_view(compiler, binding) { emit_store_scalar_to_place(tables, compiler, ir, target, ty, value) }
                    else { ir_write_ascii(compiler, ir, "  %block.bool."); ir_write_number(compiler, ir, statement); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %block.bool."); ir_write_number(compiler, ir, statement); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
                } else if ty != TY_UNIT {
                    if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, binding) || binding_is_view(compiler, binding) { emit_store_scalar_to_place(tables, compiler, ir, target, ty, value) }
                    else {
                        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                    }
                } else { () }
            } else {
                emit_compound_assignment(files, tables, compiler, ir, statement, file_index, target, binding, value, ty, op)
            }
            frame.phase = 10L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Block && frame.phase == 14L {
            frame.phase = 10L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Block && frame.phase == 15L {
            emit_expect_after_expression(source, files, tokens, tables, compiler, ir, frame.child1, file_index, frame.child2)
            frame.phase = 10L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Block && frame.phase == 16L {
            if is_aggregate_type(compiler, return_ty) {
                let source_kind = aggregate_source_kind(tables, compiler, frame.child2)
                let source_node = aggregate_source_id(tables, compiler, frame.child2)
                emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(compiler, 2L, 0L), aggregate_source_location(compiler, source_kind, source_node))
                lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L)
            } else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN_VALUE, 0L, 0L, return_ty, frame.child2) }
            frame.reachable = false
            frame.cursor = -1L
            frame.phase = 10L
            compiler.expr_work[frame_index] = frame
        } else {
            match compiler.expr_work.pop() { some(_) => (), none => () }
        }
    }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_expect_after_expression(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    expression: long,
) {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].start, compiler)
    let start = tables.nodes[node].start
    let end = tables.nodes[node].end
    let length = end - start + 1L
    ir_write_ascii(compiler, ir, "  br i1 ")
    ir_write_value_ref(compiler, ir, expression)
    ir_write_ascii(compiler, ir, ", label %expect.pass.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %expect.fail.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nexpect.fail.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n")
    if tables.nodes[expression].kind == NodeKind.Binary && tables.nodes[expression].flags >= 8L && tables.nodes[expression].flags <= 13L {
        let left_node = compiler.child_first[expression]
        let right_node = compiler.child_next[left_node]
        let operand_ty = compiler.facts[left_node].ty
        if is_aggregate_type(compiler, operand_ty) {
            let left_location = if region_node_needs_snapshot(tables, compiler, left_node) {
                compiler_location(compiler, 0L, left_node, 0L)
            } else {
                aggregate_source_location_for_node(tables, compiler, left_node)
            }
            let right_location = aggregate_source_location_for_node(tables, compiler, right_node)
            let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
            let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
            ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_expect_fail_header", "nlc_expect_fail_header"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 "); ir_write_number(compiler, ir, file_index); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds (["); ir_write_number(compiler, ir, length); ir_write_ascii(compiler, ir, " x i8], ptr @.nl.expect."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 "); ir_write_number(compiler, ir, length - 1L); ir_write_ascii(compiler, ir, ")\n")
            ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_expect_fail_left", "nlc_expect_fail_left"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  call void "); emit_type_helper_call_one(compiler, ir, operand_ty, HELPER_PRINT, left_location, left_pointer)
            ir_write_ascii(compiler, ir, "\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_newline", "nlc_print_newline"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_expect_fail_right", "nlc_expect_fail_right"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  call void "); emit_type_helper_call_one(compiler, ir, operand_ty, HELPER_PRINT, right_location, right_pointer); ir_write_ascii(compiler, ir, "\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_newline", "nlc_print_newline"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n")
        } else {
        if operand_ty == TY_INT || operand_ty == TY_BOOL || operand_ty == TY_BYTE {
            let extension = if operand_ty == TY_INT { "sext" } else { "zext" }
            ir_write_ascii(compiler, ir, "  %expect.left.")
            ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = ")
            ir_write_ascii(compiler, ir, extension)
            ir_write_ascii(compiler, ir, " ")
            ir_write_ascii(compiler, ir, llvm_type_name(operand_ty))
            ir_write_ascii(compiler, ir, " ")
            ir_write_value_ref(compiler, ir, left_node)
            ir_write_ascii(compiler, ir, " to i64\n  %expect.right.")
            ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = ")
            ir_write_ascii(compiler, ir, extension)
            ir_write_ascii(compiler, ir, " ")
            ir_write_ascii(compiler, ir, llvm_type_name(operand_ty))
            ir_write_ascii(compiler, ir, " ")
            ir_write_value_ref(compiler, ir, right_node)
            ir_write_ascii(compiler, ir, " to i64\n")
        }
        ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_expect_fail_compare", "nlc_expect_fail_compare"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 ")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.line)
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.col)
        ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, length)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.expect.")
        ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
        ir_write_number(compiler, ir, length - 1L)
        ir_write_ascii(compiler, ir, ", i64 ")
        if operand_ty == TY_LONG { ir_write_value_ref(compiler, ir, left_node) }
        else { ir_write_ascii(compiler, ir, "%expect.left."); ir_write_number(compiler, ir, node) }
        ir_write_ascii(compiler, ir, ", i64 ")
        if operand_ty == TY_LONG { ir_write_value_ref(compiler, ir, right_node) }
        else { ir_write_ascii(compiler, ir, "%expect.right."); ir_write_number(compiler, ir, node) }
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, if operand_ty == TY_BOOL { 1L } else { 0L })
        ir_write_ascii(compiler, ir, ")\n")
        }
    } else {
        ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_expect_fail_bool", "nlc_expect_fail_bool"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 ")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.line)
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.col)
        ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, length)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.expect.")
        ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
        ir_write_number(compiler, ir, length - 1L)
        ir_write_ascii(compiler, ir, ")\n")
    }
    lower_scope_exit(compiler, ir, -1L, EXIT_TEST_FAILURE, 0L, 0L, TY_UNIT, -1L)
    ir_write_ascii(compiler, ir, "expect.pass.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n")
}
// E3a1 end

recursive fn emit_expect_statement(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let expression = compiler.child_first[node]
    emit_expr_linear(source, files, tokens, tables, compiler, ir, expression, file_index, TY_UNIT, true)
    emit_expect_after_expression(source, files, tokens, tables, compiler, ir, node, file_index, expression)
}

// E3a1 begin: shared compiler integration.
recursive fn emit_function_body(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    body: long,
    file_index: long,
    function_id: long,
    return_ty: long,
    is_test: bool,
    function_root: bool,
    stop_before_tail: bool,
) -> bool {
    var base_depth = compiler.work.count()
    var body_falls = true
    if function_root {
        compiler.work.clear()
        compiler.emit_loops.clear()
        compiler.ir_terminated = false
        base_depth = 0L
    }
    compiler.work.push(CheckFrame { node: body, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[body], child0: node_last_child(tables, compiler, body), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
    for emit_step in 0L..MAX_PARSE_WORK {
        if compiler.work.count() <= base_depth { break }
        let frame_index = compiler.work.count() - 1L
        var frame = compiler.work[frame_index]
        if frame.phase == 100L {
            if frame.child2 == 1L { lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_END, frame.node, TY_UNIT, -1L) }
            if frame.child1 >= 0L {
                ir_write_ascii(compiler, ir, "if.else."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
                // E3a1 subsection
                if tables.nodes[frame.child1].kind == NodeKind.Block { emit_region_scope_enter(files, tables, compiler, ir, frame.child1, file_index) }
                // E3a1 subsection end
                frame.phase = 101L
                frame.auxiliary = 0L
                compiler.work[frame_index] = frame
                compiler.work.push(CheckFrame { node: frame.child1, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[frame.child1], child0: node_last_child(tables, compiler, frame.child1), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
            } else {
                ir_write_ascii(compiler, ir, "if.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
                match compiler.work.pop() { some(_) => (), none => () }
                let parent_index = compiler.work.count() - 1L
                var parent = compiler.work[parent_index]
                parent.reachable = true
                compiler.work[parent_index] = parent
            }
            continue
        }
        if frame.phase == 101L {
            let then_falls = frame.child2 == 1L
            let else_falls = frame.auxiliary == 1L
            if else_falls { lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_END, frame.node, TY_UNIT, -1L) }
            if then_falls || else_falls {
                ir_write_ascii(compiler, ir, "if.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            }
            match compiler.work.pop() { some(_) => (), none => () }
            let parent_index = compiler.work.count() - 1L
            var parent = compiler.work[parent_index]
            parent.reachable = then_falls || else_falls
            compiler.work[parent_index] = parent
            continue
        }
        if frame.phase == 200L {
            if frame.auxiliary == 1L {
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_FOR_INCREMENT, frame.node, TY_UNIT, -1L)
            }
            let binding = frame.child1
            let ty = compiler.bindings[binding].ty
            ir_write_ascii(compiler, ir, "for.increment."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            ir_write_ascii(compiler, ir, "  %for.current."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
            let is_inclusive = (tables.nodes[frame.node].flags & FLAG_INCLUSIVE) != 0L
            if is_inclusive {
                ir_write_ascii(compiler, ir, "  %for.last."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %for.current."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, "\n  br i1 %for.last."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", label %for.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", label %for.increment.value."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, "\nfor.increment.value."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            }
            ir_write_ascii(compiler, ir, "  %for.next."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, " = add "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %for.current."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", 1\n  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %for.next."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n  br label %for.cond."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, "\nfor.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            match compiler.emit_loops.pop() { some(_) => (), none => () }
            match compiler.work.pop() { some(_) => (), none => () }
            continue
        }
        if frame.phase == 210L {
            if frame.auxiliary == 1L {
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_FOR_INCREMENT, frame.node, TY_UNIT, -1L)
            }
            ir_write_ascii(compiler, ir, "for.increment."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n  %for.each.next."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, " = add i64 %for.each.current."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", 1\n  store i64 %for.each.next."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", ptr %for.each.index."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", align 8\n  br label %for.cond."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, "\nfor.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            match compiler.emit_loops.pop() { some(_) => (), none => () }
            match compiler.work.pop() { some(_) => (), none => () }
            continue
        }
        if frame.phase == 220L {
            if frame.auxiliary == 1L {
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_WHILE_STEP, frame.node, TY_UNIT, -1L)
            }
            ir_write_ascii(compiler, ir, "while.step."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            if compiler.step_budget_main >= 0L {
                ir_write_ascii(compiler, ir, "  %while.steps.within."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, " = call i1 @nl_core_nl_context_step_budget_take(ptr %nl.ctx)\n  br i1 %while.steps.within."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", label %while.cond."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", label %while.fail."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, "\nwhile.fail."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 23, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + tables.nodes[frame.node].start, compiler).line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + tables.nodes[frame.node].start, compiler).col); ir_write_ascii(compiler, ir, ")\n  unreachable\n")
            } else { ir_write_ascii(compiler, ir, "  br label %while.cond."); ir_write_number(compiler, ir, frame.node); ir_push_byte(compiler, ir, 10) }
            ir_write_ascii(compiler, ir, "while.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            match compiler.emit_loops.pop() { some(_) => (), none => () }
            match compiler.work.pop() { some(_) => (), none => () }
            continue
        }
        if !frame.reachable {
            frame.cursor = -1L
            compiler.work[frame_index] = frame
        }
        if frame.cursor < 0L {
            // E3a1 subsection
            if frame.node != body && frame.reachable {
                emit_region_scope_exit(tables, compiler, ir, frame.node)
            }
            // E3a1 subsection end
            if function_root && frame.node == body && frame.reachable {
                lower_scope_exit(compiler, ir, -1L, EXIT_FALLTHROUGH, if is_test { 1L } else { 0L }, 0L, return_ty, -1L)
            }
            if frame.node == body { body_falls = frame.reachable }
            match compiler.work.pop() { some(_) => (), none => () }
            if compiler.work.count() > base_depth {
                let parent_index = compiler.work.count() - 1L
                var parent = compiler.work[parent_index]
                if parent.phase == 100L { parent.child2 = if frame.reachable { 1L } else { 0L } }
                else if parent.phase == 101L { parent.auxiliary = if frame.reachable { 1L } else { 0L } }
                else if parent.phase == 200L || parent.phase == 210L || parent.phase == 220L { parent.auxiliary = if frame.reachable { 1L } else { 0L } }
                else if !frame.reachable { parent.reachable = false }
                else { () }
                compiler.work[parent_index] = parent
            }
            continue
        }
        let child = frame.cursor
        frame.cursor = compiler.child_next[child]
        compiler.work[frame_index] = frame
        if stop_before_tail && frame.node == body && child == frame.child0 &&
            (tables.nodes[body].flags & FLAG_HAS_TAIL) != 0L {
            compiler.work[frame_index].cursor = -1L
            continue
        }
        let is_statement = tables.nodes[child].kind == NodeKind.Let || tables.nodes[child].kind == NodeKind.Assign || tables.nodes[child].kind == NodeKind.ExpressionStatement || tables.nodes[child].kind == NodeKind.Discard || tables.nodes[child].kind == NodeKind.Spawn || tables.nodes[child].kind == NodeKind.ReturnStatement || tables.nodes[child].kind == NodeKind.For || tables.nodes[child].kind == NodeKind.ForEach || tables.nodes[child].kind == NodeKind.While || tables.nodes[child].kind == NodeKind.Expect || tables.nodes[child].kind == NodeKind.BreakStatement || tables.nodes[child].kind == NodeKind.ContinueStatement || tables.nodes[child].kind == NodeKind.Block
        if !is_statement {
            let redirect_return = function_root && frame.node == body && child == frame.child0 &&
                (tables.nodes[body].flags & FLAG_HAS_TAIL) != 0L && is_aggregate_type(compiler, return_ty)
            let saved_destination_node = compiler.emit_destination_node
            let saved_destination_kind = compiler.emit_destination_kind
            let saved_destination_anchor = compiler.emit_destination_anchor
            if redirect_return {
                compiler.emit_destination_node = child
                compiler.emit_destination_kind = 2L
                compiler.emit_destination_anchor = -1L
            }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, child, file_index, return_ty, is_test)
            if redirect_return {
                compiler.emit_destination_node = saved_destination_node
                compiler.emit_destination_kind = saved_destination_kind
                compiler.emit_destination_anchor = saved_destination_anchor
            }
            if function_root && frame.node == body {
                if (compiler.facts[child].flags & FACT_FALLS_THROUGH) != 0L {
                    if is_test { lower_scope_exit(compiler, ir, -1L, EXIT_TEST_SUCCESS, 0L, 0L, TY_UNIT, -1L) }
                    else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
                    else if is_aggregate_type(compiler, return_ty) {
                        let source_kind = aggregate_source_kind(tables, compiler, child)
                        let source_node = aggregate_source_id(tables, compiler, child)
                        if !redirect_return {
                            emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(compiler, 2L, 0L), aggregate_source_location(compiler, source_kind, source_node))
                        }
                        lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L)
                    }
                    else {
                        lower_scope_exit(compiler, ir, -1L, EXIT_RETURN_VALUE, 0L, 0L, return_ty, child)
                    }
                }
                frame.reachable = false
                compiler.work[frame_index] = frame
            }
            continue
        }
        let kind = tables.nodes[child].kind
        if kind == NodeKind.Let {
            var value = -1L
            var sub = compiler.child_first[child]
            for sub_step in 0L..tables.nodes[child].subtree {
                if sub < 0L { break }
                if tables.nodes[sub].kind != NodeKind.Annotation { value = sub }
                sub = compiler.child_next[sub]
            }
            let binding = compiler.facts[child].binding
            let ty = compiler.bindings[binding].ty
            let redirect_value = is_aggregate_type(compiler, ty)
            let saved_destination_node = compiler.emit_destination_node
            let saved_destination_kind = compiler.emit_destination_kind
            let saved_destination_anchor = compiler.emit_destination_anchor
            if redirect_value {
                compiler.emit_destination_node = value
                compiler.emit_destination_kind = 1L
                compiler.emit_destination_anchor = binding
            }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, value, file_index, return_ty, is_test)
            if redirect_value {
                compiler.emit_destination_node = saved_destination_node
                compiler.emit_destination_kind = saved_destination_kind
                compiler.emit_destination_anchor = saved_destination_anchor
            }
            if (compiler.facts[value].flags & FACT_FALLS_THROUGH) == 0L {
                frame.reachable = false
                frame.cursor = -1L
                compiler.work[frame_index] = frame
            } else {
                if is_aggregate_type(compiler, ty) {
                    if !redirect_value {
                        let source_kind = aggregate_source_kind(tables, compiler, value)
                        let source_node = aggregate_source_id(tables, compiler, value)
                        emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 1L, binding), aggregate_source_location(compiler, source_kind, source_node))
                    }
                } else if ty == TY_BOOL {
                    ir_write_ascii(compiler, ir, "  %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                } else if ty != TY_UNIT {
                    ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                } else { () }
            }
        } else if kind == NodeKind.Assign {
            let target = compiler.child_first[child]
            let value = compiler.child_next[target]
            if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, compiler.facts[target].binding) || binding_is_view(compiler, compiler.facts[target].binding) { emit_expr_linear(source, files, tokens, tables, compiler, ir, target, file_index, return_ty, is_test) }
            let in_place = assign_builds_in_place(tables, compiler, child)
            let saved_destination_node = compiler.emit_destination_node
            let saved_destination_kind = compiler.emit_destination_kind
            let saved_destination_anchor = compiler.emit_destination_anchor
            if in_place {
                compiler.emit_destination_node = value
                compiler.emit_destination_kind = 1L
                compiler.emit_destination_anchor = compiler.facts[target].binding
            }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, value, file_index, return_ty, is_test)
            if in_place {
                compiler.emit_destination_node = saved_destination_node
                compiler.emit_destination_kind = saved_destination_kind
                compiler.emit_destination_anchor = saved_destination_anchor
            }
            let binding = compiler.facts[target].binding
            let ty = compiler.facts[target].ty
            let op = tables.nodes[child].flags
            if op == 0L {
                if is_aggregate_type(compiler, ty) {
                    if !in_place {
                        let destination = assignment_destination(tables, compiler, ir, target, ty, binding)
                        emit_aggregate_copy_to_place(tables, compiler, ir, ty, target, value, destination)
                    }
                } else if ty == TY_BOOL {
                    if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, binding) || binding_is_view(compiler, binding) { emit_store_scalar_to_place(tables, compiler, ir, target, ty, value) }
                    else { ir_write_ascii(compiler, ir, "  %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
                } else if ty != TY_UNIT {
                    if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, binding) || binding_is_view(compiler, binding) { emit_store_scalar_to_place(tables, compiler, ir, target, ty, value) }
                    else {
                        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                    }
                } else { () }
            } else {
                emit_compound_assignment(files, tables, compiler, ir, child, file_index, target, binding, value, ty, op)
            }
        } else if kind == NodeKind.Spawn {
            emit_spawn_statement(source, files, tokens, tables, compiler, ir, child, file_index, return_ty, is_test)
        } else if kind == NodeKind.Discard {
            let expression = compiler.child_first[child]
            emit_expr_linear(source, files, tokens, tables, compiler, ir, expression, file_index, return_ty, is_test)
        } else if kind == NodeKind.ExpressionStatement {
            let expression = compiler.child_first[child]
            if expression >= 0L {
                emit_expr_linear(source, files, tokens, tables, compiler, ir, expression, file_index, return_ty, is_test)
                if (compiler.facts[expression].flags & FACT_FALLS_THROUGH) == 0L {
                    frame.reachable = false
                    frame.cursor = -1L
                    compiler.work[frame_index] = frame
                }
            }
        } else if kind == NodeKind.ReturnStatement {
            let value = compiler.child_first[child]
            if value >= 0L {
                let redirect_return = is_aggregate_type(compiler, return_ty)
                let saved_destination_node = compiler.emit_destination_node
                let saved_destination_kind = compiler.emit_destination_kind
                let saved_destination_anchor = compiler.emit_destination_anchor
                if redirect_return {
                    compiler.emit_destination_node = value
                    compiler.emit_destination_kind = 2L
                    compiler.emit_destination_anchor = -1L
                }
                emit_expr_linear(source, files, tokens, tables, compiler, ir, value, file_index, return_ty, is_test)
                if redirect_return {
                    compiler.emit_destination_node = saved_destination_node
                    compiler.emit_destination_kind = saved_destination_kind
                    compiler.emit_destination_anchor = saved_destination_anchor
                }
                if (compiler.facts[value].flags & FACT_FALLS_THROUGH) == 0L {
                    frame.reachable = false
                    frame.cursor = -1L
                    compiler.work[frame_index] = frame
                } else if is_aggregate_type(compiler, return_ty) {
                    if !redirect_return {
                        let source_kind = aggregate_source_kind(tables, compiler, value)
                        let source_node = aggregate_source_id(tables, compiler, value)
                        emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(compiler, 2L, 0L), aggregate_source_location(compiler, source_kind, source_node))
                    }
                    lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L)
                } else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
                else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN_VALUE, 0L, 0L, return_ty, value) }
            } else if is_test { lower_scope_exit(compiler, ir, -1L, EXIT_TEST_FAILURE, 0L, 0L, TY_UNIT, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
            frame.reachable = false
            compiler.work[frame_index] = frame
        } else if kind == NodeKind.Block {
            // E3a1 subsection
            emit_region_scope_enter(files, tables, compiler, ir, child, file_index)
            // E3a1 subsection end
            compiler.work.push(CheckFrame { node: child, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[child], child0: node_last_child(tables, compiler, child), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.Expect {
            emit_expect_statement(source, files, tokens, tables, compiler, ir, child, file_index)
        } else if kind == NodeKind.If || (kind == NodeKind.ExpressionStatement && compiler.child_first[child] >= 0L && tables.nodes[compiler.child_first[child]].kind == NodeKind.If) {
            let if_node = if kind == NodeKind.If { child } else { compiler.child_first[child] }
            let condition = compiler.child_first[if_node]
            let then_block = compiler.child_next[condition]
            let else_block = compiler.child_next[then_block]
            emit_expr_linear(source, files, tokens, tables, compiler, ir, condition, file_index, return_ty, is_test)
            ir_write_ascii(compiler, ir, "  br i1 "); ir_write_value_ref(compiler, ir, condition); ir_write_ascii(compiler, ir, ", label %if.then."); ir_write_number(compiler, ir, if_node); ir_write_ascii(compiler, ir, ", label %")
            if else_block >= 0L { ir_write_ascii(compiler, ir, "if.else."); ir_write_number(compiler, ir, if_node) }
            else { ir_write_ascii(compiler, ir, "if.end."); ir_write_number(compiler, ir, if_node) }
            ir_write_ascii(compiler, ir, "\nif.then."); ir_write_number(compiler, ir, if_node); ir_write_ascii(compiler, ir, ":\n")
            // E3a1 subsection
            if then_block >= 0L && tables.nodes[then_block].kind == NodeKind.Block { emit_region_scope_enter(files, tables, compiler, ir, then_block, file_index) }
            // E3a1 subsection end
            compiler.work.push(CheckFrame { node: if_node, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 100L, cursor: -1L, child0: then_block, child1: else_block, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
            compiler.work.push(CheckFrame { node: then_block, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[then_block], child0: node_last_child(tables, compiler, then_block), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.For {
            var start = -1L
            var finish = -1L
            var loop_body = -1L
            var bound_index = 0L
            var loop_child = compiler.child_first[child]
            for child_step in 0L..tables.nodes[child].subtree {
                if loop_child < 0L { break }
                if tables.nodes[loop_child].kind == NodeKind.Block { loop_body = loop_child }
                else if tables.nodes[loop_child].kind != NodeKind.Annotation {
                    if bound_index == 0L { start = loop_child; bound_index += 1L }
                    else { finish = loop_child; bound_index += 1L }
                } else { () }
                loop_child = compiler.child_next[loop_child]
            }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, start, file_index, return_ty, is_test)
            emit_expr_linear(source, files, tokens, tables, compiler, ir, finish, file_index, return_ty, is_test)
            let binding = binding_for_node(compiler, child)
            let ty = compiler.bindings[binding].ty
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, start); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n  br label %for.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nfor.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n  %for.test."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n  %for.more."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = icmp s")
            if (tables.nodes[child].flags & FLAG_INCLUSIVE) != 0L { ir_write_ascii(compiler, ir, "le ") } else { ir_write_ascii(compiler, ir, "lt ") }
            ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %for.test."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, finish); ir_write_ascii(compiler, ir, "\n  br i1 %for.more."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", label %for.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", label %for.end."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nfor.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n")
            // E3a1 subsection
            compiler.emit_loops.push(EmitLoop { node: child, body: loop_body }).unwrap()
            if loop_body >= 0L && tables.nodes[loop_body].kind == NodeKind.Block { emit_region_scope_enter(files, tables, compiler, ir, loop_body, file_index) }
            // E3a1 subsection end
            compiler.work.push(CheckFrame { node: child, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 200L, cursor: -1L, child0: finish, child1: binding, child2: -1L, result_ty: ty, auxiliary: 1L, reachable: true }).unwrap()
            compiler.work.push(CheckFrame { node: loop_body, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[loop_body], child0: node_last_child(tables, compiler, loop_body), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.ForEach {
            let collection = compiler.child_first[child]
            let loop_body = if collection >= 0L { compiler.child_next[collection] } else { -1L }
            if collection < 0L || loop_body < 0L { compiler.ir_overflow = true; continue }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, collection, file_index, return_ty, is_test)
            let collection_type = compiler.facts[collection].ty
            let collection_kind = type_kind(compiler, collection_type)
            let capacity = collection_capacity(compiler, collection_type)
            let location = collection_value_location(tables, compiler, collection)
            let pointer = emit_location_pointer_materialization(compiler, ir, location)
            if collection_kind_is_list(collection_kind) {
                ir_write_ascii(compiler, ir, "  %for.each.count.ptr."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", i64 0\n  %for.each.count."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = load i64, ptr %for.each.count.ptr."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", align 1\n")
            } else if collection_kind == TYPE_KIND_ASCII || collection_kind == TYPE_KIND_BYTES {
                ir_write_ascii(compiler, ir, "  %for.each.count.ptr."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", i64 0\n  %for.each.count."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = load i64, ptr %for.each.count.ptr."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", align 1\n")
            } else {
                ir_write_ascii(compiler, ir, "  %for.each.count."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_number(compiler, ir, capacity); ir_push_byte(compiler, ir, 10)
            }
            ir_write_ascii(compiler, ir, "  store i64 0, ptr %for.each.index."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", align 8\n  br label %for.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nfor.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n  %for.each.current."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = load i64, ptr %for.each.index."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", align 8\n  %for.each.more."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = icmp ult i64 %for.each.current."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", %for.each.count."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\n  br i1 %for.each.more."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", label %for.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", label %for.end."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nfor.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n")
            let view_binding = compiler.facts[child].binding
            let view_scope = compiler.bindings[view_binding].scope
            if tables.nodes[child].aux > 0L {
                let index_token = tables.extra[tables.nodes[child].extra]
                let index_binding = find_binding_in_scope(compiler, view_scope, compiler.token_name_ids[index_token])
                if index_binding >= 0L { ir_write_ascii(compiler, ir, "  store i64 %for.each.current."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, index_binding); ir_write_ascii(compiler, ir, ", align 8\n") }
            }
            compiler.emit_loops.push(EmitLoop { node: child, body: loop_body }).unwrap()
            if tables.nodes[loop_body].kind == NodeKind.Block { emit_region_scope_enter(files, tables, compiler, ir, loop_body, file_index) }
            compiler.work.push(CheckFrame { node: child, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 210L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 1L, reachable: true }).unwrap()
            compiler.work.push(CheckFrame { node: loop_body, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[loop_body], child0: node_last_child(tables, compiler, loop_body), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.While {
            let condition = compiler.child_first[child]
            let loop_body = if condition >= 0L { compiler.child_next[condition] } else { -1L }
            if condition < 0L || loop_body < 0L { compiler.ir_overflow = true; continue }
            ir_write_ascii(compiler, ir, "  br label %while.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nwhile.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n")
            emit_expr_linear(source, files, tokens, tables, compiler, ir, condition, file_index, return_ty, is_test)
            ir_write_ascii(compiler, ir, "  br i1 "); ir_write_value_ref(compiler, ir, condition); ir_write_ascii(compiler, ir, ", label %while.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", label %while.end."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nwhile.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n")
            compiler.emit_loops.push(EmitLoop { node: child, body: loop_body }).unwrap()
            if tables.nodes[loop_body].kind == NodeKind.Block { emit_region_scope_enter(files, tables, compiler, ir, loop_body, file_index) }
            compiler.work.push(CheckFrame { node: child, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 220L, cursor: -1L, child0: condition, child1: loop_body, child2: -1L, result_ty: -1L, auxiliary: 1L, reachable: true }).unwrap()
            compiler.work.push(CheckFrame { node: loop_body, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[loop_body], child0: node_last_child(tables, compiler, loop_body), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.BreakStatement || kind == NodeKind.ContinueStatement {
            let loop = compiler.emit_loops[compiler.emit_loops.count() - 1L]
            // E3a1 subsection
            emit_region_loop_exit(tables, compiler, ir, loop.body, child)
            // E3a1 subsection end
            let target_kind = if tables.nodes[loop.node].kind == NodeKind.While { 1L } else { 0L }
            if kind == NodeKind.BreakStatement { lower_scope_exit(compiler, ir, -1L, EXIT_BREAK, target_kind, loop.node, TY_UNIT, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_CONTINUE, target_kind, loop.node, TY_UNIT, -1L) }
            frame.reachable = false
            compiler.work[frame_index] = frame
        } else {
            compiler.internal_emit_error_kind = 1L
            compiler.internal_emit_error_node = child
            compiler.internal_emit_error_file = file_index
            compiler.ir_overflow = true
        }
    }
    body_falls
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_function_definition(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    function_id: long,
) {
    let function = compiler.functions[function_id]
    plan_function_regions(tables, compiler, function.body, function_id)
    if compiler.core_mode { ir_write_ascii(compiler, ir, "define internal ") }
    else { ir_write_ascii(compiler, ir, "define ") }
    if is_aggregate_type(compiler, function.result_ty) || function.result_ty == TY_UNIT || function.result_ty == TY_NEVER { ir_write_ascii(compiler, ir, "void") }
    else { ir_write_ascii(compiler, ir, llvm_type_name(function.result_ty)) }
    if compiler.core_mode {
        ir_push_byte(compiler, ir, 32)
        ir_write_core_function_symbol(source, files, tokens, compiler, ir, function, function_id)
        ir_push_byte(compiler, ir, 40)
    } else {
        ir_write_ascii(compiler, ir, " @nl_fn_")
        ir_write_number(compiler, ir, function_id)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top")
        if is_aggregate_type(compiler, function.result_ty) { ir_write_ascii(compiler, ir, ", "); emit_hidden_descriptor_parameter(compiler, ir) }
    }
    var wrote_parameter = !compiler.core_mode
    // E3a1 subsection: every context-taking core function receives its job context.
    if compiler.core_mode && core_function_has_context(source, tokens, files, function) {
        ir_write_ascii(compiler, ir, "ptr %nl.ctx")
        wrote_parameter = true
    }
    // E3a1 subsection end
    if compiler.core_mode && is_aggregate_type(compiler, function.result_ty) {
        if wrote_parameter { ir_write_ascii(compiler, ir, ", ") }
        emit_hidden_descriptor_parameter(compiler, ir)
        wrote_parameter = true
    }
    for parameter_index in 0L..function.param_count {
        let parameter = compiler.parameters[function.param_start + parameter_index]
        let binding = binding_for_node(compiler, parameter.node)
        if parameter.ty == TY_UNIT { continue }
        if wrote_parameter { ir_write_ascii(compiler, ir, ", ") }
        if is_aggregate_type(compiler, parameter.ty) || (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
            emit_location_parameter(compiler, ir, binding)
            wrote_parameter = true
            continue
        }
        ir_write_ascii(compiler, ir, llvm_type_name(parameter.ty)); ir_write_ascii(compiler, ir, " %arg."); ir_write_number(compiler, ir, binding)
        wrote_parameter = true
    }
    ir_write_ascii(compiler, ir, ")")
    if compiler.core_mode {
        if function.result_ty == TY_NEVER { ir_write_ascii(compiler, ir, " noreturn") }
        ir_write_ascii(compiler, ir, " nounwind")
        if files[function.file].name == b"memory.nl" { ir_write_ascii(compiler, ir, " \"no-builtins\"=\"true\"") }
    }
    ir_write_ascii(compiler, ir, " {\nentry:\n")
    emit_parameter_geometry_prologue(compiler, ir, function)
    if compiler.c_runtime {
        emit_parameter_pointer_prologue(compiler, ir, function)
        emit_parameter_length_prologue(compiler, ir, function)
    }
    // E3a1 subsection: context-free startup helpers must not capture a process
    // global. The null value only serves checked arithmetic's unreachable
    // fail edges; startup failures themselves use direct syscalls.
    if compiler.core_mode && !core_function_has_context(source, tokens, files, function) {
        ir_write_ascii(compiler, ir, "  %nl.ctx = inttoptr i64 0 to ptr\n")
    }
    // E3a1 subsection end
    let body_first = function.body - tables.nodes[function.body].subtree + 1L
    for node in 0L..tables.nodes.count() {
        if node < body_first || node > function.body { continue }
        emit_c_runtime_method_storage(source, files, tokens, tables, compiler, ir, node, function.file)
        if tables.nodes[node].kind == NodeKind.OptionalCall && compiler.facts[node].function >= 0L {
            let target = compiler.functions[compiler.facts[node].function]
            let receiver_parameter = compiler.parameters[target.param_start]
            let receiver_type = if parameter_uses_text_read_view(compiler, receiver_parameter) {
                sum_case_payload_type(compiler, compiler.facts[compiler.child_first[node]].ty, 0L, 0L)
            } else { receiver_parameter.ty }
            if receiver_type != TY_UNIT && is_aggregate_type(compiler, receiver_type) {
                let type_info = type_record(compiler, receiver_type)
                ir_write_ascii(compiler, ir, "  %optional.call.receiver.snapshot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, type_info.size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, type_info.align); ir_write_ascii(compiler, ir, "\n")
            }
        }
        if tables.nodes[node].kind == NodeKind.ForEach {
            ir_write_ascii(compiler, ir, "  %for.each.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n")
        }
        if tables.nodes[node].kind == NodeKind.Binary && (tables.nodes[node].flags == 14L || tables.nodes[node].flags == 15L) {
            ir_write_ascii(compiler, ir, "  %logic.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i1, align 1\n")
        }
        if tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 21L && compiler.facts[node].ty != TY_UNIT && !is_aggregate_type(compiler, compiler.facts[node].ty) {
            ir_write_ascii(compiler, ir, "  %coalesce.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if tables.nodes[node].kind == NodeKind.Call && token_is_word_at(source, tokens, files, function.file, tables.nodes[node].token, "fill") &&
            compiler.facts[node].function < 0L {
            ir_write_ascii(compiler, ir, "  %coll.fill.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n")
        }
        if tables.nodes[node].kind == NodeKind.If && compiler.facts[node].ty != TY_UNIT && compiler.facts[node].ty != TY_NEVER && !is_aggregate_type(compiler, compiler.facts[node].ty) {
            ir_write_ascii(compiler, ir, "  %if.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if (tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 4L) || (tables.nodes[node].kind == NodeKind.Assign && tables.nodes[node].flags == 5L) {
            let ty = if tables.nodes[node].kind == NodeKind.Binary { compiler.facts[node].ty } else { compiler.facts[compiler.child_first[node]].ty }
            ir_write_ascii(compiler, ir, "  %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if is_aggregate_type(compiler, compiler.facts[node].ty) && region_node_is_temporary(tables, compiler, node) && !region_has_slot(compiler, 0L, node) {
            let type_info = type_record(compiler, compiler.facts[node].ty)
            let size = type_info.size
            let alignment = type_info.align
            ir_write_ascii(compiler, ir, "  %agg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, alignment); ir_write_ascii(compiler, ir, "\n")
        }
    }
    for binding_id in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_id]
        if compiler.scopes[binding.scope].function_id == function_id && !binding_is_view(compiler, binding_id) && binding.ty != TY_UNIT && !(binding.parameter && (is_aggregate_type(compiler, binding.ty) || binding.mutable)) && !region_has_slot(compiler, 1L, binding_id) {
            ir_write_ascii(compiler, ir, "  %local.")
            ir_write_number(compiler, ir, binding_id)
            ir_write_ascii(compiler, ir, " = alloca ")
            if is_aggregate_type(compiler, binding.ty) {
            let type_info = type_record(compiler, binding.ty)
                ir_write_ascii(compiler, ir, "["); ir_write_number(compiler, ir, type_info.size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, type_info.align); ir_write_ascii(compiler, ir, "\n")
            } else {
                if binding.ty == TY_BOOL { ir_write_ascii(compiler, ir, "i8") } else { ir_write_ascii(compiler, ir, llvm_type_name(binding.ty)) }
                ir_write_ascii(compiler, ir, ", align 1\n")
            }
        }
    }
    for parameter_index in 0L..function.param_count {
        let parameter = compiler.parameters[function.param_start + parameter_index]
        if parameter.ty == TY_UNIT || is_aggregate_type(compiler, parameter.ty) || (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L { continue }
        let binding = binding_for_node(compiler, parameter.node)
        if parameter.ty == TY_BOOL {
            ir_write_ascii(compiler, ir, "  %arg.bool."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " = zext i1 %arg."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " to i8\n")
            ir_write_ascii(compiler, ir, "  store i8 %arg.bool."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
        } else {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(parameter.ty)); ir_write_ascii(compiler, ir, " %arg."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
        }
    }
    if !compiler.core_mode { emit_region_prologue(files, tables, compiler, ir, function.body, function.file) }
    compiler.memory_closure = compiler.core_mode && files[function.file].name == b"memory.nl"
    let _ = emit_function_body(source, files, tokens, tables, compiler, ir, function.body, function.file, function_id, function.result_ty, false, true, false)
    compiler.memory_closure = false
    ir_write_ascii(compiler, ir, "}\n\n")
    // E3a1 subsection: synthetic helpers emitted next do not inherit this frame's
    // region plan.
    if !compiler.core_mode { clear_function_regions(compiler) }
    // E3a1 subsection end
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_test_definition(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    test_index: long,
) {
    let test = compiler.tests[test_index]
    let function_id = compiler.functions.count() + test_index
    let scope_function_id = -1L - test_index
    plan_function_regions(tables, compiler, test.body, scope_function_id)
    ir_write_ascii(compiler, ir, "define i32 @nl_fn_")
    ir_write_number(compiler, ir, function_id)
    ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top) {\nentry:\n")
    let body_first = test.body - tables.nodes[test.body].subtree + 1L
    for node in 0L..tables.nodes.count() {
        if node < body_first || node > test.body { continue }
        emit_c_runtime_method_storage(source, files, tokens, tables, compiler, ir, node, test.file)
        if tables.nodes[node].kind == NodeKind.OptionalCall && compiler.facts[node].function >= 0L {
            let target = compiler.functions[compiler.facts[node].function]
            let receiver_parameter = compiler.parameters[target.param_start]
            let receiver_type = if parameter_uses_text_read_view(compiler, receiver_parameter) {
                sum_case_payload_type(compiler, compiler.facts[compiler.child_first[node]].ty, 0L, 0L)
            } else { receiver_parameter.ty }
            if receiver_type != TY_UNIT && is_aggregate_type(compiler, receiver_type) {
                let type_info = type_record(compiler, receiver_type)
                ir_write_ascii(compiler, ir, "  %optional.call.receiver.snapshot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, type_info.size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, type_info.align); ir_write_ascii(compiler, ir, "\n")
            }
        }
        if tables.nodes[node].kind == NodeKind.ForEach {
            ir_write_ascii(compiler, ir, "  %for.each.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n")
        }
        if tables.nodes[node].kind == NodeKind.Binary && (tables.nodes[node].flags == 14L || tables.nodes[node].flags == 15L) {
            ir_write_ascii(compiler, ir, "  %logic.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i1, align 1\n")
        }
        if tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 21L && compiler.facts[node].ty != TY_UNIT && !is_aggregate_type(compiler, compiler.facts[node].ty) {
            ir_write_ascii(compiler, ir, "  %coalesce.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if tables.nodes[node].kind == NodeKind.Call && token_is_word_at(source, tokens, files, test.file, tables.nodes[node].token, "fill") &&
            compiler.facts[node].function < 0L {
            ir_write_ascii(compiler, ir, "  %coll.fill.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n")
        }
        if tables.nodes[node].kind == NodeKind.If && compiler.facts[node].ty != TY_UNIT && compiler.facts[node].ty != TY_NEVER && !is_aggregate_type(compiler, compiler.facts[node].ty) {
            ir_write_ascii(compiler, ir, "  %if.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if (tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 4L) || (tables.nodes[node].kind == NodeKind.Assign && tables.nodes[node].flags == 5L) {
            let ty = if tables.nodes[node].kind == NodeKind.Binary { compiler.facts[node].ty } else { compiler.facts[compiler.child_first[node]].ty }
            ir_write_ascii(compiler, ir, "  %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if is_aggregate_type(compiler, compiler.facts[node].ty) && region_node_is_temporary(tables, compiler, node) && !region_has_slot(compiler, 0L, node) {
            let type_info = type_record(compiler, compiler.facts[node].ty)
            let size = type_info.size
            let alignment = type_info.align
            ir_write_ascii(compiler, ir, "  %agg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, alignment); ir_write_ascii(compiler, ir, "\n")
        }
    }
    for binding_id in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_id]
        if compiler.scopes[binding.scope].function_id == scope_function_id && !binding_is_view(compiler, binding_id) && binding.ty != TY_UNIT && !binding.parameter && !region_has_slot(compiler, 1L, binding_id) {
            ir_write_ascii(compiler, ir, "  %local.")
            ir_write_number(compiler, ir, binding_id)
            ir_write_ascii(compiler, ir, " = alloca ")
            if is_aggregate_type(compiler, binding.ty) {
                let type_info = type_record(compiler, binding.ty)
                ir_write_ascii(compiler, ir, "["); ir_write_number(compiler, ir, type_info.size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, type_info.align); ir_write_ascii(compiler, ir, "\n")
            } else {
                if binding.ty == TY_BOOL { ir_write_ascii(compiler, ir, "i8") } else { ir_write_ascii(compiler, ir, llvm_type_name(binding.ty)) }
                ir_write_ascii(compiler, ir, ", align 1\n")
            }
        }
    }
    emit_region_prologue(files, tables, compiler, ir, test.body, test.file)
    let _ = emit_function_body(source, files, tokens, tables, compiler, ir, test.body, test.file, scope_function_id, TY_UNIT, true, true, false)
    ir_write_ascii(compiler, ir, "}\n\n")
    // E3a1 subsection: keep test region offsets local to this emitted function.
    clear_function_regions(compiler)
    // E3a1 subsection end
}
// E3a1 end

fn struct_has_defaults(compiler: CompilerTables, type_index: long) -> bool {
    let ty = struct_record(compiler, type_index)
    for offset in 0L..ty.field_count {
        if compiler.struct_fields[ty.field_start + offset].default_node >= 0L { return true }
    }
    false
}

fn has_type_helper(compiler: CompilerTables, type_id: long, operation: long) -> bool {
    if type_id < 0L || type_id >= type_count(compiler) { return false }
    let bit = if operation == HELPER_COPY { 1L }
        else if operation == HELPER_EQUAL { 2L }
        else if operation == HELPER_PRINT { 4L }
        else if operation == HELPER_FILL { 8L }
        else if operation == HELPER_DEFAULT { 16L }
        else { 0L }
    let mask = type_helper_mask(compiler, type_id)
    bit != 0L && (mask / bit) % 2L == 1L
}


// min, max, abs and clamp lower to one LLVM intrinsic each, with no call into a library
// function. abs keeps the language's rule that abs of the minimum value fails (as a negation
// overflow), which also makes llvm.abs's poison-on-minimum flag safe. clamp fails when the
// lower bound is above the upper bound.
fn emit_numeric_builtin(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let recorded = compiler.facts[node].literal
    let narrow = recorded >= NUMERIC_BUILTIN_NARROW_TO_BYTE
    let kind = if narrow { recorded - NUMERIC_BUILTIN_NARROW_TO_BYTE } else { recorded }
    // A narrowed clamp is computed on its int operands; a byte value is held as an int in IR anyway.
    let ty = if narrow { TY_INT } else { compiler.facts[node].ty }
    let llvm_ty = llvm_type_name(ty)
    let first = compiler.child_first[node]
    let second = if first >= 0L { compiler.child_next[first] } else { -1L }
    let third = if second >= 0L { compiler.child_next[second] } else { -1L }
    if kind == NUMERIC_BUILTIN_MIN || kind == NUMERIC_BUILTIN_MAX {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call ")
        ir_write_ascii(compiler, ir, llvm_ty)
        ir_write_ascii(compiler, ir, if kind == NUMERIC_BUILTIN_MIN { " @llvm.smin." } else { " @llvm.smax." })
        ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " ")
        ir_write_value_ref(compiler, ir, first)
        ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " ")
        ir_write_value_ref(compiler, ir, second); ir_write_ascii(compiler, ir, ")\n")
    } else if kind == NUMERIC_BUILTIN_ABS {
        ir_write_ascii(compiler, ir, "  %ov.flag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq ")
        ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " ")
        ir_write_value_ref(compiler, ir, first)
        ir_write_ascii(compiler, ir, if ty == TY_INT { ", -2147483648\n" } else { ", -9223372036854775808\n" })
        emit_runtime_failure(files, tables, compiler, ir, node, file_index, if ty == TY_INT { 4L } else { 8L })
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call ")
        ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " @llvm.abs."); ir_write_ascii(compiler, ir, llvm_ty)
        ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " ")
        ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ", i1 true)\n")
    } else {
        ir_write_ascii(compiler, ir, "  %ov.flag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sgt ")
        ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " ")
        ir_write_value_ref(compiler, ir, second); ir_write_ascii(compiler, ir, ", ")
        ir_write_value_ref(compiler, ir, third); ir_write_ascii(compiler, ir, "\n")
        emit_runtime_failure(files, tables, compiler, ir, node, file_index, 21L)
        ir_write_ascii(compiler, ir, "  %clamp.low."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call ")
        ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " @llvm.smax."); ir_write_ascii(compiler, ir, llvm_ty)
        ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " ")
        ir_write_value_ref(compiler, ir, first)
        ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " ")
        ir_write_value_ref(compiler, ir, second); ir_write_ascii(compiler, ir, ")\n")
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call ")
        ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " @llvm.smin."); ir_write_ascii(compiler, ir, llvm_ty)
        ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " %clamp.low."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " ")
        ir_write_value_ref(compiler, ir, third); ir_write_ascii(compiler, ir, ")\n")
    }
}

// A cast to a range alias keeps the cast's result and fails (bad cast) when it lies outside the
// written bounds. The result has the plain base type.
fn emit_cast_range_check(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    range_node: long,
    ty: long,
) {
    let llvm_ty = llvm_type_name(ty)
    ir_write_ascii(compiler, ir, "  %cast.below."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp slt ")
    ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, range_bound_value(tables, range_node, 0L)); ir_write_ascii(compiler, ir, "\n")
    ir_write_ascii(compiler, ir, "  %cast.above."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sgt ")
    ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, range_bound_value(tables, range_node, 1L)); ir_write_ascii(compiler, ir, "\n")
    ir_write_ascii(compiler, ir, "  %ov.flag."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = or i1 %cast.below."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %cast.above."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
    emit_runtime_failure(files, tables, compiler, ir, node, file_index, 10L)
}

// A use of an array constant: copy the constant's image (see emit_array_constant_global) into the
// temporary that holds this use's value.
fn emit_array_constant_value(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let declaration = compiler.facts[node].literal
    let size = value_type_size(compiler, compiler.facts[node].ty)
    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    ir_write_ascii(compiler, ir, "  %const.array.copy."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = call ptr @memmove(ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", ptr @.nl.const."); ir_write_number(compiler, ir, declaration)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, ")\n")
}


// Where an aggregate assignment writes: the target's own address for fields and indexed elements,
// recomputed after the right-hand side for a text element of a collection (the right-hand side may
// have moved the stack), or the local or write parameter itself.
fn assignment_destination(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    target: long,
    ty: long,
    binding: long,
) -> StorageLocation {
    if tables.nodes[target].kind == NodeKind.Index && collection_text_leaf(type_kind(compiler, ty)) {
        let late_address = emit_late_place_address(tables, compiler, ir, target)
        compiler_location(compiler, 2L, late_address, 0L)
    } else if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index {
        compiler_location(compiler, 2L, target, 0L)
    } else if binding_is_write_parameter(compiler, binding) && is_sum_type(compiler, ty) {
        place_storage_location(tables, compiler, target)
    } else if binding_is_write_parameter(compiler, binding) {
        compiler_location(compiler, 3L, binding, 0L)
    } else {
        aggregate_destination_location(compiler, 1L, binding)
    }
}
