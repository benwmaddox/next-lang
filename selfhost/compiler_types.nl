// TYPE MODULE BEGIN: all type-table indexing and the stable type-id mapping lives here.
fn type_record(compiler: CompilerTables, type_id: long) -> TypeRecord {
    if type_id < 0L || type_id >= compiler.type_records.count() {
        return TypeRecord { kind_state: 3L, name_id: -1L, name_token: -1L, node: -1L, file: -1L, field_start: 0L, field_count: 0L, size: -1L, align: -1L, helper_mask: 0L }
    }
    compiler.type_records[type_id]
}

fn type_record_kind(record: TypeRecord) -> long { record.kind_state / 16L }
fn type_record_state(record: TypeRecord) -> long { record.kind_state % 16L }

fn is_sum_type_kind(kind: long) -> bool {
    kind == TYPE_KIND_ENUM || kind == TYPE_KIND_OPTION || kind == TYPE_KIND_RESULT
}

fn is_sum_type(compiler: CompilerTables, type_id: long) -> bool {
    is_sum_type_kind(type_kind(compiler, type_id))
}

fn sum_case_count(compiler: CompilerTables, type_id: long) -> long {
    if type_kind(compiler, type_id) == TYPE_KIND_ENUM { type_record(compiler, type_id).field_count }
    else if type_kind(compiler, type_id) == TYPE_KIND_OPTION || type_kind(compiler, type_id) == TYPE_KIND_RESULT { 2L }
    else { 0L }
}

fn sum_case_payload_count(compiler: CompilerTables, type_id: long, tag: long) -> long {
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_ENUM {
        let ty = type_record(compiler, type_id)
        if tag < 0L || tag >= ty.field_count { return -1L }
        compiler.enum_cases[ty.field_start + tag].payload_count
    } else if kind == TYPE_KIND_OPTION {
        if tag == 0L { 1L } else if tag == 1L { 0L } else { -1L }
    } else if kind == TYPE_KIND_RESULT {
        if tag == 0L || tag == 1L { 1L } else { -1L }
    } else { 0L }
}

fn sum_payload_record(compiler: CompilerTables, type_id: long, tag: long, part: long) -> EnumPayloadRecord {
    let kind = type_kind(compiler, type_id)
    let ty = type_record(compiler, type_id)
    let payload_index = if kind == TYPE_KIND_ENUM {
        let case = compiler.enum_cases[ty.field_start + tag]
        case.payload_start + part
    } else {
        ty.field_start + tag
    }
    if payload_index < 0L || payload_index >= compiler.enum_payloads.count() {
        return EnumPayloadRecord { case_index: -1L, type_node: -1L, ty: -1L, offset: 0L }
    }
    compiler.enum_payloads[payload_index]
}

fn sum_case_tag_for_name(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    compiler: CompilerTables,
    type_id: long,
    token: long,
) -> long {
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_OPTION {
        if token_is_word_at(source, tokens, files, file_index, token, "some") { 0L }
        else if token_is_word_at(source, tokens, files, file_index, token, "none") { 1L }
        else { -1L }
    } else if kind == TYPE_KIND_RESULT {
        if token_is_word_at(source, tokens, files, file_index, token, "ok") { 0L }
        else if token_is_word_at(source, tokens, files, file_index, token, "err") { 1L }
        else { -1L }
    } else { -1L }
}

// value_type_by_name[name] is the struct or enum type with that name, -1 if there is none and
// -2 if the name is declared more than once (a lookup then finds nothing).
fn index_value_type_name(compiler: write CompilerTables, record: TypeRecord, type_id: long) {
    let kind = type_record_kind(record)
    if (kind == TYPE_KIND_STRUCT || kind == TYPE_KIND_ENUM) && record.name_id >= 0L && record.name_id < compiler.value_type_by_name.count() {
        compiler.value_type_by_name[record.name_id] = if compiler.value_type_by_name[record.name_id] == -1L { type_id } else { -2L }
    }
}

fn append_type_record(compiler: write CompilerTables, record: TypeRecord) -> long {
    let type_id = compiler.type_records.count()
    compiler.type_records.push(record).unwrap()
    index_value_type_name(compiler, record, type_id)
    if type_record_kind(record) == TYPE_KIND_ENUM {
        compiler.enum_type_ids.push(type_id).unwrap()
        if record.name_id >= 0L && record.name_id < compiler.enum_type_by_name.count() {
            compiler.enum_type_by_name[record.name_id] = type_id
        }
    }
    type_id
}

fn struct_type_id(compiler: CompilerTables, struct_index: long) -> long {
    if struct_index < 0L { return -1L }
    var seen = 0L
    for type_id in 0L..compiler.type_records.count() {
        if type_record_kind(compiler.type_records[type_id]) == TYPE_KIND_STRUCT {
            if seen == struct_index { return type_id }
            seen += 1L
        }
    }
    -1L
}

fn struct_type_index(compiler: CompilerTables, type_id: long) -> long {
    var seen = 0L
    for index in 0L..compiler.type_records.count() {
        if type_record_kind(compiler.type_records[index]) == TYPE_KIND_STRUCT {
            if index == type_id { return seen }
            seen += 1L
        }
    }
    -1L
}

fn struct_record(compiler: CompilerTables, struct_index: long) -> TypeRecord {
    let type_id = struct_type_id(compiler, struct_index)
    type_record(compiler, type_id)
}

fn struct_type_count(compiler: CompilerTables) -> long {
    var item_count = 0L
    for type_id in 0L..compiler.type_records.count() {
        if type_record_kind(compiler.type_records[type_id]) == TYPE_KIND_STRUCT { item_count += 1L }
    }
    item_count
}

fn enum_type_id(compiler: CompilerTables, enum_index: long) -> long {
    if enum_index < 0L || enum_index >= compiler.enum_type_ids.count() { return -1L }
    compiler.enum_type_ids[enum_index]
}

fn enum_record(compiler: CompilerTables, enum_index: long) -> TypeRecord {
    let type_id = enum_type_id(compiler, enum_index)
    type_record(compiler, type_id)
}

fn enum_type_count(compiler: CompilerTables) -> long {
    compiler.enum_type_ids.count()
}

fn builtin_full_type_id(compiler: CompilerTables) -> long {
    for enum_index in 0L..enum_type_count(compiler) {
        let type_id = enum_type_id(compiler, enum_index)
        let record = type_record(compiler, type_id)
        if record.node < 0L && record.field_count == 1L &&
            compiler.enum_cases[record.field_start].name_id == record.name_id { return type_id }
    }
    -1L
}

fn enum_type_matches(compiler: CompilerTables, name_id: long) -> long {
    if name_id < 0L || name_id >= compiler.enum_type_by_name.count() { return -1L }
    compiler.enum_type_by_name[name_id]
}

fn enum_case_matches(compiler: CompilerTables, type_id: long, name_id: long) -> long {
    if type_id < 0L || type_id >= compiler.type_records.count() || type_record_kind(compiler.type_records[type_id]) != TYPE_KIND_ENUM { return -1L }
    let ty = type_record(compiler, type_id)
    for offset in 0L..ty.field_count {
        let case_index = ty.field_start + offset
        if compiler.enum_cases[case_index].name_id == name_id { return case_index }
    }
    -1L
}

fn enum_case_for_tag(compiler: CompilerTables, type_id: long, tag: long) -> long {
    if type_id < 0L || type_id >= compiler.type_records.count() || type_record_kind(compiler.type_records[type_id]) != TYPE_KIND_ENUM { return -1L }
    let ty = type_record(compiler, type_id)
    for offset in 0L..ty.field_count {
        let case_index = ty.field_start + offset
        if compiler.enum_cases[case_index].tag == tag { return case_index }
    }
    -1L
}

fn enum_case_payload_type(compiler: CompilerTables, case_index: long, payload_index: long) -> long {
    if case_index < 0L || case_index >= compiler.enum_cases.count() { return -1L }
    let case = compiler.enum_cases[case_index]
    if payload_index < 0L || payload_index >= case.payload_count { return -1L }
    compiler.enum_payloads[case.payload_start + payload_index].ty
}

