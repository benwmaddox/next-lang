// Pool owners. An id is a long at run time, but `Id<nodes>` names the pool `nodes` it belongs to, and the compiler
// refuses to use it with another pool. The owner of a pool is the node that declares it: a `let`/`var` of a local
// pool, a pool parameter, or a struct field (`struct World { nodes: pool<Node, 64> }`). `Id<name>` resolves `name`
// to a pool parameter or local of the function, else to the one struct field of that name in the package.
//
// The check is a pass after body checking. It never changes types: it follows which pool an id came from through
// names, fields, list elements, calls and `match` arms, and checks the places that expect an owned id: pool.get and
// pool.set, arguments, struct fields, annotated lets, assignments, list pushes and returns. At such a place the id's
// pool must be known and equal. A negative literal or constant (the "no id") fits anywhere. An id whose pool cannot
// be followed (for instance one that came out of arithmetic) is refused with a message saying so.
// `Id<Node>`, where Node is not a pool, stays an unowned plain id; it is refused once a package has several pools.

const OWNER_UNKNOWN: long = -1L
const OWNER_NIL: long = -2L
const OWNER_NONE: long = -3L
const OWNER_AMBIGUOUS: long = -4L
const OWNER_LIST_CAPACITY: long = 4096L

struct OwnerState {
    visible_names: list<long, 256>
    visible_keys: list<long, 256>
    binding_ids: list<long, OWNER_LIST_CAPACITY>
    binding_owners: list<long, OWNER_LIST_CAPACITY>
    function_id: long
    scrutinee: long
    pool_declarations: long
    pool_values: long
}

fn owner_binding_owner(st: OwnerState, binding: long) -> long {
    for index in 0L..st.binding_ids.count() {
        if st.binding_ids[index] == binding { return st.binding_owners[index] }
    }
    OWNER_UNKNOWN
}

fn owner_set_binding(env: Env, st: write OwnerState, binding: long, owner: long) {
    if binding < 0L || owner == OWNER_UNKNOWN || owner == OWNER_NONE || owner == OWNER_NIL { return }
    for index in 0L..st.binding_ids.count() {
        if st.binding_ids[index] == binding { st.binding_owners[index] = owner; return }
    }
    match st.binding_ids.push(binding) { ok(_) => (), err(_) => { env.exit(2) } }
    match st.binding_owners.push(owner) { ok(_) => (), err(_) => { env.exit(2) } }
}

// `Id` and the provisional window type name `Window` both name their owner (arena or pool) in `<...>`.
fn owner_is_id_word(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    token: long,
) -> bool {
    token_is_word_at(source, tokens, files, file_index, token, "Id") || token_is_word_at(source, tokens, files, file_index, token, "Window")
}

// The type argument naming the pool in `Id<pool>`, found directly or inside list<...>, Option<...> and so on.
recursive fn owner_id_argument(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    type_node: long,
    depth: long,
) -> long {
    if type_node < 0L || depth > 8L { return -1L }
    let file_index = node_file_index(tables.nodes, files, type_node)
    let first = compiler.child_first[type_node]
    if owner_is_id_word(source, tokens, files, file_index, tables.nodes[type_node].token) &&
        (tables.nodes[type_node].meta1 & 2097151L) == 1L {
        return first
    }
    var child = first
    for step in 0L..8L {
        if child < 0L { break }
        if tables.nodes[child].kind == NodeKind.TypeArgument {
            let found = owner_id_argument(source, files, tokens, tables, compiler, child, depth + 1L)
            if found >= 0L { return found }
        }
        child = compiler.child_next[child]
    }
    -1L
}

fn owner_type_is_direct_id(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    type_node: long,
) -> bool {
    if type_node < 0L { return false }
    let file_index = node_file_index(tables.nodes, files, type_node)
    owner_is_id_word(source, tokens, files, file_index, tables.nodes[type_node].token) && (tables.nodes[type_node].meta1 & 2097151L) == 1L
}

// The pool a name stands for: a pool parameter or local of function `function_id`, else the one pool field of that name.
fn owner_resolve_name(compiler: CompilerTables, st: OwnerState, name_id: long, function_id: long) -> long {
    if function_id >= 0L && function_id == st.function_id {
        var index = st.visible_names.count() - 1L
        for step in 0L..st.visible_names.count() {
            if st.visible_names[index] == name_id { return st.visible_keys[index] }
            index -= 1L
        }
    } else if function_id >= 0L {
        let function = compiler.functions[function_id]
        for offset in 0L..function.param_count {
            let parameter = compiler.parameters[function.param_start + offset]
            if parameter.name_id == name_id && type_kind(compiler, parameter.ty) == TYPE_KIND_POOL { return parameter.node }
        }
    } else { () }
    var found = OWNER_NONE
    for field in 0L..compiler.struct_fields.count() {
        let record = compiler.struct_fields[field]
        if record.name_id == name_id && type_kind(compiler, record.ty) == TYPE_KIND_POOL {
            if found != OWNER_NONE { return OWNER_AMBIGUOUS }
            found = record.node
        }
    }
    found
}

