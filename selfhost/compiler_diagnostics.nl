fn fail_name_shadow_error(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    token: long,
    category: Ascii max 64,
    previous_line: long,
) -> never {
    let file = files[file_index]
    let position = position_for_offset(file_index, file.base + offset, compiler)
    match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: name '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, file.base, token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"' conflicts with ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(category.bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b" '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, file.base, token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"'") { ok(_) => (), err(_) => env.exit(3) }
    if previous_line > 0L {
        match env.err.write(b" declared on line ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(previous_line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    }
    match env.err.write(b"; choose a different name") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_ambiguous_enum_case(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    token: long,
) -> never {
    fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, offset, "case '", token, "' belongs to more than one enum; qualify it with the enum name")
}

fn fail_unknown_enum_case(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    token: long,
    filter_enum: long,
) -> never {
    let wanted_length = tokens[token].length
    var candidate = NameCandidate { token: -1L, file: -1L, distance: 3L, length: 0L }
    for enum_index in 0L..enum_type_count(compiler) {
        if filter_enum >= 0L && enum_type_id(compiler, enum_index) != filter_enum { continue }
        let ty = enum_record(compiler, enum_index)
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            let length = tokens[case.name_token].length
            let distance = identifier_distance(source, tokens, files, file_index, token, ty.file, case.name_token)
            let threshold = if wanted_length > length { wanted_length / 3L + 1L } else { length / 3L + 1L }
            if distance <= 2L && distance <= threshold && (candidate.token < 0L || distance < candidate.distance || (distance == candidate.distance && length < candidate.length)) {
                candidate = NameCandidate { token: case.name_token, file: ty.file, distance, length }
            }
        }
    }
    let position = position_for_offset(file_index, files[file_index].base + offset, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: unknown enum case '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[file_index].base, token) { ok(_) => (), err(_) => env.exit(3) }
    if candidate.token >= 0L {
        match env.err.write(b"'; did you mean '") { ok(_) => (), err(_) => env.exit(3) }
        match write_token_raw(env.err, source, tokens, files[candidate.file].base, candidate.token) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"'") { ok(_) => (), err(_) => env.exit(3) }
    } else {
        match env.err.write(b"'; qualify it with its enum name") { ok(_) => (), err(_) => env.exit(3) }
    }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_enum_constructor_arity(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
    case_index: long,
    actual: long,
) -> never {
    let case = compiler.enum_cases[case_index]
    let ty = enum_record(compiler, case.owner)
    let node_info = tables.nodes[node]
    let anchor = if node_info.kind == NodeKind.QualifiedCase { tokens[tables.extra[node_info.extra]].start } else { node_info.start }
    let position = position_for_offset(file_index, files[file_index].base + anchor, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: case '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b".") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, case.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"' takes ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(case.payload_count).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b" payload value(s), but got ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(actual).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_enum_case_needs_payload(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
    enum_index: long,
    case_index: long,
) -> never {
    let case = compiler.enum_cases[case_index]
    let ty = enum_record(compiler, enum_index)
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].anchor, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: case '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b".") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, case.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"' needs ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(case.payload_count).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b" payload value(s)") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_match_case_arity(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    pattern: long,
    type_id: long,
    case_index: long,
    actual: long,
) -> never {
    let case = compiler.enum_cases[case_index]
    let position = position_for_offset(file_index, files[file_index].base + tokens[tables.nodes[pattern].token].start, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: case '") { ok(_) => (), err(_) => env.exit(3) }
    let ty = type_record(compiler, type_id)
    match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b".") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, case.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"' has ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(case.payload_count).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b" payload part(s), but this pattern names ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(actual).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_match_duplicate_case(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    arm: long,
    type_id: long,
    case_index: long,
) -> never {
    let case = compiler.enum_cases[case_index]
    let ty = type_record(compiler, type_id)
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[arm].start, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: unreachable duplicate pattern '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b".") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, case.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"'; remove this arm\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_match_qualifier(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    pattern: long,
    matched_type: long,
) -> never {
    let qualifier = tables.nodes[pattern].extra
    let case_token = tables.nodes[pattern].token
    let position = position_for_offset(file_index, files[file_index].base + tokens[tables.nodes[pattern].token].start, compiler)
    let matched = type_record(compiler, matched_type)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: pattern '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[file_index].base, qualifier) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b".") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[file_index].base, case_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"' does not match ") { ok(_) => (), err(_) => env.exit(3) }
    if matched.name_token >= 0L { match write_token_raw(env.err, source, tokens, files[matched.file].base, matched.name_token) { ok(_) => (), err(_) => env.exit(3) } }
    else { match env.err.write(scalar_type_name(matched_type).bytes()) { ok(_) => (), err(_) => env.exit(3) } }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn match_prior_pattern(
    tables: ParseTables,
    compiler: CompilerTables,
    match_node: long,
    stop_arm: long,
    pattern_kind: long,
    literal: long,
) -> bool {
    let scrutinee = compiler.child_first[match_node]
    var arm = if scrutinee >= 0L { compiler.child_next[scrutinee] } else { -1L }
    for step in 0L..tables.nodes[match_node].subtree {
        if arm < 0L || arm == stop_arm { break }
        let pattern = compiler.child_first[arm]
        if pattern >= 0L && compiler.facts[pattern].flags == pattern_kind &&
            (pattern_kind == MATCH_PATTERN_CASE || pattern_kind == MATCH_PATTERN_INTEGER || pattern_kind == MATCH_PATTERN_BOOL) &&
            compiler.facts[pattern].literal == literal { return true }
        arm = compiler.child_next[arm]
    }
    false
}

fn match_has_prior_wildcard(tables: ParseTables, compiler: CompilerTables, match_node: long, stop_arm: long) -> bool {
    let scrutinee = compiler.child_first[match_node]
    var arm = if scrutinee >= 0L { compiler.child_next[scrutinee] } else { -1L }
    for step in 0L..tables.nodes[match_node].subtree {
        if arm < 0L || arm == stop_arm { break }
        let pattern = compiler.child_first[arm]
        if pattern >= 0L && compiler.facts[pattern].flags == MATCH_PATTERN_WILDCARD { return true }
        arm = compiler.child_next[arm]
    }
    false
}

fn match_covered_count(tables: ParseTables, compiler: CompilerTables, match_node: long, pattern_kind: long) -> long {
    let scrutinee = compiler.child_first[match_node]
    var arm = if scrutinee >= 0L { compiler.child_next[scrutinee] } else { -1L }
    var item_count = 0L
    for step in 0L..tables.nodes[match_node].subtree {
        if arm < 0L { break }
        let pattern = compiler.child_first[arm]
        if pattern >= 0L && compiler.facts[pattern].flags == pattern_kind { item_count += 1L }
        arm = compiler.child_next[arm]
    }
    item_count
}

fn write_type_name(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    type_id: long,
) {
    let ty = type_record(compiler, type_id)
    if ty.name_token >= 0L { match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) } }
    else { match env.err.write(scalar_type_name(type_id).bytes()) { ok(_) => (), err(_) => env.exit(3) } }
}

fn fail_match_arm_type(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    arm: long,
    first_type: long,
    second_type: long,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[arm].start, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: match arms have different types: ") { ok(_) => (), err(_) => env.exit(3) }
    write_type_name(env, source, files, tokens, compiler, first_type)
    match env.err.write(b" and ") { ok(_) => (), err(_) => env.exit(3) }
    write_type_name(env, source, files, tokens, compiler, second_type)
    match env.err.write(b"; make reachable arms return the same type\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_match_scalar_duplicate(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    arm: long,
    value: long,
    is_bool: bool,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[arm].start, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: unreachable duplicate pattern '") { ok(_) => (), err(_) => env.exit(3) }
    if is_bool {
        if value == 1L { match env.err.write(b"true") { ok(_) => (), err(_) => env.exit(3) } }
        else { match env.err.write(b"false") { ok(_) => (), err(_) => env.exit(3) } }
    } else { match env.err.write(str(value).bytes()) { ok(_) => (), err(_) => env.exit(3) } }
    match env.err.write(b"'; remove this arm\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_match_requires_supported_type(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    match_node: long,
    type_id: long,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[match_node].start, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: match requires an enum, Option, Result, int, long, byte, a numeric refinement, or bool; found ") { ok(_) => (), err(_) => env.exit(3) }
    write_type_name(env, source, files, tokens, compiler, type_id)
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_match_exhaustiveness(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    match_node: long,
    matched_type: long,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[match_node].start, compiler)
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    if type_kind(compiler, matched_type) == TYPE_KIND_ENUM {
        match env.err.write(b": error: non-exhaustive match; missing ") { ok(_) => (), err(_) => env.exit(3) }
        let type_info = type_record(compiler, matched_type)
        var wrote_case = false
        for case_offset in 0L..type_info.field_count {
            let case_index = type_info.field_start + case_offset
            let case = compiler.enum_cases[case_index]
            if match_prior_pattern(tables, compiler, match_node, -1L, MATCH_PATTERN_CASE, case.tag) { continue }
            if wrote_case { match env.err.write(b", ") { ok(_) => (), err(_) => env.exit(3) } }
            match write_token_raw(env.err, source, tokens, files[type_info.file].base, type_info.name_token) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b".") { ok(_) => (), err(_) => env.exit(3) }
            match write_token_raw(env.err, source, tokens, files[type_info.file].base, case.name_token) { ok(_) => (), err(_) => env.exit(3) }
            wrote_case = true
        }
    } else if matched_type == TY_BOOL {
        match env.err.write(b": error: non-exhaustive bool match; missing ") { ok(_) => (), err(_) => env.exit(3) }
        var wrote_bool = false
        if !match_prior_pattern(tables, compiler, match_node, -1L, MATCH_PATTERN_BOOL, 1L) {
            match env.err.write(b"true") { ok(_) => (), err(_) => env.exit(3) }
            wrote_bool = true
        }
        if !match_prior_pattern(tables, compiler, match_node, -1L, MATCH_PATTERN_BOOL, 0L) {
            if wrote_bool { match env.err.write(b" and ") { ok(_) => (), err(_) => env.exit(3) } }
            match env.err.write(b"false") { ok(_) => (), err(_) => env.exit(3) }
        }
    } else {
        match env.err.write(b": error: integer matches need a '_' catch-all arm") { ok(_) => (), err(_) => env.exit(3) }
    }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_missing_struct_field(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    type_index: long,
    field_index: long,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + offset, compiler)
    let ty = struct_record(compiler, type_index)
    let field = compiler.struct_fields[field_index]
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: missing required field '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[file_index].base, field.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"' in ") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b" literal; give it a value") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn fail_unknown_struct_field(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    type_index: long,
    field_token: long,
    is_literal: bool,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + offset, compiler)
    let ty = struct_record(compiler, type_index)
    let wanted_length = tokens[field_token].length
    var candidate = NameCandidate { token: -1L, file: -1L, distance: 3L, length: 0L }
    for field_offset in 0L..ty.field_count {
        let field = compiler.struct_fields[ty.field_start + field_offset]
        let length = tokens[field.name_token].length
        let distance = identifier_distance(source, tokens, files, file_index, field_token, ty.file, field.name_token)
        let threshold = if wanted_length > length { wanted_length / 3L + 1L } else { length / 3L + 1L }
        if distance <= 2L && distance <= threshold && (candidate.token < 0L || distance < candidate.distance || (distance == candidate.distance && length < candidate.length)) {
            candidate = NameCandidate { token: field.name_token, file: ty.file, distance, length }
        }
    }
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: unknown field '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[file_index].base, field_token) { ok(_) => (), err(_) => env.exit(3) }
    if is_literal {
        match env.err.write(b"' in ") { ok(_) => (), err(_) => env.exit(3) }
        match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b" literal") { ok(_) => (), err(_) => env.exit(3) }
    } else {
        match env.err.write(b"' on ") { ok(_) => (), err(_) => env.exit(3) }
        match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) }
    }
    if candidate.token >= 0L {
        match env.err.write(b"; did you mean '") { ok(_) => (), err(_) => env.exit(3) }
        match write_token_raw(env.err, source, tokens, files[candidate.file].base, candidate.token) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"'") { ok(_) => (), err(_) => env.exit(3) }
    }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}


