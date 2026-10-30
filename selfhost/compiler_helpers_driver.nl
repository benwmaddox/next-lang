fn register_type_helper(compiler: write CompilerTables, type_id: long, operation: long) {
    if type_id < 0L || type_id >= type_count(compiler) { return }
    let bit = if operation == HELPER_COPY { 1L }
        else if operation == HELPER_EQUAL { 2L }
        else if operation == HELPER_PRINT { 4L }
        else if operation == HELPER_FILL { 8L }
        else if operation == HELPER_DEFAULT { 16L }
        else { 0L }
    if bit != 0L && !has_type_helper(compiler, type_id, operation) {
        set_type_helper_mask(compiler, type_id, type_helper_mask(compiler, type_id) + bit)
    }
}

fn type_has_registered_helper(compiler: CompilerTables, type_id: long) -> bool {
    has_type_helper(compiler, type_id, HELPER_COPY) ||
        has_type_helper(compiler, type_id, HELPER_EQUAL) ||
        has_type_helper(compiler, type_id, HELPER_PRINT) ||
        has_type_helper(compiler, type_id, HELPER_FILL) ||
        has_type_helper(compiler, type_id, HELPER_DEFAULT)
}

fn register_exit_cleanup(compiler: write CompilerTables, scope_id: long, kind: long, owner: long) {
    compiler.exit_cleanups.push(ExitCleanupRecord { scope_id, kind, owner }).unwrap()
}

fn emit_registered_exit_cleanup(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    cleanup: ExitCleanupRecord,
) {
    // E2i registers none. The cleanup owner adds its kind here and keeps its
    // action payload in owner; unrecognized records fail closed meanwhile.
    if cleanup.kind != 0L { compiler.ir_overflow = true }
}

fn add_type_helper_flag(compiler: write CompilerTables, ty: long, flag: long) {
    if !is_aggregate_type(compiler, ty) { return }
    if flag == 1L { register_type_helper(compiler, ty, HELPER_COPY) }
    else if flag == 2L { register_type_helper(compiler, ty, HELPER_EQUAL) }
    else if flag == 4L { register_type_helper(compiler, ty, HELPER_PRINT) }
    else { () }
}

fn mark_struct_helpers(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for type_id in 0L..type_count(compiler) { set_type_helper_mask(compiler, type_id, 0L) }
    for type_index in 0L..struct_type_count(compiler) {
        if struct_has_defaults(compiler, type_index) {
            let type_id = struct_type_id(compiler, type_index)
            register_type_helper(compiler, type_id, HELPER_FILL)
            register_type_helper(compiler, type_id, HELPER_DEFAULT)
        }
    }
    for function_id in 0L..compiler.functions.count() {
        let result_ty = compiler.functions[function_id].result_ty
        add_type_helper_flag(compiler, result_ty, 1L)
    }
    for field_index in 0L..compiler.struct_fields.count() {
        let field = compiler.struct_fields[field_index]
        if field.default_node >= 0L && is_aggregate_type(compiler, field.ty) { add_type_helper_flag(compiler, field.ty, 1L) }
    }
    for node in 0L..tables.nodes.count() {
        let syntax = tables.nodes[node]
        if syntax.kind == NodeKind.Let {
            let binding = compiler.facts[node].binding
            if binding >= 0L {
                let ty = compiler.bindings[binding].ty
                add_type_helper_flag(compiler, ty, 1L)
            }
        } else if syntax.kind == NodeKind.Assign {
            let target = compiler.child_first[node]
            if target >= 0L {
                let ty = compiler.facts[target].ty
                add_type_helper_flag(compiler, ty, 1L)
            }
        } else if syntax.kind == NodeKind.Return || syntax.kind == NodeKind.ReturnStatement {
            let value = compiler.child_first[node]
            if value >= 0L {
                let ty = compiler.facts[value].ty
                add_type_helper_flag(compiler, ty, 1L)
            }
        } else if syntax.kind == NodeKind.InitializerField || syntax.kind == NodeKind.If || syntax.kind == NodeKind.Block {
            let ty = compiler.facts[node].ty
            add_type_helper_flag(compiler, ty, 1L)
        } else if syntax.kind == NodeKind.PatternBinding {
            let binding_ty = compiler.facts[node].ty
            add_type_helper_flag(compiler, binding_ty, 1L)
        } else if syntax.kind == NodeKind.Call || syntax.kind == NodeKind.QualifiedCase || syntax.kind == NodeKind.OptionalCall {
            let resolved_type = compiler.facts[node].ty
            let is_constructor = syntax.kind == NodeKind.QualifiedCase ||
                (syntax.kind == NodeKind.Call && compiler.facts[node].function < 0L && is_sum_type(compiler, resolved_type))
            let file_index = node_file_index(tables.nodes, files, node)
            let is_print = syntax.kind == NodeKind.Call && compiler.facts[node].function < 0L && !is_constructor &&
                token_is_word_at(source, tokens, files, file_index, syntax.token, "print")
            var argument = compiler.child_first[node]
            for argument_step in 0L..tables.nodes[node].subtree {
                if argument < 0L { break }
                let argument_ty = compiler.facts[argument].ty
                if is_aggregate_type(compiler, argument_ty) {
                    if is_print { add_type_helper_flag(compiler, argument_ty, 4L) }
                    else if is_constructor || tables.nodes[argument].kind == NodeKind.Name || tables.nodes[argument].kind == NodeKind.Field {
                        add_type_helper_flag(compiler, argument_ty, 1L)
                    } else { () }
                }
                argument = compiler.child_next[argument]
            }
        } else if syntax.kind == NodeKind.Binary && (syntax.flags == 8L || syntax.flags == 9L) {
            let left = compiler.child_first[node]
            let right = if left >= 0L { compiler.child_next[left] } else { -1L }
            if left >= 0L && is_aggregate_type(compiler, compiler.facts[left].ty) {
                let ty = compiler.facts[left].ty
                add_type_helper_flag(compiler, ty, 2L)
                if tables.nodes[left].kind == NodeKind.Name || tables.nodes[left].kind == NodeKind.Field { add_type_helper_flag(compiler, ty, 1L) }
                if right >= 0L && (tables.nodes[right].kind == NodeKind.Name || tables.nodes[right].kind == NodeKind.Field) { add_type_helper_flag(compiler, ty, 1L) }
            }
        } else if syntax.kind == NodeKind.Binary && syntax.flags == 21L {
            let result_ty = compiler.facts[node].ty
            add_type_helper_flag(compiler, result_ty, 1L)
        } else if syntax.kind == NodeKind.Try || syntax.kind == NodeKind.MethodCall || syntax.kind == NodeKind.OptionalCall || syntax.kind == NodeKind.Match {
            let result_ty = compiler.facts[node].ty
            add_type_helper_flag(compiler, result_ty, 1L)
        } else { () }
        if syntax.kind == NodeKind.Expect {
            let expression = compiler.child_first[node]
            if expression >= 0L && tables.nodes[expression].kind == NodeKind.Binary && tables.nodes[expression].flags >= 8L && tables.nodes[expression].flags <= 13L {
                let left = compiler.child_first[expression]
                if left >= 0L {
                    let ty = compiler.facts[left].ty
                    add_type_helper_flag(compiler, ty, 4L)
                }
            }
        }
    }
    for pass in 0L..type_count(compiler) {
        let helpers_before = type_helper_mask_sum(compiler)
        for type_id in 0L..type_count(compiler) {
            if type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
                let type_info = type_record(compiler, type_id)
                for offset in 0L..type_info.field_count {
                    let child_ty = compiler.struct_fields[type_info.field_start + offset].ty
                    if !is_aggregate_type(compiler, child_ty) { continue }
                    if has_type_helper(compiler, type_id, HELPER_COPY) { register_type_helper(compiler, child_ty, HELPER_COPY) }
                    if has_type_helper(compiler, type_id, HELPER_EQUAL) { register_type_helper(compiler, child_ty, HELPER_EQUAL) }
                    if has_type_helper(compiler, type_id, HELPER_PRINT) { register_type_helper(compiler, child_ty, HELPER_PRINT) }
                }
            } else if type_kind(compiler, type_id) == TYPE_KIND_ENUM {
                let type_info = type_record(compiler, type_id)
                for case_offset in 0L..type_info.field_count {
                    let case = compiler.enum_cases[type_info.field_start + case_offset]
                    for part_offset in 0L..case.payload_count {
                        let child_ty = compiler.enum_payloads[case.payload_start + part_offset].ty
                        if !is_aggregate_type(compiler, child_ty) { continue }
                        if has_type_helper(compiler, type_id, HELPER_COPY) { register_type_helper(compiler, child_ty, HELPER_COPY) }
                        if has_type_helper(compiler, type_id, HELPER_EQUAL) { register_type_helper(compiler, child_ty, HELPER_EQUAL) }
                        if has_type_helper(compiler, type_id, HELPER_PRINT) { register_type_helper(compiler, child_ty, HELPER_PRINT) }
                    }
                }
            } else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || collection_kind_is_list(type_kind(compiler, type_id)) {
                let child_ty = collection_element_type(compiler, type_id)
                if type_kind(compiler, child_ty) == TYPE_KIND_STRUCT {
                    let element = type_record(compiler, child_ty)
                    for field_offset in 0L..element.field_count {
                        let field_ty = compiler.struct_fields[element.field_start + field_offset].ty
                        if collection_helper_leaf(type_kind(compiler, field_ty)) {
                            // Collection operations can copy, compare, or
                            // print a direct text leaf even when no whole-
                            // collection helper is otherwise requested.
                            register_type_helper(compiler, field_ty, HELPER_COPY)
                            register_type_helper(compiler, field_ty, HELPER_EQUAL)
                            register_type_helper(compiler, field_ty, HELPER_PRINT)
                        }
                    }
                }
                if collection_helper_leaf(type_kind(compiler, child_ty)) {
                    register_type_helper(compiler, child_ty, HELPER_COPY)
                    register_type_helper(compiler, child_ty, HELPER_EQUAL)
                    register_type_helper(compiler, child_ty, HELPER_PRINT)
                }
                if is_aggregate_type(compiler, child_ty) {
                    if has_type_helper(compiler, type_id, HELPER_COPY) { register_type_helper(compiler, child_ty, HELPER_COPY) }
                    if has_type_helper(compiler, type_id, HELPER_EQUAL) { register_type_helper(compiler, child_ty, HELPER_EQUAL) }
                    if has_type_helper(compiler, type_id, HELPER_PRINT) { register_type_helper(compiler, child_ty, HELPER_PRINT) }
                }
            } else { () }
        }
        if type_helper_mask_sum(compiler) == helpers_before { break }
    }
}

