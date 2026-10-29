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

// Keep language values disjoint from the stable context header in LLVM's
// alias model. Call this only for typed stores emitted through user-language
// locations; raw sys accesses and context maintenance stay unclassified.
fn emit_program_storage_tbaa(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    if !compiler.core_mode { ir_write_ascii(compiler, ir, ", !tbaa !9003") }
}

fn emit_storage_tbaa_metadata(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir,
        "\n!9000 = !{!\"next-lang context and program storage\"}\n!9001 = !{!\"context base\", !9000}\n!9002 = !{!9001, !9001, i64 0}\n!9004 = !{!\"program storage\", !9000}\n!9003 = !{!9004, !9004, i64 0}\n")
}

fn compiler_file_id_base(compiler: CompilerTables) -> long {
    if !compiler.core_mode { 0L }
    else if compiler.file_id_base >= COMPILER_TEST_BUILD_FLAG { compiler.file_id_base - COMPILER_TEST_BUILD_FLAG }
    else { compiler.file_id_base }
}

fn compiler_test_build(compiler: CompilerTables) -> bool {
    compiler.test_build || (compiler.core_mode && compiler.file_id_base >= COMPILER_TEST_BUILD_FLAG)
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

// The parser stores nodes in postorder. The first later node whose subtree
// contains a node is its direct syntax parent; later matches are ancestors.
fn region_parent_node(tables: ParseTables, node: long) -> long {
    if node < 0L || node >= tables.nodes.count() { return -1L }
    for parent: long in node + 1L..tables.nodes.count() {
        let first = parent - tables.nodes[parent].subtree + 1L
        if node >= first { return parent }
    }
    -1L
}

// The index-selected aggregate is only an address base when its direct
// postorder parent is a Field path that emit_collection_field_path_address
// can lower. Keep this predicate in sync with that helper's capability checks
// so planning and emission agree about whether the gathered value is unused.
fn collection_index_has_field_projection(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> bool {
    if node < 0L || node + 1L >= tables.nodes.count() || tables.nodes[node].kind != NodeKind.Index { return false }
    let first_field = node + 1L
    if tables.nodes[first_field].kind != NodeKind.Field || compiler.child_first[first_field] != node { return false }

    let collection = compiler.child_first[node]
    let index = if collection >= 0L { compiler.child_next[collection] } else { -1L }
    if collection < 0L || index < 0L { return false }
    let collection_type = compiler.facts[collection].ty
    let element_type = collection_element_type(compiler, collection_type)
    let copies = collection_capacity(compiler, collection_type)
    if compiler.facts[node].ty != element_type || !is_aggregate_type(compiler, compiler.facts[node].ty) ||
        type_kind(compiler, element_type) != TYPE_KIND_STRUCT || copies < 0L ||
        collection_element_base_offset(compiler, collection_type) < 0L { return false }

    var current = node
    var field_node = first_field
    for path_step in 0L..MAX_TREE_NODES {
        if field_node >= tables.nodes.count() || tables.nodes[field_node].kind != NodeKind.Field ||
            compiler.child_first[field_node] != current { break }
        let receiver_type = compiler.facts[current].ty
        if type_kind(compiler, receiver_type) != TYPE_KIND_STRUCT { return false }
        let record = type_record(compiler, receiver_type)
        let field_number = compiler.facts[field_node].literal - record.field_start
        if collection_field_lane_offset(compiler, receiver_type, copies, field_number) < 0L { return false }
        current = field_node
        field_node += 1L
    }
    true
}

fn region_node_needs_snapshot(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    let syntax_kind = tables.nodes[node].kind
    if syntax_kind != NodeKind.Name && syntax_kind != NodeKind.Field { return false }
    let ty = compiler.facts[node].ty
    if !is_aggregate_type(compiler, ty) { return false }
    if (compiler.facts[node].flags & FACT_CONSTANT_TEXT) != 0L { return true }
    if is_sum_type(compiler, ty) && compiler.facts[node].binding < 0L { return true }
    if syntax_kind == NodeKind.Name && binding_is_view(compiler, compiler.facts[node].binding) { return true }
    let parent = region_parent_node(tables, node)
    if parent < 0L { return false }
    let parent_kind = tables.nodes[parent].kind
    if parent_kind == NodeKind.Binary && compiler.child_first[parent] == node {
        let right = compiler.child_next[node]
        let op = tables.nodes[parent].flags
        if op == 0L && text_concat_left_needs_snapshot(tables, compiler, parent) { return true }
        if op >= 8L && op <= 13L &&
            (!is_text_comparable(compiler, ty, compiler.facts[right].ty) || region_subtree_has_effect(tables, right, right)) {
            return true
        }
    }
    if (parent_kind == NodeKind.Call || parent_kind == NodeKind.OptionalCall) &&
        direct_call_argument_needs_snapshot(tables, compiler, parent, node) { return true }
    false
}

fn region_node_is_direct_output(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    let parent = region_parent_node(tables, node)
    if parent < 0L { return false }
    let parent_kind = tables.nodes[parent].kind
    if parent_kind == NodeKind.Let || parent_kind == NodeKind.ReturnStatement { return true }
    if parent_kind != NodeKind.Block || node_last_child(tables, compiler, parent) != node ||
        (tables.nodes[parent].flags & FLAG_HAS_TAIL) == 0L { return false }
    for function_id in 0L..compiler.functions.count() {
        if compiler.functions[function_id].body == parent { return true }
    }
    for test_index in 0L..compiler.tests.count() {
        if compiler.tests[test_index].body == parent { return true }
    }
    false
}

fn region_subtree_has_effect(tables: ParseTables, first_node: long, root: long) -> bool {
    let first = first_node - tables.nodes[first_node].subtree + 1L
    for candidate in first..root + 1L {
        let kind = tables.nodes[candidate].kind
        if kind == NodeKind.Assign || kind == NodeKind.Call || kind == NodeKind.MethodCall ||
            kind == NodeKind.OptionalCall || kind == NodeKind.Try { return true }
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
        if compiler.child_first[parent] == node {
            if tables.nodes[parent].kind == NodeKind.MethodCall {
                if syntax_kind == NodeKind.Index {
                    // Method arguments run after the receiver has been read.
                    // Preserve its region snapshot if an argument can mutate
                    // the value before the method consumes it.
                    let mutator = compiler.child_next[node]
                    if mutator >= 0L && region_subtree_has_effect(tables, mutator, parent - 1L) { return false }
                }
                return true
            }
            if tables.nodes[parent].kind == NodeKind.Index {
                let index = compiler.child_next[node]
                if index < 0L { return false }
                // Evaluating an effectful index can mutate the collection
                // after the receiver's evaluation point. Keep the planned
                // snapshot storage in that case; only borrow the receiver
                // when its value remains stable through index evaluation.
                if region_subtree_has_effect(tables, index, index) { return false }
                return true
            }
        }
    }
    false
}

fn region_node_is_temporary(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    if node >= 0L && node < compiler.region_temp_scope.count() {
        let cached_scope = compiler.region_temp_scope[node]
        if cached_scope != -3L { return cached_scope != -2L }
    }
    if node >= 0L && node < tables.nodes.count() &&
        tables.nodes[node].kind == NodeKind.Index && collection_index_has_field_projection(tables, compiler, node) {
        return false
    }
    let syntax_kind = tables.nodes[node].kind
    if syntax_kind == NodeKind.FunctionType || syntax_kind == NodeKind.FunctionTypeParameter ||
        syntax_kind == NodeKind.ParameterType || syntax_kind == NodeKind.ResultType ||
        syntax_kind == NodeKind.Annotation || syntax_kind == NodeKind.FieldType ||
        syntax_kind == NodeKind.PayloadType || syntax_kind == NodeKind.AliasedType ||
        syntax_kind == NodeKind.DeclaredType || syntax_kind == NodeKind.TypeArgument ||
        syntax_kind == NodeKind.FitType || syntax_kind == NodeKind.CastType ||
        syntax_kind == NodeKind.Block || syntax_kind == NodeKind.MatchArm { return false }
    if region_node_is_direct_output(tables, compiler, node) { return false }
    if syntax_kind == NodeKind.Name || syntax_kind == NodeKind.Field {
        return region_node_needs_snapshot(tables, compiler, node)
    }
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

// -3 means not classified, -2 means a non-temporary, -1 means a temporary
// outside a block scope, and a nonnegative value is its owning block.
fn region_cache_body_temporary_scopes(
    tables: ParseTables,
    compiler: write CompilerTables,
    body: long,
) {
    // Function and test bodies are disjoint top-level subtrees. Their body
    // Block is always non-temporary, so a cached body slot means this exact
    // range has already completed classification and block assignment.
    if body >= 0L && body < compiler.region_temp_scope.count() &&
        compiler.region_temp_scope[body] != -3L { return }
    let first = body - tables.nodes[body].subtree + 1L
    for node in first..body + 1L {
        if node < 0L || node >= compiler.region_temp_scope.count() {
            compiler.ir_overflow = true
            return
        }
        if compiler.region_temp_scope[node] != -3L { continue }
        if !region_node_is_temporary(tables, compiler, node) {
            compiler.region_temp_scope[node] = -2L
        } else {
            compiler.region_temp_scope[node] = -1L
        }
    }
    for block_step in 0L..body - first + 1L {
        let block = body - block_step
        if tables.nodes[block].kind != NodeKind.Block ||
            tables.nodes[block].start < tables.nodes[body].start ||
            tables.nodes[block].end > tables.nodes[body].end { continue }
        let block_first = block - tables.nodes[block].subtree + 1L
        for node in block_first..block + 1L {
            if node < first || node > body { continue }
            let node_scope = compiler.region_temp_scope[node]
            if node_scope == -2L || node_scope == -3L ||
                tables.nodes[node].start < tables.nodes[body].start ||
                tables.nodes[node].end > tables.nodes[body].end { continue }
            let selected_size = if node_scope < 0L { 9223372036854775807L }
                else { tables.nodes[node_scope].subtree }
            if tables.nodes[block].subtree < selected_size {
                compiler.region_temp_scope[node] = block
            }
        }
    }
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
    if scope_id < 0L || scope_id >= compiler.block_end.count() || scope_id >= compiler.block_align.count() ||
        size <= 0L || alignment <= 0L || size > 9223372036854775807L - (alignment - 1L) ||
        compiler.region_current_size > 9223372036854775807L - (alignment - 1L) {
        compiler.ir_overflow = true
        return
    }
    let aligned = ((compiler.region_current_size + alignment - 1L) / alignment) * alignment
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
    compiler.region_current_size = aligned + size
    compiler.block_end[scope_id] = compiler.region_current_size
    if alignment > compiler.block_align[scope_id] { compiler.block_align[scope_id] = alignment }
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
    if !is_aggregate_type(compiler, ty) || node < 0L || node >= compiler.region_temp_scope.count() { return }
    let first = body - tables.nodes[body].subtree + 1L
    if node < first || node > body { return }
    let node_scope = compiler.region_temp_scope[node]
    if node_scope < 0L || node_scope != block || region_has_slot(compiler, 0L, node) { return }
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
    region_cache_body_temporary_scopes(tables, compiler, body)
    if compiler.ir_overflow { return }
    var largest_block = 0L
    let threshold = compiler.file_id_base
    let first = body - tables.nodes[body].subtree + 1L
    var binding_first = -1L
    var binding_end = -1L
    for binding_id in 0L..compiler.bindings.count() {
        let binding_scope = compiler.bindings[binding_id].scope
        if binding_scope < 0L || binding_scope >= compiler.scopes.count() ||
            compiler.scopes[binding_scope].function_id != function_id { continue }
        if binding_first < 0L { binding_first = binding_id }
        binding_end = binding_id + 1L
    }
    if binding_first < 0L { binding_first = 0L; binding_end = 0L }
    // Each block gets a local offset range. At run time that range starts at
    // the block's incoming top, so nested blocks follow their live parent
    // regions and sibling blocks can reuse the same space after a scope exit.
    // AST nodes are stored in postorder; visit outer blocks first.
    for block_step in 0L..body - first + 1L {
        let block = body - block_step
        if tables.nodes[block].kind != NodeKind.Block && tables.nodes[block].kind != NodeKind.MatchArm { continue }
        if block < 0L || block >= compiler.block_end.count() || block >= compiler.block_align.count() {
            compiler.ir_overflow = true
            return
        }
        compiler.block_end[block] = -1L
        compiler.block_align[block] = 1L
        compiler.region_current_size = 0L
        for group in 0L..2L {
            let small_group = group == 0L
            for binding_id in binding_first..binding_end {
                region_consider_binding(compiler, function_id, block, binding_id, small_group, threshold)
            }
            let block_first = block - tables.nodes[block].subtree + 1L
            for node in block_first..block + 1L {
                region_consider_temporary(tables, compiler, function_id, body, block, node, small_group, threshold)
            }
        }
        if compiler.region_current_size > largest_block { largest_block = compiler.region_current_size }
    }
    compiler.region_max_size = largest_block
}

fn emit_region_scope_enter(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    block: long,
    file_id: long,
) {
    if compiler.core_mode || compiler.region_max_size <= 0L { return }
    let function_id = region_function_for_block(tables, compiler, block)
    let body = region_body_for_block(tables, compiler, block)
    if function_id == -9223372036854775807L || body < 0L || block < 0L ||
        block >= compiler.block_end.count() || block >= compiler.block_align.count() {
        compiler.ir_overflow = true
        return
    }
    let end_offset = compiler.block_end[block]
    // A block with no live values has no stack effect. Its per-iteration
    // scope bookkeeping would only reload and republish an unchanged top.
    if end_offset < 0L { return }
    ir_write_ascii(compiler, ir, "  %nl.scope.saved."); ir_write_number(compiler, ir, block)
    ir_write_ascii(compiler, ir, " = load i64, ptr %nl.top.current.slot, align 8\n  store i64 %nl.scope.saved.")
    ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", ptr %nl.scope.top.")
    ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 10)
    if end_offset >= 0L {
        let position = position_for_offset(file_id, files[file_id].base + tables.nodes[block].anchor, compiler)
        let core_file_id = file_id + compiler_file_id_base(compiler)
        let alignment = compiler.block_align[block]
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
        ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 18, i32 ")
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
        ir_write_ascii(compiler, ir, ":\n")
        if compiler.c_runtime {
            ir_write_ascii(compiler, ir, "  call void @nlc_stack_grow(ptr %nl.ctx, i64 %nl.scope.end.")
            ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", i32 ")
            ir_write_number(compiler, ir, core_file_id); ir_write_ascii(compiler, ir, ", i32 ")
            ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 ")
            ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  call void @nl_context_set_top_offset(ptr %nl.ctx, i64 %nl.scope.end.")
            ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ")\n")
        } else {
            ir_write_ascii(compiler, ir, "  call void @nl_context_set_top_offset(ptr %nl.ctx, i64 %nl.scope.end.")
            ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ")\n  call void @nl_stack_grow(ptr %nl.ctx, i64 %nl.scope.end.")
            ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", i32 ")
            ir_write_number(compiler, ir, core_file_id); ir_write_ascii(compiler, ir, ", i32 ")
            ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 ")
            ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n")
        }
        ir_write_ascii(compiler, ir, "  br label %nl.scope.ready.")
        ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, "\nnl.scope.ready."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ":\n  %nl.scope.target."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, " = select i1 %nl.scope.more."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", i64 %nl.scope.end."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", i64 %nl.scope.saved."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, "\n  store i64 %nl.scope.target."); ir_write_number(compiler, ir, block)
        ir_write_ascii(compiler, ir, ", ptr %nl.top.current.slot, align 8\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_context_note_peak", "nlc_context_note_peak"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.scope.target.")
        ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ")\n")
    }
    let first = body - tables.nodes[body].subtree + 1L
    for node in first..body + 1L {
        if !is_aggregate_type(compiler, compiler.facts[node].ty) || compiler.region_temp_scope[node] != block || !region_has_slot(compiler, 0L, node) { continue }
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

fn emit_region_scope_exit(tables: ParseTables, compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, block: long) {
    if compiler.core_mode || compiler.region_max_size <= 0L { return }
    if block < 0L || block >= compiler.block_end.count() { compiler.ir_overflow = true; return }
    if compiler.block_end[block] < 0L { return }
    let serial = next_location_serial(ir)
    ir_write_ascii(compiler, ir, "  %nl.scope.restore."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load i64, ptr %nl.scope.top."); ir_write_number(compiler, ir, block); ir_write_ascii(compiler, ir, ", align 8\n  store i64 %nl.scope.restore."); ir_write_number(compiler, ir, block); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %nl.top.current.slot, align 8\n")
}

// E3a3-fix subsection
// A break or continue jumps past the exits of every block between the jump
// and the loop body. Restore the top from the outermost block on that path
// that holds slots. Blocks above it are slot-free and skip their own scope
// bookkeeping, so its saved top equals the loop body's entry top. When no
// block on the path holds slots, nothing was reserved and nothing is emitted.
fn emit_region_loop_exit(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    loop_body: long,
    jump: long,
) {
    if compiler.core_mode || compiler.region_max_size <= 0L { return }
    if loop_body < 0L || loop_body >= compiler.block_end.count() { compiler.ir_overflow = true; return }
    for step in 0L..loop_body - jump {
        let block = loop_body - step
        let kind = tables.nodes[block].kind
        if kind != NodeKind.Block && kind != NodeKind.MatchArm { continue }
        if block - tables.nodes[block].subtree + 1L > jump { continue }
        if block < 0L || block >= compiler.block_end.count() || compiler.block_end[block] < 0L { continue }
        emit_region_scope_exit(tables, compiler, ir, block)
        return
    }
}
// E3a3-fix subsection end

fn emit_current_top_load(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long) {
    if !compiler.core_mode && compiler.region_max_size > 0L {
        ir_write_ascii(compiler, ir, "  %nl.current.top."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr %nl.top.current.slot, align 8\n")
    }
}

fn emit_current_top_reference(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long) {
    if compiler.core_mode { ir_write_ascii(compiler, ir, "%nl.region.end") }
    else if compiler.region_max_size > 0L { ir_write_ascii(compiler, ir, "%nl.current.top."); ir_write_number(compiler, ir, node) }
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
    if compiler.region_max_size <= 0L { return }
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
    compiler.region_current_size = 0L
    compiler.region_max_size = 0L
}
// E3a1 end
