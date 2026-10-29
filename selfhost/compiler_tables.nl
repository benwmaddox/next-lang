// E1's compiler tables are owned by main and remain alive through the one IR
// write. Syntax nodes stay immutable; the links and typed facts are indexed by
// parser node id.
//
// E2i shared-code ownership (other parts add only delimited branches):
// | Shared code | Owner after E2i | Others may |
// | type table, kind classification, value_type_size/align, resolve_value_type, known_non_scalar_type, is_builtin_type_name | E2i (interface frozen) | append a kind and its branches |
// | emit_layout_address and StorageLocation | E3a1 (origins), E3a2 (lane geometry) | nothing; sum layouts reach it only through the layout table |
// | location argument/destination passing and parameter receiving | E3a2 (descriptor ABI) | nothing; E2b and E2c call the interface |
// | helper registry | E2i | register an emitter for their kind |
// | exit and cleanup function | E2i | register a cleanup; call it from a new exit |
// | register_package_declarations, signatures | E3a2 (parameter modes) | E2b: enums; E2c: result types |
// | natural_node_type, check_one_body, emit_expr_linear, emit_function_body | none | one dispatch branch per new node kind |
// | unsupported_category_for_node, unsupported_node_message | none | remove their nodes, append their rows |
// | core_sys_*, hook table, frame-budget walk | E3a1 | E2b/E2c add only unavoidable hooks with a C contract fixture |
// | limits.nl | none | append one delimited block with derivations |
const TY_INT: long = 0L
const TY_LONG: long = 1L
const TY_BOOL: long = 2L
const TY_UNIT: long = 3L
const TY_NEVER: long = 4L
const TY_ADDR: long = 5L
const TY_BYTE: long = 6L
const TY_ENV: long = 7L
const TY_FS: long = 8L
const TY_OUT: long = 9L
const TY_ARGS: long = 10L
const TY_ARG: long = 11L
const TY_STRUCT_BASE: long = 12L
// E3a1 begin: struct storage sizes are exact through signed long limits.
const MAX_VALUE_SIZE: long = 9223372036854775807L
// E3a1 end

const TYPE_KIND_SCALAR: long = 1L
const TYPE_KIND_UNIT: long = 2L
const TYPE_KIND_NEVER: long = 3L
const TYPE_KIND_STRUCT: long = 4L
const TYPE_KIND_ENUM: long = 5L
const TYPE_KIND_OPTION: long = 6L
const TYPE_KIND_RESULT: long = 7L
const TYPE_KIND_ARRAY: long = 8L
const TYPE_KIND_LIST: long = 9L
const TYPE_KIND_ASCII: long = 10L
const TYPE_KIND_TEXT: long = 11L
const TYPE_KIND_BYTES: long = 12L
const TYPE_KIND_ADDRESS: long = 13L
const TYPE_STATE_LAYOUT_OVERFLOW: long = 5L

const LOCATION_NATIVE: long = 0L
const LOCATION_DATA_STACK: long = 1L

const HELPER_COPY: long = 1L
const HELPER_EQUAL: long = 2L
const HELPER_PRINT: long = 3L
const HELPER_FILL: long = 4L
const HELPER_DEFAULT: long = 5L

const EXIT_RETURN: long = 1L
const EXIT_RETURN_VALUE: long = 2L
const EXIT_TEST_SUCCESS: long = 3L
const EXIT_TEST_FAILURE: long = 4L
const EXIT_BREAK: long = 5L
const EXIT_CONTINUE: long = 6L
const EXIT_BRANCH: long = 7L
const EXIT_FALLTHROUGH: long = 8L

const BRANCH_IF_END: long = 1L
const BRANCH_IF_EXPR_END: long = 2L
const BRANCH_FOR_INCREMENT: long = 3L
const BRANCH_WHILE_STEP: long = 4L

const SYS_NULL: long = 1L
const SYS_IS_NULL: long = 2L
const SYS_OFFSET: long = 3L
const SYS_DISTANCE: long = 4L
const SYS_FROM_RAW: long = 5L
const SYS_LOAD8: long = 6L
const SYS_LOAD32: long = 7L
const SYS_LOAD64: long = 8L
const SYS_LOAD_ADDR: long = 9L
const SYS_STORE8: long = 10L
const SYS_STORE32: long = 11L
const SYS_STORE64: long = 12L
const SYS_STORE_ADDR: long = 13L
const SYS_LIT: long = 14L
const SYS_STATE: long = 15L
const SYS_IS_ERROR: long = 16L
const SYS_COPY_FORWARD_BULK: long = 17L
const SYS_FILL_BULK: long = 18L
const SYS_WRITE: long = 19L
const SYS_EXIT_GROUP: long = 20L
const SYS_MAP: long = 21L
const SYS_PROTECT: long = 22L
const SYS_IOCTL: long = 23L
const SYS_STATX: long = 24L
const SYS_SIGACTION: long = 25L
const SYS_OPENAT: long = 26L
const SYS_CLOSE: long = 27L
const SYS_REPEAT_BYTE: long = 28L
const SYS_CALL_MAIN: long = 29L
const SYS_COPY_16: long = 30L
const SYS_FILL_16: long = 31L
// E3a1 begin: context offsets, movable-stack addresses, and growth syscalls.
const SYS_CONTEXT_OFFSET: long = 32L
const SYS_CONTEXT_SIZE: long = 33L
const SYS_STACK_ADDR: long = 34L
const SYS_STACK_LOAD8: long = 35L
const SYS_STACK_STORE8: long = 36L
const SYS_REMAP: long = 37L
const SYS_UNMAP: long = 38L
const SYS_CLOCK_GETTIME: long = 39L
const SYS_IS_TEST_BUILD: long = 40L
const SYS_CONTEXT: long = 41L
// E3a1 end

