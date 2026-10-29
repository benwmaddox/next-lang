fn register_package_declarations(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    config: MemoryConfig,
    compiler: write CompilerTables,
) {
    let _ = config
    for file_index in 0L..files.count() {
        let root = files[file_index].tree_root
        var child = compiler.child_first[root]
        for step in 0L..tables.nodes[root].subtree {
            if child < 0L { break }
            if tables.nodes[child].kind == NodeKind.Function {
                let node = tables.nodes[child]
                let name_id = compiler.token_name_ids[node.token]
                if token_is_word_at(source, tokens, files, file_index, node.token, "print") || token_is_word_at(source, tokens, files, file_index, node.token, "min") || token_is_word_at(source, tokens, files, file_index, node.token, "max") || token_is_word_at(source, tokens, files, file_index, node.token, "sort") || token_is_word_at(source, tokens, files, file_index, node.token, "sort_by") || token_is_word_at(source, tokens, files, file_index, node.token, "binary_search") || token_is_word_at(source, tokens, files, file_index, node.token, "stack_peak") {
                    fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, node.start, "'", node.token, "' is a built-in function name and cannot be redeclared")
                }
                for prior in 0L..compiler.functions.count() {
                    if compiler.functions[prior].name_id == name_id {
                        fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, node.start, "function '", node.token, "' is declared more than once")
                    }
                }
                var result_ty = TY_UNIT
                var body = -1L
                let param_start = compiler.parameters.count()
                var param_count = 0L
                var member = compiler.child_first[child]
                for inner_step in 0L..node.subtree {
                    if member < 0L { break }
                    if tables.nodes[member].kind == NodeKind.Parameter {
                        let param_node = tables.nodes[member]
                        let type_node = compiler.child_first[member]
                        let ty = parse_scalar_type(env, source, tokens, files, tables, compiler, file_index, type_node)
                        if (param_node.flags & FLAG_MODE_GROW) != 0L &&
                            type_kind(compiler, ty) != TYPE_KIND_ASCII &&
                            type_kind(compiler, ty) != TYPE_KIND_TEXT &&
                            type_kind(compiler, ty) != TYPE_KIND_BYTES {
                            fail_at_message(env, files, compiler, file_index, param_node.start,
                                "grow parameters are for Ascii, Text, and Bytes builders; use read or write for other types")
                        }
                        compiler.parameters.push(ParameterRecord {
                            node: member,
                            file: file_index,
                            name_id: compiler.token_name_ids[param_node.token],
                            name_token: encode_parameter_name_token(param_node.token, param_node.flags),
                            ty,
                        }).unwrap()
                        param_count += 1L
                    } else if tables.nodes[member].kind == NodeKind.ResultType {
                        result_ty = parse_scalar_type(env, source, tokens, files, tables, compiler, file_index, member)
                    } else if tables.nodes[member].kind == NodeKind.Block {
                        body = member
                    } else {
                        ()
                    }
                    member = compiler.child_next[member]
                }
                compiler.functions.push(FunctionRecord { node: child, file: file_index, name_id, name_token: node.token, result_ty, param_start, param_count, body }).unwrap()
                compiler.edge_first.push(-1L).unwrap()
                compiler.cycle_seen.push(0L).unwrap()
            }
            child = compiler.child_next[child]
        }
        child = compiler.child_first[root]
        for step in 0L..tables.nodes[root].subtree {
            if child < 0L { break }
            if tables.nodes[child].kind == NodeKind.Test {
                let node = tables.nodes[child]
                let body = node_children_of_kind(tables, compiler, child, NodeKind.Block)
                for prior in 0L..compiler.tests.count() {
                    let prior_test = compiler.tests[prior]
                    let prior_name = decode_string_token(source, tokens, files[prior_test.file].base, prior_test.name_token, false)
                    let name = decode_string_token(source, tokens, files[file_index].base, node.token, false)
                    if decoded_string_equal(prior_name, name) {
                        let position = position_for_offset(file_index, files[file_index].base + node.start, compiler)
                        let prior_position = position_for_offset(prior_test.file, files[prior_test.file].base + tables.nodes[prior_test.node].start, compiler)
                        match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
                        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
                        match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
                        match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                        match env.err.write(b": error: test '") { ok(_) => (), err(_) => env.exit(3) }
                        match env.err.write(name) { ok(_) => (), err(_) => env.exit(3) }
                        match env.err.write(b"' is declared more than once (first declared on line ") { ok(_) => (), err(_) => env.exit(3) }
                        match env.err.write(str(prior_position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                        match env.err.write(b"); choose a unique name\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
                    }
                }
                compiler.tests.push(TestRecord { node: child, file: file_index, name_token: node.token, body }).unwrap()
            }
            child = compiler.child_next[child]
        }
    }
}

fn find_function_by_name(compiler: CompilerTables, name_id: long) -> long {
    for function in 0L..compiler.functions.count() {
        if compiler.functions[function].name_id == name_id { return function }
    }
    -1L
}

fn is_builtin_fill_call(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    token: long,
    scope: long,
) -> bool {
    if !token_is_word_at(source, tokens, files, file_index, token, "fill") { return false }
    let name_id = compiler.token_name_ids[token]
    find_function_by_name(compiler, name_id) < 0L && find_binding_in_scope(compiler, scope, name_id) < 0L
}

const NUMERIC_BUILTIN_NONE: long = 0L
const NUMERIC_BUILTIN_MIN: long = 1L
const NUMERIC_BUILTIN_MAX: long = 2L
const NUMERIC_BUILTIN_ABS: long = 3L
const NUMERIC_BUILTIN_CLAMP: long = 4L
// Added to the kind of a clamp that is computed as an int and narrowed to a byte.
const NUMERIC_BUILTIN_NARROW_TO_BYTE: long = 100L

// min, max, abs and clamp are compiler built-ins that lower to inline LLVM intrinsics.
// A user function or local with the same name wins. scope < 0 skips the local lookup (the
// support scan runs before bindings exist).
fn numeric_builtin_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    token: long,
    scope: long,
) -> long {
    let kind = if token_is_word_at(source, tokens, files, file_index, token, "min") { NUMERIC_BUILTIN_MIN }
        else if token_is_word_at(source, tokens, files, file_index, token, "max") { NUMERIC_BUILTIN_MAX }
        else if token_is_word_at(source, tokens, files, file_index, token, "abs") { NUMERIC_BUILTIN_ABS }
        else if token_is_word_at(source, tokens, files, file_index, token, "clamp") { NUMERIC_BUILTIN_CLAMP }
        else { NUMERIC_BUILTIN_NONE }
    if kind == NUMERIC_BUILTIN_NONE { return NUMERIC_BUILTIN_NONE }
    let name_id = compiler.token_name_ids[token]
    if find_function_by_name(compiler, name_id) >= 0L { return NUMERIC_BUILTIN_NONE }
    if scope >= 0L && find_binding_in_scope(compiler, scope, name_id) >= 0L { return NUMERIC_BUILTIN_NONE }
    kind
}

