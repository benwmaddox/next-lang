fn literal_value(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    tables: ParseTables,
    file_index: long,
    node: long,
    ty: long,
) -> long {
    let syntax = tables.nodes[node]
    let magnitude = tables.literals[syntax.extra]
    let negative = (syntax.flags & FLAG_NEGATIVE) != 0L
    let max_low = if ty == TY_BYTE { if negative { 0L } else { 255L } }
        else if ty == TY_INT { if negative { 2147483648L } else { 2147483647L } }
        else if negative { 0L } else { 4294967295L }
    let max_high = if ty == TY_BYTE || ty == TY_INT { 0L } else { if negative { 2147483648L } else { 2147483647L } }
    let too_big = magnitude.limb3 != 0L || magnitude.limb2 != 0L || magnitude.limb1 > max_high || (magnitude.limb1 == max_high && magnitude.limb0 > max_low)
    if too_big {
        let file = files[file_index]
        let position = position_for_offset(file_index, file.base + syntax.start, compiler)
        match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        if ty == TY_BYTE {
            match env.err.write(b": error: byte literal '") { ok(_) => (), err(_) => env.exit(3) }
            if negative { match env.err.write(b"-") { ok(_) => (), err(_) => env.exit(3) } }
            match write_token_raw(env.err, source, tokens, file.base, syntax.token) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b"' is outside 0..255\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
        }
        match env.err.write(b": error: integer literal does not fit ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(scalar_type_name(ty).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"; add 'L' for long or give it a long context\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
    }
    if negative && ty == TY_LONG && magnitude.limb1 == 2147483648L && magnitude.limb0 == 0L { return -9223372036854775807L - 1L }
    let unsigned = magnitude.limb1 * 4294967296L + magnitude.limb0
    if negative {
        if ty == TY_INT && magnitude.limb1 == 0L && magnitude.limb0 == 2147483648L { return -2147483647L - 1L }
        -unsigned
    } else {
        unsigned
    }
}

fn unsupported_scalar_constant() -> ScalarConstantResult {
    ScalarConstantResult { value: 0L, supported: false }
}

fn scalar_constant_value(value: long) -> ScalarConstantResult {
    ScalarConstantResult { value, supported: true }
}

fn scalar_constant_arithmetic_value(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    node_offset: long,
    expected_ty: long,
    value: long,
) -> ScalarConstantResult {
    if expected_ty == TY_BYTE && (value < 0L || value > 255L) {
        fail_at_message(env, files, compiler, file_index, node_offset, "constant arithmetic overflows byte")
    }
    if expected_ty == TY_INT && (value < -2147483648L || value > 2147483647L) {
        fail_at_message(env, files, compiler, file_index, node_offset, "constant arithmetic overflows int")
    }
    scalar_constant_value(value)
}

// The first constant declared with this name (index built by register_scalar_constants), or -1.
fn find_constant_declaration(tables: ParseTables, compiler: CompilerTables, name_id: long) -> long {
    if name_id < 0L || name_id >= compiler.constant_by_name.count() { return -1L }
    compiler.constant_by_name[name_id]
}

fn package_has_enum_case_name(tables: ParseTables, compiler: CompilerTables, name_id: long) -> bool {
    for candidate in 0L..tables.nodes.count() {
        if tables.nodes[candidate].kind == NodeKind.EnumCase {
            let token = tables.nodes[candidate].token
            if token >= 0L && token < compiler.token_name_ids.count() && compiler.token_name_ids[token] == name_id {
                return true
            }
        }
    }
    false
}

fn package_name_declaration_token(tables: ParseTables, node: long) -> long {
    let kind = tables.nodes[node].kind
    if kind == NodeKind.Function || kind == NodeKind.Global || kind == NodeKind.Const ||
        kind == NodeKind.Enum || kind == NodeKind.EnumCase || kind == NodeKind.Struct ||
        kind == NodeKind.TypeAlias {
        tables.nodes[node].token
    } else { -1L }
}

fn scalar_constant_declaration_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    declaration: long,
) -> long {
    if declaration < 0L || declaration >= tables.nodes.count() { return -1L }
    let type_node = compiler.child_first[declaration]
    if type_node < 0L || tables.nodes[type_node].kind != NodeKind.DeclaredType { return -1L }
    let file_index = node_file_index(tables.nodes, files, type_node)
    let syntax = tables.nodes[type_node]
    let ty = if token_is_word_at(source, tokens, files, file_index, syntax.token, "byte") { TY_BYTE }
        else if token_is_word_at(source, tokens, files, file_index, syntax.token, "int") { TY_INT }
        else if token_is_word_at(source, tokens, files, file_index, syntax.token, "long") { TY_LONG }
        else { -1L }
    if ty >= 0L && syntax.flags == 0L && syntax.meta0 == 1L && syntax.meta1 == 0L &&
        compiler.child_first[type_node] < 0L {
        ty
    } else { -1L }
}

