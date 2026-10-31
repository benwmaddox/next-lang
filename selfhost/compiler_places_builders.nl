fn place_path_component_node(tables: ParseTables, compiler: CompilerTables, node: long, depth: long, component: long) -> long {
    if component < 0L || component >= depth { return -1L }
    var current = node
    let steps_from_leaf = depth - component - 1L
    for step in 0L..steps_from_leaf {
        if current < 0L { return -1L }
        current = compiler.child_first[current]
    }
    current
}

recursive fn places_overlap(tables: ParseTables, compiler: CompilerTables, left: long, right: long) -> bool {
    if left < 0L || right < 0L { return false }
    let left_root = place_alias_root_binding(tables, compiler, left)
    let right_root = place_alias_root_binding(tables, compiler, right)
    if left_root < 0L || left_root != right_root { return false }
    let left_depth = place_path_depth(tables, compiler, left)
    let right_depth = place_path_depth(tables, compiler, right)
    if left_depth < 0L || right_depth < 0L { return true }
    let common_depth = if left_depth < right_depth { left_depth } else { right_depth }
    for component in 0L..common_depth {
        let left_part = place_path_component_node(tables, compiler, left, left_depth, component)
        let right_part = place_path_component_node(tables, compiler, right, right_depth, component)
        if left_part < 0L || right_part < 0L { return true }
        let left_kind = tables.nodes[left_part].kind
        let right_kind = tables.nodes[right_part].kind
        if left_kind != right_kind { return true }
        if left_kind == NodeKind.Field && compiler.facts[left_part].literal != compiler.facts[right_part].literal { return false }
        if left_kind == NodeKind.Index {
            let left_receiver = compiler.child_first[left_part]
            let right_receiver = compiler.child_first[right_part]
            let left_index = if left_receiver >= 0L { compiler.child_next[left_receiver] } else { -1L }
            let right_index = if right_receiver >= 0L { compiler.child_next[right_receiver] } else { -1L }
            if left_index >= 0L && right_index >= 0L {
                let left_constant = evaluate_collection_capacity(tables, compiler, left_index, 0L)
                let right_constant = evaluate_collection_capacity(tables, compiler, right_index, 0L)
                if left_constant.constant && left_constant.valid && right_constant.constant && right_constant.valid && left_constant.value != right_constant.value { return false }
            }
        }
    }
    true
}

fn active_view_overlaps_place(
    tables: ParseTables,
    compiler: CompilerTables,
    scope: long,
    place: long,
) -> bool {
    if place_root_is_view(tables, compiler, place) { return false }
    for binding_id in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_id]
        if !binding_is_view(compiler, binding_id) || !binding_is_visible(compiler, scope, binding.scope) { continue }
        let loop_node = binding.node
        let collection = compiler.child_first[loop_node]
        if collection >= 0L && places_overlap(tables, compiler, place, collection) { return true }
    }
    false
}