fn check_entry_signature(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    require_main: bool,
) -> long {
    var entry = -1L
    for function in 0L..compiler.functions.count() {
        if token_is_word_at(source, tokens, files, compiler.functions[function].file, compiler.functions[function].name_token, "main") {
            entry = function
            break
        }
    }
    if entry < 0L {
        if require_main {
            match env.err.write(files[0].name) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b":1:1: error: package must define 'fn main()'; add an entry point that takes no arguments and returns ()\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
        }
        return -1L
    }
    let signature = compiler.functions[entry]
    if signature.param_count == 0L && type_kind(compiler, signature.result_ty) == TYPE_KIND_RESULT {
        report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit {
            found: true,
            file: signature.file,
            node: signature.node,
            offset: tables.nodes[signature.node].start,
            category: UNSUPPORTED_RESULT_MAIN,
            token: signature.name_token,
        })
    }
    let accepts_environment = compiler.c_runtime && signature.param_count == 1L &&
        compiler.parameters[signature.param_start].ty == TY_ENV
    if (signature.param_count != 0L && !accepts_environment) || signature.result_ty != TY_UNIT {
        fail_compiler_diagnostic(env, files[signature.file].name, files, signature.file, tables.nodes[signature.node].start, compiler, "'main' must take no arguments or one Env parameter, and return () or Result<(), E> with a printable error; use 'fn main()' or 'fn main(env: Env)'")
    }
    entry
}