fn enum_case_owner_type_id(compiler: CompilerTables, case_index: long) -> long {
    if case_index < 0L || case_index >= compiler.enum_cases.count() { return -1L }
    enum_type_id(compiler, compiler.enum_cases[case_index].owner)
}

fn value_type_matches(compiler: CompilerTables, name_id: long) -> long {
    if name_id < 0L || name_id >= compiler.value_type_by_name.count() { return -1L }
    let found = compiler.value_type_by_name[name_id]
    if found >= 0L { found } else { -1L }
}

fn value_type_for_node(compiler: CompilerTables, node: long) -> long {
    for type_id in 0L..compiler.type_records.count() {
        let kind = type_record_kind(compiler.type_records[type_id])
        if (kind == TYPE_KIND_STRUCT || kind == TYPE_KIND_ENUM) && compiler.type_records[type_id].node == node { return type_id }
    }
    -1L
}

// The case a bare name refers to when exactly one enum declares it: its case index, -1 when no
// enum has the case and -2 when several enums do. Answered from enum_case_by_name.
fn user_case_matches(compiler: CompilerTables, name_id: long) -> long {
    if name_id < 0L || name_id >= compiler.enum_case_by_name.count() { return -1L }
    compiler.enum_case_by_name[name_id]
}

// Records an appended enum case in enum_case_by_name: the first case with a name is kept, and a
// second enum declaring the same name makes it ambiguous (-2). Repeats inside one enum keep the first.
fn index_enum_case_at(compiler: write CompilerTables, case_index: long) {
    if case_index < 0L || case_index >= compiler.enum_cases.count() { return }
    let name_id = compiler.enum_cases[case_index].name_id
    if name_id < 0L || name_id >= compiler.enum_case_by_name.count() { return }
    let existing = compiler.enum_case_by_name[name_id]
    if existing == -1L { compiler.enum_case_by_name[name_id] = case_index }
    else if existing >= 0L && compiler.enum_cases[existing].owner != compiler.enum_cases[case_index].owner {
        compiler.enum_case_by_name[name_id] = -2L
    } else { () }
}

fn index_last_enum_case(compiler: write CompilerTables) {
    let last_case = compiler.enum_cases.count() - 1L
    index_enum_case_at(compiler, last_case)
}

fn type_kind(compiler: CompilerTables, type_id: long) -> long {
    type_record_kind(type_record(compiler, type_id))
}

fn type_state(compiler: CompilerTables, type_id: long) -> long {
    type_record_state(type_record(compiler, type_id))
}

fn type_count(compiler: CompilerTables) -> long { compiler.type_records.count() }

fn builtin_synthetic_type_id(compiler: CompilerTables, node_marker: long) -> long {
    for type_id in 0L..type_count(compiler) {
        if type_record(compiler, type_id).node == node_marker { return type_id }
    }
    -1L
}

fn type_helper_mask(compiler: CompilerTables, type_id: long) -> long {
    if type_id < 0L || type_id >= compiler.type_records.count() { return 0L }
    compiler.type_records[type_id].helper_mask
}

fn set_type_helper_mask(compiler: write CompilerTables, type_id: long, mask: long) {
    if type_id >= 0L && type_id < compiler.type_records.count() { compiler.type_records[type_id].helper_mask = mask }
}

fn is_aggregate_type(compiler: CompilerTables, type_id: long) -> bool {
    let kind = type_kind(compiler, type_id)
    kind == TYPE_KIND_STRUCT || kind == TYPE_KIND_ENUM || kind == TYPE_KIND_OPTION || kind == TYPE_KIND_RESULT ||
        kind == TYPE_KIND_ARRAY || collection_kind_is_list(kind) || kind == TYPE_KIND_ASCII || kind == TYPE_KIND_TEXT || kind == TYPE_KIND_BYTES || kind == TYPE_KIND_MAP
}

fn set_type_state(compiler: write CompilerTables, type_id: long, state: long) {
    if type_id >= 0L && type_id < compiler.type_records.count() {
        let kind = type_record_kind(compiler.type_records[type_id])
        compiler.type_records[type_id].kind_state = kind * 16L + state
    }
}

fn set_type_layout(compiler: write CompilerTables, type_id: long, size: long, align: long, state: long) {
    if type_id >= 0L && type_id < compiler.type_records.count() {
        compiler.type_records[type_id].size = size
        compiler.type_records[type_id].align = align
        set_type_state(compiler, type_id, state)
    }
}

fn generic_instance_matches(compiler: CompilerTables, type_id: long, kind: long, arg0: long, arg1: long) -> bool {
    if type_kind(compiler, type_id) != kind { return false }
    let record = type_record(compiler, type_id)
    if kind == TYPE_KIND_OPTION {
        record.field_count == 1L && compiler.enum_payloads[record.field_start].ty == arg0
    } else if kind == TYPE_KIND_RESULT {
        record.field_count == 2L && compiler.enum_payloads[record.field_start].ty == arg0 &&
            compiler.enum_payloads[record.field_start + 1L].ty == arg1
    } else { false }
}

fn layout_sum_instance(compiler: write CompilerTables, type_id: long) -> bool {
    let kind = type_kind(compiler, type_id)
    if kind != TYPE_KIND_OPTION && kind != TYPE_KIND_RESULT { return false }
    var max_end = 4L
    var alignment = 4L
    for tag in 0L..2L {
        var end = 4L
        let part_count = sum_case_payload_count(compiler, type_id, tag)
        for part in 0L..part_count {
            let payload = sum_payload_record(compiler, type_id, tag, part)
            let payload_size = value_type_size(compiler, payload.ty)
            let payload_align = value_type_align(compiler, payload.ty)
            if payload.ty >= 0L && type_state(compiler, payload.ty) == TYPE_STATE_LAYOUT_OVERFLOW {
                set_type_layout(compiler, type_id, -1L, alignment, TYPE_STATE_LAYOUT_OVERFLOW)
                return false
            }
            if payload_size < 0L || payload_align < 0L { return false }
            let offset = checked_layout_size_align(end, payload_align)
            if offset == -2L {
                set_type_layout(compiler, type_id, -1L, alignment, TYPE_STATE_LAYOUT_OVERFLOW)
                return false
            }
            if offset < 0L { return false }
            let record = type_record(compiler, type_id)
            let payload_index = record.field_start + tag
            compiler.enum_payloads[payload_index].offset = offset
            end = checked_layout_size_add(offset, payload_size)
            if end == -2L {
                set_type_layout(compiler, type_id, -1L, alignment, TYPE_STATE_LAYOUT_OVERFLOW)
                return false
            }
            if end < 0L { return false }
            if payload_align > alignment { alignment = payload_align }
        }
        if end > max_end { max_end = end }
    }
    let layout_size = checked_layout_size_align(max_end, alignment)
    if layout_size == -2L {
        set_type_layout(compiler, type_id, -1L, alignment, TYPE_STATE_LAYOUT_OVERFLOW)
        return false
    }
    if layout_size < 0L { return false }
    set_type_layout(compiler, type_id, layout_size, alignment, 2L)
    true
}

fn intern_sum_type(
    compiler: write CompilerTables,
    kind: long,
    arg0: long,
    arg1: long,
    file_index: long,
    node: long,
    name_id: long,
    name_token: long,
) -> long {
    if kind != TYPE_KIND_OPTION && kind != TYPE_KIND_RESULT { return -1L }
    for type_id in 0L..type_count(compiler) {
        if generic_instance_matches(compiler, type_id, kind, arg0, arg1) { return type_id }
    }
    let field_start = compiler.enum_payloads.count()
    compiler.enum_payloads.push(EnumPayloadRecord { case_index: 0L, type_node: -1L, ty: arg0, offset: 4L }).unwrap()
    var field_count = 1L
    if kind == TYPE_KIND_RESULT {
        compiler.enum_payloads.push(EnumPayloadRecord { case_index: 1L, type_node: -1L, ty: arg1, offset: 4L }).unwrap()
        field_count = 2L
    }
    let type_id = append_type_record(compiler, TypeRecord {
        kind_state: kind * 16L,
        name_id,
        name_token,
        node,
        file: file_index,
        field_start,
        field_count,
        size: 0L,
        align: 4L,
        helper_mask: 0L,
    })
    let _ = layout_sum_instance(compiler, type_id)
    type_id
}

