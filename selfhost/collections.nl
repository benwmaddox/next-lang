struct CollectionCapacityValue {
    value: long
    constant: bool
    valid: bool
}

const COLLECTION_METHOD_LEN: long = 1001L
const COLLECTION_METHOD_COUNT: long = 1002L
const COLLECTION_METHOD_PUSH: long = 1003L
const COLLECTION_METHOD_INSERT: long = 1004L
const COLLECTION_METHOD_REMOVE: long = 1005L
const COLLECTION_METHOD_CLEAR: long = 1006L
const COLLECTION_METHOD_POP: long = 1007L

fn collection_method_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    method_token: long,
    receiver_kind: long,
) -> long {
    if receiver_kind == TYPE_KIND_ARRAY && token_is_word_at(source, tokens, files, file_index, method_token, "len") { COLLECTION_METHOD_LEN }
    else if receiver_kind == TYPE_KIND_LIST && token_is_word_at(source, tokens, files, file_index, method_token, "count") { COLLECTION_METHOD_COUNT }
    else if receiver_kind == TYPE_KIND_LIST && token_is_word_at(source, tokens, files, file_index, method_token, "push") { COLLECTION_METHOD_PUSH }
    else if receiver_kind == TYPE_KIND_LIST && token_is_word_at(source, tokens, files, file_index, method_token, "insert") { COLLECTION_METHOD_INSERT }
    else if receiver_kind == TYPE_KIND_LIST && token_is_word_at(source, tokens, files, file_index, method_token, "remove") { COLLECTION_METHOD_REMOVE }
    else if receiver_kind == TYPE_KIND_LIST && token_is_word_at(source, tokens, files, file_index, method_token, "clear") { COLLECTION_METHOD_CLEAR }
    else if receiver_kind == TYPE_KIND_LIST && token_is_word_at(source, tokens, files, file_index, method_token, "pop") { COLLECTION_METHOD_POP }
    else { 0L }
}

fn collection_capacity_invalid() -> CollectionCapacityValue {
    CollectionCapacityValue { value: 0L, constant: false, valid: false }
}

fn collection_capacity_value(value: long) -> CollectionCapacityValue {
    CollectionCapacityValue { value, constant: true, valid: true }
}

fn collection_capacity_overflow() -> CollectionCapacityValue {
    CollectionCapacityValue { value: 0L, constant: true, valid: false }
}

fn checked_capacity_add(left: long, right: long) -> CollectionCapacityValue {
    if right > 0L && left > 9223372036854775807L - right { return collection_capacity_overflow() }
    if right < 0L && left < -9223372036854775808L - right { return collection_capacity_overflow() }
    collection_capacity_value(left + right)
}

fn checked_capacity_subtract(left: long, right: long) -> CollectionCapacityValue {
    if right < 0L && left > 9223372036854775807L + right { return collection_capacity_overflow() }
    if right > 0L && left < -9223372036854775808L + right { return collection_capacity_overflow() }
    collection_capacity_value(left - right)
}

fn checked_capacity_multiply(left: long, right: long) -> CollectionCapacityValue {
    if left == 0L || right == 0L { return collection_capacity_value(0L) }
    if left > 0L {
        if right > 0L && left > 9223372036854775807L / right { return collection_capacity_overflow() }
        if right < 0L && right < -9223372036854775808L / left { return collection_capacity_overflow() }
    } else {
        if right > 0L && left < -9223372036854775808L / right { return collection_capacity_overflow() }
        if right < 0L && right < 9223372036854775807L / left { return collection_capacity_overflow() }
    }
    collection_capacity_value(left * right)
}

fn checked_capacity_divide(left: long, right: long) -> CollectionCapacityValue {
    if right == 0L || (left == -9223372036854775808L && right == -1L) {
        return collection_capacity_overflow()
    }
    collection_capacity_value(left / right)
}

fn checked_capacity_remainder(left: long, right: long) -> CollectionCapacityValue {
    if right == 0L { return collection_capacity_overflow() }
    if left == -9223372036854775808L && right == -1L { return collection_capacity_value(0L) }
    collection_capacity_value(left % right)
}

fn checked_capacity_negate(value: long) -> CollectionCapacityValue {
    if value == -9223372036854775808L { return collection_capacity_overflow() }
    collection_capacity_value(-value)
}

fn collection_integer_literal_capacity(tables: ParseTables, node: long) -> CollectionCapacityValue {
    let syntax = tables.nodes[node]
    if syntax.extra < 0L || syntax.extra >= tables.literals.count() { return collection_capacity_invalid() }
    let literal = tables.literals[syntax.extra]
    if literal.limb3 != 0L || literal.limb2 != 0L || literal.limb1 < 0L || literal.limb0 < 0L || literal.limb0 > 4294967295L {
        return collection_capacity_overflow()
    }
    if (syntax.flags & FLAG_NEGATIVE) != 0L {
        if literal.limb1 > 2147483648L || (literal.limb1 == 2147483648L && literal.limb0 != 0L) {
            return collection_capacity_overflow()
        }
        if literal.limb1 == 2147483648L { return collection_capacity_value(-9223372036854775808L) }
        let magnitude = literal.limb1 * 4294967296L + literal.limb0
        collection_capacity_value(0L - magnitude)
    } else {
        if literal.limb1 > 2147483647L { return collection_capacity_overflow() }
        collection_capacity_value(literal.limb1 * 4294967296L + literal.limb0)
    }
}

recursive fn evaluate_collection_capacity(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    depth: long,
) -> CollectionCapacityValue {
    if depth > 256L { return collection_capacity_invalid() }
    if node < 0L || node >= tables.nodes.count() { return collection_capacity_invalid() }
    let syntax = tables.nodes[node]
    if syntax.kind == NodeKind.Integer {
        collection_integer_literal_capacity(tables, node)
    } else if syntax.kind == NodeKind.Unary && syntax.flags == 0L {
        let child = compiler.child_first[node]
        let value = evaluate_collection_capacity(tables, compiler, child, depth + 1L)
        if !value.constant || !value.valid { return value }
        checked_capacity_negate(value.value)
    } else if syntax.kind == NodeKind.Binary && syntax.flags >= 0L && syntax.flags <= 4L {
        let left_node = compiler.child_first[node]
        let right_node = if left_node >= 0L { compiler.child_next[left_node] } else { -1L }
        let left = evaluate_collection_capacity(tables, compiler, left_node, depth + 1L)
        let right = evaluate_collection_capacity(tables, compiler, right_node, depth + 1L)
        if !left.constant || !right.constant { return collection_capacity_invalid() }
        if !left.valid || !right.valid { return collection_capacity_overflow() }
        if syntax.flags == 0L {
            checked_capacity_add(left.value, right.value)
        } else if syntax.flags == 1L {
            checked_capacity_subtract(left.value, right.value)
        } else if syntax.flags == 2L {
            checked_capacity_multiply(left.value, right.value)
        } else if syntax.flags == 3L {
            checked_capacity_divide(left.value, right.value)
        } else {
            checked_capacity_remainder(left.value, right.value)
        }
    } else if syntax.kind == NodeKind.Name && syntax.token >= 0L {
        if node < compiler.facts.count() && compiler.facts[node].binding >= 0L {
            return collection_capacity_invalid()
        }
        let name_id = compiler.token_name_ids[syntax.token]
        if node < compiler.facts.count() && (compiler.facts[node].flags & FACT_CONSTANT_VALUE) != 0L {
            return collection_capacity_value(compiler.facts[node].literal)
        }
        var constant_node = -1L
        for candidate in 0L..tables.nodes.count() {
            if tables.nodes[candidate].kind == NodeKind.Const && compiler.token_name_ids[tables.nodes[candidate].token] == name_id {
                constant_node = candidate
                break
            }
        }
        if constant_node < 0L { return collection_capacity_invalid() }
        if constant_node < compiler.facts.count() &&
            (compiler.facts[constant_node].flags & FACT_CONSTANT_EVALUATED) != 0L {
            collection_capacity_value(compiler.facts[constant_node].literal)
        } else { collection_capacity_invalid() }
    } else {
        collection_capacity_invalid()
    }
}

recursive fn unsupported_collection_capacity_constant(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    depth: long,
) -> long {
    if depth > 256L || node < 0L || node >= tables.nodes.count() { return -1L }
    let syntax = tables.nodes[node]
    if syntax.kind == NodeKind.Name && syntax.token >= 0L {
        if node < compiler.facts.count() && compiler.facts[node].binding >= 0L { return -1L }
        let name_id = compiler.token_name_ids[syntax.token]
        let declaration = find_constant_declaration(tables, compiler, name_id)
        if declaration >= 0L && (compiler.facts[declaration].flags & FACT_CONSTANT_EVALUATED) == 0L {
            return declaration
        }
        return -1L
    }
    if syntax.kind == NodeKind.Unary && syntax.flags == 0L {
        return unsupported_collection_capacity_constant(tables, compiler, compiler.child_first[node], depth + 1L)
    }
    if syntax.kind == NodeKind.Binary && syntax.flags >= 0L && syntax.flags <= 4L {
        let left = compiler.child_first[node]
        let right = if left >= 0L { compiler.child_next[left] } else { -1L }
        let left_declaration = unsupported_collection_capacity_constant(tables, compiler, left, depth + 1L)
        if left_declaration >= 0L { return left_declaration }
        return unsupported_collection_capacity_constant(tables, compiler, right, depth + 1L)
    }
    -1L
}

recursive fn loop_push_receiver_binding(tables: ParseTables, compiler: CompilerTables, node: long, scope: long) -> long {
    if node < 0L { return -1L }
    let kind = tables.nodes[node].kind
    if kind == NodeKind.Name {
        find_binding_in_scope(compiler, scope, compiler.token_name_ids[tables.nodes[node].token])
    } else if kind == NodeKind.Field || kind == NodeKind.Index {
        loop_push_receiver_binding(tables, compiler, compiler.child_first[node], scope)
    } else { -1L }
}