fn child_at(
    tables: ParseTables,
    compiler: CompilerTables,
    parent: long,
    wanted: long,
) -> long {
    var child = compiler.child_first[parent]
    var index = 0L
    for step in 0L..tables.nodes[parent].subtree {
        if child < 0L { break }
        if index == wanted { return child }
        index += 1L
        child = compiler.child_next[child]
    }
    -1L
}

fn count_children(tables: ParseTables, compiler: CompilerTables, parent: long) -> long {
    var item_count = 0L
    var child = compiler.child_first[parent]
    for step in 0L..tables.nodes[parent].subtree {
        if child < 0L { break }
        item_count += 1L
        child = compiler.child_next[child]
    }
    item_count
}

fn push_check_frame(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: write CompilerTables,
    frame: CheckFrame,
) {
    if compiler.work.count() >= CHECK_FRAME_CAPACITY {
        let file_index = if frame.node >= 0L { 0L } else { 0L }
        fail_parse_limit(env, files[file_index].name, "self-hosted checker nesting limit exceeded")
    }
    compiler.work.push(frame).unwrap()
}

fn create_scope(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: write CompilerTables,
    parent: long,
    function_id: long,
    block: long,
    file_index: long,
) -> long {
    if compiler.scopes.count() >= SCOPE_TABLE_CAPACITY {
        fail_parse_limit(env, files[file_index].name, "self-hosted scope table limit exceeded")
    }
    let id = compiler.scopes.count()
    compiler.scopes.push(ScopeRecord { parent, function_id, block }).unwrap()
    id
}

fn find_binding_in_scope(
    compiler: CompilerTables,
    scope: long,
    name_id: long,
) -> long {
    var root_scope = scope
    var found_root = false
    for scope_step in 0L..compiler.scopes.count() {
        if root_scope < 0L || root_scope >= compiler.scopes.count() { return -1L }
        let parent = compiler.scopes[root_scope].parent
        if parent < 0L { found_root = true; break }
        root_scope = parent
    }
    if !found_root { return -1L }
    var current_scope = scope
    for scope_step in 0L..compiler.scopes.count() + 1L {
        if current_scope < root_scope || current_scope >= compiler.scopes.count() { break }
        var binding = compiler.bindings.count()
        for binding_step in 0L..compiler.bindings.count() {
            if binding <= 0L { break }
            binding -= 1L
            if compiler.bindings[binding].scope < root_scope { break }
            if compiler.bindings[binding].scope == current_scope && compiler.bindings[binding].name_id == name_id {
                return binding
            }
        }
        current_scope = compiler.scopes[current_scope].parent
    }
    -1L
}

fn add_local_binding(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    node: long,
    name_token: long,
    scope: long,
    ty: long,
    mutable: bool,
    loop_counter: bool,
    parameter: bool,
) -> long {
    let name_id = compiler.token_name_ids[name_token]
    let previous_binding = find_binding_in_scope(compiler, scope, name_id)
    if previous_binding >= 0L {
        let previous = compiler.bindings[previous_binding]
        if previous.scope == scope {
            let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].start, compiler)
            match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b": error: '") { ok(_) => (), err(_) => env.exit(3) }
            match write_token_raw(env.err, source, tokens, files[file_index].base, name_token) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b"' is already declared in this scope (first declared on line ") { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(str(position_for_offset(previous.file, files[previous.file].base + tables.nodes[previous.node].start, compiler).line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b"); choose another name\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
        }
        let previous_position = position_for_offset(previous.file, files[previous.file].base + tables.nodes[previous.node].start, compiler)
        fail_name_shadow_error(env, source, files, tokens, compiler, file_index, tables.nodes[node].start, name_token, "visible declaration", previous_position.line)
    }
    if name_id >= 0L && name_id < compiler.reserved_names.count() && compiler.reserved_names[name_id] {
        fail_name_shadow_error(env, source, files, tokens, compiler, file_index, tables.nodes[node].start, name_token, "bare enum case", -1L)
    }
    if compiler.bindings.count() >= BINDING_TABLE_CAPACITY {
        fail_parse_limit(env, files[file_index].name, "self-hosted binding table limit exceeded")
    }
    let id = compiler.bindings.count()
    compiler.bindings.push(BindingRecord { name_id, name_token, file: file_index, ty, mutable, loop_counter, parameter, scope, node, collection_count: -1L }).unwrap()
    id
}