const FACT_NEVER: long = 1L
const FACT_FALLS_THROUGH: long = 2L
const FACT_RESOLVED_TYPE: long = 4L
const FACT_PROVEN_SUCCESS: long = 8L
const FACT_CONSTANT_VALUE: long = 32L
const FACT_CONSTANT_DECLARED: long = 64L
const FACT_CONSTANT_VISITING: long = 128L
const FACT_CONSTANT_EVALUATED: long = 256L
const FACT_NUMERIC_BUILTIN: long = 512L
const FACT_CONSTANT_TEXT: long = 1024L
const MATCH_PATTERN_CASE: long = 11L
const MATCH_PATTERN_WILDCARD: long = 12L
const MATCH_PATTERN_INTEGER: long = 13L
const MATCH_PATTERN_BOOL: long = 14L

const UNSUPPORTED_NODE: long = 1L
const UNSUPPORTED_TYPE: long = 2L
const UNSUPPORTED_TYPE_FORM: long = 3L
const UNSUPPORTED_OPERATOR: long = 4L
const UNSUPPORTED_ASSIGNMENT: long = 5L
const UNSUPPORTED_CALLEE: long = 6L
const UNSUPPORTED_CASE: long = 7L
const UNSUPPORTED_FUNCTION_VALUE: long = 8L
const UNSUPPORTED_LARGE_VALUE: long = 9L
const UNSUPPORTED_FRAME_BUDGET: long = 10L
const UNSUPPORTED_RESULT_MAIN: long = 11L
const UNSUPPORTED_NESTED_COLLECTIONS: long = 12L
const UNSUPPORTED_TEXT_COLLECTION: long = 13L
const UNSUPPORTED_CONDITIONAL_BUILDER_LOOP: long = 14L

struct TypeRecord {
    // Kind and sizing state share a word; helper_mask is the registry row for this type id.
    kind_state: long
    name_id: long
    name_token: long
    node: long
    file: long
    field_start: long
    field_count: long
    size: long
    align: long
    helper_mask: long
}

// E2i locations carry a native-slot origin now; anchor kinds identify an SSA
// aggregate temp, local, derived address, parameter, hidden result, or helper operand.
// Offsets and lane fields are reserved for the later region and collection owners.
struct StorageLocation {
    origin: long
    anchor_kind: long
    anchor_node: long
    byte_offset: long
    copies: long
    index: long
    index_node: long
    index_stride: long
}

// E3a1 begin: per-function region offsets reuse the post-check expected-type
// scratch array, so region planning adds no input-sized table to CompilerTables.
// The threshold is a test hook; production residency remains 4096 bytes.
// E3a1 end

struct ExitCleanupRecord {
    scope_id: long
    kind: long
    owner: long
}

struct StructFieldRecord {
    owner: long
    name_id: long
    name_token: long
    node: long
    type_node: long
    ty: long
    offset: long
    default_node: long
}

struct EnumCaseRecord {
    owner: long
    name_id: long
    name_token: long
    node: long
    payload_start: long
    payload_count: long
    tag: long
}

struct EnumPayloadRecord {
    case_index: long
    type_node: long
    ty: long
    offset: long
}

struct TypeWalkFrame {
    type_index: long
    field_index: long
    size: long
    align: long
    case_index: long
    max_size: long
}

struct NodeFact {
    ty: long
    flags: long
    binding: long
    function: long
    literal: long
}

struct ScalarConstantResult {
    value: long
    supported: bool
}

struct NameSlot {
    hash: long
    token: long
    file: long
    id: long
}

struct NameCandidate {
    token: long
    file: long
    distance: long
    length: long
}

struct FunctionRecord {
    node: long
    file: long
    name_id: long
    name_token: long
    result_ty: long
    param_start: long
    param_count: long
    body: long
}

struct ParameterRecord {
    node: long
    file: long
    name_id: long
    name_token: long
    ty: long
}

struct TestRecord {
    node: long
    file: long
    name_token: long
    body: long
}

struct CallEdge {
    from: long
    to: long
    node: long
    next: long
}

struct EmitLoop {
    node: long
    // E3a1 begin
    body: long
    // E3a1 end
}

struct EmitExprFrame {
    node: long
    phase: long
    cursor: long
    child0: long
    child1: long
    child2: long
    auxiliary: long
    reachable: bool
}

struct BindingRecord {
    name_id: long
    name_token: long
    file: long
    ty: long
    mutable: bool
    loop_counter: bool
    parameter: bool
    scope: long
    node: long
    collection_count: long
}

fn parameter_name_token(parameter: ParameterRecord) -> long {
    if parameter.name_token >= 0L { parameter.name_token }
    else { (0L - 1L - parameter.name_token) % TOKEN_STORAGE_CAPACITY }
}

fn parameter_mode(parameter: ParameterRecord) -> long {
    if parameter.name_token >= 0L { 0L }
    else { (0L - 1L - parameter.name_token) / TOKEN_STORAGE_CAPACITY }
}

fn encode_parameter_name_token(token: long, mode: long) -> long {
    if mode == 0L { token }
    else { 0L - 1L - (mode * TOKEN_STORAGE_CAPACITY + token) }
}

fn binding_name_token(binding: BindingRecord) -> long {
    if binding.name_token < 0L { 0L - 1L - binding.name_token } else { binding.name_token }
}