fn propagate_sum_type_helpers(compiler: write CompilerTables) {
    for pass in 0L..type_count(compiler) {
        let helpers_before = type_helper_mask_sum(compiler)
        for type_id in 0L..type_count(compiler) {
            let kind = type_kind(compiler, type_id)
            if kind != TYPE_KIND_OPTION && kind != TYPE_KIND_RESULT { continue }
            for tag in 0L..2L {
                let part_count = sum_case_payload_count(compiler, type_id, tag)
                for part in 0L..part_count {
                    let child_ty = sum_case_payload_type(compiler, type_id, tag, part)
                    if !is_aggregate_type(compiler, child_ty) { continue }
                    if has_type_helper(compiler, type_id, HELPER_COPY) { register_type_helper(compiler, child_ty, HELPER_COPY) }
                    if has_type_helper(compiler, type_id, HELPER_EQUAL) { register_type_helper(compiler, child_ty, HELPER_EQUAL) }
                    if has_type_helper(compiler, type_id, HELPER_PRINT) { register_type_helper(compiler, child_ty, HELPER_PRINT) }
                }
            }
        }
        if type_helper_mask_sum(compiler) == helpers_before { break }
    }
}

fn emit_enum_copy_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for enum_index in 0L..enum_type_count(compiler) {
        let ty = enum_record(compiler, enum_index)
        let type_id = enum_type_id(compiler, enum_index)
        if !has_type_helper(compiler, type_id, HELPER_COPY) { continue }
        let tag_source = MAX_TREE_NODES * 20L + type_id * 2L
        let tag_dest = tag_source + 1L
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 4L, 0L, 0L)); ir_write_ascii(compiler, ir, ", ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 5L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, tag_source, compiler_location(compiler, 5L, 0L, 0L))
        emit_layout_address(compiler, ir, tag_dest, compiler_location(compiler, 4L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %copy.tag."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_source); ir_write_ascii(compiler, ir, ", align 1\n  store i32 %copy.tag."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, tag_dest); ir_write_ascii(compiler, ir, ", align 1\n  switch i32 %copy.tag."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %copy.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " [\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "    i32 "); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ", label %copy.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "copy.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ":\n")
            for part_offset in 0L..case.payload_count {
                let payload_index = case.payload_start + part_offset
                let payload = compiler.enum_payloads[payload_index]
                if payload.ty == TY_UNIT { continue }
                let dest_address = MAX_TREE_NODES * 20L + type_count(compiler) * 2L + payload_index * 2L
                let source_address = dest_address + 1L
                emit_layout_address(compiler, ir, dest_address, compiler_location(compiler, 4L, 0L, payload.offset))
                emit_layout_address(compiler, ir, source_address, compiler_location(compiler, 5L, 0L, payload.offset))
                if is_aggregate_type(compiler, payload.ty) {
                    let destination = compiler_location(compiler, 2L, dest_address, 0L)
                    let source = compiler_location(compiler, 2L, source_address, 0L)
                    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
                    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
                    ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_two(compiler, ir, payload.ty, HELPER_COPY, destination, source, destination_pointer, source_pointer); ir_push_byte(compiler, ir, 10)
                } else {
                    let storage_type: Ascii max 8 = if payload.ty == TY_BOOL { "i8" } else { llvm_type_name(payload.ty) }
                    ir_write_ascii(compiler, ir, "  %copy.value."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, " %copy.value."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, dest_address); ir_write_ascii(compiler, ir, ", align 1\n")
                }
            }
            ir_write_ascii(compiler, ir, "  br label %copy.end."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "copy.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\ncopy.end."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret void\n}\n\n")
    }
}

fn emit_enum_equal_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for enum_index in 0L..enum_type_count(compiler) {
        let ty = enum_record(compiler, enum_index)
        let type_id = enum_type_id(compiler, enum_index)
        if !has_type_helper(compiler, type_id, HELPER_EQUAL) { continue }
        let left_tag = MAX_TREE_NODES * 30L + type_id * 2L
        let right_tag = left_tag + 1L
        ir_write_ascii(compiler, ir, "define internal i1 "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_EQUAL); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 6L, 0L, 0L)); ir_write_ascii(compiler, ir, ", ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 7L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, left_tag, compiler_location(compiler, 6L, 0L, 0L))
        emit_layout_address(compiler, ir, right_tag, compiler_location(compiler, 7L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %eq.tag.left."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, left_tag); ir_write_ascii(compiler, ir, ", align 1\n  %eq.tag.right."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, right_tag); ir_write_ascii(compiler, ir, ", align 1\n  %eq.tag.same."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = icmp eq i32 %eq.tag.left."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", %eq.tag.right."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\n  br i1 %eq.tag.same."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %eq.dispatch."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %eq.false."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\neq.dispatch."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  switch i32 %eq.tag.left."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %eq.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " [\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "    i32 "); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ", label %eq.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "eq.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ":\n")
            for part_offset in 0L..case.payload_count {
                let payload_index = case.payload_start + part_offset
                let payload = compiler.enum_payloads[payload_index]
                if payload.ty == TY_UNIT { continue }
                let left_address = MAX_TREE_NODES * 30L + type_count(compiler) * 2L + payload_index * 2L
                let right_address = left_address + 1L
                emit_layout_address(compiler, ir, left_address, compiler_location(compiler, 6L, 0L, payload.offset))
                emit_layout_address(compiler, ir, right_address, compiler_location(compiler, 7L, 0L, payload.offset))
                if is_aggregate_type(compiler, payload.ty) {
                    let left_location = compiler_location(compiler, 2L, left_address, 0L)
                    let right_location = compiler_location(compiler, 2L, right_address, 0L)
                    let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
                    let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
                    ir_write_ascii(compiler, ir, "  %eq.part."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = call i1 "); emit_type_helper_call_two(compiler, ir, payload.ty, HELPER_EQUAL, left_location, right_location, left_pointer, right_pointer); ir_push_byte(compiler, ir, 10)
                } else {
                    let storage_type: Ascii max 8 = if payload.ty == TY_BOOL { "i8" } else { llvm_type_name(payload.ty) }
                    ir_write_ascii(compiler, ir, "  %eq.left."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, left_address); ir_write_ascii(compiler, ir, ", align 1\n  %eq.right."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, right_address); ir_write_ascii(compiler, ir, ", align 1\n  %eq.part."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, " %eq.left."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, ", %eq.right."); ir_write_number(compiler, ir, payload_index); ir_push_byte(compiler, ir, 10)
                }
                ir_write_ascii(compiler, ir, "  br i1 %eq.part."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, ", label %eq.next."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, part_offset); ir_write_ascii(compiler, ir, ", label %eq.false."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 10)
                ir_write_ascii(compiler, ir, "eq.next."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, part_offset); ir_write_ascii(compiler, ir, ":\n")
            }
            ir_write_ascii(compiler, ir, "  ret i1 true\n")
        }
        ir_write_ascii(compiler, ir, "eq.false."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret i1 false\neq.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\n}\n\n")
    }
}