recursive fn count_loop_pushes_for_binding(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    binding: long,
    scope: long,
    file_index: long,
    depth: long,
) -> LoopPushCount {
    if node < 0L { return LoopPushCount { count: 0L, valid: true } }
    if depth > MAX_PARSE_WORK { return LoopPushCount { count: 0L, valid: false } }
    let kind = tables.nodes[node].kind
    if kind == NodeKind.For || kind == NodeKind.ForEach || kind == NodeKind.While {
        return LoopPushCount { count: 0L, valid: false }
    }
    var assigned_growth = 0L
    if kind == NodeKind.Assign {
        let target = compiler.child_first[node]
        if loop_push_receiver_binding(tables, compiler, target, scope) == binding {
            let value = compiler.child_next[target]
            if tables.nodes[node].flags == 1L && binding >= 0L && binding < compiler.bindings.count() &&
                type_kind(compiler, compiler.bindings[binding].ty) == TYPE_KIND_ASCII {
                assigned_growth = known_text_byte_length(source, tokens, files, tables, compiler, file_index, value, 0L)
                if assigned_growth < 0L { return LoopPushCount { count: 0L, valid: false } }
            } else { return LoopPushCount { count: 0L, valid: false } }
        }
    }
    if kind == NodeKind.MethodCall {
        let receiver = compiler.child_first[node]
        if loop_push_receiver_binding(tables, compiler, receiver, scope) == binding {
            let token = tables.nodes[node].token
            let is_push = token_is_word_at(source, tokens, files, file_index, token, "push")
            let is_checked_append = token_is_word_at(source, tokens, files, file_index, token, "try_append")
            if is_checked_append { return LoopPushCount { count: 0L, valid: false } }
            let changes_count = is_push || token_is_word_at(source, tokens, files, file_index, token, "insert") ||
                token_is_word_at(source, tokens, files, file_index, token, "pop") ||
                token_is_word_at(source, tokens, files, file_index, token, "remove")
            // clear() only lowers the count, so the bound before + pushes * iterations
            // still holds after it (stage 0 keeps its loop proof across clear too).
            if changes_count && !is_push { return LoopPushCount { count: 0L, valid: false } }
        }
    }
    if kind == NodeKind.Call {
        let function = find_function_by_name(compiler, compiler.token_name_ids[tables.nodes[node].token])
        if function >= 0L {
            var argument = compiler.child_first[node]
            for argument_index in 0L..compiler.functions[function].param_count {
                let parameter = compiler.parameters[compiler.functions[function].param_start + argument_index]
                if (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L && argument >= 0L &&
                    loop_push_receiver_binding(tables, compiler, argument, scope) == binding {
                    return LoopPushCount { count: 0L, valid: false }
                }
                if argument >= 0L { argument = compiler.child_next[argument] }
            }
        }
    }
    if kind == NodeKind.Block {
        var statement = compiler.child_first[node]
        for statement_step in 0L..tables.nodes[node].subtree {
            if statement < 0L { break }
            if tables.nodes[statement].kind == NodeKind.If {
                return LoopPushCount { count: 0L, valid: false }
            }
            statement = compiler.child_next[statement]
        }
    }
    if kind == NodeKind.If {
        let condition = compiler.child_first[node]
        let then_block = if condition >= 0L { compiler.child_next[condition] } else { -1L }
        let else_block = if then_block >= 0L { compiler.child_next[then_block] } else { -1L }
        let condition_pushes = count_loop_pushes_for_binding(source, tokens, files, tables, compiler, condition, binding, scope, file_index, depth + 1L)
        let then_pushes = count_loop_pushes_for_binding(source, tokens, files, tables, compiler, then_block, binding, scope, file_index, depth + 1L)
        let else_pushes = count_loop_pushes_for_binding(source, tokens, files, tables, compiler, else_block, binding, scope, file_index, depth + 1L)
        if !condition_pushes.valid || !then_pushes.valid || !else_pushes.valid { return LoopPushCount { count: 0L, valid: false } }
        let branch_count = if then_pushes.count > else_pushes.count { then_pushes.count } else { else_pushes.count }
        return LoopPushCount { count: condition_pushes.count + branch_count, valid: true }
    }
    if kind == NodeKind.Match {
        let scrutinee = compiler.child_first[node]
        let scrutinee_pushes = count_loop_pushes_for_binding(source, tokens, files, tables, compiler, scrutinee, binding, scope, file_index, depth + 1L)
        if !scrutinee_pushes.valid { return LoopPushCount { count: 0L, valid: false } }
        var maximum = 0L
        var arm = if scrutinee >= 0L { compiler.child_next[scrutinee] } else { -1L }
        for arm_step in 0L..tables.nodes[node].subtree {
            if arm < 0L { break }
            let arm_pushes = count_loop_pushes_for_binding(source, tokens, files, tables, compiler, arm, binding, scope, file_index, depth + 1L)
            if !arm_pushes.valid { return LoopPushCount { count: 0L, valid: false } }
            if arm_pushes.count > maximum { maximum = arm_pushes.count }
            arm = compiler.child_next[arm]
        }
        return LoopPushCount { count: scrutinee_pushes.count + maximum, valid: true }
    }
    var count = assigned_growth
    if kind == NodeKind.MethodCall && token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "push") {
        let receiver = compiler.child_first[node]
        if loop_push_receiver_binding(tables, compiler, receiver, scope) == binding { count = 1L }
    }
    var child = compiler.child_first[node]
    for child_step in 0L..tables.nodes[node].subtree {
        if child < 0L { break }
        let nested = count_loop_pushes_for_binding(source, tokens, files, tables, compiler, child, binding, scope, file_index, depth + 1L)
        if !nested.valid { return LoopPushCount { count: 0L, valid: false } }
        count += nested.count
        child = compiler.child_next[child]
    }
    LoopPushCount { count, valid: true }
}

fn loop_iteration_count(tables: ParseTables, compiler: CompilerTables, start: long, finish: long, inclusive: bool) -> long {
    let first = evaluate_collection_capacity(tables, compiler, start, 0L)
    let last = evaluate_collection_capacity(tables, compiler, finish, 0L)
    if !first.constant || !last.constant || !first.valid || !last.valid { return -1L }
    if last.value <= first.value {
        if inclusive && last.value == first.value { return 1L }
        return 0L
    }
    if first.value < 0L && last.value > 9223372036854775807L + first.value { return -1L }
    let difference = last.value - first.value
    if inclusive {
        if difference == 9223372036854775807L { -1L } else { difference + 1L }
    } else { difference }
}

fn prepare_loop_push_proofs(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    loop_node: long,
    body: long,
    scope: long,
    iterations: long,
    file_index: long,
    loop_depth: long,
) {
    begin_loop_count_snapshot(compiler, loop_node)
    if body < 0L || iterations < 0L { return }
    let first_node = body - tables.nodes[body].subtree + 1L
    for candidate in first_node..body + 1L {
        let candidate_kind = tables.nodes[candidate].kind
        let receiver = if candidate_kind == NodeKind.MethodCall &&
            token_is_word_at(source, tokens, files, file_index, tables.nodes[candidate].token, "push") {
            compiler.child_first[candidate]
        } else if candidate_kind == NodeKind.Assign && tables.nodes[candidate].flags == 1L {
            compiler.child_first[candidate]
        } else { -1L }
        if receiver < 0L { continue }
        let binding = loop_push_receiver_binding(tables, compiler, receiver, scope)
        if binding < 0L { continue }
        let builder_kind = type_kind(compiler, compiler.bindings[binding].ty)
        if builder_kind != TYPE_KIND_LIST && builder_kind != TYPE_KIND_BYTES && builder_kind != TYPE_KIND_ASCII { continue }
        var seen = false
        for previous in first_node..candidate {
            let previous_kind = tables.nodes[previous].kind
            let previous_receiver = if previous_kind == NodeKind.MethodCall &&
                token_is_word_at(source, tokens, files, file_index, tables.nodes[previous].token, "push") {
                compiler.child_first[previous]
            } else if previous_kind == NodeKind.Assign && tables.nodes[previous].flags == 1L {
                compiler.child_first[previous]
            } else { -1L }
            if previous_receiver >= 0L && loop_push_receiver_binding(tables, compiler, previous_receiver, scope) == binding { seen = true }
        }
        if seen { continue }
        let pushes = count_loop_pushes_for_binding(source, tokens, files, tables, compiler, body, binding, scope, file_index, 0L)
        let before = compiler.bindings[binding].collection_count
        let capacity = collection_capacity(compiler, compiler.bindings[binding].ty)
        if !pushes.valid || pushes.count <= 0L { continue }
        // A loop that never runs proves its pushes whatever the count is (as in stage 0).
        if iterations != 0L && (before < 0L || before > capacity) { continue }
        var fits = false
        if iterations == 0L { fits = true }
        else if pushes.count <= (capacity - before) / iterations { fits = true }
        else { () }
        if fits {
            let final_count = before + pushes.count * iterations
            compiler.loop_push_proofs.push(LoopPushProof { loop_node, binding, final_count, loop_depth }).unwrap()
        }
    }
}

fn loop_push_is_proven(compiler: CompilerTables, binding: long, loop_depth: long) -> bool {
    if binding < 0L || binding >= compiler.bindings.count() { return false }
    if compiler.bindings[binding].collection_count < 0L { return false }
    if loop_depth == 0L {
        let count = compiler.bindings[binding].collection_count
        return count >= 0L && count < collection_capacity(compiler, compiler.bindings[binding].ty)
    }
    for proof_index in 0L..compiler.loop_push_proofs.count() {
        if compiler.loop_push_proofs[proof_index].binding == binding && compiler.loop_push_proofs[proof_index].loop_depth == loop_depth { return true }
    }
    false
}

fn builder_push_is_proven(compiler: CompilerTables, receiver: long, loop_depth: long) -> bool {
    if receiver < 0L { return false }
    let binding = compiler.facts[receiver].binding
    if binding < 0L || binding >= compiler.bindings.count() ||
        compiler.bindings[binding].ty != compiler.facts[receiver].ty ||
        type_kind(compiler, compiler.bindings[binding].ty) != TYPE_KIND_BYTES {
        return false
    }
    loop_push_is_proven(compiler, binding, loop_depth)
}

fn invalidate_collection_counts_for_write_call(
    compiler: write CompilerTables,
    function: FunctionRecord,
    call_node: long,
) {
    var argument = compiler.child_first[call_node]
    for argument_index in 0L..function.param_count {
        let parameter = compiler.parameters[function.param_start + argument_index]
        if (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L && argument >= 0L {
            let binding = compiler.facts[argument].binding
            if binding >= 0L && binding < compiler.bindings.count() &&
                compiler.bindings[binding].ty == compiler.facts[argument].ty &&
                (type_kind(compiler, compiler.bindings[binding].ty) == TYPE_KIND_LIST ||
                    deferred_text_kind(type_kind(compiler, compiler.bindings[binding].ty))) {
                set_binding_collection_count(compiler, binding, -1L)
            }
        }
        if argument >= 0L { argument = compiler.child_next[argument] }
    }
}

fn finish_loop_push_proofs(compiler: write CompilerTables, loop_node: long) {
    finish_loop_count_snapshot(compiler, loop_node)
    let original_count = compiler.loop_push_proofs.count()
    var write_index = 0L
    for read_index in 0L..original_count {
        let proof = compiler.loop_push_proofs[read_index]
        if proof.loop_node != loop_node {
            compiler.loop_push_proofs[write_index] = proof
            write_index += 1L
        }
    }
    for pop_index in 0L..original_count - write_index { match compiler.loop_push_proofs.pop() { some(_) => (), none() => () } }
}

fn collection_type_matches(compiler: CompilerTables, kind: long, element: long, capacity: long) -> long {
    for type_id in 0L..type_count(compiler) {
        let record = type_record(compiler, type_id)
        if type_record_kind(record) == kind && record.field_start == element && record.field_count == capacity {
            return type_id
        }
    }
    -1L
}

fn intern_collection_type(
    compiler: write CompilerTables,
    kind: long,
    element: long,
    capacity: long,
    file_index: long,
    node: long,
    name_id: long,
    name_token: long,
) -> long {
    let existing = collection_type_matches(compiler, kind, element, capacity)
    if existing >= 0L { return existing }
    append_type_record(compiler, TypeRecord {
        kind_state: kind * 16L,
        name_id,
        name_token,
        node,
        file: file_index,
        // Collection records use field_start for the element type id and
        // field_count for the fixed capacity. They never index struct_fields.
        field_start: element,
        field_count: capacity,
        size: 0L,
        align: 1L,
        helper_mask: 0L,
    })
}

fn collection_capacity_error(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    node: long,
    is_list: bool,
    negative: bool,
) -> never {
    if negative {
        if is_list {
            fail_at_message(env, files, compiler, file_index, node,
                "list capacity cannot be negative; use zero or a positive constant")
        } else {
            fail_at_message(env, files, compiler, file_index, node,
                "array capacity cannot be negative; use zero or a positive constant")
        }
    } else {
        fail_at_message(env, files, compiler, file_index, node,
            "collection capacity must be a constant integer expression; use a literal or const value")
    }
}

fn collection_capacity_overflow_error(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    node: long,
) -> never {
    fail_at_message(env, files, compiler, file_index, node, "collection size overflows long; reduce a capacity")
}

fn collection_type_syntax_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    syntax: Node,
) -> long {
    if syntax.token >= 0L && token_is_word_at(source, tokens, files, file_index, syntax.token, "list") {
        TYPE_KIND_LIST
    } else { 0L }
}