struct ScopeRecord {
    parent: long
    function_id: long
    block: long
}

struct CheckFrame {
    node: long
    scope: long
    expected: long
    function_id: long
    loop_depth: long
    is_test: bool
    phase: long
    cursor: long
    child0: long
    child1: long
    child2: long
    result_ty: long
    auxiliary: long
    reachable: bool
}

struct LoopPushProof {
    loop_node: long
    binding: long
    final_count: long
    loop_depth: long
}

struct LoopPushCount {
    count: long
    valid: bool
}

struct CollectionCountChange {
    binding: long
    previous: long
    value: long
}

struct CollectionCountBranchValue {
    join_index: long
    branch: long
    binding: long
    value: long
}

struct CollectionCountJoin {
    node: long
    kind: long
    outer_log_base: long
    binding_limit: long
    log_base: long
    values_base: long
    started: bool
    branch0_falls: bool
    branch1_falls: bool
    fallthrough_count: long
}

struct LoopCountSnapshot {
    loop_node: long
    binding_limit: long
    log_base: long
}

struct FileLineRange {
    first: long
    count: long
}

struct UnsupportedHit {
    found: bool
    file: long
    node: long
    offset: long
    category: long
    token: long
}

struct MemoryConfig {
    capability_mask: long
    job_headroom: long
    globals_budget: long
    recursion_budget: long
    step_budget_main: long
}

struct CompilerTables {
    child_first: list<long, CHILD_LINK_CAPACITY>
    child_next: list<long, CHILD_LINK_CAPACITY>
    facts: list<NodeFact, TYPED_FACT_CAPACITY>
    expected: list<long, TYPED_FACT_CAPACITY>
    region_temp_scope: list<long, TYPED_FACT_CAPACITY>
    block_end: list<long, TYPED_FACT_CAPACITY>
    block_align: list<long, TYPED_FACT_CAPACITY>
    token_name_ids: list<long, TOKEN_STORAGE_CAPACITY>
    intern_slots: list<NameSlot, INTERN_HASH_CAPACITY>
    enum_type_by_name: list<long, TOKEN_STORAGE_CAPACITY>
    value_type_by_name: list<long, TOKEN_STORAGE_CAPACITY>
    constant_by_name: list<long, TOKEN_STORAGE_CAPACITY>
    enum_case_by_name: list<long, TOKEN_STORAGE_CAPACITY>
    enum_case_name_counts: list<long, TOKEN_STORAGE_CAPACITY>
    enum_type_ids: list<long, TYPE_TABLE_CAPACITY>
    reserved_names: list<bool, TOKEN_STORAGE_CAPACITY>
    range_alias_names: list<bool, TOKEN_STORAGE_CAPACITY>
    function_name_present: list<bool, TOKEN_STORAGE_CAPACITY>
    functions: list<FunctionRecord, FUNCTION_TABLE_CAPACITY>
    parameters: list<ParameterRecord, BINDING_TABLE_CAPACITY>
    type_records: list<TypeRecord, TYPE_TABLE_CAPACITY>
    exit_cleanups: list<ExitCleanupRecord, EXIT_CLEANUP_CAPACITY>
    struct_fields: list<StructFieldRecord, FIELD_TABLE_CAPACITY>
    enum_cases: list<EnumCaseRecord, ENUM_CASE_TABLE_CAPACITY>
    enum_payloads: list<EnumPayloadRecord, ENUM_PAYLOAD_TABLE_CAPACITY>
    type_walk: list<TypeWalkFrame, MAX_TREE_NODES>
    tests: list<TestRecord, TEST_TABLE_CAPACITY>
    call_edges: list<CallEdge, CALL_EDGE_CAPACITY>
    edge_first: list<long, NODE_STORAGE_CAPACITY>
    cycle_seen: list<long, NODE_STORAGE_CAPACITY>
    cycle_stack: list<long, NODE_STORAGE_CAPACITY>
    cycle_cursor: list<long, NODE_STORAGE_CAPACITY>
    cycle_path: list<long, NODE_STORAGE_CAPACITY>
    frame_own_bytes: list<long, NODE_STORAGE_CAPACITY>
    frame_path_bytes: list<long, NODE_STORAGE_CAPACITY>
    frame_visit: list<long, NODE_STORAGE_CAPACITY>
    emit_loops: list<EmitLoop, CHECK_FRAME_CAPACITY>
    expr_work: list<EmitExprFrame, CHECK_FRAME_CAPACITY>
    bindings: list<BindingRecord, BINDING_TABLE_CAPACITY>
    loop_push_proofs: list<LoopPushProof, MAX_TREE_NODES>
    collection_count_changes: list<CollectionCountChange, NODE_STORAGE_CAPACITY>
    collection_count_branch_values: list<CollectionCountBranchValue, NODE_STORAGE_CAPACITY>
    collection_count_joins: list<CollectionCountJoin, CHECK_FRAME_CAPACITY>
    loop_count_snapshots: list<LoopCountSnapshot, CHECK_FRAME_CAPACITY>
    scopes: list<ScopeRecord, SCOPE_TABLE_CAPACITY>
    work: list<CheckFrame, CHECK_FRAME_CAPACITY>
    line_starts: list<long, SOURCE_LINE_START_CAPACITY>
    file_line_ranges: list<FileLineRange, MAX_SOURCE_FILES>
    default_context: Bytes max 4096
    table_failed: bool
    ir_overflow: bool
    internal_emit_error_kind: long
    internal_emit_error_node: long
    internal_emit_error_file: long
    ir_terminated: bool
    core_mode: bool
    c_runtime: bool
    test_build: bool
    file_id_base: long
    memory_closure: bool
    step_budget_main: long
    region_current_size: long
    region_max_size: long
    emit_destination_node: long
    emit_destination_kind: long
    emit_destination_anchor: long
}