// The key (part 0) or value (part 1) type argument of a `map<K, V, N>` type node, else -1.
fn owner_map_argument(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    type_node: long,
    part: long,
) -> long {
    if type_node < 0L { return -1L }
    let file_index = node_file_index(tables.nodes, files, type_node)
    if !token_is_word_at(source, tokens, files, file_index, tables.nodes[type_node].token, "map") || (tables.nodes[type_node].meta1 & 2097151L) != 2L { return -1L }
    var child = compiler.child_first[type_node]
    for step in 0L..part {
        if child < 0L { return -1L }
        child = compiler.child_next[child]
    }
    if child >= 0L && tables.nodes[child].kind == NodeKind.TypeArgument { child } else { -1L }
}

// The declared type node of a collection place: a local with an annotation, a parameter or a struct field.
fn owner_place_type_node(compiler: CompilerTables, tables: ParseTables, node: long) -> long {
    if node < 0L { return -1L }
    if tables.nodes[node].kind == NodeKind.Name {
        let binding = compiler.facts[node].binding
        if binding < 0L { return -1L }
        let declaring = compiler.bindings[binding].node
        let first = compiler.child_first[declaring]
        if compiler.bindings[binding].parameter { return first }
        if first >= 0L && tables.nodes[first].kind == NodeKind.Annotation { return first }
    } else if tables.nodes[node].kind == NodeKind.Field {
        let field = compiler.facts[node].literal
        if field >= 0L && field < compiler.struct_fields.count() { return compiler.struct_fields[field].type_node }
    } else { () }
    -1L
}

// The owner an `Id<...>` inside a type node names: a declaring node, OWNER_NONE for an unowned id, OWNER_UNKNOWN when
// the type has no id.
fn owner_declared(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    st: OwnerState,
    type_node: long,
    function_id: long,
) -> long {
    let map_value = owner_map_argument(source, files, tokens, tables, compiler, type_node, 1L)
    let argument = owner_id_argument(source, files, tokens, tables, compiler, if map_value >= 0L { map_value } else { type_node }, 0L)
    if argument < 0L { return OWNER_UNKNOWN }
    let found = owner_resolve_name(compiler, st, compiler.token_name_ids[tables.nodes[argument].token], function_id)
    if found == OWNER_AMBIGUOUS { OWNER_NONE } else { found }
}

fn owner_child(compiler: CompilerTables, node: long, index: long) -> long {
    var child = compiler.child_first[node]
    for step in 0L..index {
        if child < 0L { return -1L }
        child = compiler.child_next[child]
    }
    child
}

fn owner_last_child(compiler: CompilerTables, node: long) -> long {
    var child = compiler.child_first[node]
    var last = -1L
    for step in 0L..tables_child_limit() {
        if child < 0L { break }
        last = child
        child = compiler.child_next[child]
    }
    last
}

fn tables_child_limit() -> long { 100000L }

// The pool a place of pool type is: a binding's declaring node or a struct field.
fn owner_of_pool_place(compiler: CompilerTables, tables: ParseTables, node: long) -> long {
    if node < 0L { return OWNER_UNKNOWN }
    if tables.nodes[node].kind == NodeKind.Name {
        let binding = compiler.facts[node].binding
        if binding >= 0L && type_kind(compiler, compiler.bindings[binding].ty) == TYPE_KIND_POOL { return compiler.bindings[binding].node }
    } else if tables.nodes[node].kind == NodeKind.Field {
        let field = compiler.facts[node].literal
        if field >= 0L && field < compiler.struct_fields.count() && type_kind(compiler, compiler.struct_fields[field].ty) == TYPE_KIND_POOL {
            return compiler.struct_fields[field].node
        }
    } else { () }
    OWNER_UNKNOWN
}

fn owner_merge(left: long, right: long) -> long {
    if left == OWNER_NIL { return right }
    if right == OWNER_NIL { return left }
    if left == right { return left }
    OWNER_UNKNOWN
}

