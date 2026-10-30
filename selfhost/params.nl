// E3a2 write modes and location descriptor ABI.

fn binding_is_write_parameter(compiler: CompilerTables, binding: long) -> bool {
    binding >= 0L && binding < compiler.bindings.count() && compiler.bindings[binding].parameter && compiler.bindings[binding].mutable
}

fn binding_parameter_mode(compiler: CompilerTables, binding: long) -> long {
    if binding < 0L || binding >= compiler.bindings.count() || !compiler.bindings[binding].parameter { return 0L }
    let scope = compiler.bindings[binding].scope
    if scope < 0L || scope >= compiler.scopes.count() { return 0L }
    let function_id = compiler.scopes[scope].function_id
    if function_id < 0L || function_id >= compiler.functions.count() { return 0L }
    let function = compiler.functions[function_id]
    let parameter_node = compiler.bindings[binding].node
    for parameter_index: long in function.param_start..function.param_start + function.param_count {
        let parameter = compiler.parameters[parameter_index]
        if parameter.node == parameter_node { return parameter_mode(parameter) }
    }
    0L
}

fn binding_is_grow_parameter(compiler: CompilerTables, binding: long) -> bool {
    (binding_parameter_mode(compiler, binding) & FLAG_MODE_GROW) != 0L
}

fn emit_location_index_value(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, location: StorageLocation) {
    if location.index_node >= 0L {
        ir_write_value_ref(compiler, ir, location.index_node)
    } else if location.index_node < -1L {
        ir_write_ascii(compiler, ir, "%for.each.current."); ir_write_number(compiler, ir, -2L - location.index_node)
    } else if location.index == -1L {
        ir_write_ascii(compiler, ir, "%arg.index."); ir_write_number(compiler, ir, location.anchor_node)
    } else {
        ir_write_number(compiler, ir, location.index)
    }
}