fn binding_is_view(compiler: CompilerTables, binding: long) -> bool {
    binding >= 0L && binding < compiler.bindings.count() && compiler.bindings[binding].name_token < 0L
}

fn builtin_type_record(kind: long, size: long, align: long) -> TypeRecord {
    TypeRecord {
        kind_state: kind * 16L + 2L,
        name_id: -1L,
        name_token: -1L,
        node: -1L,
        file: -1L,
        field_start: 0L,
        field_count: 0L,
        size,
        align,
        helper_mask: 0L,
    }
}

fn push_builtin_address_type(env: Env, types: write list<TypeRecord, TYPE_TABLE_CAPACITY>) {
    match types.push(builtin_type_record(TYPE_KIND_ADDRESS, 8L, 8L)) {
        ok(_) => (),
        err(_) => fail_tool(env, "compiler built-in type table capacity exceeded"),
    }
}

fn seed_builtin_types(env: Env, types: write list<TypeRecord, TYPE_TABLE_CAPACITY>) {
    types.push(builtin_type_record(TYPE_KIND_SCALAR, 4L, 4L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_SCALAR, 8L, 8L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_SCALAR, 1L, 1L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_UNIT, 0L, 1L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_NEVER, 0L, 1L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_ADDRESS, 8L, 8L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_SCALAR, 4L, 4L)).unwrap()
    push_builtin_address_type(env, types)
    push_builtin_address_type(env, types)
    push_builtin_address_type(env, types)
    push_builtin_address_type(env, types)
    push_builtin_address_type(env, types)
}

fn empty_compiler_tables() -> CompilerTables {
    CompilerTables {
        child_first: list {},
        child_next: list {},
        facts: list {},
        expected: list {},
        region_temp_scope: list {},
        block_end: list {},
        block_align: list {},
        token_name_ids: list {},
        intern_slots: list {},
        enum_type_by_name: list {},
        value_type_by_name: list {},
        constant_by_name: list {},
        enum_case_by_name: list {},
        enum_case_name_counts: list {},
        enum_type_ids: list {},
        reserved_names: list {},
        range_alias_names: list {},
        function_name_present: list {},
        functions: list {},
        parameters: list {},
        type_records: list {},
        exit_cleanups: list {},
        struct_fields: list {},
        enum_cases: list {},
        enum_payloads: list {},
        type_walk: list {},
        tests: list {},
        call_edges: list {},
        edge_first: list {},
        cycle_seen: list {},
        cycle_stack: list {},
        cycle_cursor: list {},
        cycle_path: list {},
        frame_own_bytes: list {},
        frame_path_bytes: list {},
        frame_visit: list {},
        emit_loops: list {},
        expr_work: list {},
        bindings: list {},
        loop_push_proofs: list {},
        collection_count_changes: list {},
        collection_count_branch_values: list {},
        collection_count_joins: list {},
        loop_count_snapshots: list {},
        scopes: list {},
        work: list {},
        line_starts: list {},
        file_line_ranges: list {},
        default_context: Bytes.empty(),
        table_failed: false,
        ir_overflow: false,
        internal_emit_error_kind: -1L,
        internal_emit_error_node: -1L,
        internal_emit_error_file: -1L,
        ir_terminated: false,
        core_mode: false,
        c_runtime: false,
        test_build: false,
        file_id_base: 0L,
        memory_closure: false,
        step_budget_main: -1L,
        region_current_size: 0L,
        region_max_size: 0L,
        emit_destination_node: -1L,
        emit_destination_kind: 0L,
        emit_destination_anchor: -1L,
    }
}

fn reset_compiler_tables(env: Env, compiler: write CompilerTables) {
    compiler.child_first.clear()
    compiler.child_next.clear()
    compiler.facts.clear()
    compiler.expected.clear()
    compiler.region_temp_scope.clear()
    compiler.block_end.clear()
    compiler.block_align.clear()
    compiler.token_name_ids.clear()
    compiler.intern_slots.clear()
    compiler.enum_type_by_name.clear()
    compiler.value_type_by_name.clear()
    compiler.constant_by_name.clear()
    compiler.enum_case_by_name.clear()
    compiler.enum_case_name_counts.clear()
    compiler.enum_type_ids.clear()
    compiler.reserved_names.clear()
    compiler.range_alias_names.clear()
    compiler.function_name_present.clear()
    compiler.functions.clear()
    compiler.parameters.clear()
    compiler.type_records.clear()
    compiler.exit_cleanups.clear()
    seed_builtin_types(env, compiler.type_records)
    compiler.struct_fields.clear()
    compiler.enum_cases.clear()
    compiler.enum_payloads.clear()
    compiler.type_walk.clear()
    compiler.tests.clear()
    compiler.call_edges.clear()
    compiler.edge_first.clear()
    compiler.cycle_seen.clear()
    compiler.cycle_stack.clear()
    compiler.cycle_cursor.clear()
    compiler.cycle_path.clear()
    compiler.frame_own_bytes.clear()
    compiler.frame_path_bytes.clear()
    compiler.frame_visit.clear()
    compiler.emit_loops.clear()
    compiler.expr_work.clear()
    compiler.bindings.clear()
    compiler.loop_push_proofs.clear()
    compiler.collection_count_changes.clear()
    compiler.collection_count_branch_values.clear()
    compiler.collection_count_joins.clear()
    compiler.loop_count_snapshots.clear()
    compiler.scopes.clear()
    compiler.work.clear()
    compiler.line_starts.clear()
    compiler.file_line_ranges.clear()
    compiler.default_context = Bytes.empty()
    compiler.table_failed = false
    compiler.ir_overflow = false
    compiler.internal_emit_error_kind = -1L
    compiler.internal_emit_error_node = -1L
    compiler.internal_emit_error_file = -1L
    compiler.ir_terminated = false
    compiler.core_mode = false
    compiler.c_runtime = false
    compiler.test_build = false
    compiler.file_id_base = 0L
    compiler.memory_closure = false
    compiler.region_current_size = 0L
    compiler.region_max_size = 0L
}