fn fail_scalar_constant_type(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    tables: ParseTables,
    file_index: long,
    node: long,
    expected_ty: long,
) -> never {
    fail_at_message(env, files, compiler, file_index, tables.nodes[node].start,
        if expected_ty == TY_BYTE { "constant initializer must have type byte" }
            else if expected_ty == TY_INT { "constant initializer must have type int" }
            else { "constant initializer must have type long" })
}

recursive fn evaluate_scalar_constant_declaration(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    declaration: long,
    depth: long,
) -> ScalarConstantResult {
    if depth > MAX_PARSER_DEPTH {
        let file_index = node_file_index(tables.nodes, files, declaration)
        fail_at_message(env, files, compiler, file_index, tables.nodes[declaration].start, "constant dependency depth exceeds the compiler limit")
    }
    if declaration < 0L || declaration >= tables.nodes.count() { return unsupported_scalar_constant() }
    let existing = compiler.facts[declaration]
    if (existing.flags & FACT_CONSTANT_EVALUATED) != 0L { return scalar_constant_value(existing.literal) }
    if (existing.flags & FACT_CONSTANT_VISITING) != 0L {
        let file_index = node_file_index(tables.nodes, files, declaration)
        fail_at_message(env, files, compiler, file_index, tables.nodes[declaration].start, "constant dependency cycle")
    }
    if (existing.flags & FACT_CONSTANT_DECLARED) == 0L { return unsupported_scalar_constant() }
    let declared_ty = existing.ty
    compiler.facts[declaration].flags = FACT_CONSTANT_DECLARED | FACT_CONSTANT_VISITING
    let expression = node_last_child(tables, compiler, declaration)
    let value = evaluate_scalar_constant_expression(
        env, source, tokens, files, tables, compiler, expression, declared_ty, depth + 1L,
    )
    if !value.supported {
        compiler.facts[declaration].flags = FACT_CONSTANT_DECLARED
        return value
    }
    compiler.facts[declaration] = NodeFact {
        ty: declared_ty,
        flags: FACT_CONSTANT_DECLARED | FACT_CONSTANT_EVALUATED,
        binding: -1L,
        function: -1L,
        literal: value.value,
    }
    value
}

