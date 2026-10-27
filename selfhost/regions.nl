// E3a1 begin
const COMPILER_TEST_BUILD_FLAG: long = 1152921504606846976L

fn test_region_threshold_argument(argument: Arg) -> long {
    let prefix = "--test-region-threshold="
    let prefix_length = (long)prefix.len()
    if argument.count() <= prefix_length { return -1L }
    for index in 0L..prefix_length {
        let actual = match argument.get(index) { some(value) => value, none => return -1L }
        if actual != prefix.bytes()[index] { return -1L }
    }
    var value = 0L
    for index in prefix_length..argument.count() {
        let byte = match argument.get(index) { some(found) => found, none => return -1L }
        if byte < 48 || byte > 57 { return -1L }
        let digit = (long)byte - 48L
        if value > (9223372036854775807L - digit) / 10L { return -1L }
        value = value * 10L + digit
    }
    value
}

fn next_location_serial(ir: grow Bytes max IR_BUFFER_CAPACITY) -> long {
    ir.count()
}

fn compiler_file_id_base(compiler: CompilerTables) -> long {
    if !compiler.core_mode { 0L }
    else if compiler.file_id_base >= COMPILER_TEST_BUILD_FLAG { compiler.file_id_base - COMPILER_TEST_BUILD_FLAG }
    else { compiler.file_id_base }
}

fn compiler_test_build(compiler: CompilerTables) -> bool {
    compiler.core_mode && compiler.file_id_base >= COMPILER_TEST_BUILD_FLAG
}

fn region_find_slot(compiler: CompilerTables, anchor_kind: long, anchor_node: long) -> long {
    let node = if anchor_kind == 0L { anchor_node }
        else if anchor_kind == 1L && anchor_node >= 0L && anchor_node < compiler.bindings.count() { compiler.bindings[anchor_node].node }
        else { -1L }
    if node >= 0L && node < compiler.expected.count() && compiler.expected[node] >= 0L { node } else { -1L }
}

fn region_has_slot(compiler: CompilerTables, anchor_kind: long, anchor_node: long) -> bool {
    region_find_slot(compiler, anchor_kind, anchor_node) >= 0L
}

fn region_node_has_binding(compiler: CompilerTables, node: long) -> bool {
    for binding_id in 0L..compiler.bindings.count() {
        if compiler.bindings[binding_id].node == node { return true }
    }
    false
}