fn collection_push_is_proven(compiler: CompilerTables, receiver: long, loop_depth: long) -> bool {
    if receiver < 0L { return false }
    let binding = compiler.facts[receiver].binding
    if binding < 0L || binding >= compiler.bindings.count() || compiler.bindings[binding].ty != compiler.facts[receiver].ty { return false }
    loop_push_is_proven(compiler, binding, loop_depth)
}

fn set_binding_collection_count(compiler: write CompilerTables, binding: long, value: long) {
    if binding < 0L || binding >= compiler.bindings.count() { return }
    let previous = compiler.bindings[binding].collection_count
    if previous == value { return }
    if compiler.collection_count_joins.count() > 0L || compiler.loop_count_snapshots.count() > 0L {
        compiler.collection_count_changes.push(CollectionCountChange { binding, previous, value }).unwrap()
    }
    compiler.bindings[binding].collection_count = value
}

fn rollback_collection_count_changes(compiler: write CompilerTables, length: long) {
    for pop_step in 0L..NODE_STORAGE_CAPACITY {
        if compiler.collection_count_changes.count() <= length { break }
        let change = match compiler.collection_count_changes.pop() {
            some(value) => value,
            none() => break,
        }
        if change.binding >= 0L && change.binding < compiler.bindings.count() {
            compiler.bindings[change.binding].collection_count = change.previous
        }
    }
}

fn truncate_collection_count_changes(compiler: write CompilerTables, length: long) {
    for pop_step in 0L..NODE_STORAGE_CAPACITY {
        if compiler.collection_count_changes.count() <= length { break }
        match compiler.collection_count_changes.pop() { some(_) => (), none() => break }
    }
}

fn begin_collection_count_join(compiler: write CompilerTables, node: long, kind: long) -> long {
    let index = compiler.collection_count_joins.count()
    compiler.collection_count_joins.push(CollectionCountJoin {
        node,
        kind,
        outer_log_base: compiler.collection_count_changes.count(),
        binding_limit: -1L,
        log_base: -1L,
        values_base: compiler.collection_count_branch_values.count(),
        started: false,
        branch0_falls: false,
        branch1_falls: false,
        fallthrough_count: 0L,
    }).unwrap()
    index
}

fn start_collection_count_join(compiler: write CompilerTables, join_index: long) {
    if join_index < 0L || join_index >= compiler.collection_count_joins.count() { return }
    var join = compiler.collection_count_joins[join_index]
    join.binding_limit = compiler.bindings.count()
    join.log_base = compiler.collection_count_changes.count()
    join.values_base = compiler.collection_count_branch_values.count()
    join.started = true
    compiler.collection_count_joins[join_index] = join
}

fn record_collection_count_branch(
    compiler: write CompilerTables,
    join_index: long,
    branch: long,
    falls_through: bool,
) {
    if join_index < 0L || join_index >= compiler.collection_count_joins.count() { return }
    let join = compiler.collection_count_joins[join_index]
    if !join.started { return }
    if falls_through {
        if join.kind == 1L {
            compiler.collection_count_joins[join_index].fallthrough_count += 1L
        }
        for change_index: long in join.log_base..compiler.collection_count_changes.count() {
            let change = compiler.collection_count_changes[change_index]
            if change.binding < 0L || change.binding >= join.binding_limit { continue }
            var found = -1L
            for value_index: long in join.values_base..compiler.collection_count_branch_values.count() {
                let existing = compiler.collection_count_branch_values[value_index]
                if existing.join_index == join_index && existing.branch == branch && existing.binding == change.binding {
                    found = value_index
                    break
                }
            }
            if found >= 0L {
                compiler.collection_count_branch_values[found].value = change.value
            } else {
                compiler.collection_count_branch_values.push(CollectionCountBranchValue {
                    join_index,
                    branch,
                    binding: change.binding,
                    value: change.value,
                }).unwrap()
            }
        }
    }
    rollback_collection_count_changes(compiler, join.log_base)
}

fn collection_count_branch_value(
    compiler: CompilerTables,
    join_index: long,
    branch: long,
    binding: long,
) -> long {
    let join = compiler.collection_count_joins[join_index]
    for value_index: long in join.values_base..compiler.collection_count_branch_values.count() {
        let value = compiler.collection_count_branch_values[value_index]
        if value.join_index == join_index && value.branch == branch && value.binding == binding { return value.value }
    }
    -2L
}