fn struct_type_matches(compiler: CompilerTables, name_id: long) -> long {
    var found = -1L
    var struct_index = 0L
    for type_id in 0L..compiler.type_records.count() {
        if type_record_kind(compiler.type_records[type_id]) == TYPE_KIND_STRUCT {
            if compiler.type_records[type_id].name_id == name_id {
                if found >= 0L { return -1L }
                found = struct_index
            }
            struct_index += 1L
        }
    }
    found
}

fn struct_field_matches(compiler: CompilerTables, type_index: long, name_id: long) -> long {
    if type_index < 0L || type_index >= struct_type_count(compiler) { return -1L }
    let ty = struct_record(compiler, type_index)
    for offset in 0L..ty.field_count {
        let field_index = ty.field_start + offset
        if compiler.struct_fields[field_index].name_id == name_id { return field_index }
    }
    -1L
}

fn resolve_value_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
) -> long {
    if node >= 0L && node < compiler.facts.count() &&
        (compiler.facts[node].flags & FACT_RESOLVED_TYPE) != 0L {
        return compiler.facts[node].ty
    }
    let syntax = tables.nodes[node]
    if (syntax.flags & FLAG_TYPE_UNIT) != 0L { return TY_UNIT }
    if syntax.kind == NodeKind.ResultType && token_is_word_at(source, tokens, files, file_index, syntax.token, "never") { return TY_NEVER }
    if compiler.core_mode && syntax.meta0 == 2L &&
        token_is_word_at(source, tokens, files, file_index, tables.extra[syntax.extra], "sys") &&
        token_is_word_at(source, tokens, files, file_index, tables.extra[syntax.extra + 1L], "Addr") { return TY_ADDR }
    if token_is_word_at(source, tokens, files, file_index, syntax.token, "int") { return TY_INT }
    if token_is_word_at(source, tokens, files, file_index, syntax.token, "long") { return TY_LONG }
    if token_is_word_at(source, tokens, files, file_index, syntax.token, "bool") { return TY_BOOL }
    if token_is_word_at(source, tokens, files, file_index, syntax.token, "byte") { return TY_BYTE }
    if compiler.c_runtime && token_is_word_at(source, tokens, files, file_index, syntax.token, "Env") { return TY_ENV }
    if compiler.c_runtime && token_is_word_at(source, tokens, files, file_index, syntax.token, "Fs") { return TY_FS }
    if compiler.c_runtime && token_is_word_at(source, tokens, files, file_index, syntax.token, "Out") { return TY_OUT }
    if compiler.c_runtime && token_is_word_at(source, tokens, files, file_index, syntax.token, "Args") { return TY_ARGS }
    if compiler.c_runtime && token_is_word_at(source, tokens, files, file_index, syntax.token, "Arg") { return TY_ARG }
    if compiler.c_runtime && token_is_word_at(source, tokens, files, file_index, syntax.token, "Path") {
        return collection_type_matches(compiler, TYPE_KIND_LIST, TY_BYTE, 4096L)
    }
    if syntax.token < 0L { return -1L }
    let name_id = compiler.token_name_ids[syntax.token]
    let type_id = value_type_matches(compiler, name_id)
    if type_id >= 0L { return type_id }
    alias_target_type(tables, compiler, name_id)
}

// The type a `type Name = ...` alias stands for, or -1 while its target is unresolved.
fn alias_target_type(tables: ParseTables, compiler: CompilerTables, name_id: long) -> long {
    for candidate in 0L..tables.nodes.count() {
        if tables.nodes[candidate].kind != NodeKind.TypeAlias { continue }
        if compiler.token_name_ids[tables.nodes[candidate].token] != name_id { continue }
        let target = compiler.child_first[candidate]
        if target >= 0L && (compiler.facts[target].flags & FACT_RESOLVED_TYPE) != 0L { return compiler.facts[target].ty }
        return -1L
    }
    -1L
}

fn generic_type_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    file_index: long,
    node: long,
) -> long {
    let token = tables.nodes[node].token
    if token_is_word_at(source, tokens, files, file_index, token, "Option") { TYPE_KIND_OPTION }
    else if token_is_word_at(source, tokens, files, file_index, token, "Result") { TYPE_KIND_RESULT }
    else { 0L }
}

fn sum_type_syntax_shape(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    file_index: long,
    node: long,
) -> bool {
    let syntax = tables.nodes[node]
    let kind = generic_type_kind(source, tokens, files, tables, file_index, node)
    let expected_args = if kind == TYPE_KIND_OPTION { 1L } else if kind == TYPE_KIND_RESULT { 2L } else { 0L }
    expected_args > 0L && (syntax.meta1 & 2097151L) == expected_args &&
        ((syntax.meta1 >> 21L) & 2097151L) == 0L &&
        ((syntax.meta1 >> 42L) & 2097151L) == 0L &&
        (syntax.flags & FLAG_RANGE) == 0L
}

fn sum_case_payload_type(compiler: CompilerTables, type_id: long, tag: long, part: long) -> long {
    let item_count = sum_case_payload_count(compiler, type_id, tag)
    if part < 0L || part >= item_count { return -1L }
    sum_payload_record(compiler, type_id, tag, part).ty
}

// One sweep over the written types; returns whether it resolved a new node. A use of an alias
// resolves only once the alias target has, so intern_written_type_instances repeats it.
fn intern_written_type_pass(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
) -> bool {
    var progressed = false
    for node in 0L..tables.nodes.count() {
        let syntax = tables.nodes[node]
        if !is_type_node(syntax.kind) { continue }
        if (compiler.facts[node].flags & FACT_RESOLVED_TYPE) != 0L { continue }
        let file_index = node_file_index(tables.nodes, files, node)
        var ty = -1L
        if (syntax.flags & FLAG_TYPE_UNIT) != 0L { ty = TY_UNIT }
        else if syntax.kind == NodeKind.ResultType &&
            token_is_word_at(source, tokens, files, file_index, syntax.token, "never") { ty = TY_NEVER }
        else {
            let collection_type = intern_collection_type_syntax(env, source, tokens, files, tables, compiler, file_index, node)
            if collection_type >= 0L { ty = collection_type }
            if ty < 0L {
                ty = intern_text_type_syntax(env, source, tokens, files, tables, compiler, file_index, node)
            }
            let generic_kind = generic_type_kind(source, tokens, files, tables, file_index, node)
            let expected_args = if generic_kind == TYPE_KIND_OPTION { 1L } else if generic_kind == TYPE_KIND_RESULT { 2L } else { 0L }
            let has_only_type_args = (syntax.meta1 & 2097151L) == expected_args &&
                ((syntax.meta1 >> 21L) & 2097151L) == 0L &&
                ((syntax.meta1 >> 42L) & 2097151L) == 0L && (syntax.flags & FLAG_RANGE) == 0L
            if ty < 0L && expected_args > 0L && (syntax.meta1 & 2097151L) == expected_args && has_only_type_args {
                let first = compiler.child_first[node]
                let second = if first >= 0L { compiler.child_next[first] } else { -1L }
                if first >= 0L && (compiler.facts[first].flags & FACT_RESOLVED_TYPE) != 0L &&
                    (expected_args == 1L || (second >= 0L && (compiler.facts[second].flags & FACT_RESOLVED_TYPE) != 0L)) {
                    let arg0 = compiler.facts[first].ty
                    let arg1 = if expected_args == 2L { compiler.facts[second].ty } else { -1L }
                    let generic_name_id = compiler.token_name_ids[syntax.token]
                    let generic_name_token = syntax.token
                    ty = intern_sum_type(compiler, generic_kind, arg0, arg1, file_index, node,
                        generic_name_id, generic_name_token)
                }
            }
            if ty < 0L && expected_args == 0L && generic_kind == 0L {
                ty = resolve_value_type(source, tokens, files, tables, compiler, file_index, node)
            }
        }
        if ty >= 0L {
            compiler.facts[node] = NodeFact { ty, flags: FACT_RESOLVED_TYPE, binding: -1L, function: -1L, literal: 0L }
            progressed = true
        }
    }
    progressed
}