// E3a1 begin: shared compiler integration.
fn emit_struct_copy_helpers(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_COPY) { continue }
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); emit_location_argument(compiler, ir, compiler_location(compiler, 4L, 0L, 0L)); ir_write_ascii(compiler, ir, ", "); emit_location_argument(compiler, ir, compiler_location(compiler, 5L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        // E3a2: beyond the 64-byte inline tier, use the core's tuned generic
        // copy for plain structs. Collections and Bytes fields must keep
        // dispatching through their field helpers so only live values are read.
        let plain_large_copy = ty.size > 64L && !type_contains_collection(compiler, type_id, 0L) &&
            !type_contains_bytes(compiler, type_id, 0L)
        if plain_large_copy {
            let destination = compiler_location(compiler, 4L, 0L, 0L)
            let source = compiler_location(compiler, 5L, 0L, 0L)
            let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
            let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
            ir_write_ascii(compiler, ir, "  %copy.bulk."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr ")
            emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
            ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, source, source_pointer)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, ty.size); ir_write_ascii(compiler, ir, ")\n  ret void\n}\n\n")
            continue
        }
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if field.ty == TY_UNIT { continue }
            let dest_address = MAX_TREE_NODES * 2L + field_index * 2L
            let source_address = dest_address + 1L
            emit_layout_address(compiler, ir, dest_address, compiler_location(compiler, 4L, 0L, field.offset))
            emit_layout_address(compiler, ir, source_address, compiler_location(compiler, 5L, 0L, field.offset))
            if is_aggregate_type(compiler, field.ty) {
                let destination = compiler_location(compiler, 2L, dest_address, 0L)
                let source = compiler_location(compiler, 2L, source_address, 0L)
                let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
                let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
                ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_two(compiler, ir, field.ty, HELPER_COPY, destination, source, destination_pointer, source_pointer); ir_push_byte(compiler, ir, 10)
            } else {
                let storage_type: Ascii max 8 = if field.ty == TY_BOOL { "i8" } else { llvm_type_name(field.ty) }
                ir_write_ascii(compiler, ir, "  %copy.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, " %copy.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, dest_address); ir_write_ascii(compiler, ir, ", align 1\n")
            }
        }
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_struct_eq_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_EQUAL) { continue }
        ir_write_ascii(compiler, ir, "define internal i1 "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_EQUAL); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); emit_location_argument(compiler, ir, compiler_location(compiler, 6L, 0L, 0L)); ir_write_ascii(compiler, ir, ", "); emit_location_argument(compiler, ir, compiler_location(compiler, 7L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        var previous = -1L
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if field.ty == TY_UNIT { continue }
            let left_address = MAX_TREE_NODES * 3L + field_index * 2L
            let right_address = left_address + 1L
            emit_layout_address(compiler, ir, left_address, compiler_location(compiler, 6L, 0L, field.offset))
            emit_layout_address(compiler, ir, right_address, compiler_location(compiler, 7L, 0L, field.offset))
            if is_aggregate_type(compiler, field.ty) {
                let left_location = compiler_location(compiler, 2L, left_address, 0L)
                let right_location = compiler_location(compiler, 2L, right_address, 0L)
                let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
                let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
                ir_write_ascii(compiler, ir, "  %eq.raw."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = call i1 "); emit_type_helper_call_two(compiler, ir, field.ty, HELPER_EQUAL, left_location, right_location, left_pointer, right_pointer); ir_push_byte(compiler, ir, 10)
            } else {
                let storage_type: Ascii max 8 = if field.ty == TY_BOOL { "i8" } else { llvm_type_name(field.ty) }
                ir_write_ascii(compiler, ir, "  %eq.left."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, left_address); ir_write_ascii(compiler, ir, ", align 1\n  %eq.right."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, right_address); ir_write_ascii(compiler, ir, ", align 1\n  %eq.raw."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, " %eq.left."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", %eq.right."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\n")
            }
            ir_write_ascii(compiler, ir, "  %eq.acc."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = and i1 ")
            if previous < 0L { ir_write_ascii(compiler, ir, "true") }
            else { ir_write_ascii(compiler, ir, "%eq.acc."); ir_write_number(compiler, ir, previous) }
            ir_write_ascii(compiler, ir, ", %eq.raw."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\n")
            previous = field_index
        }
        ir_write_ascii(compiler, ir, "  ret i1 ")
        if previous < 0L { ir_write_ascii(compiler, ir, "true\n") }
        else { ir_write_ascii(compiler, ir, "%eq.acc."); ir_write_number(compiler, ir, previous); ir_write_ascii(compiler, ir, "\n") }
        ir_write_ascii(compiler, ir, "}\n\n")
    }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_struct_print_text_call(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    kind: Ascii max 16,
    index: long,
    length: long,
) {
    ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_ascii", "nlc_print_ascii"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr getelementptr inbounds (["); ir_write_number(compiler, ir, length + 1L); ir_write_ascii(compiler, ir, " x i8], ptr @.nl.struct."); ir_write_ascii(compiler, ir, kind); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, index); ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 "); ir_write_number(compiler, ir, length); ir_write_ascii(compiler, ir, ")\n")
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_struct_print_helpers(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_PRINT) { continue }
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_PRINT); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); emit_location_argument(compiler, ir, compiler_location(compiler, 8L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_struct_print_text_call(compiler, ir, "type", type_index, tokens[ty.name_token].length)
        emit_struct_print_text_call(compiler, ir, "open", 0L, 3L)
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if offset > 0L { emit_struct_print_text_call(compiler, ir, "separator", 0L, 2L) }
            emit_struct_print_text_call(compiler, ir, "field", field_index, tokens[field.name_token].length)
            emit_struct_print_text_call(compiler, ir, "colon", 0L, 2L)
            let address = MAX_TREE_NODES * 5L + field_index
            emit_layout_address(compiler, ir, address, compiler_location(compiler, 8L, 0L, field.offset))
            if is_aggregate_type(compiler, field.ty) {
                let location = compiler_location(compiler, 2L, address, 0L)
                let pointer = emit_location_pointer_materialization(compiler, ir, location)
                ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_one(compiler, ir, field.ty, HELPER_PRINT, location, pointer); ir_push_byte(compiler, ir, 10)
            } else if field.ty == TY_BOOL {
                ir_write_ascii(compiler, ir, "  %print.bool.byte."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n  %print.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = trunc i8 %print.bool.byte."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " to i1\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_bool_raw", "nlc_print_bool_raw"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i1 zeroext %print.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ")\n")
            } else {
                ir_write_ascii(compiler, ir, "  %print.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(field.ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n  call void "); emit_context_runtime_symbol(compiler, ir, if field.ty == TY_LONG { "nl_print_long_raw" } else { "nl_print_int_raw" }, if field.ty == TY_LONG { "nlc_print_long_raw" } else { "nlc_print_int_raw" }); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); ir_write_ascii(compiler, ir, llvm_type_name(field.ty)); ir_write_ascii(compiler, ir, " %print.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ")\n")
            }
        }
        emit_struct_print_text_call(compiler, ir, "close", 0L, 2L)
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}
// E3a1 end

fn emit_enum_text_call(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    prefix: Ascii max 32,
    index: long,
    length: long,
) {
    ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_ascii", "nlc_print_ascii"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr getelementptr inbounds (["); ir_write_number(compiler, ir, length + 1L); ir_write_ascii(compiler, ir, " x i8], ptr @.nl.enum."); ir_write_ascii(compiler, ir, prefix); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, index); ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 "); ir_write_number(compiler, ir, length); ir_write_ascii(compiler, ir, ")\n")
}

fn emit_enum_print_helpers(
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for enum_index in 0L..enum_type_count(compiler) {
        let ty = enum_record(compiler, enum_index)
        let type_id = enum_type_id(compiler, enum_index)
        if !has_type_helper(compiler, type_id, HELPER_PRINT) { continue }
        let tag_address = MAX_TREE_NODES * 40L + type_id
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_PRINT); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); emit_location_argument(compiler, ir, compiler_location(compiler, 8L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, tag_address, compiler_location(compiler, 8L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %print.tag."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address); ir_write_ascii(compiler, ir, ", align 1\n  switch i32 %print.tag."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %print.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " [\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "    i32 "); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ", label %print.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "print.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ":\n")
            if case.name_token < 0L {
                emit_sum_builtin_text_call(compiler, ir, "Full", 4L)
            } else {
                emit_enum_text_call(compiler, ir, "case", ty.field_start + case_offset, tokens[case.name_token].length)
            }
            if case.payload_count > 0L {
                emit_enum_text_call(compiler, ir, "open", 0L, 1L)
                for part_offset in 0L..case.payload_count {
                    let payload_index = case.payload_start + part_offset
                    let payload = compiler.enum_payloads[payload_index]
                    if part_offset > 0L { emit_enum_text_call(compiler, ir, "separator", 0L, 2L) }
                    if payload.ty == TY_UNIT {
                        emit_enum_text_call(compiler, ir, "unit", 0L, 2L)
                    } else {
                        let address = MAX_TREE_NODES * 40L + type_count(compiler) + payload_index
                        emit_layout_address(compiler, ir, address, compiler_location(compiler, 8L, 0L, payload.offset))
                        if is_aggregate_type(compiler, payload.ty) {
                            let location = compiler_location(compiler, 2L, address, 0L)
                            let pointer = emit_location_pointer_materialization(compiler, ir, location)
                            ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_one(compiler, ir, payload.ty, HELPER_PRINT, location, pointer); ir_push_byte(compiler, ir, 10)
                        } else if payload.ty == TY_BOOL {
                            ir_write_ascii(compiler, ir, "  %print.bool.byte."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n  %print.bool."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = trunc i8 %print.bool.byte."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " to i1\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_bool_raw", "nlc_print_bool_raw"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i1 zeroext %print.bool."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, ")\n")
                        } else {
                            ir_write_ascii(compiler, ir, "  %print.value."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n  call void "); emit_context_runtime_symbol(compiler, ir, if payload.ty == TY_LONG { "nl_print_long_raw" } else { "nl_print_int_raw" }, if payload.ty == TY_LONG { "nlc_print_long_raw" } else { "nlc_print_int_raw" }); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty)); ir_write_ascii(compiler, ir, " %print.value."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, ")\n")
                        }
                    }
                }
                emit_enum_text_call(compiler, ir, "close", 0L, 1L)
            }
            ir_write_ascii(compiler, ir, "  ret void\n")
        }
        ir_write_ascii(compiler, ir, "print.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\n}\n\n")
    }
}

fn emit_sum_builtin_text_call(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    word: Ascii max 16,
    length: long,
) {
    ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_ascii", "nlc_print_ascii"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr getelementptr inbounds ([")
    ir_write_number(compiler, ir, length + 1L)
    ir_write_ascii(compiler, ir, " x i8], ptr @.nl.sum.")
    ir_write_ascii(compiler, ir, word)
    ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
    ir_write_number(compiler, ir, length)
    ir_write_ascii(compiler, ir, ")\n")
}

fn emit_sum_copy_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_id in 0L..type_count(compiler) {
        let kind = type_kind(compiler, type_id)
        if (kind != TYPE_KIND_OPTION && kind != TYPE_KIND_RESULT) || !has_type_helper(compiler, type_id, HELPER_COPY) { continue }
        let source_tag_address = MAX_TREE_NODES * 50L + type_id * 2L
        let dest_tag_address = source_tag_address + 1L
        ir_write_ascii(compiler, ir, "define internal void ")
        emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 4L, 0L, 0L))
        ir_write_ascii(compiler, ir, ", ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 5L, 0L, 0L))
        ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, source_tag_address, compiler_location(compiler, 5L, 0L, 0L))
        emit_layout_address(compiler, ir, dest_tag_address, compiler_location(compiler, 4L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %sum.copy.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, source_tag_address)
        ir_write_ascii(compiler, ir, ", align 1\n  store i32 %sum.copy.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, dest_tag_address)
        ir_write_ascii(compiler, ir, ", align 1\n  switch i32 %sum.copy.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %sum.copy.invalid."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " [\n    i32 0, label %sum.copy.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".0\n    i32 1, label %sum.copy.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".1\n  ]\n")
        for tag in 0L..2L {
            ir_write_ascii(compiler, ir, "sum.copy.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ":\n")
            let part_count = sum_case_payload_count(compiler, type_id, tag)
            for part in 0L..part_count {
                let payload = sum_payload_record(compiler, type_id, tag, part)
                if payload.ty == TY_UNIT { continue }
                let dest_address = MAX_TREE_NODES * 50L + type_count(compiler) * 3L + payload.case_index * 2L + type_id * 2L
                let source_address = dest_address + 1L
                emit_layout_address(compiler, ir, dest_address, compiler_location(compiler, 4L, 0L, payload.offset))
                emit_layout_address(compiler, ir, source_address, compiler_location(compiler, 5L, 0L, payload.offset))
                if is_aggregate_type(compiler, payload.ty) {
                    let destination = compiler_location(compiler, 2L, dest_address, 0L)
                    let source = compiler_location(compiler, 2L, source_address, 0L)
                    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
                    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
                    ir_write_ascii(compiler, ir, "  call void ")
                    emit_type_helper_call_two(compiler, ir, payload.ty, HELPER_COPY, destination, source, destination_pointer, source_pointer)
                    ir_push_byte(compiler, ir, 10)
                } else {
                    let storage_type: Ascii max 8 = if payload.ty == TY_BOOL { "i8" } else { llvm_type_name(payload.ty) }
                    ir_write_ascii(compiler, ir, "  %sum.copy.value."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type)
                    ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address)
                    ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage_type)
                    ir_write_ascii(compiler, ir, " %sum.copy.value."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, dest_address)
                    ir_write_ascii(compiler, ir, ", align 1\n")
                }
            }
            ir_write_ascii(compiler, ir, "  br label %sum.copy.end."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "sum.copy.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\nsum.copy.end.")
        ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret void\n}\n\n")
    }
}

