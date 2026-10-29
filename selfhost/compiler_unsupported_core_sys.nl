fn is_core_addr_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
) -> bool {
    if !compiler.core_mode || tables.nodes[node].meta0 != 2L { return false }
    let first = tables.extra[tables.nodes[node].extra]
    let second = tables.extra[tables.nodes[node].extra + 1L]
    token_is_word_at(source, tokens, files, file_index, first, "sys") &&
        token_is_word_at(source, tokens, files, file_index, second, "Addr")
}

fn is_top_level_function(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> bool {
    for parent in 0L..tables.nodes.count() {
        if tables.nodes[parent].kind != NodeKind.Program { continue }
        var child = compiler.child_first[parent]
        for step in 0L..tables.nodes.count() {
            if child < 0L { break }
            if child == node { return true }
            child = compiler.child_next[child]
        }
    }
    false
}

fn is_core_sys_receiver(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    file_index: long,
) -> bool {
    if !compiler.core_mode { return false }
    let receiver = compiler.child_first[node]
    receiver >= 0L && tables.nodes[receiver].kind == NodeKind.Name &&
        token_is_word_at(source, tokens, files, file_index, tables.nodes[receiver].token, "sys")
}

fn core_sys_operation(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    token: long,
) -> long {
    if token_is_word_at(source, tokens, files, file_index, token, "null") { SYS_NULL }
    else if token_is_word_at(source, tokens, files, file_index, token, "is_null") { SYS_IS_NULL }
    else if token_is_word_at(source, tokens, files, file_index, token, "offset") { SYS_OFFSET }
    else if token_is_word_at(source, tokens, files, file_index, token, "distance") { SYS_DISTANCE }
    else if token_is_word_at(source, tokens, files, file_index, token, "from_raw") { SYS_FROM_RAW }
    else if token_is_word_at(source, tokens, files, file_index, token, "load8") { SYS_LOAD8 }
    else if token_is_word_at(source, tokens, files, file_index, token, "load32") { SYS_LOAD32 }
    else if token_is_word_at(source, tokens, files, file_index, token, "load64") { SYS_LOAD64 }
    else if token_is_word_at(source, tokens, files, file_index, token, "load_addr") { SYS_LOAD_ADDR }
    else if token_is_word_at(source, tokens, files, file_index, token, "store8") { SYS_STORE8 }
    else if token_is_word_at(source, tokens, files, file_index, token, "store32") { SYS_STORE32 }
    else if token_is_word_at(source, tokens, files, file_index, token, "store64") { SYS_STORE64 }
    else if token_is_word_at(source, tokens, files, file_index, token, "store_addr") { SYS_STORE_ADDR }
    else if token_is_word_at(source, tokens, files, file_index, token, "lit") { SYS_LIT }
    else if token_is_word_at(source, tokens, files, file_index, token, "state") { SYS_STATE }
    else if token_is_word_at(source, tokens, files, file_index, token, "is_error") { SYS_IS_ERROR }
    else if token_is_word_at(source, tokens, files, file_index, token, "copy_forward_bulk") { SYS_COPY_FORWARD_BULK }
    else if token_is_word_at(source, tokens, files, file_index, token, "fill_bulk") { SYS_FILL_BULK }
    else if token_is_word_at(source, tokens, files, file_index, token, "repeat_byte") { SYS_REPEAT_BYTE }
    else if token_is_word_at(source, tokens, files, file_index, token, "copy_16") { SYS_COPY_16 }
    else if token_is_word_at(source, tokens, files, file_index, token, "fill_16") { SYS_FILL_16 }
    // E3a1 begin
    else if token_is_word_at(source, tokens, files, file_index, token, "context_offset") { SYS_CONTEXT_OFFSET }
    else if token_is_word_at(source, tokens, files, file_index, token, "context_size") { SYS_CONTEXT_SIZE }
    else if token_is_word_at(source, tokens, files, file_index, token, "context") { SYS_CONTEXT }
    else if token_is_word_at(source, tokens, files, file_index, token, "is_test_build") { SYS_IS_TEST_BUILD }
    else if token_is_word_at(source, tokens, files, file_index, token, "stack_addr") { SYS_STACK_ADDR }
    else if token_is_word_at(source, tokens, files, file_index, token, "stack_load8") { SYS_STACK_LOAD8 }
    else if token_is_word_at(source, tokens, files, file_index, token, "stack_store8") { SYS_STACK_STORE8 }
    else if token_is_word_at(source, tokens, files, file_index, token, "remap") { SYS_REMAP }
    else if token_is_word_at(source, tokens, files, file_index, token, "unmap") { SYS_UNMAP }
    else if token_is_word_at(source, tokens, files, file_index, token, "clock_gettime") { SYS_CLOCK_GETTIME }
    // E3a1 end
    else if token_is_word_at(source, tokens, files, file_index, token, "write") { SYS_WRITE }
    else if token_is_word_at(source, tokens, files, file_index, token, "exit_group") { SYS_EXIT_GROUP }
    else if token_is_word_at(source, tokens, files, file_index, token, "map") { SYS_MAP }
    else if token_is_word_at(source, tokens, files, file_index, token, "protect") { SYS_PROTECT }
    else if token_is_word_at(source, tokens, files, file_index, token, "ioctl") { SYS_IOCTL }
    else if token_is_word_at(source, tokens, files, file_index, token, "statx") { SYS_STATX }
    else if token_is_word_at(source, tokens, files, file_index, token, "sigaction") { SYS_SIGACTION }
    else if token_is_word_at(source, tokens, files, file_index, token, "openat") { SYS_OPENAT }
    else if token_is_word_at(source, tokens, files, file_index, token, "close") { SYS_CLOSE }
    else if token_is_word_at(source, tokens, files, file_index, token, "call_main") { SYS_CALL_MAIN }
    else { -1L }
}

// E3a1 begin: shared compiler integration.
fn core_sys_argument_count(operation: long) -> long {
    if operation == SYS_NULL || operation == SYS_STATE { 0L }
    // E3a1 subsection
    else if operation == SYS_CONTEXT_SIZE || operation == SYS_IS_TEST_BUILD || operation == SYS_CONTEXT { 0L }
    else if operation == SYS_CONTEXT_OFFSET { 1L }
    else if operation == SYS_STACK_ADDR || operation == SYS_STACK_LOAD8 { 2L }
    else if operation == SYS_STACK_STORE8 { 3L }
    else if operation == SYS_UNMAP || operation == SYS_CLOCK_GETTIME { 2L }
    else if operation == SYS_REMAP { 5L }
    // E3a1 subsection end
    else if operation == SYS_LIT || operation == SYS_REPEAT_BYTE { 1L }
    else if operation == SYS_IS_NULL || operation == SYS_FROM_RAW || operation == SYS_IS_ERROR || operation == SYS_EXIT_GROUP || operation == SYS_CLOSE { 1L }
    else if operation == SYS_OFFSET || operation == SYS_DISTANCE || operation == SYS_LOAD8 || operation == SYS_LOAD32 || operation == SYS_LOAD64 || operation == SYS_LOAD_ADDR || operation == SYS_COPY_16 || operation == SYS_FILL_16 { 2L }
    else if operation == SYS_PROTECT || operation == SYS_IOCTL || operation == SYS_FILL_BULK { 3L }
    else if operation == SYS_CALL_MAIN { 4L }
    else if operation == SYS_STORE8 || operation == SYS_STORE32 || operation == SYS_STORE64 || operation == SYS_STORE_ADDR || operation == SYS_COPY_FORWARD_BULK || operation == SYS_WRITE { 3L }
    else if operation == SYS_OPENAT || operation == SYS_SIGACTION { 4L }
    else if operation == SYS_STATX { 5L }
    else if operation == SYS_MAP { 6L }
    else { -1L }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn core_sys_argument_type(operation: long, index: long) -> long {
    // E3a1 subsection
    if operation == SYS_CONTEXT_OFFSET && index == 0L { TY_LONG }
    else if operation == SYS_STACK_ADDR && index == 0L { TY_ADDR }
    else if operation == SYS_STACK_ADDR && index == 1L { TY_LONG }
    else if operation == SYS_STACK_LOAD8 && index == 0L { TY_ADDR }
    else if operation == SYS_STACK_LOAD8 && index == 1L { TY_LONG }
    else if operation == SYS_STACK_STORE8 && index == 0L { TY_ADDR }
    else if operation == SYS_STACK_STORE8 && index == 1L { TY_LONG }
    else if operation == SYS_STACK_STORE8 && index == 2L { TY_INT }
    else if operation == SYS_REMAP && index == 0L { TY_ADDR }
    else if operation == SYS_REMAP && (index == 1L || index == 2L) { TY_LONG }
    else if operation == SYS_REMAP && index == 3L { TY_INT }
    else if operation == SYS_REMAP && index == 4L { TY_ADDR }
    else if operation == SYS_UNMAP && index == 0L { TY_ADDR }
    else if operation == SYS_UNMAP && index == 1L { TY_LONG }
    else if operation == SYS_CLOCK_GETTIME && index == 0L { TY_INT }
    else if operation == SYS_CLOCK_GETTIME && index == 1L { TY_ADDR }
    // E3a1 subsection end
    else if operation == SYS_IS_NULL && index == 0L { TY_ADDR }
    else if operation == SYS_OFFSET && index == 0L { TY_ADDR }
    else if operation == SYS_OFFSET && index == 1L { TY_LONG }
    else if operation == SYS_DISTANCE && index < 2L { TY_ADDR }
    else if operation == SYS_COPY_16 && (index == 0L || index == 1L) { TY_ADDR }
    else if operation == SYS_FILL_16 && index == 0L { TY_ADDR }
    else if operation == SYS_FILL_16 && index == 1L { TY_LONG }
    else if operation == SYS_FROM_RAW && index == 0L { TY_LONG }
    else if (operation == SYS_LOAD8 || operation == SYS_LOAD32 || operation == SYS_LOAD64 || operation == SYS_LOAD_ADDR) && index == 0L { TY_ADDR }
    else if (operation == SYS_LOAD8 || operation == SYS_LOAD32 || operation == SYS_LOAD64 || operation == SYS_LOAD_ADDR) && index == 1L { TY_LONG }
    else if (operation == SYS_STORE8 || operation == SYS_STORE32 || operation == SYS_STORE64 || operation == SYS_STORE_ADDR) && index == 0L { TY_ADDR }
    else if (operation == SYS_STORE8 || operation == SYS_STORE32 || operation == SYS_STORE64 || operation == SYS_STORE_ADDR) && index == 1L { TY_LONG }
    else if operation == SYS_STORE8 && index == 2L { TY_INT }
    else if operation == SYS_STORE32 && index == 2L { TY_INT }
    else if operation == SYS_STORE64 && index == 2L { TY_LONG }
    else if operation == SYS_STORE_ADDR && index == 2L { TY_ADDR }
    else if operation == SYS_IS_ERROR && index == 0L { TY_LONG }
    else if operation == SYS_COPY_FORWARD_BULK && index < 2L { TY_ADDR }
    else if operation == SYS_COPY_FORWARD_BULK && index == 2L { TY_LONG }
    else if operation == SYS_FILL_BULK && index == 0L { TY_ADDR }
    else if operation == SYS_FILL_BULK && index == 1L { TY_INT }
    else if operation == SYS_FILL_BULK && index == 2L { TY_LONG }
    else if operation == SYS_REPEAT_BYTE && index == 0L { TY_INT }
    else if operation == SYS_WRITE && index == 0L { TY_INT }
    else if operation == SYS_WRITE && index == 1L { TY_ADDR }
    else if operation == SYS_WRITE && index == 2L { TY_LONG }
    else if operation == SYS_EXIT_GROUP && index == 0L { TY_INT }
    else if operation == SYS_MAP && (index == 0L || index == 5L) { if index == 0L { TY_ADDR } else { TY_LONG } }
    else if operation == SYS_MAP && index == 1L { TY_LONG }
    else if operation == SYS_MAP && (index == 2L || index == 3L || index == 4L) { TY_INT }
    else if operation == SYS_PROTECT && index == 0L { TY_ADDR }
    else if operation == SYS_PROTECT && index == 1L { TY_LONG }
    else if operation == SYS_PROTECT && index == 2L { TY_INT }
    else if operation == SYS_IOCTL && index == 0L { TY_INT }
    else if operation == SYS_IOCTL && index == 1L { TY_LONG }
    else if operation == SYS_IOCTL && index == 2L { TY_ADDR }
    else if operation == SYS_STATX && index == 0L { TY_INT }
    else if operation == SYS_STATX && index == 1L { TY_ADDR }
    else if operation == SYS_STATX && (index == 2L || index == 3L) { TY_INT }
    else if operation == SYS_STATX && index == 4L { TY_ADDR }
    else if operation == SYS_SIGACTION && index == 0L { TY_INT }
    else if operation == SYS_SIGACTION && (index == 1L || index == 2L) { TY_ADDR }
    else if operation == SYS_SIGACTION && index == 3L { TY_LONG }
    else if operation == SYS_OPENAT && index == 0L { TY_INT }
    else if operation == SYS_OPENAT && index == 1L { TY_ADDR }
    else if operation == SYS_OPENAT && (index == 2L || index == 3L) { TY_INT }
    else if operation == SYS_CLOSE && index == 0L { TY_INT }
    else if operation == SYS_CALL_MAIN && index == 0L { TY_INT }
    else if operation == SYS_CALL_MAIN && (index == 1L || index == 2L) { TY_ADDR }
    else if operation == SYS_CALL_MAIN && index == 3L { TY_ADDR }
    else if operation == SYS_LIT && index == 0L { TY_ADDR }
    else { -1L }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn core_sys_result_type(operation: long) -> long {
    // E3a1 subsection
    if operation == SYS_CONTEXT_OFFSET || operation == SYS_CONTEXT_SIZE { TY_LONG }
    else if operation == SYS_IS_TEST_BUILD { TY_BOOL }
    else if operation == SYS_CONTEXT || operation == SYS_STACK_ADDR { TY_ADDR }
    else if operation == SYS_STACK_LOAD8 { TY_INT }
    else if operation == SYS_REMAP || operation == SYS_UNMAP || operation == SYS_CLOCK_GETTIME { TY_LONG }
    // E3a1 subsection end
    else if operation == SYS_IS_NULL || operation == SYS_IS_ERROR { TY_BOOL }
    else if operation == SYS_NULL || operation == SYS_OFFSET || operation == SYS_FROM_RAW || operation == SYS_LOAD_ADDR || operation == SYS_STATE || operation == SYS_LIT { TY_ADDR }
    else if operation == SYS_LOAD8 || operation == SYS_LOAD32 { TY_INT }
    else if operation == SYS_LOAD64 || operation == SYS_DISTANCE || operation == SYS_WRITE || operation == SYS_MAP || operation == SYS_PROTECT || operation == SYS_IOCTL || operation == SYS_STATX || operation == SYS_SIGACTION || operation == SYS_OPENAT || operation == SYS_CLOSE { TY_LONG }
    else if operation == SYS_REPEAT_BYTE { TY_LONG }
    else if operation == SYS_CALL_MAIN { TY_INT }
    else if operation == SYS_EXIT_GROUP { TY_NEVER }
    else { TY_UNIT }
}
// E3a1 end

fn is_c_runtime_capability_type(compiler: CompilerTables, type_id: long) -> bool {
    compiler.c_runtime && type_id >= TY_ENV && type_id <= TY_ARG
}

fn unsupported_category_for_node(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    deferred_text_states: list<byte, TYPE_TABLE_CAPACITY * 2L>,
    node: long,
    file_index: long,
) -> long {
    let value = tables.nodes[node]
    if value.kind == NodeKind.FieldType || value.kind == NodeKind.PayloadType ||
        value.kind == NodeKind.ParameterType || value.kind == NodeKind.ResultType ||
        value.kind == NodeKind.Annotation {
        if syntax_has_deferred_text_collection(source, tokens, files, tables, compiler, deferred_text_states, file_index, node) {
            return UNSUPPORTED_TEXT_COLLECTION
        }
    }
    // Range types (int 0..=255) are not implemented: reject them wherever a type is written
    // instead of treating them as their base type and dropping the range check.
    if is_type_node(value.kind) && (value.flags & FLAG_RANGE) != 0L { return UNSUPPORTED_TYPE_FORM }
    match value.kind {
        NodeKind.Program => 0L,
        NodeKind.Enum => 0L,
        // E3a1 begin: large struct and sum values use data-stack regions.
        NodeKind.Struct => if value.aux > 0L { UNSUPPORTED_NODE } else { 0L },
        // E3a1 end
        NodeKind.StructField => 0L,
        NodeKind.EnumCase => 0L,
        NodeKind.FieldType => if type_node_is_oversized(source, tokens, files, tables, compiler, node, file_index) { UNSUPPORTED_LARGE_VALUE } else { 0L },
        NodeKind.PayloadType => if type_node_is_oversized(source, tokens, files, tables, compiler, node, file_index) { UNSUPPORTED_LARGE_VALUE } else { 0L },
        NodeKind.TypeAlias => 0L,
        NodeKind.Const => if (compiler.facts[node].flags & FACT_CONSTANT_EVALUATED) != 0L { 0L } else { UNSUPPORTED_NODE },
        NodeKind.Global => UNSUPPORTED_NODE,
        NodeKind.ForEach => 0L,
        NodeKind.While => if compiler.c_runtime { UNSUPPORTED_NODE } else { 0L },
        NodeKind.Discard => 0L,
        NodeKind.Match => 0L,
        NodeKind.Cast => 0L,
        NodeKind.CastType => {
            if token_is_word_at(source, tokens, files, file_index, value.token, "int") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "long") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "byte") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "Ascii") { 0L }
            else if (compiler.facts[node].flags & FACT_RESOLVED_TYPE) != 0L &&
                (compiler.facts[node].ty == TY_INT || compiler.facts[node].ty == TY_LONG || compiler.facts[node].ty == TY_BYTE) { 0L }
            else { UNSUPPORTED_NODE }
        },
        NodeKind.Fit => 0L,
        NodeKind.FitType => 0L,
        NodeKind.Try => 0L,
        NodeKind.MethodCall => if is_core_sys_receiver(source, tokens, files, tables, compiler, node, file_index) ||
            token_is_word_at(source, tokens, files, file_index, value.token, "is_some") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "is_none") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "is_ok") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "is_err") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "ok") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "unwrap") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "len") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "count") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "byte_len") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "slice") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "bytes") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "contains") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "starts_with") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "validate_utf8") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "to_text") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "to_ascii") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "try_append") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "push") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "insert") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "remove") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "clear") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "pop") ||
            token_is_word_at(source, tokens, files, file_index, value.token, "empty") ||
            (compiler.c_runtime && (
                token_is_word_at(source, tokens, files, file_index, value.token, "args") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "exit") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "get") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "byte") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "length") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "list_with_extension") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "join") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "read") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "write")
            )) ||
            parse_number_method_kind(source, tokens, files, file_index, value.token) != PARSE_NUMBER_NONE { 0L } else { UNSUPPORTED_NODE },
        NodeKind.IndirectCall => UNSUPPORTED_NODE,
        NodeKind.Index => 0L,
        NodeKind.OptionalCall => 0L,
        NodeKind.Field => 0L,
        NodeKind.QualifiedCase => {
            let qualifier = tables.nodes[node].token
            let enum_index = enum_type_matches(compiler, compiler.token_name_ids[qualifier])
            if enum_index >= 0L { 0L }
            else if token_is_word_at(source, tokens, files, file_index, qualifier, "Option") || token_is_word_at(source, tokens, files, file_index, qualifier, "Result") { 0L }
            else { 0L }
        },
        NodeKind.StructInit => 0L,
        NodeKind.InitializerField => 0L,
        NodeKind.ArrayLiteral => 0L,
        NodeKind.ListLiteral => 0L,
        NodeKind.PoolLiteral => UNSUPPORTED_NODE,
        NodeKind.MapLiteral => UNSUPPORTED_NODE,
        NodeKind.SetLiteral => UNSUPPORTED_NODE,
        NodeKind.QueueLiteral => UNSUPPORTED_NODE,
        NodeKind.RingLiteral => UNSUPPORTED_NODE,
        NodeKind.GridIndex => UNSUPPORTED_NODE,
        NodeKind.ToLong => 0L,
        NodeKind.WildcardPattern => 0L,
        NodeKind.BoolPattern => 0L,
        NodeKind.CasePattern => 0L,
        NodeKind.PatternBinding => 0L,
        NodeKind.IgnoredPatternBinding => 0L,
        NodeKind.MatchArm => 0L,
        NodeKind.FunctionType => UNSUPPORTED_NODE,
        NodeKind.FunctionTypeParameter => UNSUPPORTED_NODE,
        NodeKind.Effect => UNSUPPORTED_NODE,
        NodeKind.AliasedType => if (compiler.facts[node].flags & FACT_RESOLVED_TYPE) != 0L { 0L } else { UNSUPPORTED_TYPE },
        NodeKind.DeclaredType => if compiler.facts[node].ty == TY_INT || compiler.facts[node].ty == TY_LONG { 0L } else { UNSUPPORTED_NODE },
        NodeKind.TypeArgument => 0L,
        NodeKind.ParameterType => {
            if is_core_addr_type(source, tokens, files, tables, compiler, file_index, node) { 0L }
            else if (value.flags & FLAG_TYPE_UNIT) != 0L { 0L }
            else if type_node_is_oversized(source, tokens, files, tables, compiler, node, file_index) { UNSUPPORTED_LARGE_VALUE }
            else if generic_type_kind(source, tokens, files, tables, file_index, node) != 0L { 0L }
            else if sum_type_syntax_shape(source, tokens, files, tables, file_index, node) { 0L }
            else {
                let resolved_type = resolve_value_type(source, tokens, files, tables, compiler, file_index, node)
                if is_aggregate_type(compiler, resolved_type) { 0L }
                else if is_c_runtime_capability_type(compiler, resolved_type) { 0L }
                else if known_non_scalar_type(source, tokens, files, file_index, value.token) { UNSUPPORTED_TYPE }
                else if value.meta0 > 1L || (value.meta1 & 2097151L) > 0L || ((value.meta1 >> 21L) & 2097151L) > 0L || ((value.meta1 >> 42L) & 2097151L) > 0L || (value.flags & FLAG_RANGE) != 0L { UNSUPPORTED_TYPE_FORM }
                else { 0L }
            }
        },
        NodeKind.ResultType => {
            if is_core_addr_type(source, tokens, files, tables, compiler, file_index, node) { 0L }
            else if (value.flags & FLAG_TYPE_UNIT) != 0L { 0L }
            else if token_is_word_at(source, tokens, files, file_index, value.token, "never") { 0L }
            else if type_node_is_oversized(source, tokens, files, tables, compiler, node, file_index) { UNSUPPORTED_LARGE_VALUE }
            else if generic_type_kind(source, tokens, files, tables, file_index, node) != 0L { 0L }
            else if sum_type_syntax_shape(source, tokens, files, tables, file_index, node) { 0L }
            else {
                let resolved_type = resolve_value_type(source, tokens, files, tables, compiler, file_index, node)
                if is_aggregate_type(compiler, resolved_type) { 0L }
                else if is_c_runtime_capability_type(compiler, resolved_type) { 0L }
                else if known_non_scalar_type(source, tokens, files, file_index, value.token) { UNSUPPORTED_TYPE }
                else if value.meta0 > 1L || (value.meta1 & 2097151L) > 0L || ((value.meta1 >> 21L) & 2097151L) > 0L || ((value.meta1 >> 42L) & 2097151L) > 0L || (value.flags & FLAG_RANGE) != 0L { UNSUPPORTED_TYPE_FORM }
                else { 0L }
            }
        },
        NodeKind.Annotation => {
            if is_core_addr_type(source, tokens, files, tables, compiler, file_index, node) { 0L }
            else if (value.flags & FLAG_TYPE_UNIT) != 0L { 0L }
            else if type_node_is_oversized(source, tokens, files, tables, compiler, node, file_index) { UNSUPPORTED_LARGE_VALUE }
            else if generic_type_kind(source, tokens, files, tables, file_index, node) != 0L { 0L }
            else if sum_type_syntax_shape(source, tokens, files, tables, file_index, node) { 0L }
            else {
                let resolved_type = resolve_value_type(source, tokens, files, tables, compiler, file_index, node)
                if is_aggregate_type(compiler, resolved_type) { 0L }
                else if is_c_runtime_capability_type(compiler, resolved_type) { 0L }
                else if known_non_scalar_type(source, tokens, files, file_index, value.token) { UNSUPPORTED_TYPE }
                else if value.meta0 > 1L || (value.meta1 & 2097151L) > 0L || ((value.meta1 >> 21L) & 2097151L) > 0L || ((value.meta1 >> 42L) & 2097151L) > 0L || (value.flags & FLAG_RANGE) != 0L { UNSUPPORTED_TYPE_FORM }
                else { 0L }
            }
        },
        NodeKind.Function => {
            if !is_top_level_function(tables, compiler, node) || value.aux > 0L { UNSUPPORTED_NODE }
            else { 0L }
        },
        NodeKind.Parameter => 0L,
        NodeKind.Test => if value.aux > 0L { UNSUPPORTED_NODE } else { 0L },
        NodeKind.Block => 0L,
        NodeKind.Let => 0L,
        NodeKind.Assign => if value.flags < 0L || value.flags > 10L { UNSUPPORTED_ASSIGNMENT } else { 0L },
        NodeKind.ReturnStatement => 0L,
        NodeKind.ExpressionStatement => 0L,
        NodeKind.For => 0L,
        NodeKind.Expect => 0L,
        NodeKind.BreakStatement => 0L,
        NodeKind.ContinueStatement => 0L,
        NodeKind.Unit => 0L,
        NodeKind.Integer => 0L,
        NodeKind.Bool => 0L,
        NodeKind.BytesLiteral => 0L,
        NodeKind.ByteString => 0L,
        NodeKind.Name => {
            if is_function_value_name(files, tables, compiler, node, file_index) { UNSUPPORTED_FUNCTION_VALUE }
            else if builtin_case_name(source, tokens, files, file_index, value.token) &&
                user_case_matches(compiler, compiler.token_name_ids[value.token]) == -1L &&
                !(token_is_word_at(source, tokens, files, file_index, value.token, "none") &&
                    find_function_by_name(compiler, compiler.token_name_ids[value.token]) < 0L) &&
                !is_shadowed_function_value(tables, compiler, node, compiler.token_name_ids[value.token]) { UNSUPPORTED_CASE }
            else { 0L }
        },
        NodeKind.Return => 0L,
        NodeKind.LoopExit => 0L,
        NodeKind.Unary => 0L,
        NodeKind.If => 0L,
        NodeKind.Binary => if value.flags < 0L || (value.flags > 20L && value.flags != 21L) || value.flags == 5L || value.flags == 6L || value.flags == 7L { UNSUPPORTED_OPERATOR } else { 0L },
        NodeKind.Call => {
            if token_is_word_at(source, tokens, files, file_index, value.token, "fill") { 0L }
            else if format_text_builtin_kind(source, tokens, files, tables, compiler, file_index, node) != FORMAT_TEXT_NONE { 0L }
            else if builtin_function_name(source, tokens, files, file_index, value.token) {
                let id = compiler.token_name_ids[value.token]
                if function_exists_by_name(compiler, id) { 0L } else { UNSUPPORTED_CALLEE }
            } else if builtin_case_name(source, tokens, files, file_index, value.token) &&
                user_case_matches(compiler, compiler.token_name_ids[value.token]) == -1L &&
                !builtin_sum_case_name(source, tokens, files, file_index, value.token) &&
                find_function_by_name(compiler, compiler.token_name_ids[value.token]) < 0L {
                UNSUPPORTED_CASE
            } else { 0L }
        },
        _ => UNSUPPORTED_NODE,
    }
}

