// Jobs: `spawn f(a, b)` starts f on a thread of its own. The arguments are evaluated here, copied into a block
// the runtime allocates (eight bytes each), and the thread's entry, generated once per spawn site, creates a
// job context (its own data stack), loads the arguments and calls f. The runtime waits for every job before the
// program ends.

const JOB_ARGUMENT_BYTES: long = 8L

// Bytes a parameter takes in the argument block: eight for a number or a handle, a struct's size rounded up to eight.
fn job_slot_bytes(compiler: CompilerTables, ty: long) -> long {
    if is_aggregate_type(compiler, ty) {
        let size = value_type_size(compiler, ty)
        if size <= 0L { JOB_ARGUMENT_BYTES } else { ((size + 7L) / 8L) * 8L }
    } else { JOB_ARGUMENT_BYTES }
}

// Where parameter `index` starts in the block, and the block's whole size (index = param_count).
fn job_slot_offset(compiler: CompilerTables, target: FunctionRecord, index: long) -> long {
    var offset = 0L
    for parameter_index in 0L..index {
        offset += job_slot_bytes(compiler, compiler.parameters[target.param_start + parameter_index].ty)
    }
    offset
}

fn job_call_node(tables: ParseTables, compiler: CompilerTables, spawn: long) -> long {
    compiler.child_first[spawn]
}