fn emit_sum_equal_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_id in 0L..type_count(compiler) {
        let kind = type_kind(compiler, type_id)
        if (kind != TYPE_KIND_OPTION && kind != TYPE_KIND_RESULT) || !has_type_helper(compiler, type_id, HELPER_EQUAL) { continue }
        let left_tag_address = MAX_TREE_NODES * 51L + type_id * 2L
        let right_tag_address = left_tag_address + 1L
        ir_write_ascii(compiler, ir, "define internal i1 ")
        emit_type_helper_symbol(compiler, ir, type_id, HELPER_EQUAL)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 6L, 0L, 0L))
        ir_write_ascii(compiler, ir, ", ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 7L, 0L, 0L))
        ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, left_tag_address, compiler_location(compiler, 6L, 0L, 0L))
        emit_layout_address(compiler, ir, right_tag_address, compiler_location(compiler, 7L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %sum.eq.left.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, left_tag_address)
        ir_write_ascii(compiler, ir, ", align 1\n  %sum.eq.right.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, right_tag_address)
        ir_write_ascii(compiler, ir, ", align 1\n  %sum.eq.same.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = icmp eq i32 %sum.eq.left.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", %sum.eq.right.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, "\n  br i1 %sum.eq.same.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %sum.eq.dispatch."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %sum.eq.false."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, "\nsum.eq.dispatch."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ":\n  switch i32 %sum.eq.left.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %sum.eq.invalid."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " [\n    i32 0, label %sum.eq.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".0\n    i32 1, label %sum.eq.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".1\n  ]\n")
        for tag in 0L..2L {
            ir_write_ascii(compiler, ir, "sum.eq.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ":\n")
            let part_count = sum_case_payload_count(compiler, type_id, tag)
            for part in 0L..part_count {
                let payload = sum_payload_record(compiler, type_id, tag, part)
                if payload.ty == TY_UNIT { continue }
                let left_address = MAX_TREE_NODES * 51L + type_count(compiler) * 2L + payload.case_index * 2L + type_id * 2L
                let right_address = left_address + 1L
                emit_layout_address(compiler, ir, left_address, compiler_location(compiler, 6L, 0L, payload.offset))
                emit_layout_address(compiler, ir, right_address, compiler_location(compiler, 7L, 0L, payload.offset))
                if is_aggregate_type(compiler, payload.ty) {
                    let left_location = compiler_location(compiler, 2L, left_address, 0L)
                    let right_location = compiler_location(compiler, 2L, right_address, 0L)
                    let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
                    let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
                    ir_write_ascii(compiler, ir, "  %sum.eq.part."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, " = call i1 ")
                    emit_type_helper_call_two(compiler, ir, payload.ty, HELPER_EQUAL, left_location, right_location, left_pointer, right_pointer)
                    ir_push_byte(compiler, ir, 10)
                } else {
                    let storage_type: Ascii max 8 = if payload.ty == TY_BOOL { "i8" } else { llvm_type_name(payload.ty) }
                    ir_write_ascii(compiler, ir, "  %sum.eq.left."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type)
                    ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, left_address)
                    ir_write_ascii(compiler, ir, ", align 1\n  %sum.eq.right."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type)
                    ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, right_address)
                    ir_write_ascii(compiler, ir, ", align 1\n  %sum.eq.part."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, storage_type)
                    ir_write_ascii(compiler, ir, " %sum.eq.left."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, ", %sum.eq.right."); ir_write_number(compiler, ir, payload.case_index); ir_push_byte(compiler, ir, 10)
                }
                ir_write_ascii(compiler, ir, "  br i1 %sum.eq.part."); ir_write_number(compiler, ir, payload.case_index)
                ir_write_ascii(compiler, ir, ", label %sum.eq.next."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, part)
                ir_write_ascii(compiler, ir, ", label %sum.eq.false."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 10)
                ir_write_ascii(compiler, ir, "sum.eq.next."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, part); ir_write_ascii(compiler, ir, ":\n")
            }
            ir_write_ascii(compiler, ir, "  ret i1 true\n")
        }
        ir_write_ascii(compiler, ir, "sum.eq.false."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret i1 false\nsum.eq.invalid.")
        ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\n}\n\n")
    }
}

fn emit_sum_print_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_id in 0L..type_count(compiler) {
        let kind = type_kind(compiler, type_id)
        if (kind != TYPE_KIND_OPTION && kind != TYPE_KIND_RESULT) || !has_type_helper(compiler, type_id, HELPER_PRINT) { continue }
        let tag_address = MAX_TREE_NODES * 52L + type_id
        ir_write_ascii(compiler, ir, "define internal void ")
        emit_type_helper_symbol(compiler, ir, type_id, HELPER_PRINT)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 8L, 0L, 0L))
        ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, tag_address, compiler_location(compiler, 8L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %sum.print.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address)
        ir_write_ascii(compiler, ir, ", align 1\n  switch i32 %sum.print.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %sum.print.invalid."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " [\n    i32 0, label %sum.print.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".0\n    i32 1, label %sum.print.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".1\n  ]\n")
        for tag in 0L..2L {
            ir_write_ascii(compiler, ir, "sum.print.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ":\n")
            let word: Ascii max 16 = if kind == TYPE_KIND_OPTION && tag == 0L { "some" }
                else if kind == TYPE_KIND_OPTION { "none" }
                else if tag == 0L { "ok" } else { "err" }
            let word_length = if kind == TYPE_KIND_OPTION { 4L } else if tag == 0L { 2L } else { 3L }
            emit_sum_builtin_text_call(compiler, ir, word, word_length)
            let part_count = sum_case_payload_count(compiler, type_id, tag)
            if part_count > 0L {
                emit_sum_builtin_text_call(compiler, ir, "lparen", 1L)
                for part in 0L..part_count {
                    let payload = sum_payload_record(compiler, type_id, tag, part)
                    if part > 0L { emit_sum_builtin_text_call(compiler, ir, "separator", 2L) }
                    if payload.ty == TY_UNIT { emit_sum_builtin_text_call(compiler, ir, "unit", 2L) }
                    else {
                        let address = MAX_TREE_NODES * 52L + type_count(compiler) + payload.case_index
                        emit_layout_address(compiler, ir, address, compiler_location(compiler, 8L, 0L, payload.offset))
                        if is_aggregate_type(compiler, payload.ty) {
                            let location = compiler_location(compiler, 2L, address, 0L)
                            let pointer = emit_location_pointer_materialization(compiler, ir, location)
                            ir_write_ascii(compiler, ir, "  call void ")
                            emit_type_helper_call_one(compiler, ir, payload.ty, HELPER_PRINT, location, pointer)
                            ir_push_byte(compiler, ir, 10)
                        } else if payload.ty == TY_BOOL {
                            ir_write_ascii(compiler, ir, "  %sum.print.bool.byte."); ir_write_number(compiler, ir, payload.case_index)
                            ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, address)
                            ir_write_ascii(compiler, ir, ", align 1\n  %sum.print.bool."); ir_write_number(compiler, ir, payload.case_index)
                            ir_write_ascii(compiler, ir, " = trunc i8 %sum.print.bool.byte."); ir_write_number(compiler, ir, payload.case_index)
                            ir_write_ascii(compiler, ir, " to i1\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_bool_raw", "nlc_print_bool_raw"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i1 zeroext %sum.print.bool."); ir_write_number(compiler, ir, payload.case_index); ir_write_ascii(compiler, ir, ")\n")
                        } else {
                            ir_write_ascii(compiler, ir, "  %sum.print.value."); ir_write_number(compiler, ir, payload.case_index)
                            ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty))
                            ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address)
                            ir_write_ascii(compiler, ir, ", align 1\n  call void "); emit_context_runtime_symbol(compiler, ir, if payload.ty == TY_LONG { "nl_print_long_raw" } else { "nl_print_int_raw" }, if payload.ty == TY_LONG { "nlc_print_long_raw" } else { "nlc_print_int_raw" })
                            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty))
                            ir_write_ascii(compiler, ir, " %sum.print.value."); ir_write_number(compiler, ir, payload.case_index); ir_write_ascii(compiler, ir, ")\n")
                        }
                    }
                }
                emit_sum_builtin_text_call(compiler, ir, "rparen", 1L)
            }
            ir_write_ascii(compiler, ir, "  ret void\n")
        }
        ir_write_ascii(compiler, ir, "sum.print.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\n}\n\n")
    }
}

fn emit_contains_index_helper(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "define internal i1 @nl.contains.index(ptr %items, i64 %count, i64 %wanted) {\nentry:\n  br label %loop\nloop:\n  %index = phi i64 [ 0, %entry ], [ %next, %advance ]\n  %finished = icmp uge i64 %index, %count\n  br i1 %finished, label %missing, label %check\ncheck:\n  %item.ptr = getelementptr i64, ptr %items, i64 %index\n  %item = load i64, ptr %item.ptr, align 1\n  %matches = icmp eq i64 %item, %wanted\n  br i1 %matches, label %found, label %advance\nadvance:\n  %next = add i64 %index, 1\n  br label %loop\nfound:\n  ret i1 true\nmissing:\n  ret i1 false\n}\n\n")
}

