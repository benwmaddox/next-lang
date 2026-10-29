fn deferred_text_kind(kind: long) -> bool {
    kind == TYPE_KIND_ASCII || kind == TYPE_KIND_TEXT || kind == TYPE_KIND_BYTES
}

recursive fn deferred_text_type_contains_collection(
    compiler: CompilerTables,
    type_id: long,
    under_collection: bool,
    depth: long,
    states: write list<byte, TYPE_TABLE_CAPACITY * 2L>,
) -> long {
    if type_id < 0L || type_id >= type_count(compiler) { return 0L }
    // Keep the existing recursion bound, but do not cache a truncated path as
    // a complete negative result. A later, shallower root can still inspect it.
    if depth > 256L { return -1L }
    let state_index = type_id * 2L + if under_collection { 1L } else { 0L }
    if state_index < 0L || state_index >= states.count() { return -1L }
    let previous = states[state_index]
    if previous == 3 { return 1L }
    if previous == 2 || previous == 1 { return 0L }
    states[state_index] = 1
    let kind = type_kind(compiler, type_id)
    if deferred_text_kind(kind) {
        if under_collection { states[state_index] = 3; return 1L }
        states[state_index] = 2
        return 0L
    }
    var unresolved = false
    if kind == TYPE_KIND_ARRAY || kind == TYPE_KIND_LIST {
        let element_type = collection_element_type(compiler, type_id)
        if !under_collection && type_kind(compiler, element_type) == TYPE_KIND_STRUCT {
            // A collection of records may carry bounded Bytes in its direct
            // fields. Keep every other text-bearing path gated, including
            // nested records, collections, and sum payloads.
            let element = type_record(compiler, element_type)
            for field_offset in 0L..element.field_count {
                let field_type = compiler.struct_fields[element.field_start + field_offset].ty
                if type_kind(compiler, field_type) == TYPE_KIND_BYTES { continue }
                let found = deferred_text_type_contains_collection(
                    compiler, field_type, true, depth + 1L, states)
                if found > 0L { states[state_index] = 3; return 1L }
                if found < 0L { unresolved = true }
            }
        } else {
            let found = deferred_text_type_contains_collection(
                compiler, element_type, true, depth + 1L, states)
            if found > 0L { states[state_index] = 3; return 1L }
            if found < 0L { unresolved = true }
        }
    } else if kind == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        for field_offset in 0L..record.field_count {
            let found = deferred_text_type_contains_collection(
                compiler, compiler.struct_fields[record.field_start + field_offset].ty,
                under_collection, depth + 1L, states)
            if found > 0L { states[state_index] = 3; return 1L }
            if found < 0L { unresolved = true }
        }
    } else if kind == TYPE_KIND_ENUM {
        let record = type_record(compiler, type_id)
        for case_offset in 0L..record.field_count {
            let case = compiler.enum_cases[record.field_start + case_offset]
            for part in 0L..case.payload_count {
                let found = deferred_text_type_contains_collection(
                    compiler, compiler.enum_payloads[case.payload_start + part].ty,
                    under_collection, depth + 1L, states)
                if found > 0L { states[state_index] = 3; return 1L }
                if found < 0L { unresolved = true }
            }
        }
    } else if kind == TYPE_KIND_OPTION || kind == TYPE_KIND_RESULT {
        for tag in 0L..sum_case_count(compiler, type_id) {
            for part in 0L..sum_case_payload_count(compiler, type_id, tag) {
                let payload_type = sum_case_payload_type(compiler, type_id, tag, part)
                let found = deferred_text_type_contains_collection(
                    compiler, payload_type,
                    under_collection, depth + 1L, states)
                if found > 0L { states[state_index] = 3; return 1L }
                if found < 0L { unresolved = true }
            }
        }
    } else { () }
    if unresolved { states[state_index] = 0; -1L }
    else { states[state_index] = 2; 0L }
}

fn populate_deferred_text_collection_states(
    compiler: CompilerTables,
    states: write list<byte, TYPE_TABLE_CAPACITY * 2L>,
) {
    states.clear()
    for index in 0L..type_count(compiler) * 2L { states.push(0).unwrap() }
    for type_id in 0L..type_count(compiler) {
        let _ = deferred_text_type_contains_collection(compiler, type_id, false, 0L, states)
    }
}

fn type_has_deferred_text_collection(
    compiler: CompilerTables,
    type_id: long,
    states: list<byte, TYPE_TABLE_CAPACITY * 2L>,
) -> bool {
    if type_id < 0L || type_id >= type_count(compiler) { return false }
    let state_index = type_id * 2L
    state_index < states.count() && states[state_index] == 3
}

fn syntax_has_deferred_text_collection(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    states: list<byte, TYPE_TABLE_CAPACITY * 2L>,
    file_index: long,
    node: long,
) -> bool {
    let type_id = resolve_value_type(source, tokens, files, tables, compiler, file_index, node)
    type_id >= 0L && type_has_deferred_text_collection(compiler, type_id, states)
}

fn is_ascii_append_assignment(op: long, target_type: long, compiler: CompilerTables) -> bool {
    op == 1L && type_kind(compiler, target_type) == TYPE_KIND_ASCII
}