fn intern_collection_type_syntax(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    node: long,
) -> long {
    let syntax = tables.nodes[node]
    let argument_count = syntax.meta1 & 2097151L
    let constant_count = (syntax.meta1 >> 21L) & 2097151L
    let array_count = (syntax.meta1 >> 42L) & 2097151L
    let is_list = collection_type_syntax_kind(source, tokens, files, file_index, syntax) == TYPE_KIND_LIST
    if !is_list && array_count == 0L {
        return intern_text_type_syntax(env, source, tokens, files, tables, compiler, file_index, node)
    }

    var type_id = -1L
    var child = compiler.child_first[node]
    if is_list {
        if argument_count != 1L || constant_count != 1L || child < 0L || tables.nodes[child].kind != NodeKind.TypeArgument {
            fail_at_message(env, files, compiler, file_index, syntax.start, "list type needs an element type and a constant capacity")
        }
        if (compiler.facts[child].flags & FACT_RESOLVED_TYPE) == 0L { return -1L }
        let element_type = compiler.facts[child].ty
        child = compiler.child_next[child]
        let capacity_node = child
        let capacity_value = evaluate_collection_capacity(tables, compiler, capacity_node, 0L)
        if !capacity_value.constant {
            let unsupported = unsupported_collection_capacity_constant(tables, compiler, capacity_node, 0L)
            if unsupported >= 0L { return -1L }
            collection_capacity_error(env, files, compiler, file_index, if capacity_node >= 0L { tables.nodes[capacity_node].start } else { syntax.start }, true, false)
        }
        if !capacity_value.valid { collection_capacity_overflow_error(env, files, compiler, file_index, syntax.start) }
        if capacity_value.value < 0L { collection_capacity_error(env, files, compiler, file_index, tables.nodes[capacity_node].start, true, true) }
        let list_name_id = compiler.token_name_ids[syntax.token]
        type_id = intern_collection_type(compiler, TYPE_KIND_LIST, element_type, capacity_value.value, file_index, node, list_name_id, syntax.token)
        child = if capacity_node >= 0L { compiler.child_next[capacity_node] } else { -1L }
    } else {
        type_id = intern_text_type_syntax(env, source, tokens, files, tables, compiler, file_index, node)
        if type_id < 0L { type_id = resolve_value_type(source, tokens, files, tables, compiler, file_index, node) }
        if type_id < 0L && generic_type_kind(source, tokens, files, tables, file_index, node) != 0L {
            let generic_kind = generic_type_kind(source, tokens, files, tables, file_index, node)
            let expected_args = if generic_kind == TYPE_KIND_OPTION { 1L } else { 2L }
            let first = compiler.child_first[node]
            let second = if first >= 0L { compiler.child_next[first] } else { -1L }
            if first >= 0L && (expected_args == 1L || second >= 0L) {
                let first_ty = compiler.facts[first].ty
                let second_ty = if expected_args == 2L { compiler.facts[second].ty } else { -1L }
                let sum_name_id = compiler.token_name_ids[syntax.token]
                type_id = intern_sum_type(compiler, generic_kind, first_ty, second_ty, file_index, node, sum_name_id, syntax.token)
            }
        }
        child = compiler.child_first[node]
        for arg_step in 0L..argument_count { if child >= 0L { child = compiler.child_next[child] } }
        for const_step in 0L..constant_count { if child >= 0L { child = compiler.child_next[child] } }
    }

    for array_index in 0L..array_count {
        if child < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "array type needs a constant capacity") }
        if type_id < 0L { return -1L }
        let capacity_node = child
        let capacity_value = evaluate_collection_capacity(tables, compiler, capacity_node, 0L)
        if !capacity_value.constant {
            let unsupported = unsupported_collection_capacity_constant(tables, compiler, capacity_node, 0L)
            if unsupported >= 0L { return -1L }
            collection_capacity_error(env, files, compiler, file_index, tables.nodes[capacity_node].start, false, false)
        }
        if !capacity_value.valid { collection_capacity_overflow_error(env, files, compiler, file_index, syntax.start) }
        if capacity_value.value < 0L { collection_capacity_error(env, files, compiler, file_index, tables.nodes[capacity_node].start, false, true) }
        type_id = intern_collection_type(compiler, TYPE_KIND_ARRAY, type_id, capacity_value.value, file_index, node, -1L, syntax.token)
        child = compiler.child_next[child]
    }
    type_id
}

fn collection_element_type(compiler: CompilerTables, type_id: long) -> long {
    if type_kind(compiler, type_id) == TYPE_KIND_ASCII || type_kind(compiler, type_id) == TYPE_KIND_BYTES { TY_BYTE }
    else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || type_kind(compiler, type_id) == TYPE_KIND_LIST {
        type_record(compiler, type_id).field_start
    } else { -1L }
}

fn collection_capacity(compiler: CompilerTables, type_id: long) -> long {
    if type_kind(compiler, type_id) == TYPE_KIND_ASCII || type_kind(compiler, type_id) == TYPE_KIND_BYTES { text_max_bytes(compiler, type_id) }
    else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || type_kind(compiler, type_id) == TYPE_KIND_LIST {
        type_record(compiler, type_id).field_count
    } else { -1L }
}

recursive fn type_contains_collection(compiler: CompilerTables, type_id: long, depth: long) -> bool {
    if depth > 256L || type_id < 0L || type_id >= type_count(compiler) { return false }
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_ARRAY || kind == TYPE_KIND_LIST { return true }
    if kind == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_offset in 0L..record.field_count {
            if type_contains_collection(compiler, compiler.struct_fields[record.field_start + field_offset].ty, depth + 1L) { return true }
        }
    } else if kind == TYPE_KIND_ENUM {
        let record = type_record(compiler, type_id)
        for case_offset in 0L..record.field_count {
            let case = compiler.enum_cases[record.field_start + case_offset]
            for part in 0L..case.payload_count {
                if type_contains_collection(compiler, compiler.enum_payloads[case.payload_start + part].ty, depth + 1L) { return true }
            }
        }
    } else if kind == TYPE_KIND_OPTION || kind == TYPE_KIND_RESULT {
        for tag in 0L..sum_case_count(compiler, type_id) {
            for part in 0L..sum_case_payload_count(compiler, type_id, tag) {
                let payload_type = sum_case_payload_type(compiler, type_id, tag, part)
                if type_contains_collection(compiler, payload_type, depth + 1L) { return true }
            }
        }
    } else { () }
    false
}

fn collection_has_nested_elements(compiler: CompilerTables, type_id: long) -> bool {
    let kind = type_kind(compiler, type_id)
    if kind != TYPE_KIND_ARRAY && kind != TYPE_KIND_LIST { return false }
    let element_type = collection_element_type(compiler, type_id)
    type_contains_collection(compiler, element_type, 0L)
}

recursive fn type_contains_bytes(compiler: CompilerTables, type_id: long, depth: long) -> bool {
    if depth > 256L { return true }
    if type_id < 0L || type_id >= type_count(compiler) { return false }
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_BYTES { return true }
    if kind == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_offset in 0L..record.field_count {
            if type_contains_bytes(compiler, compiler.struct_fields[record.field_start + field_offset].ty, depth + 1L) { return true }
        }
    } else if kind == TYPE_KIND_ARRAY || kind == TYPE_KIND_LIST {
        let element_type = collection_element_type(compiler, type_id)
        return type_contains_bytes(compiler, element_type, depth + 1L)
    } else if kind == TYPE_KIND_ENUM {
        let record = type_record(compiler, type_id)
        for case_offset in 0L..record.field_count {
            let case = compiler.enum_cases[record.field_start + case_offset]
            for part in 0L..case.payload_count {
                if type_contains_bytes(compiler, compiler.enum_payloads[case.payload_start + part].ty, depth + 1L) { return true }
            }
        }
    } else if kind == TYPE_KIND_OPTION || kind == TYPE_KIND_RESULT {
        for tag in 0L..sum_case_count(compiler, type_id) {
            for part in 0L..sum_case_payload_count(compiler, type_id, tag) {
                let payload_type = sum_case_payload_type(compiler, type_id, tag, part)
                if type_contains_bytes(compiler, payload_type, depth + 1L) { return true }
            }
        }
    } else { () }
    false
}

fn syntax_has_nested_collection_elements(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
) -> bool {
    let type_id = resolve_value_type(source, tokens, files, tables, compiler, file_index, node)
    type_id >= 0L && collection_has_nested_elements(compiler, type_id) &&
        !is_c_runtime_dir_entry_list_type(compiler, type_id)
}

fn is_c_runtime_path_type(compiler: CompilerTables, type_id: long) -> bool {
    if !compiler.c_runtime || type_kind(compiler, type_id) != TYPE_KIND_LIST { return false }
    let path = type_record(compiler, type_id)
    path.field_start == TY_BYTE && path.field_count == 4096L
}

fn is_c_runtime_dir_entry_type(compiler: CompilerTables, type_id: long) -> bool {
    if !compiler.c_runtime || type_kind(compiler, type_id) != TYPE_KIND_STRUCT { return false }
    let entry = type_record(compiler, type_id)
    if entry.node != -7L || entry.field_count != 2L { return false }
    let name = compiler.struct_fields[entry.field_start]
    let kind = compiler.struct_fields[entry.field_start + 1L]
    let file_kind = type_record(compiler, kind.ty)
    name.node == -7L && name.offset == 0L && is_c_runtime_path_type(compiler, name.ty) &&
        kind.node == -7L && kind.offset == 16392L &&
        type_record_kind(file_kind) == TYPE_KIND_ENUM && file_kind.node == -5L && file_kind.field_count == 3L
}

fn is_c_runtime_dir_entry_list_type(compiler: CompilerTables, type_id: long) -> bool {
    if !compiler.c_runtime || type_kind(compiler, type_id) != TYPE_KIND_LIST { return false }
    let entries = type_record(compiler, type_id)
    entries.field_count >= 0L && entries.field_count <= MAX_DIRECTORY_ENTRIES &&
        is_c_runtime_dir_entry_type(compiler, entries.field_start)
}

fn checked_size_product(left: long, right: long) -> long {
    if left < 0L || right < 0L { return -1L }
    if left == 0L || right == 0L { return 0L }
    if left > MAX_VALUE_SIZE / right { -2L } else { left * right }
}

fn checked_layout_size_add(left: long, right: long) -> long {
    if left == -2L || right == -2L { return -2L }
    if left < 0L || right < 0L { return -1L }
    if left > MAX_VALUE_SIZE - right { -2L } else { left + right }
}

fn checked_layout_size_align(value: long, align: long) -> long {
    if value == -2L { return -2L }
    if value < 0L || align <= 0L { return -1L }
    if align <= 1L { return value }
    let remainder = value % align
    if remainder == 0L { value } else { checked_layout_size_add(value, align - remainder) }
}

recursive fn type_group_size(compiler: CompilerTables, type_id: long, copies: long) -> long {
    if type_id < 0L || copies < 0L { return -1L }
    let kind = type_kind(compiler, type_id)
    let record = type_record(compiler, type_id)
    if kind == TYPE_KIND_STRUCT {
        var offset = 0L
        var alignment = 1L
        for field_offset in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_offset]
            let field_size = type_group_size(compiler, field.ty, copies)
            let field_align = value_type_align(compiler, field.ty)
            if field_size < 0L { return field_size }
            if field_align < 0L { return -1L }
            offset = checked_layout_size_align(offset, field_align)
            if offset < 0L { return offset }
            offset = checked_layout_size_add(offset, field_size)
            if offset < 0L { return offset }
            if field_align > alignment { alignment = field_align }
        }
        checked_layout_size_align(offset, alignment)
    } else if kind == TYPE_KIND_ARRAY {
        let repeated = checked_size_product(copies, record.field_count)
        if repeated < 0L { repeated } else { type_group_size(compiler, record.field_start, repeated) }
    } else if kind == TYPE_KIND_LIST {
        let counts_size = checked_size_product(copies, 8L)
        let repeated = checked_size_product(copies, record.field_count)
        let element_align = value_type_align(compiler, record.field_start)
        let element_size = type_group_size(compiler, record.field_start, repeated)
        if counts_size == -2L || repeated == -2L || element_size == -2L { -2L }
        else if counts_size < 0L || repeated < 0L || element_align < 0L || element_size < 0L { -1L }
        else {
            let element_offset = checked_layout_size_align(counts_size, element_align)
            if element_offset < 0L { return element_offset }
            let alignment = if element_align > 8L { element_align } else { 8L }
            checked_layout_size_align(checked_layout_size_add(element_offset, element_size), alignment)
        }
    } else {
        let size = value_type_size(compiler, type_id)
        if size < 0L { -1L } else { checked_size_product(size, copies) }
    }
}

fn collection_field_lane_offset(compiler: CompilerTables, struct_type: long, copies: long, wanted_field: long) -> long {
    if type_kind(compiler, struct_type) != TYPE_KIND_STRUCT || copies < 0L { return -1L }
    let record = type_record(compiler, struct_type)
    if wanted_field < 0L || wanted_field >= record.field_count { return -1L }
    var offset = 0L
    for field_offset in 0L..wanted_field {
        let field = compiler.struct_fields[record.field_start + field_offset]
        let field_align = value_type_align(compiler, field.ty)
        let field_size = type_group_size(compiler, field.ty, copies)
        if field_align < 0L || field_size < 0L { return -1L }
        offset = size_align_saturated(offset, field_align)
        offset = size_add_saturated(offset, field_size)
    }
    let target = compiler.struct_fields[record.field_start + wanted_field]
    size_align_saturated(offset, value_type_align(compiler, target.ty))
}

fn collection_element_base_offset(compiler: CompilerTables, type_id: long) -> long {
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_ASCII || kind == TYPE_KIND_BYTES { text_data_offset(compiler, type_id) }
    else if kind == TYPE_KIND_ARRAY { 0L }
    else if kind == TYPE_KIND_LIST {
        let element_type = collection_element_type(compiler, type_id)
        size_align_saturated(8L, value_type_align(compiler, element_type))
    } else { -1L }
}

fn collection_storage_type(ty: long) -> Ascii max 8 {
    if ty == TY_BOOL { return "i8" }
    llvm_type_name(ty)
}