fn intern_written_type_instances(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for pass in 0L..MAX_TYPE_ALIAS_PASSES {
        if !intern_written_type_pass(env, source, tokens, files, tables, compiler) { break }
    }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.Fit {
            let value_node = compiler.child_first[node]
            let target_node = if value_node >= 0L { compiler.child_next[value_node] } else { -1L }
            if target_node >= 0L {
                let target_ty = compiler.facts[target_node].ty
                if type_kind(compiler, target_ty) == TYPE_KIND_ASCII || target_ty == TY_BYTE {
                    let _fit_option_type = intern_sum_type(compiler, TYPE_KIND_OPTION, target_ty, -1L,
                        node_file_index(tables.nodes, files, node), node, -1L, -1L)
                }
            }
        }
    }
}


// E3a1 begin: exact struct layout sizing replaces E2's 4,097-byte cap.
fn size_add_saturated(left: long, right: long) -> long {
    if left >= MAX_VALUE_SIZE || right >= MAX_VALUE_SIZE || left > MAX_VALUE_SIZE - right { MAX_VALUE_SIZE }
    else { left + right }
}

fn size_align_saturated(value: long, align: long) -> long {
    if value >= MAX_VALUE_SIZE || align <= 1L { value }
    else {
        let remainder = value % align
        if remainder == 0L { value }
        else { size_add_saturated(value, align - remainder) }
    }
}
// E3a1 end

fn value_type_size(compiler: CompilerTables, ty: long) -> long {
    if ty < 0L || ty >= compiler.type_records.count() { return -1L }
    let record = type_record(compiler, ty)
    if type_record_state(record) == 2L { record.size } else { -1L }
}

fn value_type_align(compiler: CompilerTables, ty: long) -> long {
    if ty < 0L || ty >= compiler.type_records.count() { return -1L }
    let record = type_record(compiler, ty)
    if type_record_state(record) == 2L { record.align } else { -1L }
}

fn mark_reserved_name(compiler: write CompilerTables, name_id: long) {
    if name_id >= 0L && name_id < compiler.reserved_names.count() {
        compiler.reserved_names[name_id] = true
    }
}

fn check_package_name_shadows(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for file_index in 0L..files.count() {
        let first = files[file_index].first_token
        let last = first + files[file_index].token_count
        for token in first..last {
            if tokens[token].kind == TokenKind.Ident && builtin_case_name(source, tokens, files, file_index, token) {
                let name_id = compiler.token_name_ids[token]
                mark_reserved_name(compiler, name_id)
            }
        }
    }
    for case_index in 0L..compiler.enum_cases.count() {
        let name_id = compiler.enum_cases[case_index].name_id
        if name_id >= 0L && name_id < compiler.enum_case_name_counts.count() {
            compiler.enum_case_name_counts[name_id] += 1L
        }
    }
    for case_index in 0L..compiler.enum_cases.count() {
        let name_id = compiler.enum_cases[case_index].name_id
        if name_id >= 0L && name_id < compiler.enum_case_name_counts.count() {
            mark_reserved_name(compiler, name_id)
        }
    }
    for node in 0L..tables.nodes.count() {
        let syntax = tables.nodes[node]
        if syntax.kind != NodeKind.Let && syntax.kind != NodeKind.Parameter && syntax.kind != NodeKind.For && syntax.kind != NodeKind.PatternBinding { continue }
        let name_id = compiler.token_name_ids[syntax.token]
        if name_id >= 0L && name_id < compiler.reserved_names.count() && compiler.reserved_names[name_id] {
            let file_index = node_file_index(tables.nodes, files, node)
            fail_name_shadow_error(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token, "bare enum case", -1L)
        }
        if is_shadowed_function_value(tables, compiler, node, name_id) {
            let file_index = node_file_index(tables.nodes, files, node)
            fail_name_shadow_error(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token, "visible declaration", -1L)
        }
    }
}

fn index_package_enums(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    if compiler.c_runtime { intern_builtin_io_types(env, source, files, tokens, compiler) }
    for file_index in 0L..files.count() {
        let root = files[file_index].tree_root
        var child = compiler.child_first[root]
        for step in 0L..tables.nodes[root].subtree {
            if child < 0L { break }
            if tables.nodes[child].kind == NodeKind.Enum {
                let syntax = tables.nodes[child]
                let enum_index = enum_type_count(compiler)
                let case_start = compiler.enum_cases.count()
                var case_node = compiler.child_first[child]
                for case_step in 0L..syntax.subtree {
                    if case_node < 0L { break }
                    if tables.nodes[case_node].kind == NodeKind.EnumCase {
                        let case_syntax = tables.nodes[case_node]
                        let payload_start = compiler.enum_payloads.count()
                        var payload_node = compiler.child_first[case_node]
                        for payload_step in 0L..case_syntax.subtree {
                            if payload_node < 0L { break }
                            if tables.nodes[payload_node].kind == NodeKind.PayloadType {
                                compiler.enum_payloads.push(EnumPayloadRecord { case_index: compiler.enum_cases.count(), type_node: payload_node, ty: -1L, offset: 0L }).unwrap()
                            }
                            payload_node = compiler.child_next[payload_node]
                        }
                        compiler.enum_cases.push(EnumCaseRecord {
                            owner: enum_index,
                            name_id: compiler.token_name_ids[case_syntax.token],
                            name_token: case_syntax.token,
                            node: case_node,
                            payload_start,
                            payload_count: compiler.enum_payloads.count() - payload_start,
                            tag: compiler.enum_cases.count() - case_start,
                        }).unwrap()
                        index_last_enum_case(compiler)
                    }
                    case_node = compiler.child_next[case_node]
                }
                let _ = append_type_record(compiler, TypeRecord {
                    kind_state: TYPE_KIND_ENUM * 16L,
                    name_id: compiler.token_name_ids[syntax.token],
                    name_token: syntax.token,
                    node: child,
                    file: file_index,
                    field_start: case_start,
                    field_count: compiler.enum_cases.count() - case_start,
                    size: 0L,
                    align: 4L,
                    helper_mask: 0L,
                })
            }
            child = compiler.child_next[child]
        }
    }
}

fn append_builtin_io_type(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: write CompilerTables,
    record: TypeRecord,
) -> long {
    let type_id = compiler.type_records.count()
    match compiler.type_records.push(record) {
        ok(_) => (),
        err(_) => fail_parse_limit(env, files[0].name, "C-runtime built-in type table capacity exceeded"),
    }
    index_value_type_name(compiler, record, type_id)
    if type_record_kind(record) == TYPE_KIND_ENUM {
        match compiler.enum_type_ids.push(type_id) {
            ok(_) => (),
            err(_) => fail_parse_limit(env, files[0].name, "C-runtime enum table capacity exceeded"),
        }
        if record.name_id >= 0L && record.name_id < compiler.enum_type_by_name.count() {
            compiler.enum_type_by_name[record.name_id] = type_id
        }
    }
    type_id
}

fn intern_builtin_io_enum_case(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: write CompilerTables,
    owner: long,
    case_name_id: long,
    case_token: long,
    tag: long,
    payload_type: long,
) {
    let payload_start = compiler.enum_payloads.count()
    if payload_type >= 0L {
        let payload = EnumPayloadRecord {
            case_index: compiler.enum_cases.count(),
            type_node: -1L,
            ty: payload_type,
            offset: 0L,
        }
        match compiler.enum_payloads.push(payload) {
            ok(_) => (),
            err(_) => fail_parse_limit(env, files[0].name, "C-runtime enum payload table capacity exceeded"),
        }
    }
    let case_record = EnumCaseRecord {
        owner,
        name_id: case_name_id,
        name_token: case_token,
        node: -4L,
        payload_start,
        payload_count: compiler.enum_payloads.count() - payload_start,
        tag,
    }
    match compiler.enum_cases.push(case_record) {
        ok(_) => (),
        err(_) => fail_parse_limit(env, files[0].name, "C-runtime enum case table capacity exceeded"),
    }
    index_last_enum_case(compiler)
}