// E3a1 begin: shared compiler integration.
fn emit_struct_fill_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    var any_defaults = false
    for type_index in 0L..struct_type_count(compiler) {
        let type_id = struct_type_id(compiler, type_index)
        if has_type_helper(compiler, type_id, HELPER_FILL) { any_defaults = true }
    }
    if !any_defaults { return }
    emit_contains_index_helper(compiler, ir)
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_FILL) { continue }
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_FILL); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top, "); emit_hidden_descriptor_parameter(compiler, ir); ir_write_ascii(compiler, ir, ", ptr %nl.given, i64 %nl.given.count) {\nentry:\n  %nl.region.end = add i64 %nl.top, 0\n")
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if field.default_node < 0L { continue }
            let address = MAX_TREE_NODES * 4L + field_index
            ir_write_ascii(compiler, ir, "  %given."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = call i1 @nl.contains.index(ptr %nl.given, i64 %nl.given.count, i64 "); ir_write_number(compiler, ir, offset); ir_write_ascii(compiler, ir, ")\n  br i1 %given."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", label %skip."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", label %fill."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\nfill."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ":\n")
            ir_write_ascii(compiler, ir, "  %default.dest.offset."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = add i64 %nl.dest.offset, "); ir_write_number(compiler, ir, field.offset); ir_write_ascii(compiler, ir, "\n  call void "); emit_default_field_helper_symbol(compiler, ir, type_id, field_index); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.region.end, ptr %nl.dest.anchor, i64 %default.dest.offset."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ")\n  br label %skip."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\nskip."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ":\n")
        }
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_struct_default_helpers(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for field_index in 0L..compiler.struct_fields.count() {
        let field = compiler.struct_fields[field_index]
        if field.default_node < 0L { continue }
        let field_type_id = struct_type_id(compiler, field.owner)
        if !has_type_helper(compiler, field_type_id, HELPER_DEFAULT) { continue }
        let function_id = -100000L - field_index
        let expression = field.default_node
        let default_file = struct_record(compiler, field.owner).file
        ir_write_ascii(compiler, ir, "define internal void "); emit_default_field_helper_symbol(compiler, ir, field_type_id, field_index); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top, "); emit_hidden_descriptor_parameter(compiler, ir); ir_write_ascii(compiler, ir, ") {\nentry:\n  %nl.region.end = add i64 %nl.top, 0\n")
        let first = expression - tables.nodes[expression].subtree
        for node in first..expression + 1L {
            if tables.nodes[node].kind == NodeKind.If && compiler.facts[node].ty != TY_UNIT && compiler.facts[node].ty != TY_NEVER && !is_aggregate_type(compiler, compiler.facts[node].ty) {
                ir_write_ascii(compiler, ir, "  %if.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
            }
            if (tables.nodes[node].kind == NodeKind.Binary && (tables.nodes[node].flags == 14L || tables.nodes[node].flags == 15L)) {
                ir_write_ascii(compiler, ir, "  %logic.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i1, align 1\n")
            }
            if tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 21L && compiler.facts[node].ty != TY_UNIT && !is_aggregate_type(compiler, compiler.facts[node].ty) {
                ir_write_ascii(compiler, ir, "  %coalesce.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
            }
            if is_aggregate_type(compiler, compiler.facts[node].ty) {
                let ty = type_record(compiler, compiler.facts[node].ty)
                let size = ty.size
                let alignment = ty.align
                ir_write_ascii(compiler, ir, "  %agg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, alignment); ir_write_ascii(compiler, ir, "\n")
            }
        }
        for binding_index in 0L..compiler.bindings.count() {
            let binding = compiler.bindings[binding_index]
            if compiler.scopes[binding.scope].function_id == function_id && binding.ty != TY_UNIT {
                ir_write_ascii(compiler, ir, "  %local."); ir_write_number(compiler, ir, binding_index); ir_write_ascii(compiler, ir, " = alloca ")
                if is_aggregate_type(compiler, binding.ty) {
                    let ty = type_record(compiler, binding.ty)
                    let size = ty.size
                    let alignment = ty.align
                    ir_write_ascii(compiler, ir, "["); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, alignment); ir_write_ascii(compiler, ir, "\n")
                } else {
                    if binding.ty == TY_BOOL { ir_write_ascii(compiler, ir, "i8") } else { ir_write_ascii(compiler, ir, llvm_type_name(binding.ty)) }
                    ir_write_ascii(compiler, ir, ", align 1\n")
                }
            }
        }
        emit_expr_linear(source, files, tokens, tables, compiler, ir, expression, default_file, field.ty, false)
        if is_aggregate_type(compiler, field.ty) {
            let source_kind = aggregate_source_kind(tables, compiler, expression)
            let source_node = aggregate_source_id(tables, compiler, expression)
            emit_aggregate_copy(compiler, ir, field.ty, aggregate_destination_location(compiler, 2L, 0L), aggregate_source_location(compiler, source_kind, source_node))
        } else if field.ty == TY_BOOL {
            let destination = compiler_location(compiler, 9L, 0L, 0L)
            let pointer = emit_location_pointer_materialization(compiler, ir, destination)
            ir_write_ascii(compiler, ir, "  %default.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, expression); ir_write_ascii(compiler, ir, " to i8\n  store i8 %default.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer); ir_write_ascii(compiler, ir, ", align 1\n")
        } else {
            let destination = compiler_location(compiler, 9L, 0L, 0L)
            let pointer = emit_location_pointer_materialization(compiler, ir, destination)
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(field.ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, expression); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}
// E3a1 end

fn emit_type_helpers_for_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    kind: long,
) {
    if kind == TYPE_KIND_STRUCT {
        var has_struct_helpers = false
        for type_id in 0L..type_count(compiler) {
            if type_kind(compiler, type_id) == kind && type_has_registered_helper(compiler, type_id) {
                has_struct_helpers = true
            }
        }
        if has_struct_helpers {
            emit_struct_copy_helpers(tables, compiler, ir)
            emit_struct_eq_helpers(compiler, ir)
            emit_struct_print_helpers(source, files, tokens, compiler, ir)
            emit_struct_default_helpers(source, files, tokens, tables, compiler, ir)
            emit_struct_fill_helpers(compiler, ir)
        }
    } else if kind == TYPE_KIND_ENUM {
        var has_enum_helpers = false
        for type_id in 0L..type_count(compiler) {
            if type_kind(compiler, type_id) == kind && type_has_registered_helper(compiler, type_id) { has_enum_helpers = true }
        }
        if has_enum_helpers {
            emit_enum_copy_helpers(compiler, ir)
            emit_enum_equal_helpers(compiler, ir)
            emit_enum_print_helpers(tokens, compiler, ir)
        }
    } else if kind == TYPE_KIND_OPTION {
        emit_sum_copy_helpers(compiler, ir)
        emit_sum_equal_helpers(compiler, ir)
        emit_sum_print_helpers(compiler, ir)
    } else if kind == TYPE_KIND_RESULT {
        ()
    } else if kind == TYPE_KIND_QUEUE || kind == TYPE_KIND_POOL {
        ()
    } else if kind == TYPE_KIND_MAP {
        emit_map_copy_helpers(compiler, ir)
        emit_map_type_functions(compiler, ir)
    } else if kind == TYPE_KIND_ARRAY || collection_kind_is_list(kind) {
        emit_collection_copy_helpers(compiler, ir, kind)
        emit_collection_equal_helpers(compiler, ir, kind)
        emit_collection_print_helpers(compiler, ir, kind)
    } else if kind == TYPE_KIND_ASCII || kind == TYPE_KIND_TEXT || kind == TYPE_KIND_BYTES {
        emit_text_type_helpers(compiler, ir, kind)
    } else {
        for type_id in 0L..type_count(compiler) {
            if type_kind(compiler, type_id) == kind && type_has_registered_helper(compiler, type_id) { compiler.ir_overflow = true }
        }
    }
}

fn emit_registered_type_helpers(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    emit_collection_print_globals(compiler, ir)
    emit_sort_functions(tables, compiler, ir)
    for kind in TYPE_KIND_STRUCT..TYPE_KIND_POOL + 1L {
        emit_type_helpers_for_kind(source, files, tokens, tables, compiler, ir, kind)
    }
}

fn ir_write_struct_identifier_global(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    kind: Ascii max 16,
    index: long,
    file_index: long,
    token: long,
) {
    let length = tokens[token].length
    let start = files[file_index].base + tokens[token].start
    ir_write_ascii(compiler, ir, "@.nl.struct."); ir_write_ascii(compiler, ir, kind); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, index); ir_write_ascii(compiler, ir, " = private unnamed_addr constant ["); ir_write_number(compiler, ir, length + 1L); ir_write_ascii(compiler, ir, " x i8] c\"")
    for byte_index in 0L..length { ir_write_escaped_byte(compiler, ir, source[start + byte_index]) }
    ir_write_ascii(compiler, ir, "\\00\", align 1\n")
}

fn ir_write_enum_case_global(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    case_index: long,
) {
    let case = compiler.enum_cases[case_index]
    let owner = enum_record(compiler, case.owner)
    let length = tokens[case.name_token].length
    let start = files[owner.file].base + tokens[case.name_token].start
    ir_write_ascii(compiler, ir, "@.nl.enum.case."); ir_write_number(compiler, ir, case_index); ir_write_ascii(compiler, ir, " = private unnamed_addr constant ["); ir_write_number(compiler, ir, length + 1L); ir_write_ascii(compiler, ir, " x i8] c\"")
    for byte_index in 0L..length { ir_write_escaped_byte(compiler, ir, source[start + byte_index]) }
    ir_write_ascii(compiler, ir, "\\00\", align 1\n")
}


// E3a1 begin: shared compiler integration.
fn emit_file_globals(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for file_index in 0L..files.count() {
        ir_write_ascii(compiler, ir, "@.nl.file.")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
        ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8] c\"")
        for index in 0L..files[file_index].name.count() { ir_write_escaped_byte(compiler, ir, files[file_index].name[index]) }
        ir_write_ascii(compiler, ir, "\\00\", align 1\n")
    }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.BytesLiteral || tables.nodes[node].kind == NodeKind.ByteString {
            let syntax = tables.nodes[node]
            let literal_file = node_file_index(tables.nodes, files, node)
            let literal = if syntax.kind == NodeKind.BytesLiteral {
                decode_string_token(source, tokens, files[literal_file].base, syntax.extra, true)
            } else { decode_string_token(source, tokens, files[literal_file].base, syntax.token, false) }
            ir_write_ascii(compiler, ir, "@.nl.literal.")
            ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
            ir_write_number(compiler, ir, literal.count() + 1L)
            ir_write_ascii(compiler, ir, " x i8] c\"")
            for index in 0L..literal.count() { ir_write_escaped_byte(compiler, ir, literal[index]) }
            ir_write_ascii(compiler, ir, "\\00\", align 1\n")
        }
    }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.Const && (compiler.facts[node].flags & FACT_CONSTANT_ARRAY) != 0L {
            emit_array_constant_global(source, tokens, files, tables, compiler, ir, node)
        }
    }
    let first_file_id = compiler_file_id_base(compiler)
    emit_file_table_global(files, compiler, ir, first_file_id)
    let main_name: Bytes max 4096 = b"main"
    ir_write_global_string(compiler, ir, "@.nl.entry.main = private unnamed_addr constant [", main_name)
    for test_index in 0L..compiler.tests.count() {
        let test = compiler.tests[test_index]
        let name = decode_string_token(source, tokens, files[test.file].base, test.name_token, false)
        ir_write_test_global(compiler, ir, test_index, name)
    }
    ir_write_ascii(compiler, ir, "@.nl.entry.table = private constant [")
    ir_write_number(compiler, ir, compiler.tests.count() + 1L)
    ir_write_ascii(compiler, ir, " x { ptr, i64 }] [")
    ir_write_ascii(compiler, ir, "{ ptr, i64 } { ptr getelementptr inbounds ([5 x i8], ptr @.nl.entry.main, i64 0, i64 0), i64 4 }")
    for test_index in 0L..compiler.tests.count() {
        let test = compiler.tests[test_index]
        let name = decode_string_token(source, tokens, files[test.file].base, test.name_token, false)
        ir_write_ascii(compiler, ir, ", { ptr, i64 } { ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, name.count() + 8L)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.entry.test.")
        ir_write_number(compiler, ir, test_index)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
        ir_write_number(compiler, ir, name.count() + 7L)
        ir_write_ascii(compiler, ir, " }")
    }
    ir_write_ascii(compiler, ir, "], align 8\n")
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.Expect { ir_write_expect_global(source, tables, compiler, ir, node) }
        if tables.nodes[node].kind == NodeKind.StructInit {
            let type_index = compiler.facts[node].literal
            let ty = struct_record(compiler, type_index)
            var item_count = 0L
            for field_offset in 0L..ty.field_count {
                let field_index = ty.field_start + field_offset
                var child = compiler.child_first[node]
                for field_step in 0L..tables.nodes[node].subtree {
                    if child < 0L { break }
                    if compiler.facts[child].binding == field_index { item_count += 1L }
                    child = compiler.child_next[child]
                }
            }
            ir_write_ascii(compiler, ir, "@.nl.given."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = private constant ["); ir_write_number(compiler, ir, item_count); ir_write_ascii(compiler, ir, " x i64] ")
            if item_count == 0L { ir_write_ascii(compiler, ir, "zeroinitializer\n") }
            else {
                ir_write_ascii(compiler, ir, "[")
                var wrote = false
                for field_offset in 0L..ty.field_count {
                    let field_index = ty.field_start + field_offset
                    var child = compiler.child_first[node]
                    for field_step in 0L..tables.nodes[node].subtree {
                        if child < 0L { break }
                        if compiler.facts[child].binding == field_index {
                            if wrote { ir_write_ascii(compiler, ir, ", ") }
                            ir_write_ascii(compiler, ir, "i64 "); ir_write_number(compiler, ir, field_offset); wrote = true
                        }
                        child = compiler.child_next[child]
                    }
                }
                ir_write_ascii(compiler, ir, "]\n")
            }
        }
    }
    let open_text: Bytes max 4096 = b" { "
    let close_text: Bytes max 4096 = b" }"
    let separator_text: Bytes max 4096 = b", "
    let colon_text: Bytes max 4096 = b": "
    let enum_open_text: Bytes max 4096 = b"("
    let enum_close_text: Bytes max 4096 = b")"
    let enum_separator_text: Bytes max 4096 = b", "
    let enum_unit_text: Bytes max 4096 = b"()"
    ir_write_global_string(compiler, ir, "@.nl.struct.open.0 = private unnamed_addr constant [", open_text)
    ir_write_global_string(compiler, ir, "@.nl.struct.close.0 = private unnamed_addr constant [", close_text)
    ir_write_global_string(compiler, ir, "@.nl.struct.separator.0 = private unnamed_addr constant [", separator_text)
    ir_write_global_string(compiler, ir, "@.nl.struct.colon.0 = private unnamed_addr constant [", colon_text)
    ir_write_global_string(compiler, ir, "@.nl.enum.open.0 = private unnamed_addr constant [", enum_open_text)
    ir_write_global_string(compiler, ir, "@.nl.enum.close.0 = private unnamed_addr constant [", enum_close_text)
    ir_write_global_string(compiler, ir, "@.nl.enum.separator.0 = private unnamed_addr constant [", enum_separator_text)
    ir_write_global_string(compiler, ir, "@.nl.enum.unit.0 = private unnamed_addr constant [", enum_unit_text)
    let sum_some: Bytes max 4096 = b"some"
    let sum_none: Bytes max 4096 = b"none"
    let sum_ok: Bytes max 4096 = b"ok"
    let sum_err: Bytes max 4096 = b"err"
    let sum_lparen: Bytes max 4096 = b"("
    let sum_rparen: Bytes max 4096 = b")"
    let sum_separator: Bytes max 4096 = b", "
    let sum_unit: Bytes max 4096 = b"()"
    let sum_full: Bytes max 4096 = b"Full"
    ir_write_global_string(compiler, ir, "@.nl.sum.some = private unnamed_addr constant [", sum_some)
    ir_write_global_string(compiler, ir, "@.nl.sum.none = private unnamed_addr constant [", sum_none)
    ir_write_global_string(compiler, ir, "@.nl.sum.ok = private unnamed_addr constant [", sum_ok)
    ir_write_global_string(compiler, ir, "@.nl.sum.err = private unnamed_addr constant [", sum_err)
    ir_write_global_string(compiler, ir, "@.nl.sum.lparen = private unnamed_addr constant [", sum_lparen)
    ir_write_global_string(compiler, ir, "@.nl.sum.rparen = private unnamed_addr constant [", sum_rparen)
    ir_write_global_string(compiler, ir, "@.nl.sum.separator = private unnamed_addr constant [", sum_separator)
    ir_write_global_string(compiler, ir, "@.nl.sum.unit = private unnamed_addr constant [", sum_unit)
    ir_write_global_string(compiler, ir, "@.nl.sum.Full = private unnamed_addr constant [", sum_full)
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        if ty.node < 0L { continue }
        ir_write_struct_identifier_global(source, files, tokens, compiler, ir, "type", type_index, ty.file, ty.name_token)
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            ir_write_struct_identifier_global(source, files, tokens, compiler, ir, "field", field_index, ty.file, field.name_token)
        }
    }
    for case_index in 0L..compiler.enum_cases.count() {
        if compiler.enum_cases[case_index].name_token >= 0L {
            ir_write_enum_case_global(source, files, tokens, compiler, ir, case_index)
        }
    }
    ir_write_ascii(compiler, ir, "\n")
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_main_function(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    config: MemoryConfig,
    entry: long,
) {
    if compiler.c_runtime {
        emit_c_main_function(compiler, ir, files, config, entry)
        return
    }
    // E3a1 subsection: create the stable context before any context-passing hook.
    ir_write_ascii(compiler, ir, "define i32 @main(i32 %argc, ptr %argv, ptr %envp, ptr %auxv) {\nentry:\n  %nl.ctx = call ptr @nl_context_create(i64 4096, i64 ")
    ir_write_number(compiler, ir, config.recursion_budget)
    ir_write_ascii(compiler, ir, ", i64 ")
    ir_write_number(compiler, ir, config.step_budget_main)
    ir_write_ascii(compiler, ir, ", ptr @.nl.entry.table, i64 0, ptr %envp, ptr %auxv)\n  call void @nl_core_init(ptr %nl.ctx, i32 %argc, ptr %argv, ptr %envp, ptr %auxv)\n")
    // E3a1 subsection end
    if compiler.tests.count() > 0L {
        ir_write_ascii(compiler, ir, "  %nl.selected = call i32 @nl_test_selected_index(ptr %nl.ctx)\n  switch i32 %nl.selected, label %nl.select.default [\n")
        for test_index in 0L..compiler.tests.count() {
            ir_write_ascii(compiler, ir, "    i32 ")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ", label %nl.select.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for test_index in 0L..compiler.tests.count() {
            ir_write_ascii(compiler, ir, "nl.select.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ":\n  br label %nl.select.ready\n")
        }
        ir_write_ascii(compiler, ir, "nl.select.default:\n  br label %nl.select.ready\nnl.select.ready:\n  %nl.entry.index = phi i64 ")
        for test_index in 0L..compiler.tests.count() {
            if test_index > 0L { ir_write_ascii(compiler, ir, ", ") }
            ir_write_ascii(compiler, ir, "[ ")
            ir_write_number(compiler, ir, test_index + 1L)
            ir_write_ascii(compiler, ir, ", %nl.select.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, " ]")
        }
        ir_write_ascii(compiler, ir, ", [ ")
        if entry >= 0L { ir_write_ascii(compiler, ir, "0") } else { ir_write_ascii(compiler, ir, "1") }
        ir_write_ascii(compiler, ir, ", %nl.select.default ]\n")
        ir_write_ascii(compiler, ir, "  call void @nl_context_set_entry_name(ptr %nl.ctx, ptr @.nl.entry.table, i64 %nl.entry.index)\n")
    }
    ir_write_ascii(compiler, ir, "  %nl.top = call i64 @nl_context_base_offset(ptr %nl.ctx)\n  %nl.env = call ptr @nl_env_create(ptr %nl.ctx, i32 %argc, ptr %argv, i32 ")
    ir_write_number(compiler, ir, config.capability_mask)
    ir_write_ascii(compiler, ir, ")\n")
    ir_write_ascii(compiler, ir, "  call void @nl_register_files(ptr %nl.ctx, i32 0, ptr @.nl.file.table.0, i32 ")
    ir_write_number(compiler, ir, files.count())
    ir_write_ascii(compiler, ir, ")\n")
    ir_write_ascii(compiler, ir, "  call void @nl_core_register_files(ptr %nl.ctx)\n")
    if compiler.tests.count() > 0L {
        ir_write_ascii(compiler, ir, "  switch i32 %nl.selected, label %nl.test.fallback [\n")
        for test_index in 0L..compiler.tests.count() {
            ir_write_ascii(compiler, ir, "    i32 ")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ", label %nl.test.run.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for test_index in 0L..compiler.tests.count() {
            ir_write_ascii(compiler, ir, "nl.test.run.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ":\n  call void @nl_set_test_mode(ptr %nl.ctx)\n  %nl.test.result.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, " = call i32 @nl_fn_")
            let test_function_id = compiler.functions.count() + test_index
            ir_write_number(compiler, ir, test_function_id)
            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top)\n  call void @nl_env_destroy(ptr %nl.ctx, ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 %nl.test.result.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "nl.test.fallback:\n")
    }
    if entry >= 0L {
        ir_write_ascii(compiler, ir, "  call void @nl_fn_")
        ir_write_number(compiler, ir, entry)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top)\n")
    }
    ir_write_ascii(compiler, ir, "  call void @nl_env_destroy(ptr %nl.ctx, ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 0\n}\n")
}
// E3a1 end

