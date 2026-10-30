fn report_frame_budget_unsupported(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
) -> never {
    report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit {
        found: true,
        file: file_index,
        node,
        offset: tables.nodes[node].start,
        category: UNSUPPORTED_FRAME_BUDGET,
        token: tables.nodes[node].token,
    })
}

fn check_native_frame_budget(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    entry: long,
    want_test_build: bool,
) {
    populate_frame_slot_bytes(tables, compiler)
    compute_frame_slot_paths(tables, compiler)
    if want_test_build {
        for test_index in 0L..compiler.tests.count() {
            let graph_node = test_graph_node(compiler, test_index)
            if compiler.frame_path_bytes[graph_node] >= 0L && compiler.frame_path_bytes[graph_node] > 1048576L {
                let test = compiler.tests[test_index]
                report_frame_budget_unsupported(env, source, files, tokens, tables, compiler, test.file, test.node)
            }
        }
    } else if entry >= 0L && compiler.frame_path_bytes[entry] >= 0L && compiler.frame_path_bytes[entry] > 1048576L {
        let function = compiler.functions[entry]
        report_frame_budget_unsupported(env, source, files, tokens, tables, compiler, function.file, function.node)
    } else { () }
}

fn fail_call_cycle(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
) -> never {
    let first_function = compiler.cycle_path[0L]
    let function = compiler.functions[first_function]
    let position = position_for_offset(function.file, files[function.file].base + tables.nodes[function.node].start, compiler)
    match env.err.write(files[function.file].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: call cycle contains unmarked function(s) ") { ok(_) => (), err(_) => env.exit(3) }
    var wrote_name = false
    for function_id in 0L..compiler.functions.count() {
        var belongs = false
        for path_index in 0L..compiler.cycle_path.count() {
            if compiler.cycle_path[path_index] == function_id { belongs = true }
        }
        if belongs && (tables.nodes[compiler.functions[function_id].node].flags & FLAG_RECURSIVE) == 0L {
            if wrote_name { match env.err.write(b", ") { ok(_) => (), err(_) => env.exit(3) } }
            let member = compiler.functions[function_id]
            match env.err.write(b"'") { ok(_) => (), err(_) => env.exit(3) }
            match write_token_raw(env.err, source, tokens, files[member.file].base, member.name_token) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b"'") { ok(_) => (), err(_) => env.exit(3) }
            wrote_name = true
        }
    }
    match env.err.write(b"; mark every function in the cycle 'recursive'\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn check_call_cycles(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for node in 0L..compiler.edge_first.count() { compiler.cycle_seen[node] = 0L }
    for start in 0L..compiler.functions.count() {
        if (tables.nodes[compiler.functions[start].node].flags & FLAG_RECURSIVE) != 0L { continue }
        let stamp = start + 1L
        compiler.cycle_seen[start] = stamp
        compiler.cycle_stack.clear()
        compiler.cycle_cursor.clear()
        compiler.cycle_path.clear()
        compiler.cycle_stack.push(start).unwrap()
        compiler.cycle_cursor.push(compiler.edge_first[start]).unwrap()
        var found = false
        for step in 0L..MAX_PARSE_WORK {
            if compiler.cycle_stack.count() == 0L { break }
            let top = compiler.cycle_stack.count() - 1L
            let edge_id = compiler.cycle_cursor[top]
            if edge_id < 0L {
                match compiler.cycle_stack.pop() { some(_) => (), none => () }
                match compiler.cycle_cursor.pop() { some(_) => (), none => () }
            } else {
                let edge = compiler.call_edges[edge_id]
                compiler.cycle_cursor[top] = edge.next
                if edge.to == start {
                    for path_index in 0L..compiler.cycle_stack.count() {
                        compiler.cycle_path.push(compiler.cycle_stack[path_index]).unwrap()
                    }
                    found = true
                    break
                }
                if compiler.cycle_seen[edge.to] != stamp {
                    compiler.cycle_seen[edge.to] = stamp
                    compiler.cycle_stack.push(edge.to).unwrap()
                    compiler.cycle_cursor.push(compiler.edge_first[edge.to]).unwrap()
                }
            }
        }
        if found { fail_call_cycle(env, source, files, tokens, tables, compiler) }
    }
}

fn ir_push_byte(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: byte) {
    if compiler.ir_overflow { return }
    match ir.push(value) {
        ok(_) => (),
        err(_) => { compiler.ir_overflow = true },
    }
}

fn ir_write_ascii(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: Ascii max 8192) {
    if compiler.ir_overflow { return }
    match ir.try_append(value.bytes()) {
        ok(_) => (),
        err(_) => { for index in 0L..value.len() { ir_push_byte(compiler, ir, value.bytes()[index]) } },
    }
}

fn ir_write_bytes(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: Bytes max 4096) {
    if compiler.ir_overflow { return }
    match ir.try_append(value) {
        ok(_) => (),
        err(_) => { for index in 0L..value.count() { ir_push_byte(compiler, ir, value[index]) } },
    }
}

fn ir_write_number(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: long) {
    let text = str(value)
    ir_write_ascii(compiler, ir, text)
}

fn ir_hex_digit(value: long, lowercase: bool) -> byte {
    let digits = if lowercase { b"0123456789abcdef" } else { b"0123456789ABCDEF" }
    digits[value]
}

fn ir_write_escaped_byte(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: byte) {
    let byte_value = value.to_long()
    if byte_value >= 32L && byte_value <= 126L && byte_value != 34L && byte_value != 92L {
        ir_push_byte(compiler, ir, value)
    } else {
        ir_push_byte(compiler, ir, 92)
        ir_push_byte(compiler, ir, ir_hex_digit(byte_value / 16L, false))
        ir_push_byte(compiler, ir, ir_hex_digit(byte_value % 16L, false))
    }
}

// A byte written as a backslash and two hex digits, which LLVM accepts for any byte value.
fn ir_write_hex_escaped(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, byte_value: long) {
    ir_push_byte(compiler, ir, 92)
    ir_push_byte(compiler, ir, ir_hex_digit(byte_value / 16L, false))
    ir_push_byte(compiler, ir, ir_hex_digit(byte_value % 16L, false))
}

fn ir_write_global_string(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    prefix: Ascii max 128,
    name: Bytes max 4096,
) {
    ir_write_ascii(compiler, ir, prefix)
    ir_write_number(compiler, ir, name.count() + 1L)
    ir_write_ascii(compiler, ir, " x i8] c\"")
    for index in 0L..name.count() { ir_write_escaped_byte(compiler, ir, name[index]) }
    ir_write_ascii(compiler, ir, "\\00\", align 1\n")
}

fn ir_write_test_global(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    test_index: long,
    name: Bytes max 16777217,
) {
    ir_write_ascii(compiler, ir, "@.nl.entry.test.")
    ir_write_number(compiler, ir, test_index)
    ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
    ir_write_number(compiler, ir, name.count() + 8L)
    ir_write_ascii(compiler, ir, " x i8] c\"test '")
    for index in 0L..name.count() { ir_write_escaped_byte(compiler, ir, name[index]) }
    ir_write_ascii(compiler, ir, "'\\00\", align 1\n")
}

// E3a1 begin: hooks receive compiler-emitted pointer/length tables.
fn emit_file_table_global(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    first_file_id: long,
) {
    ir_write_ascii(compiler, ir, "@.nl.file.table.")
    ir_write_number(compiler, ir, first_file_id)
    ir_write_ascii(compiler, ir, " = private constant [")
    ir_write_number(compiler, ir, files.count())
    ir_write_ascii(compiler, ir, " x { ptr, i64 }] ")
    if files.count() == 0L {
        ir_write_ascii(compiler, ir, "zeroinitializer, align 8\n")
        return
    }
    ir_write_ascii(compiler, ir, "[")
    for file_index in 0L..files.count() {
        if file_index > 0L { ir_write_ascii(compiler, ir, ", ") }
        let file_id = first_file_id + file_index
        ir_write_ascii(compiler, ir, "{ ptr, i64 } { ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.file.")
        ir_write_number(compiler, ir, file_id)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
        ir_write_number(compiler, ir, files[file_index].name.count())
        ir_write_ascii(compiler, ir, " }")
    }
    ir_write_ascii(compiler, ir, "], align 8\n")
}
// E3a1 end

fn ir_write_expect_global(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let syntax = tables.nodes[node]
    let start = syntax.start
    let end = syntax.end
    ir_write_ascii(compiler, ir, "@.nl.expect.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
    ir_write_number(compiler, ir, end - start + 1L)
    ir_write_ascii(compiler, ir, " x i8] c\"")
    for index in start..end { ir_write_escaped_byte(compiler, ir, source[index]) }
    ir_write_ascii(compiler, ir, "\\00\", align 1\n")
}

fn llvm_type_name(ty: long) -> Ascii max 8 {
    if ty == TY_INT { "i32" }
    else if ty == TY_LONG { "i64" }
    else if ty == TY_BOOL { "i1" }
    else if ty == TY_BYTE { "i32" }
    else if ty == TY_DOUBLE { "double" }
    else if ty == TY_UNIT { "void" }
    else if ty == TY_NEVER { "void" }
    else if ty == TY_ADDR || (ty >= TY_ENV && ty <= TY_ARG) { "ptr" }
    else { "i32" }
}

fn binding_for_node(compiler: CompilerTables, node: long) -> long {
    for binding in 0L..compiler.bindings.count() {
        if compiler.bindings[binding].node == node { return binding }
    }
    -1L
}

fn ir_write_value_ref(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long) {
    if node >= 0L && node < compiler.facts.count() && (compiler.facts[node].flags & FACT_CONSTANT_VALUE) != 0L {
        let value = compiler.facts[node].literal
        ir_write_number(compiler, ir, value)
    } else {
        ir_write_ascii(compiler, ir, "%v")
        ir_write_number(compiler, ir, node)
    }
}

fn native_location(anchor_kind: long, anchor_node: long, byte_offset: long) -> StorageLocation {
    StorageLocation { origin: LOCATION_NATIVE, anchor_kind, anchor_node, byte_offset, copies: 1L, index: 0L, index_node: -1L, index_stride: 0L }
}

fn storage_location_with_offset(base: StorageLocation, extra_offset: long) -> StorageLocation {
    StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node,
        byte_offset: base.byte_offset + extra_offset, copies: base.copies, index: base.index,
        index_node: base.index_node, index_stride: base.index_stride }
}

fn sum_parameter_location(compiler: CompilerTables, binding: long, base: StorageLocation) -> StorageLocation {
    if binding < 0L || binding >= compiler.bindings.count() { return base }
    let type_id = compiler.bindings[binding].ty
    if !is_sum_type(compiler, type_id) { return base }
    // The caller folded any element index into the offset, so a sum value is just at its offset.
    StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node,
        byte_offset: base.byte_offset, copies: 1L, index: 0L, index_node: -1L, index_stride: 0L }
}