fn intern_builtin_io_types(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
) {
    let io_error_token = find_builtin_word_token(source, files, tokens, "IoError")
    let io_error_name = if io_error_token >= 0L { compiler.token_name_ids[io_error_token] } else { -110L }
    let io_error_owner = enum_type_count(compiler)
    let io_error_start = compiler.enum_cases.count()
    let not_found_token = find_builtin_word_token(source, files, tokens, "NotFound")
    let no_permission_token = find_builtin_word_token(source, files, tokens, "NoPermission")
    let too_large_token = find_builtin_word_token(source, files, tokens, "TooLarge")
    let too_many_token = find_builtin_word_token(source, files, tokens, "TooMany")
    let name_too_long_token = find_builtin_word_token(source, files, tokens, "NameTooLong")
    let bad_path_token = find_builtin_word_token(source, files, tokens, "BadPath")
    let outside_token = find_builtin_word_token(source, files, tokens, "Outside")
    let other_token = find_builtin_word_token(source, files, tokens, "Other")
    let invalid_utf8_token = find_builtin_word_token(source, files, tokens, "InvalidUtf8")
    intern_builtin_io_enum_case(env, files, compiler, io_error_owner, if not_found_token >= 0L { compiler.token_name_ids[not_found_token] } else { -111L }, not_found_token, 0L, -1L)
    intern_builtin_io_enum_case(env, files, compiler, io_error_owner, if no_permission_token >= 0L { compiler.token_name_ids[no_permission_token] } else { -112L }, no_permission_token, 1L, -1L)
    intern_builtin_io_enum_case(env, files, compiler, io_error_owner, if too_large_token >= 0L { compiler.token_name_ids[too_large_token] } else { -113L }, too_large_token, 2L, -1L)
    intern_builtin_io_enum_case(env, files, compiler, io_error_owner, if too_many_token >= 0L { compiler.token_name_ids[too_many_token] } else { -114L }, too_many_token, 3L, -1L)
    intern_builtin_io_enum_case(env, files, compiler, io_error_owner, if name_too_long_token >= 0L { compiler.token_name_ids[name_too_long_token] } else { -115L }, name_too_long_token, 4L, -1L)
    intern_builtin_io_enum_case(env, files, compiler, io_error_owner, if bad_path_token >= 0L { compiler.token_name_ids[bad_path_token] } else { -116L }, bad_path_token, 5L, -1L)
    intern_builtin_io_enum_case(env, files, compiler, io_error_owner, if outside_token >= 0L { compiler.token_name_ids[outside_token] } else { -117L }, outside_token, 6L, -1L)
    intern_builtin_io_enum_case(env, files, compiler, io_error_owner, if other_token >= 0L { compiler.token_name_ids[other_token] } else { -118L }, other_token, 7L, TY_INT)
    intern_builtin_io_enum_case(env, files, compiler, io_error_owner, if invalid_utf8_token >= 0L { compiler.token_name_ids[invalid_utf8_token] } else { -119L }, invalid_utf8_token, 8L, -1L)
    let _io_error_type = append_builtin_io_type(env, files, compiler, TypeRecord {
        kind_state: TYPE_KIND_ENUM * 16L,
        name_id: io_error_name,
        name_token: io_error_token,
        node: -4L,
        file: 0L,
        field_start: io_error_start,
        field_count: 9L,
        size: 0L,
        align: 4L,
        helper_mask: 0L,
    })

    let file_kind_token = find_builtin_word_token(source, files, tokens, "FileKind")
    let file_kind_name = if file_kind_token >= 0L { compiler.token_name_ids[file_kind_token] } else { -120L }
    let file_kind_owner = enum_type_count(compiler)
    let file_kind_start = compiler.enum_cases.count()
    let file_token = find_builtin_word_token(source, files, tokens, "File")
    let directory_token = find_builtin_word_token(source, files, tokens, "Directory")
    intern_builtin_io_enum_case(env, files, compiler, file_kind_owner, if file_token >= 0L { compiler.token_name_ids[file_token] } else { -121L }, file_token, 0L, -1L)
    intern_builtin_io_enum_case(env, files, compiler, file_kind_owner, if directory_token >= 0L { compiler.token_name_ids[directory_token] } else { -122L }, directory_token, 1L, -1L)
    intern_builtin_io_enum_case(env, files, compiler, file_kind_owner, if other_token >= 0L { compiler.token_name_ids[other_token] } else { -123L }, other_token, 2L, -1L)
    let _file_kind_type = append_builtin_io_type(env, files, compiler, TypeRecord {
        kind_state: TYPE_KIND_ENUM * 16L,
        name_id: file_kind_name,
        name_token: file_kind_token,
        node: -5L,
        file: 0L,
        field_start: file_kind_start,
        field_count: 3L,
        size: 0L,
        align: 4L,
        helper_mask: 0L,
    })

    let path_token = find_builtin_word_token(source, files, tokens, "Path")
    let path_name = if path_token >= 0L { compiler.token_name_ids[path_token] } else { -124L }
    let existing_path_type = collection_type_matches(compiler, TYPE_KIND_LIST, TY_BYTE, 4096L)
    let _path_type = if existing_path_type >= 0L { existing_path_type } else {
        append_builtin_io_type(env, files, compiler, TypeRecord {
            kind_state: TYPE_KIND_LIST * 16L,
            name_id: path_name,
            name_token: path_token,
            node: -6L,
            file: 0L,
            field_start: TY_BYTE,
            field_count: 4096L,
            size: 0L,
            align: 1L,
            helper_mask: 0L,
        })
    }

    let entry_token = find_builtin_word_token(source, files, tokens, "DirEntry")
    let entry_name = if entry_token >= 0L { compiler.token_name_ids[entry_token] } else { -125L }
    let path_type = collection_type_matches(compiler, TYPE_KIND_LIST, TY_BYTE, 4096L)
    let file_kind_type = builtin_synthetic_type_id(compiler, -5L)
    let fields_start = compiler.struct_fields.count()
    let name_token = find_builtin_word_token(source, files, tokens, "name")
    let kind_token = find_builtin_word_token(source, files, tokens, "kind")
    let name_field = StructFieldRecord {
        owner: struct_type_count(compiler),
        name_id: if name_token >= 0L { compiler.token_name_ids[name_token] } else { -126L },
        name_token,
        node: -7L,
        type_node: -1L,
        ty: path_type,
        offset: 0L,
        default_node: -1L,
    }
    match compiler.struct_fields.push(name_field) {
        ok(_) => (),
        err(_) => fail_parse_limit(env, files[0].name, "C-runtime struct field table capacity exceeded"),
    }
    let kind_field = StructFieldRecord {
        owner: struct_type_count(compiler),
        name_id: if kind_token >= 0L { compiler.token_name_ids[kind_token] } else { -127L },
        name_token: kind_token,
        node: -7L,
        type_node: -1L,
        ty: file_kind_type,
        offset: 16392L,
        default_node: -1L,
    }
    match compiler.struct_fields.push(kind_field) {
        ok(_) => (),
        err(_) => fail_parse_limit(env, files[0].name, "C-runtime struct field table capacity exceeded"),
    }
    let _entry_type = append_builtin_io_type(env, files, compiler, TypeRecord {
        kind_state: TYPE_KIND_STRUCT * 16L + 2L,
        name_id: entry_name,
        name_token: entry_token,
        node: -7L,
        file: 0L,
        field_start: fields_start,
        field_count: 2L,
        size: 16400L,
        align: 8L,
        helper_mask: 0L,
    })
}