// The pool the ids inside an expression's value belong to.
recursive fn owner_of_value(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    st: OwnerState,
    node: long,
    depth: long,
) -> long {
    if node < 0L || depth > 64L { return OWNER_UNKNOWN }
    let kind = tables.nodes[node].kind
    if (compiler.facts[node].flags & FACT_CONSTANT_VALUE) != 0L && compiler.facts[node].literal < 0L && compiler.facts[node].ty == TY_LONG { return OWNER_NIL }
    if kind == NodeKind.Integer {
        if (tables.nodes[node].flags & FLAG_NEGATIVE) != 0L { return OWNER_NIL }
        return OWNER_UNKNOWN
    }
    if kind == NodeKind.Name {
        return owner_binding_owner(st, compiler.facts[node].binding)
    }
    if kind == NodeKind.Field {
        let field = compiler.facts[node].literal
        if field < 0L || field >= compiler.struct_fields.count() { return OWNER_UNKNOWN }
        let declared = owner_declared(source, files, tokens, tables, compiler, st, compiler.struct_fields[field].type_node, -1L)
        if declared == OWNER_NONE { return OWNER_UNKNOWN }
        return declared
    }
    if kind == NodeKind.Index {
        return owner_of_value(source, files, tokens, tables, compiler, st, compiler.child_first[node], depth + 1L)
    }
    if kind == NodeKind.MethodCall {
        let receiver = compiler.child_first[node]
        if receiver >= 0L && (compiler.facts[node].flags & FACT_WINDOW_OP) != 0L {
            // arena.add / arena.finish make a window of that arena; slice keeps its receiver's arena
            let window_op = compiler.facts[node].literal & 255L
            if window_op == WOP_ADD || window_op == WOP_FINISH { return owner_of_pool_place(compiler, tables, receiver) }
            if window_op == WOP_SLICE { return owner_of_value(source, files, tokens, tables, compiler, st, receiver, depth + 1L) }
            return OWNER_UNKNOWN
        }
        if receiver >= 0L && type_kind(compiler, compiler.facts[receiver].ty) == TYPE_KIND_POOL && compiler.facts[node].literal == COLLECTION_METHOD_POOL_ADD {
            return owner_of_pool_place(compiler, tables, receiver)
        }
        // `.unwrap()` hands on the id inside the Result or Option.
        let file_index = node_file_index(tables.nodes, files, node)
        if receiver >= 0L && token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "unwrap") {
            return owner_of_value(source, files, tokens, tables, compiler, st, receiver, depth + 1L)
        }
        // map.get, list.pop and queue.peek/pop hand out an element (inside an Option): its ids belong to the collection's pool.
        if receiver >= 0L {
            let receiver_kind = type_kind(compiler, compiler.facts[receiver].ty)
            let method = compiler.facts[node].literal
            if (receiver_kind == TYPE_KIND_MAP && (method == COLLECTION_METHOD_MAP_GET || method == COLLECTION_METHOD_MAP_REMOVE)) ||
                ((collection_kind_is_list(receiver_kind) || receiver_kind == TYPE_KIND_QUEUE) && (method == COLLECTION_METHOD_POP || method == COLLECTION_METHOD_PEEK)) {
                return owner_of_value(source, files, tokens, tables, compiler, st, receiver, depth + 1L)
            }
        }
        return OWNER_UNKNOWN
    }
    if kind == NodeKind.Call {
        let function_id = compiler.facts[node].function
        if function_id < 0L {
            // ok(x) and some(x) carry the owner of x.
            let argument = compiler.child_first[node]
            if argument >= 0L && compiler.child_next[argument] < 0L { return owner_of_value(source, files, tokens, tables, compiler, st, argument, depth + 1L) }
            return OWNER_UNKNOWN
        }
        let function = compiler.functions[function_id]
        var result_type = -1L
        var member = compiler.child_first[function.node]
        for step in 0L..tables_child_limit() {
            if member < 0L { break }
            if tables.nodes[member].kind == NodeKind.ResultType { result_type = member }
            member = compiler.child_next[member]
        }
        let declared = owner_declared(source, files, tokens, tables, compiler, st, result_type, function_id)
        if declared == OWNER_NONE { return OWNER_UNKNOWN }
        if declared < 0L { return declared }
        // A pool parameter stands for the pool the caller passed.
        for offset in 0L..function.param_count {
            if compiler.parameters[function.param_start + offset].node == declared {
                return owner_of_pool_place(compiler, tables, owner_child(compiler, node, offset))
            }
        }
        return declared
    }
    // `a ?? b` is an id of a's pool or of b's.
    if kind == NodeKind.Binary && tables.nodes[node].flags == 21L {
        let left = compiler.child_first[node]
        let right = if left >= 0L { compiler.child_next[left] } else { -1L }
        return owner_merge(owner_of_value(source, files, tokens, tables, compiler, st, left, depth + 1L),
            owner_of_value(source, files, tokens, tables, compiler, st, right, depth + 1L))
    }
    if kind == NodeKind.ArrayLiteral {
        var merged = OWNER_NIL
        var element = compiler.child_first[node]
        for step in 0L..tables_child_limit() {
            if element < 0L { break }
            merged = owner_merge(merged, owner_of_value(source, files, tokens, tables, compiler, st, element, depth + 1L))
            element = compiler.child_next[element]
        }
        return merged
    }
    if kind == NodeKind.Block {
        let last = owner_last_child(compiler, node)
        if last < 0L { return OWNER_UNKNOWN }
        return owner_of_value(source, files, tokens, tables, compiler, st, last, depth + 1L)
    }
    if kind == NodeKind.Match {
        var merged = OWNER_NIL
        var arm = compiler.child_next[compiler.child_first[node]]
        for step in 0L..tables_child_limit() {
            if arm < 0L { break }
            let pattern = compiler.child_first[arm]
            let body = if pattern >= 0L { compiler.child_next[pattern] } else { -1L }
            if body >= 0L && compiler.facts[body].ty != TY_NEVER {
                merged = owner_merge(merged, owner_of_value(source, files, tokens, tables, compiler, st, body, depth + 1L))
            }
            arm = compiler.child_next[arm]
        }
        return merged
    }
    if kind == NodeKind.If {
        var merged = OWNER_NIL
        var branch = compiler.child_next[compiler.child_first[node]]
        for step in 0L..4L {
            if branch < 0L { break }
            if compiler.facts[branch].ty != TY_NEVER {
                merged = owner_merge(merged, owner_of_value(source, files, tokens, tables, compiler, st, branch, depth + 1L))
            }
            branch = compiler.child_next[branch]
        }
        return merged
    }
    OWNER_UNKNOWN
}