// E3a1 begin: by-reference user calls carry movable locations as null+offset.
fn emit_prepare_location_descriptor(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    location: StorageLocation,
    include_geometry: bool,
    descriptor_node: long,
) {
    let dynamic_index = location.index_node != -1L && !include_geometry
    let needs_base = location.origin == LOCATION_DATA_STACK || location.anchor_kind == 3L || location.anchor_kind == 9L
    if !dynamic_index && !needs_base { return }
    var base_is_ssa = false
    if location.origin == LOCATION_DATA_STACK {
        let slot = region_find_slot(compiler, location.anchor_kind, location.anchor_node)
        if slot < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %write.offset.base."); ir_write_number(compiler, ir, descriptor_node); ir_write_ascii(compiler, ir, " = add i64 %region.offset."); ir_write_number(compiler, ir, slot); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
        base_is_ssa = true
    } else if location.anchor_kind == 3L {
        ir_write_ascii(compiler, ir, "  %write.offset.base."); ir_write_number(compiler, ir, descriptor_node); ir_write_ascii(compiler, ir, " = add i64 %arg.offset."); ir_write_number(compiler, ir, location.anchor_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
        base_is_ssa = true
    } else if location.anchor_kind == 9L {
        ir_write_ascii(compiler, ir, "  %write.offset.base."); ir_write_number(compiler, ir, descriptor_node); ir_write_ascii(compiler, ir, " = add i64 %nl.dest.offset, "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
        base_is_ssa = true
    } else if location.byte_offset != 0L {
        ir_write_ascii(compiler, ir, "  %write.offset.base."); ir_write_number(compiler, ir, descriptor_node); ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
        base_is_ssa = true
    } else { () }
    if dynamic_index {
        if location.index_stride <= 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %write.offset.index."); ir_write_number(compiler, ir, descriptor_node); ir_write_ascii(compiler, ir, " = mul i64 "); emit_location_index_value(compiler, ir, location); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.index_stride); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %write.offset."); ir_write_number(compiler, ir, descriptor_node); ir_write_ascii(compiler, ir, " = add i64 ")
        if base_is_ssa { ir_write_ascii(compiler, ir, "%write.offset.base."); ir_write_number(compiler, ir, descriptor_node) }
        else { ir_write_ascii(compiler, ir, "0") }
        ir_write_ascii(compiler, ir, ", %write.offset.index."); ir_write_number(compiler, ir, descriptor_node); ir_push_byte(compiler, ir, 10)
    } else if base_is_ssa {
        ir_write_ascii(compiler, ir, "  %write.offset."); ir_write_number(compiler, ir, descriptor_node); ir_write_ascii(compiler, ir, " = add i64 %write.offset.base."); ir_write_number(compiler, ir, descriptor_node); ir_write_ascii(compiler, ir, ", 0\n")
    } else { () }
}

fn emit_location_descriptor_argument(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    location: StorageLocation,
    include_geometry: bool,
    descriptor_node: long,
) {
    if location.copies < -1L || location.index < -1L { compiler.ir_overflow = true; return }
    if location.origin == LOCATION_DATA_STACK {
        let slot = region_find_slot(compiler, location.anchor_kind, location.anchor_node)
        if slot < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "ptr null, i64 ")
        if location.byte_offset != 0L || (location.index_node != -1L && !include_geometry) {
            ir_write_ascii(compiler, ir, "%write.offset."); ir_write_number(compiler, ir, descriptor_node)
        } else { ir_write_ascii(compiler, ir, "%region.offset."); ir_write_number(compiler, ir, slot) }
    } else if location.anchor_kind == 3L {
        ir_write_ascii(compiler, ir, "ptr %arg.anchor."); ir_write_number(compiler, ir, location.anchor_node); ir_write_ascii(compiler, ir, ", i64 ")
        if location.byte_offset != 0L || (location.index_node != -1L && !include_geometry) {
            ir_write_ascii(compiler, ir, "%write.offset."); ir_write_number(compiler, ir, descriptor_node)
        } else { ir_write_ascii(compiler, ir, "%arg.offset."); ir_write_number(compiler, ir, location.anchor_node) }
    } else if location.anchor_kind == 9L {
        ir_write_ascii(compiler, ir, "ptr %nl.dest.anchor, i64 ")
        if location.byte_offset != 0L { ir_write_ascii(compiler, ir, "%write.offset."); ir_write_number(compiler, ir, descriptor_node) }
        else { ir_write_ascii(compiler, ir, "%nl.dest.offset") }
    } else {
        ir_write_ascii(compiler, ir, "ptr ")
        if location.anchor_kind == 0L { ir_write_ascii(compiler, ir, "%agg."); ir_write_number(compiler, ir, location.anchor_node) }
        else if location.anchor_kind == 1L { ir_write_ascii(compiler, ir, "%local."); ir_write_number(compiler, ir, location.anchor_node) }
        else if location.anchor_kind == 2L { ir_write_ascii(compiler, ir, "%addr."); ir_write_number(compiler, ir, location.anchor_node) }
        else if location.anchor_kind == 10L { ir_write_ascii(compiler, ir, "%optional.call.receiver.snapshot."); ir_write_number(compiler, ir, location.anchor_node) }
        else { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, ", i64 ")
        if location.index_node != -1L && !include_geometry { ir_write_ascii(compiler, ir, "%write.offset."); ir_write_number(compiler, ir, descriptor_node) }
        else { ir_write_number(compiler, ir, location.byte_offset) }
    }
}

fn emit_location_descriptor_parameter(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, prefix: Ascii max 32, binding: long) {
    ir_write_ascii(compiler, ir, "ptr %"); ir_write_ascii(compiler, ir, prefix); ir_write_ascii(compiler, ir, ".anchor")
    if prefix == "arg" { ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, binding) }
    ir_write_ascii(compiler, ir, ", i64 %"); ir_write_ascii(compiler, ir, prefix); ir_write_ascii(compiler, ir, ".offset")
    if prefix == "arg" { ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, binding) }
}
// E3a1 end

fn emit_location_argument(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    location: StorageLocation,
) {
    ir_write_ascii(compiler, ir, "ptr ")
    emit_location_pointer(compiler, ir, location)
}

// E3a1 begin: shared compiler integration.
fn emit_location_parameter(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    binding: long,
) {
    emit_location_descriptor_parameter(compiler, ir, "arg", binding)
    // A read-only Text parameter also receives its length and code point count; every other parameter
    // is just an anchor and an offset.
    if binding_is_text_read_view(compiler, binding) {
        ir_write_ascii(compiler, ir, ", i64 %arg.copies."); ir_write_number(compiler, ir, binding)
        ir_write_ascii(compiler, ir, ", i64 %arg.index."); ir_write_number(compiler, ir, binding)
    }
}