fn intern_builtin_full(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
) {
    var token = -1L
    var file_index = 0L
    for candidate_file in 0L..files.count() {
        let first = files[candidate_file].first_token
        let last = first + files[candidate_file].token_count
        for candidate in first..last {
            if token_is_word_at(source, tokens, files, candidate_file, candidate, "Full") {
                token = candidate
                file_index = candidate_file
                break
            }
        }
        if token >= 0L { break }
    }
    let name_id = if token >= 0L { compiler.token_name_ids[token] } else { -1L }
    if token >= 0L && enum_type_matches(compiler, name_id) >= 0L { return }
    let enum_index = enum_type_count(compiler)
    let case_start = compiler.enum_cases.count()
    compiler.enum_cases.push(EnumCaseRecord {
        owner: enum_index,
        name_id,
        name_token: token,
        node: -1L,
        payload_start: compiler.enum_payloads.count(),
        payload_count: 0L,
        tag: 0L,
    }).unwrap()
    index_last_enum_case(compiler)
    let _ = append_type_record(compiler, TypeRecord {
        kind_state: TYPE_KIND_ENUM * 16L + 2L,
        name_id,
        name_token: token,
        node: -1L,
        file: file_index,
        field_start: case_start,
        field_count: 1L,
        size: 4L,
        align: 4L,
        helper_mask: 0L,
    })
}

fn find_builtin_word_token(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    word: Ascii max 32,
) -> long {
    for file_index in 0L..files.count() {
        let first = files[file_index].first_token
        let last = first + files[file_index].token_count
        for token in first..last {
            if token_is_word_at(source, tokens, files, file_index, token, word) { return token }
        }
    }
    -1L
}

fn intern_builtin_text_types(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
) {
    var utf8_error_token = find_builtin_word_token(source, files, tokens, "Utf8Error")
    var valid_up_to_token = find_builtin_word_token(source, files, tokens, "valid_up_to")
    let invalid_utf8_token = find_builtin_word_token(source, files, tokens, "InvalidUtf8")
    let non_ascii_token = find_builtin_word_token(source, files, tokens, "NonAscii")
    var text_error_token = find_builtin_word_token(source, files, tokens, "TextError")
    var text_error_file = 0L
    var utf8_error_file = 0L
    if text_error_token >= 0L {
        for file_index in 0L..files.count() {
            if text_error_token >= files[file_index].first_token && text_error_token < files[file_index].first_token + files[file_index].token_count { text_error_file = file_index }
        }
    }
    if utf8_error_token >= 0L {
        for file_index in 0L..files.count() {
            if utf8_error_token >= files[file_index].first_token && utf8_error_token < files[file_index].first_token + files[file_index].token_count { utf8_error_file = file_index }
        }
    }
    if text_error_token < 0L { text_error_token = -1L }
    if utf8_error_token < 0L { utf8_error_token = -1L }
    if valid_up_to_token < 0L { valid_up_to_token = -1L }
    let text_error_name = if text_error_token >= 0L { compiler.token_name_ids[text_error_token] } else { -103L }
    let utf8_error_name = if utf8_error_token >= 0L { compiler.token_name_ids[utf8_error_token] } else { -102L }
    let invalid_utf8_name = if invalid_utf8_token >= 0L { compiler.token_name_ids[invalid_utf8_token] } else { -104L }
    let non_ascii_name = if non_ascii_token >= 0L { compiler.token_name_ids[non_ascii_token] } else { -105L }
    if enum_type_matches(compiler, text_error_name) < 0L {
        let enum_index = enum_type_count(compiler)
        let case_start = compiler.enum_cases.count()
        compiler.enum_cases.push(EnumCaseRecord { owner: enum_index, name_id: invalid_utf8_name, name_token: invalid_utf8_token, node: -2L, payload_start: compiler.enum_payloads.count(), payload_count: 0L, tag: 0L }).unwrap()
        compiler.enum_cases.push(EnumCaseRecord { owner: enum_index, name_id: non_ascii_name, name_token: non_ascii_token, node: -2L, payload_start: compiler.enum_payloads.count(), payload_count: 0L, tag: 1L }).unwrap()
        let builtin_case_start = compiler.enum_cases.count() - 2L
        index_enum_case_at(compiler, builtin_case_start)
        index_last_enum_case(compiler)
        let _text_error_type = append_type_record(compiler, TypeRecord {
            kind_state: TYPE_KIND_ENUM * 16L + 2L,
            name_id: text_error_name,
            name_token: text_error_token,
            node: -2L,
            file: text_error_file,
            field_start: case_start,
            field_count: 2L,
            size: 4L,
            align: 4L,
            helper_mask: 0L,
        })
    }
    var have_utf8 = false
    for type_id in 0L..type_count(compiler) {
        if compiler.type_records[type_id].node == -3L { have_utf8 = true }
    }
    if !have_utf8 {
        let struct_index = struct_type_count(compiler)
        let field_start = compiler.struct_fields.count()
        compiler.struct_fields.push(StructFieldRecord {
            owner: struct_index,
            name_id: if valid_up_to_token >= 0L { compiler.token_name_ids[valid_up_to_token] } else { -106L },
            name_token: valid_up_to_token,
            node: -3L,
            type_node: -1L,
            ty: TY_LONG,
            offset: 0L,
            default_node: -1L,
        }).unwrap()
        compiler.type_records.push(TypeRecord {
            kind_state: TYPE_KIND_STRUCT * 16L + 2L,
            name_id: utf8_error_name,
            name_token: utf8_error_token,
            node: -3L,
            file: utf8_error_file,
            field_start,
            field_count: 1L,
            size: 8L,
            align: 8L,
            helper_mask: 0L,
        }).unwrap()
    }
}

fn index_package_structs(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for file_index in 0L..files.count() {
        let root = files[file_index].tree_root
        var child = compiler.child_first[root]
        for step in 0L..tables.nodes[root].subtree {
            if child < 0L { break }
            if tables.nodes[child].kind == NodeKind.Struct {
                let syntax = tables.nodes[child]
                let type_index = struct_type_count(compiler)
                let field_start = compiler.struct_fields.count()
                var field = compiler.child_first[child]
                for field_step in 0L..syntax.subtree {
                    if field < 0L { break }
                    if tables.nodes[field].kind == NodeKind.StructField {
                        let field_syntax = tables.nodes[field]
                        let type_node = compiler.child_first[field]
                        let default_node = if type_node >= 0L { compiler.child_next[type_node] } else { -1L }
                        compiler.struct_fields.push(StructFieldRecord {
                            owner: type_index,
                            name_id: compiler.token_name_ids[field_syntax.token],
                            name_token: field_syntax.token,
                            node: field,
                            type_node,
                            ty: -1L,
                            offset: 0L,
                            default_node: if default_node >= 0L { default_node } else { -1L },
                        }).unwrap()
                    }
                    field = compiler.child_next[field]
                }
                let _ = append_type_record(compiler, TypeRecord {
                    kind_state: TYPE_KIND_STRUCT * 16L,
                    name_id: compiler.token_name_ids[syntax.token],
                    name_token: syntax.token,
                    node: child,
                    file: file_index,
                    field_start,
                    field_count: compiler.struct_fields.count() - field_start,
                    size: 0L,
                    align: 1L,
                    helper_mask: 0L,
                })
            }
            child = compiler.child_next[child]
        }
    }
}

fn initial_type_walk_frame(compiler: CompilerTables, type_id: long) -> TypeWalkFrame {
    if is_sum_type(compiler, type_id) {
        TypeWalkFrame { type_index: type_id, field_index: 0L, size: 4L, align: 4L, case_index: 0L, max_size: 4L }
    } else {
        TypeWalkFrame { type_index: type_id, field_index: 0L, size: 0L, align: 1L, case_index: 0L, max_size: 0L }
    }
}