// An alias whose target stayed unresolved after the type sweeps names a type that does not
// exist, or is part of a cycle. Only plain names are reported here; targets that are
// unsupported forms (maps, ranges) keep their "not supported yet" diagnostics.
fn check_type_alias_targets(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
) {
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind != NodeKind.TypeAlias { continue }
        let target = compiler.child_first[node]
        if target < 0L || (compiler.facts[target].flags & FACT_RESOLVED_TYPE) != 0L { continue }
        let syntax = tables.nodes[target]
        if syntax.flags != 0L || syntax.meta0 != 1L || syntax.meta1 != 0L { continue }
        let file_index = node_file_index(tables.nodes, files, target)
        if known_non_scalar_type(source, tokens, files, file_index, syntax.token) { continue }
        fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start,
            "unknown type in alias '", tables.nodes[node].token, "'; declare the base type first")
    }
}

// A text or bytes literal longer than the type it initialises (stage 0's wording).
fn fail_text_literal_too_long(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    is_bytes: bool,
    length: long,
    capacity: long,
) -> never {
    let file = files[file_index]
    let position = position_for_offset(file_index, file.base + offset, compiler)
    match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    if is_bytes {
        match env.err.write(b": error: byte literal has ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(length).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b" bytes, exceeding Bytes max ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(capacity).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"; increase the byte maximum") { ok(_) => (), err(_) => env.exit(3) }
    } else {
        match env.err.write(b": error: ASCII literal does not fit Ascii max ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(capacity).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"; increase its byte maximum") { ok(_) => (), err(_) => env.exit(3) }
    }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}