recursive fn evaluate_scalar_constant_expression(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    node: long,
    expected_ty: long,
    depth: long,
) -> ScalarConstantResult {
    if node < 0L || node >= tables.nodes.count() { return unsupported_scalar_constant() }
    if depth > MAX_PARSER_DEPTH {
        let file_index = node_file_index(tables.nodes, files, node)
        fail_at_message(env, files, compiler, file_index, tables.nodes[node].start, "constant expression depth exceeds the compiler limit")
    }
    let syntax = tables.nodes[node]
    let file_index = node_file_index(tables.nodes, files, node)
    if syntax.kind == NodeKind.Integer {
        if (expected_ty == TY_INT || expected_ty == TY_BYTE) && (syntax.flags & FLAG_LONG_SUFFIX) != 0L {
            fail_scalar_constant_type(env, files, compiler, tables, file_index, node, expected_ty)
        }
        scalar_constant_value(literal_value(env, source, tokens, files, compiler, tables, file_index, node, expected_ty))
    } else if syntax.kind == NodeKind.Name {
        let name_id = compiler.token_name_ids[syntax.token]
        let declaration = find_constant_declaration(tables, compiler, name_id)
        if declaration >= 0L {
            if (compiler.facts[declaration].flags & FACT_CONSTANT_DECLARED) == 0L { return unsupported_scalar_constant() }
            if compiler.facts[declaration].ty != expected_ty {
                fail_scalar_constant_type(env, files, compiler, tables, file_index, node, expected_ty)
            }
            evaluate_scalar_constant_declaration(env, source, tokens, files, tables, compiler, declaration, depth + 1L)
        } else if user_case_matches(compiler, name_id) >= 0L ||
            package_has_enum_case_name(tables, compiler, name_id) ||
            builtin_case_name(source, tokens, files, file_index, syntax.token) {
            fail_scalar_constant_type(env, files, compiler, tables, file_index, node, expected_ty)
        } else {
            var is_package_value = false
            for candidate in 0L..tables.nodes.count() {
                let token = package_name_declaration_token(tables, candidate)
                if token >= 0L && compiler.token_name_ids[token] == name_id &&
                    (tables.nodes[candidate].kind == NodeKind.Function || tables.nodes[candidate].kind == NodeKind.Global) {
                    is_package_value = true
                }
            }
            if is_package_value { unsupported_scalar_constant() }
            else { fail_name_error(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token, -1L, false) }
        }
    } else if syntax.kind == NodeKind.Unary && syntax.flags == 0L {
        let child = compiler.child_first[node]
        let value = evaluate_scalar_constant_expression(env, source, tokens, files, tables, compiler, child, expected_ty, depth + 1L)
        if !value.supported { return value }
        let negated = checked_capacity_negate(value.value)
        if !negated.valid { fail_at_message(env, files, compiler, file_index, syntax.start, "constant arithmetic overflows long") }
        scalar_constant_arithmetic_value(env, files, compiler, file_index, syntax.start, expected_ty, negated.value)
    } else if syntax.kind == NodeKind.Unary && syntax.flags == 1L {
        fail_scalar_constant_type(env, files, compiler, tables, file_index, node, expected_ty)
    } else if syntax.kind == NodeKind.Unary {
        unsupported_scalar_constant()
    } else if syntax.kind == NodeKind.Binary && syntax.flags >= 0L && syntax.flags <= 4L {
        let left_node = compiler.child_first[node]
        let right_node = if left_node >= 0L { compiler.child_next[left_node] } else { -1L }
        let left = evaluate_scalar_constant_expression(env, source, tokens, files, tables, compiler, left_node, expected_ty, depth + 1L)
        if !left.supported { return left }
        let right = evaluate_scalar_constant_expression(env, source, tokens, files, tables, compiler, right_node, expected_ty, depth + 1L)
        if !right.supported { return right }
        if syntax.flags == 0L {
            let result = checked_capacity_add(left.value, right.value)
            if !result.valid { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant arithmetic overflows long") }
            scalar_constant_arithmetic_value(env, files, compiler, file_index, syntax.anchor, expected_ty, result.value)
        } else if syntax.flags == 1L {
            let result = checked_capacity_subtract(left.value, right.value)
            if !result.valid { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant arithmetic overflows long") }
            scalar_constant_arithmetic_value(env, files, compiler, file_index, syntax.anchor, expected_ty, result.value)
        } else if syntax.flags == 2L {
            let result = checked_capacity_multiply(left.value, right.value)
            if !result.valid { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant arithmetic overflows long") }
            scalar_constant_arithmetic_value(env, files, compiler, file_index, syntax.anchor, expected_ty, result.value)
        } else if syntax.flags == 3L {
            if right.value == 0L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant division by zero") }
            let result = checked_capacity_divide(left.value, right.value)
            if !result.valid { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant arithmetic overflows long") }
            scalar_constant_arithmetic_value(env, files, compiler, file_index, syntax.anchor, expected_ty, result.value)
        } else {
            if right.value == 0L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant remainder by zero") }
            let result = checked_capacity_remainder(left.value, right.value)
            if !result.valid { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant arithmetic overflows long") }
            scalar_constant_arithmetic_value(env, files, compiler, file_index, syntax.anchor, expected_ty, result.value)
        }
    } else if syntax.kind == NodeKind.Bool || syntax.kind == NodeKind.ByteString ||
        syntax.kind == NodeKind.BytesLiteral || syntax.kind == NodeKind.ArrayLiteral ||
        syntax.kind == NodeKind.ListLiteral || syntax.kind == NodeKind.StructInit ||
        syntax.kind == NodeKind.Unit {
        fail_scalar_constant_type(env, files, compiler, tables, file_index, node, expected_ty)
    } else if syntax.kind == NodeKind.Call || syntax.kind == NodeKind.MethodCall ||
        syntax.kind == NodeKind.OptionalCall || syntax.kind == NodeKind.Cast ||
        syntax.kind == NodeKind.If || syntax.kind == NodeKind.Match || syntax.kind == NodeKind.Block ||
        syntax.kind == NodeKind.Binary || syntax.kind == NodeKind.Unary {
        unsupported_scalar_constant()
    } else {
        unsupported_scalar_constant()
    }
}

fn register_scalar_constants(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind != NodeKind.Const { continue }
        let token = tables.nodes[node].token
        if token < 0L || token >= compiler.token_name_ids.count() { continue }
        let indexed_name = compiler.token_name_ids[token]
        if indexed_name >= 0L && indexed_name < compiler.constant_by_name.count() && compiler.constant_by_name[indexed_name] < 0L {
            compiler.constant_by_name[indexed_name] = node
        }
    }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind != NodeKind.Const { continue }
        let syntax = tables.nodes[node]
        let name_id = compiler.token_name_ids[syntax.token]
        let const_file_index = node_file_index(tables.nodes, files, node)
        if builtin_case_name(source, tokens, files, const_file_index, syntax.token) {
            fail_dynamic_checker_error(env, source, files, tokens, compiler, const_file_index, syntax.start,
                "package name '", syntax.token, "' conflicts with a constant declaration")
        }
        for prior in 0L..node {
            if tables.nodes[prior].kind == NodeKind.Const &&
                compiler.token_name_ids[tables.nodes[prior].token] == name_id {
                let file_index = node_file_index(tables.nodes, files, node)
                fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start,
                    "constant '", syntax.token, "' is declared more than once")
            }
        }
        for other in 0L..tables.nodes.count() {
            if other == node { continue }
            let other_token = package_name_declaration_token(tables, other)
            if other_token < 0L || compiler.token_name_ids[other_token] != name_id { continue }
            let other_kind = tables.nodes[other].kind
            if other_kind == NodeKind.Global {
                let file_index = node_file_index(tables.nodes, files, node)
                fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start,
                    "constant '", syntax.token, "' is declared more than once")
            } else if other_kind == NodeKind.Function {
                let file_index = node_file_index(tables.nodes, files, other)
                fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, tables.nodes[other].start,
                    "function '", other_token, "' conflicts with a global or constant; choose a unique value name")
            } else if other_kind == NodeKind.Enum || other_kind == NodeKind.EnumCase ||
                other_kind == NodeKind.Struct || other_kind == NodeKind.TypeAlias {
                let conflict = if other > node { other } else { node }
                let conflict_token = tables.nodes[conflict].token
                let file_index = node_file_index(tables.nodes, files, conflict)
                fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, tables.nodes[conflict].start,
                    "package name '", conflict_token, "' conflicts with a constant declaration")
            } else { () }
        }
        let constant_ty = scalar_constant_declaration_type(source, tokens, files, tables, compiler, node)
        if constant_ty >= 0L {
            compiler.facts[node] = NodeFact {
                ty: constant_ty,
                flags: FACT_CONSTANT_DECLARED,
                binding: -1L,
                function: -1L,
                literal: 0L,
            }
        }
    }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.Const &&
            (compiler.facts[node].flags & FACT_CONSTANT_DECLARED) != 0L {
            let _ = evaluate_scalar_constant_declaration(env, source, tokens, files, tables, compiler, node, 0L)
        }
    }
}