fn region_node_is_collection_method_receiver(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> bool {
    let syntax_kind = tables.nodes[node].kind
    if syntax_kind != NodeKind.Name && syntax_kind != NodeKind.Field && syntax_kind != NodeKind.Index { return false }
    let kind = type_kind(compiler, compiler.facts[node].ty)
    if kind != TYPE_KIND_ARRAY && kind != TYPE_KIND_LIST { return false }
    for parent in 0L..tables.nodes.count() {
        if compiler.child_first[parent] == node && tables.nodes[parent].kind == NodeKind.MethodCall {
            return true
        }
    }
    false
}

fn region_node_is_temporary(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    let syntax_kind = tables.nodes[node].kind
    if syntax_kind == NodeKind.FunctionType || syntax_kind == NodeKind.FunctionTypeParameter ||
        syntax_kind == NodeKind.ParameterType || syntax_kind == NodeKind.ResultType ||
        syntax_kind == NodeKind.Annotation || syntax_kind == NodeKind.FieldType ||
        syntax_kind == NodeKind.PayloadType || syntax_kind == NodeKind.AliasedType ||
        syntax_kind == NodeKind.DeclaredType || syntax_kind == NodeKind.TypeArgument ||
        syntax_kind == NodeKind.FitType || syntax_kind == NodeKind.CastType { return false }
    !region_node_has_binding(compiler, node) &&
        !region_node_is_pattern_binding(tables, node) &&
        !region_node_is_collection_method_receiver(tables, compiler, node)
}

fn region_node_is_pattern_binding(tables: ParseTables, node: long) -> bool {
    tables.nodes[node].kind == NodeKind.PatternBinding || tables.nodes[node].kind == NodeKind.IgnoredPatternBinding
}

fn region_slot_offset(compiler: CompilerTables, anchor_kind: long, anchor_node: long) -> long {
    let index = region_find_slot(compiler, anchor_kind, anchor_node)
    if index < 0L { -1L } else { compiler.expected[index] }
}

fn region_scope_for_binding(compiler: CompilerTables, function_id: long, binding_id: long) -> long {
    if binding_id < 0L || binding_id >= compiler.bindings.count() { return -1L }
    let scope_id = compiler.bindings[binding_id].scope
    if scope_id < 0L || scope_id >= compiler.scopes.count() { return -1L }
    if compiler.scopes[scope_id].function_id != function_id { return -1L }
    let owner = compiler.scopes[scope_id].block
    if function_id >= 0L && function_id < compiler.functions.count() && owner == compiler.functions[function_id].node {
        return compiler.functions[function_id].body
    }
    let test_index = -1L - function_id
    if test_index >= 0L && test_index < compiler.tests.count() && owner == compiler.tests[test_index].node {
        return compiler.tests[test_index].body
    }
    owner
}

fn region_function_for_block(tables: ParseTables, compiler: CompilerTables, block: long) -> long {
    for function_id in 0L..compiler.functions.count() {
        let body = compiler.functions[function_id].body
        let first = body - tables.nodes[body].subtree + 1L
        if block >= first && block <= body { return function_id }
    }
    for test_index in 0L..compiler.tests.count() {
        let body = compiler.tests[test_index].body
        let first = body - tables.nodes[body].subtree + 1L
        if block >= first && block <= body { return -1L - test_index }
    }
    for scope_id in 0L..compiler.scopes.count() {
        if compiler.scopes[scope_id].block == block { return compiler.scopes[scope_id].function_id }
    }
    -9223372036854775807L
}

fn region_body_for_block(tables: ParseTables, compiler: CompilerTables, block: long) -> long {
    let function_id = region_function_for_block(tables, compiler, block)
    if function_id >= 0L && function_id < compiler.functions.count() {
        return compiler.functions[function_id].body
    }
    let test_index = -1L - function_id
    if test_index >= 0L && test_index < compiler.tests.count() {
        return compiler.tests[test_index].body
    }
    -1L
}

fn region_scope_for_temporary(
    tables: ParseTables,
    body: long,
    node: long,
) -> long {
    if tables.nodes[node].start < tables.nodes[body].start ||
        tables.nodes[node].end > tables.nodes[body].end { return -1L }
    let first = body - tables.nodes[body].subtree + 1L
    var selected = -1L
    var selected_size = 9223372036854775807L
    for block_step in 0L..body - first + 1L {
        let block = body - block_step
        if tables.nodes[block].kind != NodeKind.Block ||
            tables.nodes[block].start < tables.nodes[body].start ||
            tables.nodes[block].end > tables.nodes[body].end { continue }
        let block_first = block - tables.nodes[block].subtree + 1L
        if node >= block_first && node <= block && tables.nodes[block].subtree < selected_size {
            selected = block
            selected_size = tables.nodes[block].subtree
        }
    }
    selected
}

fn region_add_slot(
    compiler: write CompilerTables,
    function_id: long,
    scope_id: long,
    anchor_kind: long,
    anchor_node: long,
    size: long,
    alignment: long,
) {
    if size <= 0L || alignment <= 0L || size > 9223372036854775807L - (alignment - 1L) ||
        compiler.expected[0L] > 9223372036854775807L - (alignment - 1L) {
        compiler.ir_overflow = true
        return
    }
    let aligned = ((compiler.expected[0L] + alignment - 1L) / alignment) * alignment
    if aligned > 9223372036854775807L - size {
        compiler.ir_overflow = true
        return
    }
    let node = if anchor_kind == 0L { anchor_node }
        else if anchor_kind == 1L && anchor_node >= 0L && anchor_node < compiler.bindings.count() { compiler.bindings[anchor_node].node }
        else { -1L }
    if node < 0L || node >= compiler.expected.count() {
        compiler.ir_overflow = true
        return
    }
    compiler.expected[node] = aligned
    compiler.expected[0L] = aligned + size
}

fn region_consider_binding(
    compiler: write CompilerTables,
    function_id: long,
    block: long,
    binding_id: long,
    small_group: bool,
    threshold: long,
) {
    let binding = compiler.bindings[binding_id]
    if binding.parameter || binding_is_view(compiler, binding_id) || !is_aggregate_type(compiler, binding.ty) ||
        region_scope_for_binding(compiler, function_id, binding_id) != block ||
        region_has_slot(compiler, 1L, binding_id) {
        return
    }
    let info = type_record(compiler, binding.ty)
    if info.size <= threshold { return }
    if (info.size <= 65536L) != small_group { return }
    region_add_slot(compiler, function_id, block, 1L, binding_id, info.size, info.align)
}

fn region_consider_temporary(
    tables: ParseTables,
    compiler: write CompilerTables,
    function_id: long,
    body: long,
    block: long,
    node: long,
    small_group: bool,
    threshold: long,
) {
    let ty = compiler.facts[node].ty
    if !is_aggregate_type(compiler, ty) || !region_node_is_temporary(tables, compiler, node) || region_has_slot(compiler, 0L, node) { return }
    let first = body - tables.nodes[body].subtree + 1L
    if node < first || node > body { return }
    if region_scope_for_temporary(tables, body, node) != block { return }
    let info = type_record(compiler, ty)
    if info.size <= threshold { return }
    if (info.size <= 65536L) != small_group { return }
    region_add_slot(compiler, function_id, block, 0L, node, info.size, info.align)
}

fn plan_function_regions(
    tables: ParseTables,
    compiler: write CompilerTables,
    body: long,
    function_id: long,
) {
    if compiler.core_mode { return }
    var largest_block = 0L
    let threshold = compiler.file_id_base
    let first = body - tables.nodes[body].subtree + 1L
    // Each block gets a local offset range. At run time that range starts at
    // the block's incoming top, so nested blocks follow their live parent
    // regions and sibling blocks can reuse the same space after a scope exit.
    // AST nodes are stored in postorder; visit outer blocks first.
    for block_step in 0L..body - first + 1L {
        let block = body - block_step
        if tables.nodes[block].kind != NodeKind.Block && tables.nodes[block].kind != NodeKind.MatchArm { continue }
        compiler.expected[0L] = 0L
        for group in 0L..2L {
            let small_group = group == 0L
            for binding_id in 0L..compiler.bindings.count() {
                region_consider_binding(compiler, function_id, block, binding_id, small_group, threshold)
            }
            for node in first..body + 1L {
                region_consider_temporary(tables, compiler, function_id, body, block, node, small_group, threshold)
            }
        }
        if compiler.expected[0L] > largest_block { largest_block = compiler.expected[0L] }
    }
    compiler.expected[0L] = largest_block
}

fn region_scope_end_offset(
    tables: ParseTables,
    compiler: write CompilerTables,
    body: long,
    function_id: long,
    block: long,
) -> long {
    var end = -1L
    for binding_id in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_id]
        if binding_is_view(compiler, binding_id) || !is_aggregate_type(compiler, binding.ty) || region_scope_for_binding(compiler, function_id, binding_id) != block { continue }
        let offset = region_slot_offset(compiler, 1L, binding_id)
        let size = type_record(compiler, binding.ty).size
        if offset >= 0L && offset <= 9223372036854775807L - size && offset + size > end { end = offset + size }
    }
    let first = body - tables.nodes[body].subtree + 1L
    for node in first..body + 1L {
        if !region_node_is_temporary(tables, compiler, node) || region_scope_for_temporary(tables, body, node) != block || !is_aggregate_type(compiler, compiler.facts[node].ty) { continue }
        let offset = region_slot_offset(compiler, 0L, node)
        let size = type_record(compiler, compiler.facts[node].ty).size
        if offset >= 0L && offset <= 9223372036854775807L - size && offset + size > end { end = offset + size }
    }
    end
}