fn core_position(file_data: Bytes max FILE_SOURCE_CAPACITY, offset: long) -> SourcePosition {
    var line = 1L
    var col = 1L
    for index in 0L..offset {
        if file_data[index] == 10 { line += 1L; col = 1L }
        else { col += 1L }
    }
    SourcePosition { line, col }
}

fn fail_core_internal(
    env: Env,
    file: Bytes max 4096,
    position: SourcePosition,
    message: Ascii max 160,
) -> never {
    match env.err.write(b"nlc: internal error in the core library: ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(file) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(message.bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(3), err(_) => env.exit(3) }
}

fn copy_core_name(name: Ascii max 64) -> Bytes max 4096 {
    var result: Bytes max 4096 = Bytes.empty()
    for index in 0L..name.len() { result.push(name.bytes()[index]).unwrap() }
    result
}

// The core files whose helpers a C-runtime program compiles in directly. They use no core state and fail
// nothing, and the compiled functions are internal, so only the ones the program calls survive.
fn embedded_core_is_prelude_file(name: Ascii max 64) -> bool {
    name == "text_format.nl" || name == "parse_number.nl" || name == "utf8_validate.nl" || name == "utf8_trusted.nl"
}

fn append_embedded_core_sources(
    env: Env,
    source: grow Bytes max SOURCE_BUFFER_CAPACITY,
    files: write list<SourceFile, MAX_SOURCE_FILES>,
    tokens: write list<Token, TOKEN_STORAGE_CAPACITY>,
    delimiters: write list<DelimiterKind, MAX_DELIMITER_NESTING>,
    tables: write ParseTables,
    prelude_only: bool,
) {
    for file_index in 0L..embedded_core_file_count() {
        if prelude_only && !embedded_core_is_prelude_file(embedded_core_file_name(file_index)) { continue }
        let file_name = copy_core_name(embedded_core_file_name(file_index))
        var file_data: Bytes max FILE_SOURCE_CAPACITY = Bytes.empty()
        for chunk_index in 0L..embedded_core_chunk_count(file_index) {
            let chunk = embedded_core_file_chunk(file_index, chunk_index)
            match file_data.try_append(chunk) {
                ok(_) => (),
                err(_) => fail_core_internal(env, file_name, SourcePosition { line: 1L, col: 1L }, "embedded source exceeded its fixed file buffer"),
            }
        }
        match file_data.validate_utf8() {
            ok(_) => (),
            err(error) => fail_core_internal(env, file_name, core_position(file_data, error.valid_up_to), "embedded source is not valid UTF-8"),
        }
        let file_length = file_data.count()
        let base = source.count()
        match source.try_append(file_data) {
            ok(_) => (),
            err(_) => fail_core_internal(env, file_name, SourcePosition { line: 1L, col: 1L }, "embedded source exceeded its fixed package buffer"),
        }
        let first_token = tokens.count()
        let summary = match lex_file(source, base, file_length, tokens, delimiters) {
            ok(value) => value,
            err(problem) => fail_core_internal(env, file_name, SourcePosition { line: problem.line, col: problem.col }, "embedded source has a lexer error"),
        }
        let root = match parse_file(source, tokens, tables, base, file_length, first_token, summary.token_count) {
            ok(value) => value,
            err(problem) => fail_core_internal(env, file_name, core_position(file_data, problem.offset), "embedded source has a parser error"),
        }
        let core_file = SourceFile { name: file_name, base, length: file_length, first_token, token_count: summary.token_count, end_line: summary.end_line, end_col: summary.end_col, tree_root: root }
        match files.push(core_file) {
            ok(_) => (),
            err(_) => fail_core_internal(env, b"core", SourcePosition { line: 1L, col: 1L }, "embedded file count exceeded its fixed limit"),
        }
    }
}

// E3a1 begin: shared compiler integration.
fn emit_core_file_globals(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for file_index in 0L..files.count() {
        let global_file_id = compiler_file_id_base(compiler) + file_index
        ir_write_ascii(compiler, ir, "@.nl.file.")
        ir_write_number(compiler, ir, global_file_id)
        ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
        ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8] c\"")
        for index in 0L..files[file_index].name.count() { ir_write_escaped_byte(compiler, ir, files[file_index].name[index]) }
        ir_write_ascii(compiler, ir, "\\00\", align 1\n")
    }
    let first_file_id = compiler_file_id_base(compiler)
    emit_file_table_global(files, compiler, ir, first_file_id)
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.BytesLiteral || tables.nodes[node].kind == NodeKind.ByteString {
            let syntax = tables.nodes[node]
            let literal_file = node_file_index(tables.nodes, files, node)
            let literal = if syntax.kind == NodeKind.BytesLiteral {
                decode_string_token(source, tokens, files[literal_file].base, syntax.extra, true)
            } else { decode_string_token(source, tokens, files[literal_file].base, syntax.token, false) }
            ir_write_ascii(compiler, ir, "@.nl.core.literal.")
            ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
            ir_write_number(compiler, ir, literal.count() + 1L)
            ir_write_ascii(compiler, ir, " x i8] c\"")
            for index in 0L..literal.count() { ir_write_escaped_byte(compiler, ir, literal[index]) }
            ir_write_ascii(compiler, ir, "\\00\", align 1\n")
        }
    }
}
// E3a1 end