fn write_text_builder_descriptor(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    type_id: long,
) {
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_ASCII || kind == TYPE_KIND_BYTES {
        match env.err.write(if kind == TYPE_KIND_ASCII { b"Ascii max " } else { b"Bytes max " }) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(text_max_bytes(compiler, type_id)).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    } else if kind == TYPE_KIND_TEXT {
        match env.err.write(b"Text max ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(text_max_codepoints(compiler, type_id)).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b" bytes max ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(text_max_bytes(compiler, type_id)).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    } else {
        write_type_name(env, source, files, tokens, compiler, type_id)
    }
}

fn fail_grow_argument_width_mismatch(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    expected: long,
    actual: long,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + offset, compiler)
    let kind = type_kind(compiler, expected)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: grow argument needs ") { ok(_) => (), err(_) => env.exit(3) }
    if kind == TYPE_KIND_ASCII { match env.err.write(b"an Ascii") { ok(_) => (), err(_) => env.exit(3) } }
    else if kind == TYPE_KIND_TEXT { match env.err.write(b"a Text") { ok(_) => (), err(_) => env.exit(3) } }
    else { match env.err.write(b"a Bytes") { ok(_) => (), err(_) => env.exit(3) } }
    match env.err.write(b" builder with exactly ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(text_max_bytes(compiler, expected)).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    if kind == TYPE_KIND_TEXT {
        match env.err.write(b" bytes and ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(text_max_codepoints(compiler, expected)).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b" code points reserved; found ") { ok(_) => (), err(_) => env.exit(3) }
    } else { match env.err.write(b" bytes reserved; found ") { ok(_) => (), err(_) => env.exit(3) } }
    write_text_builder_descriptor(env, source, files, tokens, compiler, actual)
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_builder_argument_type(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    receiver_kind: long,
    actual: long,
    is_push: bool,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + offset, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: ") { ok(_) => (), err(_) => env.exit(3) }
    if is_push { match env.err.write(b"Bytes.push needs byte; found ") { ok(_) => (), err(_) => env.exit(3) } }
    else if receiver_kind == TYPE_KIND_ASCII { match env.err.write(b"try_append needs Ascii; found ") { ok(_) => (), err(_) => env.exit(3) } }
    else if receiver_kind == TYPE_KIND_TEXT { match env.err.write(b"Text.try_append needs Text or Ascii; found ") { ok(_) => (), err(_) => env.exit(3) } }
    else { match env.err.write(b"try_append needs Bytes; found ") { ok(_) => (), err(_) => env.exit(3) } }
    if is_push { write_type_name(env, source, files, tokens, compiler, actual) }
    else { write_text_builder_descriptor(env, source, files, tokens, compiler, actual) }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn check_call_write_modes(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    function: FunctionRecord,
    call_node: long,
    file_index: long,
    scope: long,
) {
    let first_argument = compiler.child_first[call_node]
    var argument = first_argument
    for argument_index in 0L..function.param_count {
        let parameter = compiler.parameters[function.param_start + argument_index]
        let mode = parameter_mode(parameter)
        if (mode & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
            if !is_assignable_place(tables, argument) { fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "a write argument must be an assignable place") }
            let binding = place_root_binding(tables, compiler, argument)
            if binding < 0L || !compiler.bindings[binding].mutable {
                fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start,
                    "a write argument must be a var, a field of a var, or another write parameter")
            }
            if active_view_overlaps_place(tables, compiler, scope, argument) {
                fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "cannot pass storage containing a live collection view as write")
            }
            if (mode & FLAG_MODE_GROW) != 0L && !grow_text_width_matches(compiler, compiler.facts[argument].ty, parameter.ty) {
                fail_grow_argument_width_mismatch(env, source, files, tokens, compiler, file_index,
                    tables.nodes[argument].start, parameter.ty, compiler.facts[argument].ty)
            }
        }
        var previous = first_argument
        for previous_index in 0L..argument_index {
            let previous_parameter = compiler.parameters[function.param_start + previous_index]
            let current_mutable = (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L
            let previous_mutable = (parameter_mode(previous_parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L
            if previous_index < argument_index && (current_mutable || previous_mutable) && places_overlap(tables, compiler, argument, previous) {
                fail_at_message(env, files, compiler, file_index, tables.nodes[call_node].start, "arguments overlap, and at least one is passed as write; pass separate fields or a copy")
            }
            previous = compiler.child_next[previous]
        }
        argument = compiler.child_next[argument]
    }
}

fn is_numeric_type(ty: long) -> bool { ty == TY_INT || ty == TY_LONG }

fn fail_at_message(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    message: Ascii max 160,
) -> never {
    fail_compiler_diagnostic(env, files[file_index].name, files, file_index, offset, compiler, message)
}

fn fail_ascii_append_unproven(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    assignment: long,
    target: long,
    maximum: long,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[assignment].start, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: cannot prove this append fits Ascii max ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(maximum).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"; use '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[file_index].base, tables.nodes[target].token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b".try_append(value)' and handle Full") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn conditional_builder_loop_ancestor(tables: ParseTables, node: long) -> long {
    var current = node
    var conditional = false
    for step in 0L..MAX_TREE_NODES {
        let parent = region_parent_node(tables, current)
        if parent < 0L { return -1L }
        let kind = tables.nodes[parent].kind
        if kind == NodeKind.If || kind == NodeKind.Match { conditional = true }
        if conditional && (kind == NodeKind.For || kind == NodeKind.ForEach || kind == NodeKind.While) {
            return parent
        }
        current = parent
    }
    -1L
}

fn fail_assignment_error(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    assignment: long,
    binding_id: long,
) -> never {
    let binding = compiler.bindings[binding_id]
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[assignment].start, compiler)
    let target = compiler.child_first[assignment]
    let through_path = target >= 0L && tables.nodes[target].kind == NodeKind.Field
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    if through_path { match env.err.write(b": error: cannot assign through ") { ok(_) => (), err(_) => env.exit(3) } }
    else { match env.err.write(b": error: cannot assign to ") { ok(_) => (), err(_) => env.exit(3) } }
    if binding.loop_counter { match env.err.write(b"loop counter '") { ok(_) => (), err(_) => env.exit(3) } }
    else if binding.parameter { match env.err.write(b"read parameter '") { ok(_) => (), err(_) => env.exit(3) } }
    else { match env.err.write(b"immutable 'let' binding '") { ok(_) => (), err(_) => env.exit(3) } }
    let name_token = binding_name_token(binding)
    match write_token_raw(env.err, source, tokens, files[binding.file].base, name_token) { ok(_) => (), err(_) => env.exit(3) }
    if binding.loop_counter { match env.err.write("'; loop counters are immutable") { ok(_) => (), err(_) => env.exit(3) } }
    else if binding.parameter { match env.err.write("'; pass it as 'write' to allow mutation") { ok(_) => (), err(_) => env.exit(3) } }
    else { match env.err.write("'; declare it with 'var'") { ok(_) => (), err(_) => env.exit(3) } }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_missing_return(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    function: FunctionRecord,
    result_ty: long,
    offset: long,
) -> never {
    let position = position_for_offset(function.file, files[function.file].base + offset, compiler)
    match env.err.write(files[function.file].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: function '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[function.file].base, function.name_token) { ok(_) => (), err(_) => env.exit(3) }
    if result_ty == TY_NEVER {
        match env.err.write(b"' can complete normally; every path in a '-> never' function must end in a never expression\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
    } else {
        match env.err.write(b"' can reach the end without a ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(scalar_type_name(result_ty).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"; return a value on every path\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
    }
}

fn fail_no_return_value(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    result_ty: long,
    function: FunctionRecord,
) -> never {
    if result_ty == TY_NEVER {
        let position = position_for_offset(file_index, files[file_index].base + offset, compiler)
        match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b": error: function '") { ok(_) => (), err(_) => env.exit(3) }
        match write_token_raw(env.err, source, tokens, files[function.file].base, function.name_token) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"' returns never and cannot use 'return'; end every path with a never expression\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
    }
    let message: Ascii max 160 = if result_ty == TY_INT { "this function must return int; add a value after 'return'" }
        else if result_ty == TY_LONG { "this function must return long; add a value after 'return'" }
        else if result_ty == TY_BOOL { "this function must return bool; add a value after 'return'" }
        else { "this function must return a value; add a value after 'return'" }
    fail_at_message(env, files, compiler, file_index, offset, message)
}

fn body_child_expected(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    parent: long,
    child: long,
    frame: CheckFrame,
    child_index: long,
    file_index: long,
    config: MemoryConfig,
) -> long {
    let kind = tables.nodes[parent].kind
    if kind == NodeKind.Block {
        if (tables.nodes[parent].flags & FLAG_HAS_TAIL) != 0L && child == node_last_child(tables, compiler, parent) {
            if frame.expected == TY_UNIT { return -1L }
            return frame.expected
        }
        -1L
    } else if kind == NodeKind.Let {
        if child == frame.child0 && frame.child1 >= 0L { frame.child1 }
        else { -1L }
    } else if kind == NodeKind.Assign {
        if child == frame.child0 { -1L } else { frame.result_ty }
    } else if kind == NodeKind.StructInit {
        frame.auxiliary
    } else if kind == NodeKind.ArrayLiteral {
        if type_kind(compiler, frame.result_ty) == TYPE_KIND_BYTES { TY_BYTE }
        else { collection_element_type(compiler, frame.result_ty) }
    } else if kind == NodeKind.Index && child == frame.child1 {
        TY_LONG
    } else if kind == NodeKind.Field {
        -1L
    } else if kind == NodeKind.Return || kind == NodeKind.ReturnStatement {
        if frame.function_id >= 0L { compiler.functions[frame.function_id].result_ty } else { TY_UNIT }
    } else if kind == NodeKind.ExpressionStatement {
        -1L
    } else if kind == NodeKind.Expect {
        TY_BOOL
    } else if kind == NodeKind.Call {
        if frame.child2 >= 0L { enum_case_payload_type(compiler, frame.child2, child_index) }
        else if frame.auxiliary >= 21L && frame.auxiliary <= 24L && frame.result_ty >= 0L {
            let tag = if frame.auxiliary == 21L || frame.auxiliary == 23L { 0L } else { 1L }
            sum_case_payload_type(compiler, frame.result_ty, tag, child_index)
        }
        else if is_builtin_fill_call(source, tokens, files, compiler, file_index, tables.nodes[parent].token, frame.scope) {
            if type_kind(compiler, frame.expected) == TYPE_KIND_ARRAY { collection_element_type(compiler, frame.expected) } else { -1L }
        }
        else if token_is_word_at(source, tokens, files, file_index, tables.nodes[parent].token, "print") { -1L }
        else if numeric_builtin_kind(source, tokens, files, compiler, file_index, tables.nodes[parent].token, frame.scope) != NUMERIC_BUILTIN_NONE {
            if frame.expected == TY_INT || frame.expected == TY_LONG { frame.expected } else { -1L }
        }
        else {
            let function = find_function_by_name(compiler, compiler.token_name_ids[tables.nodes[parent].token])
            if function >= 0L && child_index < compiler.functions[function].param_count {
                let parameter = compiler.parameters[compiler.functions[function].param_start + child_index]
                if (parameter_mode(parameter) & FLAG_MODE_GROW) != 0L || parameter_uses_text_read_view(compiler, parameter) { -1L } else { parameter.ty }
            } else { -1L }
        }
    } else if kind == NodeKind.OptionalCall {
        if child == frame.child0 { -1L }
        else {
            let function = find_function_by_name(compiler, compiler.token_name_ids[tables.nodes[parent].token])
            let parameter_index = child_index + 1L
            if function >= 0L && parameter_index < compiler.functions[function].param_count {
                let parameter = compiler.parameters[compiler.functions[function].param_start + parameter_index]
                if parameter_uses_text_read_view(compiler, parameter) { -1L } else { parameter.ty }
            } else { -1L }
        }
    } else if kind == NodeKind.QualifiedCase && frame.child2 >= 0L {
        enum_case_payload_type(compiler, frame.child2, child_index)
    } else if kind == NodeKind.MethodCall && frame.child0 >= 0L && child != frame.child0 &&
        struct_method_target(source, files, tokens, compiler, compiler.facts[frame.child0].ty, tables.nodes[parent].token, file_index) >= 0L {
        // the receiver is the function's first parameter, so argument k is parameter k + 1
        let method_function = struct_method_target(source, files, tokens, compiler, compiler.facts[frame.child0].ty, tables.nodes[parent].token, file_index)
        let parameter_index = child_index + 1L
        if parameter_index < compiler.functions[method_function].param_count {
            let parameter = compiler.parameters[compiler.functions[method_function].param_start + parameter_index]
            if (parameter_mode(parameter) & FLAG_MODE_GROW) != 0L || parameter_uses_text_read_view(compiler, parameter) { -1L } else { parameter.ty }
        } else { -1L }
    } else if kind == NodeKind.MethodCall && frame.child0 >= 0L &&
        c_runtime_method_kind(source, tokens, files, compiler, file_index, tables.nodes[parent].token, compiler.facts[frame.child0].ty) != C_METHOD_NONE {
        c_runtime_child_expected(source, tokens, files, compiler, file_index, tables.nodes[parent].token,
            compiler.facts[frame.child0].ty, child_index)
    } else if kind == NodeKind.MethodCall && is_core_sys_receiver(source, tokens, files, tables, compiler, parent, file_index) {
        core_sys_argument_type(core_sys_operation(source, tokens, files, file_index, tables.nodes[parent].token), child_index)
    } else if kind == NodeKind.MethodCall && frame.child0 >= 0L &&
        (type_kind(compiler, compiler.facts[frame.child0].ty) == TYPE_KIND_ARRAY || collection_kind_is_list(type_kind(compiler, compiler.facts[frame.child0].ty))) {
        let collection_receiver_kind = type_kind(compiler, compiler.facts[frame.child0].ty)
        let method = collection_method_kind(source, tokens, files, file_index, tables.nodes[parent].token,
            collection_receiver_kind)
        if method == COLLECTION_METHOD_PUSH && child_index == 0L { collection_element_type(compiler, compiler.facts[frame.child0].ty) }
        else if method == COLLECTION_METHOD_INSERT && child_index == 0L { TY_LONG }
        else if method == COLLECTION_METHOD_INSERT && child_index == 1L { collection_element_type(compiler, compiler.facts[frame.child0].ty) }
        else if method == COLLECTION_METHOD_REMOVE && child_index == 0L { TY_LONG }
        else { -1L }
    } else if kind == NodeKind.MethodCall && frame.child0 >= 0L &&
        (type_kind(compiler, compiler.facts[frame.child0].ty) == TYPE_KIND_ASCII ||
         type_kind(compiler, compiler.facts[frame.child0].ty) == TYPE_KIND_TEXT ||
         type_kind(compiler, compiler.facts[frame.child0].ty) == TYPE_KIND_BYTES) {
        let receiver_type = compiler.facts[frame.child0].ty
        let receiver_kind = type_kind(compiler, receiver_type)
        let method = text_method_kind(source, tokens, files, file_index, tables.nodes[parent].token, receiver_kind)
        // push takes a byte or any int (stage 0 truncates an int to its low 8 bits); only a literal is typed as a byte
        if method == TEXT_METHOD_PUSH && child_index == 0L { if tables.nodes[child].kind == NodeKind.Integer { TY_BYTE } else { -1L } }
        else if method == TEXT_METHOD_SLICE { TY_LONG }
        else if (method == TEXT_METHOD_CONTAINS || method == TEXT_METHOD_STARTS_WITH) && child_index == 0L { compiler.facts[frame.child0].ty }
        else { -1L }
    } else if kind == NodeKind.Fit && child == frame.child0 {
        -1L
    } else if kind == NodeKind.Cast && child == frame.child0 {
        -1L
    } else if kind == NodeKind.Unary {
        if tables.nodes[parent].flags == 1L { TY_BOOL }
        else if tables.nodes[parent].flags == 2L { natural_node_type(source, tokens, files, tables, compiler, child, frame.scope, file_index) }
        else { frame.expected }
    } else if kind == NodeKind.Binary {
        let op = tables.nodes[parent].flags
        if op == 14L || op == 15L { TY_BOOL }
        else if op == 21L {
            if child == frame.child0 {
                let known = natural_node_type(source, tokens, files, tables, compiler, frame.child0, frame.scope, file_index)
                if known >= 0L { -1L }
                else {
                    let value_ty = if frame.expected >= 0L { frame.expected }
                        else { natural_node_type(source, tokens, files, tables, compiler, frame.child1, frame.scope, file_index) }
                    if value_ty >= 0L { find_sum_instance(compiler, TYPE_KIND_OPTION, value_ty, -1L) }
                    else { -1L }
                }
            } else {
                let option_ty = compiler.facts[frame.child0].ty
                sum_case_payload_type(compiler, option_ty, 0L, 0L)
            }
        }
        else if op >= 8L && op <= 13L {
            let other = if child == frame.child0 { frame.child1 } else { frame.child0 }
            let known = natural_node_type(source, tokens, files, tables, compiler, other, frame.scope, file_index)
            if is_unsuffixed_integer(tables, other) && !is_unsuffixed_integer(tables, child) { -1L }
            else if type_kind(compiler, known) == TYPE_KIND_ASCII || type_kind(compiler, known) == TYPE_KIND_TEXT || type_kind(compiler, known) == TYPE_KIND_BYTES { -1L }
            else if known >= 0L { known }
            else if is_unsuffixed_integer(tables, child) { -1L }
            else { -1L }
        } else if op >= 16L && op <= 20L {
            let other = if child == frame.child0 { frame.child1 } else { frame.child0 }
            let known = natural_node_type(source, tokens, files, tables, compiler, other, frame.scope, file_index)
            let both_unsuffixed = is_unsuffixed_integer(tables, frame.child0) && is_unsuffixed_integer(tables, frame.child1)
            if both_unsuffixed && frame.expected >= TY_INT && frame.expected <= TY_LONG { frame.expected }
            else if is_numeric_type(known) && is_unsuffixed_integer(tables, child) && !is_unsuffixed_integer(tables, other) { known }
            else if frame.expected >= TY_INT && frame.expected <= TY_LONG { frame.expected }
            else { -1L }
        } else if frame.expected >= TY_INT && frame.expected <= TY_LONG { frame.expected }
        else {
            let other = if child == frame.child0 { frame.child1 } else { frame.child0 }
            let known = natural_node_type(source, tokens, files, tables, compiler, other, frame.scope, file_index)
            if is_numeric_type(known) && is_unsuffixed_integer(tables, child) { known } else { -1L }
        }
    } else if kind == NodeKind.If {
        if child == frame.child0 { TY_BOOL } else { frame.expected }
    } else if kind == NodeKind.For {
        if child_index < 2L { frame.result_ty } else { TY_UNIT }
    } else {
        -1L
    }
}

fn node_has_parent_kind(tables: ParseTables, compiler: CompilerTables, node: long, parent_kind: NodeKind) -> bool {
    for parent in 0L..tables.nodes.count() {
        if tables.nodes[parent].kind == parent_kind && compiler.child_first[parent] == node { return true }
    }
    false
}

fn find_sum_instance(compiler: CompilerTables, kind: long, arg0: long, arg1: long) -> long {
    for type_id in 0L..type_count(compiler) {
        if generic_instance_matches(compiler, type_id, kind, arg0, arg1) { return type_id }
    }
    -1L
}

fn node_last_child(tables: ParseTables, compiler: CompilerTables, parent: long) -> long {
    var child = compiler.child_first[parent]
    var last = -1L
    for step in 0L..tables.nodes[parent].subtree {
        if child < 0L { break }
        last = child
        child = compiler.child_next[child]
    }
    last
}

fn node_children_fall_through(tables: ParseTables, compiler: CompilerTables, parent: long) -> bool {
    var child = compiler.child_first[parent]
    for step in 0L..tables.nodes[parent].subtree {
        if child < 0L { break }
        if (compiler.facts[child].flags & FACT_FALLS_THROUGH) == 0L { return false }
        child = compiler.child_next[child]
    }
    true
}