fn emit_collection_text_helper_call(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    operation: long,
    result_name: Ascii max 32,
    result_serial: long,
    left_name: Ascii max 32,
    left_serial: long,
    right_name: Ascii max 32,
    right_serial: long,
) {
    if type_kind(compiler, type_id) != TYPE_KIND_BYTES || !has_type_helper(compiler, type_id, operation) {
        compiler.ir_overflow = true
        return
    }
    ir_write_ascii(compiler, ir, "  ")
    if operation == HELPER_EQUAL {
        ir_push_byte(compiler, ir, 37); ir_write_ascii(compiler, ir, result_name); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, result_serial); ir_write_ascii(compiler, ir, " = ")
    }
    ir_write_ascii(compiler, ir, "call ")
    if operation == HELPER_COPY { ir_write_ascii(compiler, ir, "void ") }
    else if operation == HELPER_EQUAL { ir_write_ascii(compiler, ir, "i1 ") }
    else { compiler.ir_overflow = true; return }
    emit_type_helper_symbol(compiler, ir, type_id, operation)
    ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr %"); ir_write_ascii(compiler, ir, left_name); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, left_serial)
    if operation == HELPER_COPY {
        ir_write_ascii(compiler, ir, ", ptr %"); ir_write_ascii(compiler, ir, right_name); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, right_serial)
    } else if operation == HELPER_EQUAL {
        ir_write_ascii(compiler, ir, ", ptr %"); ir_write_ascii(compiler, ir, right_name); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, right_serial)
    } else { () }
    ir_write_ascii(compiler, ir, ")\n")
}

fn emit_collection_lane_address(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    anchor_kind: long,
    byte_offset: long,
) {
    emit_layout_address(compiler, ir, node, compiler_location(compiler, anchor_kind, 0L, byte_offset))
}

fn emit_collection_dynamic_address(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    label: Ascii max 32,
    base: Ascii max 16,
    type_id: long,
    byte_offset: long,
    element_size: long,
) -> long {
    let serial = next_location_serial(ir)
    ir_write_ascii(compiler, ir, "  %coll.offset."); ir_write_number(compiler, ir, serial)
    ir_write_ascii(compiler, ir, " = mul i64 %coll.index."); ir_write_number(compiler, ir, type_id)
    ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, element_size); ir_push_byte(compiler, ir, 10)
    if byte_offset != 0L {
        ir_write_ascii(compiler, ir, "  %coll.offset.base."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = add i64 %coll.offset."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, byte_offset); ir_push_byte(compiler, ir, 10)
    }
    ir_write_ascii(compiler, ir, "  %coll.ptr."); ir_write_number(compiler, ir, serial)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %"); ir_write_ascii(compiler, ir, base)
    ir_write_ascii(compiler, ir, ", i64 ")
    if byte_offset == 0L { ir_write_ascii(compiler, ir, "%coll.offset."); ir_write_number(compiler, ir, serial) }
    else { ir_write_ascii(compiler, ir, "%coll.offset.base."); ir_write_number(compiler, ir, serial) }
    ir_push_byte(compiler, ir, 10)
    let _ = label
    serial
}

recursive fn emit_collection_copy_element_fields(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies: long,
    path_offset: long,
    row_offset: long,
    collection_type: long,
) {
    if type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_number in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_number]
            let lane_offset = collection_field_lane_offset(compiler, type_id, copies, field_number)
            if lane_offset < 0L { compiler.ir_overflow = true; return }
            emit_collection_copy_element_fields(compiler, ir, field.ty, copies, path_offset + lane_offset,
                row_offset + field.offset, collection_type)
        }
    } else if is_c_runtime_path_type(compiler, type_id) {
        let element_type = collection_element_type(compiler, type_id)
        let byte_size = value_type_size(compiler, element_type)
        let payload_stride = checked_size_product(collection_capacity(compiler, type_id), byte_size)
        if copies < 0L || byte_size < 0L || payload_stride < 0L { compiler.ir_overflow = true; return }
        let source_count = emit_collection_dynamic_address(compiler, ir, "source", "nl.source", collection_type, path_offset, 8L)
        let destination_count = emit_collection_dynamic_address(compiler, ir, "destination", "nl.dest", collection_type, path_offset, 8L)
        let source_payload = emit_collection_dynamic_address(compiler, ir, "source", "nl.source", collection_type,
            path_offset + copies * 8L, payload_stride)
        let destination_payload = emit_collection_dynamic_address(compiler, ir, "destination", "nl.dest", collection_type,
            path_offset + copies * 8L, payload_stride)
        let serial = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.copy.path.count."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = load i64, ptr %coll.ptr."); ir_write_number(compiler, ir, source_count); ir_write_ascii(compiler, ir, ", align 1\n  store i64 %coll.copy.path.count.")
        ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, destination_count); ir_write_ascii(compiler, ir, ", align 1\n")
        ir_write_ascii(compiler, ir, "  %coll.copy.path.bytes."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = mul i64 %coll.copy.path.count."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, byte_size); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.copy.path.payload."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %coll.ptr."); ir_write_number(compiler, ir, destination_payload)
        ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, source_payload)
        ir_write_ascii(compiler, ir, ", i64 %coll.copy.path.bytes."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ")\n")
    } else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || type_kind(compiler, type_id) == TYPE_KIND_LIST {
        compiler.ir_overflow = true
    } else {
        let size = value_type_size(compiler, type_id)
        let storage = collection_storage_type(type_id)
        if size < 0L { compiler.ir_overflow = true; return }
        let source = emit_collection_dynamic_address(compiler, ir, "source", "nl.source", collection_type, path_offset, size)
        let destination = emit_collection_dynamic_address(compiler, ir, "destination", "nl.dest", collection_type, path_offset, size)
        if type_kind(compiler, type_id) == TYPE_KIND_BYTES {
            emit_collection_text_helper_call(compiler, ir, type_id, HELPER_COPY, "", 0L, "coll.ptr", destination, "coll.ptr", source)
        } else if is_sum_type(compiler, type_id) {
            ir_write_ascii(compiler, ir, "  %coll.copy.sum."); ir_write_number(compiler, ir, source)
            ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %coll.ptr."); ir_write_number(compiler, ir, destination)
            ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, source)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, ")\n")
        } else {
            ir_write_ascii(compiler, ir, "  %coll.copy.value."); ir_write_number(compiler, ir, source)
            ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage)
            ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, source); ir_write_ascii(compiler, ir, ", align 1\n  store ")
            ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.copy.value."); ir_write_number(compiler, ir, source)
            ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, destination); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        let _ = row_offset
    }
}

recursive fn emit_collection_equal_element_fields(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies: long,
    path_offset: long,
    collection_type: long,
) {
    if type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_number in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_number]
            let lane_offset = collection_field_lane_offset(compiler, type_id, copies, field_number)
            if lane_offset < 0L { compiler.ir_overflow = true; return }
            emit_collection_equal_element_fields(compiler, ir, field.ty, copies, path_offset + lane_offset, collection_type)
        }
    } else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || type_kind(compiler, type_id) == TYPE_KIND_LIST {
        compiler.ir_overflow = true
    } else {
        let size = value_type_size(compiler, type_id)
        let storage = collection_storage_type(type_id)
        if size < 0L { compiler.ir_overflow = true; return }
        let left = emit_collection_dynamic_address(compiler, ir, "left", "nl.left", collection_type, path_offset, size)
        let right = emit_collection_dynamic_address(compiler, ir, "right", "nl.right", collection_type, path_offset, size)
        let serial = next_location_serial(ir)
        if type_kind(compiler, type_id) == TYPE_KIND_BYTES {
            emit_collection_text_helper_call(compiler, ir, type_id, HELPER_EQUAL, "coll.eq.text", serial, "coll.ptr", left, "coll.ptr", right)
            ir_write_ascii(compiler, ir, "  br i1 %coll.eq.text."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", label %coll.eq.field.ok."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", label %coll.eq.false."); ir_write_number(compiler, ir, collection_type); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "coll.eq.field.ok."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ":\n")
        } else if is_sum_type(compiler, type_id) {
            ir_write_ascii(compiler, ir, "  %coll.eq.sum."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = call i1 "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_EQUAL)
            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr %coll.ptr."); ir_write_number(compiler, ir, left); ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, right); ir_write_ascii(compiler, ir, ")\n  br i1 %coll.eq.sum."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", label %coll.eq.field.ok."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", label %coll.eq.false."); ir_write_number(compiler, ir, collection_type); ir_write_ascii(compiler, ir, "\ncoll.eq.field.ok."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ":\n")
        } else {
            ir_write_ascii(compiler, ir, "  %coll.eq.left."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, left); ir_write_ascii(compiler, ir, ", align 1\n  %coll.eq.right."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, right); ir_write_ascii(compiler, ir, ", align 1\n  %coll.eq.same."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.eq.left."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", %coll.eq.right."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, "\n  br i1 %coll.eq.same."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", label %coll.eq.field.ok."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", label %coll.eq.false."); ir_write_number(compiler, ir, collection_type); ir_write_ascii(compiler, ir, "\ncoll.eq.field.ok."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ":\n")
        }
    }
}

recursive fn emit_collection_gather_element_fields(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies: long,
    path_offset: long,
    row_offset: long,
    collection_type: long,
) {
    if type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_number in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_number]
            let lane_offset = collection_field_lane_offset(compiler, type_id, copies, field_number)
            if lane_offset < 0L { compiler.ir_overflow = true; return }
            emit_collection_gather_element_fields(compiler, ir, field.ty, copies, path_offset + lane_offset,
                row_offset + field.offset, collection_type)
        }
    } else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || type_kind(compiler, type_id) == TYPE_KIND_LIST {
        compiler.ir_overflow = true
    } else {
        let size = value_type_size(compiler, type_id)
        let storage = collection_storage_type(type_id)
        if size < 0L { compiler.ir_overflow = true; return }
        let source = emit_collection_dynamic_address(compiler, ir, "value", "nl.value", collection_type, path_offset, size)
        let serial = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.row.ptr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %coll.print.element."); ir_write_number(compiler, ir, collection_type); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, row_offset); ir_push_byte(compiler, ir, 10)
        if type_kind(compiler, type_id) == TYPE_KIND_BYTES {
            emit_collection_text_helper_call(compiler, ir, type_id, HELPER_COPY, "", 0L, "coll.row.ptr", serial, "coll.ptr", source)
        } else if is_sum_type(compiler, type_id) {
            ir_write_ascii(compiler, ir, "  %coll.row.sum."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %coll.row.ptr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, source); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, ")\n")
        } else {
            ir_write_ascii(compiler, ir, "  %coll.row.value."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, source); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.row.value."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.row.ptr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1\n")
        }
    }
}

fn emit_collection_bulk_memcpy(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, type_id: long, size: long) {
    ir_write_ascii(compiler, ir, "  %coll.copy.bulk."); ir_write_number(compiler, ir, type_id)
    ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %nl.dest, ptr %nl.source, i64 ")
    ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, ")\n")
}

fn emit_collection_copy_helpers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, collection_kind: long) {
    for type_id in 0L..type_count(compiler) {
        if type_kind(compiler, type_id) != collection_kind || !has_type_helper(compiler, type_id, HELPER_COPY) { continue }
        let element = collection_element_type(compiler, type_id)
        let capacity = collection_capacity(compiler, type_id)
        let base_offset = collection_element_base_offset(compiler, type_id)
        let size = value_type_size(compiler, type_id)
        if capacity < 0L || base_offset < 0L || size < 0L { compiler.ir_overflow = true; continue }
        let bulk_copy = size > 64L && !collection_has_nested_elements(compiler, type_id) &&
            !type_contains_bytes(compiler, element, 0L)
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr %nl.dest, ptr %nl.source) {\nentry:\n")
        if collection_kind == TYPE_KIND_ARRAY && bulk_copy {
            emit_collection_bulk_memcpy(compiler, ir, type_id, size)
            ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
            continue
        }
        if collection_kind == TYPE_KIND_LIST {
            ir_write_ascii(compiler, ir, "  %coll.copy.count."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, " = load i64, ptr %nl.source, align 1\n")
            if bulk_copy {
                ir_write_ascii(compiler, ir, "  %coll.copy.full."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, " = icmp eq i64 %coll.copy.count."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, capacity)
                ir_write_ascii(compiler, ir, "\n  br i1 %coll.copy.full."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, ", label %coll.copy.bulk.block."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, ", label %coll.copy.start."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, "\ncoll.copy.bulk.block."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, ":\n")
                emit_collection_bulk_memcpy(compiler, ir, type_id, size)
                ir_write_ascii(compiler, ir, "  ret void\ncoll.copy.start."); ir_write_number(compiler, ir, type_id)
                ir_write_ascii(compiler, ir, ":\n")
            }
            ir_write_ascii(compiler, ir, "  store i64 %coll.copy.count."); ir_write_number(compiler, ir, type_id)
            ir_write_ascii(compiler, ir, ", ptr %nl.dest, align 1\n")
        }
        ir_write_ascii(compiler, ir, "  br label %coll.copy.cond."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, "\ncoll.copy.cond."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ":\n  %coll.index."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = phi i64 [ 0, %")
        if collection_kind == TYPE_KIND_LIST && bulk_copy {
            ir_write_ascii(compiler, ir, "coll.copy.start."); ir_write_number(compiler, ir, type_id)
        } else { ir_write_ascii(compiler, ir, "entry") }
        ir_write_ascii(compiler, ir, " ], [ %coll.next."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", %coll.copy.increment."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " ]\n  %coll.more."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = icmp ult i64 %coll.index."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", ")
        if collection_kind == TYPE_KIND_LIST {
            ir_write_ascii(compiler, ir, "%coll.copy.count."); ir_write_number(compiler, ir, type_id)
        } else { ir_write_number(compiler, ir, capacity) }
        ir_write_ascii(compiler, ir, "\n  br i1 %coll.more."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %coll.copy.body."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %coll.copy.done."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, "\ncoll.copy.body."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ":\n")
        if is_aggregate_type(compiler, element) {
            emit_collection_copy_element_fields(compiler, ir, element, capacity, base_offset, 0L, type_id)
        } else {
            let stride = value_type_size(compiler, element)
            let storage = collection_storage_type(element)
            let source = emit_collection_dynamic_address(compiler, ir, "source", "nl.source", type_id, base_offset, stride)
            let destination = emit_collection_dynamic_address(compiler, ir, "destination", "nl.dest", type_id, base_offset, stride)
            ir_write_ascii(compiler, ir, "  %coll.copy.value."); ir_write_number(compiler, ir, source)
            ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage)
            ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, source)
            ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage)
            ir_write_ascii(compiler, ir, " %coll.copy.value."); ir_write_number(compiler, ir, source)
            ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, destination)
            ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  br label %coll.copy.increment."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, "\ncoll.copy.increment."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ":\n  %coll.next."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = add i64 %coll.index."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", 1\n  br label %coll.copy.cond."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, "\ncoll.copy.done."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ":\n  ret void\n}\n\n")
    }
}