fn is_indexed_sum_parameter_location(location: StorageLocation) -> bool {
    location.origin == LOCATION_NATIVE && location.anchor_kind == 3L && location.anchor_node >= 0L &&
        location.copies == -1L && location.index == -1L && location.index_node == -1L && location.index_stride > 0L
}

// E3a1 begin: resolve native-slot anchors through the per-function plan.
fn compiler_location(compiler: CompilerTables, anchor_kind: long, anchor_node: long, byte_offset: long) -> StorageLocation {
    let native = native_location(anchor_kind, anchor_node, byte_offset)
    if region_has_slot(compiler, anchor_kind, anchor_node) {
        StorageLocation { origin: LOCATION_DATA_STACK, anchor_kind, anchor_node, byte_offset, copies: 1L, index: 0L, index_node: -1L, index_stride: 0L }
    } else {
        StorageLocation { origin: native.origin, anchor_kind, anchor_node, byte_offset, copies: 1L, index: 0L, index_node: -1L, index_stride: 0L }
    }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn aggregate_destination_location(compiler: CompilerTables, kind: long, node: long) -> StorageLocation {
    if kind == 0L && node == compiler.emit_destination_node && compiler.emit_destination_kind == 1L {
        return compiler_location(compiler, 1L, compiler.emit_destination_anchor, 0L)
    }
    if kind == 0L && node == compiler.emit_destination_node && compiler.emit_destination_kind == 2L {
        return compiler_location(compiler, 9L, 0L, 0L)
    }
    if kind == 0L { compiler_location(compiler, 0L, node, 0L) }
    else if kind == 1L { compiler_location(compiler, 1L, node, 0L) }
    // User function results carry a relocatable descriptor. Core helpers keep
    // their no-growth pointer ABI and use anchor kind 4 directly.
    else if kind == 2L { compiler_location(compiler, 9L, 0L, 0L) }
    else { compiler_location(compiler, 2L, node, 0L) }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn aggregate_source_location(compiler: CompilerTables, kind: long, node: long) -> StorageLocation {
    if kind == 0L { compiler_location(compiler, 0L, node, 0L) }
    else if kind == 1L { compiler_location(compiler, 1L, node, 0L) }
    else if kind == 2L {
        let location = compiler_location(compiler, 3L, node, 0L)
        sum_parameter_location(compiler, node, location)
    }
    else { compiler_location(compiler, 2L, node, 0L) }
}
// E3a1 end

fn direct_call_argument_source_location(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> StorageLocation {
    let kind = aggregate_source_kind(tables, compiler, node)
    let source_node = aggregate_source_id(tables, compiler, node)
    if kind == 3L && tables.nodes[node].kind == NodeKind.Field &&
        place_root_binding(tables, compiler, node) >= 0L {
        place_storage_location(tables, compiler, node)
    } else {
        aggregate_source_location(compiler, kind, source_node)
    }
}

recursive fn place_storage_location(tables: ParseTables, compiler: CompilerTables, node: long) -> StorageLocation {
    if node < 0L { return compiler_location(compiler, 0L, node, 0L) }
    let kind = tables.nodes[node].kind
    if kind == NodeKind.Name {
        let binding = compiler.facts[node].binding
        if binding_is_view(compiler, binding) {
            let loop_node = compiler.bindings[binding].node
            let collection = compiler.child_first[loop_node]
            let collection_type = compiler.facts[collection].ty
            let element_type = collection_element_type(compiler, collection_type)
            let capacity = collection_capacity(compiler, collection_type)
            let base_offset = collection_element_base_offset(compiler, collection_type)
            let element_stride = if type_kind(compiler, collection_type) == TYPE_KIND_ASCII || type_kind(compiler, collection_type) == TYPE_KIND_BYTES { 1L }
                else { value_type_size(compiler, element_type) }
            let base = collection_value_location(tables, compiler, collection)
            if is_aggregate_type(compiler, element_type) {
                StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node, byte_offset: base.byte_offset + base_offset, copies: 1L, index: 0L, index_node: -2L - loop_node, index_stride: element_stride }
            } else {
                StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node, byte_offset: base.byte_offset + base_offset, copies: 1L, index: 0L, index_node: -2L - loop_node, index_stride: element_stride }
            }
        } else if binding >= 0L && compiler.bindings[binding].parameter && is_aggregate_type(compiler, compiler.bindings[binding].ty) {
            let location = compiler_location(compiler, 3L, binding, 0L)
            sum_parameter_location(compiler, binding, StorageLocation { origin: location.origin, anchor_kind: location.anchor_kind, anchor_node: location.anchor_node, byte_offset: location.byte_offset, copies: -1L, index: -1L, index_node: -1L, index_stride: 0L })
        } else if binding >= 0L && compiler.bindings[binding].parameter { compiler_location(compiler, 3L, binding, 0L) }
        else { compiler_location(compiler, 1L, binding, 0L) }
    } else if kind == NodeKind.Field {
        var root = node
        for root_step in 0L..MAX_TREE_NODES {
            if root < 0L || tables.nodes[root].kind != NodeKind.Field { break }
            root = compiler.child_first[root]
        }
        if root >= 0L && tables.nodes[root].kind == NodeKind.Name {
            let root_binding = compiler.facts[root].binding
            if root_binding >= 0L && compiler.bindings[root_binding].parameter && is_aggregate_type(compiler, compiler.bindings[root_binding].ty) {
                let receiver = compiler.child_first[node]
                if receiver < 0L { return compiler_location(compiler, 2L, node, 0L) }
                let base = place_storage_location(tables, compiler, receiver)
                let receiver_type = compiler.facts[receiver].ty
                let field_index = compiler.facts[node].literal
                if type_kind(compiler, receiver_type) != TYPE_KIND_STRUCT || field_index < 0L {
                    return compiler_location(compiler, 2L, node, 0L)
                }
                let field = compiler.struct_fields[field_index]
                return StorageLocation {
                    origin: base.origin,
                    anchor_kind: base.anchor_kind,
                    anchor_node: base.anchor_node,
                    byte_offset: base.byte_offset + field.offset,
                    copies: 1L,
                    index: 0L,
                    index_node: -1L,
                    index_stride: 0L,
                }
            }
        }
        let receiver = compiler.child_first[node]
        if receiver < 0L { return compiler_location(compiler, 0L, node, 0L) }
        let base = place_storage_location(tables, compiler, receiver)
        let receiver_type = compiler.facts[receiver].ty
        let field_index = compiler.facts[node].literal
        if type_kind(compiler, receiver_type) != TYPE_KIND_STRUCT || field_index < 0L { return compiler_location(compiler, 2L, node, 0L) }
        let field = compiler.struct_fields[field_index]
        let field_offset = if base.copies > 1L && base.index_node != -1L {
            let field_start = type_record(compiler, receiver_type).field_start
            collection_field_lane_offset(compiler, receiver_type, base.copies, field_index - field_start)
        } else { field.offset }
        let stride = base.index_stride
        StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node, byte_offset: base.byte_offset + field_offset, copies: base.copies, index: base.index, index_node: base.index_node, index_stride: stride }
    } else if kind == NodeKind.Index {
        let receiver = compiler.child_first[node]
        let index_node = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
        if receiver < 0L || index_node < 0L { return compiler_location(compiler, 2L, node, 0L) }
        let collection_type = compiler.facts[receiver].ty
        let element_type = collection_element_type(compiler, collection_type)
        let capacity = collection_capacity(compiler, collection_type)
        let base_offset = collection_element_base_offset(compiler, collection_type)
        let base = place_storage_location(tables, compiler, receiver)
        if element_type < 0L || capacity < 0L || base_offset < 0L { return compiler_location(compiler, 2L, node, 0L) }
        if is_aggregate_type(compiler, element_type) {
            StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node, byte_offset: base.byte_offset + base_offset, copies: 1L, index: 0L, index_node, index_stride: value_type_size(compiler, element_type) }
        } else {
            StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node, byte_offset: base.byte_offset + base_offset, copies: 1L, index: 0L, index_node, index_stride: value_type_size(compiler, element_type) }
        }
    } else { compiler_location(compiler, 0L, node, 0L) }
}