fn finish_if_collection_count_join(compiler: write CompilerTables, join_index: long) {
    if join_index < 0L || join_index >= compiler.collection_count_joins.count() { return }
    let join = compiler.collection_count_joins[join_index]
    if join.started && (join.branch0_falls || join.branch1_falls) {
        for value_index: long in join.values_base..compiler.collection_count_branch_values.count() {
            let candidate = compiler.collection_count_branch_values[value_index]
            if candidate.join_index != join_index { continue }
            var already_joined = false
            for previous_index: long in join.values_base..value_index {
                let previous = compiler.collection_count_branch_values[previous_index]
                if previous.join_index == join_index && previous.binding == candidate.binding {
                    already_joined = true
                    break
                }
            }
            if already_joined { continue }
            let baseline = if candidate.binding < compiler.bindings.count() {
                compiler.bindings[candidate.binding].collection_count
            } else { -1L }
            let left = if join.branch0_falls {
                let found = collection_count_branch_value(compiler, join_index, 0L, candidate.binding)
                if found == -2L { baseline } else { found }
            } else { -2L }
            let right = if join.branch1_falls {
                let found = collection_count_branch_value(compiler, join_index, 1L, candidate.binding)
                if found == -2L { baseline } else { found }
            } else { -2L }
            let merged = if !join.branch0_falls { right }
                else if !join.branch1_falls { left }
                else if left < 0L || right < 0L || left != right { -1L }
                else { left }
            set_binding_collection_count(compiler, candidate.binding, merged)
        }
    }
    for pop_step in 0L..NODE_STORAGE_CAPACITY {
        if compiler.collection_count_branch_values.count() <= join.values_base { break }
        match compiler.collection_count_branch_values.pop() { some(_) => (), none() => break }
    }
    match compiler.collection_count_joins.pop() { some(_) => (), none() => () }
    if compiler.collection_count_joins.count() == 0L && compiler.loop_count_snapshots.count() == 0L {
        truncate_collection_count_changes(compiler, join.outer_log_base)
    }
}

fn finish_match_collection_count_join(compiler: write CompilerTables, join_index: long) {
    if join_index < 0L || join_index >= compiler.collection_count_joins.count() { return }
    let join = compiler.collection_count_joins[join_index]
    if join.started && join.fallthrough_count > 0L {
        for value_index: long in join.values_base..compiler.collection_count_branch_values.count() {
            let candidate = compiler.collection_count_branch_values[value_index]
            if candidate.join_index != join_index || candidate.binding < 0L { continue }
            var already_joined = false
            for previous_index: long in join.values_base..value_index {
                let previous = compiler.collection_count_branch_values[previous_index]
                if previous.join_index == join_index && previous.binding == candidate.binding {
                    already_joined = true
                    break
                }
            }
            if already_joined { continue }
            let baseline = if candidate.binding < compiler.bindings.count() {
                compiler.bindings[candidate.binding].collection_count
            } else { -1L }
            var merged = -2L
            var branch_value_count = 0L
            if baseline >= 0L {
                for branch_value_index: long in join.values_base..compiler.collection_count_branch_values.count() {
                    let branch_value = compiler.collection_count_branch_values[branch_value_index]
                    if branch_value.join_index != join_index || branch_value.binding != candidate.binding { continue }
                    branch_value_count += 1L
                    if branch_value.value < 0L { merged = -1L; break }
                    if merged == -2L { merged = branch_value.value }
                    else if merged != branch_value.value { merged = -1L; break }
                    else { () }
                }
            } else { merged = -1L }
            if merged >= 0L && branch_value_count < join.fallthrough_count {
                if baseline < 0L || merged != baseline { merged = -1L }
            }
            if merged == -2L { merged = baseline }
            set_binding_collection_count(compiler, candidate.binding, merged)
        }
    }
    for pop_step in 0L..NODE_STORAGE_CAPACITY {
        if compiler.collection_count_branch_values.count() <= join.values_base { break }
        match compiler.collection_count_branch_values.pop() { some(_) => (), none() => break }
    }
    match compiler.collection_count_joins.pop() { some(_) => (), none() => () }
    if compiler.collection_count_joins.count() == 0L && compiler.loop_count_snapshots.count() == 0L {
        truncate_collection_count_changes(compiler, join.outer_log_base)
    }
}