fn emit_collection_equal_helpers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, collection_kind: long) {
    for type_id in 0L..type_count(compiler) {
        if type_kind(compiler, type_id) != collection_kind || !has_type_helper(compiler, type_id, HELPER_EQUAL) { continue }
        let element = collection_element_type(compiler, type_id)
        let capacity = collection_capacity(compiler, type_id)
        let base_offset = collection_element_base_offset(compiler, type_id)
        if capacity < 0L || base_offset < 0L { compiler.ir_overflow = true; continue }
        ir_write_ascii(compiler, ir, "define internal i1 "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_EQUAL)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr %nl.left, ptr %nl.right) {\nentry:\n")
        if collection_kind == TYPE_KIND_LIST {
            ir_write_ascii(compiler, ir, "  %coll.eq.left.count."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i64, ptr %nl.left, align 1\n  %coll.eq.right.count."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i64, ptr %nl.right, align 1\n  %coll.eq.same.count."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = icmp eq i64 %coll.eq.left.count."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", %coll.eq.right.count."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\n  br i1 %coll.eq.same.count."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %coll.eq.loop."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %coll.eq.false."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\n")
        } else { ir_write_ascii(compiler, ir, "  br label %coll.eq.loop."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\n") }
        ir_write_ascii(compiler, ir, "coll.eq.loop."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  %coll.index."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = phi i64 [ 0, %entry ], [ %coll.next."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", %coll.eq.increment."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " ]\n  %coll.more."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = icmp ult i64 %coll.index."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", ")
        if collection_kind == TYPE_KIND_LIST { ir_write_ascii(compiler, ir, "%coll.eq.left.count."); ir_write_number(compiler, ir, type_id) }
        else { ir_write_number(compiler, ir, capacity) }
        ir_write_ascii(compiler, ir, "\n  br i1 %coll.more."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %coll.eq.body."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %coll.eq.true."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\ncoll.eq.body."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n")
        if is_aggregate_type(compiler, element) { emit_collection_equal_element_fields(compiler, ir, element, capacity, base_offset, type_id) }
        else {
            let stride = value_type_size(compiler, element)
            let storage = collection_storage_type(element)
            let left = emit_collection_dynamic_address(compiler, ir, "left", "nl.left", type_id, base_offset, stride)
            let right = emit_collection_dynamic_address(compiler, ir, "right", "nl.right", type_id, base_offset, stride)
            let serial = next_location_serial(ir)
            ir_write_ascii(compiler, ir, "  %coll.eq.left."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, left); ir_write_ascii(compiler, ir, ", align 1\n  %coll.eq.right."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, right); ir_write_ascii(compiler, ir, ", align 1\n  %coll.eq.same."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.eq.left."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", %coll.eq.right."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, "\n  br i1 %coll.eq.same."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", label %coll.eq.field.ok."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", label %coll.eq.false."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\ncoll.eq.field.ok."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ":\n")
        }
        ir_write_ascii(compiler, ir, "  br label %coll.eq.increment."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\ncoll.eq.increment."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  %coll.next."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = add i64 %coll.index."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", 1\n  br label %coll.eq.loop."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\ncoll.eq.true."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret i1 true\ncoll.eq.false."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret i1 false\n}\n\n")
    }
}

fn emit_collection_print_globals(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    var needed = false
    for type_id in 0L..type_count(compiler) {
        let kind = type_kind(compiler, type_id)
        if (kind == TYPE_KIND_ARRAY || kind == TYPE_KIND_LIST) && has_type_helper(compiler, type_id, HELPER_PRINT) { needed = true }
    }
    if !needed { return }
    ir_write_global_string(compiler, ir, "@.nl.collection.open = private unnamed_addr constant [", b"[")
    ir_write_global_string(compiler, ir, "@.nl.collection.close = private unnamed_addr constant [", b"]")
    ir_write_global_string(compiler, ir, "@.nl.collection.separator = private unnamed_addr constant [", b", ")
}

fn emit_collection_print_text(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, name: Ascii max 32, length: long) {
    ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_ascii", "nlc_print_ascii"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr getelementptr inbounds ([")
    ir_write_number(compiler, ir, length + 1L)
    ir_write_ascii(compiler, ir, " x i8], ptr @.nl.collection.")
    ir_write_ascii(compiler, ir, name)
    ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
    ir_write_number(compiler, ir, length)
    ir_write_ascii(compiler, ir, ")\n")
}

fn emit_collection_scalar_print(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, ty: long, value_name: Ascii max 64) {
    if ty == TY_BOOL {
        ir_write_ascii(compiler, ir, "  %coll.print.bool."); ir_write_ascii(compiler, ir, value_name); ir_write_ascii(compiler, ir, " = trunc i8 %coll.print.value."); ir_write_ascii(compiler, ir, value_name); ir_write_ascii(compiler, ir, " to i1\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_bool_raw", "nlc_print_bool_raw"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i1 zeroext %coll.print.bool."); ir_write_ascii(compiler, ir, value_name); ir_write_ascii(compiler, ir, ")\n")
    } else {
        ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, if ty == TY_LONG { "nl_print_long_raw" } else { "nl_print_int_raw" }, if ty == TY_LONG { "nlc_print_long_raw" } else { "nlc_print_int_raw" }); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %coll.print.value."); ir_write_ascii(compiler, ir, value_name); ir_write_ascii(compiler, ir, ")\n")
    }
}

fn emit_collection_print_helpers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, collection_kind: long) {
    for type_id in 0L..type_count(compiler) {
        if type_kind(compiler, type_id) != collection_kind || !has_type_helper(compiler, type_id, HELPER_PRINT) { continue }
        let element = collection_element_type(compiler, type_id)
        let capacity = collection_capacity(compiler, type_id)
        let stride = value_type_size(compiler, element)
        let base_offset = collection_element_base_offset(compiler, type_id)
        if capacity < 0L || base_offset < 0L || (!is_aggregate_type(compiler, element) && stride < 0L) { compiler.ir_overflow = true; continue }
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_PRINT)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); emit_location_argument(compiler, ir, compiler_location(compiler, 8L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        if collection_kind == TYPE_KIND_LIST {
            ir_write_ascii(compiler, ir, "  %coll.print.count."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i64, ptr %nl.value, align 1\n")
        }
        if type_kind(compiler, element) == TYPE_KIND_STRUCT || is_sum_type(compiler, element) {
            let element_size = value_type_size(compiler, element)
            let element_align = value_type_align(compiler, element)
            if element_size < 0L || element_align < 0L { compiler.ir_overflow = true; continue }
            ir_write_ascii(compiler, ir, "  %coll.print.element."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, element_size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, element_align); ir_push_byte(compiler, ir, 10)
        }
        emit_collection_print_text(compiler, ir, "open", 1L)
        ir_write_ascii(compiler, ir, "  br label %coll.print.cond."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\ncoll.print.cond."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  %coll.index."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = phi i64 [ 0, %entry ], [ %coll.next."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", %coll.print.increment."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " ]\n  %coll.more."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = icmp ult i64 %coll.index."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", ")
        if collection_kind == TYPE_KIND_LIST { ir_write_ascii(compiler, ir, "%coll.print.count."); ir_write_number(compiler, ir, type_id) }
        else { ir_write_number(compiler, ir, capacity) }
        ir_write_ascii(compiler, ir, "\n  br i1 %coll.more."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %coll.print.body."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %coll.print.done."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\ncoll.print.body."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  %coll.print.first."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = icmp eq i64 %coll.index."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", 0\n  br i1 %coll.print.first."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %coll.print.item."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %coll.print.separator."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\ncoll.print.separator."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n")
        emit_collection_print_text(compiler, ir, "separator", 2L)
        ir_write_ascii(compiler, ir, "  br label %coll.print.item."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\ncoll.print.item."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n")
        if is_aggregate_type(compiler, element) {
            emit_collection_gather_element_fields(compiler, ir, element, capacity, base_offset, 0L, type_id)
            ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_symbol(compiler, ir, element, HELPER_PRINT); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr %coll.print.element."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ")\n")
        } else {
            let address = emit_collection_dynamic_address(compiler, ir, "value", "nl.value", type_id, base_offset, stride)
            ir_write_ascii(compiler, ir, "  %coll.print.value."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, collection_storage_type(element)); ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n")
            let value_name: Ascii max 64 = str(address)
            emit_collection_scalar_print(compiler, ir, element, value_name)
        }
        ir_write_ascii(compiler, ir, "  br label %coll.print.increment."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\ncoll.print.increment."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  %coll.next."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = add i64 %coll.index."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", 1\n  br label %coll.print.cond."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\ncoll.print.done."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n")
        emit_collection_print_text(compiler, ir, "close", 1L)
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}

fn collection_value_location(tables: ParseTables, compiler: CompilerTables, node: long) -> StorageLocation {
    if tables.nodes[node].kind == NodeKind.Name {
        let binding = compiler.facts[node].binding
        if binding < 0L && (compiler.facts[node].flags & (FACT_CONSTANT_TEXT | FACT_CONSTANT_ARRAY)) != 0L { return compiler_location(compiler, 0L, node, 0L) }
        if binding >= 0L && compiler.bindings[binding].parameter {
            compiler_location(compiler, 3L, binding, 0L)
        } else { compiler_location(compiler, 1L, binding, 0L) }
    } else if tables.nodes[node].kind == NodeKind.Field {
        compiler_location(compiler, 2L, node, 0L)
    } else { compiler_location(compiler, 0L, node, 0L) }
}

fn emit_collection_index_address(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let receiver = compiler.child_first[node]
    let index = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
    if receiver < 0L || index < 0L { compiler.ir_overflow = true; return }
    let collection_ty = compiler.facts[receiver].ty
    let kind = type_kind(compiler, collection_ty)
    let is_text_bytes = kind == TYPE_KIND_BYTES || kind == TYPE_KIND_ASCII
    let element = if is_text_bytes { TY_BYTE } else { collection_element_type(compiler, collection_ty) }
    let capacity = if is_text_bytes { text_max_bytes(compiler, collection_ty) } else { collection_capacity(compiler, collection_ty) }
    let stride = if is_text_bytes { 1L } else { value_type_size(compiler, element) }
    let base_offset = if is_text_bytes { text_data_offset(compiler, collection_ty) } else { collection_element_base_offset(compiler, collection_ty) }
    if capacity < 0L || stride < 0L || base_offset < 0L { compiler.ir_overflow = true; return }
    var location = collection_value_location(tables, compiler, receiver)
    if tables.nodes[receiver].kind == NodeKind.Field {
        let address_id = emit_late_place_address(tables, compiler, ir, receiver)
        location = compiler_location(compiler, 2L, address_id, 0L)
    }
    let pointer_serial = emit_location_pointer_materialization(compiler, ir, location)
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].anchor, compiler)
    ir_write_ascii(compiler, ir, "  %coll.index.negative."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp slt i64 "); ir_write_value_ref(compiler, ir, index); ir_write_ascii(compiler, ir, ", 0\n")
    if is_text_bytes {
        ir_write_ascii(compiler, ir, "  %text.index.length."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial)
        ir_write_ascii(compiler, ir, ", align 1\n  %coll.index.high."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = icmp sge i64 "); ir_write_value_ref(compiler, ir, index)
        ir_write_ascii(compiler, ir, ", %text.index.length."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    } else if kind == TYPE_KIND_LIST {
        ir_write_ascii(compiler, ir, "  %coll.index.count.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 0\n  %coll.index.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr %coll.index.count.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  %coll.index.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sge i64 "); ir_write_value_ref(compiler, ir, index); ir_write_ascii(compiler, ir, ", %coll.index.count."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    } else {
        ir_write_ascii(compiler, ir, "  %coll.index.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sge i64 "); ir_write_value_ref(compiler, ir, index); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, capacity); ir_write_ascii(compiler, ir, "\n")
    }
    ir_write_ascii(compiler, ir, "  %coll.index.invalid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i1 %coll.index.negative."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %coll.index.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  br i1 %coll.index.invalid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.index.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.index.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.index.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 16, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\ncoll.index.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if is_text_bytes {
        ir_write_ascii(compiler, ir, "  %coll.index.bytes."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = add i64 "); ir_write_value_ref(compiler, ir, index); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset)
        ir_write_ascii(compiler, ir, "\n  %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, location, pointer_serial)
        ir_write_ascii(compiler, ir, ", i64 %coll.index.bytes."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    } else if is_aggregate_type(compiler, element) { () }
    else {
        ir_write_ascii(compiler, ir, "  %coll.index.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = mul i64 "); ir_write_value_ref(compiler, ir, index); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_write_ascii(compiler, ir, "\n  %coll.index.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.index.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.index.offset."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    }
}

recursive fn emit_collection_store_element_fields(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies: long,
    lane: long,
    lane_node: long,
    destination_offset: long,
    source_offset: long,
    destination_location: StorageLocation,
    source_location: StorageLocation,
    destination_pointer: long,
    source_pointer: long,
) {
    if type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_number in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_number]
            let lane_offset = collection_field_lane_offset(compiler, type_id, copies, field_number)
            if lane_offset < 0L { compiler.ir_overflow = true; return }
            emit_collection_store_element_fields(compiler, ir, field.ty, copies, lane,
                lane_node, destination_offset + lane_offset, source_offset + field.offset,
                destination_location, source_location, destination_pointer, source_pointer)
        }
    } else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || type_kind(compiler, type_id) == TYPE_KIND_LIST {
        compiler.ir_overflow = true
    } else {
        let size = value_type_size(compiler, type_id)
        let storage = collection_storage_type(type_id)
        if size < 0L { compiler.ir_overflow = true; return }
        let serial = next_location_serial(ir)
        var dynamic_offset = -1L
        if lane_node != -1L {
            let lane_bytes = next_location_serial(ir)
            ir_write_ascii(compiler, ir, "  %coll.literal.lane.bytes."); ir_write_number(compiler, ir, lane_bytes); ir_write_ascii(compiler, ir, " = mul i64 "); emit_collection_lane_index(compiler, ir, lane_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, size); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "  %coll.literal.dynamic.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, destination_offset); ir_write_ascii(compiler, ir, ", %coll.literal.lane.bytes."); ir_write_number(compiler, ir, lane_bytes); ir_push_byte(compiler, ir, 10)
            dynamic_offset = serial
        }
        ir_write_ascii(compiler, ir, "  %coll.literal.dest."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, destination_location, destination_pointer)
        ir_write_ascii(compiler, ir, ", i64 ")
        if dynamic_offset >= 0L { ir_write_ascii(compiler, ir, "%coll.literal.dynamic.offset."); ir_write_number(compiler, ir, dynamic_offset) }
        else { ir_write_number(compiler, ir, destination_offset + lane * size) }
        ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.literal.src."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, source_location, source_pointer)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, source_offset); ir_push_byte(compiler, ir, 10)
        if type_kind(compiler, type_id) == TYPE_KIND_BYTES {
            emit_collection_text_helper_call(compiler, ir, type_id, HELPER_COPY, "", 0L, "coll.literal.dest", serial, "coll.literal.src", serial)
        } else if is_sum_type(compiler, type_id) {
            ir_write_ascii(compiler, ir, "  %coll.literal.sum."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %coll.literal.dest."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.literal.src."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, ")\n")
        } else {
            ir_write_ascii(compiler, ir, "  %coll.literal.value."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.literal.src."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.literal.value."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.literal.dest."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        }
    }
}

fn emit_collection_lane_value(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, kind: long, node: long) {
    if kind == 1L { ir_write_ascii(compiler, ir, "%coll.push.count."); ir_write_number(compiler, ir, node) }
    else if kind == 2L { ir_write_value_ref(compiler, ir, node) }
    else if kind == 3L { ir_write_ascii(compiler, ir, "%coll.insert.from."); ir_write_number(compiler, ir, node) }
    else if kind == 4L { ir_write_ascii(compiler, ir, "%coll.insert.cursor."); ir_write_number(compiler, ir, node) }
    else if kind == 5L { ir_write_ascii(compiler, ir, "%coll.remove.source.index."); ir_write_number(compiler, ir, node) }
    else if kind == 6L { ir_write_ascii(compiler, ir, "%coll.remove.cursor."); ir_write_number(compiler, ir, node) }
    else if kind == 7L { ir_write_ascii(compiler, ir, "%for.each.current."); ir_write_number(compiler, ir, node) }
    else if kind == 8L { ir_write_ascii(compiler, ir, "%coll.pop.last."); ir_write_number(compiler, ir, node) }
    else { compiler.ir_overflow = true }
}

fn emit_collection_lane_index(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, lane_node: long) {
    if lane_node >= 0L { ir_write_value_ref(compiler, ir, lane_node) }
    else { ir_write_ascii(compiler, ir, "%for.each.current."); ir_write_number(compiler, ir, -2L - lane_node) }
}

recursive fn emit_collection_store_dynamic_fields(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies: long,
    path_offset: long,
    row_offset: long,
    destination_location: StorageLocation,
    destination_pointer: long,
    source_location: StorageLocation,
    source_pointer: long,
    lane_kind: long,
    lane_node: long,
) {
    if type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_number in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_number]
            let lane_offset = collection_field_lane_offset(compiler, type_id, copies, field_number)
            if lane_offset < 0L { compiler.ir_overflow = true; return }
            emit_collection_store_dynamic_fields(compiler, ir, field.ty, copies, path_offset + lane_offset,
                row_offset + field.offset, destination_location, destination_pointer, source_location,
                source_pointer, lane_kind, lane_node)
        }
    } else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || type_kind(compiler, type_id) == TYPE_KIND_LIST {
        compiler.ir_overflow = true
    } else {
        let size = value_type_size(compiler, type_id)
        let storage = collection_storage_type(type_id)
        let serial = next_location_serial(ir)
        if size < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %coll.dynamic.lane.bytes."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = mul i64 "); emit_collection_lane_value(compiler, ir, lane_kind, lane_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, size); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.dynamic.lane.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, path_offset); ir_write_ascii(compiler, ir, ", %coll.dynamic.lane.bytes."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.dynamic.lane.dest."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination_location, destination_pointer); ir_write_ascii(compiler, ir, ", i64 %coll.dynamic.lane.offset."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.dynamic.lane.src."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, row_offset); ir_push_byte(compiler, ir, 10)
        if type_kind(compiler, type_id) == TYPE_KIND_BYTES {
            emit_collection_text_helper_call(compiler, ir, type_id, HELPER_COPY, "", 0L, "coll.dynamic.lane.dest", serial, "coll.dynamic.lane.src", serial)
        } else if is_sum_type(compiler, type_id) {
            ir_write_ascii(compiler, ir, "  %coll.dynamic.lane.sum."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %coll.dynamic.lane.dest."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.dynamic.lane.src."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, ")\n")
        } else {
            ir_write_ascii(compiler, ir, "  %coll.dynamic.lane.value."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.dynamic.lane.src."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.dynamic.lane.value."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.dynamic.lane.dest."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        }
    }
}

recursive fn emit_collection_move_dynamic_fields(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies: long,
    path_offset: long,
    location: StorageLocation,
    pointer_serial: long,
    source_lane_kind: long,
    source_lane_node: long,
    destination_lane_kind: long,
    destination_lane_node: long,
) {
    if type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_number in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_number]
            let lane_offset = collection_field_lane_offset(compiler, type_id, copies, field_number)
            if lane_offset < 0L { compiler.ir_overflow = true; return }
            emit_collection_move_dynamic_fields(compiler, ir, field.ty, copies, path_offset + lane_offset,
                location, pointer_serial, source_lane_kind, source_lane_node, destination_lane_kind, destination_lane_node)
        }
    } else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || type_kind(compiler, type_id) == TYPE_KIND_LIST {
        compiler.ir_overflow = true
    } else {
        let size = value_type_size(compiler, type_id)
        let storage = collection_storage_type(type_id)
        let serial = next_location_serial(ir)
        if size < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %coll.move.src.bytes."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = mul i64 "); emit_collection_lane_value(compiler, ir, source_lane_kind, source_lane_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, size); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.move.src.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, path_offset); ir_write_ascii(compiler, ir, ", %coll.move.src.bytes."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.move.dst.bytes."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = mul i64 "); emit_collection_lane_value(compiler, ir, destination_lane_kind, destination_lane_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, size); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.move.dst.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, path_offset); ir_write_ascii(compiler, ir, ", %coll.move.dst.bytes."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.move.src.ptr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.move.src.offset."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.move.dst.ptr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.move.dst.offset."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
        if type_kind(compiler, type_id) == TYPE_KIND_BYTES {
            emit_collection_text_helper_call(compiler, ir, type_id, HELPER_COPY, "", 0L, "coll.move.dst.ptr", serial, "coll.move.src.ptr", serial)
        } else if is_sum_type(compiler, type_id) {
            ir_write_ascii(compiler, ir, "  %coll.move.sum."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %coll.move.dst.ptr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.move.src.ptr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, ")\n")
        } else {
            ir_write_ascii(compiler, ir, "  %coll.move.value."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.move.src.ptr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.move.value."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.move.dst.ptr."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        }
    }
}

recursive fn emit_collection_gather_dynamic_fields(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies: long,
    path_offset: long,
    row_offset: long,
    source_location: StorageLocation,
    source_pointer: long,
    source_lane_kind: long,
    source_lane_node: long,
    destination_location: StorageLocation,
    destination_pointer: long,
) {
    if type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_number in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_number]
            let lane_offset = collection_field_lane_offset(compiler, type_id, copies, field_number)
            if lane_offset < 0L { compiler.ir_overflow = true; return }
            emit_collection_gather_dynamic_fields(compiler, ir, field.ty, copies, path_offset + lane_offset,
                row_offset + field.offset, source_location, source_pointer, source_lane_kind, source_lane_node,
                destination_location, destination_pointer)
        }
    } else if is_c_runtime_path_type(compiler, type_id) {
        let element_type = collection_element_type(compiler, type_id)
        let byte_size = value_type_size(compiler, element_type)
        let payload_stride = checked_size_product(collection_capacity(compiler, type_id), byte_size)
        let destination_data_offset = collection_element_base_offset(compiler, type_id)
        if copies < 0L || byte_size < 0L || payload_stride < 0L || destination_data_offset < 0L {
            compiler.ir_overflow = true
            return
        }
        let serial = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.gather.path.count.index."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = mul i64 "); emit_collection_lane_value(compiler, ir, source_lane_kind, source_lane_node)
        ir_write_ascii(compiler, ir, ", 8\n  %coll.gather.path.count.offset."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, path_offset)
        ir_write_ascii(compiler, ir, ", %coll.gather.path.count.index."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, "\n  %coll.gather.path.count.src."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer)
        ir_write_ascii(compiler, ir, ", i64 %coll.gather.path.count.offset."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, "\n  %coll.gather.path.count."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = load i64, ptr %coll.gather.path.count.src."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1\n")
        ir_write_ascii(compiler, ir, "  %coll.gather.path.count.dst."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination_location, destination_pointer)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, row_offset); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  store i64 %coll.gather.path.count."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, ", ptr %coll.gather.path.count.dst."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1\n")
        ir_write_ascii(compiler, ir, "  %coll.gather.path.payload.index."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = mul i64 "); emit_collection_lane_value(compiler, ir, source_lane_kind, source_lane_node)
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, payload_stride)
        ir_write_ascii(compiler, ir, "\n  %coll.gather.path.payload.offset."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, path_offset + copies * 8L)
        ir_write_ascii(compiler, ir, ", %coll.gather.path.payload.index."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, "\n  %coll.gather.path.payload.src."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer)
        ir_write_ascii(compiler, ir, ", i64 %coll.gather.path.payload.offset."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, "\n  %coll.gather.path.payload.dst."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination_location, destination_pointer)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, row_offset + destination_data_offset); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.gather.path.bytes."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = mul i64 %coll.gather.path.count."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, byte_size); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.gather.path.copy."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %coll.gather.path.payload.dst."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, ", ptr %coll.gather.path.payload.src."); ir_write_number(compiler, ir, serial)
        ir_write_ascii(compiler, ir, ", i64 %coll.gather.path.bytes."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ")\n")
    } else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || type_kind(compiler, type_id) == TYPE_KIND_LIST {
        compiler.ir_overflow = true
    } else {
        let size = value_type_size(compiler, type_id)
        let storage = collection_storage_type(type_id)
        let serial = next_location_serial(ir)
        if size < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %coll.gather.bytes."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = mul i64 "); emit_collection_lane_value(compiler, ir, source_lane_kind, source_lane_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, size); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.gather.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, path_offset); ir_write_ascii(compiler, ir, ", %coll.gather.bytes."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.gather.src."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer); ir_write_ascii(compiler, ir, ", i64 %coll.gather.offset."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.gather.dst."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination_location, destination_pointer); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, row_offset); ir_push_byte(compiler, ir, 10)
        if type_kind(compiler, type_id) == TYPE_KIND_BYTES {
            emit_collection_text_helper_call(compiler, ir, type_id, HELPER_COPY, "", 0L, "coll.gather.dst", serial, "coll.gather.src", serial)
        } else if is_sum_type(compiler, type_id) {
            ir_write_ascii(compiler, ir, "  %coll.gather.sum."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr %coll.gather.dst."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.gather.src."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, ")\n")
        } else {
            ir_write_ascii(compiler, ir, "  %coll.gather.value."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.gather.src."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.gather.value."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %coll.gather.dst."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        }
    }
}