fn check_call_count(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    function: FunctionRecord,
    call_node: long,
    file_index: long,
) {
    let actual = count_children(tables, compiler, call_node)
    if actual != function.param_count {
        fail_call_arity(env, source, files, tokens, compiler, file_index, tables.nodes[call_node].start, function.name_token, function.param_count, actual)
    }
}

fn is_assignable_place(tables: ParseTables, node: long) -> bool {
    if node < 0L { return false }
    tables.nodes[node].kind == NodeKind.Name || tables.nodes[node].kind == NodeKind.Field || tables.nodes[node].kind == NodeKind.Index
}

fn place_root_binding(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    var current = node
    for path_step in 0L..MAX_TREE_NODES {
        if current < 0L { return -1L }
        let kind = tables.nodes[current].kind
        if kind == NodeKind.Field || kind == NodeKind.Index {
            current = compiler.child_first[current]
        } else if kind == NodeKind.Name {
            return compiler.facts[current].binding
        } else {
            return -1L
        }
    }
    -1L
}

fn place_root_is_view(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    let binding = place_root_binding(tables, compiler, node)
    binding_is_view(compiler, binding)
}

fn place_alias_root_binding(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    if node < 0L { return -1L }
    var binding = compiler.facts[node].binding
    for view_step in 0L..compiler.bindings.count() {
        if !binding_is_view(compiler, binding) { break }
        let loop_node = compiler.bindings[binding].node
        let collection = compiler.child_first[loop_node]
        if collection < 0L { return -1L }
        binding = compiler.facts[collection].binding
    }
    binding
}