fn add_compiler_links(env: Env, tables: write ParseTables, compiler: write CompilerTables) {
    for node in 0L..tables.nodes.count() {
        compiler.child_first.push(-1L).unwrap()
        compiler.child_next.push(-1L).unwrap()
        compiler.facts.push(NodeFact { ty: -1L, flags: 0L, binding: -1L, function: -1L, literal: 0L }).unwrap()
        compiler.expected.push(-1L).unwrap()
        match compiler.region_temp_scope.push(-3L) {
            ok(_) => (),
            err(_) => fail_tool(env, "compiler region node cache capacity exceeded"),
        }
        match compiler.block_end.push(-1L) {
            ok(_) => (),
            err(_) => fail_tool(env, "compiler region block cache capacity exceeded"),
        }
        match compiler.block_align.push(1L) {
            ok(_) => (),
            err(_) => fail_tool(env, "compiler region block cache capacity exceeded"),
        }
    }
    for parent in 0L..tables.nodes.count() {
        let first = parent - tables.nodes[parent].subtree + 1L
        if first < parent {
            var child = parent - 1L
            var next = -1L
            for step in 0L..tables.nodes[parent].subtree {
                if child < first { break }
                compiler.child_next[child] = next
                next = child
                child -= tables.nodes[child].subtree
            }
            compiler.child_first[parent] = next
        }
    }
}

fn build_line_start_index(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: write CompilerTables,
) {
    for file_index in 0L..files.count() {
        let first = compiler.line_starts.count()
        compiler.line_starts.push(files[file_index].base).unwrap()
        for offset in 0L..files[file_index].length {
            if source[files[file_index].base + offset] == 10 {
                if compiler.line_starts.count() >= SOURCE_LINE_START_CAPACITY {
                    fail_parse_limit(env, files[file_index].name, "source line index limit exceeded")
                }
                compiler.line_starts.push(files[file_index].base + offset + 1L).unwrap()
            }
        }
        compiler.file_line_ranges.push(FileLineRange {
            first,
            count: compiler.line_starts.count() - first,
        }).unwrap()
    }
}

fn position_for_offset(
    file_index: long,
    absolute_offset: long,
    compiler: CompilerTables,
) -> SourcePosition {
    let range = compiler.file_line_ranges[file_index]
    var low = 0L
    var high = range.count
    for step in 0L..MAX_PARSER_DEPTH {
        if low >= high { break }
        let middle = low + (high - low) / 2L
        if compiler.line_starts[range.first + middle] <= absolute_offset {
            low = middle + 1L
        } else {
            high = middle
        }
    }
    let line_index = if low == 0L { 0L } else { low - 1L }
    let line_start = compiler.line_starts[range.first + line_index]
    SourcePosition { line: line_index + 1L, col: absolute_offset - line_start + 1L }
}

fn compiler_diagnostic(
    out: Out,
    file: Bytes max 4096,
    position: SourcePosition,
    message: Ascii max 160,
) -> Result<(), IoError> {
    out.write(file)?
    out.write(b":")?
    out.write(str(position.line).bytes())?
    out.write(b":")?
    out.write(str(position.col).bytes())?
    out.write(b": error: ")?
    out.write(message.bytes())?
    out.write(b"\n")
}

fn fail_compiler_diagnostic(
    env: Env,
    file: Bytes max 4096,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    absolute_offset: long,
    compiler: CompilerTables,
    message: Ascii max 160,
) -> never {
    let position = position_for_offset(file_index, files[file_index].base + absolute_offset, compiler)
    if compiler.core_mode {
        fail_core_internal(env, file, position, message)
    } else if compiler.default_context.count() > 0L {
        match env.err.write(file) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b": error: ") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(message.bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
    } else {
        match compiler_diagnostic(env.err, file, position, message) {
            ok(_) => env.exit(2),
            err(_) => env.exit(3),
        }
    }
}

fn node_file_index(
    nodes: list<Node, NODE_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    node: long,
) -> long {
    for file_index in 0L..files.count() {
        let root = files[file_index].tree_root
        if root < 0L { continue }
        let first = node_first_child(nodes, root)
        if node >= first && node <= root { return file_index }
    }
    0L
}

fn token_is_word_at(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    token: long,
    expected: Ascii max 96,
) -> bool {
    if token < 0L || token >= tokens.count() { return false }
    if tokens[token].kind != TokenKind.Ident || tokens[token].length != expected.len() { return false }
    let start = files[file_index].base + tokens[token].start
    for index in 0L..tokens[token].length {
        if source[start + index] != expected.bytes()[index] { return false }
    }
    true
}

fn same_name_tokens(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    left_file: long,
    left_token: long,
    right_file: long,
    right_token: long,
) -> bool {
    if tokens[left_token].length != tokens[right_token].length { return false }
    let left_start = files[left_file].base + tokens[left_token].start
    let right_start = files[right_file].base + tokens[right_token].start
    for index in 0L..tokens[left_token].length {
        if source[left_start + index] != source[right_start + index] { return false }
    }
    true
}