fn emit_collection_gather_view_value(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let binding = compiler.facts[node].binding
    if !binding_is_view(compiler, binding) { compiler.ir_overflow = true; return }
    let loop_node = compiler.bindings[binding].node
    let collection = compiler.child_first[loop_node]
    let collection_type = compiler.facts[collection].ty
    let element_type = collection_element_type(compiler, collection_type)
    let capacity = collection_capacity(compiler, collection_type)
    let base_offset = collection_element_base_offset(compiler, collection_type)
    let source = if tables.nodes[collection].kind == NodeKind.Field {
        let address_id = emit_late_place_address(tables, compiler, ir, collection)
        compiler_location(compiler, 2L, address_id, 0L)
    } else { collection_value_location(tables, compiler, collection) }
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    if (!is_aggregate_type(compiler, element_type)) || capacity < 0L || base_offset < 0L {
        compiler.ir_overflow = true
        return
    }
    emit_collection_gather_dynamic_fields(compiler, ir, element_type, capacity, base_offset, 0L,
        source, source_pointer, 7L, loop_node, destination, destination_pointer)
}

fn emit_collection_gather_index_value(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let collection = compiler.child_first[node]
    let index_node = if collection >= 0L { compiler.child_next[collection] } else { -1L }
    if collection < 0L || index_node < 0L { compiler.ir_overflow = true; return }
    let collection_type = compiler.facts[collection].ty
    let element_type = collection_element_type(compiler, collection_type)
    let capacity = collection_capacity(compiler, collection_type)
    let base_offset = collection_element_base_offset(compiler, collection_type)
    if (!is_aggregate_type(compiler, element_type)) || capacity < 0L || base_offset < 0L {
        compiler.ir_overflow = true
        return
    }
    let source = if tables.nodes[collection].kind == NodeKind.Field {
        let address_id = emit_late_place_address(tables, compiler, ir, collection)
        compiler_location(compiler, 2L, address_id, 0L)
    } else { collection_value_location(tables, compiler, collection) }
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    emit_collection_gather_dynamic_fields(compiler, ir, element_type, capacity, base_offset, 0L,
        source, source_pointer, 2L, index_node, destination, destination_pointer)
}