// E3a1 begin: materialize a movable address immediately before its use.
fn emit_location_pointer_materialization(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    location: StorageLocation,
    ) -> long {
    if !is_indexed_sum_parameter_location(location) && (location.copies != 1L || location.index != 0L) {
        compiler.ir_overflow = true
        return -1L
    }
    let serial = next_location_serial(ir)
    if location.origin == LOCATION_DATA_STACK {
        let slot = region_find_slot(compiler, location.anchor_kind, location.anchor_node)
        if slot < 0L { compiler.ir_overflow = true; return -1L }
        if location.byte_offset == 0L { ir_write_ascii(compiler, ir, "  %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %region.offset."); ir_write_number(compiler, ir, slot); ir_write_ascii(compiler, ir, ", 0\n") }
        else { ir_write_ascii(compiler, ir, "  %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %region.offset."); ir_write_number(compiler, ir, slot); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.byte_offset); ir_write_ascii(compiler, ir, "\n") }
        ir_write_ascii(compiler, ir, "  %loc.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = call ptr "); emit_context_runtime_symbol(compiler, ir, "nl_context_current_base", "nlc_context_current_base"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  %loc.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %loc.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", i64 %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, "\n")
        return serial
    } else if location.anchor_kind == 3L && !is_indexed_sum_parameter_location(location) && compiler.c_runtime && parameter_has_pointer(compiler, location.anchor_node) {
        ir_write_ascii(compiler, ir, "  %loc.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %arg.ptr."); ir_write_number(compiler, ir, location.anchor_node)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
        return serial
    } else if location.anchor_kind == 3L || location.anchor_kind == 9L {
        if location.anchor_kind == 3L {
            ir_write_ascii(compiler, ir, "  %loc.anchor."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = select i1 true, ptr %arg.anchor."); ir_write_number(compiler, ir, location.anchor_node); ir_write_ascii(compiler, ir, ", ptr %arg.anchor."); ir_write_number(compiler, ir, location.anchor_node); ir_push_byte(compiler, ir, 10)
            if is_indexed_sum_parameter_location(location) {
                ir_write_ascii(compiler, ir, "  %loc.offset.index."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = mul i64 %arg.index."); ir_write_number(compiler, ir, location.anchor_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.index_stride); ir_push_byte(compiler, ir, 10)
                ir_write_ascii(compiler, ir, "  %loc.offset.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %arg.offset."); ir_write_number(compiler, ir, location.anchor_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
                ir_write_ascii(compiler, ir, "  %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %loc.offset.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", %loc.offset.index."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
            } else {
                ir_write_ascii(compiler, ir, "  %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %arg.offset."); ir_write_number(compiler, ir, location.anchor_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
            }
        } else {
            ir_write_ascii(compiler, ir, "  %loc.anchor."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = select i1 true, ptr %nl.dest.anchor, ptr %nl.dest.anchor\n  %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %nl.dest.offset, "); ir_write_number(compiler, ir, location.byte_offset); ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "  %loc.is.stack."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = icmp eq ptr %loc.anchor."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", null\n  %loc.native.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %loc.anchor."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", i64 %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, "\n  %loc.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = call ptr "); emit_context_runtime_symbol(compiler, ir, "nl_context_current_base", "nlc_context_current_base"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  %loc.stack.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %loc.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", i64 %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, "\n  %loc.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = select i1 %loc.is.stack."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %loc.stack.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %loc.native.pointer."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
        return serial
    } else if location.byte_offset != 0L {
        let base_location = StorageLocation {
            origin: location.origin,
            anchor_kind: location.anchor_kind,
            anchor_node: location.anchor_node,
            byte_offset: 0L,
            copies: 1L,
            index: 0L,
            index_node: -1L,
            index_stride: 0L,
        }
        ir_write_ascii(compiler, ir, "  %loc.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, base_location, -1L)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
        serial
    } else { -1L }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_location_pointer_reference(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, location: StorageLocation, serial: long) {
    if serial >= 0L { ir_write_ascii(compiler, ir, "%loc.pointer."); ir_write_number(compiler, ir, serial) }
    else if location.anchor_kind == 0L { ir_write_ascii(compiler, ir, "%agg."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 1L { ir_write_ascii(compiler, ir, "%local."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 2L { ir_write_ascii(compiler, ir, "%addr."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 10L { ir_write_ascii(compiler, ir, "%optional.call.receiver.snapshot."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 4L { ir_write_ascii(compiler, ir, "%nl.dest") }
    else if location.anchor_kind == 5L { ir_write_ascii(compiler, ir, "%nl.source") }
    else if location.anchor_kind == 6L { ir_write_ascii(compiler, ir, "%nl.left") }
    else if location.anchor_kind == 7L { ir_write_ascii(compiler, ir, "%nl.right") }
    else if location.anchor_kind == 8L { ir_write_ascii(compiler, ir, "%nl.value") }
    else { compiler.ir_overflow = true }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_location_pointer(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, location: StorageLocation) {
    let serial = emit_location_pointer_materialization(compiler, ir, location)
    emit_location_pointer_reference(compiler, ir, location, serial)
}
// E3a1 end


fn lower_scope_exit(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    scope_id: long,
    exit_kind: long,
    target_kind: long,
    target: long,
    value_ty: long,
    value_node: long,
) {
    // One invocation lowers one exited scope. A multi-scope exit invokes this
    // in innermost-first order; E2i has no cleanup records to run.
    for cleanup_step in 0L..compiler.exit_cleanups.count() {
        let cleanup = compiler.exit_cleanups[compiler.exit_cleanups.count() - cleanup_step - 1L]
        if cleanup.scope_id == scope_id { emit_registered_exit_cleanup(compiler, ir, cleanup) }
    }
    // E3a1 begin
    // Restore the incoming top on function exits. Loop resets are emitted at
    // branch sites, which know the loop body's region scope.
    if !compiler.core_mode && (exit_kind == EXIT_RETURN || exit_kind == EXIT_RETURN_VALUE || exit_kind == EXIT_TEST_SUCCESS || exit_kind == EXIT_TEST_FAILURE || exit_kind == EXIT_FALLTHROUGH) {
        if compiler.region_max_size > 0L {
            ir_write_ascii(compiler, ir, "  call void @nl_context_set_top_offset(ptr %nl.ctx, i64 %nl.top)\n")
        }
    } else { () }
    // E3a1 end
    if exit_kind == EXIT_RETURN { ir_write_ascii(compiler, ir, "  ret void\n") }
    else if exit_kind == EXIT_RETURN_VALUE {
        ir_write_ascii(compiler, ir, "  ret "); ir_write_ascii(compiler, ir, llvm_type_name(value_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, "\n")
    } else if exit_kind == EXIT_TEST_SUCCESS { ir_write_ascii(compiler, ir, "  ret i32 0\n") }
    else if exit_kind == EXIT_TEST_FAILURE { ir_write_ascii(compiler, ir, "  ret i32 1\n") }
    else if exit_kind == EXIT_FALLTHROUGH {
        if target_kind == 1L { ir_write_ascii(compiler, ir, "  ret i32 0\n") }
        else if value_ty == TY_UNIT || value_ty == TY_NEVER || is_aggregate_type(compiler, value_ty) { ir_write_ascii(compiler, ir, "  ret void\n") }
        else { ir_write_ascii(compiler, ir, "  ret "); ir_write_ascii(compiler, ir, llvm_type_name(value_ty)); ir_write_ascii(compiler, ir, " 0\n") }
    } else if exit_kind == EXIT_BREAK || exit_kind == EXIT_CONTINUE {
        if target_kind == 1L {
            if exit_kind == EXIT_BREAK { ir_write_ascii(compiler, ir, "  br label %while.end.") }
            else { ir_write_ascii(compiler, ir, "  br label %while.step.") }
        } else if exit_kind == EXIT_BREAK { ir_write_ascii(compiler, ir, "  br label %for.end.") }
        else { ir_write_ascii(compiler, ir, "  br label %for.increment.") }
        ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, "\n")
    } else if exit_kind == EXIT_BRANCH {
        ir_write_ascii(compiler, ir, "  br label %")
        if target_kind == BRANCH_IF_END { ir_write_ascii(compiler, ir, "if.end.") }
        else if target_kind == BRANCH_IF_EXPR_END { ir_write_ascii(compiler, ir, "if.expr.end.") }
        else if target_kind == BRANCH_FOR_INCREMENT { ir_write_ascii(compiler, ir, "for.increment.") }
        else if target_kind == BRANCH_WHILE_STEP { ir_write_ascii(compiler, ir, "while.step.") }
        else { compiler.ir_overflow = true }
        ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, "\n")
    } else { compiler.ir_overflow = true }
}

// E3a1 begin: shared compiler integration.
fn emit_layout_address(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    result_node: long,
    location: StorageLocation,
) {
    if is_indexed_sum_parameter_location(location) {
        let pointer_location = StorageLocation {
            origin: location.origin,
            anchor_kind: location.anchor_kind,
            anchor_node: location.anchor_node,
            byte_offset: 0L,
            copies: location.copies,
            index: location.index,
            index_node: location.index_node,
            index_stride: location.index_stride,
        }
        let pointer_serial = emit_location_pointer_materialization(compiler, ir, pointer_location)
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, result_node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, pointer_location, pointer_serial)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
        return
    }
    if location.origin != LOCATION_NATIVE || location.copies != 1L || location.index != 0L {
        if location.origin != LOCATION_DATA_STACK || location.copies != 1L || location.index != 0L { compiler.ir_overflow = true; return }
    }
    let pointer_location = compiler_location(compiler, location.anchor_kind, location.anchor_node, 0L)
    let pointer_serial = emit_location_pointer_materialization(compiler, ir, pointer_location)
    ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, result_node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
    emit_location_pointer_reference(compiler, ir, pointer_location, pointer_serial)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_write_ascii(compiler, ir, "\n")
}
// E3a1 end

recursive fn emit_collection_field_path_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    address_id: long,
) -> bool {
    compiler.type_walk.clear()
    var current = node
    for path_step in 0L..MAX_TREE_NODES {
        if current < 0L || tables.nodes[current].kind != NodeKind.Field { break }
        compiler.type_walk.push(TypeWalkFrame { type_index: current, field_index: -1L, size: 0L, align: 0L, case_index: 0L, max_size: 0L }).unwrap()
        current = compiler.child_first[current]
    }
    if current < 0L || tables.nodes[current].kind != NodeKind.Index {
        compiler.type_walk.clear()
        return false
    }
    let collection_node = compiler.child_first[current]
    let index_node = if collection_node >= 0L { compiler.child_next[collection_node] } else { -1L }
    if collection_node < 0L || index_node < 0L { compiler.type_walk.clear(); return false }
    let collection_type = compiler.facts[collection_node].ty
    let element_type = collection_element_type(compiler, collection_type)
    let copies = collection_capacity(compiler, collection_type)
    var byte_offset = collection_element_base_offset(compiler, collection_type)
    if type_kind(compiler, element_type) != TYPE_KIND_STRUCT || copies < 0L || byte_offset < 0L { compiler.type_walk.clear(); return false }
    for path_index in 0L..compiler.type_walk.count() {
        let field_node = compiler.type_walk[compiler.type_walk.count() - path_index - 1L].type_index
        let receiver = compiler.child_first[field_node]
        let receiver_type = compiler.facts[receiver].ty
        let field_index = compiler.facts[field_node].literal
        let field_number = field_index - type_record(compiler, receiver_type).field_start
        let field_offset = collection_field_lane_offset(compiler, receiver_type, copies, field_number)
        if field_offset < 0L { compiler.ir_overflow = true; compiler.type_walk.clear(); return true }
        byte_offset += field_offset
    }
    var location = collection_value_location(tables, compiler, collection_node)
    if tables.nodes[collection_node].kind == NodeKind.Field {
        let collection_address = emit_late_place_address(tables, compiler, ir, collection_node)
        location = compiler_location(compiler, 2L, collection_address, 0L)
    }
    let pointer = emit_location_pointer_materialization(compiler, ir, location)
    let stride = value_type_size(compiler, element_type)
    if stride > 0L {
        ir_write_ascii(compiler, ir, "  %coll.field.index.bytes."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = mul i64 "); ir_write_value_ref(compiler, ir, index_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.field.index.offset."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, byte_offset); ir_write_ascii(compiler, ir, ", %coll.field.index.bytes."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", i64 %coll.field.index.offset."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
    } else {
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, byte_offset); ir_push_byte(compiler, ir, 10)
    }
    compiler.type_walk.clear()
    true
}

recursive fn emit_dynamic_group_size_for_descriptor(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies_binding: long,
) -> long {
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        var offset_serial = -1L
        var alignment = 1L
        for field_number in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_number]
            let field_align = value_type_align(compiler, field.ty)
            if field_align < 0L { compiler.ir_overflow = true; return -1L }
            if field_align > alignment { alignment = field_align }
            let rounded = next_location_serial(ir)
            ir_write_ascii(compiler, ir, "  %coll.desc.align.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = add i64 ")
            if offset_serial >= 0L { ir_write_ascii(compiler, ir, "%coll.desc.group.add."); ir_write_number(compiler, ir, offset_serial) }
            else { ir_write_ascii(compiler, ir, "0") }
            ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, field_align - 1L); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "  %coll.desc.align.mask."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = and i64 %coll.desc.align.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, ", -"); ir_write_number(compiler, ir, field_align); ir_push_byte(compiler, ir, 10)
            let size_serial = emit_dynamic_group_size_for_descriptor(compiler, ir, field.ty, copies_binding)
            if size_serial < 0L { return -1L }
            let added = next_location_serial(ir)
            ir_write_ascii(compiler, ir, "  %coll.desc.group.add."); ir_write_number(compiler, ir, added); ir_write_ascii(compiler, ir, " = add i64 %coll.desc.align.mask."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, ", %coll.desc.group.size."); ir_write_number(compiler, ir, size_serial); ir_push_byte(compiler, ir, 10)
            offset_serial = added
        }
        let rounded = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.final.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = add i64 ")
        if offset_serial >= 0L { ir_write_ascii(compiler, ir, "%coll.desc.group.add."); ir_write_number(compiler, ir, offset_serial) }
        else { ir_write_ascii(compiler, ir, "0") }
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, alignment - 1L); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.desc.group.size."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = and i64 %coll.desc.final.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, ", -"); ir_write_number(compiler, ir, alignment); ir_push_byte(compiler, ir, 10)
        rounded
    } else if kind == TYPE_KIND_ARRAY || collection_kind_is_list(kind) {
        // E3a2 forbids a collection-bearing struct as a collection element,
        // so descriptors that reach this branch have the standalone geometry
        // (one copy). Its inline collection storage has a static exact size.
        let size = value_type_size(compiler, type_id)
        if size < 0L { compiler.ir_overflow = true; return -1L }
        let serial = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.group.size."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_number(compiler, ir, size); ir_push_byte(compiler, ir, 10)
        serial
    } else {
        let size = value_type_size(compiler, type_id)
        if size < 0L { compiler.ir_overflow = true; return -1L }
        let serial = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.group.size."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = mul i64 %arg.copies."); ir_write_number(compiler, ir, copies_binding); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, size); ir_push_byte(compiler, ir, 10)
        serial
    }
}

fn emit_dynamic_field_lane_offset_for_descriptor(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies_binding: long,
    wanted_field: long,
) -> long {
    if type_kind(compiler, type_id) != TYPE_KIND_STRUCT { compiler.ir_overflow = true; return -1L }
    let record = type_record(compiler, type_id)
    if wanted_field < 0L || wanted_field >= record.field_count { compiler.ir_overflow = true; return -1L }
    var offset_serial = -1L
    for field_number in 0L..wanted_field + 1L {
        let field = compiler.struct_fields[record.field_start + field_number]
        let field_align = value_type_align(compiler, field.ty)
        let rounded = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.field.align.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = add i64 ")
        if offset_serial >= 0L { ir_write_ascii(compiler, ir, "%coll.desc.field.offset."); ir_write_number(compiler, ir, offset_serial) }
        else { ir_write_ascii(compiler, ir, "0") }
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, field_align - 1L); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.desc.field.offset."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = and i64 %coll.desc.field.align.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, ", -"); ir_write_number(compiler, ir, field_align); ir_push_byte(compiler, ir, 10)
        if field_number == wanted_field { return rounded }
        let size_serial = emit_dynamic_group_size_for_descriptor(compiler, ir, field.ty, copies_binding)
        if size_serial < 0L { return -1L }
        let added = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.field.offset."); ir_write_number(compiler, ir, added); ir_write_ascii(compiler, ir, " = add i64 %coll.desc.field.offset."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, ", %coll.desc.group.size."); ir_write_number(compiler, ir, size_serial); ir_push_byte(compiler, ir, 10)
        offset_serial = added
    }
    compiler.ir_overflow = true
    -1L
}

fn emit_parameter_field_path_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    address_id: long,
) -> bool {
    compiler.type_walk.clear()
    var current = node
    for path_step in 0L..MAX_TREE_NODES {
        if current < 0L || tables.nodes[current].kind != NodeKind.Field { break }
        compiler.type_walk.push(TypeWalkFrame { type_index: current, field_index: -1L, size: 0L, align: 0L, case_index: 0L, max_size: 0L }).unwrap()
        current = compiler.child_first[current]
    }
    if current < 0L || tables.nodes[current].kind != NodeKind.Name {
        compiler.type_walk.clear()
        return false
    }
    let binding = compiler.facts[current].binding
    let is_view = binding_is_view(compiler, binding)
    if !is_view && (binding < 0L || !compiler.bindings[binding].parameter || !is_aggregate_type(compiler, compiler.bindings[binding].ty)) {
        compiler.type_walk.clear()
        return false
    }
    // The element is one plain slot: a field is at its offset inside the slot, and the element
    // itself is `index` slots from the start of the collection (a loop variable's index is the
    // loop counter, a parameter's is passed in).
    let slot_size = value_type_size(compiler, compiler.bindings[binding].ty)
    var field_type = compiler.bindings[binding].ty
    var byte_offset = 0L
    if is_view {
        let loop_node = compiler.bindings[binding].node
        let collection = compiler.child_first[loop_node]
        byte_offset = collection_element_base_offset(compiler, compiler.facts[collection].ty)
    }
    for path_index in 0L..compiler.type_walk.count() {
        let field_node = compiler.type_walk[compiler.type_walk.count() - path_index - 1L].type_index
        let field_number = compiler.facts[field_node].literal - type_record(compiler, field_type).field_start
        let field_offset = collection_field_lane_offset(compiler, field_type, 1L, field_number)
        if field_offset < 0L || slot_size < 0L { compiler.type_walk.clear(); compiler.ir_overflow = true; return true }
        byte_offset += field_offset
        field_type = compiler.facts[field_node].ty
    }
    let view_loop_node = compiler.bindings[binding].node
    ir_write_ascii(compiler, ir, "  %coll.desc.element.index."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = mul i64 ")
    if is_view {
        ir_write_ascii(compiler, ir, "%for.each.current."); ir_write_number(compiler, ir, view_loop_node)
    } else {
        ir_write_ascii(compiler, ir, "%arg.index."); ir_write_number(compiler, ir, binding)
    }
    ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, slot_size); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %coll.desc.path.offset."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = add i64 %coll.desc.element.index.")
    ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, byte_offset); ir_push_byte(compiler, ir, 10)
    var base = compiler_location(compiler, 3L, binding, 0L)
    if is_view {
        let collection = compiler.child_first[compiler.bindings[binding].node]
        let collection_base = collection_value_location(tables, compiler, collection)
        base = compiler_location(compiler, collection_base.anchor_kind, collection_base.anchor_node, collection_base.byte_offset)
    }
    let pointer = emit_location_pointer_materialization(compiler, ir, base)
    ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
    emit_location_pointer_reference(compiler, ir, base, pointer)
    ir_write_ascii(compiler, ir, ", i64 %coll.desc.path.offset."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
    compiler.type_walk.clear()
    true
}

fn emit_collection_view_name_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) -> bool {
    let binding = compiler.facts[node].binding
    if !binding_is_view(compiler, binding) || is_aggregate_type(compiler, compiler.bindings[binding].ty) { return false }
    let loop_node = compiler.bindings[binding].node
    let collection = compiler.child_first[loop_node]
    let collection_type = compiler.facts[collection].ty
    let element_type = collection_element_type(compiler, collection_type)
    let stride = if type_kind(compiler, collection_type) == TYPE_KIND_ASCII || type_kind(compiler, collection_type) == TYPE_KIND_BYTES { 1L }
        else { value_type_size(compiler, element_type) }
    let base_offset = collection_element_base_offset(compiler, collection_type)
    if stride < 0L || base_offset < 0L { compiler.ir_overflow = true; return true }
    let base = collection_value_location(tables, compiler, collection)
    let pointer_location = compiler_location(compiler, base.anchor_kind, base.anchor_node, base.byte_offset)
    let pointer = emit_location_pointer_materialization(compiler, ir, pointer_location)
    ir_write_ascii(compiler, ir, "  %coll.view.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = mul i64 %for.each.current."); ir_write_number(compiler, ir, loop_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %coll.view.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, ", %coll.view.bytes."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, pointer_location, pointer); ir_write_ascii(compiler, ir, ", i64 %coll.view.offset."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    true
}