fn token_name_hash(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    token: long,
) -> long {
    var hash = 2166136261L
    let start = files[file_index].base + tokens[token].start
    for index in 0L..tokens[token].length {
        hash = (hash * 16777619L + source[start + index].to_long()) % 4294967291L
    }
    hash
}

fn intern_package_names(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for token in 0L..tokens.count() {
        compiler.token_name_ids.push(-1L).unwrap()
    }
    let doubled_token_count = tokens.count() * 2L
    let desired_slots = if doubled_token_count > INTERN_HASH_CAPACITY { INTERN_HASH_CAPACITY } else { doubled_token_count }
    var slot_count = 1L
    for resize_step in 0L..INTERN_HASH_CAPACITY {
        if slot_count >= desired_slots { break }
        slot_count *= 2L
    }
    let slot_mask = slot_count - 1L
    for slot in 0L..slot_count {
        compiler.intern_slots.push(NameSlot { hash: 0L, token: -1L, file: -1L, id: -1L }).unwrap()
    }
    var next_name_id = 0L
    for file_index in 0L..files.count() {
        let first = files[file_index].first_token
        let last = first + files[file_index].token_count
        for token in first..last {
            if tokens[token].kind != TokenKind.Ident { continue }
            let hash = token_name_hash(source, tokens, files, file_index, token)
            var slot_index = hash & slot_mask
            var inserted = false
            for probe in 0L..slot_count {
                let slot = compiler.intern_slots[slot_index]
                if slot.id < 0L {
                    compiler.intern_slots[slot_index] = NameSlot { hash, token, file: file_index, id: next_name_id }
                    compiler.token_name_ids[token] = next_name_id
                    next_name_id += 1L
                    inserted = true
                    break
                }
                if slot.hash == hash && same_name_tokens(source, tokens, files, file_index, token, slot.file, slot.token) {
                    compiler.token_name_ids[token] = slot.id
                    inserted = true
                    break
                }
                slot_index = (slot_index + 1L) & slot_mask
            }
            if !inserted { fail_parse_limit(env, files[file_index].name, "identifier interning limit exceeded") }
        }
    }
    for name_id in 0L..next_name_id {
        compiler.enum_type_by_name.push(-1L).unwrap()
        compiler.value_type_by_name.push(-1L).unwrap()
        compiler.constant_by_name.push(-1L).unwrap()
        compiler.enum_case_by_name.push(-1L).unwrap()
        compiler.enum_case_name_counts.push(0L).unwrap()
        compiler.reserved_names.push(false).unwrap()
        compiler.range_alias_names.push(false).unwrap()
        match compiler.function_name_present.push(false) {
            ok(_) => (),
            err(_) => fail_tool(env, "compiler function name map capacity exceeded"),
        }
    }
    for node in 0L..tables.nodes.count() {
        let syntax = tables.nodes[node]
        if syntax.kind != NodeKind.Function { continue }
        let token = syntax.token
        if token >= 0L && token < compiler.token_name_ids.count() {
            let name_id = compiler.token_name_ids[token]
            if name_id >= 0L && name_id < compiler.function_name_present.count() {
                compiler.function_name_present[name_id] = true
            }
        }
    }
}

fn function_exists_by_name(
    compiler: CompilerTables,
    name_id: long,
) -> bool {
    name_id >= 0L && name_id < compiler.function_name_present.count() &&
        compiler.function_name_present[name_id]
}

fn binding_is_visible(
    compiler: CompilerTables,
    scope: long,
    wanted_scope: long,
) -> bool {
    var current = scope
    for step in 0L..compiler.scopes.count() + 1L {
        if current < 0L { break }
        if current == wanted_scope { return true }
        current = compiler.scopes[current].parent
    }
    false
}

fn identifier_distance(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    left_file: long,
    left_token: long,
    right_file: long,
    right_token: long,
) -> long {
    let left_length = tokens[left_token].length
    let right_length = tokens[right_token].length
    if left_length > 128L || right_length > 128L { return 3L }
    if left_length > right_length + 2L || right_length > left_length + 2L { return 3L }
    var previous: list<long, 130> = list {}
    var current: list<long, 130> = list {}
    for column in 0L..right_length + 1L { previous.push(column).unwrap() }
    let left_start = files[left_file].base + tokens[left_token].start
    let right_start = files[right_file].base + tokens[right_token].start
    for row in 0L..left_length {
        current.clear()
        current.push(row + 1L).unwrap()
        for column in 0L..right_length {
            let deletion = previous[column + 1L] + 1L
            let insertion = current[column] + 1L
            let substitution = previous[column] + if source[left_start + row] == source[right_start + column] { 0L } else { 1L }
            var best = deletion
            if insertion < best { best = insertion }
            if substitution < best { best = substitution }
            if best > 3L { best = 3L }
            current.push(best).unwrap()
        }
        previous.clear()
        for column in 0L..current.count() { previous.push(current[column]).unwrap() }
    }
    previous[right_length]
}