fn size_package_types(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    compiler.type_walk.clear()
    for root_type in 0L..type_count(compiler) {
        let root_kind = type_kind(compiler, root_type)
        if root_kind != TYPE_KIND_STRUCT && !is_sum_type(compiler, root_type) &&
            root_kind != TYPE_KIND_ARRAY && !collection_kind_is_list(root_kind) { continue }
        if type_state(compiler, root_type) != 0L { continue }
        set_type_state(compiler, root_type, 1L)
        compiler.type_walk.push(initial_type_walk_frame(compiler, root_type)).unwrap()
        for walk_step in 0L..MAX_TREE_NODES {
            if compiler.type_walk.count() == 0L { break }
            let frame_index = compiler.type_walk.count() - 1L
            var frame = compiler.type_walk[frame_index]
            let type_info = type_record(compiler, frame.type_index)
            let frame_kind = type_kind(compiler, frame.type_index)
            if frame_kind == TYPE_KIND_ARRAY || collection_kind_is_list(frame_kind) {
                if frame_kind == TYPE_KIND_ARRAY && type_info.field_count == 0L {
                    // A zero-length array has no element storage. Preserve the
                    // Stage0 layout even when the unused element layout would
                    // overflow on its own.
                    set_type_layout(compiler, frame.type_index, 0L, 1L, 2L)
                    let _ = compiler.type_walk.pop()
                    continue
                }
                let element_ty = type_info.field_start
                let element_size = value_type_size(compiler, element_ty)
                let element_align = value_type_align(compiler, element_ty)
                if element_size < 0L || element_align < 0L {
                    let element_kind = type_kind(compiler, element_ty)
                    if element_ty >= 0L && type_state(compiler, element_ty) == TYPE_STATE_LAYOUT_OVERFLOW {
                        set_type_layout(compiler, frame.type_index, -1L, 1L, TYPE_STATE_LAYOUT_OVERFLOW)
                        let _ = compiler.type_walk.pop()
                        continue
                    }
                    if (element_kind == TYPE_KIND_STRUCT || is_sum_type(compiler, element_ty) || element_kind == TYPE_KIND_ARRAY || collection_kind_is_list(element_kind)) && type_state(compiler, element_ty) == 0L {
                        set_type_state(compiler, element_ty, 1L)
                        compiler.type_walk.push(initial_type_walk_frame(compiler, element_ty)).unwrap()
                        continue
                    }
                    set_type_state(compiler, frame.type_index, if type_state(compiler, element_ty) == 1L || type_state(compiler, element_ty) == 4L { 4L } else { 3L })
                    let _ = compiler.type_walk.pop()
                    continue
                }
                let size = type_group_size(compiler, frame.type_index, 1L)
                let alignment = if collection_kind_is_list(frame_kind) && element_align < 8L { 8L }
                    else { element_align }
                if size == -2L {
                    set_type_layout(compiler, frame.type_index, -1L, alignment, TYPE_STATE_LAYOUT_OVERFLOW)
                } else if size < 0L || size >= MAX_VALUE_SIZE {
                    set_type_layout(compiler, frame.type_index, MAX_VALUE_SIZE, alignment, 2L)
                } else { set_type_layout(compiler, frame.type_index, size, alignment, 2L) }
                let _ = compiler.type_walk.pop()
                continue
            }
            if frame_kind == TYPE_KIND_STRUCT {
                if frame.field_index >= type_info.field_count {
                    let layout_size = checked_layout_size_align(frame.size, frame.align)
                    if layout_size == -2L { set_type_layout(compiler, frame.type_index, -1L, frame.align, TYPE_STATE_LAYOUT_OVERFLOW) }
                    else if layout_size < 0L { set_type_state(compiler, frame.type_index, 3L) }
                    else { set_type_layout(compiler, frame.type_index, layout_size, frame.align, 2L) }
                    let _ = compiler.type_walk.pop()
                    continue
                }
                let field_index = type_info.field_start + frame.field_index
                let field = compiler.struct_fields[field_index]
                let ty = resolve_value_type(source, tokens, files, tables, compiler, type_info.file, field.type_node)
                compiler.struct_fields[field_index].ty = ty
                let field_size = value_type_size(compiler, ty)
                let field_align = value_type_align(compiler, ty)
                if field_size < 0L || field_align < 0L {
                    if ty >= 0L && type_state(compiler, ty) == TYPE_STATE_LAYOUT_OVERFLOW {
                        set_type_layout(compiler, frame.type_index, -1L, frame.align, TYPE_STATE_LAYOUT_OVERFLOW)
                        let _ = compiler.type_walk.pop()
                        continue
                    }
                    let child_kind = type_kind(compiler, ty)
                    if (child_kind == TYPE_KIND_STRUCT || is_sum_type(compiler, ty) || child_kind == TYPE_KIND_ARRAY || collection_kind_is_list(child_kind)) && type_state(compiler, ty) == 0L {
                        set_type_state(compiler, ty, 1L)
                        compiler.type_walk.push(initial_type_walk_frame(compiler, ty)).unwrap()
                        continue
                    }
                    set_type_state(compiler, frame.type_index, if type_state(compiler, ty) == 1L || type_state(compiler, ty) == 4L { 4L } else { 3L })
                    let _ = compiler.type_walk.pop()
                    continue
                }
                let offset = checked_layout_size_align(frame.size, field_align)
                if offset == -2L {
                    set_type_layout(compiler, frame.type_index, -1L, frame.align, TYPE_STATE_LAYOUT_OVERFLOW)
                    let _ = compiler.type_walk.pop()
                    continue
                }
                if offset < 0L {
                    set_type_state(compiler, frame.type_index, 3L)
                    let _ = compiler.type_walk.pop()
                    continue
                }
                compiler.struct_fields[field_index].offset = offset
                frame.size = checked_layout_size_add(offset, field_size)
                if frame.size == -2L {
                    set_type_layout(compiler, frame.type_index, -1L, frame.align, TYPE_STATE_LAYOUT_OVERFLOW)
                    let _ = compiler.type_walk.pop()
                    continue
                }
                if frame.size < 0L {
                    set_type_state(compiler, frame.type_index, 3L)
                    let _ = compiler.type_walk.pop()
                    continue
                }
                if field_align > frame.align { frame.align = field_align }
                frame.field_index += 1L
                compiler.type_walk[frame_index] = frame
            } else {
                let kind = type_kind(compiler, frame.type_index)
                let case_count = sum_case_count(compiler, frame.type_index)
                if frame.field_index >= case_count {
                    let layout_size = checked_layout_size_align(frame.max_size, frame.align)
                    if layout_size == -2L { set_type_layout(compiler, frame.type_index, -1L, frame.align, TYPE_STATE_LAYOUT_OVERFLOW) }
                    else if layout_size < 0L { set_type_state(compiler, frame.type_index, 3L) }
                    else { set_type_layout(compiler, frame.type_index, layout_size, frame.align, 2L) }
                    let _ = compiler.type_walk.pop()
                    continue
                }
                let part_count = sum_case_payload_count(compiler, frame.type_index, frame.field_index)
                if frame.case_index >= part_count {
                    if frame.size > frame.max_size { frame.max_size = frame.size }
                    frame.field_index += 1L
                    frame.case_index = 0L
                    frame.size = 4L
                    compiler.type_walk[frame_index] = frame
                    continue
                }
                let payload_index = if kind == TYPE_KIND_ENUM {
                    let case_index = type_info.field_start + frame.field_index
                    compiler.enum_cases[case_index].payload_start + frame.case_index
                } else {
                    type_info.field_start + frame.field_index
                }
                let payload = compiler.enum_payloads[payload_index]
                let ty = if payload.type_node >= 0L {
                    resolve_value_type(source, tokens, files, tables, compiler, type_info.file, payload.type_node)
                } else { payload.ty }
                compiler.enum_payloads[payload_index].ty = ty
                let payload_size = value_type_size(compiler, ty)
                let payload_align = value_type_align(compiler, ty)
                if payload_size < 0L || payload_align < 0L {
                    if ty >= 0L && type_state(compiler, ty) == TYPE_STATE_LAYOUT_OVERFLOW {
                        set_type_layout(compiler, frame.type_index, -1L, frame.align, TYPE_STATE_LAYOUT_OVERFLOW)
                        let _ = compiler.type_walk.pop()
                        continue
                    }
                    if (type_kind(compiler, ty) == TYPE_KIND_STRUCT || is_sum_type(compiler, ty) || type_kind(compiler, ty) == TYPE_KIND_ARRAY || collection_kind_is_list(type_kind(compiler, ty))) && type_state(compiler, ty) == 0L {
                        set_type_state(compiler, ty, 1L)
                        compiler.type_walk.push(initial_type_walk_frame(compiler, ty)).unwrap()
                        continue
                    }
                    set_type_state(compiler, frame.type_index, if type_state(compiler, ty) == 1L || type_state(compiler, ty) == 4L { 4L } else { 3L })
                    let _ = compiler.type_walk.pop()
                    continue
                }
                let offset = checked_layout_size_align(frame.size, payload_align)
                if offset == -2L {
                    set_type_layout(compiler, frame.type_index, -1L, frame.align, TYPE_STATE_LAYOUT_OVERFLOW)
                    let _ = compiler.type_walk.pop()
                    continue
                }
                if offset < 0L {
                    set_type_state(compiler, frame.type_index, 3L)
                    let _ = compiler.type_walk.pop()
                    continue
                }
                compiler.enum_payloads[payload_index].offset = offset
                frame.size = checked_layout_size_add(offset, payload_size)
                if frame.size == -2L {
                    set_type_layout(compiler, frame.type_index, -1L, frame.align, TYPE_STATE_LAYOUT_OVERFLOW)
                    let _ = compiler.type_walk.pop()
                    continue
                }
                if frame.size < 0L {
                    set_type_state(compiler, frame.type_index, 3L)
                    let _ = compiler.type_walk.pop()
                    continue
                }
                if payload_align > frame.align { frame.align = payload_align }
                frame.case_index += 1L
                compiler.type_walk[frame_index] = frame
            }
        }
        if compiler.type_walk.count() > 0L {
            set_type_state(compiler, root_type, 3L)
            compiler.type_walk.clear()
        }
    }
}