fn syscall_register(index: long) -> Ascii max 8 {
    if index == 0L { "rdi" }
    else if index == 1L { "rsi" }
    else if index == 2L { "rdx" }
    else if index == 3L { "r10" }
    else if index == 4L { "r8" }
    else { "r9" }
}

fn emit_one_syscall_helper(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, item_count: long) {
    ir_write_ascii(compiler, ir, "define internal i64 @nl.sys.call")
    ir_write_number(compiler, ir, item_count)
    ir_write_ascii(compiler, ir, "(i64 %n")
    for index in 0L..item_count {
        ir_write_ascii(compiler, ir, ", i64 %a")
        ir_write_number(compiler, ir, index)
    }
    ir_write_ascii(compiler, ir, ") alwaysinline nounwind {\nentry:\n  %r = call i64 asm sideeffect \"syscall\", \"={rax},{rax}")
    for index in 0L..item_count {
        ir_push_byte(compiler, ir, 44)
        ir_push_byte(compiler, ir, 123)
        ir_write_ascii(compiler, ir, syscall_register(index))
        ir_push_byte(compiler, ir, 125)
    }
    ir_write_ascii(compiler, ir, ",~{rcx},~{r11},~{memory},~{dirflag},~{fpsr},~{flags}\"(i64 %n")
    for index in 0L..item_count {
        ir_write_ascii(compiler, ir, ", i64 %a")
        ir_write_number(compiler, ir, index)
    }
    ir_write_ascii(compiler, ir, ")\n  ret i64 %r\n}\n\n")
}

fn emit_syscall_helpers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    for item_count in 0L..7L { emit_one_syscall_helper(compiler, ir, item_count) }
}

fn emit_core_registration(files: list<SourceFile, MAX_SOURCE_FILES>, compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    // E3a1 begin
    let first_file_id = compiler_file_id_base(compiler)
    let file_count = files.count()
    ir_write_ascii(compiler, ir, "define internal void @nl_core_register_files(ptr %nl.ctx) nounwind {\nentry:\n")
    ir_write_ascii(compiler, ir, "  call void @nl_register_files(ptr %nl.ctx, i32 ")
    ir_write_number(compiler, ir, first_file_id)
    ir_write_ascii(compiler, ir, ", ptr @.nl.file.table.")
    ir_write_number(compiler, ir, first_file_id)
    ir_write_ascii(compiler, ir, ", i32 ")
    ir_write_number(compiler, ir, file_count)
    ir_write_ascii(compiler, ir, ")\n")
    ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    // E3a1 end
}

fn emit_core_start_assembly(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "module asm \".text\"\nmodule asm \".globl _start\"\nmodule asm \".type _start, @function\"\nmodule asm \"_start:\"\nmodule asm \"  .cfi_startproc\"\nmodule asm \"  .cfi_undefined rip\"\nmodule asm \"  xor %ebp, %ebp\"\nmodule asm \"  mov %rsp, %rdi\"\nmodule asm \"  and $-16, %rsp\"\nmodule asm \"  call nl_core_start\"\nmodule asm \"  ud2\"\nmodule asm \"  .cfi_endproc\"\nmodule asm \".size _start, . - _start\"\n")
    ir_write_ascii(compiler, ir, "@llvm.used = appending global [1 x ptr] [ptr @nl_core_start], section \"llvm.metadata\"\n")
}