fn emit_collection_literal_element(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    collection_node: long,
    type_id: long,
    lane: long,
    value_node: long,
) {
    let element = collection_element_type(compiler, type_id)
    if is_aggregate_type(compiler, element) {
        let copies = collection_capacity(compiler, type_id)
        let destination = aggregate_destination_location(compiler, 0L, collection_node)
        let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
        let source_kind = if tables.nodes[value_node].kind == NodeKind.Name && compiler.facts[value_node].binding >= 0L {
            if compiler.bindings[compiler.facts[value_node].binding].parameter { 2L } else { 1L }
        } else if tables.nodes[value_node].kind == NodeKind.Field { 3L } else { 0L }
        let source_id = if source_kind == 1L || source_kind == 2L { compiler.facts[value_node].binding } else { value_node }
        let source = aggregate_source_location(compiler, source_kind, source_id)
        let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
        let path_offset = collection_element_base_offset(compiler, type_id)
        if copies < 0L || path_offset < 0L { compiler.ir_overflow = true; return }
        emit_collection_store_element_fields(compiler, ir, element, copies, lane, -1L, path_offset, 0L, destination, source, destination_pointer, source_pointer)
        return
    }
    let stride = value_type_size(compiler, element)
    let base_offset = collection_element_base_offset(compiler, type_id)
    if stride < 0L || base_offset < 0L { compiler.ir_overflow = true; return }
    let location = aggregate_destination_location(compiler, 0L, collection_node)
    let serial = emit_location_pointer_materialization(compiler, ir, location)
    let address = MAX_TREE_NODES * 66L + collection_node
    ir_write_ascii(compiler, ir, "  %coll.literal.addr."); ir_write_number(compiler, ir, collection_node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, lane); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, serial); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, base_offset + lane * stride); ir_push_byte(compiler, ir, 10)
    let storage_type = collection_storage_type(element)
    if element == TY_BOOL {
        ir_write_ascii(compiler, ir, "  %coll.literal.bool."); ir_write_number(compiler, ir, collection_node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, lane); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, " to i8\n  store i8 %coll.literal.bool."); ir_write_number(compiler, ir, collection_node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, lane); ir_write_ascii(compiler, ir, ", ptr %coll.literal.addr."); ir_write_number(compiler, ir, collection_node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, lane); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
    } else {
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(element)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, ", ptr %coll.literal.addr."); ir_write_number(compiler, ir, collection_node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, lane); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
    }
    let _ = address
}

fn emit_collection_fill_array(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    type_id: long,
    value_node: long,
) {
    if type_kind(compiler, type_id) != TYPE_KIND_ARRAY { compiler.ir_overflow = true; return }
    let element = collection_element_type(compiler, type_id)
    let capacity = collection_capacity(compiler, type_id)
    let base_offset = collection_element_base_offset(compiler, type_id)
    if capacity < 0L || base_offset < 0L { compiler.ir_overflow = true; return }
    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    if is_aggregate_type(compiler, element) {
        let source_kind = if tables.nodes[value_node].kind == NodeKind.Name && compiler.facts[value_node].binding >= 0L {
            if compiler.bindings[compiler.facts[value_node].binding].parameter { 2L } else { 1L }
        } else if tables.nodes[value_node].kind == NodeKind.Field { 3L } else { 0L }
        let source_id = if source_kind == 1L || source_kind == 2L { compiler.facts[value_node].binding } else { value_node }
        let source = aggregate_source_location(compiler, source_kind, source_id)
        let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
        for lane in 0L..capacity {
            emit_collection_store_element_fields(compiler, ir, element, capacity, lane, -1L, base_offset, 0L, destination, source, destination_pointer, source_pointer)
        }
        return
    }
    let stride = value_type_size(compiler, element)
    if stride < 0L { compiler.ir_overflow = true; return }
    if element == TY_BOOL {
        ir_write_ascii(compiler, ir, "  %coll.fill.bool."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, " to i8\n")
    }
    ir_write_ascii(compiler, ir, "  store i64 0, ptr %coll.fill.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n  br label %coll.fill.cond."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "coll.fill.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.fill.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr %coll.fill.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n  %coll.fill.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ult i64 %coll.fill.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, capacity); ir_write_ascii(compiler, ir, "\n  br i1 %coll.fill.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.fill.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.fill.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.fill.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.fill.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = mul i64 %coll.fill.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_write_ascii(compiler, ir, "\n  %coll.fill.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.fill.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %coll.fill.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer); ir_write_ascii(compiler, ir, ", i64 %coll.fill.offset."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    if element == TY_BOOL { ir_write_ascii(compiler, ir, "  store i8 %coll.fill.bool."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %coll.fill.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10) }
    else { ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(element)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, ", ptr %coll.fill.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10) }
    ir_write_ascii(compiler, ir, "  %coll.fill.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.fill.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  store i64 %coll.fill.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %coll.fill.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n  br label %coll.fill.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.fill.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
}

fn emit_collection_default_array_aggregate(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    type_id: long,
) {
    let element = collection_element_type(compiler, type_id)
    let capacity = collection_capacity(compiler, type_id)
    let base_offset = collection_element_base_offset(compiler, type_id)
    if type_kind(compiler, type_id) != TYPE_KIND_ARRAY || type_kind(compiler, element) != TYPE_KIND_STRUCT ||
        capacity < 0L || base_offset < 0L || !has_type_helper(compiler, element, HELPER_FILL) {
        compiler.ir_overflow = true
        return
    }
    if capacity == 0L { return }
    let element_type = type_record(compiler, element)
    let value_node = next_location_serial(ir)
    ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, value_node)
    ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, element_type.size)
    ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, element_type.align); ir_push_byte(compiler, ir, 10)
    let source = compiler_location(compiler, 2L, value_node, 0L)
    let destination = aggregate_destination_location(compiler, 0L, node)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    let top_node = next_location_serial(ir)
    emit_current_top_load(compiler, ir, top_node)
    ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_symbol(compiler, ir, element, HELPER_FILL)
    ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 "); emit_current_top_reference(compiler, ir, top_node)
    ir_write_ascii(compiler, ir, ", ")
    emit_prepare_location_descriptor(compiler, ir, source, true, top_node)
    emit_location_descriptor_argument(compiler, ir, source, true, top_node)
    ir_write_ascii(compiler, ir, ", ptr null, i64 0)\n")
    for lane in 0L..capacity {
        emit_collection_store_element_fields(compiler, ir, element, capacity, lane, -1L,
            base_offset, 0L, destination, source, destination_pointer, -1L)
    }
}

fn emit_collection_zero_storage(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long, type_id: long, live_count: long) {
    let element = collection_element_type(compiler, type_id)
    if type_kind(compiler, type_id) == TYPE_KIND_LIST {
        let location = aggregate_destination_location(compiler, 0L, node)
        let serial = emit_location_pointer_materialization(compiler, ir, location)
        ir_write_ascii(compiler, ir, "  %coll.zero.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, serial); ir_write_ascii(compiler, ir, ", i64 0\n  store i64 "); ir_write_number(compiler, ir, live_count); ir_write_ascii(compiler, ir, ", ptr %coll.zero.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        return
    }
    if is_aggregate_type(compiler, element) {
        emit_collection_default_array_aggregate(compiler, ir, node, type_id)
        return
    }
    let stride = value_type_size(compiler, element)
    let base_offset = collection_element_base_offset(compiler, type_id)
    if stride < 0L || base_offset < 0L { compiler.ir_overflow = true; return }
    let location = aggregate_destination_location(compiler, 0L, node)
    let serial = emit_location_pointer_materialization(compiler, ir, location)
    let storage_type = collection_storage_type(element)
    for lane in live_count..collection_capacity(compiler, type_id) {
        ir_write_ascii(compiler, ir, "  %coll.zero.addr."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, lane); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, serial); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, base_offset + lane * stride); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, " 0, ptr %coll.zero.addr."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, lane); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
    }
}