// E3a1 begin: shared compiler integration.
fn type_node_is_oversized(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    file_index: long,
) -> bool {
    let ty = resolve_value_type(source, tokens, files, tables, compiler, file_index, node)
    if !is_aggregate_type(compiler, ty) { return false }
    // Exact-MAX layouts are representable. Defer their unsupported-large
    // decision until after bodies have had a chance to diagnose derived
    // result layouts that overflow when they add headers or sum tags.
    value_type_size(compiler, ty) > MAX_VALUE_SIZE
}

fn sum_layout_has_invalid_overflow(compiler: CompilerTables, type_id: long) -> bool {
    if type_id < 0L || type_id >= type_count(compiler) { return true }
    type_state(compiler, type_id) == TYPE_STATE_LAYOUT_OVERFLOW || value_type_size(compiler, type_id) < 0L
}

fn check_deferred_large_value_gate(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
) {
    var hit = UnsupportedHit { found: false, file: 0L, node: -1L, offset: 0L, category: 0L, token: -1L }
    for type_id in 0L..type_count(compiler) {
        let record = type_record(compiler, type_id)
        if type_record_state(record) != 2L || record.size != MAX_VALUE_SIZE ||
            record.file < 0L || record.file >= files.count() ||
            record.node < 0L || record.node >= tables.nodes.count() {
            continue
        }
        let node = record.node
        let start = tables.nodes[node].start
        let is_earlier = !hit.found || record.file < hit.file ||
            (record.file == hit.file && (start < hit.offset ||
                (start == hit.offset && (tables.nodes[node].end > tables.nodes[hit.node].end ||
                    (tables.nodes[node].end == tables.nodes[hit.node].end && node > hit.node)))))
        if is_earlier {
            hit = UnsupportedHit { found: true, file: record.file, node,
                offset: start, category: UNSUPPORTED_LARGE_VALUE, token: tables.nodes[node].token }
        }
    }
    if hit.found { report_unsupported(env, source, files, tokens, tables, compiler, hit) }
}
// E3a1 end
// TYPE MODULE END


// Range aliases (type Slot = long 0..=512) are supported only as cast targets so far: a cast
// checks the range at run time and the value then has the plain base type. range_alias_names
// marks every alias whose chain ends in a written range, so uses elsewhere can be refused.
fn mark_range_aliases(tables: ParseTables, compiler: write CompilerTables) {
    for pass in 0L..MAX_TYPE_ALIAS_PASSES {
        var changed = false
        for node in 0L..tables.nodes.count() {
            if tables.nodes[node].kind != NodeKind.TypeAlias { continue }
            let name_id = compiler.token_name_ids[tables.nodes[node].token]
            if name_id < 0L || compiler.range_alias_names[name_id] { continue }
            let target = compiler.child_first[node]
            if target < 0L { continue }
            let syntax = tables.nodes[target]
            if (syntax.flags & FLAG_RANGE) != 0L || type_node_uses_range_alias(compiler, syntax) {
                compiler.range_alias_names[name_id] = true
                changed = true
            }
        }
        if !changed { break }
    }
}

// A plain written name that is a range alias.
fn type_node_uses_range_alias(compiler: CompilerTables, syntax: Node) -> bool {
    if syntax.flags != 0L || syntax.meta0 != 1L || syntax.meta1 != 0L || syntax.token < 0L { return false }
    let name_id = compiler.token_name_ids[syntax.token]
    name_id >= 0L && name_id < compiler.range_alias_names.count() && compiler.range_alias_names[name_id]
}

// The type node that carries the written range for this type (itself, or the target of the
// alias chain it names), or -1 when the type has no range.
fn written_type_range_node(tables: ParseTables, compiler: CompilerTables, type_node: long) -> long {
    var node = type_node
    for step in 0L..MAX_TYPE_ALIAS_PASSES {
        let syntax = tables.nodes[node]
        if (syntax.flags & FLAG_RANGE) != 0L { return node }
        if !type_node_uses_range_alias(compiler, syntax) { return -1L }
        let name_id = compiler.token_name_ids[syntax.token]
        var next = -1L
        for candidate in 0L..tables.nodes.count() {
            if tables.nodes[candidate].kind == NodeKind.TypeAlias && compiler.token_name_ids[tables.nodes[candidate].token] == name_id {
                next = compiler.child_first[candidate]
                break
            }
        }
        if next < 0L { return -1L }
        node = next
    }
    -1L
}

// A written bound of a range type: which is 0 for the lower bound, 1 for the upper bound. The
// magnitudes are 128-bit; supported ranges fit a signed 64-bit value (see range_node_supported).
fn range_bound_value(tables: ParseTables, range_node: long, which: long) -> long {
    let base = tables.nodes[range_node].anchor + which * 2L
    let magnitude = tables.literals[tables.extra[base]]
    let value = magnitude.limb1 * 4294967296L + magnitude.limb0
    let bound = if tables.extra[base + 1L] != 0L { 0L - value } else { value }
    if which == 1L && (tables.nodes[range_node].flags & FLAG_RANGE_INCLUSIVE) == 0L { bound - 1L } else { bound }
}

// Whether a written range is one the compiler handles: int or long base, no wrap or clamp
// policy, bounds that fit the base type, lower bound not above the upper bound.
fn range_node_supported(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    file_index: long,
    range_node: long,
) -> bool {
    let syntax = tables.nodes[range_node]
    if (syntax.flags & (FLAG_POLICY_WRAP | FLAG_POLICY_CLAMP)) != 0L { return false }
    if syntax.meta0 != 1L || syntax.meta1 != 0L { return false }
    let is_int = token_is_word_at(source, tokens, files, file_index, syntax.token, "int")
    if !is_int && !token_is_word_at(source, tokens, files, file_index, syntax.token, "long") { return false }
    for which in 0L..2L {
        let magnitude = tables.literals[tables.extra[syntax.anchor + which * 2L]]
        if magnitude.limb2 != 0L || magnitude.limb3 != 0L || magnitude.limb1 > 2147483647L { return false }
        if is_int && (magnitude.limb1 != 0L || magnitude.limb0 > 2147483647L) { return false }
    }
    range_bound_value(tables, range_node, 0L) <= range_bound_value(tables, range_node, 1L)
}

// The helper masks only gain flags, so an unchanged total means nothing was registered.
fn type_helper_mask_sum(compiler: CompilerTables) -> long {
    var total = 0L
    for type_id in 0L..type_count(compiler) { total += type_helper_mask(compiler, type_id) }
    total
}
