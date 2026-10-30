// sort(list) and sort_by(list, ctx, compare) on the C runtime. Each call site gets one generated
// function: a stable bottom-up merge sort over the collection's elements in place, using a
// temporary run of the data stack for the merge buffer. `sort` orders int, long or byte elements
// by value. `sort_by` calls the named comparator `compare(ctx, a, b) -> bool` ("a goes before b");
// ctx is an int, long or bool passed by value, and the elements are passed as read-only locations
// (or by value when they are numbers).

const SORT_NONE: long = 0L
const SORT_PLAIN: long = 1L
const SORT_BY: long = 2L

fn sort_builtin_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    token: long,
    scope: long,
) -> long {
    if !compiler.c_runtime { return SORT_NONE }
    let kind = if token_is_word_at(source, tokens, files, file_index, token, "sort") { SORT_PLAIN }
        else if token_is_word_at(source, tokens, files, file_index, token, "sort_by") { SORT_BY }
        else { SORT_NONE }
    if kind == SORT_NONE { return SORT_NONE }
    let name_id = compiler.token_name_ids[token]
    if find_function_by_name(compiler, name_id) >= 0L { return SORT_NONE }
    if scope >= 0L && find_binding_in_scope(compiler, scope, name_id) >= 0L { return SORT_NONE }
    kind
}

// The named comparator of a sort_by call: the third argument, when it names a function.
fn is_sort_comparator_name(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
) -> bool {
    if !compiler.c_runtime { return false }
    let parent = region_parent_node(tables, node)
    if parent < 0L || tables.nodes[parent].kind != NodeKind.Call { return false }
    if !token_is_word_at(source, tokens, files, file_index, tables.nodes[parent].token, "sort_by") { return false }
    if find_function_by_name(compiler, compiler.token_name_ids[tables.nodes[parent].token]) >= 0L { return false }
    let first = compiler.child_first[parent]
    let second = if first >= 0L { compiler.child_next[first] } else { -1L }
    let third = if second >= 0L { compiler.child_next[second] } else { -1L }
    third == node && compiler.child_next[third] < 0L
}

fn sort_element_is_number(type_id: long) -> bool {
    type_id == TY_INT || type_id == TY_LONG || type_id == TY_BYTE
}