fn region_scope_alignment(
    tables: ParseTables,
    compiler: write CompilerTables,
    body: long,
    function_id: long,
    block: long,
) -> long {
    var alignment = 1L
    for binding_id in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_id]
        if binding_is_view(compiler, binding_id) || !is_aggregate_type(compiler, binding.ty) || region_scope_for_binding(compiler, function_id, binding_id) != block { continue }
        if region_slot_offset(compiler, 1L, binding_id) >= 0L && type_record(compiler, binding.ty).align > alignment {
            alignment = type_record(compiler, binding.ty).align
        }
    }
    let first = body - tables.nodes[body].subtree + 1L
    for node in first..body + 1L {
        if region_node_has_binding(compiler, node) || region_node_is_pattern_binding(tables, node) || region_scope_for_temporary(tables, body, node) != block || !is_aggregate_type(compiler, compiler.facts[node].ty) { continue }
        if region_slot_offset(compiler, 0L, node) >= 0L && type_record(compiler, compiler.facts[node].ty).align > alignment {
            alignment = type_record(compiler, compiler.facts[node].ty).align
        }
    }
    alignment
}

fn emit_region_scope_enter(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    block: long,
    file_id: long,
) {
    if compiler.core_mode || compiler.expected[0L] <= 0L { return }
    let function_id = region_function_for_block(tables, compiler, block)
    let body = region_body_for_block(tables, compiler, block)
    if function_id == -9223372036854775807L || body < 0L { compiler.ir_overflow = true; return }
    ir_write_ascii(compiler, ir, "  %nl.scope.saved."); ir_write_number(compiler, ir, block)
    ir_write_ascii(compiler, ir, " = load i64, ptr %nl.top.current.slot, align 8\n  store i64 %nl.scope.saved.")
    ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", ptr %nl.scope.top.")
    ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 10)
    let end_offset = region_scope_end_offset(tables, compiler, body, function_id, block)
    if end_offset >= 0L {
        let position = position_for_offset(file_id, files[file_id].base + tables.nodes[block].anchor, compiler)
        let core_file_id = file_id + compiler_file_id_base(compiler)
        let alignment = region_scope_alignment(tables, compiler, body, function_id, block)
        ir_write_ascii(compiler, ir, "  %nl.scope.rem."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = urem i64 %nl.scope.saved."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, alignment); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %nl.scope.pad.raw."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = sub i64 "); ir_write_number(compiler, ir, alignment)
        ir_write_ascii(compiler, ir, ", %nl.scope.rem."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %nl.scope.is.aligned."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = icmp eq i64 %nl.scope.rem."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", 0\n  %nl.scope.pad."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = select i1 %nl.scope.is.aligned."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", i64 0, i64 %nl.scope.pad.raw."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %nl.scope.base."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = add i64 %nl.scope.saved."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", %nl.scope.pad."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %nl.scope.align.overflow."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = icmp ult i64 %nl.scope.base."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", %nl.scope.saved."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %nl.scope.end."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = add i64 %nl.scope.base."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, end_offset); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %nl.scope.end.overflow."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = icmp ult i64 %nl.scope.end."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", %nl.scope.base."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %nl.scope.overflow."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = or i1 %nl.scope.align.overflow."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", %nl.scope.end.overflow."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  br i1 %nl.scope.overflow."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", label %nl.scope.fail."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", label %nl.scope.check."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, "\nnl.scope.fail."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ":\n  call void @nl_fail(ptr %nl.ctx, i32 18, i32 ")
        ir_write_number(compiler, ir, core_file_id); ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\nnl.scope.check.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ":\n  %nl.scope.more.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, " = icmp ugt i64 %nl.scope.end.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", %nl.scope.saved.")
        ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, "\n  br i1 %nl.scope.more."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", label %nl.scope.reserve."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", label %nl.scope.ready."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, "\nnl.scope.reserve."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ":\n  %nl.scope.reserved."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = call i64 @nl_context_reservation_bytes(ptr %nl.ctx)\n  %nl.scope.grow.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, " = icmp ugt i64 %nl.scope.end.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", %nl.scope.reserved.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, "\n  br i1 %nl.scope.grow.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", label %nl.scope.slow.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", label %nl.scope.ready.")
        ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, "\nnl.scope.slow."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ":\n  call void @nl_context_set_top_offset(ptr %nl.ctx, i64 %nl.scope.end.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ")\n  call void @nl_stack_grow(ptr %nl.ctx, i64 %nl.scope.end.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, core_file_id); ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  br label %nl.scope.ready.")
        ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, "\nnl.scope.ready."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ":\n  %nl.scope.target."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = select i1 %nl.scope.more."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", i64 %nl.scope.end."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", i64 %nl.scope.saved."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, "\n  store i64 %nl.scope.target."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", ptr %nl.top.current.slot, align 8\n  call void @nl_context_set_top_offset(ptr %nl.ctx, i64 %nl.scope.target.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ")\n  call void @nl_context_note_peak(ptr %nl.ctx, i64 %nl.scope.target.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ")\n")
    }
    let first = body - tables.nodes[body].subtree + 1L
    for node in first..body + 1L {
        if !is_aggregate_type(compiler, compiler.facts[node].ty) || !region_node_is_temporary(tables, compiler, node) || region_scope_for_temporary(tables, body, node) != block || !region_has_slot(compiler, 0L, node) { continue }
        let offset = compiler.expected[node]
        ir_write_ascii(compiler, ir, "  %region.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %nl.scope.base."); ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, offset); ir_push_byte(compiler, ir, 10)
    }
    for binding_id in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_id]
        if region_scope_for_binding(compiler, function_id, binding_id) != block || !region_has_slot(compiler, 1L, binding_id) { continue }
        let offset = compiler.expected[binding.node]
        ir_write_ascii(compiler, ir, "  %region.offset."); ir_write_number(compiler, ir, binding.node); ir_write_ascii(compiler, ir, " = add i64 %nl.scope.base."); ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, offset); ir_push_byte(compiler, ir, 10)
    }
}