fn place_path_depth(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    var current = node
    var depth = 0L
    for step in 0L..MAX_TREE_NODES {
        if current < 0L { return -1L }
        let kind = tables.nodes[current].kind
        if kind == NodeKind.Field || kind == NodeKind.Index {
            depth += 1L
            current = compiler.child_first[current]
        } else if kind == NodeKind.Name { return depth }
        else { return -1L }
    }
    -1L
}


// A constant of type Ascii max N or Bytes max N initialised with a literal of that kind. A use of
// the constant copies the literal into the use's own temporary (see emit_text_literal_value), so
// the constant needs no storage of its own.
fn register_text_constants(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind != NodeKind.Const { continue }
        if (compiler.facts[node].flags & FACT_CONSTANT_EVALUATED) != 0L { continue }
        let type_node = compiler.child_first[node]
        if type_node < 0L || (compiler.facts[type_node].flags & FACT_RESOLVED_TYPE) == 0L { continue }
        let declared = compiler.facts[type_node].ty
        let kind = type_kind(compiler, declared)
        if kind != TYPE_KIND_ASCII && kind != TYPE_KIND_BYTES { continue }
        let initializer = node_last_child(tables, compiler, node)
        if initializer < 0L || initializer == type_node { continue }
        let wanted = if kind == TYPE_KIND_ASCII { NodeKind.ByteString } else { NodeKind.BytesLiteral }
        if tables.nodes[initializer].kind != wanted { continue }
        let file_index = node_file_index(tables.nodes, files, node)
        let literal = if wanted == NodeKind.BytesLiteral {
            decode_string_token(source, tokens, files[file_index].base, tables.nodes[initializer].extra, true)
        } else { decode_string_token(source, tokens, files[file_index].base, tables.nodes[initializer].token, false) }
        if literal.count() > text_max_bytes(compiler, declared) {
            fail_text_literal_too_long(env, files, compiler, file_index, tables.nodes[initializer].start,
                wanted == NodeKind.BytesLiteral, literal.count(), text_max_bytes(compiler, declared))
        }
        compiler.facts[node] = NodeFact {
            ty: declared,
            flags: FACT_CONSTANT_DECLARED | FACT_CONSTANT_EVALUATED | FACT_CONSTANT_TEXT,
            binding: -1L,
            function: -1L,
            literal: initializer,
        }
    }
}