fn fail_owner_mismatch(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    expected: long,
    actual: long,
    window: bool,
) -> never {
    let file = files[file_index]
    let position = position_for_offset(file_index, file.base + offset, compiler)
    match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: expected ") { ok(_) => (), err(_) => env.exit(3) }
    let expected_file = files[node_file_index(tables.nodes, files, expected)]
    match write_token_raw(env.err, source, tokens, expected_file.base, tables.nodes[expected].token) { ok(_) => (), err(_) => env.exit(3) }
    if window { match env.err.write(b".Window, got ") { ok(_) => (), err(_) => env.exit(3) } }
    else { match env.err.write(b".Id, got ") { ok(_) => (), err(_) => env.exit(3) } }
    if actual >= 0L {
        let actual_file = files[node_file_index(tables.nodes, files, actual)]
        match write_token_raw(env.err, source, tokens, actual_file.base, tables.nodes[actual].token) { ok(_) => (), err(_) => env.exit(3) }
        if window { match env.err.write(b".Window") { ok(_) => (), err(_) => env.exit(3) } }
        else { match env.err.write(b".Id") { ok(_) => (), err(_) => env.exit(3) } }
    } else {
        match env.err.write(b"an id whose pool is not known (arithmetic on an id loses its pool)") { ok(_) => (), err(_) => env.exit(3) }
    }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

// A place that expects an id of pool `expected` is given the value `value`.
fn owner_check_sink(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    st: OwnerState,
    expected: long,
    value: long,
) {
    if expected < 0L || value < 0L { return }
    let actual = owner_of_value(source, files, tokens, tables, compiler, st, value, 0L)
    if actual == OWNER_NIL || actual == expected { return }
    // With a single pool in the package every id belongs to it, so an id of unknown origin cannot be another pool's.
    if actual < 0L && st.pool_declarations <= 1L { return }
    let file_index = node_file_index(tables.nodes, files, value)
    fail_owner_mismatch(env, source, files, tokens, tables, compiler, file_index, tables.nodes[value].start, expected, if actual >= 0L { actual } else { -1L }, compiler.facts[value].ty == TY_WINDOW)
}

fn owner_value_is_pool_struct(compiler: CompilerTables, type_id: long) -> bool {
    type_kind(compiler, type_id) == TYPE_KIND_STRUCT && type_contains_pool(compiler, type_id, 0L)
}

// A window operation (windows.nl): operations that read bytes through the window's owner get the arena's binding in their
// fact so that the emitter can load its address; two windows compared with each other must have the same arena; appending a
// window to an arena needs a window of that arena.
fn owner_resolve_window_op(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    st: OwnerState,
    node: long,
) {
    let op = compiler.facts[node].literal & 255L
    let first = compiler.child_first[node]
    let second = if first >= 0L { compiler.child_next[first] } else { -1L }
    let file_index = node_file_index(tables.nodes, files, node)
    if op == WOP_APPEND && second >= 0L && compiler.facts[second].ty == TY_WINDOW {
        owner_check_sink(env, source, files, tokens, tables, compiler, st, owner_of_pool_place(compiler, tables, first), second)
        return
    }
    if !window_op_needs_owner(op) { return }
    let owner = owner_of_value(source, files, tokens, tables, compiler, st, first, 0L)
    if owner < 0L {
        fail_at_message(env, files, compiler, file_index, tables.nodes[node].start,
            "cannot tell which arena this window belongs to; declare it as Window<arena name>")
    }
    if ((op >= WOP_EQ && op <= WOP_GE) || (op >= WOP_STARTS_WITH && op <= WOP_CONTAINS)) && second >= 0L && compiler.facts[second].ty == TY_WINDOW {
        owner_check_sink(env, source, files, tokens, tables, compiler, st, owner, second)
    }
    var found = -1L
    for binding in 0L..compiler.bindings.count() {
        if compiler.bindings[binding].node == owner && type_kind(compiler, compiler.bindings[binding].ty) == TYPE_KIND_POOL { found = binding; break }
    }
    if found < 0L {
        // a struct field: the function's one value of the struct that holds the field (a parameter or a local) gives the address
        var field = -1L
        for candidate in 0L..compiler.struct_fields.count() {
            if compiler.struct_fields[candidate].node == owner { field = candidate; break }
        }
        let function_node = compiler.functions[st.function_id].node
        let lowest = node_first_child(tables.nodes, function_node)
        if field >= 0L && st.function_id >= 0L {
            for binding in 0L..compiler.bindings.count() {
                let holder = compiler.bindings[binding].node
                if holder < lowest || holder > function_node || type_kind(compiler, compiler.bindings[binding].ty) != TYPE_KIND_STRUCT { continue }
                let record = type_record(compiler, compiler.bindings[binding].ty)
                if field >= record.field_start && field < record.field_start + record.field_count {
                    found = binding
                    compiler.facts[node].literal = op + (compiler.struct_fields[field].offset + 1L) * 256L
                    break
                }
            }
        }
    }
    if found < 0L {
        fail_at_message(env, files, compiler, file_index, tables.nodes[node].start,
            "this arena is a struct field with no value of its struct in this function; pass the arena down as its own parameter")
    }
    compiler.facts[node].binding = found
}

recursive fn owner_walk(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    st: write OwnerState,
    node: long,
    depth: long,
) {
    if node < 0L || depth > 200L { return }
    let kind = tables.nodes[node].kind
    let file_index = node_file_index(tables.nodes, files, node)
    if kind == NodeKind.Match {
        let scrutinee = compiler.child_first[node]
        owner_walk(env, source, files, tokens, tables, compiler, st, scrutinee, depth + 1L)
        var arm = compiler.child_next[scrutinee]
        for step in 0L..tables_child_limit() {
            if arm < 0L { break }
            st.scrutinee = scrutinee
            owner_walk(env, source, files, tokens, tables, compiler, st, arm, depth + 1L)
            arm = compiler.child_next[arm]
        }
        return
    }
    // A for-each variable over a collection of ids carries the collection's pool into the loop body.
    if kind == NodeKind.ForEach {
        let collection = compiler.child_first[node]
        let binding = compiler.facts[node].binding
        if collection >= 0L && binding >= 0L && type_kind(compiler, compiler.facts[collection].ty) == TYPE_KIND_MAP {
            // for key, value in map: the key's ids belong to the pool named by the map's key type, the value's by its value type.
            let map_type = owner_place_type_node(compiler, tables, collection)
            let function_scope = if tables.nodes[collection].kind == NodeKind.Name { st.function_id } else { -1L }
            let key_node = owner_map_argument(source, files, tokens, tables, compiler, map_type, 0L)
            let key_binding_type = compiler.bindings[binding].ty
            if key_binding_type == TY_LONG || collection_kind_is_list(type_kind(compiler, key_binding_type)) || type_kind(compiler, key_binding_type) == TYPE_KIND_ARRAY {
                let key_owner = if key_node >= 0L { owner_declared(source, files, tokens, tables, compiler, st, key_node, function_scope) } else { OWNER_UNKNOWN }
                owner_set_binding(env, st, binding, if key_owner == OWNER_NONE { OWNER_UNKNOWN } else { key_owner })
            }
            if tables.nodes[node].aux > 0L {
                let value_token = tables.extra[tables.nodes[node].extra]
                let value_binding = find_binding_in_scope(compiler, compiler.bindings[binding].scope, compiler.token_name_ids[value_token])
                if value_binding >= 0L {
                    let value_type = compiler.bindings[value_binding].ty
                    if value_type == TY_LONG || collection_kind_is_list(type_kind(compiler, value_type)) || type_kind(compiler, value_type) == TYPE_KIND_ARRAY {
                        owner_set_binding(env, st, value_binding, owner_of_value(source, files, tokens, tables, compiler, st, collection, 0L))
                    }
                }
            }
        } else if collection >= 0L && binding >= 0L && compiler.bindings[binding].ty == TY_LONG {
            owner_set_binding(env, st, binding, owner_of_value(source, files, tokens, tables, compiler, st, collection, 0L))
        }
    }
    var child = compiler.child_first[node]
    for step in 0L..tables_child_limit() {
        if child < 0L { break }
        owner_walk(env, source, files, tokens, tables, compiler, st, child, depth + 1L)
        child = compiler.child_next[child]
    }
    if is_type_node(kind) && owner_is_id_word(source, tokens, files, file_index, tables.nodes[node].token) &&
        (tables.nodes[node].meta1 & 2097151L) == 1L {
        let argument = compiler.child_first[node]
        let found = owner_resolve_name(compiler, st, compiler.token_name_ids[tables.nodes[argument].token], st.function_id)
        if found == OWNER_AMBIGUOUS {
            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start,
                "several pool fields have this name; give them different names so that Id<name> names one pool")
        }
        if found == OWNER_NONE && st.pool_declarations > 1L {
            fail_at_message(env, files, compiler, file_index, tables.nodes[node].start,
                "with more than one pool in the package, an id must name its pool: write Id<pool name> (owner parameters such as Id<P> are not supported yet)")
        }
    }
    if (compiler.facts[node].flags & FACT_WINDOW_OP) != 0L {
        owner_resolve_window_op(env, source, files, tokens, tables, compiler, st, node)
    }
    if kind == NodeKind.PatternBinding {
        let binding = compiler.facts[node].binding
        let binding_kind = if binding >= 0L { type_kind(compiler, compiler.bindings[binding].ty) } else { 0L }
        if binding >= 0L && st.scrutinee >= 0L && (compiler.bindings[binding].ty == TY_LONG || collection_kind_is_list(binding_kind) || binding_kind == TYPE_KIND_ARRAY) {
            owner_set_binding(env, st, binding, owner_of_value(source, files, tokens, tables, compiler, st, st.scrutinee, 0L))
        }
    } else if kind == NodeKind.Let {
        let binding = compiler.facts[node].binding
        let first = compiler.child_first[node]
        let has_annotation = first >= 0L && tables.nodes[first].kind == NodeKind.Annotation
        let value = if has_annotation { compiler.child_next[first] } else { first }
        if binding >= 0L && type_kind(compiler, compiler.bindings[binding].ty) == TYPE_KIND_POOL {
            match st.visible_names.push(compiler.bindings[binding].name_id) { ok(_) => (), err(_) => { env.exit(2) } }
            match st.visible_keys.push(compiler.bindings[binding].node) { ok(_) => (), err(_) => { env.exit(2) } }
        } else {
            var owner = OWNER_UNKNOWN
            if has_annotation {
                owner = owner_declared(source, files, tokens, tables, compiler, st, first, st.function_id)
                if owner >= 0L && owner_type_is_direct_id(source, files, tokens, tables, first) {
                    owner_check_sink(env, source, files, tokens, tables, compiler, st, owner, value)
                }
            }
            if owner < 0L { owner = owner_of_value(source, files, tokens, tables, compiler, st, value, 0L) }
            owner_set_binding(env, st, binding, owner)
        }
    } else if kind == NodeKind.Index {
        // pool[id]: the index must be an id of that pool.
        let receiver = compiler.child_first[node]
        if receiver >= 0L && type_kind(compiler, compiler.facts[receiver].ty) == TYPE_KIND_POOL {
            owner_check_sink(env, source, files, tokens, tables, compiler, st, owner_of_pool_place(compiler, tables, receiver), compiler.child_next[receiver])
        }
    } else if kind == NodeKind.MethodCall {
        let receiver = compiler.child_first[node]
        let argument = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
        if receiver >= 0L && type_kind(compiler, compiler.facts[receiver].ty) == TYPE_KIND_POOL {
            let method = compiler.facts[node].literal
            if method == COLLECTION_METHOD_POOL_GET || method == COLLECTION_METHOD_POOL_SET {
                owner_check_sink(env, source, files, tokens, tables, compiler, st, owner_of_pool_place(compiler, tables, receiver), argument)
            }
        } else if receiver >= 0L && collection_kind_is_list(type_kind(compiler, compiler.facts[receiver].ty)) &&
            compiler.facts[node].literal == COLLECTION_METHOD_PUSH {
            let element_owner = owner_of_value(source, files, tokens, tables, compiler, st, receiver, 0L)
            if element_owner >= 0L { owner_check_sink(env, source, files, tokens, tables, compiler, st, element_owner, argument) }
        } else if receiver >= 0L && type_kind(compiler, compiler.facts[receiver].ty) == TYPE_KIND_MAP && argument >= 0L {
            // A map declared with `Id<pool>` keys or values takes only ids of that pool.
            let method = compiler.facts[node].literal
            let map_type = owner_place_type_node(compiler, tables, receiver)
            let function_scope = if tables.nodes[receiver].kind == NodeKind.Name { st.function_id } else { -1L }
            let key_node = owner_map_argument(source, files, tokens, tables, compiler, map_type, 0L)
            if (method == COLLECTION_METHOD_MAP_GET || method == COLLECTION_METHOD_MAP_SET || method == COLLECTION_METHOD_MAP_CONTAINS ||
                method == COLLECTION_METHOD_MAP_REMOVE) && owner_type_is_direct_id(source, files, tokens, tables, key_node) {
                owner_check_sink(env, source, files, tokens, tables, compiler, st,
                    owner_declared(source, files, tokens, tables, compiler, st, key_node, function_scope), argument)
            }
            let value_node = owner_map_argument(source, files, tokens, tables, compiler, map_type, 1L)
            if method == COLLECTION_METHOD_MAP_SET && owner_type_is_direct_id(source, files, tokens, tables, value_node) {
                owner_check_sink(env, source, files, tokens, tables, compiler, st,
                    owner_declared(source, files, tokens, tables, compiler, st, value_node, function_scope), compiler.child_next[argument])
            }
        } else { () }
    } else if kind == NodeKind.Call {
        let function_id = compiler.facts[node].function
        if function_id >= 0L && (compiler.facts[node].flags & FACT_STRUCT_METHOD) == 0L {
            let function = compiler.functions[function_id]
            var parameter_node = compiler.child_first[function.node]
            var offset = 0L
            for step in 0L..tables_child_limit() {
                if parameter_node < 0L || offset >= function.param_count { break }
                if tables.nodes[parameter_node].kind == NodeKind.Parameter {
                    let type_node = compiler.child_first[parameter_node]
                    if owner_type_is_direct_id(source, files, tokens, tables, type_node) {
                        var expected = owner_declared(source, files, tokens, tables, compiler, st, type_node, function_id)
                        // A pool parameter stands for the pool the caller passed.
                        for other in 0L..function.param_count {
                            if compiler.parameters[function.param_start + other].node == expected {
                                expected = owner_of_pool_place(compiler, tables, owner_child(compiler, node, other))
                            }
                        }
                        owner_check_sink(env, source, files, tokens, tables, compiler, st, expected, owner_child(compiler, node, offset))
                    }
                    offset += 1L
                }
                parameter_node = compiler.child_next[parameter_node]
            }
        }
    } else if kind == NodeKind.InitializerField {
        let field = compiler.facts[node].binding
        if field >= 0L && field < compiler.struct_fields.count() {
            let type_node = compiler.struct_fields[field].type_node
            if owner_type_is_direct_id(source, files, tokens, tables, type_node) {
                owner_check_sink(env, source, files, tokens, tables, compiler, st,
                    owner_declared(source, files, tokens, tables, compiler, st, type_node, -1L), compiler.child_first[node])
            }
        }
    } else if kind == NodeKind.Assign {
        let target = compiler.child_first[node]
        let value = if target >= 0L { compiler.child_next[target] } else { -1L }
        if target >= 0L && (tables.nodes[target].kind == NodeKind.Name || tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index) {
            let expected = owner_of_value(source, files, tokens, tables, compiler, st, target, 0L)
            if expected >= 0L { owner_check_sink(env, source, files, tokens, tables, compiler, st, expected, value) }
        }
    } else if kind == NodeKind.Return || kind == NodeKind.ReturnStatement {
        if st.function_id >= 0L {
            let value = compiler.child_first[node]
            owner_check_return(env, source, files, tokens, tables, compiler, st, value)
            owner_check_fresh_result(env, files, tables, compiler, st.function_id, value)
        }
    } else { () }
}