// E3a1 begin: shared compiler integration.
fn compile_embedded_core(
    env: Env,
    config: MemoryConfig,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    file_id_base: long,
    test_build: bool,
    tables: write ParseTables,
    compiler: write CompilerTables,
    prelude_only: bool,
) -> bool {
    var source: Bytes max SOURCE_BUFFER_CAPACITY = Bytes.empty()
    var files: list<SourceFile, MAX_SOURCE_FILES> = list {}
    var tokens: list<Token, TOKEN_STORAGE_CAPACITY> = list {}
    var delimiters: list<DelimiterKind, MAX_DELIMITER_NESTING> = list {}
    reset_parse_tables(tables)
    initialize_parse_tables(tables)
    append_embedded_core_sources(env, source, files, tokens, delimiters, tables, prelude_only)
    reset_compiler_tables(env, compiler)
    compiler.core_mode = true
    compiler.test_build = test_build
    compiler.file_id_base = file_id_base + if test_build { COMPILER_TEST_BUILD_FLAG } else { 0L }
    add_compiler_links(env, tables, compiler)
    intern_package_names(env, source, files, tokens, tables, compiler)
    build_line_start_index(env, source, files, compiler)
    register_scalar_constants(env, source, tokens, files, tables, compiler)
    index_package_enums(env, source, files, tokens, tables, compiler)
    // E3a1 subsection: embedded core context intrinsics need the sized layout.
    index_package_structs(source, files, tokens, tables, compiler)
    // E3a1 subsection end
    intern_written_type_instances(env, source, tokens, files, tables, compiler)
    size_package_types(source, files, tokens, tables, compiler)
    check_package_name_shadows(env, source, files, tokens, tables, compiler)
    check_package_eligibility(env, source, files, tokens, tables, compiler)
    check_struct_declarations(env, source, files, tokens, tables, compiler)
    register_package_declarations(env, source, files, tokens, tables, config, compiler)
    let _entry = check_entry_signature(env, source, files, tokens, tables, compiler, false)
    check_package_bodies(env, source, files, tokens, tables, config, compiler)
    check_deferred_large_value_gate(env, source, files, tokens, tables, compiler)
    add_default_call_graph_edges(tables, compiler)
    check_call_cycles(env, source, files, tokens, tables, compiler)
    mark_struct_helpers(source, files, tokens, tables, compiler)
    propagate_sum_type_helpers(compiler)
    for function_id in 0L..compiler.functions.count() {
        emit_function_definition(source, files, tokens, tables, compiler, ir, function_id)
    }
    emit_registered_type_helpers(source, files, tokens, tables, compiler, ir)
    if prelude_only { return !compiler.ir_overflow }
    emit_core_file_globals(source, files, tokens, tables, compiler, ir)
    emit_core_registration(files, compiler, ir)
    emit_syscall_helpers(compiler, ir)
    ir_write_ascii(compiler, ir, "@llvm.compiler.used = appending global [5 x ptr] [ptr @memcpy, ptr @memmove, ptr @memset, ptr @memcmp, ptr @bcmp], section \"llvm.metadata\"\n")
    emit_core_start_assembly(compiler, ir)
    !compiler.ir_overflow
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn compile_selfhost_package(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    config: MemoryConfig,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    want_test_build: bool,
    core_hash: Ascii max 64,
) {
    compiler.test_build = want_test_build
    check_struct_declarations(env, source, files, tokens, tables, compiler)
    register_package_declarations(env, source, files, tokens, tables, config, compiler)
    initialize_default_graph_nodes(compiler)
    let entry = check_entry_signature(env, source, files, tokens, tables, compiler, !want_test_build)
    check_struct_defaults(env, source, files, tokens, tables, config, compiler)
    check_package_bodies(env, source, files, tokens, tables, config, compiler)
    check_deferred_large_value_gate(env, source, files, tokens, tables, compiler)
    add_default_call_graph_edges(tables, compiler)
    check_call_cycles(env, source, files, tokens, tables, compiler)
    check_native_frame_budget(env, source, files, tokens, tables, compiler, entry, want_test_build)
    mark_struct_helpers(source, files, tokens, tables, compiler)
    propagate_sum_type_helpers(compiler)
    ir_write_ascii(compiler, ir, "; nlc-link-ir 2\n; nlc.build ")
    ir_write_ascii(compiler, ir, if want_test_build { "test" } else { "program" })
    ir_write_ascii(compiler, ir, "\n; nlc.stack offset\n; nlc.recursion none\n")
    ir_write_ascii(compiler, ir, if compiler.c_runtime { "; nlc.runtime c\n" } else { "; nlc.runtime core\n" })
    ir_write_ascii(compiler, ir, "; nlc.core ")
    ir_write_ascii(compiler, ir, core_hash)
    ir_write_ascii(compiler, ir, "\n")
    for test_index in 0L..compiler.tests.count() {
        let test = compiler.tests[test_index]
        let name = decode_string_token(source, tokens, files[test.file].base, test.name_token, false)
        ir_write_ascii(compiler, ir, "; nlc.test ")
        ir_write_number(compiler, ir, test_index)
        ir_write_ascii(compiler, ir, " ")
        for index in 0L..name.count() {
            ir_push_byte(compiler, ir, ir_hex_digit(name[index].to_long() / 16L, true))
            ir_push_byte(compiler, ir, ir_hex_digit(name[index].to_long() % 16L, true))
        }
        ir_write_ascii(compiler, ir, "\n")
    }
    ir_write_ascii(compiler, ir, "source_filename = \"next-lang\"\n\ndeclare { i32, i1 } @llvm.sadd.with.overflow.i32(i32, i32)\ndeclare { i32, i1 } @llvm.ssub.with.overflow.i32(i32, i32)\ndeclare { i32, i1 } @llvm.smul.with.overflow.i32(i32, i32)\ndeclare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)\ndeclare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)\ndeclare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)\ndeclare void @llvm.trap()\ndeclare i32 @llvm.smin.i32(i32, i32)\ndeclare i32 @llvm.smax.i32(i32, i32)\ndeclare i64 @llvm.smin.i64(i64, i64)\ndeclare i64 @llvm.smax.i64(i64, i64)\ndeclare i32 @llvm.abs.i32(i32, i1)\ndeclare i64 @llvm.abs.i64(i64, i1)\n")
    ir_write_ascii(compiler, ir, "\n")
    if compiler.c_runtime { emit_c_runtime_adapters(compiler, ir) }
    for function_id in 0L..compiler.functions.count() {
        emit_function_definition(source, files, tokens, tables, compiler, ir, function_id)
    }
    for test_index in 0L..compiler.tests.count() {
        emit_test_definition(source, files, tokens, tables, compiler, ir, test_index)
    }
    emit_registered_type_helpers(source, files, tokens, tables, compiler, ir)
    emit_file_globals(files, source, tokens, tables, compiler, ir)
    emit_main_function(source, compiler, ir, files, tokens, config, entry)
    emit_job_entries(files, tables, compiler, ir, config)
    let user_ir_overflow = compiler.ir_overflow
    let prelude_only = compiler.c_runtime
    if !compile_embedded_core(env, config, ir, files.count(), want_test_build, tables, compiler, prelude_only) {
        fail_parse_limit(env, files[0].name, "self-hosted LLVM IR buffer limit exceeded")
    }
    compiler.ir_overflow = compiler.ir_overflow || user_ir_overflow
    emit_storage_tbaa_metadata(compiler, ir)
    ir_write_ascii(compiler, ir, "\n; nlc-link-ir end\n")
}
// E3a1 end

// Checker order follows checker.rs. main first loads and parses every sorted
// file, reads package.toml, builds child/sibling links and interns names, then
// runs check_package_eligibility over all nodes. That pass picks the lowest
// file/offset and the outer node at a shared offset, before any checker error.
// compile_selfhost_package then registers declarations, checks the entry,
// checks function bodies in declaration order and tests in declaration order,
// and only after every body checks call cycles. Registration is file ordered;
// each file's functions are checked before that file's tests. A function's
// built-in-name and duplicate checks precede its parameter/result types, in
// source order; test duplicates are checked while that file's tests register.
//
// Body checking uses the explicit CheckFrame stack below. Child visitation is
// source order except where expected-type inference requires Rust's order:
// check_operand_pair visits the right operand first when only the left is an
// unsuffixed literal with no expected type. Literal range checks wait until an
// annotation, parameter, result, return, or peer operand supplies context.
// Loop counter constraints from annotation, natural bound types, and body uses
// are joined before either bound is checked. Fall-through/never facts are
// finalized for each block before missing-return and unit-tail checks. These
// order points are pinned by the E1 checker-order fixtures and comparison
// harness.


// The image of an array constant: the array exactly as a variable of that type would hold it, so a
// use can copy it into place. Integer elements are little-endian.
fn emit_array_constant_global(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    declaration: long,
) {
    let declared = compiler.facts[declaration].ty
    let element = collection_element_type(compiler, declared)
    let stride = value_type_size(compiler, element)
    let capacity = collection_capacity(compiler, declared)
    var item = compiler.child_first[node_last_child(tables, compiler, declaration)]
    ir_write_ascii(compiler, ir, "@.nl.const."); ir_write_number(compiler, ir, declaration)
    ir_write_ascii(compiler, ir, " = private unnamed_addr constant ["); ir_write_number(compiler, ir, value_type_size(compiler, declared))
    ir_write_ascii(compiler, ir, " x i8] c\"")
    for index in 0L..capacity {
        if type_kind(compiler, element) == TYPE_KIND_ASCII {
            // [length: i64][bytes][zero padding up to the element size], as a variable would hold it
            let literal = decode_string_token(source, tokens, files[node_file_index(tables.nodes, files, declaration)].base, tables.nodes[item].token, false)
            let data_offset = text_data_offset(compiler, element)
            for shift in 0L..8L { ir_write_hex_escaped(compiler, ir, (literal.count() >> (shift * 8L)) & 255L) }
            for gap in 8L..data_offset { ir_write_hex_escaped(compiler, ir, 0L) }
            for position in 0L..literal.count() { ir_write_hex_escaped(compiler, ir, literal[position].to_long()) }
            for pad in data_offset + literal.count()..stride { ir_write_hex_escaped(compiler, ir, 0L) }
        } else {
            let magnitude = tables.literals[tables.nodes[item].extra]
            let raw = magnitude.limb1 * 4294967296L + magnitude.limb0
            let value = if (tables.nodes[item].flags & FLAG_NEGATIVE) != 0L { 0L - raw } else { raw }
            for shift in 0L..stride { ir_write_hex_escaped(compiler, ir, (value >> (shift * 8L)) & 255L) }
        }
        item = compiler.child_next[item]
    }
    ir_write_ascii(compiler, ir, "\", align 8\n")
}