fn unsupported_node_message(kind: NodeKind) -> Ascii max 160 {
    match kind {
        NodeKind.Enum => "enum declarations",
        NodeKind.Struct => "struct declarations",
        NodeKind.TypeAlias => "type aliases",
        NodeKind.Const => "constant declarations",
        NodeKind.Global => "global declarations",
        NodeKind.ForEach => "for-each loops",
        NodeKind.Discard => "discard statements",
        NodeKind.Match => "match",
        NodeKind.MatchArm => "match arms",
        NodeKind.Cast => "casts",
        NodeKind.Fit => "fit expressions",
        NodeKind.Try => "? propagation",
        NodeKind.MethodCall => "method calls",
        NodeKind.IndirectCall => "indirect calls",
        NodeKind.Index => "indexing",
        NodeKind.OptionalCall => "optional calls",
        NodeKind.Field => "field access",
        NodeKind.QualifiedCase => "qualified enum cases",
        NodeKind.StructInit => "struct initialisers",
        NodeKind.InitializerField => "initializer fields",
        NodeKind.ArrayLiteral => "array literals",
        NodeKind.ListLiteral => "list literals",
        NodeKind.PoolLiteral => "pool literals",
        NodeKind.MapLiteral => "map literals",
        NodeKind.SetLiteral => "set literals",
        NodeKind.QueueLiteral => "queue literals",
        NodeKind.RingLiteral => "ring literals",
        NodeKind.GridIndex => "grid indexing",
        NodeKind.FunctionType => "function types",
        NodeKind.FunctionTypeParameter => "function type parameters",
        NodeKind.Effect => "function effects",
        NodeKind.Parameter => "write and grow parameters",
        NodeKind.Test => "test parameters",
        NodeKind.Function => "generic functions",
        NodeKind.While => "while loops",
        NodeKind.WildcardPattern => "match patterns",
        NodeKind.BoolPattern => "match patterns",
        NodeKind.CasePattern => "match patterns",
        NodeKind.PatternBinding => "match patterns",
        NodeKind.IgnoredPatternBinding => "match patterns",
        _ => "this construct",
    }
}