fn emit_region_scope_exit(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, block: long) {
    if compiler.core_mode || compiler.expected[0L] <= 0L { return }
    let serial = next_location_serial(ir)
    ir_write_ascii(compiler, ir, "  %nl.scope.restore."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load i64, ptr %nl.scope.top."); ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", align 8\n  store i64 %nl.scope.restore."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %nl.top.current.slot, align 8\n  call void @nl_context_set_top_offset(ptr %nl.ctx, i64 %nl.scope.restore."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ")\n")
}

fn emit_current_top_load(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long) {
    if !compiler.core_mode && compiler.expected[0L] > 0L {
        ir_write_ascii(compiler, ir, "  %nl.current.top."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr %nl.top.current.slot, align 8\n")
    }
}

fn emit_current_top_reference(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long) {
    if compiler.core_mode { ir_write_ascii(compiler, ir, "%nl.region.end") }
    else if compiler.expected[0L] > 0L { ir_write_ascii(compiler, ir, "%nl.current.top."); ir_write_number(compiler, ir, node) }
    else { ir_write_ascii(compiler, ir, "%nl.top") }
}

fn emit_region_prologue(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    body: long,
    file_id: long,
) {
    if compiler.expected[0L] <= 0L { return }
    ir_write_ascii(compiler, ir, "  %nl.top.current.slot = alloca i64, align 8\n  store i64 %nl.top, ptr %nl.top.current.slot, align 8\n")
    let first = body - tables.nodes[body].subtree + 1L
    for block in first..body + 1L {
        if tables.nodes[block].kind == NodeKind.Block || tables.nodes[block].kind == NodeKind.MatchArm {
            ir_write_ascii(compiler, ir, "  %nl.scope.top."); ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n")
        }
    }
    emit_region_scope_enter(files, tables, compiler, ir, body, file_id)
}

fn clear_function_regions(compiler: write CompilerTables) {
    for node in 0L..compiler.expected.count() { compiler.expected[node] = -1L }
    compiler.expected[0L] = 0L
}
// E3a1 end