// A constant of fixed array type whose elements are int, long or byte literals, or Ascii max N text literals.
// register_array_constants checks the shape; emit_file_globals writes the array image as an IR
// global and a use copies it into the use's own temporary (emit_array_constant_value).
fn register_array_constants(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind != NodeKind.Const { continue }
        if (compiler.facts[node].flags & FACT_CONSTANT_EVALUATED) != 0L { continue }
        let type_node = compiler.child_first[node]
        if type_node < 0L || (compiler.facts[type_node].flags & FACT_RESOLVED_TYPE) == 0L { continue }
        let declared = compiler.facts[type_node].ty
        if type_kind(compiler, declared) != TYPE_KIND_ARRAY { continue }
        let element = collection_element_type(compiler, declared)
        let element_kind = type_kind(compiler, element)
        if element != TY_INT && element != TY_LONG && element != TY_BYTE && element_kind != TYPE_KIND_ASCII { continue }
        let initializer = node_last_child(tables, compiler, node)
        if initializer < 0L || initializer == type_node || tables.nodes[initializer].kind != NodeKind.ArrayLiteral { continue }
        let file_index = node_file_index(tables.nodes, files, node)
        let capacity = collection_capacity(compiler, declared)
        var item = compiler.child_first[initializer]
        var count = 0L
        var supported = true
        for step in 0L..capacity + 1L {
            if item < 0L { break }
            let literal_kind = tables.nodes[item].kind
            if element_kind == TYPE_KIND_ASCII {
                if literal_kind != NodeKind.ByteString { supported = false }
                else {
                    let literal_length = decode_string_token(source, tokens, files[file_index].base, tables.nodes[item].token, false).count()
                    if literal_length > text_max_bytes(compiler, element) {
                        fail_text_literal_too_long(env, files, compiler, file_index, tables.nodes[item].start, false, literal_length, text_max_bytes(compiler, element))
                    }
                }
            } else if literal_kind != NodeKind.Integer { supported = false }
            else {
                let _checked = literal_value(env, source, tokens, files, compiler, tables, file_index, item, element)
            }
            count += 1L
            item = compiler.child_next[item]
        }
        if !supported || count != capacity { continue }
        compiler.facts[node] = NodeFact {
            ty: declared,
            flags: FACT_CONSTANT_DECLARED | FACT_CONSTANT_EVALUATED | FACT_CONSTANT_ARRAY,
            binding: -1L,
            function: -1L,
            literal: node,
        }
    }
}

// ---- constants of struct, array, list and map type -----------------------------------------------------------------
// A constant whose initializer is built only from literals: numbers, bools, text, struct literals naming every field,
// array literals of the full length, and empty `list {}` / `map {}`. register_image_constants checks the shape (after the
// types are sized); emit_file_globals writes the value as a byte image in an IR global, like an array constant, and a use
// copies it into the use's own temporary.


// The initializer field of struct literal `node` that names struct field `field`, else -1 (also when it is named twice).
fn const_image_field_init(tables: ParseTables, compiler: CompilerTables, node: long, field: long) -> long {
    var found = -1L
    var child = compiler.child_first[node]
    for step in 0L..tables.nodes[node].subtree {
        if child < 0L { break }
        if tables.nodes[child].kind == NodeKind.InitializerField &&
            compiler.token_name_ids[tables.nodes[child].token] == compiler.struct_fields[field].name_id {
            if found >= 0L { return -1L }
            found = child
        }
        child = compiler.child_next[child]
    }
    found
}