// Evaluate the arguments, copy them into a fresh block and start the thread.
recursive fn emit_spawn_statement(
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
    let call = job_call_node(tables, compiler, node)
    let target = compiler.functions[compiler.facts[call].function]
    var argument = compiler.child_first[call]
    for parameter_index in 0L..target.param_count {
        if argument < 0L { compiler.ir_overflow = true; return }
        let parameter = compiler.parameters[target.param_start + parameter_index]
        // A parameter that is an aggregate handle needs its address materialised by the ordinary expression path.
        var is_parameter = false
        if tables.nodes[argument].kind == NodeKind.Name {
            let argument_binding = compiler.facts[argument].binding
            is_parameter = argument_binding >= 0L && argument_binding < compiler.bindings.count() && compiler.bindings[argument_binding].parameter
        }
        let place = tables.nodes[argument].kind == NodeKind.Name && !is_parameter
        // A handle held in a variable or field is read in place; any other handle is built first.
        if !(is_aggregate_type(compiler, parameter.ty) && place) {
            emit_expr_linear(source, files, tokens, tables, compiler, ir, argument, file_index, return_ty, is_test)
        }
        argument = compiler.child_next[argument]
    }
    ir_write_ascii(compiler, ir, "  %spawn.args."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = call ptr @nl_job_args_alloc(i64 "); ir_write_number(compiler, ir, job_slot_offset(compiler, target, target.param_count))
    ir_write_ascii(compiler, ir, ")\n")
    argument = compiler.child_first[call]
    for parameter_index in 0L..target.param_count {
        let parameter = compiler.parameters[target.param_start + parameter_index]
        ir_write_ascii(compiler, ir, "  %spawn.slot."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, parameter_index)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %spawn.args."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, job_slot_offset(compiler, target, parameter_index))
        if is_aggregate_type(compiler, parameter.ty) {
            // A struct (a mailbox handle is one 64-bit word) is copied into its slot as it is.
            let source_location = aggregate_source_location_for_node(tables, compiler, argument)
            let source_pointer = emit_location_pointer_materialization(compiler, ir, source_location)
            ir_write_ascii(compiler, ir, "\n  %spawn.copy."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, parameter_index)
            ir_write_ascii(compiler, ir, " = call ptr @memmove(ptr %spawn.slot."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, parameter_index)
            ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, value_type_size(compiler, parameter.ty)); ir_write_ascii(compiler, ir, ")\n")
            argument = compiler.child_next[argument]
            continue
        } else {
            ir_write_ascii(compiler, ir, "\n  store "); ir_write_ascii(compiler, ir, llvm_type_name(parameter.ty)); ir_push_byte(compiler, ir, 32)
            ir_write_value_ref(compiler, ir, argument)
        }
        ir_write_ascii(compiler, ir, ", ptr %spawn.slot."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, parameter_index)
        ir_write_ascii(compiler, ir, ", align 1\n")
        argument = compiler.child_next[argument]
    }
    ir_write_ascii(compiler, ir, "  call void @nl_job_start(ptr @nl.job."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %spawn.args."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
    // Remember the site so its thread entry is emitted (only sites in emitted functions have an entry).
    compiler.facts[node].literal = 1L
}

// One thread entry per spawn site: make the job's context, read the arguments, call the function.
fn emit_job_entries(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    config: MemoryConfig,
) {
    if !compiler.c_runtime { return }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind != NodeKind.Spawn || compiler.facts[node].literal != 1L { continue }
        let call = job_call_node(tables, compiler, node)
        let target_id = compiler.facts[call].function
        let target = compiler.functions[target_id]
        let file_index = node_file_index(tables.nodes, files, node)
        ir_write_ascii(compiler, ir, "define ptr @nl.job."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, "(ptr %args) {\nentry:\n  %ctx = call ptr @nl_context_create_job(i64 4096, i64 "); ir_write_number(compiler, ir, config.recursion_budget)
        ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds (["); ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.file."); ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0))\n  %top = call i64 @nl_context_base_offset(ptr %ctx)\n")
        for parameter_index in 0L..target.param_count {
            let parameter = compiler.parameters[target.param_start + parameter_index]
            ir_write_ascii(compiler, ir, "  %slot."); ir_write_number(compiler, ir, parameter_index)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %args, i64 "); ir_write_number(compiler, ir, job_slot_offset(compiler, target, parameter_index))
            if !is_aggregate_type(compiler, parameter.ty) {
                ir_write_ascii(compiler, ir, "\n  %a."); ir_write_number(compiler, ir, parameter_index)
                ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(parameter.ty))
                ir_write_ascii(compiler, ir, ", ptr %slot."); ir_write_number(compiler, ir, parameter_index); ir_write_ascii(compiler, ir, ", align 1")
            }
            ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  call void @nl_fn_"); ir_write_number(compiler, ir, target_id); ir_write_ascii(compiler, ir, "(ptr %ctx, i64 %top")
        for parameter_index in 0L..target.param_count {
            let parameter = compiler.parameters[target.param_start + parameter_index]
            if is_aggregate_type(compiler, parameter.ty) {
                // The handle is read in place from the argument block (a descriptor: an address and an offset).
                ir_write_ascii(compiler, ir, ", ptr %slot."); ir_write_number(compiler, ir, parameter_index); ir_write_ascii(compiler, ir, ", i64 0")
            } else {
                ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_type_name(parameter.ty))
                ir_write_ascii(compiler, ir, " %a."); ir_write_number(compiler, ir, parameter_index)
            }
        }
        ir_write_ascii(compiler, ir, ")\n  call void @nl_context_destroy(ptr %ctx)\n  call void @nl_job_args_free(ptr %args)\n  ret ptr null\n}\n\n")
    }
}

// A value `spawn` may copy into a job's argument block: plain records (numbers, enums, text and bytes, and structs, arrays
// and lists of them). Pools, maps and the like stay with their owner.
recursive fn job_copyable_type(compiler: CompilerTables, type_id: long) -> bool {
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_SCALAR || kind == TYPE_KIND_ENUM || kind == TYPE_KIND_ASCII || kind == TYPE_KIND_TEXT || kind == TYPE_KIND_BYTES { return true }
    if kind == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_offset in 0L..record.field_count {
            if !job_copyable_type(compiler, compiler.struct_fields[record.field_start + field_offset].ty) { return false }
        }
        true
    } else if kind == TYPE_KIND_ARRAY || kind == TYPE_KIND_LIST {
        job_copyable_type(compiler, collection_element_type(compiler, type_id))
    } else { false }
}