fn binding_is_text_read_view(compiler: CompilerTables, binding: long) -> bool {
    type_kind(compiler, compiler.bindings[binding].ty) == TYPE_KIND_TEXT &&
        (binding_parameter_mode(compiler, binding) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) == 0L
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_hidden_destination_argument(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    destination: StorageLocation,
) {
    emit_location_descriptor_argument(compiler, ir, destination, true, destination.anchor_node)
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_hidden_destination_parameter(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    emit_location_argument(compiler, ir, compiler_location(compiler, 4L, 0L, 0L))
}
// E3a1 end

// E3a1 begin
fn emit_hidden_descriptor_parameter(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    emit_location_descriptor_parameter(compiler, ir, "nl.dest", 0L)
}
// E3a1 end

fn direct_call_argument_is_write(tables: ParseTables, compiler: CompilerTables, call: long, wanted: long) -> bool {
    if call < 0L || wanted < 0L { return false }
    let target = compiler.facts[call].function
    if target < 0L || target >= compiler.functions.count() { return false }
    let function = compiler.functions[target]
    var argument = compiler.child_first[call]
    var argument_index = 0L
    for step in 0L..tables.nodes[call].subtree {
        if argument < 0L || argument == wanted { break }
        argument_index += 1L
        argument = compiler.child_next[argument]
    }
    argument == wanted && argument_index < function.param_count &&
        (parameter_mode(compiler.parameters[function.param_start + argument_index]) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L
}

fn direct_call_argument_uses_text_view(tables: ParseTables, compiler: CompilerTables, call: long, wanted: long) -> bool {
    if call < 0L || wanted < 0L { return false }
    let target = compiler.facts[call].function
    if target < 0L || target >= compiler.functions.count() { return false }
    let function = compiler.functions[target]
    var argument = compiler.child_first[call]
    var argument_index = 0L
    for step in 0L..tables.nodes[call].subtree {
        if argument < 0L || argument == wanted { break }
        argument_index += 1L
        argument = compiler.child_next[argument]
    }
    argument == wanted && argument_index < function.param_count &&
        parameter_uses_text_read_view(compiler, compiler.parameters[function.param_start + argument_index])
}

fn direct_call_text_view_needs_snapshot(tables: ParseTables, compiler: CompilerTables, call: long, wanted: long) -> bool {
    if !direct_call_argument_uses_text_view(tables, compiler, call, wanted) ||
        (tables.nodes[wanted].kind != NodeKind.Name && tables.nodes[wanted].kind != NodeKind.Field) {
        return false
    }
    var later = compiler.child_next[wanted]
    for step in 0L..tables.nodes[call].subtree {
        if later < 0L { break }
        if region_subtree_has_effect(tables, later, later) { return true }
        later = compiler.child_next[later]
    }
    false
}

// Aggregate arguments are already stable places for a single-argument call.
// Snapshot a read argument only when evaluating a later argument may mutate
// it; this preserves left-to-right value semantics without reserving a second
// source-sized buffer for calls such as head(payload). Formatter builtins keep
// their existing prepared-value path because their lowering consumes that
// snapshot explicitly.
fn direct_call_argument_needs_snapshot(tables: ParseTables, compiler: CompilerTables, call: long, wanted: long) -> bool {
    if call < 0L || wanted < 0L ||
        (tables.nodes[wanted].kind != NodeKind.Name && tables.nodes[wanted].kind != NodeKind.Field) ||
        !is_aggregate_type(compiler, compiler.facts[wanted].ty) ||
        direct_call_argument_is_write(tables, compiler, call, wanted) {
        return false
    }
    if call < compiler.facts.count() && (compiler.facts[call].flags & FACT_FORMAT_TEXT) != 0L {
        return true
    }
    var later = compiler.child_next[wanted]
    for step in 0L..tables.nodes[call].subtree {
        if later < 0L { break }
        if region_subtree_has_effect(tables, later, later) { return true }
        later = compiler.child_next[later]
    }
    false
}

// Whatever the argument is (a struct, sum, text, array, list or map), it is reached by a plain offset: the caller folds the element
// index into the offset. Its parameter still has the aggregate shape, with one copy at index zero.
fn descriptor_geometry(compiler: CompilerTables, ty: long) -> bool {
    false
}

fn emit_plain_geometry_tail(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, ty: long) {
    // Nothing: an argument that is not a read-only Text is only an anchor and an offset.
}

// The function body still names a parameter's copy count and index in a few places; for a parameter that
// no longer receives them, they are the constants 1 and 0.
fn emit_parameter_geometry_prologue(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, function: FunctionRecord) {
    for parameter_index in 0L..function.param_count {
        let parameter = compiler.parameters[function.param_start + parameter_index]
        let binding = binding_for_node(compiler, parameter.node)
        if binding < 0L || parameter.ty == TY_UNIT || !is_aggregate_type(compiler, parameter.ty) { continue }
        if binding_is_text_read_view(compiler, binding) { continue }
        ir_write_ascii(compiler, ir, "  %arg.copies."); ir_write_number(compiler, ir, binding)
        ir_write_ascii(compiler, ir, " = add i64 0, 1\n  %arg.index."); ir_write_number(compiler, ir, binding)
        ir_write_ascii(compiler, ir, " = add i64 0, 0\n")
    }
}

// A parameter passed as a location (anchor and offset) is the same storage for the whole call, and the
// data stack no longer moves, so its address is worked out once at entry; every access then adds its
// own offset to that pointer.
fn parameter_has_pointer(compiler: CompilerTables, binding: long) -> bool {
    if binding < 0L || binding >= compiler.bindings.count() || !compiler.bindings[binding].parameter { return false }
    let ty = compiler.bindings[binding].ty
    ty != TY_UNIT && (is_aggregate_type(compiler, ty) || (binding_parameter_mode(compiler, binding) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L)
}

fn emit_parameter_pointer_prologue(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, function: FunctionRecord) {
    for parameter_index in 0L..function.param_count {
        let parameter = compiler.parameters[function.param_start + parameter_index]
        let binding = binding_for_node(compiler, parameter.node)
        if !parameter_has_pointer(compiler, binding) { continue }
        ir_write_ascii(compiler, ir, "  %arg.is.stack."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " = icmp eq ptr %arg.anchor."); ir_write_number(compiler, ir, binding)
        ir_write_ascii(compiler, ir, ", null\n  %arg.native."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %arg.anchor."); ir_write_number(compiler, ir, binding)
        ir_write_ascii(compiler, ir, ", i64 %arg.offset."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, "\n  %arg.base."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " = call ptr ")
        emit_context_runtime_symbol(compiler, ir, "nl_context_current_base", "nlc_context_current_base")
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  %arg.stack."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %arg.base."); ir_write_number(compiler, ir, binding)
        ir_write_ascii(compiler, ir, ", i64 %arg.offset."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, "\n  %arg.ptr."); ir_write_number(compiler, ir, binding)
        ir_write_ascii(compiler, ir, " = select i1 %arg.is.stack."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", ptr %arg.stack."); ir_write_number(compiler, ir, binding)
        ir_write_ascii(compiler, ir, ", ptr %arg.native."); ir_write_number(compiler, ir, binding); ir_push_byte(compiler, ir, 10)
    }
}

// A read-only text or list parameter cannot change while the function runs, so its length is loaded
// once at entry and bounds checks and counts use that.
fn parameter_length_cached(compiler: CompilerTables, binding: long) -> bool {
    if !parameter_has_pointer(compiler, binding) { return false }
    if (binding_parameter_mode(compiler, binding) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L { return false }
    let kind = type_kind(compiler, compiler.bindings[binding].ty)
    kind == TYPE_KIND_ASCII || kind == TYPE_KIND_BYTES || kind == TYPE_KIND_LIST
}

fn cached_length_binding(tables: ParseTables, compiler: CompilerTables, receiver: long) -> long {
    if !compiler.c_runtime || receiver < 0L || tables.nodes[receiver].kind != NodeKind.Name { return -1L }
    let binding = compiler.facts[receiver].binding
    if binding >= 0L && parameter_length_cached(compiler, binding) { binding } else { -1L }
}

fn emit_parameter_length_prologue(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, function: FunctionRecord) {
    for parameter_index in 0L..function.param_count {
        let parameter = compiler.parameters[function.param_start + parameter_index]
        let binding = binding_for_node(compiler, parameter.node)
        if !parameter_length_cached(compiler, binding) { continue }
        ir_write_ascii(compiler, ir, "  %arg.len."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " = load i64, ptr %arg.ptr."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
    }
}