fn closest_name_candidate(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    token: long,
    file_index: long,
    scope: long,
    is_function: bool,
) -> NameCandidate {
    let name_length = tokens[token].length
    var best = NameCandidate { token: -1L, file: -1L, distance: 3L, length: 0L }
    for function_index in 0L..compiler.functions.count() {
        let function = compiler.functions[function_index]
        let length = tokens[function.name_token].length
        let distance = identifier_distance(source, tokens, files, file_index, token, function.file, function.name_token)
        let threshold = if name_length > length { name_length / 3L + 1L } else { length / 3L + 1L }
        if distance <= 2L && distance <= threshold && (best.token < 0L || distance < best.distance || (distance == best.distance && length < best.length)) {
            best = NameCandidate { token: function.name_token, file: function.file, distance, length }
        }
    }
    if is_function { return best }
    for binding_index in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_index]
        if !binding_is_visible(compiler, scope, binding.scope) { continue }
        let name_token = binding_name_token(binding)
        let length = tokens[name_token].length
        let distance = identifier_distance(source, tokens, files, file_index, token, binding.file, name_token)
        let threshold = if name_length > length { name_length / 3L + 1L } else { length / 3L + 1L }
        if distance <= 2L && distance <= threshold && (best.token < 0L || distance < best.distance || (distance == best.distance && length < best.length)) {
            best = NameCandidate { token: name_token, file: binding.file, distance, length }
        }
    }
    best
}

fn block_for_node(tables: ParseTables, node: long) -> long {
    if node < 0L || node >= tables.nodes.count() { return -1L }
    for candidate in node..tables.nodes.count() {
        let syntax = tables.nodes[candidate]
        if syntax.kind == NodeKind.Program { break }
        let subtree_start = candidate - syntax.subtree + 1L
        if syntax.kind == NodeKind.Block && subtree_start <= node { return candidate }
        if (syntax.kind == NodeKind.Function || syntax.kind == NodeKind.Test) && subtree_start <= node { break }
    }
    -1L
}

fn enclosing_owner(tables: ParseTables, node: long) -> long {
    if node < 0L || node >= tables.nodes.count() { return -1L }
    for candidate: long in node + 1L..tables.nodes.count() {
        let syntax = tables.nodes[candidate]
        if syntax.kind == NodeKind.Program { break }
        if (syntax.kind == NodeKind.Function || syntax.kind == NodeKind.Test) && candidate - syntax.subtree + 1L <= node {
            return candidate
        }
    }
    -1L
}

fn is_shadowed_function_value(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    name_id: long,
) -> bool {
    let owner = enclosing_owner(tables, node)
    if owner < 0L { return false }
    let reference = tables.nodes[node]
    let reference_block = block_for_node(tables, node)
    let first = owner - tables.nodes[owner].subtree + 1L
    for candidate in first..owner + 1L {
        if candidate == node { continue }
        let declaration = tables.nodes[candidate]
        let kind = declaration.kind
        if kind != NodeKind.Parameter && kind != NodeKind.Let && kind != NodeKind.For && kind != NodeKind.ForEach && kind != NodeKind.PatternBinding { continue }
        if kind == NodeKind.ForEach {
            let body = node_children_of_kind(tables, compiler, candidate, NodeKind.Block)
            let visible = body >= 0L && tables.nodes[body].start <= reference.start && tables.nodes[body].end >= reference.end
            if visible && compiler.token_name_ids[declaration.token] == name_id { return true }
            for index_offset in 0L..declaration.aux {
                let index_token = tables.extra[declaration.extra + index_offset]
                if visible && compiler.token_name_ids[index_token] == name_id { return true }
            }
            continue
        }
        if declaration.token < 0L || compiler.token_name_ids[declaration.token] != name_id { continue }
        if kind == NodeKind.Parameter { return true }
        if kind == NodeKind.Let && declaration.end < reference.start {
            let declaration_block = block_for_node(tables, candidate)
            if declaration_block >= 0L && reference_block >= 0L &&
                tables.nodes[declaration_block].start <= tables.nodes[reference_block].start &&
                tables.nodes[declaration_block].end >= tables.nodes[reference_block].end { return true }
        }
        if kind == NodeKind.For {
            let body = node_children_of_kind(tables, compiler, candidate, NodeKind.Block)
            if body >= 0L && tables.nodes[body].start <= reference.start && tables.nodes[body].end >= reference.end { return true }
        }
        if kind == NodeKind.PatternBinding && declaration.end < reference.start {
            var declaration_arm = -1L
            for arm in candidate + 1L..owner {
                let arm_syntax = tables.nodes[arm]
                if arm_syntax.kind == NodeKind.MatchArm && arm - arm_syntax.subtree + 1L <= candidate {
                    declaration_arm = arm
                    break
                }
            }
            if declaration_arm >= 0L {
                let arm_syntax = tables.nodes[declaration_arm]
                if arm_syntax.start <= reference.start && arm_syntax.end >= reference.end { return true }
            }
        }
    }
    false
}

fn is_function_value_name(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    file_index: long,
) -> bool {
    let token = tables.nodes[node].token
    if token < 0L { return false }
    let name_id = compiler.token_name_ids[token]
    function_exists_by_name(compiler, name_id) && !is_shadowed_function_value(tables, compiler, node, name_id)
}