fn begin_loop_count_snapshot(compiler: write CompilerTables, loop_node: long) {
    compiler.loop_count_snapshots.push(LoopCountSnapshot {
        loop_node,
        binding_limit: compiler.bindings.count(),
        log_base: compiler.collection_count_changes.count(),
    }).unwrap()
}

fn finish_loop_count_snapshot(compiler: write CompilerTables, loop_node: long) {
    var snapshot_index = -1L
    for index in 0L..compiler.loop_count_snapshots.count() {
        if compiler.loop_count_snapshots[index].loop_node == loop_node { snapshot_index = index }
    }
    if snapshot_index < 0L { return }
    let snapshot = compiler.loop_count_snapshots[snapshot_index]
    let values_base = compiler.collection_count_branch_values.count()
    for change_index: long in snapshot.log_base..compiler.collection_count_changes.count() {
        let change = compiler.collection_count_changes[change_index]
        if change.binding < 0L || change.binding >= snapshot.binding_limit { continue }
        var found = -1L
        for value_index in values_base..compiler.collection_count_branch_values.count() {
            if compiler.collection_count_branch_values[value_index].binding == change.binding { found = value_index; break }
        }
        if found >= 0L { compiler.collection_count_branch_values[found].value = change.value }
        else {
            compiler.collection_count_branch_values.push(CollectionCountBranchValue {
                join_index: -1L,
                branch: loop_node,
                binding: change.binding,
                value: change.value,
            }).unwrap()
        }
    }
    rollback_collection_count_changes(compiler, snapshot.log_base)
    for value_index in values_base..compiler.collection_count_branch_values.count() {
        let after = compiler.collection_count_branch_values[value_index]
        let before = compiler.bindings[after.binding].collection_count
        var proof_index = -1L
        for candidate in 0L..compiler.loop_push_proofs.count() {
            if compiler.loop_push_proofs[candidate].loop_node == loop_node && compiler.loop_push_proofs[candidate].binding == after.binding {
                proof_index = candidate
                break
            }
        }
        var merged = -1L
        if proof_index >= 0L {
            if after.value >= 0L { merged = compiler.loop_push_proofs[proof_index].final_count }
        } else if before >= 0L && after.value >= 0L && before == after.value {
            merged = before
        } else { () }
        set_binding_collection_count(compiler, after.binding, merged)
    }
    for pop_step in 0L..NODE_STORAGE_CAPACITY {
        if compiler.collection_count_branch_values.count() <= values_base { break }
        match compiler.collection_count_branch_values.pop() { some(_) => (), none() => break }
    }
    var found_snapshot = false
    for reverse_index in 0L..compiler.loop_count_snapshots.count() {
        let index = compiler.loop_count_snapshots.count() - reverse_index - 1L
        if compiler.loop_count_snapshots[index].loop_node == loop_node {
            for shift in index..compiler.loop_count_snapshots.count() - 1L {
                compiler.loop_count_snapshots[shift] = compiler.loop_count_snapshots[shift + 1L]
            }
            match compiler.loop_count_snapshots.pop() { some(_) => (), none() => () }
            found_snapshot = true
            break
        }
    }
    if found_snapshot && compiler.collection_count_joins.count() == 0L && compiler.loop_count_snapshots.count() == 0L {
        truncate_collection_count_changes(compiler, snapshot.log_base)
    }
}

fn type_name_or_fallback(ty: long) -> Ascii max 16 {
    scalar_type_name(ty)
}