// A function may return a pool or a struct holding pools only if it builds the value right there (a struct literal,
// `pool {}`, or a call of another function that does), so the returned value is the only one and no pool is ever copied.
fn owner_check_fresh_result(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    function_id: long,
    value: long,
) {
    if value < 0L || function_id < 0L { return }
    let result_ty = compiler.functions[function_id].result_ty
    if !(type_kind(compiler, result_ty) == TYPE_KIND_POOL || owner_value_is_pool_struct(compiler, result_ty)) { return }
    let kind = tables.nodes[value].kind
    if kind == NodeKind.StructInit || kind == NodeKind.PoolLiteral { return }
    if kind == NodeKind.Call && compiler.facts[value].function >= 0L { return }
    // Same wording as stage 0; a result holding a pool is allowed only when built in place (a struct literal, `pool {}` or a call).
    let function_node = compiler.functions[function_id].node
    fail_at_message(env, files, compiler, node_file_index(tables.nodes, files, function_node), tables.nodes[function_node].start,
        "a value containing a pool cannot be returned; pool owners cannot escape a function")
}

fn owner_check_return(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    st: OwnerState,
    value: long,
) {
    if value < 0L || st.function_id < 0L { return }
    var result_type = -1L
    var member = compiler.child_first[compiler.functions[st.function_id].node]
    for step in 0L..tables_child_limit() {
        if member < 0L { break }
        if tables.nodes[member].kind == NodeKind.ResultType { result_type = member }
        member = compiler.child_next[member]
    }
    if !owner_type_is_direct_id(source, files, tokens, tables, result_type) { return }
    var expected = owner_declared(source, files, tokens, tables, compiler, st, result_type, st.function_id)
    if expected < 0L { return }
    owner_check_sink(env, source, files, tokens, tables, compiler, st, expected, value)
}