fn report_unsupported(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    hit: UnsupportedHit,
) -> never {
    let file = files[hit.file]
    let position = position_for_offset(hit.file, file.base + hit.offset, compiler)
    match env.err.write(file.name) {
        ok(_) => (), err(_) => env.exit(3),
    }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: not supported by the self-hosted compiler yet: ") { ok(_) => (), err(_) => env.exit(3) }
    if hit.category == UNSUPPORTED_TYPE {
        match env.err.write(b"type ") { ok(_) => (), err(_) => env.exit(3) }
        match write_token_raw(env.err, source, tokens, file.base, hit.token) { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_TYPE_FORM {
        let node = tables.nodes[hit.node]
        if node.kind == NodeKind.TypeArgument || node.meta0 > 1L || (node.flags & FLAG_RANGE) != 0L {
            match env.err.write(b"generic, array, or refined type forms") { ok(_) => (), err(_) => env.exit(3) }
        } else {
            match env.err.write(b"type arguments") { ok(_) => (), err(_) => env.exit(3) }
        }
    } else if hit.category == UNSUPPORTED_OPERATOR {
        let spelling: Ascii max 32 = match tables.nodes[hit.node].flags {
            5L => "+%", 6L => "-%", 7L => "*%",
            16L => "&", 17L => "|", 18L => "^", 19L => "<<", 20L => ">>", 21L => "??",
            _ => "operator",
        }
        match env.err.write(b"the ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(spelling.bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b" operator") { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_ASSIGNMENT {
        match env.err.write(b"the >>= operator") { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_CALLEE {
        match env.err.write(b"calls to built-in functions") { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_CASE {
        match env.err.write(b"built-in enum cases") { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_FUNCTION_VALUE {
        match env.err.write(b"function values") { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_LARGE_VALUE {
        match env.err.write(b"value types larger than 4096 bytes") { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_NESTED_COLLECTIONS {
        match env.err.write(b"nested collections") { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_TEXT_COLLECTION {
        match env.err.write(b"text in collections") { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_CONDITIONAL_BUILDER_LOOP {
        match env.err.write(b"conditional builder growth inside loops") { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_FRAME_BUDGET {
        match env.err.write(b"aggregate locals over 1 MiB on one call path") { ok(_) => (), err(_) => env.exit(3) }
    } else if hit.category == UNSUPPORTED_RESULT_MAIN {
        match env.err.write(b"a Result-returning main function") { ok(_) => (), err(_) => env.exit(3) }
    } else {
        match env.err.write(unsupported_node_message(tables.nodes[hit.node].kind).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn check_package_eligibility(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
) {
    for node in 0L..tables.nodes.count() {
        if !is_type_node(tables.nodes[node].kind) { continue }
        let file_index = node_file_index(tables.nodes, files, node)
        let type_id = resolve_value_type(source, tokens, files, tables, compiler, file_index, node)
        if type_id >= 0L && type_state(compiler, type_id) == TYPE_STATE_LAYOUT_OVERFLOW {
            fail_at_message(env, files, compiler, file_index, tables.nodes[node].start,
                "collection size overflows long; reduce a capacity or the nested element size")
        }
    }
    check_const_bytes_diagnostic(env, source, files, tokens, tables, compiler)
    var deferred_text_states: list<byte, TYPE_TABLE_CAPACITY * 2L> = list {}
    populate_deferred_text_collection_states(compiler, deferred_text_states)
    var hit = UnsupportedHit { found: false, file: 0L, node: -1L, offset: 0L, category: 0L, token: -1L }
    for node in 0L..tables.nodes.count() {
        let file_index = node_file_index(tables.nodes, files, node)
        let category = unsupported_category_for_node(source, tokens, files, tables, compiler, deferred_text_states, node, file_index)
        if category == 0L { continue }
        let start = if category == UNSUPPORTED_OPERATOR { tables.nodes[node].anchor } else { tables.nodes[node].start }
        let is_earlier = !hit.found || file_index < hit.file || (file_index == hit.file && (start < hit.offset || (start == hit.offset && (tables.nodes[node].end > tables.nodes[hit.node].end || (tables.nodes[node].end == tables.nodes[hit.node].end && node > hit.node)))))
        if is_earlier {
            hit = UnsupportedHit { found: true, file: file_index, node, offset: start, category, token: tables.nodes[node].token }
        }
    }
    if hit.found { report_unsupported(env, source, files, tokens, tables, compiler, hit) }
}

fn report_typed_unsupported(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
    category: long,
) -> never {
    report_unsupported(env, source, files, tokens, tables, compiler,
        UnsupportedHit { found: true, file: file_index, node, offset: tables.nodes[node].start, category, token: tables.nodes[node].token })
}

fn check_text_builder_method(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    scope: long,
    node: long,
    receiver: long,
    receiver_type: long,
    expected: long,
) -> long {
    let method_token = tables.nodes[node].token
    let receiver_kind = type_kind(compiler, receiver_type)
    let is_push = token_is_word_at(source, tokens, files, file_index, method_token, "push")
    let argument = compiler.child_next[receiver]
    let argument_count = count_children(tables, compiler, node) - 1L
    if argument_count != 1L {
        let message: Ascii max 160 = if is_push { "Bytes.push(byte) takes one byte" }
            else if receiver_kind == TYPE_KIND_ASCII { "Ascii.try_append(value) takes one Ascii value" }
            else if receiver_kind == TYPE_KIND_TEXT { "Text.try_append(value) takes one Text or Ascii value" }
            else { "Bytes.try_append(value) takes one Bytes value" }
        fail_at_message(env, files, compiler, file_index, tables.nodes[node].anchor, message)
    }
    let receiver_binding = compiler.facts[receiver].binding
    if receiver_binding < 0L {
        let message: Ascii max 160 = if is_push { "Bytes.push needs a mutable builder; use a var or grow parameter" }
            else if receiver_kind == TYPE_KIND_ASCII { "Ascii.try_append needs a mutable builder; use a var or grow parameter" }
            else if receiver_kind == TYPE_KIND_TEXT { "Text.try_append needs a mutable builder; use a var or grow parameter" }
            else { "Bytes.try_append needs a mutable builder; use a var or grow parameter" }
        fail_at_message(env, files, compiler, file_index, tables.nodes[receiver].start, message)
    }
    if !compiler.bindings[receiver_binding].mutable {
        let message: Ascii max 160 = if is_push { "Bytes.push needs a mutable builder; declare it with var" }
            else if receiver_kind == TYPE_KIND_ASCII { "Ascii.try_append needs a mutable builder; declare it with var" }
            else if receiver_kind == TYPE_KIND_TEXT { "Text.try_append needs a mutable builder; declare it with var" }
            else { "Bytes.try_append needs a mutable builder; declare it with var" }
        fail_at_message(env, files, compiler, file_index, tables.nodes[receiver].start, message)
    }
    if binding_is_write_parameter(compiler, receiver_binding) && !binding_is_grow_parameter(compiler, receiver_binding) {
        let message: Ascii max 160 = if is_push { "Bytes.push through a write parameter requires 'grow' mode; 'write' cannot increase its length" }
            else if receiver_kind == TYPE_KIND_ASCII { "Ascii.try_append through a write parameter requires 'grow' mode; 'write' cannot increase its length" }
            else if receiver_kind == TYPE_KIND_TEXT { "Text.try_append through a write parameter requires 'grow' mode; 'write' cannot increase its length" }
            else { "Bytes.try_append through a write parameter requires 'grow' mode; 'write' cannot increase its length" }
        fail_at_message(env, files, compiler, file_index, tables.nodes[receiver].start, message)
    }
    if active_view_overlaps_place(tables, compiler, scope, receiver) {
        fail_at_message(env, files, compiler, file_index, tables.nodes[node].start,
            "cannot replace or modify storage that contains a live collection view")
    }
    if argument < 0L { fail_at_message(env, files, compiler, file_index, tables.nodes[node].anchor, "text builder method is missing its value") }
    let argument_type = compiler.facts[argument].ty
    let valid_argument = if is_push { argument_type == TY_BYTE }
        else if receiver_kind == TYPE_KIND_ASCII { type_kind(compiler, argument_type) == TYPE_KIND_ASCII }
        else if receiver_kind == TYPE_KIND_TEXT { type_kind(compiler, argument_type) == TYPE_KIND_TEXT || type_kind(compiler, argument_type) == TYPE_KIND_ASCII }
        else { type_kind(compiler, argument_type) == TYPE_KIND_BYTES }
    if !valid_argument {
        fail_builder_argument_type(env, source, files, tokens, compiler, file_index,
            tables.nodes[argument].start, receiver_kind, argument_type, is_push)
    }
    let full_ty = builtin_full_type_id(compiler)
    if full_ty < 0L { fail_at_message(env, files, compiler, file_index, tables.nodes[node].start, "internal capacity error type is unavailable") }
    let result_ty = intern_sum_type(compiler, TYPE_KIND_RESULT, TY_UNIT, full_ty, file_index, node, -1L, -1L)
    if expected >= 0L && expected != result_ty {
        require_type(env, files, compiler, file_index, node, expected, result_ty, tables)
    }
    result_ty
}

fn check_nested_collections_eligibility(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
) {
    var hit = UnsupportedHit { found: false, file: 0L, node: -1L, offset: 0L, category: 0L, token: -1L }
    for node in 0L..tables.nodes.count() {
        let kind = tables.nodes[node].kind
        if kind != NodeKind.FieldType && kind != NodeKind.Annotation && kind != NodeKind.ParameterType && kind != NodeKind.ResultType { continue }
        let file_index = node_file_index(tables.nodes, files, node)
        if !syntax_has_nested_collection_elements(source, tokens, files, tables, compiler, file_index, node) { continue }
        let start = tables.nodes[node].start
        let same_position = hit.found && file_index == hit.file && start == hit.offset
        let is_earlier = !hit.found || file_index < hit.file ||
            (file_index == hit.file && start < hit.offset) ||
            (same_position && tables.nodes[node].end > tables.nodes[hit.node].end) ||
            (same_position && tables.nodes[node].end == tables.nodes[hit.node].end && node > hit.node)
        if is_earlier {
            hit = UnsupportedHit { found: true, file: file_index, node, offset: start, category: UNSUPPORTED_NESTED_COLLECTIONS, token: tables.nodes[node].token }
        }
    }
    if hit.found { report_unsupported(env, source, files, tokens, tables, compiler, hit) }
}

fn ascii_space(value: byte) -> bool {
    value == 32 || value == 9 || value == 10 || value == 13
}

fn trim_start(contents: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> long {
    var index = start
    for step in 0L..end - start {
        if index >= end || !ascii_space(contents[index]) { break }
        index += 1L
    }
    index
}

fn trim_end(contents: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> long {
    var index = end
    for step in 0L..end - start {
        if index <= start || !ascii_space(contents[index - 1L]) { break }
        index -= 1L
    }
    index
}