recursive fn const_image_valid(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
    ty: long,
    depth: long,
) -> bool {
    if depth > 8L || node < 0L || ty < 0L { return false }
    let kind = type_kind(compiler, ty)
    let syntax_kind = tables.nodes[node].kind
    if ty == TY_BOOL { return syntax_kind == NodeKind.Bool }
    if ty == TY_INT || ty == TY_LONG || ty == TY_BYTE {
        if syntax_kind != NodeKind.Integer { return false }
        let _checked = literal_value(env, source, tokens, files, compiler, tables, file_index, node, ty)
        return true
    }
    if kind == TYPE_KIND_ASCII || kind == TYPE_KIND_BYTES {
        let is_bytes = kind == TYPE_KIND_BYTES
        let wanted = if is_bytes { NodeKind.BytesLiteral } else { NodeKind.ByteString }
        if syntax_kind != wanted { return false }
        let literal = if is_bytes { decode_string_token(source, tokens, files[file_index].base, tables.nodes[node].extra, true) } else { decode_string_token(source, tokens, files[file_index].base, tables.nodes[node].token, false) }
        if literal.count() > text_max_bytes(compiler, ty) {
            fail_text_literal_too_long(env, files, compiler, file_index, tables.nodes[node].start, is_bytes, literal.count(), text_max_bytes(compiler, ty))
        }
        return true
    }
    if kind == TYPE_KIND_STRUCT {
        if syntax_kind != NodeKind.StructInit { return false }
        let record = type_record(compiler, ty)
        if compiler.token_name_ids[tables.nodes[node].token] != record.name_id { return false }
        var children = 0L
        var child = compiler.child_first[node]
        for step in 0L..tables.nodes[node].subtree {
            if child < 0L { break }
            children += 1L
            child = compiler.child_next[child]
        }
        if children != record.field_count { return false }
        for offset in 0L..record.field_count {
            let field = record.field_start + offset
            let init = const_image_field_init(tables, compiler, node, field)
            if init < 0L { return false }
            if !const_image_valid(env, source, tokens, files, tables, compiler, file_index, compiler.child_first[init], compiler.struct_fields[field].ty, depth + 1L) { return false }
        }
        return true
    }
    if kind == TYPE_KIND_ARRAY {
        if syntax_kind != NodeKind.ArrayLiteral { return false }
        let element = collection_element_type(compiler, ty)
        let capacity = collection_capacity(compiler, ty)
        var item = compiler.child_first[node]
        var count = 0L
        for step in 0L..capacity + 1L {
            if item < 0L { break }
            if !const_image_valid(env, source, tokens, files, tables, compiler, file_index, item, element, depth + 1L) { return false }
            count += 1L
            item = compiler.child_next[item]
        }
        return count == capacity
    }
    if collection_kind_is_list(kind) { return syntax_kind == NodeKind.ListLiteral && compiler.child_first[node] < 0L }
    if kind == TYPE_KIND_MAP { return syntax_kind == NodeKind.MapLiteral && compiler.child_first[node] < 0L }
    false
}

fn register_image_constants(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind != NodeKind.Const { continue }
        if (compiler.facts[node].flags & FACT_CONSTANT_EVALUATED) != 0L { continue }
        let type_node = compiler.child_first[node]
        if type_node < 0L || (compiler.facts[type_node].flags & FACT_RESOLVED_TYPE) == 0L { continue }
        let declared = compiler.facts[type_node].ty
        let kind = type_kind(compiler, declared)
        if kind != TYPE_KIND_STRUCT && kind != TYPE_KIND_ARRAY && !collection_kind_is_list(kind) && kind != TYPE_KIND_MAP { continue }
        if value_type_size(compiler, declared) < 0L || type_contains_pool(compiler, declared, 0L) { continue }
        let initializer = node_last_child(tables, compiler, node)
        if initializer < 0L || initializer == type_node { continue }
        let file_index = node_file_index(tables.nodes, files, node)
        if !const_image_valid(env, source, tokens, files, tables, compiler, file_index, initializer, declared, 0L) { continue }
        compiler.facts[node] = NodeFact {
            ty: declared,
            flags: FACT_CONSTANT_DECLARED | FACT_CONSTANT_EVALUATED | FACT_CONSTANT_ARRAY,
            binding: -1L,
            function: -1L,
            literal: node,
        }
    }
}

fn const_image_zeros(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, count: long) {
    for index in 0L..count { ir_write_hex_escaped(compiler, ir, 0L) }
}