fn check_pool_owners(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    var st = OwnerState {
        visible_names: list {}, visible_keys: list {}, binding_ids: list {}, binding_owners: list {},
        function_id: -1L, scrutinee: -1L, pool_declarations: 0L, pool_values: 0L,
    }
    for field in 0L..compiler.struct_fields.count() {
        if type_kind(compiler, compiler.struct_fields[field].ty) == TYPE_KIND_POOL { st.pool_declarations += 1L }
    }
    for binding in 0L..compiler.bindings.count() {
        if compiler.bindings[binding].parameter { continue }
        let ty = compiler.bindings[binding].ty
        if type_kind(compiler, ty) == TYPE_KIND_POOL { st.pool_declarations += 1L }
        if owner_value_is_pool_struct(compiler, ty) {
            st.pool_values += 1L
            if st.pool_values > 1L {
                let file_index = compiler.bindings[binding].file
                fail_at_message(env, files, compiler, file_index, tables.nodes[compiler.bindings[binding].node].start,
                    "only one value of a struct holding pools can exist, since its pools' ids would otherwise mix; pass that value down as write")
            }
        }
    }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.Struct {
            owner_walk(env, source, files, tokens, tables, compiler, st, node, 0L)
        }
    }
    for function_id in 0L..compiler.functions.count() {
        let function = compiler.functions[function_id]
        if function.file < 0L { continue }
        st.function_id = function_id
        st.scrutinee = -1L
        for step in 0L..st.visible_names.count() { match st.visible_names.pop() { some(_) => (), none => () } }
        for step in 0L..st.visible_keys.count() { match st.visible_keys.pop() { some(_) => (), none => () } }
        for offset in 0L..function.param_count {
            let parameter = compiler.parameters[function.param_start + offset]
            if type_kind(compiler, parameter.ty) == TYPE_KIND_POOL {
                match st.visible_names.push(parameter.name_id) { ok(_) => (), err(_) => { env.exit(2) } }
                match st.visible_keys.push(parameter.node) { ok(_) => (), err(_) => { env.exit(2) } }
            }
        }
        for offset in 0L..function.param_count {
            let parameter = compiler.parameters[function.param_start + offset]
            let type_node = compiler.child_first[parameter.node]
            let owner = owner_declared(source, files, tokens, tables, compiler, st, type_node, function_id)
            // Parameters carry their declared owner into the body through the binding of the same node.
            for binding in 0L..compiler.bindings.count() {
                if compiler.bindings[binding].parameter && compiler.bindings[binding].node == parameter.node { owner_set_binding(env, st, binding, owner) }
            }
        }
        owner_walk(env, source, files, tokens, tables, compiler, st, function.node, 0L)
        // The body's last expression is returned.
        let body = function.body
        if body >= 0L {
            let last = owner_last_child(compiler, body)
            if last >= 0L {
                let last_kind = tables.nodes[last].kind
                if last_kind == NodeKind.Name || last_kind == NodeKind.Field || last_kind == NodeKind.Index || last_kind == NodeKind.Call ||
                    last_kind == NodeKind.MethodCall || last_kind == NodeKind.Match || last_kind == NodeKind.If || last_kind == NodeKind.Block {
                    owner_check_return(env, source, files, tokens, tables, compiler, st, last)
                    owner_check_fresh_result(env, files, tables, compiler, function_id, last)
                }
            }
        }
    }
}