fn emit_collection_method_index_address(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    location: StorageLocation,
    pointer_serial: long,
    index_node: long,
    base_offset: long,
    stride: long,
) {
    let serial = next_location_serial(ir)
    ir_write_ascii(compiler, ir, "  %coll.method.bytes."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = mul i64 "); ir_write_value_ref(compiler, ir, index_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %coll.method.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %coll.method.bytes."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.method.offset."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
}

fn emit_collection_capacity_result_tag(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    tag: long,
) {
    emit_sum_tag_store(compiler, ir, node, tag)
    if tag == 1L {
        let error = sum_payload_record(compiler, compiler.facts[node].ty, 1L, 0L)
        let address = enum_temporary_address(node, MAX_TREE_NODES * 3L + 1L)
        emit_layout_address(compiler, ir, address, storage_location_with_offset(aggregate_destination_location(compiler, 0L, node), error.offset))
        ir_write_ascii(compiler, ir, "  %coll.full.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i32 0, 0\n  store i32 %coll.full.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n")
    }
}

fn emit_collection_method(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    method: long,
) {
    let receiver = compiler.child_first[node]
    let argument = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
    let value_argument = if method == COLLECTION_METHOD_INSERT && argument >= 0L { compiler.child_next[argument] } else { argument }
    let type_id = compiler.facts[receiver].ty
    let kind = type_kind(compiler, type_id)
    let element = collection_element_type(compiler, type_id)
    let capacity = collection_capacity(compiler, type_id)
    let stride = value_type_size(compiler, element)
    let base_offset = collection_element_base_offset(compiler, type_id)
    if base_offset < 0L || (method != COLLECTION_METHOD_LEN && method != COLLECTION_METHOD_COUNT && stride < 0L) {
        compiler.ir_overflow = true
        return
    }
    var location = collection_value_location(tables, compiler, receiver)
    if tables.nodes[receiver].kind == NodeKind.Field {
        let address_id = emit_late_place_address(tables, compiler, ir, receiver)
        location = compiler_location(compiler, 2L, address_id, 0L)
    }
    let pointer_serial = emit_location_pointer_materialization(compiler, ir, location)
    if method == COLLECTION_METHOD_LEN {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_number(compiler, ir, capacity); ir_push_byte(compiler, ir, 10)
        return
    }
    if method == COLLECTION_METHOD_COUNT {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1\n")
        return
    }
    if method == COLLECTION_METHOD_CLEAR {
        ir_write_ascii(compiler, ir, "  store i64 0, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1\n")
        return
    }
    if method == COLLECTION_METHOD_PUSH {
        let proven = (compiler.facts[node].flags & FACT_PROVEN_SUCCESS) != 0L
        ir_write_ascii(compiler, ir, "  %coll.push.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1\n")
        if proven {
            ir_write_ascii(compiler, ir, "  br label %coll.push.add."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        } else {
            ir_write_ascii(compiler, ir, "  %coll.push.room."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ult i64 %coll.push.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, capacity); ir_write_ascii(compiler, ir, "\n  br i1 %coll.push.room."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.push.add."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.push.full."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "coll.push.add."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.push.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = mul i64 %coll.push.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_write_ascii(compiler, ir, "\n  %coll.push.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.push.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %coll.push.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.push.offset."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
        if is_aggregate_type(compiler, element) {
            let source_kind = if tables.nodes[value_argument].kind == NodeKind.Name && compiler.facts[value_argument].binding >= 0L {
                if compiler.bindings[compiler.facts[value_argument].binding].parameter { 2L } else { 1L }
            } else if tables.nodes[value_argument].kind == NodeKind.Field { 3L } else { 0L }
            let source_id = if source_kind == 1L || source_kind == 2L { compiler.facts[value_argument].binding } else { value_argument }
            let source_location = aggregate_source_location(compiler, source_kind, source_id)
            let source_pointer = emit_location_pointer_materialization(compiler, ir, source_location)
            emit_collection_store_dynamic_fields(compiler, ir, element, capacity, base_offset, 0L,
                location, pointer_serial, source_location, source_pointer, 1L, node)
        } else if element == TY_BOOL {
            ir_write_ascii(compiler, ir, "  %coll.push.bool."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i8\n  store i8 %coll.push.bool."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %coll.push.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        } else {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(element)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", ptr %coll.push.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  %coll.push.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.push.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  store i64 %coll.push.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        emit_collection_capacity_result_tag(compiler, ir, node, 0L)
        ir_write_ascii(compiler, ir, "  br label %coll.push.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        if !proven {
            ir_write_ascii(compiler, ir, "coll.push.full."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
            emit_collection_capacity_result_tag(compiler, ir, node, 1L)
            ir_write_ascii(compiler, ir, "  br label %coll.push.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "coll.push.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        return
    }
    if method == COLLECTION_METHOD_INSERT {
        let position = position_for_offset(file_index, files[file_index].base + tables.nodes[argument].anchor, compiler)
        ir_write_ascii(compiler, ir, "  %coll.insert.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1\n  %coll.insert.negative."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp slt i64 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", 0\n  %coll.insert.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ugt i64 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", %coll.insert.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %coll.insert.invalid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i1 %coll.insert.negative."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %coll.insert.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  br i1 %coll.insert.invalid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.insert.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.insert.valid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.insert.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 16, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\ncoll.insert.valid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.insert.room."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ult i64 %coll.insert.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, capacity); ir_write_ascii(compiler, ir, "\n  br i1 %coll.insert.room."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.insert.shift.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.insert.full."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.insert.shift.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.insert.cursor."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = phi i64 [ %coll.insert.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %coll.insert.valid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ], [ %coll.insert.prev."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %coll.insert.shift.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ]\n  %coll.insert.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ugt i64 %coll.insert.cursor."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, "\n  br i1 %coll.insert.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.insert.shift.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.insert.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.insert.shift.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.insert.from."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sub i64 %coll.insert.cursor."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  %coll.insert.from.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = mul i64 %coll.insert.from."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_write_ascii(compiler, ir, "\n  %coll.insert.from.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.insert.from.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %coll.insert.to.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = mul i64 %coll.insert.cursor."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_write_ascii(compiler, ir, "\n  %coll.insert.to.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.insert.to.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %coll.insert.from.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.insert.from.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %coll.insert.to.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.insert.to.offset."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
        let storage = collection_storage_type(element)
        if is_aggregate_type(compiler, element) {
            emit_collection_move_dynamic_fields(compiler, ir, element, capacity, base_offset,
                location, pointer_serial, 3L, node, 4L, node)
        } else {
            ir_write_ascii(compiler, ir, "  %coll.insert.moved."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.insert.from.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.insert.moved."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %coll.insert.to.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  %coll.insert.prev."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sub i64 %coll.insert.cursor."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  br label %coll.insert.shift.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.insert.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.insert.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = mul i64 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_write_ascii(compiler, ir, "\n  %coll.insert.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.insert.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %coll.insert.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.insert.offset."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
        if is_aggregate_type(compiler, element) {
            let source_kind = if tables.nodes[value_argument].kind == NodeKind.Name && compiler.facts[value_argument].binding >= 0L {
                if compiler.bindings[compiler.facts[value_argument].binding].parameter { 2L } else { 1L }
            } else if tables.nodes[value_argument].kind == NodeKind.Field { 3L } else { 0L }
            let source_id = if source_kind == 1L || source_kind == 2L { compiler.facts[value_argument].binding } else { value_argument }
            let source_location = aggregate_source_location(compiler, source_kind, source_id)
            let source_pointer = emit_location_pointer_materialization(compiler, ir, source_location)
            emit_collection_store_dynamic_fields(compiler, ir, element, capacity, base_offset, 0L,
                location, pointer_serial, source_location, source_pointer, 2L, argument)
        } else if element == TY_BOOL { ir_write_ascii(compiler, ir, "  %coll.insert.bool."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value_argument); ir_write_ascii(compiler, ir, " to i8\n  store i8 %coll.insert.bool."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %coll.insert.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10) }
        else { ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(element)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_argument); ir_write_ascii(compiler, ir, ", ptr %coll.insert.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10) }
        ir_write_ascii(compiler, ir, "  %coll.insert.next.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.insert.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  store i64 %coll.insert.next.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        emit_collection_capacity_result_tag(compiler, ir, node, 0L)
        ir_write_ascii(compiler, ir, "  br label %coll.insert.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.insert.full."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_collection_capacity_result_tag(compiler, ir, node, 1L)
        ir_write_ascii(compiler, ir, "  br label %coll.insert.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.insert.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        return
    }
    if method == COLLECTION_METHOD_POP {
        let result_type = compiler.facts[node].ty
        let payload = sum_payload_record(compiler, result_type, 0L, 0L)
        ir_write_ascii(compiler, ir, "  %coll.pop.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1\n")
        ir_write_ascii(compiler, ir, "  %coll.pop.empty."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i64 %coll.pop.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n  br i1 %coll.pop.empty."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.pop.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.pop.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.pop.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.pop.last."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sub i64 %coll.pop.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n")
        let destination = aggregate_destination_location(compiler, 0L, node)
        let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
        if is_aggregate_type(compiler, element) {
            emit_collection_gather_dynamic_fields(compiler, ir, element, capacity, base_offset, payload.offset,
                location, pointer_serial, 8L, node, destination, destination_pointer)
        } else {
            let storage = collection_storage_type(element)
            let source_serial = next_location_serial(ir)
            ir_write_ascii(compiler, ir, "  %coll.pop.bytes."); ir_write_number(compiler, ir, source_serial); ir_write_ascii(compiler, ir, " = mul i64 %coll.pop.last."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "  %coll.pop.offset."); ir_write_number(compiler, ir, source_serial); ir_write_ascii(compiler, ir, " = add i64 %coll.pop.bytes."); ir_write_number(compiler, ir, source_serial); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "  %coll.ptr."); ir_write_number(compiler, ir, source_serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.pop.offset."); ir_write_number(compiler, ir, source_serial); ir_push_byte(compiler, ir, 10)
            let address = enum_temporary_address(node, MAX_TREE_NODES * 3L + 2L)
            emit_layout_address(compiler, ir, address, storage_location_with_offset(aggregate_destination_location(compiler, 0L, node), payload.offset))
            ir_write_ascii(compiler, ir, "  %coll.pop.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.ptr."); ir_write_number(compiler, ir, source_serial); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.pop.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  store i64 %coll.pop.last."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        emit_sum_tag_store(compiler, ir, node, 0L)
        ir_write_ascii(compiler, ir, "  br label %coll.pop.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.pop.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_sum_tag_store(compiler, ir, node, 1L)
        ir_write_ascii(compiler, ir, "  br label %coll.pop.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.pop.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        return
    }
    if method == COLLECTION_METHOD_REMOVE {
        let position = position_for_offset(file_index, files[file_index].base + tables.nodes[argument].anchor, compiler)
        ir_write_ascii(compiler, ir, "  %coll.remove.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1\n  %coll.remove.negative."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp slt i64 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", 0\n  %coll.remove.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sge i64 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", %coll.remove.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %coll.remove.invalid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i1 %coll.remove.negative."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %coll.remove.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  br i1 %coll.remove.invalid."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.remove.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.remove.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.remove.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 16, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\ncoll.remove.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        if is_aggregate_type(compiler, element) {
            let result_location = aggregate_destination_location(compiler, 0L, node)
            let result_pointer = emit_location_pointer_materialization(compiler, ir, result_location)
            emit_collection_gather_dynamic_fields(compiler, ir, element, capacity, base_offset, 0L,
                location, pointer_serial, 2L, argument, result_location, result_pointer)
        } else {
            emit_collection_method_index_address(compiler, ir, node, location, pointer_serial, argument, base_offset, stride)
            if element == TY_BOOL { ir_write_ascii(compiler, ir, "  %coll.remove.raw."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i8 %coll.remove.raw."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i1\n") }
            else { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(element)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n") }
        }
        ir_write_ascii(compiler, ir, "  br label %coll.remove.shift.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.remove.shift.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.remove.cursor."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = phi i64 [ "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", %coll.remove.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ], [ %coll.remove.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %coll.remove.shift.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " ]\n  %coll.remove.source.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.remove.cursor."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  %coll.remove.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ult i64 %coll.remove.source.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %coll.remove.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  br i1 %coll.remove.more."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.remove.shift.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %coll.remove.finish."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.remove.shift.body."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.remove.from.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = mul i64 %coll.remove.source.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_write_ascii(compiler, ir, "\n  %coll.remove.from.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.remove.from.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %coll.remove.to.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = mul i64 %coll.remove.cursor."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_write_ascii(compiler, ir, "\n  %coll.remove.to.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.remove.to.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %coll.remove.from.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.remove.from.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %coll.remove.to.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", i64 %coll.remove.to.offset."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
        if is_aggregate_type(compiler, element) {
            emit_collection_move_dynamic_fields(compiler, ir, element, capacity, base_offset,
                location, pointer_serial, 5L, node, 6L, node)
        } else {
            let storage = collection_storage_type(element)
            ir_write_ascii(compiler, ir, "  %coll.remove.moved."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, ", ptr %coll.remove.from.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %coll.remove.moved."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %coll.remove.to.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  %coll.remove.next."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %coll.remove.cursor."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  br label %coll.remove.shift.cond."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ncoll.remove.finish."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %coll.remove.new.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sub i64 %coll.remove.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  store i64 %coll.remove.new.count."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1"); emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
        return
    }
    let _ = kind
    compiler.ir_overflow = true
}