// Write the bytes of the value of `node` as a variable of type `ty` holds it: exactly value_type_size(ty) bytes.
recursive fn emit_const_image_bytes(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    file_index: long,
    node: long,
    ty: long,
) {
    let kind = type_kind(compiler, ty)
    let size = value_type_size(compiler, ty)
    if ty == TY_BOOL {
        ir_write_hex_escaped(compiler, ir, if (tables.nodes[node].flags & FLAG_VALUE) != 0L { 1L } else { 0L })
    } else if ty == TY_INT || ty == TY_LONG || ty == TY_BYTE {
        let magnitude = tables.literals[tables.nodes[node].extra]
        let raw = magnitude.limb1 * 4294967296L + magnitude.limb0
        let value = if (tables.nodes[node].flags & FLAG_NEGATIVE) != 0L { 0L - raw } else { raw }
        for shift in 0L..size { ir_write_hex_escaped(compiler, ir, (value >> (shift * 8L)) & 255L) }
    } else if kind == TYPE_KIND_ASCII || kind == TYPE_KIND_BYTES {
        // [length: i64][zero padding to the data offset][bytes][zero padding up to the size]
        let literal = if kind == TYPE_KIND_BYTES { decode_string_token(source, tokens, files[file_index].base, tables.nodes[node].extra, true) } else { decode_string_token(source, tokens, files[file_index].base, tables.nodes[node].token, false) }
        let data_offset = text_data_offset(compiler, ty)
        for shift in 0L..8L { ir_write_hex_escaped(compiler, ir, (literal.count() >> (shift * 8L)) & 255L) }
        const_image_zeros(compiler, ir, data_offset - 8L)
        for position in 0L..literal.count() { ir_write_hex_escaped(compiler, ir, literal[position].to_long()) }
        const_image_zeros(compiler, ir, size - data_offset - literal.count())
    } else if kind == TYPE_KIND_STRUCT {
        let record = type_record(compiler, ty)
        var position = 0L
        for offset in 0L..record.field_count {
            let field = record.field_start + offset
            let field_ty = compiler.struct_fields[field].ty
            let field_offset = compiler.struct_fields[field].offset
            const_image_zeros(compiler, ir, field_offset - position)
            let init = const_image_field_init(tables, compiler, node, field)
            let init_value = compiler.child_first[init]
            emit_const_image_bytes(source, tokens, files, tables, compiler, ir, file_index, init_value, field_ty)
            position = field_offset + value_type_size(compiler, field_ty)
        }
        const_image_zeros(compiler, ir, size - position)
    } else if kind == TYPE_KIND_ARRAY {
        let element = collection_element_type(compiler, ty)
        let stride = value_type_size(compiler, element)
        var item = compiler.child_first[node]
        var written = 0L
        for index in 0L..collection_capacity(compiler, ty) {
            emit_const_image_bytes(source, tokens, files, tables, compiler, ir, file_index, item, element)
            written += stride
            item = compiler.child_next[item]
        }
        const_image_zeros(compiler, ir, size - written)
    } else {
        // an empty list or map is all zero bytes
        const_image_zeros(compiler, ir, size)
    }
}

fn emit_image_constant_global(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    declaration: long,
) {
    let declared = compiler.facts[declaration].ty
    ir_write_ascii(compiler, ir, "@.nl.const."); ir_write_number(compiler, ir, declaration)
    ir_write_ascii(compiler, ir, " = private unnamed_addr constant ["); ir_write_number(compiler, ir, value_type_size(compiler, declared))
    ir_write_ascii(compiler, ir, " x i8] c\"")
    emit_const_image_bytes(source, tokens, files, tables, compiler, ir, node_file_index(tables.nodes, files, declaration), node_last_child(tables, compiler, declaration), declared)
    ir_write_ascii(compiler, ir, "\", align 8\n")
}

// Whether an array constant is written by emit_array_constant_global (int, long, byte or Ascii elements) rather than as an image.
fn const_is_simple_array(compiler: CompilerTables, declaration: long) -> bool {
    let declared = compiler.facts[declaration].ty
    if type_kind(compiler, declared) != TYPE_KIND_ARRAY { return false }
    let element = collection_element_type(compiler, declared)
    element == TY_INT || element == TY_LONG || element == TY_BYTE || type_kind(compiler, element) == TYPE_KIND_ASCII
}