fn fail_type_mismatch(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    expected: long,
    actual: long,
) -> never {
    let file = files[file_index]
    let position = position_for_offset(file_index, file.base + offset, compiler)
    match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: expected ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(type_name_or_fallback(expected).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b", found ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(type_name_or_fallback(actual).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"; cast explicitly with (") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(type_name_or_fallback(expected).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b")value") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn require_type(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    node: long,
    expected: long,
    actual: long,
    tables: ParseTables,
) {
    // A byte widens to an int wherever an int is expected, as in stage 0 (both are 32-bit values in IR).
    if actual == TY_NEVER || actual == expected || text_width_fits(compiler, actual, expected) { return }
    if expected == TY_INT && actual == TY_BYTE { return }
    let offset = tables.nodes[node].start
    fail_type_mismatch(env, files, compiler, file_index, offset, expected, actual)
}

fn parameter_uses_text_read_view(compiler: CompilerTables, parameter: ParameterRecord) -> bool {
    type_kind(compiler, parameter.ty) == TYPE_KIND_TEXT &&
        (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) == 0L
}

fn require_text_read_argument(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    node: long,
    expected: long,
    actual: long,
    tables: ParseTables,
) {
    if actual == TY_NEVER || text_read_argument_fits(compiler, expected, actual) { return }
    fail_type_mismatch(env, files, compiler, file_index, tables.nodes[node].start, expected, actual)
}

fn is_unsuffixed_integer(tables: ParseTables, node: long) -> bool {
    node >= 0L && tables.nodes[node].kind == NodeKind.Integer && (tables.nodes[node].flags & FLAG_LONG_SUFFIX) == 0L
}

recursive fn natural_node_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    scope: long,
    file_index: long,
) -> long {
    if node < 0L { return -1L }
    let value = tables.nodes[node]
    match value.kind {
        NodeKind.Integer => if (value.flags & FLAG_LONG_SUFFIX) != 0L { TY_LONG } else { TY_INT },
        NodeKind.Bool => TY_BOOL,
        NodeKind.Unit => TY_UNIT,
        NodeKind.Name => {
            let name_id = compiler.token_name_ids[value.token]
            let binding = find_binding_in_scope(compiler, scope, name_id)
            if binding >= 0L { compiler.bindings[binding].ty }
            else {
                let constant = find_constant_declaration(tables, compiler, name_id)
                if constant >= 0L && (compiler.facts[constant].flags & FACT_CONSTANT_EVALUATED) != 0L { compiler.facts[constant].ty }
                else {
                    let candidate = user_case_matches(compiler, name_id)
                    if candidate >= 0L { enum_case_owner_type_id(compiler, candidate) } else { -1L }
                }
            }
        },
        NodeKind.Call => {
            let id = compiler.token_name_ids[value.token]
            let function = find_function_by_name(compiler, id)
            if function >= 0L { compiler.functions[function].result_ty }
            else if token_is_word_at(source, tokens, files, file_index, value.token, "print") { TY_UNIT }
            else if find_binding_in_scope(compiler, scope, id) >= 0L { -1L }
            else {
                let candidate = user_case_matches(compiler, id)
                if candidate >= 0L { enum_case_owner_type_id(compiler, candidate) } else { -1L }
            }
        },
        NodeKind.QualifiedCase => {
            enum_type_matches(compiler, compiler.token_name_ids[value.token])
        },
        NodeKind.Field => {
            let receiver = compiler.child_first[node]
            if receiver >= 0L && tables.nodes[receiver].kind == NodeKind.Name && find_binding_in_scope(compiler, scope, compiler.token_name_ids[tables.nodes[receiver].token]) < 0L {
                let type_id = enum_type_matches(compiler, compiler.token_name_ids[tables.nodes[receiver].token])
                if type_id >= 0L {
                    let case_index = enum_case_matches(compiler, type_id, compiler.token_name_ids[value.token])
                    if case_index >= 0L { type_id } else { -1L }
                } else { -1L }
            } else { -1L }
        },
        NodeKind.Index => {
            let receiver = compiler.child_first[node]
            if receiver >= 0L {
                let receiver_ty = natural_node_type(source, tokens, files, tables, compiler, receiver, scope, file_index)
                collection_element_type(compiler, receiver_ty)
            } else { -1L }
        },
        NodeKind.StructInit => {
            let type_index = struct_type_matches(compiler, compiler.token_name_ids[value.token])
            if type_index >= 0L { struct_type_id(compiler, type_index) } else { -1L }
        },
        NodeKind.MethodCall => {
            if is_core_sys_receiver(source, tokens, files, tables, compiler, node, file_index) {
                core_sys_result_type(core_sys_operation(source, tokens, files, file_index, value.token))
            } else { -1L }
        },
        NodeKind.Cast => {
            let target = compiler.child_first[node]
            if target >= 0L && token_is_word_at(source, tokens, files, file_index, tables.nodes[target].token, "int") { TY_INT }
            else if target >= 0L && token_is_word_at(source, tokens, files, file_index, tables.nodes[target].token, "long") { TY_LONG }
            else if target >= 0L && token_is_word_at(source, tokens, files, file_index, tables.nodes[target].token, "byte") { TY_BYTE }
            else { -1L }
        },
        NodeKind.Fit => {
            let value_node = compiler.child_first[node]
            let target_node = if value_node >= 0L { compiler.child_next[value_node] } else { -1L }
            if target_node >= 0L &&
                (type_kind(compiler, compiler.facts[target_node].ty) == TYPE_KIND_ASCII || compiler.facts[target_node].ty == TY_BYTE) {
                find_sum_instance(compiler, TYPE_KIND_OPTION, compiler.facts[target_node].ty, -1L)
            } else { -1L }
        },
        NodeKind.ToLong => TY_LONG,
        NodeKind.Unary => -1L,
        NodeKind.Binary => if value.flags >= 8L && value.flags <= 15L { TY_BOOL } else { -1L },
        _ => -1L,
    }
}