fn check_sort_builtin(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    node: long,
    scope: long,
    sort_kind: long,
) -> long {
    let syntax = tables.nodes[node]
    let arg_count = count_children(tables, compiler, node)
    let wanted = if sort_kind == SORT_PLAIN { 1L } else { 3L }
    if arg_count != wanted {
        let shape: Ascii max 96 = if sort_kind == SORT_PLAIN { "sort takes one writable list or array" } else { "sort_by takes a writable list or array, a context, and a comparator" }
        fail_at_message(env, files, compiler, file_index, syntax.start, shape)
    }
    let collection = child_at(tables, compiler, node, 0L)
    let collection_ty = compiler.facts[collection].ty
    let collection_kind = type_kind(compiler, collection_ty)
    if collection_kind != TYPE_KIND_ARRAY && collection_kind != TYPE_KIND_LIST {
        fail_at_message(env, files, compiler, file_index, tables.nodes[collection].start, "sort needs a writable list or array")
    }
    let binding = place_root_binding(tables, compiler, collection)
    if binding < 0L || !compiler.bindings[binding].mutable || !is_assignable_place(tables, collection) {
        fail_at_message(env, files, compiler, file_index, tables.nodes[collection].start, "sort needs a writable list or array")
    }
    let element = collection_element_type(compiler, collection_ty)
    var comparator = -1L
    if sort_kind == SORT_PLAIN {
        if !sort_element_is_number(element) {
            fail_at_message(env, files, compiler, file_index, tables.nodes[collection].start, "sort needs a list or array of int, long or byte; use sort_by for other elements")
        }
    } else {
        let context = child_at(tables, compiler, node, 1L)
        let context_ty = compiler.facts[context].ty
        if context_ty != TY_INT && context_ty != TY_LONG && context_ty != TY_BOOL {
            fail_at_message(env, files, compiler, file_index, tables.nodes[context].start, "sort_by context must be an int, long or bool")
        }
        if !sort_element_is_number(element) && !is_aggregate_type(compiler, element) {
            fail_at_message(env, files, compiler, file_index, tables.nodes[collection].start, "sort_by needs a list or array of numbers or records")
        }
        let name_node = child_at(tables, compiler, node, 2L)
        comparator = compiler.facts[name_node].function
        if comparator < 0L || tables.nodes[name_node].kind != NodeKind.Name {
            fail_at_message(env, files, compiler, file_index, tables.nodes[name_node].start, "sort_by needs the name of a comparator function")
        }
        let function = compiler.functions[comparator]
        if function.param_count != 3L || function.result_ty != TY_BOOL ||
            compiler.parameters[function.param_start].ty != context_ty ||
            compiler.parameters[function.param_start + 1L].ty != element ||
            compiler.parameters[function.param_start + 2L].ty != element ||
            (parameter_mode(compiler.parameters[function.param_start]) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L ||
            (parameter_mode(compiler.parameters[function.param_start + 1L]) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L ||
            (parameter_mode(compiler.parameters[function.param_start + 2L]) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
            fail_at_message(env, files, compiler, file_index, tables.nodes[name_node].start, "the comparator must be fn(context, a, b) -> bool with read-only parameters of the context and element types")
        }
    }
    comparator
}

// ---- generated sort function ------------------------------------------------------------------

fn emit_sort_function(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    collection_ty: long,
    comparator: long,
    context_ty: long,
) {
    let element = collection_element_type(compiler, collection_ty)
    let stride = value_type_size(compiler, element)
    let is_list = collection_kind_is_list(type_kind(compiler, collection_ty))
    let base_offset = collection_element_base_offset(compiler, collection_ty)
    let capacity = collection_capacity(compiler, collection_ty)
    let align = if value_type_align(compiler, element) > 8L { value_type_align(compiler, element) } else { 8L }
    let element_llvm = if sort_element_is_number(element) { llvm_type_name(element) } else { "ptr" }
    if stride <= 0L || base_offset < 0L { compiler.ir_overflow = true; return }

    ir_write_ascii(compiler, ir, "define void @nl.sort."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top, ptr %list")
    if comparator >= 0L { ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_type_name(context_ty)); ir_write_ascii(compiler, ir, " %c") }
    ir_write_ascii(compiler, ir, ") {\nentry:\n")
    if is_list {
        ir_write_ascii(compiler, ir, "  %n = load i64, ptr %list\n")
    } else {
        ir_write_ascii(compiler, ir, "  %n = add i64 0, "); ir_write_number(compiler, ir, capacity); ir_push_byte(compiler, ir, 10)
    }
    ir_write_ascii(compiler, ir, "  %data = getelementptr i8, ptr %list, i64 "); ir_write_number(compiler, ir, base_offset)
    ir_write_ascii(compiler, ir, "\n  %small = icmp ule i64 %n, 1\n  br i1 %small, label %done, label %prep\nprep:\n  %bytes = mul i64 %n, "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, "\n  %tmp.off = call i64 @nl_stack_alloc_offset(ptr %nl.ctx, i64 %nl.top, i64 %bytes, i64 "); ir_write_number(compiler, ir, align)
    ir_write_ascii(compiler, ir, ", i32 0, i32 0, i32 0)\n  %tmp.top = add i64 %tmp.off, %bytes\n  %base = call ptr @nlc_context_current_base(ptr %nl.ctx)\n  %buf = getelementptr i8, ptr %base, i64 %tmp.off\n  br label %pass.head\n")
    ir_write_ascii(compiler, ir, "pass.head:\n  %w = phi i64 [ 1, %prep ], [ %w2, %pass.next ]\n  %wlt = icmp ult i64 %w, %n\n  br i1 %wlt, label %run.head, label %done\n")
    ir_write_ascii(compiler, ir, "run.head:\n  %lo = phi i64 [ 0, %pass.head ], [ %hi, %run.next ]\n  %more = icmp ult i64 %lo, %n\n  br i1 %more, label %run.body, label %copyback\n")
    ir_write_ascii(compiler, ir, "run.body:\n  %mid0 = add i64 %lo, %w\n  %mid.big = icmp ugt i64 %mid0, %n\n  %mid = select i1 %mid.big, i64 %n, i64 %mid0\n  %hi0 = add i64 %mid, %w\n  %hi.big = icmp ugt i64 %hi0, %n\n  %hi = select i1 %hi.big, i64 %n, i64 %hi0\n  br label %merge.head\n")
    ir_write_ascii(compiler, ir, "merge.head:\n  %i = phi i64 [ %lo, %run.body ], [ %i.l, %take.left ], [ %i, %take.right ]\n  %j = phi i64 [ %mid, %run.body ], [ %j, %take.left ], [ %j.r, %take.right ]\n")
    ir_write_ascii(compiler, ir, "  %k = phi i64 [ %lo, %run.body ], [ %k.l, %take.left ], [ %k.r, %take.right ]\n  %merged = icmp uge i64 %k, %hi\n  br i1 %merged, label %run.next, label %merge.pick\n")
    ir_write_ascii(compiler, ir, "merge.pick:\n  %left.empty = icmp uge i64 %i, %mid\n  br i1 %left.empty, label %take.right, label %check.right\ncheck.right:\n  %right.empty = icmp uge i64 %j, %hi\n  br i1 %right.empty, label %take.left, label %compare\ncompare:\n")
    ir_write_ascii(compiler, ir, "  %ja = mul i64 %j, "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, "\n  %pa = getelementptr i8, ptr %data, i64 %ja\n  %ib = mul i64 %i, "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, "\n  %pb = getelementptr i8, ptr %data, i64 %ib\n")
    if comparator < 0L {
        ir_write_ascii(compiler, ir, "  %va = load "); ir_write_ascii(compiler, ir, element_llvm); ir_write_ascii(compiler, ir, ", ptr %pa\n  %vb = load ")
        ir_write_ascii(compiler, ir, element_llvm); ir_write_ascii(compiler, ir, ", ptr %pb\n  %less = icmp slt "); ir_write_ascii(compiler, ir, element_llvm); ir_write_ascii(compiler, ir, " %va, %vb\n")
    } else {
        var left_argument: Ascii max 48 = "ptr %pa, i64 0"
        var right_argument: Ascii max 48 = "ptr %pb, i64 0"
        if sort_element_is_number(element) {
            ir_write_ascii(compiler, ir, "  %va = load "); ir_write_ascii(compiler, ir, element_llvm); ir_write_ascii(compiler, ir, ", ptr %pa\n  %vb = load "); ir_write_ascii(compiler, ir, element_llvm); ir_write_ascii(compiler, ir, ", ptr %pb\n")
            left_argument = "i32 %va"
            right_argument = "i32 %vb"
            if element == TY_LONG { left_argument = "i64 %va"; right_argument = "i64 %vb" }
        }
        ir_write_ascii(compiler, ir, "  %less = call i1 @nl_fn_"); ir_write_number(compiler, ir, comparator); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %tmp.top, ")
        ir_write_ascii(compiler, ir, llvm_type_name(context_ty)); ir_write_ascii(compiler, ir, " %c, "); ir_write_ascii(compiler, ir, left_argument); ir_write_ascii(compiler, ir, ", ")
        ir_write_ascii(compiler, ir, right_argument); ir_write_ascii(compiler, ir, ")\n")
    }
    ir_write_ascii(compiler, ir, "  br i1 %less, label %take.right, label %take.left\n")
    ir_write_ascii(compiler, ir, "take.left:\n  %src.l = mul i64 %i, "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, "\n  %sp.l = getelementptr i8, ptr %data, i64 %src.l\n  %dst.l = mul i64 %k, "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, "\n  %dp.l = getelementptr i8, ptr %buf, i64 %dst.l\n  %cp.l = call ptr @memcpy(ptr %dp.l, ptr %sp.l, i64 "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, ")\n  %i.l = add i64 %i, 1\n  %k.l = add i64 %k, 1\n  br label %merge.head\n")
    ir_write_ascii(compiler, ir, "take.right:\n  %src.r = mul i64 %j, "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, "\n  %sp.r = getelementptr i8, ptr %data, i64 %src.r\n  %dst.r = mul i64 %k, "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, "\n  %dp.r = getelementptr i8, ptr %buf, i64 %dst.r\n  %cp.r = call ptr @memcpy(ptr %dp.r, ptr %sp.r, i64 "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, ")\n  %j.r = add i64 %j, 1\n  %k.r = add i64 %k, 1\n  br label %merge.head\n")
    ir_write_ascii(compiler, ir, "run.next:\n  br label %run.head\ncopyback:\n  %total = mul i64 %n, "); ir_write_number(compiler, ir, stride)
    ir_write_ascii(compiler, ir, "\n  %cb = call ptr @memcpy(ptr %data, ptr %buf, i64 %total)\n  br label %pass.next\npass.next:\n  %w2 = mul i64 %w, 2\n  br label %pass.head\ndone:\n  ret void\n}\n\n")
}

// One sort function per sort or sort_by call node.
fn emit_sort_functions(tables: ParseTables, compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    if !compiler.c_runtime { return }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind != NodeKind.Call || (compiler.facts[node].flags & FACT_SORT_BUILTIN) == 0L { continue }
        let collection = compiler.child_first[node]
        let comparator = compiler.facts[node].literal
        let context_ty = if comparator >= 0L { compiler.facts[compiler.child_next[collection]].ty } else { TY_INT }
        let collection_ty = compiler.facts[collection].ty
        emit_sort_function(compiler, ir, node, collection_ty, comparator, context_ty)
    }
}

// The call site: pass the collection's address (and the context) to the generated function.
fn emit_sort_call(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let collection = compiler.child_first[node]
    var location = collection_value_location(tables, compiler, collection)
    if tables.nodes[collection].kind == NodeKind.Field {
        let address_id = emit_late_place_address(tables, compiler, ir, collection)
        location = compiler_location(compiler, 2L, address_id, 0L)
    }
    let pointer_serial = emit_location_pointer_materialization(compiler, ir, location)
    emit_current_top_load(compiler, ir, node)
    let comparator = compiler.facts[node].literal
    ir_write_ascii(compiler, ir, "  call void @nl.sort."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 ")
    emit_current_top_reference(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr ")
    emit_location_pointer_reference(compiler, ir, location, pointer_serial)
    if comparator >= 0L {
        let context = compiler.child_next[collection]
        ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[context].ty)); ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, context)
    }
    ir_write_ascii(compiler, ir, ")\n")
}