fn builtin_function_name(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    token: long,
) -> bool {
    token_is_word_at(source, tokens, files, file_index, token, "min") ||
    token_is_word_at(source, tokens, files, file_index, token, "max") ||
    token_is_word_at(source, tokens, files, file_index, token, "abs") ||
    token_is_word_at(source, tokens, files, file_index, token, "sort") ||
    token_is_word_at(source, tokens, files, file_index, token, "sort_by") ||
    token_is_word_at(source, tokens, files, file_index, token, "binary_search") ||
    token_is_word_at(source, tokens, files, file_index, token, "stack_peak") ||
    token_is_word_at(source, tokens, files, file_index, token, "str") ||
    token_is_word_at(source, tokens, files, file_index, token, "str_hex") ||
    token_is_word_at(source, tokens, files, file_index, token, "str_bin") ||
    token_is_word_at(source, tokens, files, file_index, token, "parse_int") ||
    token_is_word_at(source, tokens, files, file_index, token, "parse_long") ||
    token_is_word_at(source, tokens, files, file_index, token, "parse_int_radix") ||
    token_is_word_at(source, tokens, files, file_index, token, "parse_long_radix") ||
    token_is_word_at(source, tokens, files, file_index, token, "parse_int_literal") ||
    token_is_word_at(source, tokens, files, file_index, token, "clamp") ||
    token_is_word_at(source, tokens, files, file_index, token, "ascii_upper") ||
    token_is_word_at(source, tokens, files, file_index, token, "pad") ||
    token_is_word_at(source, tokens, files, file_index, token, "pad_right") ||
    token_is_word_at(source, tokens, files, file_index, token, "pad_zero") ||
    token_is_word_at(source, tokens, files, file_index, token, "fill") ||
    token_is_word_at(source, tokens, files, file_index, token, "args") ||
    token_is_word_at(source, tokens, files, file_index, token, "exit") ||
    token_is_word_at(source, tokens, files, file_index, token, "len") ||
    token_is_word_at(source, tokens, files, file_index, token, "count") ||
    token_is_word_at(source, tokens, files, file_index, token, "get") ||
    token_is_word_at(source, tokens, files, file_index, token, "empty") ||
    token_is_word_at(source, tokens, files, file_index, token, "default") ||
    token_is_word_at(source, tokens, files, file_index, token, "width") ||
    token_is_word_at(source, tokens, files, file_index, token, "bytes") ||
    token_is_word_at(source, tokens, files, file_index, token, "to_long")
}

fn builtin_case_name(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    token: long,
) -> bool {
    token_is_word_at(source, tokens, files, file_index, token, "some") ||
    token_is_word_at(source, tokens, files, file_index, token, "none") ||
    token_is_word_at(source, tokens, files, file_index, token, "ok") ||
    token_is_word_at(source, tokens, files, file_index, token, "err") ||
    token_is_word_at(source, tokens, files, file_index, token, "File") ||
    token_is_word_at(source, tokens, files, file_index, token, "Directory") ||
    token_is_word_at(source, tokens, files, file_index, token, "NotFound") ||
    token_is_word_at(source, tokens, files, file_index, token, "NoPermission") ||
    token_is_word_at(source, tokens, files, file_index, token, "TooLarge") ||
    token_is_word_at(source, tokens, files, file_index, token, "TooMany") ||
    token_is_word_at(source, tokens, files, file_index, token, "NameTooLong") ||
    token_is_word_at(source, tokens, files, file_index, token, "BadPath") ||
    token_is_word_at(source, tokens, files, file_index, token, "Outside") ||
    token_is_word_at(source, tokens, files, file_index, token, "InvalidUtf8") ||
    token_is_word_at(source, tokens, files, file_index, token, "NonAscii") ||
    token_is_word_at(source, tokens, files, file_index, token, "Full")
}

fn builtin_sum_case_name(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    token: long,
) -> bool {
    token_is_word_at(source, tokens, files, file_index, token, "some") ||
        token_is_word_at(source, tokens, files, file_index, token, "none") ||
        token_is_word_at(source, tokens, files, file_index, token, "ok") ||
        token_is_word_at(source, tokens, files, file_index, token, "err")
}

fn known_non_scalar_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    token: long,
) -> bool {
    token_is_word_at(source, tokens, files, file_index, token, "never") ||
    token_is_word_at(source, tokens, files, file_index, token, "Env") ||
    token_is_word_at(source, tokens, files, file_index, token, "Fs") ||
    token_is_word_at(source, tokens, files, file_index, token, "Out") ||
    token_is_word_at(source, tokens, files, file_index, token, "Arg") ||
    token_is_word_at(source, tokens, files, file_index, token, "Args") ||
    token_is_word_at(source, tokens, files, file_index, token, "Ascii") ||
    token_is_word_at(source, tokens, files, file_index, token, "Text") ||
    token_is_word_at(source, tokens, files, file_index, token, "Bytes") ||
    token_is_word_at(source, tokens, files, file_index, token, "Id") ||
    token_is_word_at(source, tokens, files, file_index, token, "Option") ||
    token_is_word_at(source, tokens, files, file_index, token, "Result") ||
    token_is_word_at(source, tokens, files, file_index, token, "list") ||
    token_is_word_at(source, tokens, files, file_index, token, "map") ||
    token_is_word_at(source, tokens, files, file_index, token, "set") ||
    token_is_word_at(source, tokens, files, file_index, token, "pool") ||
    token_is_word_at(source, tokens, files, file_index, token, "queue") ||
    token_is_word_at(source, tokens, files, file_index, token, "ring") ||
    token_is_word_at(source, tokens, files, file_index, token, "grid") ||
    token_is_word_at(source, tokens, files, file_index, token, "Path") ||
    token_is_word_at(source, tokens, files, file_index, token, "DirEntry") ||
    token_is_word_at(source, tokens, files, file_index, token, "FileKind") ||
    token_is_word_at(source, tokens, files, file_index, token, "IoError") ||
    token_is_word_at(source, tokens, files, file_index, token, "Full") ||
    token_is_word_at(source, tokens, files, file_index, token, "Utf8Error") ||
    token_is_word_at(source, tokens, files, file_index, token, "TextError")
}