fn natural_loop_bound_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    scope: long,
    file_index: long,
) -> long {
    if node < 0L || is_unsuffixed_integer(tables, node) { return -1L }
    natural_node_type(source, tokens, files, tables, compiler, node, scope, file_index)
}

fn fail_loop_type_conflict(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    first: long,
    second: long,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + offset, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: loop counter and range uses conflict between ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(scalar_type_name(first).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b" and ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(scalar_type_name(second).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"; cast a bound or use explicitly typed values of one type\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_loop_bound_type(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    ty: long,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + offset, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: a range bound must be int or long, found ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(type_name_or_fallback(ty).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn loop_body_call_parameter_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    call: long,
    counter_name_id: long,
    file_index: long,
) -> long {
    let target = find_function_by_name(compiler, compiler.token_name_ids[tables.nodes[call].token])
    if target < 0L { return -1L }
    let function = compiler.functions[target]
    var child = compiler.child_first[call]
    var argument_index = 0L
    for step in 0L..tables.nodes[call].subtree {
        if child < 0L { break }
        if tables.nodes[child].kind == NodeKind.Name && compiler.token_name_ids[tables.nodes[child].token] == counter_name_id && argument_index < function.param_count {
            let ty = compiler.parameters[function.param_start + argument_index].ty
            if is_numeric_type(ty) { return ty }
        }
        argument_index += 1L
        child = compiler.child_next[child]
    }
    -1L
}

fn fail_mixed_types(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    left: long,
    right: long,
) -> never {
    let file = files[file_index]
    let position = position_for_offset(file_index, file.base + offset, compiler)
    match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: cannot combine ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(scalar_type_name(left).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b" and ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(scalar_type_name(right).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"; cast the left value to ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(scalar_type_name(right).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b" or the right value to ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(scalar_type_name(left).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_name_error(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    token: long,
    scope: long,
    is_function: bool,
) -> never {
    let file = files[file_index]
    let position = position_for_offset(file_index, file.base + offset, compiler)
    match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    if is_function { match env.err.write(b": error: unknown function '") { ok(_) => (), err(_) => env.exit(3) } }
    else { match env.err.write(b": error: unknown name '") { ok(_) => (), err(_) => env.exit(3) } }
    match write_token_raw(env.err, source, tokens, file.base, token) { ok(_) => (), err(_) => env.exit(3) }
    let candidate = closest_name_candidate(source, tokens, files, compiler, token, file_index, scope, is_function)
    if candidate.token >= 0L {
        match env.err.write(b"'; did you mean '") { ok(_) => (), err(_) => env.exit(3) }
        match write_token_raw(env.err, source, tokens, files[candidate.file].base, candidate.token) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"'") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
    } else if is_function {
        match env.err.write(b"'; declare it with fn") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
    } else {
        match env.err.write(b"'; declare it with let or var") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
    }
}

fn fail_call_arity(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    file_index: long,
    call_offset: long,
    name_token: long,
    expected: long,
    actual: long,
) -> never {
    let file = files[file_index]
    let position = position_for_offset(file_index, file.base + call_offset, compiler)
    match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: function '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, file.base, name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"' takes ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(expected).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b" argument(s), but got ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(actual).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

