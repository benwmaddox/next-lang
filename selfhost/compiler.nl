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
    enum_case_name_counts: list<long, TOKEN_STORAGE_CAPACITY>
    enum_type_ids: list<long, TYPE_TABLE_CAPACITY>
    reserved_names: list<bool, TOKEN_STORAGE_CAPACITY>
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
        enum_case_name_counts: list {},
        enum_type_ids: list {},
        reserved_names: list {},
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
    compiler.enum_case_name_counts.clear()
    compiler.enum_type_ids.clear()
    compiler.reserved_names.clear()
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
    for slot in 0L..INTERN_HASH_CAPACITY {
        compiler.intern_slots.push(NameSlot { hash: 0L, token: -1L, file: -1L, id: -1L }).unwrap()
    }
    var next_name_id = 0L
    for file_index in 0L..files.count() {
        let first = files[file_index].first_token
        let last = first + files[file_index].token_count
        for token in first..last {
            if tokens[token].kind != TokenKind.Ident { continue }
            let hash = token_name_hash(source, tokens, files, file_index, token)
            var slot_index = hash % INTERN_HASH_CAPACITY
            var inserted = false
            for probe in 0L..INTERN_HASH_CAPACITY {
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
                slot_index = (slot_index + 1L) % INTERN_HASH_CAPACITY
            }
            if !inserted { fail_parse_limit(env, files[file_index].name, "identifier interning limit exceeded") }
        }
    }
    for name_id in 0L..next_name_id {
        compiler.enum_type_by_name.push(-1L).unwrap()
        compiler.enum_case_name_counts.push(0L).unwrap()
        compiler.reserved_names.push(false).unwrap()
    }
}

fn function_exists_by_name(
    tables: ParseTables,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    name_id: long,
) -> bool {
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.Function {
            let token = tables.nodes[node].token
            if token >= 0L && compiler.token_name_ids[token] == name_id { return true }
        }
    }
    false
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
    function_exists_by_name(tables, files, compiler, name_id) && !is_shadowed_function_value(tables, compiler, node, name_id)
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

fn append_type_record(compiler: write CompilerTables, record: TypeRecord) -> long {
    let type_id = compiler.type_records.count()
    compiler.type_records.push(record).unwrap()
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
    var found = -1L
    for type_id in 0L..compiler.type_records.count() {
        let kind = type_record_kind(compiler.type_records[type_id])
        if (kind == TYPE_KIND_STRUCT || kind == TYPE_KIND_ENUM) && compiler.type_records[type_id].name_id == name_id {
            if found >= 0L { return -1L }
            found = type_id
        }
    }
    found
}

fn value_type_for_node(compiler: CompilerTables, node: long) -> long {
    for type_id in 0L..compiler.type_records.count() {
        let kind = type_record_kind(compiler.type_records[type_id])
        if (kind == TYPE_KIND_STRUCT || kind == TYPE_KIND_ENUM) && compiler.type_records[type_id].node == node { return type_id }
    }
    -1L
}

fn user_case_matches(compiler: CompilerTables, name_id: long) -> long {
    var found = -1L
    for enum_index in 0L..enum_type_count(compiler) {
        let type_id = enum_type_id(compiler, enum_index)
        let case_index = enum_case_matches(compiler, type_id, name_id)
        if case_index >= 0L {
            if found >= 0L { return -2L }
            found = case_index
        }
    }
    found
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
        kind == TYPE_KIND_ARRAY || kind == TYPE_KIND_LIST || kind == TYPE_KIND_ASCII || kind == TYPE_KIND_TEXT || kind == TYPE_KIND_BYTES
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

fn intern_written_type_instances(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for node in 0L..tables.nodes.count() {
        let syntax = tables.nodes[node]
        if !is_type_node(syntax.kind) { continue }
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
        }
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
            root_kind != TYPE_KIND_ARRAY && root_kind != TYPE_KIND_LIST { continue }
        if type_state(compiler, root_type) != 0L { continue }
        set_type_state(compiler, root_type, 1L)
        compiler.type_walk.push(initial_type_walk_frame(compiler, root_type)).unwrap()
        for walk_step in 0L..MAX_TREE_NODES {
            if compiler.type_walk.count() == 0L { break }
            let frame_index = compiler.type_walk.count() - 1L
            var frame = compiler.type_walk[frame_index]
            let type_info = type_record(compiler, frame.type_index)
            let frame_kind = type_kind(compiler, frame.type_index)
            if frame_kind == TYPE_KIND_ARRAY || frame_kind == TYPE_KIND_LIST {
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
                    if (element_kind == TYPE_KIND_STRUCT || is_sum_type(compiler, element_ty) || element_kind == TYPE_KIND_ARRAY || element_kind == TYPE_KIND_LIST) && type_state(compiler, element_ty) == 0L {
                        set_type_state(compiler, element_ty, 1L)
                        compiler.type_walk.push(initial_type_walk_frame(compiler, element_ty)).unwrap()
                        continue
                    }
                    set_type_state(compiler, frame.type_index, if type_state(compiler, element_ty) == 1L || type_state(compiler, element_ty) == 4L { 4L } else { 3L })
                    let _ = compiler.type_walk.pop()
                    continue
                }
                let size = type_group_size(compiler, frame.type_index, 1L)
                let alignment = if frame_kind == TYPE_KIND_LIST && element_align < 8L { 8L }
                    else if frame_kind == TYPE_KIND_LIST { element_align }
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
                    if (child_kind == TYPE_KIND_STRUCT || is_sum_type(compiler, ty) || child_kind == TYPE_KIND_ARRAY || child_kind == TYPE_KIND_LIST) && type_state(compiler, ty) == 0L {
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
                    if (type_kind(compiler, ty) == TYPE_KIND_STRUCT || is_sum_type(compiler, ty) || type_kind(compiler, ty) == TYPE_KIND_ARRAY || type_kind(compiler, ty) == TYPE_KIND_LIST) && type_state(compiler, ty) == 0L {
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
        NodeKind.TypeAlias => UNSUPPORTED_NODE,
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
        NodeKind.AliasedType => UNSUPPORTED_NODE,
        NodeKind.DeclaredType => if compiler.facts[node].ty == TY_LONG { 0L } else { UNSUPPORTED_NODE },
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
                if function_exists_by_name(tables, files, compiler, id) { 0L } else { UNSUPPORTED_CALLEE }
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

fn manifest_equals(contents: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long, expected: Ascii max 64) -> bool {
    if end - start != expected.len() { return false }
    for index in 0L..expected.len() {
        if contents[start + index] != expected.bytes()[index] { return false }
    }
    true
}

fn manifest_number(contents: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> long {
    if start >= end { return -1L }
    var value = 0L
    var had_digit = false
    for index in start..end {
        let digit = contents[index]
        if digit == 95 { continue }
        let digit_value = digit.to_long()
        if digit_value < 48L || digit_value > 57L { return -1L }
        had_digit = true
        if value > 922337203685477580L { return -1L }
        value = value * 10L + (digit_value - 48L)
        if value < 0L { return -1L }
    }
    if !had_digit { -1L } else { value }
}

fn manifest_step_budget_number(contents: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> long {
    if start >= end { return -1L }
    var value = 0L
    var had_digit = false
    var previous_was_digit = false
    for index in start..end {
        let digit = contents[index]
        let digit_value = digit.to_long()
        if digit_value >= 48L && digit_value <= 57L {
            let number = digit_value - 48L
            if value > (9223372036854775807L - number) / 10L { return -1L }
            value = value * 10L + number
            had_digit = true
            previous_was_digit = true
        } else if digit == 95 {
            if !previous_was_digit || index + 1L >= end || contents[index + 1L].to_long() < 48L || contents[index + 1L].to_long() > 57L { return -1L }
            previous_was_digit = false
        } else {
            return -1L
        }
    }
    if !had_digit || !previous_was_digit { -1L } else { value }
}

fn manifest_step_budget_assignment_malformed(
    contents: Bytes max FILE_SOURCE_CAPACITY,
    start: long,
    end: long,
) -> bool {
    var key_end = start
    for index in start..end {
        if contents[index] == 61 || ascii_space(contents[index]) { break }
        key_end = index + 1L
    }
    if !manifest_equals(contents, start, key_end, "step_budget.main") { return false }
    var value_start = key_end
    for index in key_end..end {
        if !ascii_space(contents[index]) {
            value_start = index
            break
        }
        value_start = end
    }
    value_start >= end || contents[value_start] != 61
}

fn manifest_memory(contents: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> long {
    let unit_start = trim_start(contents, start, end)
    let trimmed_end = trim_end(contents, unit_start, end)
    var number_end = trimmed_end
    var multiplier = 1048576L
    if trimmed_end - unit_start >= 3L && contents[trimmed_end - 3L] == 71 && contents[trimmed_end - 2L] == 105 && contents[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 3L
        multiplier = 1073741824L
    } else if trimmed_end - unit_start >= 3L && contents[trimmed_end - 3L] == 77 && contents[trimmed_end - 2L] == 105 && contents[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 3L
        multiplier = 1048576L
    } else if trimmed_end - unit_start >= 3L && contents[trimmed_end - 3L] == 75 && contents[trimmed_end - 2L] == 105 && contents[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 3L
        multiplier = 1024L
    } else if trimmed_end - unit_start >= 2L && contents[trimmed_end - 2L] == 71 && contents[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 2L
        multiplier = 1000000000L
    } else if trimmed_end - unit_start >= 2L && contents[trimmed_end - 2L] == 77 && contents[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 2L
        multiplier = 1000000L
    } else if trimmed_end - unit_start >= 2L && contents[trimmed_end - 2L] == 75 && contents[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 2L
        multiplier = 1000L
    } else if trimmed_end - unit_start >= 1L && contents[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 1L
        multiplier = 1L
    } else {
        ()
    }
    let trimmed_number_end = trim_end(contents, unit_start, number_end)
    let value = manifest_number(contents, unit_start, trimmed_number_end)
    if value < 0L || value > 9223372036854775807L / multiplier { return -1L }
    value * multiplier
}

fn write_manifest_range(out: Out, contents: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> Result<(), IoError> {
    var value: Bytes max 4096 = Bytes.empty()
    for index in start..end {
        match value.push(contents[index]) {
            ok(_) => (),
            err(_) => return err(IoError.TooLarge),
        }
    }
    out.write(value)
}

fn write_manifest_tool_error(
    env: Env,
    path: Bytes max 4096,
    line: long,
    prefix: Ascii max 160,
) -> never {
    match env.err.write(b"nlc: tool failure: ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(path) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(prefix.bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(3), err(_) => env.exit(3) }
}

fn load_manifest(
    env: Env,
    package: Arg,
) -> MemoryConfig {
    var config = MemoryConfig { capability_mask: 2L, job_headroom: 268435456L, globals_budget: 67108864L, recursion_budget: 0L, step_budget_main: -1L }
    let manifest_path = match env.fs.join(package, "package.toml") {
        ok(path) => path,
        err(_) => fail_tool(env, "cannot join package manifest path"),
    }
    let display_path = display_name(manifest_path)
    var contents: Bytes max FILE_SOURCE_CAPACITY = Bytes.empty()
    match env.fs.read(manifest_path, contents) {
        ok(_) => (),
        err(error) => {
            if error == IoError.NotFound { return config }
            fail_tool(env, "cannot read package manifest")
        },
    }
    match contents.validate_utf8() {
        ok(_) => (),
        err(_) => fail_tool(env, "package manifest is not valid UTF-8"),
    }
    var capabilities_seen = false
    var step_budget_main_seen = false
    var line_number = 1L
    var line_start = 0L
    for step in 0L..contents.count() + 1L {
        if step < contents.count() && contents[step] != 10 { continue }
        let raw_end = step
        var end = raw_end
        for trim_step in 0L..raw_end - line_start {
            if end <= line_start || contents[end - 1L] != 13 { break }
            end -= 1L
        }
        var comment = end
        for offset in line_start..end {
            if contents[offset] == 35 { comment = offset; break }
        }
        let first = trim_start(contents, line_start, comment)
        let last = trim_end(contents, first, comment)
        if first < last && !(contents[first] == 91 && contents[last - 1L] == 93) {
            if manifest_step_budget_assignment_malformed(contents, first, last) {
                write_manifest_tool_error(env, display_path, line_number, "expected step_budget.main = <nonnegative integer step count>")
            }
            var equals = -1L
            for offset in first..last {
                if contents[offset] == 61 { equals = offset; break }
            }
            if equals >= 0L {
                let key_start = trim_start(contents, first, equals)
                let key_end = trim_end(contents, key_start, equals)
                let value_start = trim_start(contents, equals + 1L, last)
                let value_end = trim_end(contents, value_start, last)
                if manifest_equals(contents, key_start, key_end, "capabilities") {
                    if capabilities_seen { write_manifest_tool_error(env, display_path, line_number, "capabilities is listed more than once") }
                    capabilities_seen = true
                    if value_end - value_start < 2L || contents[value_start] != 91 || contents[value_end - 1L] != 93 {
                        write_manifest_tool_error(env, display_path, line_number, "expected capabilities to be an array such as [\"fs\", \"out\"]")
                    }
                    config.capability_mask = 0L
                    var item_start = value_start + 1L
                    let item_end = value_end - 1L
                    for item_step in 0L..item_end - item_start + 1L {
                        if item_start >= item_end || contents[item_start] == 44 {
                            let item_left = trim_start(contents, item_start, if item_start < item_end { item_start } else { item_end })
                            let _ = item_left
                            item_start += 1L
                            continue
                        }
                        var comma = item_start
                        for scan in item_start..item_end {
                            if contents[scan] == 44 { comma = scan; break }
                            comma = scan + 1L
                        }
                        let left = trim_start(contents, item_start, comma)
                        let right = trim_end(contents, left, comma)
                        if right <= left || right - left < 2L || contents[left] != 34 || contents[right - 1L] != 34 {
                            write_manifest_tool_error(env, display_path, line_number, "capability names must be quoted strings")
                        }
                        let cap_start = left + 1L
                        let cap_end = right - 1L
                        let bit = if manifest_equals(contents, cap_start, cap_end, "fs") { 1L }
                            else if manifest_equals(contents, cap_start, cap_end, "out") { 2L }
                            else if manifest_equals(contents, cap_start, cap_end, "env") { 4L }
                            else { -1L }
                        if bit < 0L {
                            match env.err.write(b"nlc: tool failure: ") { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(display_path) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(str(line_number).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b": unknown capability '") { ok(_) => (), err(_) => env.exit(3) }
                            match write_manifest_range(env.err, contents, cap_start, cap_end) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b"'; capabilities currently supports fs, out, and env\n") { ok(_) => env.exit(3), err(_) => env.exit(3) }
                        }
                        if (config.capability_mask & bit) != 0L {
                            match env.err.write(b"nlc: tool failure: ") { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(display_path) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(str(line_number).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b": capability '") { ok(_) => (), err(_) => env.exit(3) }
                            match write_manifest_range(env.err, contents, cap_start, cap_end) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b"' is listed more than once\n") { ok(_) => env.exit(3), err(_) => env.exit(3) }
                        }
                        config.capability_mask = config.capability_mask | bit
                        item_start = comma + 1L
                    }
                } else if manifest_equals(contents, key_start, key_end, "step_budget.main") {
                    if step_budget_main_seen { write_manifest_tool_error(env, display_path, line_number, "step_budget.main is listed more than once") }
                    step_budget_main_seen = true
                    let budget = manifest_step_budget_number(contents, value_start, value_end)
                    if budget < 0L {
                        write_manifest_tool_error(env, display_path, line_number, "expected step_budget.main to be a nonnegative integer step count")
                    }
                    config.step_budget_main = budget
                } else if manifest_equals(contents, key_start, key_end, "job_headroom") || manifest_equals(contents, key_start, key_end, "globals_budget") || manifest_equals(contents, key_start, key_end, "recursion_budget") {
                    let memory = manifest_memory(contents, value_start, value_end)
                    if memory < 0L {
                        let message: Ascii max 160 = if manifest_equals(contents, key_start, key_end, "job_headroom") { "expected job_headroom to be a nonnegative byte count or MB value" }
                            else if manifest_equals(contents, key_start, key_end, "globals_budget") { "expected globals_budget to be a nonnegative byte count or MB value" }
                            else { "expected recursion_budget to be a nonnegative byte count or MB value" }
                        write_manifest_tool_error(env, display_path, line_number, message)
                    }
                    if manifest_equals(contents, key_start, key_end, "job_headroom") { config.job_headroom = memory }
                    else if manifest_equals(contents, key_start, key_end, "globals_budget") { config.globals_budget = memory }
                    else { config.recursion_budget = memory }
                } else {
                    ()
                }
            }
        }
        line_start = step + 1L
        line_number += 1L
    }
    config
}

fn scalar_type_name(ty: long) -> Ascii max 16 {
    if ty == TY_INT { "int" }
    else if ty == TY_LONG { "long" }
    else if ty == TY_BOOL { "bool" }
    else if ty == TY_BYTE { "byte" }
    else if ty == TY_UNIT { "()" }
    else if ty == TY_ADDR { "sys.Addr" }
    else { "never" }
}

fn parse_scalar_type(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
) -> long {
    let value = tables.nodes[node]
    let resolved = resolve_value_type(source, tokens, files, tables, compiler, file_index, node)
    if resolved >= 0L { return resolved }
    let sum_kind = generic_type_kind(source, tokens, files, tables, file_index, node)
    let required_arguments = if sum_kind == TYPE_KIND_OPTION { 1L } else if sum_kind == TYPE_KIND_RESULT { 2L } else { 0L }
    let actual_arguments = value.meta1 & 2097151L
    let has_extra_type_form = ((value.meta1 >> 21L) & 2097151L) != 0L ||
        ((value.meta1 >> 42L) & 2097151L) != 0L || (value.flags & FLAG_RANGE) != 0L
    if required_arguments > 0L && (actual_arguments != required_arguments || has_extra_type_form) {
        let file = files[file_index]
        let position = position_for_offset(file_index, file.base + value.start, compiler)
        match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b": error: type '") { ok(_) => (), err(_) => env.exit(3) }
        match write_token_raw(env.err, source, tokens, file.base, value.token) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b"' has an invalid number or form of type parameters\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
    }
    let file = files[file_index]
    let position = position_for_offset(file_index, file.base + value.start, compiler)
    match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: unknown type '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, file.base, value.token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"'; declare it with enum\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn is_builtin_type_name(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    token: long,
) -> bool {
    token_is_word_at(source, tokens, files, file_index, token, "int") ||
    token_is_word_at(source, tokens, files, file_index, token, "long") ||
    token_is_word_at(source, tokens, files, file_index, token, "bool") ||
    token_is_word_at(source, tokens, files, file_index, token, "byte") ||
    token_is_word_at(source, tokens, files, file_index, token, "Ascii") ||
    token_is_word_at(source, tokens, files, file_index, token, "Text") ||
    token_is_word_at(source, tokens, files, file_index, token, "Bytes") ||
    token_is_word_at(source, tokens, files, file_index, token, "Option") ||
    token_is_word_at(source, tokens, files, file_index, token, "Result") ||
    token_is_word_at(source, tokens, files, file_index, token, "Full") ||
    token_is_word_at(source, tokens, files, file_index, token, "TextError") ||
    token_is_word_at(source, tokens, files, file_index, token, "Utf8Error") ||
    (compiler.c_runtime && (
        token_is_word_at(source, tokens, files, file_index, token, "Env") ||
        token_is_word_at(source, tokens, files, file_index, token, "Fs") ||
        token_is_word_at(source, tokens, files, file_index, token, "Out") ||
        token_is_word_at(source, tokens, files, file_index, token, "Args") ||
        token_is_word_at(source, tokens, files, file_index, token, "Arg") ||
        token_is_word_at(source, tokens, files, file_index, token, "Path") ||
        token_is_word_at(source, tokens, files, file_index, token, "DirEntry") ||
        token_is_word_at(source, tokens, files, file_index, token, "FileKind") ||
        token_is_word_at(source, tokens, files, file_index, token, "IoError")
    ))
}

fn has_prior_type_name(
    tables: ParseTables,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    file_index: long,
    node: long,
    name_id: long,
) -> bool {
    for prior_file in 0L..files.count() {
        let root = files[prior_file].tree_root
        for phase in 0L..2L {
            var child = compiler.child_first[root]
            for step in 0L..tables.nodes[root].subtree {
                if child < 0L { break }
                let kind = tables.nodes[child].kind
                let wanted = if phase == 0L { NodeKind.Enum } else { NodeKind.Struct }
                if kind == wanted {
                    if prior_file == file_index && child == node { return false }
                    if prior_file > file_index { return false }
                    if compiler.token_name_ids[tables.nodes[child].token] == name_id { return true }
                }
                child = compiler.child_next[child]
            }
        }
    }
    false
}

fn fail_duplicate_struct_field(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    field_index: long,
    previous_index: long,
) -> never {
    let current = compiler.struct_fields[field_index]
    let owner = struct_record(compiler, current.owner)
    let position = position_for_offset(owner.file, files[owner.file].base + tables.nodes[current.node].start, compiler)
    let previous_position = position_for_offset(owner.file, files[owner.file].base + tables.nodes[compiler.struct_fields[previous_index].node].start, compiler)
    match env.err.write(files[owner.file].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: field '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[owner.file].base, current.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"' is declared twice (first on line ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(previous_position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b")\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn check_struct_declarations(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    // Rust registers type names per file, with enums before structs.
    for file_index in 0L..files.count() {
        let root = files[file_index].tree_root
        for phase in 0L..2L {
            var child = compiler.child_first[root]
            for step in 0L..tables.nodes[root].subtree {
                if child < 0L { break }
                let kind = tables.nodes[child].kind
                let wanted = if phase == 0L { NodeKind.Enum } else { NodeKind.Struct }
                if kind == wanted {
                    let declaration = tables.nodes[child]
                    let name_id = compiler.token_name_ids[declaration.token]
                    if is_builtin_type_name(source, tokens, files, compiler, file_index, declaration.token) ||
                        has_prior_type_name(tables, files, tokens, compiler, file_index, child, name_id) {
                        fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, declaration.start, "type '", declaration.token, "' is declared more than once or shadows a built-in type")
                    }
                }
                child = compiler.child_next[child]
            }
        }
    }
    // Enum cases and payload types are checked across every file before any
    // struct field is visited, matching checker.rs::fill_enum_cases.
    for enum_index in 0L..enum_type_count(compiler) {
        let ty = enum_record(compiler, enum_index)
        if ty.node < 0L { continue }
        for case_offset in 0L..ty.field_count {
            let case_index = ty.field_start + case_offset
            let current = compiler.enum_cases[case_index]
            for previous_offset in 0L..case_offset {
                let previous_index = ty.field_start + previous_offset
                if compiler.enum_cases[previous_index].name_id == current.name_id {
                    let previous_position = position_for_offset(ty.file, files[ty.file].base + tables.nodes[compiler.enum_cases[previous_index].node].start, compiler)
                    let position = position_for_offset(ty.file, files[ty.file].base + tables.nodes[current.node].start, compiler)
                    match env.err.write(files[ty.file].name) { ok(_) => (), err(_) => env.exit(3) }
                    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
                    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
                    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                    match env.err.write(b": error: case '") { ok(_) => (), err(_) => env.exit(3) }
                    match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) }
                    match env.err.write(b".") { ok(_) => (), err(_) => env.exit(3) }
                    match write_token_raw(env.err, source, tokens, files[ty.file].base, current.name_token) { ok(_) => (), err(_) => env.exit(3) }
                    match env.err.write(b"' is declared twice (first on line ") { ok(_) => (), err(_) => env.exit(3) }
                    match env.err.write(str(previous_position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                    match env.err.write(b")\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
                }
            }
            for payload_offset in 0L..current.payload_count {
                let payload_index = current.payload_start + payload_offset
                let payload = compiler.enum_payloads[payload_index]
                compiler.enum_payloads[payload_index].ty = parse_scalar_type(env, source, tokens, files, tables, compiler, ty.file, payload.type_node)
            }
        }
    }
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        if ty.node < 0L { continue }
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            for prior_offset in 0L..offset {
                let previous_index = ty.field_start + prior_offset
                if compiler.struct_fields[previous_index].name_id == field.name_id {
                    fail_duplicate_struct_field(env, source, files, tokens, tables, compiler, field_index, previous_index)
                }
            }
            let field_ty = parse_scalar_type(env, source, tokens, files, tables, compiler, ty.file, field.type_node)
            compiler.struct_fields[field_index].ty = field_ty
            if field_ty == TY_UNIT {
                fail_compiler_diagnostic(env, files[ty.file].name, files, ty.file, tables.nodes[field.node].start, compiler, "a struct field must have a storable value type; use an enum unit case for ()")
            }
        }
    }
    // Infinite-size checking follows the same per-file enum-then-struct order.
    for file_index in 0L..files.count() {
        let root = files[file_index].tree_root
        for phase in 0L..2L {
            var child = compiler.child_first[root]
            for step in 0L..tables.nodes[root].subtree {
                if child < 0L { break }
                let kind = tables.nodes[child].kind
                let wanted = if phase == 0L { NodeKind.Enum } else { NodeKind.Struct }
                if kind == wanted {
                    for type_id in 0L..type_count(compiler) {
                        let ty = type_record(compiler, type_id)
                        if ty.node == child && type_state(compiler, type_id) == 4L {
                            fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, tables.nodes[child].start, "value type '", ty.name_token, "' contains itself directly or through Option/Result and would have infinite size")
                        }
                    }
                }
                child = compiler.child_next[child]
            }
        }
    }
}

fn node_children_of_kind(
    tables: ParseTables,
    compiler: CompilerTables,
    parent: long,
    wanted: NodeKind,
) -> long {
    var child = compiler.child_first[parent]
    for step in 0L..tables.nodes[parent].subtree {
        if child < 0L { break }
        if tables.nodes[child].kind == wanted { return child }
        child = compiler.child_next[child]
    }
    -1L
}

fn count_node_children_of_kind(
    tables: ParseTables,
    compiler: CompilerTables,
    parent: long,
    wanted: NodeKind,
) -> long {
    var item_count = 0L
    var child = compiler.child_first[parent]
    for step in 0L..tables.nodes[parent].subtree {
        if child < 0L { break }
        if tables.nodes[child].kind == wanted { item_count += 1L }
        child = compiler.child_next[child]
    }
    item_count
}

fn decoded_string_equal(left: Bytes max 16777217, right: Bytes max 16777217) -> bool {
    if left.count() != right.count() { return false }
    for index in 0L..left.count() {
        if left[index] != right[index] { return false }
    }
    true
}

fn fail_dynamic_checker_error(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    file_index: long,
    offset: long,
    prefix: Ascii max 160,
    token: long,
    suffix: Ascii max 160,
) -> never {
    let file = files[file_index]
    let position = position_for_offset(file_index, file.base + offset, compiler)
    match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(prefix.bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, file.base, token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(suffix.bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

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
    var current_scope = scope
    for scope_step in 0L..compiler.scopes.count() + 1L {
        if current_scope < 0L { break }
        var binding = compiler.bindings.count()
        for binding_step in 0L..compiler.bindings.count() {
            if binding <= 0L { break }
            binding -= 1L
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
    for prior in 0L..compiler.bindings.count() {
        if compiler.bindings[prior].scope == scope && compiler.bindings[prior].name_id == name_id {
            let previous = compiler.bindings[prior]
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
    }
    let visible_binding = find_binding_in_scope(compiler, scope, name_id)
    if visible_binding >= 0L {
        let previous = compiler.bindings[visible_binding]
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
    if actual == TY_NEVER || actual == expected || text_width_fits(compiler, actual, expected) { return }
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
                if constant >= 0L && (compiler.facts[constant].flags & FACT_CONSTANT_EVALUATED) != 0L { TY_LONG }
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

fn find_constant_declaration(tables: ParseTables, compiler: CompilerTables, name_id: long) -> long {
    for candidate in 0L..tables.nodes.count() {
        if tables.nodes[candidate].kind != NodeKind.Const { continue }
        let token = tables.nodes[candidate].token
        if token >= 0L && token < compiler.token_name_ids.count() && compiler.token_name_ids[token] == name_id {
            return candidate
        }
    }
    -1L
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

fn scalar_constant_declaration_is_long(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    declaration: long,
) -> bool {
    if declaration < 0L || declaration >= tables.nodes.count() { return false }
    let type_node = compiler.child_first[declaration]
    if type_node < 0L || tables.nodes[type_node].kind != NodeKind.DeclaredType { return false }
    let file_index = node_file_index(tables.nodes, files, type_node)
    let syntax = tables.nodes[type_node]
    token_is_word_at(source, tokens, files, file_index, syntax.token, "long") &&
        syntax.flags == 0L && syntax.meta0 == 1L && syntax.meta1 == 0L &&
        compiler.child_first[type_node] < 0L
}

fn fail_scalar_constant_type(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    tables: ParseTables,
    file_index: long,
    node: long,
) -> never {
    fail_at_message(env, files, compiler, file_index, tables.nodes[node].start, "constant initializer must have type long")
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
    compiler.facts[declaration].flags = FACT_CONSTANT_DECLARED | FACT_CONSTANT_VISITING
    let expression = node_last_child(tables, compiler, declaration)
    let value = evaluate_scalar_constant_expression(
        env, source, tokens, files, tables, compiler, expression, depth + 1L,
    )
    if !value.supported {
        compiler.facts[declaration].flags = FACT_CONSTANT_DECLARED
        return value
    }
    compiler.facts[declaration] = NodeFact {
        ty: TY_LONG,
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
        scalar_constant_value(literal_value(env, source, tokens, files, compiler, tables, file_index, node, TY_LONG))
    } else if syntax.kind == NodeKind.Name {
        let name_id = compiler.token_name_ids[syntax.token]
        let declaration = find_constant_declaration(tables, compiler, name_id)
        if declaration >= 0L {
            if (compiler.facts[declaration].flags & FACT_CONSTANT_DECLARED) == 0L { return unsupported_scalar_constant() }
            evaluate_scalar_constant_declaration(env, source, tokens, files, tables, compiler, declaration, depth + 1L)
        } else if user_case_matches(compiler, name_id) >= 0L ||
            package_has_enum_case_name(tables, compiler, name_id) ||
            builtin_case_name(source, tokens, files, file_index, syntax.token) {
            fail_scalar_constant_type(env, files, compiler, tables, file_index, node)
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
        let value = evaluate_scalar_constant_expression(env, source, tokens, files, tables, compiler, child, depth + 1L)
        if !value.supported { return value }
        let negated = checked_capacity_negate(value.value)
        if !negated.valid { fail_at_message(env, files, compiler, file_index, syntax.start, "constant arithmetic overflows long") }
        scalar_constant_value(negated.value)
    } else if syntax.kind == NodeKind.Unary && syntax.flags == 1L {
        fail_scalar_constant_type(env, files, compiler, tables, file_index, node)
    } else if syntax.kind == NodeKind.Unary {
        unsupported_scalar_constant()
    } else if syntax.kind == NodeKind.Binary && syntax.flags >= 0L && syntax.flags <= 4L {
        let left_node = compiler.child_first[node]
        let right_node = if left_node >= 0L { compiler.child_next[left_node] } else { -1L }
        let left = evaluate_scalar_constant_expression(env, source, tokens, files, tables, compiler, left_node, depth + 1L)
        if !left.supported { return left }
        let right = evaluate_scalar_constant_expression(env, source, tokens, files, tables, compiler, right_node, depth + 1L)
        if !right.supported { return right }
        if syntax.flags == 0L {
            let result = checked_capacity_add(left.value, right.value)
            if !result.valid { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant arithmetic overflows long") }
            scalar_constant_value(result.value)
        } else if syntax.flags == 1L {
            let result = checked_capacity_subtract(left.value, right.value)
            if !result.valid { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant arithmetic overflows long") }
            scalar_constant_value(result.value)
        } else if syntax.flags == 2L {
            let result = checked_capacity_multiply(left.value, right.value)
            if !result.valid { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant arithmetic overflows long") }
            scalar_constant_value(result.value)
        } else if syntax.flags == 3L {
            if right.value == 0L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant division by zero") }
            let result = checked_capacity_divide(left.value, right.value)
            if !result.valid { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant arithmetic overflows long") }
            scalar_constant_value(result.value)
        } else {
            if right.value == 0L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant remainder by zero") }
            let result = checked_capacity_remainder(left.value, right.value)
            if !result.valid { fail_at_message(env, files, compiler, file_index, syntax.anchor, "constant arithmetic overflows long") }
            scalar_constant_value(result.value)
        }
    } else if syntax.kind == NodeKind.Bool || syntax.kind == NodeKind.ByteString ||
        syntax.kind == NodeKind.BytesLiteral || syntax.kind == NodeKind.ArrayLiteral ||
        syntax.kind == NodeKind.ListLiteral || syntax.kind == NodeKind.StructInit ||
        syntax.kind == NodeKind.Unit {
        fail_scalar_constant_type(env, files, compiler, tables, file_index, node)
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
        if scalar_constant_declaration_is_long(source, tokens, files, tables, compiler, node) {
            compiler.facts[node] = NodeFact {
                ty: TY_LONG,
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
    } else if kind == NodeKind.MethodCall && frame.child0 >= 0L &&
        c_runtime_method_kind(source, tokens, files, compiler, file_index, tables.nodes[parent].token, compiler.facts[frame.child0].ty) != C_METHOD_NONE {
        c_runtime_child_expected(source, tokens, files, compiler, file_index, tables.nodes[parent].token,
            compiler.facts[frame.child0].ty, child_index)
    } else if kind == NodeKind.MethodCall && is_core_sys_receiver(source, tokens, files, tables, compiler, parent, file_index) {
        core_sys_argument_type(core_sys_operation(source, tokens, files, file_index, tables.nodes[parent].token), child_index)
    } else if kind == NodeKind.MethodCall && frame.child0 >= 0L &&
        (type_kind(compiler, compiler.facts[frame.child0].ty) == TYPE_KIND_ARRAY || type_kind(compiler, compiler.facts[frame.child0].ty) == TYPE_KIND_LIST) {
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
        if method == TEXT_METHOD_PUSH && child_index == 0L { TY_BYTE }
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

fn check_one_body(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    config: MemoryConfig,
    compiler: write CompilerTables,
    body: long,
    file_index: long,
    function_id: long,
    result_ty: long,
    is_test: bool,
    root_scope: long,
) {
    compiler.work.clear()
    compiler.loop_push_proofs.clear()
    compiler.collection_count_changes.clear()
    compiler.collection_count_branch_values.clear()
    compiler.collection_count_joins.clear()
    compiler.loop_count_snapshots.clear()
    push_check_frame(env, files, compiler, CheckFrame {
        node: body,
        scope: root_scope,
        expected: result_ty,
        function_id,
        loop_depth: 0L,
        is_test,
        phase: 0L,
        cursor: -1L,
        child0: -1L,
        child1: -1L,
        child2: -1L,
        result_ty: -1L,
        auxiliary: 1L,
        reachable: true,
    })
    for work_step in 0L..MAX_PARSE_WORK {
        if compiler.work.count() == 0L { break }
        let frame_index = compiler.work.count() - 1L
        var frame = compiler.work[frame_index]
        let node = frame.node
        let syntax = tables.nodes[node]
        let kind = syntax.kind
        if kind == NodeKind.Match && frame.phase == 0L {
            frame.child0 = compiler.child_first[node]
            frame.cursor = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
            frame.auxiliary = begin_collection_count_join(compiler, node, 1L)
            frame.phase = 70L
            compiler.work[frame_index] = frame
            if frame.child0 >= 0L {
                push_check_frame(env, files, compiler, CheckFrame {
                    node: frame.child0,
                    scope: frame.scope,
                    expected: -1L,
                    function_id,
                    loop_depth: frame.loop_depth,
                    is_test,
                    phase: 0L,
                    cursor: -1L,
                    child0: -1L,
                    child1: -1L,
                    child2: -1L,
                    result_ty: -1L,
                    auxiliary: 0L,
                    reachable: true,
                })
            }
            continue
        }
        if kind == NodeKind.Match && frame.phase == 70L {
            let matched_type = compiler.facts[frame.child0].ty
            if !compiler.collection_count_joins[frame.auxiliary].started {
                start_collection_count_join(compiler, frame.auxiliary)
            }
            if !is_sum_type(compiler, matched_type) && !is_numeric_type(matched_type) && matched_type != TY_BYTE && matched_type != TY_BOOL {
                fail_match_requires_supported_type(env, source, files, tokens, tables, compiler, file_index, node, matched_type)
            }
            let arm = frame.cursor
            if arm < 0L {
                if !match_has_prior_wildcard(tables, compiler, node, -1L) {
                    if is_sum_type(compiler, matched_type) {
                        if match_covered_count(tables, compiler, node, MATCH_PATTERN_CASE) != sum_case_count(compiler, matched_type) {
                            fail_match_exhaustiveness(env, source, files, tokens, tables, compiler, file_index, node, matched_type)
                        }
                    } else if matched_type == TY_BOOL {
                        if match_covered_count(tables, compiler, node, MATCH_PATTERN_BOOL) != 2L {
                            fail_match_exhaustiveness(env, source, files, tokens, tables, compiler, file_index, node, matched_type)
                        }
                    } else {
                        fail_match_exhaustiveness(env, source, files, tokens, tables, compiler, file_index, node, matched_type)
                    }
                }
                let match_result_ty = if frame.result_ty < 0L { TY_NEVER } else { frame.result_ty }
                if frame.expected >= 0L && match_result_ty != TY_NEVER && match_result_ty != frame.expected {
                    require_type(env, files, compiler, file_index, node, frame.expected, match_result_ty, tables)
                }
                finish_match_collection_count_join(compiler, frame.auxiliary)
                compiler.facts[node] = NodeFact { ty: match_result_ty, flags: if match_result_ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
                match compiler.work.pop() { some(_) => (), none() => () }
                continue
            }
            let pattern = compiler.child_first[arm]
            let body_node = if pattern >= 0L { compiler.child_next[pattern] } else { -1L }
            let pattern_kind = tables.nodes[pattern].kind
            let has_wildcard = match_has_prior_wildcard(tables, compiler, node, arm)
            if pattern_kind == NodeKind.WildcardPattern {
                var already_total = false
                if is_sum_type(compiler, matched_type) {
                    already_total = match_covered_count(tables, compiler, node, MATCH_PATTERN_CASE) == sum_case_count(compiler, matched_type)
                } else if matched_type == TY_BOOL {
                    already_total = match_covered_count(tables, compiler, node, MATCH_PATTERN_BOOL) == 2L
                } else { () }
                if has_wildcard || already_total {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[arm].start, "unreachable match arm; previous patterns already cover this value")
                }
                compiler.facts[pattern] = NodeFact { ty: matched_type, flags: MATCH_PATTERN_WILDCARD, binding: -1L, function: -1L, literal: 0L }
            } else if pattern_kind == NodeKind.Integer {
                if !is_numeric_type(matched_type) && matched_type != TY_BYTE {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "integer patterns require an int, long, byte, or numeric refinement match value")
                }
                if has_wildcard { fail_at_message(env, files, compiler, file_index, tables.nodes[arm].start, "unreachable match arm after '_'") }
                let pattern_ty = if (tables.nodes[pattern].flags & FLAG_LONG_SUFFIX) != 0L { TY_LONG } else { matched_type }
                require_type(env, files, compiler, file_index, pattern, matched_type, pattern_ty, tables)
                let value = literal_value(env, source, tokens, files, compiler, tables, file_index, pattern, pattern_ty)
                if match_prior_pattern(tables, compiler, node, arm, MATCH_PATTERN_INTEGER, value) {
                    fail_match_scalar_duplicate(env, files, tables, compiler, file_index, arm, value, false)
                }
                compiler.facts[pattern] = NodeFact { ty: matched_type, flags: MATCH_PATTERN_INTEGER, binding: -1L, function: -1L, literal: value }
            } else if pattern_kind == NodeKind.BoolPattern {
                if matched_type != TY_BOOL {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "bool patterns require a bool match value")
                }
                let value = if (tables.nodes[pattern].flags & FLAG_VALUE) != 0L { 1L } else { 0L }
                if has_wildcard || match_prior_pattern(tables, compiler, node, arm, MATCH_PATTERN_BOOL, value) {
                    fail_match_scalar_duplicate(env, files, tables, compiler, file_index, arm, value, true)
                }
                compiler.facts[pattern] = NodeFact { ty: TY_BOOL, flags: MATCH_PATTERN_BOOL, binding: -1L, function: -1L, literal: value }
            } else if pattern_kind == NodeKind.CasePattern {
                if !is_sum_type(compiler, matched_type) {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "enum case patterns require an enum, Option, or Result match value")
                }
                if has_wildcard { fail_at_message(env, files, compiler, file_index, tables.nodes[arm].start, "unreachable match arm after '_'") }
                let generic_sum = type_kind(compiler, matched_type) == TYPE_KIND_OPTION || type_kind(compiler, matched_type) == TYPE_KIND_RESULT
                if (tables.nodes[pattern].flags & FLAG_HAS_ANNOTATION) != 0L {
                    let qualifier = tables.nodes[pattern].extra
                    if generic_sum {
                        let qualifier_matches = (type_kind(compiler, matched_type) == TYPE_KIND_OPTION && token_is_word_at(source, tokens, files, file_index, qualifier, "Option")) ||
                            (type_kind(compiler, matched_type) == TYPE_KIND_RESULT && token_is_word_at(source, tokens, files, file_index, qualifier, "Result"))
                        if !qualifier_matches { fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "qualified match case does not match the Option or Result scrutinee") } else { () }
                    } else if enum_type_matches(compiler, compiler.token_name_ids[qualifier]) != matched_type {
                        fail_match_qualifier(env, source, files, tokens, tables, compiler, file_index, pattern, matched_type)
                    } else { () }
                }
                let tag = if generic_sum {
                    sum_case_tag_for_name(source, tokens, files, file_index, compiler, matched_type, tables.nodes[pattern].token)
                } else {
                    let found_case = enum_case_matches(compiler, matched_type, compiler.token_name_ids[tables.nodes[pattern].token])
                    if found_case >= 0L { compiler.enum_cases[found_case].tag } else { -1L }
                }
                if tag < 0L {
                    if generic_sum { fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "unknown Option or Result match case") }
                    else { fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "unknown enum match case") }
                }
                let case_index = if generic_sum { -1L } else { enum_case_matches(compiler, matched_type, compiler.token_name_ids[tables.nodes[pattern].token]) }
                let payload_count = if generic_sum { sum_case_payload_count(compiler, matched_type, tag) } else { compiler.enum_cases[case_index].payload_count }
                let binding_count = count_children(tables, compiler, pattern)
                if binding_count != payload_count {
                    if generic_sum { fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "Option or Result match case has the wrong number of payload bindings") }
                    else { fail_match_case_arity(env, source, files, tokens, tables, compiler, file_index, pattern, matched_type, case_index, binding_count) }
                }
                if match_prior_pattern(tables, compiler, node, arm, MATCH_PATTERN_CASE, tag) {
                    if generic_sum { fail_at_message(env, files, compiler, file_index, tables.nodes[arm].start, "duplicate Option or Result match case") }
                    else { fail_match_duplicate_case(env, source, files, tokens, tables, compiler, file_index, arm, matched_type, case_index) }
                }
                compiler.facts[pattern] = NodeFact { ty: matched_type, flags: MATCH_PATTERN_CASE, binding: case_index, function: -1L, literal: tag }
                let arm_scope = create_scope(env, files, compiler, frame.scope, function_id, arm, file_index)
                let body_scope = if tables.nodes[body_node].kind == NodeKind.Block { create_scope(env, files, compiler, arm_scope, function_id, body_node, file_index) } else { arm_scope }
                var binding_node = compiler.child_first[pattern]
                for payload_index in 0L..payload_count {
                    if binding_node < 0L { fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "internal match pattern payload count mismatch") }
                    let payload_ty = if generic_sum { sum_case_payload_type(compiler, matched_type, tag, payload_index) }
                        else { compiler.enum_payloads[compiler.enum_cases[case_index].payload_start + payload_index].ty }
                    if tables.nodes[binding_node].kind == NodeKind.PatternBinding {
                        let binding = add_local_binding(env, source, files, tokens, tables, compiler, file_index, binding_node, tables.nodes[binding_node].token, arm_scope, payload_ty, false, false, false)
                        compiler.facts[binding_node] = NodeFact { ty: payload_ty, flags: FACT_FALLS_THROUGH, binding, function: -1L, literal: payload_index }
                    } else {
                        compiler.facts[binding_node] = NodeFact { ty: payload_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: payload_index }
                    }
                    binding_node = compiler.child_next[binding_node]
                }
                frame.child1 = arm
                frame.child2 = body_node
                frame.phase = 71L
                compiler.work[frame_index] = frame
                push_check_frame(env, files, compiler, CheckFrame {
                    node: body_node,
                    scope: body_scope,
                    expected: frame.expected,
                    function_id,
                    loop_depth: frame.loop_depth,
                    is_test,
                    phase: 0L,
                    cursor: -1L,
                    child0: -1L,
                    child1: -1L,
                    child2: -1L,
                    result_ty: -1L,
                    auxiliary: 1L,
                    reachable: true,
                })
                continue
            } else {
                fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "unsupported match pattern")
            }
            let arm_scope = create_scope(env, files, compiler, frame.scope, function_id, arm, file_index)
            let body_scope = if tables.nodes[body_node].kind == NodeKind.Block { create_scope(env, files, compiler, arm_scope, function_id, body_node, file_index) } else { arm_scope }
            frame.child1 = arm
            frame.child2 = body_node
            frame.phase = 71L
            compiler.work[frame_index] = frame
            push_check_frame(env, files, compiler, CheckFrame {
                node: body_node,
                scope: body_scope,
                expected: frame.expected,
                function_id,
                loop_depth: frame.loop_depth,
                is_test,
                phase: 0L,
                cursor: -1L,
                child0: -1L,
                child1: -1L,
                child2: -1L,
                result_ty: -1L,
                auxiliary: 1L,
                reachable: true,
            })
            continue
        }
        if kind == NodeKind.Match && frame.phase == 71L {
            let arm_type = compiler.facts[frame.child2].ty
            record_collection_count_branch(
                compiler,
                frame.auxiliary,
                frame.child1,
                (compiler.facts[frame.child2].flags & FACT_FALLS_THROUGH) != 0L,
            )
            if arm_type != TY_NEVER {
                if frame.result_ty < 0L {
                    frame.result_ty = arm_type
                } else if frame.result_ty != arm_type {
                    if type_kind(compiler, frame.result_ty) == TYPE_KIND_ASCII && type_kind(compiler, arm_type) == TYPE_KIND_ASCII {
                        let result_maximum = text_max_bytes(compiler, frame.result_ty)
                        let arm_maximum = text_max_bytes(compiler, arm_type)
                        if arm_maximum > result_maximum {
                            frame.result_ty = intern_text_type(compiler, TYPE_KIND_ASCII, arm_maximum, 0L, file_index, node, -1L, -1L)
                            if frame.result_ty < 0L {
                                fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child1].start,
                                    "Ascii match result exceeds compiler capacity")
                            }
                        }
                    } else {
                        fail_match_arm_type(env, source, files, tokens, tables, compiler, file_index, frame.child1, frame.result_ty, arm_type)
                    }
                } else { () }
            }
            frame.cursor = compiler.child_next[frame.child1]
            frame.child1 = -1L
            frame.child2 = -1L
            frame.phase = 70L
            compiler.work[frame_index] = frame
            continue
        }
        if kind == NodeKind.If && frame.phase == 0L {
            frame.child0 = compiler.child_first[node]
            frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
            frame.child2 = if frame.child1 >= 0L { compiler.child_next[frame.child1] } else { -1L }
            frame.auxiliary = begin_collection_count_join(compiler, node, 0L)
            frame.phase = 200L
            compiler.work[frame_index] = frame
            push_check_frame(env, files, compiler, CheckFrame {
                node: frame.child0,
                scope: frame.scope,
                expected: TY_BOOL,
                function_id,
                loop_depth: frame.loop_depth,
                is_test,
                phase: 0L,
                cursor: -1L,
                child0: -1L,
                child1: -1L,
                child2: -1L,
                result_ty: -1L,
                auxiliary: 0L,
                reachable: true,
            })
            continue
        }
        if kind == NodeKind.If && frame.phase == 200L {
            start_collection_count_join(compiler, frame.auxiliary)
            frame.phase = 201L
            compiler.work[frame_index] = frame
            let expected = body_child_expected(source, tokens, files, tables, compiler, node, frame.child1, frame, 1L, file_index, config)
            push_check_frame(env, files, compiler, CheckFrame {
                node: frame.child1,
                scope: frame.scope,
                expected,
                function_id,
                loop_depth: frame.loop_depth,
                is_test,
                phase: 0L,
                cursor: -1L,
                child0: -1L,
                child1: -1L,
                child2: -1L,
                result_ty: -1L,
                auxiliary: 0L,
                reachable: true,
            })
            continue
        }
        if kind == NodeKind.If && frame.phase == 201L {
            let condition_falls = (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) != 0L
            let then_falls = condition_falls && (compiler.facts[frame.child1].flags & FACT_FALLS_THROUGH) != 0L
            compiler.collection_count_joins[frame.auxiliary].branch0_falls = then_falls
            record_collection_count_branch(compiler, frame.auxiliary, 0L, then_falls)
            if frame.child2 >= 0L {
                frame.phase = 202L
                compiler.work[frame_index] = frame
                let expected = body_child_expected(source, tokens, files, tables, compiler, node, frame.child2, frame, 2L, file_index, config)
                push_check_frame(env, files, compiler, CheckFrame {
                    node: frame.child2,
                    scope: frame.scope,
                    expected,
                    function_id,
                    loop_depth: frame.loop_depth,
                    is_test,
                    phase: 0L,
                    cursor: -1L,
                    child0: -1L,
                    child1: -1L,
                    child2: -1L,
                    result_ty: -1L,
                    auxiliary: 0L,
                    reachable: true,
                })
            } else {
                compiler.collection_count_joins[frame.auxiliary].branch1_falls = condition_falls
                finish_if_collection_count_join(compiler, frame.auxiliary)
                frame.phase = 2L
                compiler.work[frame_index] = frame
            }
            continue
        }
        if kind == NodeKind.If && frame.phase == 202L {
            let condition_falls = (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) != 0L
            let else_falls = condition_falls && (compiler.facts[frame.child2].flags & FACT_FALLS_THROUGH) != 0L
            compiler.collection_count_joins[frame.auxiliary].branch1_falls = else_falls
            record_collection_count_branch(compiler, frame.auxiliary, 1L, else_falls)
            finish_if_collection_count_join(compiler, frame.auxiliary)
            frame.phase = 2L
            compiler.work[frame_index] = frame
            continue
        }
        if frame.phase == 0L {
            if function_id <= -100000L && (kind == NodeKind.Return || kind == NodeKind.ReturnStatement) {
                fail_at_message(env, files, compiler, file_index, syntax.start, "return is not allowed in a field default")
            }
            if kind == NodeKind.StructInit {
                let type_index = struct_type_matches(compiler, compiler.token_name_ids[syntax.token])
                if type_index < 0L {
                    if is_builtin_type_name(source, tokens, files, compiler, file_index, syntax.token) {
                        fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start, "'", syntax.token, "' is not a struct type")
                    }
                    fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start, "unknown struct '", syntax.token, "'; declare it with struct")
                }
                frame.result_ty = struct_type_id(compiler, type_index)
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Field {
                let receiver = compiler.child_first[node]
                if receiver >= 0L && tables.nodes[receiver].kind == NodeKind.Name &&
                    find_binding_in_scope(compiler, frame.scope, compiler.token_name_ids[tables.nodes[receiver].token]) < 0L {
                    let type_id = enum_type_matches(compiler, compiler.token_name_ids[tables.nodes[receiver].token])
                    if type_id >= 0L {
                        let case_index = enum_case_matches(compiler, type_id, compiler.token_name_ids[syntax.token])
                        if case_index >= 0L {
                            let case = compiler.enum_cases[case_index]
                            if case.payload_count > 0L { fail_enum_case_needs_payload(env, source, files, tokens, tables, compiler, file_index, node, case.owner, case_index) }
                            let ty = type_id
                            if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                            compiler.facts[node] = NodeFact { ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: case.tag }
                            match compiler.work.pop() { some(_) => (), none() => () }
                            continue
                        }
                    }
                }
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Block {
                if frame.auxiliary == 1L { frame.auxiliary = 0L }
                else { frame.scope = create_scope(env, files, compiler, frame.scope, function_id, node, file_index) }
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Let {
                var annotation = -1L
                var value = -1L
                var child = compiler.child_first[node]
                for child_step in 0L..syntax.subtree {
                    if child < 0L { break }
                    if tables.nodes[child].kind == NodeKind.Annotation { annotation = child } else { value = child }
                    child = compiler.child_next[child]
                }
                frame.child0 = value
                frame.child1 = if annotation >= 0L { parse_scalar_type(env, source, tokens, files, tables, compiler, file_index, annotation) } else { -1L }
                frame.cursor = value
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Index {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.ArrayLiteral {
                let collection_ty = frame.expected
                let collection_kind = type_kind(compiler, collection_ty)
                if collection_kind != TYPE_KIND_ARRAY && collection_kind != TYPE_KIND_LIST && collection_kind != TYPE_KIND_BYTES {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer whether this literal is an array or list; add a T[N] or list<T, N> annotation")
                }
                let element_count = count_children(tables, compiler, node)
                let capacity = if collection_kind == TYPE_KIND_BYTES { text_max_bytes(compiler, collection_ty) } else { collection_capacity(compiler, collection_ty) }
                if collection_kind == TYPE_KIND_ARRAY && element_count != capacity {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "array literal has the wrong number of elements for its array type")
                }
                if collection_kind == TYPE_KIND_LIST && element_count > capacity {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "list literal exceeds its capacity")
                }
                frame.result_ty = collection_ty
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.ListLiteral {
                if type_kind(compiler, frame.expected) != TYPE_KIND_LIST {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the capacity for 'list {}'; add a list<T, N> type annotation")
                }
                compiler.facts[node] = NodeFact { ty: frame.expected, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                match compiler.work.pop() { some(_) => (), none() => () }
                continue
            }
            if kind == NodeKind.Assign {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.result_ty = -1L
                frame.cursor = 0L
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Return || kind == NodeKind.ReturnStatement || kind == NodeKind.ExpressionStatement || kind == NodeKind.Discard || kind == NodeKind.Expect {
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Call && (syntax.flags & FLAG_SYNTHETIC) != 0L {
                if frame.expected < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "an omitted initializer needs an explicit type") }
                compiler.facts[node] = NodeFact { ty: frame.expected, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                match compiler.work.pop() { some(_) => (), none() => () }
                continue
            }
            if kind == NodeKind.Call {
                let target = find_function_by_name(compiler, compiler.token_name_ids[syntax.token])
                if target < 0L {
                    if builtin_sum_case_name(source, tokens, files, file_index, syntax.token) &&
                        user_case_matches(compiler, compiler.token_name_ids[syntax.token]) == -1L {
                        let constructor_kind = if token_is_word_at(source, tokens, files, file_index, syntax.token, "some") || token_is_word_at(source, tokens, files, file_index, syntax.token, "none") { TYPE_KIND_OPTION } else { TYPE_KIND_RESULT }
                        let constructor_tag = if token_is_word_at(source, tokens, files, file_index, syntax.token, "some") || token_is_word_at(source, tokens, files, file_index, syntax.token, "ok") { 0L } else { 1L }
                        let constructor_code = if constructor_kind == TYPE_KIND_OPTION && constructor_tag == 0L { 21L }
                            else if constructor_kind == TYPE_KIND_OPTION { 22L }
                            else if constructor_tag == 0L { 23L } else { 24L }
                        let expected_kind = type_kind(compiler, frame.expected)
                        let expected_sum = if expected_kind == constructor_kind { frame.expected } else { -1L }
                        let actual = count_children(tables, compiler, node)
                        let wanted = if constructor_code == 22L { 0L } else { 1L }
                        if actual != wanted { fail_at_message(env, files, compiler, file_index, syntax.start, "built-in sum constructor has the wrong number of arguments") }
                        if constructor_kind == TYPE_KIND_OPTION && constructor_tag == 1L && expected_sum < 0L {
                            fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the missing type parameter for 'none'; add an Option<T> expected type")
                        }
                        if constructor_kind == TYPE_KIND_RESULT && expected_sum < 0L {
                            let message: Ascii max 160 = if constructor_tag == 0L { "cannot infer the missing type parameter for 'ok'; add a Result<T, E> expected type" } else { "cannot infer the missing type parameter for 'err'; add a Result<T, E> expected type" }
                            fail_at_message(env, files, compiler, file_index, syntax.start, message)
                        }
                        if frame.expected >= 0L && expected_sum < 0L && constructor_kind == TYPE_KIND_OPTION {
                            fail_at_message(env, files, compiler, file_index, syntax.start, "expected Option<T> for this constructor")
                        }
                        frame.result_ty = expected_sum
                        frame.auxiliary = constructor_code
                        frame.cursor = compiler.child_first[node]
                        frame.phase = 1L
                        compiler.work[frame_index] = frame
                        continue
                    }
                    var case_index = -1L
                    var case_type = -1L
                    if type_kind(compiler, frame.expected) == TYPE_KIND_ENUM {
                        let expected_case = enum_case_matches(compiler, frame.expected, compiler.token_name_ids[syntax.token])
                        if expected_case >= 0L { case_index = expected_case; case_type = frame.expected }
                    }
                    if case_index < 0L {
                        case_index = user_case_matches(compiler, compiler.token_name_ids[syntax.token])
                        if case_index == -2L { fail_ambiguous_enum_case(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token) }
                        if case_index >= 0L { case_type = enum_case_owner_type_id(compiler, case_index) }
                    }
                    if case_index >= 0L {
                        let actual = count_children(tables, compiler, node)
                        if actual != compiler.enum_cases[case_index].payload_count { fail_enum_constructor_arity(env, source, files, tokens, tables, compiler, file_index, node, case_index, actual) }
                        frame.result_ty = case_type
                        frame.child2 = case_index
                        frame.cursor = compiler.child_first[node]
                        frame.phase = 1L
                        compiler.work[frame_index] = frame
                        continue
                    }
                }
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.OptionalCall {
                let receiver = compiler.child_first[node]
                if receiver < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "malformed optional call") }
                frame.child0 = receiver
                frame.cursor = receiver
                frame.auxiliary = -2L
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.QualifiedCase {
                let type_id = enum_type_matches(compiler, compiler.token_name_ids[syntax.token])
                if type_id < 0L {
                    fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start, "unknown enum '", syntax.token, "'; declare it with enum")
                }
                let case_token = tables.extra[syntax.extra]
                let case_index = enum_case_matches(compiler, type_id, compiler.token_name_ids[case_token])
                if case_index < 0L { fail_unknown_enum_case(env, source, files, tokens, tables, compiler, file_index, tokens[case_token].start, case_token, type_id) }
                let actual = count_children(tables, compiler, node)
                if actual != compiler.enum_cases[case_index].payload_count { fail_enum_constructor_arity(env, source, files, tokens, tables, compiler, file_index, node, case_index, actual) }
                frame.result_ty = type_id
                frame.child2 = case_index
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.MethodCall {
                let receiver = compiler.child_first[node]
                let empty_kind = text_empty_constructor_kind(source, tokens, files, tables, compiler, file_index, frame.scope, node)
                if empty_kind != 0L {
                    let text_ty = intern_text_type(compiler, empty_kind, 0L, 0L, file_index, node, -1L, -1L)
                    if text_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "empty text type exceeds compiler capacity") }
                    frame.child0 = receiver
                    frame.cursor = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                    frame.auxiliary = TEXT_METHOD_EMPTY
                    frame.result_ty = text_ty
                } else if is_core_sys_receiver(source, tokens, files, tables, compiler, node, file_index) {
                    let operation = core_sys_operation(source, tokens, files, file_index, syntax.token)
                    if operation < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "unknown core system operation") }
                    frame.cursor = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                    frame.auxiliary = operation
                } else {
                    frame.child0 = receiver
                    frame.cursor = receiver
                    frame.auxiliary = -1L
                }
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Cast {
                let type_node = compiler.child_first[node]
                let value_node = if type_node >= 0L { compiler.child_next[type_node] } else { -1L }
                if type_node < 0L || value_node < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "malformed cast expression") }
                let target_text_kind = text_type_syntax_kind(source, tokens, files, file_index, tables.nodes[type_node])
                let target_ty = if target_text_kind == TYPE_KIND_ASCII {
                    intern_text_type_syntax(env, source, tokens, files, tables, compiler, file_index, type_node)
                } else { parse_scalar_type(env, source, tokens, files, tables, compiler, file_index, type_node) }
                if !is_numeric_type(target_ty) && target_ty != TY_BYTE && type_kind(compiler, target_ty) != TYPE_KIND_ASCII {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "casts in this subset require int, long, byte, or a bounded Ascii type")
                }
                frame.child0 = value_node
                frame.child1 = type_node
                frame.result_ty = target_ty
                frame.cursor = value_node
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Fit {
                let value_node = compiler.child_first[node]
                let target_node = if value_node >= 0L { compiler.child_next[value_node] } else { -1L }
                if value_node < 0L || target_node < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "malformed fit expression") }
                let target_ty = compiler.facts[target_node].ty
                if type_kind(compiler, target_ty) != TYPE_KIND_ASCII && target_ty != TY_BYTE {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "fit<T>() needs an int or long refinement type")
                }
                frame.child0 = value_node
                frame.child1 = target_node
                frame.result_ty = target_ty
                frame.cursor = value_node
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.ToLong {
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Try {
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Unary {
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Binary {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.cursor = 0L
                if syntax.flags == 21L {
                    let known = natural_node_type(source, tokens, files, tables, compiler, frame.child0, frame.scope, file_index)
                    let value_ty = if is_aggregate_type(compiler, frame.expected) || is_numeric_type(frame.expected) || frame.expected == TY_BOOL || frame.expected == TY_UNIT {
                        frame.expected
                    } else { natural_node_type(source, tokens, files, tables, compiler, frame.child1, frame.scope, file_index) }
                    if known < 0L && value_ty >= 0L {
                        let file = node_file_index(tables.nodes, files, node)
                        let _ = intern_sum_type(compiler, TYPE_KIND_OPTION, value_ty, -1L, file, node, -1L, -1L)
                    }
                }
                if frame.child0 >= 0L && frame.child1 >= 0L && is_unsuffixed_integer(tables, frame.child0) && frame.expected < 0L { frame.auxiliary = 1L }
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.If {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.child2 = if frame.child1 >= 0L { compiler.child_next[frame.child1] } else { -1L }
                frame.cursor = 0L
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.For {
                var annotation = -1L
                var start = -1L
                var finish = -1L
                var body_node = -1L
                var child = compiler.child_first[node]
                var bound_index = 0L
                for child_step in 0L..syntax.subtree {
                    if child < 0L { break }
                    if tables.nodes[child].kind == NodeKind.Annotation { annotation = child }
                    else if tables.nodes[child].kind == NodeKind.Block { body_node = child }
                    else if bound_index == 0L { start = child; bound_index += 1L }
                    else { finish = child; bound_index += 1L }
                    child = compiler.child_next[child]
                }
                var loop_ty = -1L
                if annotation >= 0L {
                    loop_ty = parse_scalar_type(env, source, tokens, files, tables, compiler, file_index, annotation)
                    if !is_numeric_type(loop_ty) { fail_at_message(env, files, compiler, file_index, tables.nodes[annotation].start, "a loop counter must be int or long; use one of those types") }
                }
                for bound_slot in 0L..2L {
                    let bound = if bound_slot == 0L { start } else { finish }
                    let bound_ty = natural_loop_bound_type(source, tokens, files, tables, compiler, bound, frame.scope, file_index)
                    if bound_ty < 0L { continue }
                    if !is_numeric_type(bound_ty) { fail_loop_bound_type(env, files, compiler, file_index, tables.nodes[bound].start, bound_ty) }
                    if loop_ty < 0L { loop_ty = bound_ty }
                    if loop_ty >= 0L && loop_ty != bound_ty { fail_loop_type_conflict(env, files, compiler, file_index, syntax.start, loop_ty, bound_ty) }
                }
                let counter_name_id = compiler.token_name_ids[syntax.token]
                let body_first = body_node - tables.nodes[body_node].subtree + 1L
                for candidate in body_first..body_node + 1L {
                    if tables.nodes[candidate].kind != NodeKind.Call { continue }
                    let use_ty = loop_body_call_parameter_type(source, tokens, files, tables, compiler, candidate, counter_name_id, file_index)
                    if use_ty < 0L { continue }
                    if loop_ty < 0L { loop_ty = use_ty }
                    if loop_ty != use_ty { fail_loop_type_conflict(env, files, compiler, file_index, syntax.start, loop_ty, use_ty) }
                }
                if loop_ty < 0L { loop_ty = TY_INT }
                let loop_scope = create_scope(env, files, compiler, frame.scope, function_id, node, file_index)
                let _ = add_local_binding(env, source, files, tokens, tables, compiler, file_index, node, syntax.token, loop_scope, loop_ty, false, true, false)
                frame.child0 = start
                frame.child1 = finish
                frame.child2 = body_node
                frame.result_ty = loop_ty
                frame.auxiliary = loop_scope
                frame.cursor = 0L
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.While {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.cursor = 0L
                frame.phase = 1L
                begin_loop_count_snapshot(compiler, node)
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.ForEach {
                let collection = compiler.child_first[node]
                let body_node = if collection >= 0L { compiler.child_next[collection] } else { -1L }
                if collection < 0L || body_node < 0L || tables.nodes[body_node].kind != NodeKind.Block {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "malformed collection loop")
                }
                frame.child0 = collection
                frame.child1 = body_node
                frame.phase = 80L
                compiler.work[frame_index] = frame
                push_check_frame(env, files, compiler, CheckFrame {
                    node: collection,
                    scope: frame.scope,
                    expected: -1L,
                    function_id,
                    loop_depth: frame.loop_depth,
                    is_test,
                    phase: 0L,
                    cursor: -1L,
                    child0: -1L,
                    child1: -1L,
                    child2: -1L,
                    result_ty: -1L,
                    auxiliary: 0L,
                    reachable: true,
                })
                continue
            }
            if kind == NodeKind.Unit {
                compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            } else if kind == NodeKind.BytesLiteral {
                if compiler.core_mode {
                    compiler.facts[node] = NodeFact { ty: TY_ADDR, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                } else {
                    let literal = decode_string_token(source, tokens, files[file_index].base, syntax.extra, true)
                    let text_ty = intern_text_type(compiler, TYPE_KIND_BYTES, literal.count(), 0L, file_index, node, -1L, -1L)
                    if frame.expected >= 0L { require_type(env, files, compiler, file_index, node, frame.expected, text_ty, tables) }
                    compiler.facts[node] = NodeFact { ty: text_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                }
            } else if kind == NodeKind.ByteString {
                if (syntax.flags & FLAG_BYTESTRING_NONASCII_HEX) != 0L {
                    fail_at_message(env, files, compiler, file_index, syntax.start,
                        "non-ASCII \\xNN escapes are not allowed in Text or Ascii literals; write the character as UTF-8 or use a byte-string literal")
                }
                let literal = decode_string_token(source, tokens, files[file_index].base, syntax.token, false)
                var literal_ty = -1L
                if decoded_text_is_ascii(literal) {
                    if type_kind(compiler, frame.expected) == TYPE_KIND_TEXT {
                        literal_ty = intern_text_type(compiler, TYPE_KIND_TEXT, literal.count(), literal.count(), file_index, node, -1L, -1L)
                    } else {
                        literal_ty = intern_text_type(compiler, TYPE_KIND_ASCII, literal.count(), 0L, file_index, node, -1L, -1L)
                    }
                } else {
                    literal_ty = intern_text_type(compiler, TYPE_KIND_TEXT, literal.count(), decoded_text_codepoints(literal), file_index, node, -1L, -1L)
                }
                if frame.expected >= 0L { require_type(env, files, compiler, file_index, node, frame.expected, literal_ty, tables) }
                compiler.facts[node] = NodeFact { ty: literal_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            } else if kind == NodeKind.Integer {
                let ty = if (syntax.flags & FLAG_LONG_SUFFIX) != 0L { TY_LONG } else if is_numeric_type(frame.expected) || frame.expected == TY_BYTE { frame.expected } else { TY_INT }
                if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                let value = literal_value(env, source, tokens, files, compiler, tables, file_index, node, ty)
                compiler.facts[node] = NodeFact { ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: value }
            } else if kind == NodeKind.Bool {
                if frame.expected >= 0L && frame.expected != TY_BOOL { require_type(env, files, compiler, file_index, node, frame.expected, TY_BOOL, tables) }
                compiler.facts[node] = NodeFact { ty: TY_BOOL, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: if (syntax.flags & FLAG_VALUE) != 0L { 1L } else { 0L } }
            } else if kind == NodeKind.Name {
                let binding = find_binding_in_scope(compiler, frame.scope, compiler.token_name_ids[syntax.token])
                if binding < 0L {
                    let constant = find_constant_declaration(tables, compiler, compiler.token_name_ids[syntax.token])
                    if constant >= 0L && (compiler.facts[constant].flags & FACT_CONSTANT_EVALUATED) != 0L {
                        if frame.expected >= 0L && frame.expected != TY_LONG {
                            require_type(env, files, compiler, file_index, node, frame.expected, TY_LONG, tables)
                        }
                        compiler.facts[node] = NodeFact {
                            ty: TY_LONG,
                            flags: FACT_FALLS_THROUGH | FACT_CONSTANT_VALUE,
                            binding: -1L,
                            function: -1L,
                            literal: compiler.facts[constant].literal,
                        }
                        match compiler.work.pop() { some(_) => (), none() => () }
                        continue
                    }
                    let function = find_function_by_name(compiler, compiler.token_name_ids[syntax.token])
                    if function >= 0L { report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node, offset: syntax.start, category: UNSUPPORTED_NODE, token: syntax.token }) }
                    var case_index = -1L
                    var case_type = -1L
                    let sum_tag = if token_is_word_at(source, tokens, files, file_index, syntax.token, "none") && type_kind(compiler, frame.expected) == TYPE_KIND_OPTION { 1L } else { -1L }
                    if sum_tag >= 0L {
                        compiler.facts[node] = NodeFact { ty: frame.expected, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: sum_tag }
                        match compiler.work.pop() { some(_) => (), none() => () }
                        continue
                    }
                    if token_is_word_at(source, tokens, files, file_index, syntax.token, "none") && frame.expected < 0L {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the missing type parameter for 'none'; add an Option<T> expected type")
                    }
                    if type_kind(compiler, frame.expected) == TYPE_KIND_ENUM {
                    let expected_case = enum_case_matches(compiler, frame.expected, compiler.token_name_ids[syntax.token])
                        if expected_case >= 0L { case_index = expected_case; case_type = frame.expected }
                    } else if frame.expected < 0L {
                        case_index = user_case_matches(compiler, compiler.token_name_ids[syntax.token])
                        if case_index == -2L { fail_ambiguous_enum_case(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token) }
                        if case_index >= 0L { case_type = enum_case_owner_type_id(compiler, case_index) }
                    } else { () }
                    if case_index >= 0L {
                        let case = compiler.enum_cases[case_index]
                        if case.payload_count > 0L { fail_enum_constructor_arity(env, source, files, tokens, tables, compiler, file_index, node, case_index, 0L) }
                        if frame.expected >= 0L && frame.expected != case_type { require_type(env, files, compiler, file_index, node, frame.expected, case_type, tables) }
                        compiler.facts[node] = NodeFact { ty: case_type, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: case.tag }
                        match compiler.work.pop() { some(_) => (), none() => () }
                        continue
                    }
                    fail_name_error(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token, frame.scope, false)
                }
                let ty = compiler.bindings[binding].ty
                if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                compiler.facts[node] = NodeFact { ty, flags: FACT_FALLS_THROUGH, binding, function: -1L, literal: 0L }
            } else if kind == NodeKind.InitializerField {
                fail_at_message(env, files, compiler, file_index, syntax.start, "internal struct initializer checker dispatch failure")
            } else if kind == NodeKind.BreakStatement || kind == NodeKind.ContinueStatement || kind == NodeKind.LoopExit {
                let is_break = kind == NodeKind.BreakStatement || (kind == NodeKind.LoopExit && (syntax.flags & FLAG_VALUE) != 0L)
                if frame.loop_depth == 0L {
                    if function_id <= -100000L {
                        fail_at_message(env, files, compiler, file_index, syntax.start, if is_break { "'break' is only valid inside a loop" } else { "'continue' is only valid inside a loop" })
                    }
                    fail_at_message(env, files, compiler, file_index, syntax.start, if is_break { "'break' is only valid inside a loop; move it into a for body" } else { "'continue' is only valid inside a loop; move it into a for body" })
                }
                compiler.facts[node] = NodeFact { ty: TY_NEVER, flags: FACT_NEVER, binding: -1L, function: -1L, literal: 0L }
            } else {
                fail_at_message(env, files, compiler, file_index, syntax.start, "internal self-hosted checker node dispatch failure")
            }
            match compiler.work.pop() { some(_) => (), none => () }
            continue
        }
        if kind == NodeKind.ForEach && frame.phase == 80L {
            let collection_type = compiler.facts[frame.child0].ty
            let collection_kind = type_kind(compiler, collection_type)
            if collection_kind != TYPE_KIND_ARRAY && collection_kind != TYPE_KIND_LIST &&
                collection_kind != TYPE_KIND_ASCII && collection_kind != TYPE_KIND_BYTES {
                fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start, "for-each loops require an array, list, Ascii, or Bytes")
            }
            let collection_binding = place_root_binding(tables, compiler, frame.child0)
            if !is_assignable_place(tables, frame.child0) || collection_binding < 0L {
                fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start, "collection iteration needs a local, parameter, or field place; bind the value to a local first")
            }
            let mutable_view = compiler.bindings[collection_binding].mutable
            let view_scope = create_scope(env, files, compiler, frame.scope, function_id, node, file_index)
            let element_type = collection_element_type(compiler, collection_type)
            let view_binding = add_local_binding(env, source, files, tokens, tables, compiler, file_index, node, syntax.token, view_scope, element_type, mutable_view, false, false)
            var view_record = compiler.bindings[view_binding]
            view_record.name_token = 0L - 1L - view_record.name_token
            compiler.bindings[view_binding] = view_record
            if syntax.aux > 0L {
                let index_token = tables.extra[syntax.extra]
                let _ = add_local_binding(env, source, files, tokens, tables, compiler, file_index, node, index_token, view_scope, TY_LONG, false, true, false)
            }
            frame.phase = 81L
            frame.result_ty = element_type
            frame.auxiliary = view_scope
            frame.child2 = frame.child1
            let iterations = if collection_binding >= 0L && compiler.bindings[collection_binding].collection_count >= 0L {
                compiler.bindings[collection_binding].collection_count
            } else { collection_capacity(compiler, collection_type) }
            prepare_loop_push_proofs(source, tokens, files, tables, compiler, node, frame.child2, frame.scope, iterations, file_index, frame.loop_depth + 1L)
            compiler.work[frame_index] = frame
            push_check_frame(env, files, compiler, CheckFrame {
                node: frame.child2,
                scope: view_scope,
                expected: TY_UNIT,
                function_id,
                loop_depth: frame.loop_depth + 1L,
                is_test,
                phase: 0L,
                cursor: -1L,
                child0: -1L,
                child1: -1L,
                child2: -1L,
                result_ty: -1L,
                auxiliary: 1L,
                reachable: true,
            })
            continue
        }
        if kind == NodeKind.ForEach && frame.phase == 81L {
            finish_loop_push_proofs(compiler, node)
            let view_binding = binding_for_node(compiler, node)
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: view_binding, function: -1L, literal: compiler.facts[frame.child0].ty }
            match compiler.work.pop() { some(_) => (), none() => () }
            continue
        }
        if frame.phase == 1L {
            var child = -1L
            var child_scope = frame.scope
            var child_loop_depth = frame.loop_depth
            var child_index = -1L
            if kind == NodeKind.Block || kind == NodeKind.Call || kind == NodeKind.QualifiedCase || kind == NodeKind.MethodCall || kind == NodeKind.OptionalCall || kind == NodeKind.Index || kind == NodeKind.ArrayLiteral {
                child = frame.cursor
                if child >= 0L { frame.cursor = compiler.child_next[child] }
                child_index = 0L
                if kind == NodeKind.Call || kind == NodeKind.QualifiedCase || kind == NodeKind.MethodCall || kind == NodeKind.OptionalCall {
                    var sibling = compiler.child_first[node]
                    var position = 0L
                    for item_count in 0L..tables.nodes[node].subtree {
                        if sibling < 0L || sibling == child { break }
                        position += 1L
                        sibling = compiler.child_next[sibling]
                    }
                    child_index = position - if kind == NodeKind.MethodCall || kind == NodeKind.OptionalCall { 1L } else { 0L }
                }
            } else if kind == NodeKind.Field {
                child = frame.cursor
                frame.cursor = -1L
            } else if kind == NodeKind.StructInit {
                let initializer = frame.cursor
                if initializer >= 0L {
                    let type_index = struct_type_index(compiler, frame.result_ty)
                    let field_index = struct_field_matches(compiler, type_index, compiler.token_name_ids[tables.nodes[initializer].token])
                    if field_index < 0L {
                        fail_unknown_struct_field(env, source, files, tokens, tables, compiler, file_index, tables.nodes[initializer].start, type_index, tables.nodes[initializer].token, true)
                    }
                    var previous = compiler.child_first[node]
                    for previous_step in 0L..tables.nodes[node].subtree {
                        if previous < 0L || previous == initializer { break }
                        if compiler.facts[previous].binding == field_index {
                            let first_position = position_for_offset(file_index, files[file_index].base + tables.nodes[previous].start, compiler)
                            let current_position = position_for_offset(file_index, files[file_index].base + tables.nodes[initializer].start, compiler)
                            match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(str(current_position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(str(current_position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b": error: field '") { ok(_) => (), err(_) => env.exit(3) }
                            match write_token_raw(env.err, source, tokens, files[file_index].base, tables.nodes[initializer].token) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b"' is supplied more than once (first on line ") { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(str(first_position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b")") { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
                        }
                        previous = compiler.child_next[previous]
                    }
                    compiler.facts[initializer] = NodeFact { ty: compiler.struct_fields[field_index].ty, flags: FACT_FALLS_THROUGH, binding: field_index, function: -1L, literal: 0L }
                    frame.auxiliary = compiler.struct_fields[field_index].ty
                    child = compiler.child_first[initializer]
                    frame.cursor = compiler.child_next[initializer]
                }
            } else if kind == NodeKind.Let {
                child = frame.cursor
                frame.cursor = -1L
            } else if kind == NodeKind.Assign {
                if frame.cursor == 0L { child = frame.child0; frame.cursor = 1L }
                else if frame.cursor == 1L {
                    frame.result_ty = if frame.child0 >= 0L { compiler.facts[frame.child0].ty } else { -1L }
                    child = frame.child1
                    frame.cursor = 2L
                }
                else { () }
            } else if kind == NodeKind.Return || kind == NodeKind.ReturnStatement || kind == NodeKind.ExpressionStatement || kind == NodeKind.Discard || kind == NodeKind.Expect || kind == NodeKind.Unary || kind == NodeKind.Cast || kind == NodeKind.Fit || kind == NodeKind.ToLong || kind == NodeKind.Try {
                child = frame.cursor
                frame.cursor = -1L
            } else if kind == NodeKind.Binary {
                if frame.cursor < 2L {
                    let order = if frame.auxiliary == 1L { 1L - frame.cursor } else { frame.cursor }
                    child = if order == 0L { frame.child0 } else { frame.child1 }
                    frame.cursor += 1L
                    child_index = order
                }
            } else if kind == NodeKind.If {
                if frame.cursor < 3L {
                    if frame.cursor == 0L { child = frame.child0 }
                    else if frame.cursor == 1L { child = frame.child1 }
                    else { child = frame.child2 }
                    child_index = frame.cursor
                    frame.cursor += 1L
                } else { () }
            } else if kind == NodeKind.For {
                if frame.cursor < 3L {
                    if frame.cursor == 0L { child = frame.child0 }
                    else if frame.cursor == 1L { child = frame.child1 }
                    else {
                        child = frame.child2
                        child_scope = frame.auxiliary
                        child_loop_depth += 1L
                        let inclusive = (tables.nodes[node].flags & FLAG_INCLUSIVE) != 0L
                        let iterations = loop_iteration_count(tables, compiler, frame.child0, frame.child1, inclusive)
                        prepare_loop_push_proofs(source, tokens, files, tables, compiler, node, child, frame.scope, iterations, file_index, frame.loop_depth + 1L)
                    }
                    child_index = frame.cursor
                    frame.cursor += 1L
                } else { () }
            } else if kind == NodeKind.While {
                if frame.cursor < 2L {
                    child = if frame.cursor == 0L { frame.child0 } else { frame.child1 }
                    child_index = frame.cursor
                    if frame.cursor == 1L { child_loop_depth += 1L }
                    frame.cursor += 1L
                } else { () }
            } else {
                ()
            }
            compiler.work[frame_index] = frame
            if child >= 0L {
                let expected = body_child_expected(source, tokens, files, tables, compiler, node, child, frame, child_index, file_index, config)
                push_check_frame(env, files, compiler, CheckFrame {
                    node: child,
                    scope: child_scope,
                    expected,
                    function_id,
                    loop_depth: child_loop_depth,
                    is_test,
                    phase: 0L,
                    cursor: -1L,
                    child0: -1L,
                    child1: -1L,
                    child2: -1L,
                    result_ty: -1L,
                    auxiliary: 0L,
                    reachable: true,
                })
            } else {
                frame.phase = 2L
                compiler.work[frame_index] = frame
            }
            continue
        }
        if kind == NodeKind.Let {
            let value = frame.child0
            let value_fact = compiler.facts[value]
            if is_bytes_view_value(tables, compiler, value) {
                fail_at_message(env, files, compiler, file_index, tables.nodes[value].start,
                    "a .bytes() view is temporary and cannot be stored or returned")
            }
            if value_fact.ty == TY_NEVER {
                fail_at_message(env, files, compiler, file_index, tables.nodes[value].start, "a binding needs a value; functions and if expressions used here must return int, long, or bool")
            }
            let ty = if frame.child1 >= 0L { frame.child1 } else { value_fact.ty }
            require_type(env, files, compiler, file_index, value, ty, value_fact.ty, tables)
            let binding = add_local_binding(env, source, files, tokens, tables, compiler, file_index, node, syntax.token, frame.scope, ty, (syntax.flags & FLAG_MUTABLE) != 0L, false, false)
            if type_kind(compiler, ty) == TYPE_KIND_LIST {
                if tables.nodes[value].kind == NodeKind.ListLiteral || (tables.nodes[value].kind == NodeKind.Call && (tables.nodes[value].flags & FLAG_SYNTHETIC) != 0L) {
                    set_binding_collection_count(compiler, binding, 0L)
                } else { () }
            } else if deferred_text_kind(type_kind(compiler, ty)) {
                let byte_length = known_text_byte_length(source, tokens, files, tables, compiler, file_index, value, 0L)
                set_binding_collection_count(compiler, binding, byte_length)
            } else { () }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: if (value_fact.flags & FACT_FALLS_THROUGH) != 0L { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding, function: -1L, literal: 0L }
        } else if kind == NodeKind.ArrayLiteral {
            let ty = frame.result_ty
            let flags = if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }
            compiler.facts[node] = NodeFact { ty, flags, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Index {
            let receiver = frame.child0
            let index = frame.child1
            let collection_ty = if receiver >= 0L { compiler.facts[receiver].ty } else { -1L }
            let collection_kind = type_kind(compiler, collection_ty)
            if collection_kind != TYPE_KIND_ARRAY && collection_kind != TYPE_KIND_LIST && collection_kind != TYPE_KIND_BYTES && collection_kind != TYPE_KIND_ASCII {
                fail_at_message(env, files, compiler, file_index, syntax.start, "this value cannot be indexed; use an array, list, Bytes, or Ascii")
            }
            let index_ty = if index >= 0L { compiler.facts[index].ty } else { -1L }
            if index_ty != TY_LONG {
                if index_ty == TY_INT { fail_at_message(env, files, compiler, file_index, tables.nodes[index].start, "collection indexes are long; cast an int index with .to_long()") }
                else { fail_at_message(env, files, compiler, file_index, tables.nodes[index].start, "collection indexes must be long") }
            }
            let element_ty = if collection_kind == TYPE_KIND_BYTES || collection_kind == TYPE_KIND_ASCII { TY_BYTE } else { collection_element_type(compiler, collection_ty) }
            if frame.expected >= 0L && frame.expected != element_ty { require_type(env, files, compiler, file_index, node, frame.expected, element_ty, tables) }
            let flags = if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }
            compiler.facts[node] = NodeFact { ty: element_ty, flags, binding: compiler.facts[receiver].binding, function: -1L, literal: collection_ty }
        } else if kind == NodeKind.Field {
            let receiver = frame.child0
            let receiver_ty = compiler.facts[receiver].ty
            let environment_field = if receiver_ty == TY_ENV {
                c_runtime_environment_field_kind(source, tokens, files, compiler, file_index, syntax.token)
            } else { 0L }
            if receiver_ty == TY_ENV {
                let field_ty = c_runtime_environment_field_type(environment_field)
                if field_ty < 0L {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "Env has no field with this name")
                }
                if frame.expected >= 0L && frame.expected != field_ty { require_type(env, files, compiler, file_index, node, frame.expected, field_ty, tables) }
                compiler.facts[node] = NodeFact { ty: field_ty, flags: FACT_FALLS_THROUGH, binding: compiler.facts[receiver].binding, function: -1L, literal: environment_field }
            } else if !is_aggregate_type(compiler, receiver_ty) {
                let message: Ascii max 160 = "value has no fields; cannot read this field"
                fail_at_message(env, files, compiler, file_index, syntax.anchor, message)
            } else {
                let type_index = struct_type_index(compiler, receiver_ty)
                let field_index = struct_field_matches(compiler, type_index, compiler.token_name_ids[syntax.token])
                if field_index < 0L {
                    fail_unknown_struct_field(env, source, files, tokens, tables, compiler, file_index, syntax.anchor, type_index, syntax.token, false)
                }
                let field_ty = compiler.struct_fields[field_index].ty
                if frame.expected >= 0L && frame.expected != field_ty { require_type(env, files, compiler, file_index, node, frame.expected, field_ty, tables) }
                compiler.facts[node] = NodeFact { ty: field_ty, flags: FACT_FALLS_THROUGH, binding: compiler.facts[receiver].binding, function: -1L, literal: field_index }
            }
        } else if kind == NodeKind.StructInit {
            let type_index = struct_type_index(compiler, frame.result_ty)
            let ty = struct_record(compiler, type_index)
            var values_fall_through = true
            var supplied_value = compiler.child_first[node]
            for value_step in 0L..syntax.subtree {
                if supplied_value < 0L { break }
                let field_value = compiler.child_first[supplied_value]
                if field_value >= 0L && (compiler.facts[field_value].flags & FACT_FALLS_THROUGH) == 0L { values_fall_through = false }
                supplied_value = compiler.child_next[supplied_value]
            }
            for offset in 0L..ty.field_count {
                let field_index = ty.field_start + offset
                var supplied = false
                var initializer = compiler.child_first[node]
                for field_step in 0L..tables.nodes[node].subtree {
                    if initializer < 0L { break }
                    if compiler.facts[initializer].binding == field_index { supplied = true }
                    initializer = compiler.child_next[initializer]
                }
                if !supplied && compiler.struct_fields[field_index].default_node < 0L {
                    fail_missing_struct_field(env, source, files, tokens, tables, compiler, file_index, syntax.start, type_index, field_index)
                }
            }
            if frame.expected >= 0L && frame.expected != frame.result_ty { require_type(env, files, compiler, file_index, node, frame.expected, frame.result_ty, tables) }
            compiler.facts[node] = NodeFact { ty: frame.result_ty, flags: if values_fall_through { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: type_index }
        } else if kind == NodeKind.Assign {
            let target = frame.child0
            let value = frame.child1
            if target < 0L || (tables.nodes[target].kind != NodeKind.Name && tables.nodes[target].kind != NodeKind.Field && tables.nodes[target].kind != NodeKind.Index) { fail_at_message(env, files, compiler, file_index, syntax.start, "assignment target must be a local name, field path, or collection element") }
            let target_fact = compiler.facts[target]
            let binding = target_fact.binding
            if binding < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "assignment target must be a writable local, field, or collection element") }
            if !compiler.bindings[binding].mutable { fail_assignment_error(env, source, files, tokens, tables, compiler, file_index, node, binding) }
            if active_view_overlaps_place(tables, compiler, frame.scope, target) {
                fail_at_message(env, files, compiler, file_index, tables.nodes[target].start, "cannot replace or modify storage that contains a live collection view")
            }
            let op = syntax.flags
            let value_fact = compiler.facts[value]
            if is_ascii_append_assignment(op, target_fact.ty, compiler) {
                require_type(env, files, compiler, file_index, value, target_fact.ty, value_fact.ty, tables)
                if binding_is_write_parameter(compiler, binding) && !binding_is_grow_parameter(compiler, binding) {
                    fail_at_message(env, files, compiler, file_index, syntax.start,
                        "appending through a parameter requires 'grow' mode; 'write' cannot increase its length")
                }
                let maximum = text_max_bytes(compiler, target_fact.ty)
                let tracked_length = if binding >= 0L && binding < compiler.bindings.count() &&
                    compiler.bindings[binding].ty == target_fact.ty {
                    compiler.bindings[binding].collection_count
                } else { -1L }
                let current_maximum = if tracked_length >= 0L { tracked_length } else { maximum }
                let appended_length = known_text_byte_length(source, tokens, files, tables, compiler, file_index, value, 0L)
                let appended_maximum = if appended_length >= 0L { appended_length } else { text_max_bytes(compiler, value_fact.ty) }
                let loop_proven = frame.loop_depth == 0L || appended_maximum == 0L ||
                    loop_push_is_proven(compiler, binding, frame.loop_depth)
                if maximum < 0L || current_maximum > maximum || appended_maximum < 0L ||
                    appended_maximum > maximum - current_maximum || !loop_proven {
                    let conditional_loop = conditional_builder_loop_ancestor(tables, node)
                    if !loop_proven && conditional_loop >= 0L {
                        report_typed_unsupported(env, source, files, tokens, tables, compiler,
                            file_index, conditional_loop, UNSUPPORTED_CONDITIONAL_BUILDER_LOOP)
                    }
                    fail_ascii_append_unproven(env, source, files, tokens, tables, compiler, file_index, node, target, maximum)
                }
                if binding >= 0L && binding < compiler.bindings.count() && compiler.bindings[binding].ty == target_fact.ty {
                    if tracked_length >= 0L && appended_length >= 0L {
                        set_binding_collection_count(compiler, binding, tracked_length + appended_length)
                    } else { set_binding_collection_count(compiler, binding, -1L) }
                }
            } else { () }
            if is_bytes_view_value(tables, compiler, value) {
                fail_at_message(env, files, compiler, file_index, tables.nodes[value].start,
                    "a .bytes() view is temporary and cannot be stored or returned")
            }
            if op == 0L {
                require_type(env, files, compiler, file_index, value, target_fact.ty, value_fact.ty, tables)
                if deferred_text_kind(type_kind(compiler, target_fact.ty)) &&
                    binding >= 0L && binding < compiler.bindings.count() && compiler.bindings[binding].ty == target_fact.ty {
                    set_binding_collection_count(compiler, binding,
                        known_text_byte_length(source, tokens, files, tables, compiler, file_index, value, 0L))
                }
            } else if is_ascii_append_assignment(op, target_fact.ty, compiler) { () }
            else {
                if !is_numeric_type(target_fact.ty) { fail_at_message(env, files, compiler, file_index, syntax.anchor, "compound assignment requires int or long") }
                require_type(env, files, compiler, file_index, value, target_fact.ty, value_fact.ty, tables)
            }
            if type_kind(compiler, target_fact.ty) == TYPE_KIND_LIST && binding < compiler.bindings.count() {
                set_binding_collection_count(compiler, binding, -1L)
            } else if deferred_text_kind(type_kind(compiler, target_fact.ty)) && op != 0L && !is_ascii_append_assignment(op, target_fact.ty, compiler) && binding < compiler.bindings.count() {
                set_binding_collection_count(compiler, binding, -1L)
            } else { () }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding, function: -1L, literal: 0L }
        } else if kind == NodeKind.Return || kind == NodeKind.ReturnStatement {
            if is_test { fail_at_message(env, files, compiler, file_index, syntax.start, "a test cannot return; let the test finish so all expectations run") }
            if frame.child0 < 0L {
                if result_ty != TY_UNIT { fail_no_return_value(env, source, files, tokens, compiler, file_index, syntax.start, result_ty, compiler.functions[function_id]) }
                else { compiler.facts[node] = NodeFact { ty: TY_NEVER, flags: FACT_NEVER, binding: -1L, function: -1L, literal: 0L } }
            } else {
                if is_bytes_view_value(tables, compiler, frame.child0) {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start,
                        "a .bytes() view is temporary and cannot be stored or returned")
                }
                let actual = compiler.facts[frame.child0].ty
                require_type(env, files, compiler, file_index, frame.child0, result_ty, actual, tables)
                compiler.facts[node] = NodeFact { ty: TY_NEVER, flags: FACT_NEVER, binding: -1L, function: -1L, literal: 0L }
            }
        } else if kind == NodeKind.Discard {
            let value = frame.child0
            if value < 0L || tables.nodes[value].kind != NodeKind.MethodCall ||
                (compiler.facts[value].literal != COLLECTION_METHOD_PUSH && compiler.facts[value].literal != COLLECTION_METHOD_INSERT &&
                    compiler.facts[value].literal != TEXT_METHOD_TRY_APPEND && compiler.facts[value].literal != TEXT_METHOD_PUSH) {
                fail_at_message(env, files, compiler, file_index, syntax.start, "discard accepts only built-in operations whose Result error is capacity Full")
            }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: if (compiler.facts[value].flags & FACT_FALLS_THROUGH) != 0L { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.ExpressionStatement {
            let ty = if frame.child0 >= 0L { compiler.facts[frame.child0].ty } else { TY_UNIT }
            let proven_success = frame.child0 >= 0L && (compiler.facts[frame.child0].flags & FACT_PROVEN_SUCCESS) != 0L
            if type_kind(compiler, ty) == TYPE_KIND_RESULT && !proven_success {
                let operation = if frame.child0 >= 0L { compiler.facts[frame.child0].literal } else { 0L }
                let is_collection_capacity_result = frame.child0 >= 0L && tables.nodes[frame.child0].kind == NodeKind.MethodCall &&
                    (operation == COLLECTION_METHOD_PUSH || operation == COLLECTION_METHOD_INSERT)
                let is_builder_capacity_result = frame.child0 >= 0L && tables.nodes[frame.child0].kind == NodeKind.MethodCall &&
                    (operation == TEXT_METHOD_TRY_APPEND || operation == TEXT_METHOD_PUSH)
                let message: Ascii max 160 = if is_collection_capacity_result { "collection Result with error Full is unused; handle it or write 'discard' to drop Full" }
                    else if is_builder_capacity_result { "builder Result with error Full is unused; handle it or write 'discard' to drop Full" }
                    else { "this Result value is unused; handle it with '?', 'match', or '??' where supported" }
                fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start, message)
            }
            compiler.facts[node] = NodeFact { ty: if ty == TY_NEVER { TY_NEVER } else { TY_UNIT }, flags: if ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Expect {
            if !is_test { fail_at_message(env, files, compiler, file_index, syntax.start, "'expect' is only valid inside a test block") }
            let actual = if frame.child0 >= 0L { compiler.facts[frame.child0].ty } else { -1L }
            if actual >= 0L { require_type(env, files, compiler, file_index, frame.child0, TY_BOOL, actual, tables) }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Call {
            let name_id = compiler.token_name_ids[syntax.token]
            let arg_count = count_children(tables, compiler, node)
            if frame.child2 >= 0L {
                let ty = frame.result_ty
                if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                let case = compiler.enum_cases[frame.child2]
                compiler.facts[node] = NodeFact { ty, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: case.tag }
            } else if frame.auxiliary >= 21L && frame.auxiliary <= 24L {
                let tag = if frame.auxiliary == 21L || frame.auxiliary == 23L { 0L } else { 1L }
                let sum_kind = if frame.auxiliary == 21L || frame.auxiliary == 22L { TYPE_KIND_OPTION } else { TYPE_KIND_RESULT }
                let payload = if frame.auxiliary == 22L { -1L } else { compiler.facts[compiler.child_first[node]].ty }
                let ty = if frame.result_ty >= 0L { frame.result_ty }
                    else { intern_sum_type(compiler, sum_kind, payload, -1L, file_index, node, -1L, -1L) }
                if ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the type of this Option or Result constructor") }
                if type_state(compiler, ty) != 2L { let _ = layout_sum_instance(compiler, ty) }
                if sum_layout_has_invalid_overflow(compiler, ty) { fail_at_message(env, files, compiler, file_index, syntax.start, "Option or Result value layout is too large") }
                if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                compiler.facts[node] = NodeFact { ty, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: tag }
            } else if is_builtin_fill_call(source, tokens, files, compiler, file_index, syntax.token, frame.scope) {
                if arg_count != 1L { fail_at_message(env, files, compiler, file_index, syntax.start, "fill takes one value, but got an invalid number") }
                if frame.expected < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "fill needs an expected array type; add a T[N] annotation") }
                if type_kind(compiler, frame.expected) != TYPE_KIND_ARRAY { fail_at_message(env, files, compiler, file_index, syntax.start, "fill constructs a fixed array; add an array type annotation") }
                let argument = compiler.child_first[node]
                let element_type = collection_element_type(compiler, frame.expected)
                require_type(env, files, compiler, file_index, argument, element_type, compiler.facts[argument].ty, tables)
                compiler.facts[node] = NodeFact { ty: frame.expected, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: 0L }
            } else if token_is_word_at(source, tokens, files, file_index, syntax.token, "print") {
                if (config.capability_mask & 2L) == 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "package manifest must grant capability 'out' in the 'capabilities' key") }
                if arg_count != 1L { fail_at_message(env, files, compiler, file_index, syntax.start, "print takes one argument, but got an invalid number; call print(value)") }
                let argument = child_at(tables, compiler, node, 0L)
                let arg_ty = compiler.facts[argument].ty
                if !is_numeric_type(arg_ty) && arg_ty != TY_BOOL && arg_ty != TY_BYTE && !is_aggregate_type(compiler, arg_ty) {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "print supports int, long, bool, Ascii, enum, struct, array, list, queue, ring, grid, map, set, pool, and function values")
                }
                compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: 0L }
            } else if format_text_builtin_kind(source, tokens, files, tables, compiler, file_index, node) != FORMAT_TEXT_NONE {
                let format_kind = format_text_builtin_kind(source, tokens, files, tables, compiler, file_index, node)
                let ty = check_format_text_builtin(env, source, tokens, files, tables, compiler, file_index, node, frame.expected)
                let flags = if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }
                compiler.facts[node] = NodeFact { ty, flags: flags | FACT_FORMAT_TEXT, binding: -1L, function: -1L, literal: format_kind }
            } else {
                let target = find_function_by_name(compiler, name_id)
                if target < 0L {
                    let local = find_binding_in_scope(compiler, frame.scope, name_id)
                    if local >= 0L {
                        fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start, "value '", syntax.token, "' is not callable; use a function-typed value")
                    }
                    fail_name_error(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token, frame.scope, true)
                }
                let function = compiler.functions[target]
                check_call_count(env, source, files, tokens, tables, compiler, function, node, file_index)
                check_call_write_modes(env, source, files, tokens, tables, compiler, function, node, file_index, frame.scope)
                var read_text_argument = compiler.child_first[node]
                for argument_index in 0L..function.param_count {
                    if read_text_argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "call is missing an argument") }
                    let parameter = compiler.parameters[function.param_start + argument_index]
                    if parameter_uses_text_read_view(compiler, parameter) {
                        require_text_read_argument(env, files, compiler, file_index, read_text_argument,
                            parameter.ty, compiler.facts[read_text_argument].ty, tables)
                    }
                    read_text_argument = compiler.child_next[read_text_argument]
                }
                invalidate_collection_counts_for_write_call(compiler, function, node)
                if function_id >= 0L {
                    let edge_id = compiler.call_edges.count()
                    let next_edge = compiler.edge_first[function_id]
                    compiler.call_edges.push(CallEdge { from: function_id, to: target, node, next: next_edge }).unwrap()
                    compiler.edge_first[function_id] = edge_id
                }
                let ty = function.result_ty
                compiler.facts[node] = NodeFact { ty, flags: if ty == TY_NEVER || !node_children_fall_through(tables, compiler, node) { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: target, literal: 0L }
            }
        } else if kind == NodeKind.OptionalCall {
            let receiver = frame.child0
            let receiver_ty = if receiver >= 0L { compiler.facts[receiver].ty } else { -1L }
            let receiver_kind = type_kind(compiler, receiver_ty)
            if receiver_kind == TYPE_KIND_RESULT {
                fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional chaining requires Option; convert a Result with .ok() first")
            }
            if receiver_kind != TYPE_KIND_OPTION {
                fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional chaining requires an Option<T> receiver")
            }
            let inner_ty = sum_case_payload_type(compiler, receiver_ty, 0L, 0L)
            let argument_count = count_children(tables, compiler, node) - 1L
            let method_is_to_long = token_is_word_at(source, tokens, files, file_index, syntax.token, "to_long")
            var optional_result_ty = -1L
            if method_is_to_long {
                if argument_count != 0L || inner_ty != TY_INT {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional method 'to_long()' takes no arguments and requires Option<int>")
                }
                optional_result_ty = intern_sum_type(compiler, TYPE_KIND_OPTION, TY_LONG, -1L, file_index, node, -1L, -1L)
            } else {
                let target = find_function_by_name(compiler, compiler.token_name_ids[syntax.token])
                if target < 0L { fail_name_error(env, source, files, tokens, compiler, file_index, syntax.anchor, syntax.token, frame.scope, true) }
                let function = compiler.functions[target]
                if function.param_count != argument_count + 1L {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional call has the wrong number of arguments")
                }
                let receiver_parameter = compiler.parameters[function.param_start]
                if (parameter_mode(receiver_parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional chaining cannot call a function whose receiver parameter is write")
                }
                if parameter_uses_text_read_view(compiler, receiver_parameter) {
                    require_text_read_argument(env, files, compiler, file_index, receiver,
                        receiver_parameter.ty, inner_ty, tables)
                } else {
                    require_type(env, files, compiler, file_index, receiver, receiver_parameter.ty, inner_ty, tables)
                }
                var argument = compiler.child_next[receiver]
                for argument_index in 1L..function.param_count {
                    let parameter = compiler.parameters[function.param_start + argument_index]
                    if argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "optional call is missing an argument") }
                    if (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
                        fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional calls cannot pass a write parameter; call a function directly with an assignable place")
                    }
                    if parameter_uses_text_read_view(compiler, parameter) {
                        require_text_read_argument(env, files, compiler, file_index, argument,
                            parameter.ty, compiler.facts[argument].ty, tables)
                    } else {
                        require_type(env, files, compiler, file_index, argument, parameter.ty, compiler.facts[argument].ty, tables)
                    }
                    argument = compiler.child_next[argument]
                }
                optional_result_ty = if type_kind(compiler, function.result_ty) == TYPE_KIND_OPTION { function.result_ty }
                    else { intern_sum_type(compiler, TYPE_KIND_OPTION, function.result_ty, -1L, file_index, node, -1L, -1L) }
                if sum_layout_has_invalid_overflow(compiler, optional_result_ty) {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "optional call result has an invalid Option layout")
                }
                if frame.function_id >= 0L {
                    let edge_id = compiler.call_edges.count()
                    let next_edge = compiler.edge_first[frame.function_id]
                    compiler.call_edges.push(CallEdge { from: frame.function_id, to: target, node, next: next_edge }).unwrap()
                    compiler.edge_first[frame.function_id] = edge_id
                }
                compiler.facts[node] = NodeFact { ty: optional_result_ty, flags: if (compiler.facts[receiver].flags & FACT_FALLS_THROUGH) != 0L { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: target, literal: 0L }
            }
            if frame.expected >= 0L && frame.expected != optional_result_ty { require_type(env, files, compiler, file_index, node, frame.expected, optional_result_ty, tables) }
            if method_is_to_long || optional_result_ty >= 0L {
                compiler.facts[node] = NodeFact { ty: optional_result_ty, flags: if (compiler.facts[receiver].flags & FACT_FALLS_THROUGH) != 0L { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: if method_is_to_long { -1L } else { compiler.facts[node].function }, literal: if method_is_to_long { -2L } else { 0L } }
            }
        } else if kind == NodeKind.QualifiedCase {
            let ty = frame.result_ty
            if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
            let case = compiler.enum_cases[frame.child2]
            compiler.facts[node] = NodeFact { ty, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: case.tag }
        } else if kind == NodeKind.MethodCall {
            let operation = frame.auxiliary
            let receiver = frame.child0
            let receiver_ty = if receiver >= 0L { compiler.facts[receiver].ty } else { -1L }
            let receiver_kind = type_kind(compiler, receiver_ty)
            let c_method = if receiver >= 0L { c_runtime_method_kind(source, tokens, files, compiler, file_index, syntax.token, receiver_ty) } else { C_METHOD_NONE }
            if c_method != C_METHOD_NONE {
                let method_result = c_runtime_check_method(env, source, files, tokens, tables, compiler, file_index, node, frame.scope, receiver_ty, frame.expected)
                compiler.facts[node] = NodeFact { ty: method_result, flags: if method_result == TY_NEVER || !node_children_fall_through(tables, compiler, node) { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: c_method }
            } else if check_parse_number_method(env, source, files, tokens, tables, compiler, file_index, node, frame.expected) {
                ()
            } else if operation == TEXT_METHOD_EMPTY {
                if count_children(tables, compiler, node) != 1L {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "empty takes no arguments")
                }
                let method_result_ty = frame.result_ty
                if frame.expected >= 0L && frame.expected != method_result_ty {
                    require_type(env, files, compiler, file_index, node, frame.expected, method_result_ty, tables)
                }
                compiler.facts[node] = NodeFact { ty: method_result_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: TEXT_METHOD_EMPTY }
            } else if receiver_kind == TYPE_KIND_ARRAY || receiver_kind == TYPE_KIND_LIST {
                let method = collection_method_kind(source, tokens, files, file_index, syntax.token, receiver_kind)
                if method == 0L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "no matching array or list method is available on this value") }
                let actual_count = count_children(tables, compiler, node) - 1L
                let wanted_count = if method == COLLECTION_METHOD_PUSH || method == COLLECTION_METHOD_REMOVE { 1L }
                    else if method == COLLECTION_METHOD_INSERT { 2L } else { 0L }
                if actual_count != wanted_count { fail_at_message(env, files, compiler, file_index, syntax.start, "collection method has the wrong number of arguments") }
                var argument = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                var operation_result_type = TY_UNIT
                if method == COLLECTION_METHOD_LEN {
                    operation_result_type = TY_LONG
                } else if method == COLLECTION_METHOD_COUNT {
                    operation_result_type = TY_LONG
                } else if method == COLLECTION_METHOD_REMOVE {
                    if argument < 0L || compiler.facts[argument].ty != TY_LONG { fail_at_message(env, files, compiler, file_index, if argument >= 0L { tables.nodes[argument].start } else { syntax.start }, "collection indexes are long; cast an int index with .to_long()") }
                    if active_view_overlaps_place(tables, compiler, frame.scope, receiver) {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "cannot call a list method while a collection view is live; move the operation after the loop")
                    }
                    operation_result_type = collection_element_type(compiler, receiver_ty)
                } else if method == COLLECTION_METHOD_POP {
                    let receiver_binding = compiler.facts[receiver].binding
                    if receiver_binding < 0L || !compiler.bindings[receiver_binding].mutable { fail_at_message(env, files, compiler, file_index, syntax.start, "list mutation requires a writable local, parameter, or field place") }
                    if active_view_overlaps_place(tables, compiler, frame.scope, receiver) {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "cannot call a list method while a collection view is live; move the operation after the loop")
                    }
                    operation_result_type = intern_sum_type(compiler, TYPE_KIND_OPTION, collection_element_type(compiler, receiver_ty), -1L, file_index, node, -1L, -1L)
                } else if method == COLLECTION_METHOD_PUSH || method == COLLECTION_METHOD_INSERT {
                    let receiver_binding = compiler.facts[receiver].binding
                    if receiver_binding < 0L || !compiler.bindings[receiver_binding].mutable { fail_at_message(env, files, compiler, file_index, syntax.start, "list mutation requires a writable local, parameter, or field place") }
                    if method == COLLECTION_METHOD_INSERT && active_view_overlaps_place(tables, compiler, frame.scope, receiver) {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "cannot call a list method while a collection view is live; move the operation after the loop")
                    }
                    if method == COLLECTION_METHOD_INSERT {
                        if argument < 0L || compiler.facts[argument].ty != TY_LONG { fail_at_message(env, files, compiler, file_index, if argument >= 0L { tables.nodes[argument].start } else { syntax.start }, "collection indexes are long; cast an int index with .to_long()") }
                        argument = compiler.child_next[argument]
                    }
                    if argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "list mutation is missing its element") }
                    let element_type = collection_element_type(compiler, receiver_ty)
                    require_type(env, files, compiler, file_index, argument, element_type, compiler.facts[argument].ty, tables)
                    let full_ty = builtin_full_type_id(compiler)
                    if full_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "internal capacity error type is unavailable") }
                    operation_result_type = intern_sum_type(compiler, TYPE_KIND_RESULT, TY_UNIT, full_ty, file_index, node, -1L, -1L)
                } else if method == COLLECTION_METHOD_CLEAR {
                    let receiver_binding = compiler.facts[receiver].binding
                    if receiver_binding < 0L || !compiler.bindings[receiver_binding].mutable { fail_at_message(env, files, compiler, file_index, syntax.start, "list mutation requires a writable local, parameter, or field place") }
                    if active_view_overlaps_place(tables, compiler, frame.scope, receiver) {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "cannot call a list method while a collection view is live; move the operation after the loop")
                    }
                } else { fail_at_message(env, files, compiler, file_index, syntax.start, "unsupported collection method") }
                if frame.expected >= 0L && frame.expected != operation_result_type { require_type(env, files, compiler, file_index, node, frame.expected, operation_result_type, tables) }
                let receiver_binding = compiler.facts[receiver].binding
                let tracks_root = receiver_binding >= 0L && receiver_binding < compiler.bindings.count() && compiler.bindings[receiver_binding].ty == receiver_ty
                let proven = method == COLLECTION_METHOD_PUSH && collection_push_is_proven(compiler, receiver, frame.loop_depth)
                if tracks_root {
                    if method == COLLECTION_METHOD_PUSH {
                        if proven { set_binding_collection_count(compiler, receiver_binding, compiler.bindings[receiver_binding].collection_count + 1L) }
                        else { set_binding_collection_count(compiler, receiver_binding, collection_capacity(compiler, receiver_ty)) }
                    } else if method == COLLECTION_METHOD_CLEAR { set_binding_collection_count(compiler, receiver_binding, 0L) }
                    else if method == COLLECTION_METHOD_INSERT || method == COLLECTION_METHOD_POP || method == COLLECTION_METHOD_REMOVE {
                        set_binding_collection_count(compiler, receiver_binding, -1L)
                    } else { () }
                }
                let fact_flags = (if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }) |
                    (if proven { FACT_PROVEN_SUCCESS } else { 0L })
                compiler.facts[node] = NodeFact { ty: operation_result_type, flags: fact_flags, binding: compiler.facts[receiver].binding, function: -1L, literal: method }
            } else if receiver_kind == TYPE_KIND_ASCII || receiver_kind == TYPE_KIND_TEXT || receiver_kind == TYPE_KIND_BYTES {
                let method = text_method_kind(source, tokens, files, file_index, syntax.token, receiver_kind)
                if method == 0L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "no matching text method is available on this value") }
                if method == TEXT_METHOD_TRY_APPEND || method == TEXT_METHOD_PUSH {
                    let method_result_ty = check_text_builder_method(env, source, files, tokens, tables, compiler,
                        file_index, frame.scope, node, receiver, receiver_ty, frame.expected)
                    let receiver_binding = compiler.facts[receiver].binding
                    let tracks_root = receiver_binding >= 0L && receiver_binding < compiler.bindings.count() &&
                        compiler.bindings[receiver_binding].ty == receiver_ty
                    let proven = method == TEXT_METHOD_PUSH && builder_push_is_proven(compiler, receiver, frame.loop_depth)
                    if tracks_root {
                        if method == TEXT_METHOD_PUSH && proven {
                            set_binding_collection_count(compiler, receiver_binding, compiler.bindings[receiver_binding].collection_count + 1L)
                        } else {
                            set_binding_collection_count(compiler, receiver_binding, -1L)
                        }
                    }
                    let fact_flags = (if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }) |
                        (if proven { FACT_PROVEN_SUCCESS } else { 0L })
                    compiler.facts[node] = NodeFact { ty: method_result_ty, flags: fact_flags, binding: receiver_binding, function: -1L, literal: method }
                } else {
                let actual_count = count_children(tables, compiler, node) - 1L
                let wanted_count = if method == TEXT_METHOD_SLICE { 2L }
                    else if method == TEXT_METHOD_CONTAINS || method == TEXT_METHOD_STARTS_WITH { 1L }
                    else { 0L }
                if actual_count != wanted_count { fail_at_message(env, files, compiler, file_index, syntax.start, "text method has the wrong number of arguments") }
                var argument = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                var method_result_ty = TY_LONG
                if method == TEXT_METHOD_SLICE {
                    for bound in 0L..2L {
                        if argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "slice is missing a bound") }
                        if compiler.facts[argument].ty != TY_LONG {
                            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "slice bounds must be long")
                        }
                        argument = compiler.child_next[argument]
                    }
                    method_result_ty = receiver_ty
                } else if method == TEXT_METHOD_BYTES {
                    method_result_ty = intern_text_type(compiler, TYPE_KIND_BYTES, text_max_bytes(compiler, receiver_ty), 0L, file_index, node, -1L, -1L)
                    if method_result_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "Bytes view type exceeds the supported value size") }
                } else if method == TEXT_METHOD_VALIDATE_UTF8 {
                    let error_ty = builtin_synthetic_type_id(compiler, -3L)
                    if error_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "Utf8Error built-in type is unavailable") }
                    method_result_ty = intern_sum_type(compiler, TYPE_KIND_RESULT, TY_UNIT, error_ty, file_index, node, -1L, -1L)
                    if sum_layout_has_invalid_overflow(compiler, method_result_ty) {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "Bytes.validate_utf8 result has an invalid layout")
                    }
                } else if method == TEXT_METHOD_TO_TEXT {
                    let error_ty = builtin_synthetic_type_id(compiler, -3L)
                    if error_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "Utf8Error built-in type is unavailable") }
                    let maximum = text_max_bytes(compiler, receiver_ty)
                    if maximum < 0L || maximum > MAX_VALUE_SIZE - 16L {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "Bytes.to_text Text maximum overflows; reduce the Bytes maximum")
                    }
                    let text_ty = intern_text_type(compiler, TYPE_KIND_TEXT, maximum, maximum, file_index, node, -1L, -1L)
                    if text_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "Bytes.to_text Text result exceeds the supported value size") }
                    method_result_ty = intern_sum_type(compiler, TYPE_KIND_RESULT, text_ty, error_ty, file_index, node, -1L, -1L)
                    if sum_layout_has_invalid_overflow(compiler, method_result_ty) {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "Bytes.to_text Result layout overflows; reduce the Bytes maximum")
                    }
                } else if method == TEXT_METHOD_TO_ASCII {
                    let error_ty = builtin_synthetic_type_id(compiler, -2L)
                    if error_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "TextError built-in type is unavailable") }
                    let maximum = text_max_bytes(compiler, receiver_ty)
                    if maximum < 0L || maximum > MAX_VALUE_SIZE - 8L {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "to_ascii Ascii maximum overflows; reduce the source maximum")
                    }
                    let ascii_ty = intern_text_type(compiler, TYPE_KIND_ASCII, maximum, 0L, file_index, node, -1L, -1L)
                    if ascii_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "to_ascii Ascii result exceeds the supported value size") }
                    method_result_ty = intern_sum_type(compiler, TYPE_KIND_RESULT, ascii_ty, error_ty, file_index, node, -1L, -1L)
                    if sum_layout_has_invalid_overflow(compiler, method_result_ty) {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "to_ascii Result layout overflows; reduce the source maximum")
                    }
                } else if method == TEXT_METHOD_CONTAINS || method == TEXT_METHOD_STARTS_WITH {
                    if argument < 0L || type_kind(compiler, compiler.facts[argument].ty) != TYPE_KIND_ASCII {
                        fail_at_message(env, files, compiler, file_index, if argument >= 0L { tables.nodes[argument].start } else { syntax.start }, "Ascii string methods require an Ascii argument")
                    }
                    require_type(env, files, compiler, file_index, argument, receiver_ty, compiler.facts[argument].ty, tables)
                    method_result_ty = TY_BOOL
                } else { method_result_ty = TY_LONG }
                if frame.expected >= 0L && frame.expected != method_result_ty {
                    require_type(env, files, compiler, file_index, node, frame.expected, method_result_ty, tables)
                }
                compiler.facts[node] = NodeFact { ty: method_result_ty, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: method }
                }
            } else if operation < 0L {
                if count_children(tables, compiler, node) != 1L {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "Option and Result methods take no arguments")
                }
                let method_is_some = token_is_word_at(source, tokens, files, file_index, syntax.token, "is_some")
                let method_is_none = token_is_word_at(source, tokens, files, file_index, syntax.token, "is_none")
                let method_is_ok = token_is_word_at(source, tokens, files, file_index, syntax.token, "is_ok")
                let method_is_err = token_is_word_at(source, tokens, files, file_index, syntax.token, "is_err")
                let method_ok = token_is_word_at(source, tokens, files, file_index, syntax.token, "ok")
                let method_unwrap = token_is_word_at(source, tokens, files, file_index, syntax.token, "unwrap")
                var method_result_ty = -1L
                if receiver_kind == TYPE_KIND_OPTION && (method_is_some || method_is_none) { method_result_ty = TY_BOOL }
                else if receiver_kind == TYPE_KIND_OPTION && method_unwrap { method_result_ty = sum_case_payload_type(compiler, receiver_ty, 0L, 0L) }
                else if receiver_kind == TYPE_KIND_RESULT && (method_is_ok || method_is_err) { method_result_ty = TY_BOOL }
                else if receiver_kind == TYPE_KIND_RESULT && method_unwrap { method_result_ty = sum_case_payload_type(compiler, receiver_ty, 0L, 0L) }
                else if receiver_kind == TYPE_KIND_RESULT && method_ok {
                    let value_ty = sum_case_payload_type(compiler, receiver_ty, 0L, 0L)
                    method_result_ty = intern_sum_type(compiler, TYPE_KIND_OPTION, value_ty, -1L, file_index, node, -1L, -1L)
                    if sum_layout_has_invalid_overflow(compiler, method_result_ty) { fail_at_message(env, files, compiler, file_index, syntax.start, "Option value from Result.ok() has an invalid layout") }
                } else {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "no matching Option or Result method is available on this value")
                }
                if frame.expected >= 0L && frame.expected != method_result_ty { require_type(env, files, compiler, file_index, node, frame.expected, method_result_ty, tables) }
                compiler.facts[node] = NodeFact { ty: method_result_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            } else {
                let expected_count = core_sys_argument_count(operation)
                let actual_count = count_children(tables, compiler, node) - 1L
                if expected_count < 0L || actual_count != expected_count {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "core system operation has the wrong number of arguments")
                }
                var argument = compiler.child_first[node]
                if argument >= 0L { argument = compiler.child_next[argument] }
                for argument_index in 0L..expected_count {
                    if argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "core system operation is missing an argument") }
                    let expected_ty = core_sys_argument_type(operation, argument_index)
                    if expected_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "invalid core system operation signature") }
                    require_type(env, files, compiler, file_index, argument, expected_ty, compiler.facts[argument].ty, tables)
                    if operation == SYS_LIT && tables.nodes[argument].kind != NodeKind.BytesLiteral {
                        fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "sys.lit requires a byte-string literal")
                    }
                    argument = compiler.child_next[argument]
                }
                let syscall_result_ty = core_sys_result_type(operation)
                if frame.expected >= 0L && frame.expected != syscall_result_ty && syscall_result_ty != TY_NEVER {
                    require_type(env, files, compiler, file_index, node, frame.expected, syscall_result_ty, tables)
                }
                compiler.facts[node] = NodeFact { ty: syscall_result_ty, flags: if syscall_result_ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: operation }
            }
        } else if kind == NodeKind.Fit {
            let source_ty = compiler.facts[frame.child0].ty
            let target_ty = frame.result_ty
            if type_kind(compiler, target_ty) == TYPE_KIND_ASCII {
                if type_kind(compiler, source_ty) != TYPE_KIND_ASCII {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start,
                        "fit input must be Ascii")
                }
            } else if target_ty == TY_BYTE {
                if source_ty != TY_INT {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start,
                        "fit input must have base type int")
                }
            } else {
                fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start,
                    "fit<T>() needs an int or long refinement type")
            }
            let option_ty = intern_sum_type(compiler, TYPE_KIND_OPTION, target_ty, -1L, file_index, node, -1L, -1L)
            if sum_layout_has_invalid_overflow(compiler, option_ty) {
                fail_at_message(env, files, compiler, file_index, syntax.start, "fit result Option layout overflows; reduce the target maximum")
            }
            if frame.expected >= 0L && frame.expected != option_ty { require_type(env, files, compiler, file_index, node, frame.expected, option_ty, tables) }
            compiler.facts[node] = NodeFact { ty: option_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Cast {
            let source_ty = compiler.facts[frame.child0].ty
            let target_ty = frame.result_ty
            if type_kind(compiler, target_ty) == TYPE_KIND_ASCII {
                if type_kind(compiler, source_ty) != TYPE_KIND_ASCII {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "Ascii casts require an Ascii input")
                } else { () }
            } else if (!is_numeric_type(source_ty) && source_ty != TY_BYTE) || (!is_numeric_type(target_ty) && target_ty != TY_BYTE) {
                fail_at_message(env, files, compiler, file_index, syntax.start, "casts in this subset require int, long, or byte")
            } else { () }
            if frame.expected >= 0L && frame.expected != target_ty {
                require_type(env, files, compiler, file_index, node, frame.expected, target_ty, tables)
            }
            compiler.facts[node] = NodeFact { ty: target_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.ToLong {
            let value_ty = compiler.facts[frame.child0].ty
            if value_ty != TY_INT && value_ty != TY_BYTE {
                let message: Ascii max 160 = if value_ty == TY_LONG { "no method 'to_long' on long; 'to_long' is available on int" }
                    else if value_ty == TY_BOOL { "no method 'to_long' on bool; 'to_long' is available on int" }
                    else if value_ty == TY_UNIT { "no method 'to_long' on (); 'to_long' is available on int" }
                    else if value_ty == TY_ADDR { "no method 'to_long' on sys.Addr; 'to_long' is available on int" }
                    else { "no method 'to_long' on never; 'to_long' is available on int" }
                fail_at_message(env, files, compiler, file_index, syntax.anchor, message)
            }
            if frame.expected >= 0L && frame.expected != TY_LONG {
                require_type(env, files, compiler, file_index, node, frame.expected, TY_LONG, tables)
            }
            compiler.facts[node] = NodeFact { ty: TY_LONG, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Unary {
            let child = frame.child0
            let value = compiler.facts[child]
            if syntax.flags == 1L {
                require_type(env, files, compiler, file_index, child, TY_BOOL, value.ty, tables)
                compiler.facts[node] = NodeFact { ty: TY_BOOL, flags: value.flags, binding: -1L, function: -1L, literal: 0L }
            } else {
                if !is_numeric_type(value.ty) {
                    if syntax.flags == 2L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "unary '~' requires int or long") }
                    else { fail_at_message(env, files, compiler, file_index, syntax.anchor, "unary '-' requires int or long") }
                }
                compiler.facts[node] = NodeFact { ty: value.ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            }
        } else if kind == NodeKind.Binary {
            let left = compiler.facts[frame.child0]
            let right = compiler.facts[frame.child1]
            let op = syntax.flags
            var ty = -1L
            if op == 14L || op == 15L {
                require_type(env, files, compiler, file_index, frame.child0, TY_BOOL, left.ty, tables)
                require_type(env, files, compiler, file_index, frame.child1, TY_BOOL, right.ty, tables)
                ty = TY_BOOL
            } else if op == 21L {
                if type_kind(compiler, left.ty) == TYPE_KIND_RESULT {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "'??' works on Option only; use 'match' to handle a Result or '?' to pass its error up")
                }
                if type_kind(compiler, left.ty) != TYPE_KIND_OPTION {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "'??' requires an Option<T> value")
                }
                ty = sum_case_payload_type(compiler, left.ty, 0L, 0L)
                require_type(env, files, compiler, file_index, frame.child1, ty, right.ty, tables)
            } else if op == 0L && is_text_concatenation(compiler, left.ty, right.ty) {
                let left_kind = type_kind(compiler, left.ty)
                let right_kind = type_kind(compiler, right.ty)
                let result_kind = if left_kind == TYPE_KIND_BYTES { TYPE_KIND_BYTES }
                    else if left_kind == TYPE_KIND_TEXT || right_kind == TYPE_KIND_TEXT { TYPE_KIND_TEXT }
                    else { TYPE_KIND_ASCII }
                let left_bytes = text_max_bytes(compiler, left.ty)
                let right_bytes = text_max_bytes(compiler, right.ty)
                if left_bytes < 0L || right_bytes < 0L || left_bytes > 9223372036854775807L - right_bytes {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "text concatenation maximum overflows; reduce an operand maximum")
                }
                let result_bytes = left_bytes + right_bytes
                let result_header = if result_kind == TYPE_KIND_TEXT { 16L } else { 8L }
                if result_bytes > MAX_VALUE_SIZE - result_header {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor,
                        "text concatenation maximum overflows; reduce an operand maximum")
                }
                let result_points = if result_kind == TYPE_KIND_TEXT {
                    let left_points = text_max_codepoints(compiler, left.ty)
                    let right_points = text_max_codepoints(compiler, right.ty)
                    if left_points < 0L || right_points < 0L || left_points > 9223372036854775807L - right_points {
                        fail_at_message(env, files, compiler, file_index, syntax.anchor, "Text concatenation code-point maximum overflows; reduce an operand maximum")
                    }
                    left_points + right_points
                } else { 0L }
                var concat_result_ty = intern_text_type(compiler, result_kind, result_bytes, result_points, file_index, node, -1L, -1L)
                if concat_result_ty < 0L {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor,
                        "text concatenation result exceeds the supported value size")
                }
                if frame.expected >= 0L {
                    if text_width_fits(compiler, concat_result_ty, frame.expected) { concat_result_ty = frame.expected }
                    else { fail_type_mismatch(env, files, compiler, file_index, syntax.anchor, frame.expected, concat_result_ty) }
                }
                ty = concat_result_ty
            } else if op >= 8L && op <= 13L {
                let text_pair = is_text_comparable(compiler, left.ty, right.ty)
                if left.ty != right.ty && !text_pair { fail_mixed_types(env, files, compiler, file_index, syntax.anchor, left.ty, right.ty) }
                if (op == 8L || op == 9L) && (left.ty == TY_UNIT || left.ty == TY_NEVER) {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "equality requires values other than ()")
                }
                if op >= 10L && !is_numeric_type(left.ty) && left.ty != TY_BYTE && !text_pair { fail_at_message(env, files, compiler, file_index, syntax.anchor, "ordered comparisons require int, long, or byte values") }
                ty = TY_BOOL
            } else if op >= 16L && op <= 20L {
                if !is_numeric_type(left.ty) { fail_at_message(env, files, compiler, file_index, syntax.anchor, "bitwise operators require int or long values") }
                if left.ty != right.ty { fail_mixed_types(env, files, compiler, file_index, syntax.anchor, left.ty, right.ty) }
                require_type(env, files, compiler, file_index, frame.child1, left.ty, right.ty, tables)
                ty = left.ty
            } else {
                if !is_numeric_type(left.ty) { fail_at_message(env, files, compiler, file_index, syntax.anchor, "arithmetic operators require int or long values") }
                if is_numeric_type(right.ty) && left.ty != right.ty { fail_mixed_types(env, files, compiler, file_index, syntax.anchor, left.ty, right.ty) }
                require_type(env, files, compiler, file_index, frame.child1, left.ty, right.ty, tables)
                ty = left.ty
            }
            if frame.expected >= 0L && ty != TY_NEVER && ty != frame.expected { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
            compiler.facts[node] = NodeFact { ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.If {
            let condition = compiler.facts[frame.child0]
            require_type(env, files, compiler, file_index, frame.child0, TY_BOOL, condition.ty, tables)
            let then_ty = compiler.facts[frame.child1].ty
            let else_ty = if frame.child2 >= 0L { compiler.facts[frame.child2].ty } else { TY_UNIT }
            var ty = -1L
            if then_ty == TY_NEVER { ty = else_ty }
            else if else_ty == TY_NEVER { ty = then_ty }
            else if then_ty == else_ty { ty = then_ty }
            else if type_kind(compiler, then_ty) == TYPE_KIND_ASCII && type_kind(compiler, else_ty) == TYPE_KIND_ASCII {
                let then_maximum = text_max_bytes(compiler, then_ty)
                let else_maximum = text_max_bytes(compiler, else_ty)
                let maximum = if then_maximum > else_maximum { then_maximum } else { else_maximum }
                ty = intern_text_type(compiler, TYPE_KIND_ASCII, maximum, 0L, file_index, node, -1L, -1L)
                if ty < 0L {
                    fail_at_message(env, files, compiler, file_index, syntax.start,
                        "Ascii conditional result exceeds compiler capacity")
                }
            }
            else { fail_type_mismatch(env, files, compiler, file_index, syntax.start, then_ty, else_ty) }
            if frame.expected >= 0L && ty != TY_NEVER && ty != frame.expected { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
            compiler.facts[node] = NodeFact { ty, flags: if then_ty == TY_NEVER && else_ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.For {
            finish_loop_push_proofs(compiler, node)
            let start_ty = compiler.facts[frame.child0].ty
            let end_ty = compiler.facts[frame.child1].ty
            require_type(env, files, compiler, file_index, frame.child0, frame.result_ty, start_ty, tables)
            require_type(env, files, compiler, file_index, frame.child1, frame.result_ty, end_ty, tables)
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.While {
            let condition = compiler.facts[frame.child0]
            require_type(env, files, compiler, file_index, frame.child0, TY_BOOL, condition.ty, tables)
            finish_loop_push_proofs(compiler, node)
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Block {
            let has_tail = (syntax.flags & FLAG_HAS_TAIL) != 0L
            let last = node_last_child(tables, compiler, node)
            let tail_proven_success = has_tail && last >= 0L && (compiler.facts[last].flags & FACT_PROVEN_SUCCESS) != 0L
            let tail_ty = if !has_tail || last < 0L || tail_proven_success { TY_UNIT } else { compiler.facts[last].ty }
            var can_reach = true
            var child = compiler.child_first[node]
            for child_step in 0L..syntax.subtree {
                if child < 0L { break }
                if child != last || !has_tail {
                    if can_reach && (compiler.facts[child].flags & FACT_FALLS_THROUGH) == 0L { can_reach = false }
                }
                child = compiler.child_next[child]
            }
            if frame.expected == TY_UNIT && can_reach && has_tail && tail_ty != TY_UNIT && tail_ty != TY_NEVER {
                if type_kind(compiler, tail_ty) == TYPE_KIND_RESULT {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[last].start, "this Result value is unused; handle it with '?', 'match', or '??' where supported")
                }
                let message: Ascii max 160 = "block value must be discarded or returned as unit"
                fail_at_message(env, files, compiler, file_index, tables.nodes[last].start, message)
            }
            child = compiler.child_first[node]
            for child_step in 0L..syntax.subtree {
                if child < 0L { break }
                if (child != last || !has_tail) &&
                    (tables.nodes[child].kind == NodeKind.Block || tables.nodes[child].kind == NodeKind.If) &&
                    type_kind(compiler, compiler.facts[child].ty) == TYPE_KIND_RESULT &&
                    (compiler.facts[child].flags & FACT_PROVEN_SUCCESS) == 0L {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[child].start, "this Result value is unused; handle it with '?', 'match', or '??' where supported")
                }
                child = compiler.child_next[child]
            }
            if frame.expected >= 0L && frame.expected != TY_UNIT && can_reach && has_tail && tail_ty != TY_NEVER { require_type(env, files, compiler, file_index, last, frame.expected, tail_ty, tables) }
            let result = if !can_reach { TY_NEVER } else if has_tail { tail_ty } else { TY_UNIT }
            compiler.facts[node] = NodeFact { ty: result, flags: if !can_reach || result == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Try {
            if function_id <= -100000L {
                fail_at_message(env, files, compiler, file_index, syntax.start, "'?' is not allowed in a field default")
            }
            if is_test {
                fail_at_message(env, files, compiler, file_index, syntax.start, "a test cannot use '?'; let the test finish so all expectations run")
            }
            let operand_ty = compiler.facts[frame.child0].ty
            let operand_kind = type_kind(compiler, operand_ty)
            var success_ty = -1L
            if operand_kind == TYPE_KIND_OPTION {
                if type_kind(compiler, result_ty) != TYPE_KIND_OPTION {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "'?' on Option requires the enclosing function to return Option")
                }
                success_ty = sum_case_payload_type(compiler, operand_ty, 0L, 0L)
            } else if operand_kind == TYPE_KIND_RESULT {
                if type_kind(compiler, result_ty) != TYPE_KIND_RESULT {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "'?' on Result requires the enclosing function to return Result")
                }
                let operand_error = sum_case_payload_type(compiler, operand_ty, 1L, 0L)
                let return_error = sum_case_payload_type(compiler, result_ty, 1L, 0L)
                if operand_error != return_error {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "'?' error type does not match the enclosing Result error type")
                }
                success_ty = sum_case_payload_type(compiler, operand_ty, 0L, 0L)
            } else {
                fail_at_message(env, files, compiler, file_index, syntax.start, "'?' requires an Option or Result value")
            }
            if frame.expected >= 0L && frame.expected != success_ty { require_type(env, files, compiler, file_index, node, frame.expected, success_ty, tables) }
            compiler.facts[node] = NodeFact { ty: success_ty, flags: if (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) != 0L { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: 0L }
        } else {
            fail_at_message(env, files, compiler, file_index, syntax.start, "internal self-hosted checker finalization failure")
        }
        match compiler.work.pop() { some(_) => (), none => () }
    }
    if compiler.work.count() > 0L { fail_parse_limit(env, files[file_index].name, "self-hosted checker work limit exceeded") }
    let body_fact = compiler.facts[body]
    if tables.nodes[body].kind == NodeKind.Block && result_ty != TY_UNIT && (body_fact.flags & FACT_FALLS_THROUGH) != 0L && (tables.nodes[body].flags & FLAG_HAS_TAIL) == 0L {
        fail_missing_return(env, source, files, tokens, compiler, compiler.functions[function_id], result_ty, tables.nodes[body].start)
    }
    if tables.nodes[body].kind == NodeKind.Block && result_ty == TY_UNIT && (body_fact.flags & FACT_FALLS_THROUGH) != 0L && body_fact.ty != TY_UNIT && body_fact.ty != TY_NEVER {
        fail_at_message(env, files, compiler, file_index, tables.nodes[body].start, "unit function body has a non-unit tail expression")
    }
}

fn check_package_bodies(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    config: MemoryConfig,
    compiler: write CompilerTables,
) {
    for function_id in 0L..compiler.functions.count() {
        let function = compiler.functions[function_id]
        let scope = create_scope(env, files, compiler, -1L, function_id, function.node, function.file)
        for parameter_index in 0L..function.param_count {
            let parameter = compiler.parameters[function.param_start + parameter_index]
            let parameter_token = parameter_name_token(parameter)
            let parameter_mode_flags = parameter_mode(parameter)
            let _ = add_local_binding(env, source, files, tokens, tables, compiler, function.file, parameter.node, parameter_token, scope, parameter.ty, (parameter_mode_flags & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L, false, true)
        }
        check_one_body(env, source, files, tokens, tables, config, compiler, function.body, function.file, function_id, function.result_ty, false, scope)
    }
    for test_index in 0L..compiler.tests.count() {
        let test = compiler.tests[test_index]
        let scope = create_scope(env, files, compiler, -1L, -1L - test_index, test.node, test.file)
        check_one_body(env, source, files, tokens, tables, config, compiler, test.body, test.file, -1L - test_index, TY_UNIT, true, scope)
    }
}

fn initialize_default_graph_nodes(compiler: write CompilerTables) {
    for function_id in 0L..compiler.functions.count() {
        compiler.frame_own_bytes.push(0L).unwrap()
        compiler.frame_path_bytes.push(0L).unwrap()
        compiler.frame_visit.push(0L).unwrap()
    }
    for field_index in 0L..compiler.struct_fields.count() {
        compiler.edge_first.push(-1L).unwrap()
        compiler.cycle_seen.push(0L).unwrap()
        compiler.frame_own_bytes.push(0L).unwrap()
        compiler.frame_path_bytes.push(0L).unwrap()
        compiler.frame_visit.push(0L).unwrap()
    }
    for test_index in 0L..compiler.tests.count() {
        compiler.edge_first.push(-1L).unwrap()
        compiler.cycle_seen.push(0L).unwrap()
        compiler.frame_own_bytes.push(0L).unwrap()
        compiler.frame_path_bytes.push(0L).unwrap()
        compiler.frame_visit.push(0L).unwrap()
    }
}

fn default_graph_node(compiler: CompilerTables, field_index: long) -> long {
    compiler.functions.count() + field_index
}

fn test_graph_node(compiler: CompilerTables, test_index: long) -> long {
    compiler.functions.count() + compiler.struct_fields.count() + test_index
}

fn struct_literal_omits_field(
    tables: ParseTables,
    compiler: CompilerTables,
    literal: long,
    field_index: long,
) -> bool {
    var initializer = compiler.child_first[literal]
    for step in 0L..tables.nodes[literal].subtree {
        if initializer < 0L { break }
        if compiler.facts[initializer].binding == field_index { return false }
        initializer = compiler.child_next[initializer]
    }
    true
}

fn push_call_graph_edge(compiler: write CompilerTables, from: long, to: long, syntax_node: long) {
    let edge_id = compiler.call_edges.count()
    let next_edge = compiler.edge_first[from]
    compiler.call_edges.push(CallEdge { from, to, node: syntax_node, next: next_edge }).unwrap()
    compiler.edge_first[from] = edge_id
}

fn fail_default_cycle(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    field_index: long,
) -> never {
    let field = compiler.struct_fields[field_index]
    let ty = struct_record(compiler, field.owner)
    let position = position_for_offset(ty.file, files[ty.file].base + tables.nodes[field.default_node].start, compiler)
    match env.err.write(files[ty.file].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: field defaults form a cycle through ") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b".") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, field.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"; give one of these fields an explicit value\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn check_default_cycles(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for start_field in 0L..compiler.struct_fields.count() {
        if compiler.struct_fields[start_field].default_node < 0L { continue }
        let start_node = default_graph_node(compiler, start_field)
        if compiler.cycle_seen[start_node] == 2L { continue }
        compiler.cycle_seen[start_node] = 1L
        compiler.cycle_stack.clear()
        compiler.cycle_cursor.clear()
        compiler.cycle_stack.push(start_node).unwrap()
        compiler.cycle_cursor.push(compiler.edge_first[start_node]).unwrap()
        for step in 0L..MAX_PARSE_WORK {
            if compiler.cycle_stack.count() == 0L { break }
            let top = compiler.cycle_stack.count() - 1L
            let edge_id = compiler.cycle_cursor[top]
            if edge_id < 0L {
                let finished = compiler.cycle_stack[top]
                compiler.cycle_seen[finished] = 2L
                match compiler.cycle_stack.pop() { some(_) => (), none => () }
                match compiler.cycle_cursor.pop() { some(_) => (), none => () }
            } else {
                let edge = compiler.call_edges[edge_id]
                compiler.cycle_cursor[top] = edge.next
                if compiler.cycle_seen[edge.to] == 1L {
                    var cycle_start = -1L
                    for path_index in 0L..compiler.cycle_stack.count() {
                        if compiler.cycle_stack[path_index] == edge.to { cycle_start = path_index }
                    }
                    var first_cycle_field = edge.to - compiler.functions.count()
                    for path_index in cycle_start..compiler.cycle_stack.count() {
                        let candidate = compiler.cycle_stack[path_index] - compiler.functions.count()
                        if candidate < first_cycle_field { first_cycle_field = candidate }
                    }
                    fail_default_cycle(env, source, files, tokens, tables, compiler, first_cycle_field)
                } else if compiler.cycle_seen[edge.to] == 0L {
                    compiler.cycle_seen[edge.to] = 1L
                    compiler.cycle_stack.push(edge.to).unwrap()
                    compiler.cycle_cursor.push(compiler.edge_first[edge.to]).unwrap()
                } else { () }
            }
        }
    }
}

fn append_default_context_ascii(context: grow Bytes max 4096, value: Ascii max 64) {
    for index in 0L..value.len() { context.push(value.bytes()[index]).unwrap() }
}

fn append_default_context_token(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    context: grow Bytes max 4096,
    file_index: long,
    token_index: long,
) {
    let token = tokens[token_index]
    let start = files[file_index].base + token.start
    for offset in 0L..token.length { context.push(source[start + offset]).unwrap() }
}

fn check_struct_defaults(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    config: MemoryConfig,
    compiler: write CompilerTables,
) {
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        for field_offset in 0L..ty.field_count {
            let field_index = ty.field_start + field_offset
            let field = compiler.struct_fields[field_index]
            if field.default_node < 0L { continue }
            let function_id = -100000L - field_index
            var default_context: Bytes max 4096 = Bytes.empty()
            append_default_context_ascii(default_context, " (in the default for field '")
            append_default_context_token(source, files, tokens, default_context, ty.file, ty.name_token)
            append_default_context_ascii(default_context, ".")
            append_default_context_token(source, files, tokens, default_context, ty.file, field.name_token)
            append_default_context_ascii(default_context, "')")
            compiler.default_context = default_context
            let scope = create_scope(env, files, compiler, -1L, function_id, field.node, ty.file)
            check_one_body(env, source, files, tokens, tables, config, compiler, field.default_node, ty.file, function_id, field.ty, false, scope)
            let actual = compiler.facts[field.default_node].ty
            if actual != TY_NEVER && actual != field.ty { require_type(env, files, compiler, ty.file, field.default_node, field.ty, actual, tables) }
            compiler.default_context = Bytes.empty()
        }
    }
    for source_field in 0L..compiler.struct_fields.count() {
        let field = compiler.struct_fields[source_field]
        if field.default_node < 0L { continue }
        let root = field.default_node
        let first = root - tables.nodes[root].subtree + 1L
        for syntax_node in first..root + 1L {
            if tables.nodes[syntax_node].kind != NodeKind.StructInit { continue }
            let target_type = struct_type_matches(compiler, compiler.token_name_ids[tables.nodes[syntax_node].token])
            if target_type < 0L { continue }
            let target = struct_record(compiler, target_type)
            for target_offset in 0L..target.field_count {
                let target_field = target.field_start + target_offset
                if compiler.struct_fields[target_field].default_node >= 0L && struct_literal_omits_field(tables, compiler, syntax_node, target_field) {
                    let from = default_graph_node(compiler, source_field)
                    let to = default_graph_node(compiler, target_field)
                    push_call_graph_edge(compiler, from, to, syntax_node)
                }
            }
        }
    }
    check_default_cycles(env, source, files, tokens, tables, compiler)
}

fn add_default_call_graph_edges(
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for function_id in 0L..compiler.functions.count() {
        let root = compiler.functions[function_id].body
        let first = root - tables.nodes[root].subtree + 1L
        for syntax_node in first..root + 1L {
            if tables.nodes[syntax_node].kind != NodeKind.StructInit { continue }
            let type_index = struct_type_matches(compiler, compiler.token_name_ids[tables.nodes[syntax_node].token])
            if type_index < 0L { continue }
            let ty = struct_record(compiler, type_index)
            for offset in 0L..ty.field_count {
                let field_index = ty.field_start + offset
                if compiler.struct_fields[field_index].default_node >= 0L && struct_literal_omits_field(tables, compiler, syntax_node, field_index) {
                    let to = default_graph_node(compiler, field_index)
                    push_call_graph_edge(compiler, function_id, to, syntax_node)
                }
            }
        }
    }
    for field_index in 0L..compiler.struct_fields.count() {
        let field = compiler.struct_fields[field_index]
        if field.default_node < 0L { continue }
        let root = field.default_node
        let first = root - tables.nodes[root].subtree + 1L
        for syntax_node in first..root + 1L {
            if tables.nodes[syntax_node].kind == NodeKind.Call {
                let target = compiler.facts[syntax_node].function
                if target >= 0L {
                    let from = default_graph_node(compiler, field_index)
                    push_call_graph_edge(compiler, from, target, syntax_node)
                }
            }
        }
    }
    for test_index in 0L..compiler.tests.count() {
        let root = compiler.tests[test_index].body
        let first = root - tables.nodes[root].subtree + 1L
        let from = test_graph_node(compiler, test_index)
        for syntax_node in first..root + 1L {
            if tables.nodes[syntax_node].kind == NodeKind.Call {
                let target = compiler.facts[syntax_node].function
                if target >= 0L { push_call_graph_edge(compiler, from, target, syntax_node) }
            } else if tables.nodes[syntax_node].kind == NodeKind.StructInit {
                let type_index = struct_type_matches(compiler, compiler.token_name_ids[tables.nodes[syntax_node].token])
                if type_index < 0L { continue }
                let ty = struct_record(compiler, type_index)
                for offset in 0L..ty.field_count {
                    let field_index = ty.field_start + offset
                    if compiler.struct_fields[field_index].default_node >= 0L && struct_literal_omits_field(tables, compiler, syntax_node, field_index) {
                        let to = default_graph_node(compiler, field_index)
                        push_call_graph_edge(compiler, from, to, syntax_node)
                    }
                }
            } else { () }
        }
    }
}

fn add_frame_slot_bytes(compiler: write CompilerTables, graph_node: long, ty: long) {
    if !is_aggregate_type(compiler, ty) { return }
    let size = value_type_size(compiler, ty)
    if size > 0L && size <= compiler.file_id_base { compiler.frame_own_bytes[graph_node] += size }
}

fn add_body_frame_slot_bytes(
    tables: ParseTables,
    compiler: write CompilerTables,
    root: long,
    graph_node: long,
) {
    let first = root - tables.nodes[root].subtree + 1L
    for syntax_node in first..root + 1L {
        let ty = compiler.facts[syntax_node].ty
        add_frame_slot_bytes(compiler, graph_node, ty)
    }
}

fn compute_frame_slot_paths(tables: ParseTables, compiler: write CompilerTables) {
    let graph_count = compiler.edge_first.count()
    for node in 0L..graph_count {
        compiler.frame_path_bytes[node] = -1L
        if node < compiler.functions.count() && (tables.nodes[compiler.functions[node].node].flags & FLAG_RECURSIVE) != 0L {
            compiler.frame_visit[node] = 2L
        } else {
            compiler.frame_visit[node] = 0L
        }
    }
    for start in 0L..graph_count {
        if compiler.frame_visit[start] == 2L { continue }
        compiler.cycle_stack.clear()
        compiler.cycle_cursor.clear()
        compiler.frame_visit[start] = 1L
        compiler.cycle_stack.push(start).unwrap()
        compiler.cycle_cursor.push(compiler.edge_first[start]).unwrap()
        for step in 0L..MAX_PARSE_WORK {
            if compiler.cycle_stack.count() == 0L { break }
            let top = compiler.cycle_stack.count() - 1L
            let edge_id = compiler.cycle_cursor[top]
            if edge_id >= 0L {
                let edge = compiler.call_edges[edge_id]
                compiler.cycle_cursor[top] = edge.next
                if edge.to >= 0L && edge.to < graph_count && compiler.frame_visit[edge.to] == 0L {
                    compiler.frame_visit[edge.to] = 1L
                    compiler.cycle_stack.push(edge.to).unwrap()
                    compiler.cycle_cursor.push(compiler.edge_first[edge.to]).unwrap()
                }
            } else {
                let node = compiler.cycle_stack[top]
                var largest_child = 0L
                var unknown_child = false
                var successor = compiler.edge_first[node]
                for edge_step in 0L..compiler.call_edges.count() {
                    if successor < 0L { break }
                    let edge = compiler.call_edges[successor]
                    if edge.to >= 0L && edge.to < graph_count {
                        let child_path = compiler.frame_path_bytes[edge.to]
                        if child_path < 0L {
                            unknown_child = true
                        } else if child_path > largest_child {
                            largest_child = child_path
                        } else { () }
                    }
                    successor = edge.next
                }
                if unknown_child {
                    compiler.frame_path_bytes[node] = -1L
                } else {
                    compiler.frame_path_bytes[node] = compiler.frame_own_bytes[node] + largest_child
                }
                compiler.frame_visit[node] = 2L
                match compiler.cycle_stack.pop() { some(_) => (), none => () }
                match compiler.cycle_cursor.pop() { some(_) => (), none => () }
            }
        }
    }
}

fn populate_frame_slot_bytes(tables: ParseTables, compiler: write CompilerTables) {
    for function_id in 0L..compiler.functions.count() {
        let function = compiler.functions[function_id]
        add_body_frame_slot_bytes(tables, compiler, function.body, function_id)
        for binding_id in 0L..compiler.bindings.count() {
            let binding = compiler.bindings[binding_id]
            if compiler.scopes[binding.scope].function_id == function_id && !binding.parameter {
                add_frame_slot_bytes(compiler, function_id, binding.ty)
            }
        }
    }
    for field_index in 0L..compiler.struct_fields.count() {
        let field = compiler.struct_fields[field_index]
        if field.default_node < 0L { continue }
        let graph_node = default_graph_node(compiler, field_index)
        add_body_frame_slot_bytes(tables, compiler, field.default_node, graph_node)
        let function_id = -100000L - field_index
        for binding_id in 0L..compiler.bindings.count() {
            let binding = compiler.bindings[binding_id]
            if compiler.scopes[binding.scope].function_id == function_id && !binding.parameter {
                add_frame_slot_bytes(compiler, graph_node, binding.ty)
            }
        }
    }
    for test_index in 0L..compiler.tests.count() {
        let body = compiler.tests[test_index].body
        let graph_node = test_graph_node(compiler, test_index)
        add_body_frame_slot_bytes(tables, compiler, body, graph_node)
        let function_id = -1L - test_index
        for binding_id in 0L..compiler.bindings.count() {
            let binding = compiler.bindings[binding_id]
            if compiler.scopes[binding.scope].function_id == function_id && !binding.parameter {
                add_frame_slot_bytes(compiler, graph_node, binding.ty)
            }
        }
    }
}

fn report_frame_budget_unsupported(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    node: long,
) -> never {
    report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit {
        found: true,
        file: file_index,
        node,
        offset: tables.nodes[node].start,
        category: UNSUPPORTED_FRAME_BUDGET,
        token: tables.nodes[node].token,
    })
}

fn check_native_frame_budget(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    entry: long,
    want_test_build: bool,
) {
    populate_frame_slot_bytes(tables, compiler)
    compute_frame_slot_paths(tables, compiler)
    if want_test_build {
        for test_index in 0L..compiler.tests.count() {
            let graph_node = test_graph_node(compiler, test_index)
            if compiler.frame_path_bytes[graph_node] >= 0L && compiler.frame_path_bytes[graph_node] > 1048576L {
                let test = compiler.tests[test_index]
                report_frame_budget_unsupported(env, source, files, tokens, tables, compiler, test.file, test.node)
            }
        }
    } else if entry >= 0L && compiler.frame_path_bytes[entry] >= 0L && compiler.frame_path_bytes[entry] > 1048576L {
        let function = compiler.functions[entry]
        report_frame_budget_unsupported(env, source, files, tokens, tables, compiler, function.file, function.node)
    } else { () }
}

fn fail_call_cycle(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
) -> never {
    let first_function = compiler.cycle_path[0L]
    let function = compiler.functions[first_function]
    let position = position_for_offset(function.file, files[function.file].base + tables.nodes[function.node].start, compiler)
    match env.err.write(files[function.file].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: call cycle contains unmarked function(s) ") { ok(_) => (), err(_) => env.exit(3) }
    var wrote_name = false
    for function_id in 0L..compiler.functions.count() {
        var belongs = false
        for path_index in 0L..compiler.cycle_path.count() {
            if compiler.cycle_path[path_index] == function_id { belongs = true }
        }
        if belongs && (tables.nodes[compiler.functions[function_id].node].flags & FLAG_RECURSIVE) == 0L {
            if wrote_name { match env.err.write(b", ") { ok(_) => (), err(_) => env.exit(3) } }
            let member = compiler.functions[function_id]
            match env.err.write(b"'") { ok(_) => (), err(_) => env.exit(3) }
            match write_token_raw(env.err, source, tokens, files[member.file].base, member.name_token) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b"'") { ok(_) => (), err(_) => env.exit(3) }
            wrote_name = true
        }
    }
    match env.err.write(b"; mark every function in the cycle 'recursive'\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn check_call_cycles(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for node in 0L..compiler.edge_first.count() { compiler.cycle_seen[node] = 0L }
    for start in 0L..compiler.functions.count() {
        if (tables.nodes[compiler.functions[start].node].flags & FLAG_RECURSIVE) != 0L { continue }
        let stamp = start + 1L
        compiler.cycle_seen[start] = stamp
        compiler.cycle_stack.clear()
        compiler.cycle_cursor.clear()
        compiler.cycle_path.clear()
        compiler.cycle_stack.push(start).unwrap()
        compiler.cycle_cursor.push(compiler.edge_first[start]).unwrap()
        var found = false
        for step in 0L..MAX_PARSE_WORK {
            if compiler.cycle_stack.count() == 0L { break }
            let top = compiler.cycle_stack.count() - 1L
            let edge_id = compiler.cycle_cursor[top]
            if edge_id < 0L {
                match compiler.cycle_stack.pop() { some(_) => (), none => () }
                match compiler.cycle_cursor.pop() { some(_) => (), none => () }
            } else {
                let edge = compiler.call_edges[edge_id]
                compiler.cycle_cursor[top] = edge.next
                if edge.to == start {
                    for path_index in 0L..compiler.cycle_stack.count() {
                        compiler.cycle_path.push(compiler.cycle_stack[path_index]).unwrap()
                    }
                    found = true
                    break
                }
                if compiler.cycle_seen[edge.to] != stamp {
                    compiler.cycle_seen[edge.to] = stamp
                    compiler.cycle_stack.push(edge.to).unwrap()
                    compiler.cycle_cursor.push(compiler.edge_first[edge.to]).unwrap()
                }
            }
        }
        if found { fail_call_cycle(env, source, files, tokens, tables, compiler) }
    }
}

fn ir_push_byte(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: byte) {
    if compiler.ir_overflow { return }
    match ir.push(value) {
        ok(_) => (),
        err(_) => { compiler.ir_overflow = true },
    }
}

fn ir_write_ascii(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: Ascii max 8192) {
    for index in 0L..value.len() { ir_push_byte(compiler, ir, value.bytes()[index]) }
}

fn ir_write_bytes(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: Bytes max 4096) {
    for index in 0L..value.count() { ir_push_byte(compiler, ir, value[index]) }
}

fn ir_write_number(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: long) {
    let text = str(value)
    for index in 0L..text.len() { ir_push_byte(compiler, ir, text.bytes()[index]) }
}

fn ir_hex_digit(value: long, lowercase: bool) -> byte {
    let digits = if lowercase { b"0123456789abcdef" } else { b"0123456789ABCDEF" }
    digits[value]
}

fn ir_write_escaped_byte(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: byte) {
    let byte_value = value.to_long()
    if byte_value >= 32L && byte_value <= 126L && byte_value != 34L && byte_value != 92L {
        ir_push_byte(compiler, ir, value)
    } else {
        ir_push_byte(compiler, ir, 92)
        ir_push_byte(compiler, ir, ir_hex_digit(byte_value / 16L, false))
        ir_push_byte(compiler, ir, ir_hex_digit(byte_value % 16L, false))
    }
}

fn ir_write_global_string(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    prefix: Ascii max 128,
    name: Bytes max 4096,
) {
    ir_write_ascii(compiler, ir, prefix)
    ir_write_number(compiler, ir, name.count() + 1L)
    ir_write_ascii(compiler, ir, " x i8] c\"")
    for index in 0L..name.count() { ir_write_escaped_byte(compiler, ir, name[index]) }
    ir_write_ascii(compiler, ir, "\\00\", align 1\n")
}

fn ir_write_test_global(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    test_index: long,
    name: Bytes max 16777217,
) {
    ir_write_ascii(compiler, ir, "@.nl.entry.test.")
    ir_write_number(compiler, ir, test_index)
    ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
    ir_write_number(compiler, ir, name.count() + 8L)
    ir_write_ascii(compiler, ir, " x i8] c\"test '")
    for index in 0L..name.count() { ir_write_escaped_byte(compiler, ir, name[index]) }
    ir_write_ascii(compiler, ir, "'\\00\", align 1\n")
}

// E3a1 begin: hooks receive compiler-emitted pointer/length tables.
fn emit_file_table_global(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    first_file_id: long,
) {
    ir_write_ascii(compiler, ir, "@.nl.file.table.")
    ir_write_number(compiler, ir, first_file_id)
    ir_write_ascii(compiler, ir, " = private constant [")
    ir_write_number(compiler, ir, files.count())
    ir_write_ascii(compiler, ir, " x { ptr, i64 }] ")
    if files.count() == 0L {
        ir_write_ascii(compiler, ir, "zeroinitializer, align 8\n")
        return
    }
    ir_write_ascii(compiler, ir, "[")
    for file_index in 0L..files.count() {
        if file_index > 0L { ir_write_ascii(compiler, ir, ", ") }
        let file_id = first_file_id + file_index
        ir_write_ascii(compiler, ir, "{ ptr, i64 } { ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.file.")
        ir_write_number(compiler, ir, file_id)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
        ir_write_number(compiler, ir, files[file_index].name.count())
        ir_write_ascii(compiler, ir, " }")
    }
    ir_write_ascii(compiler, ir, "], align 8\n")
}
// E3a1 end

fn ir_write_expect_global(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let syntax = tables.nodes[node]
    let start = syntax.start
    let end = syntax.end
    ir_write_ascii(compiler, ir, "@.nl.expect.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
    ir_write_number(compiler, ir, end - start + 1L)
    ir_write_ascii(compiler, ir, " x i8] c\"")
    for index in start..end { ir_write_escaped_byte(compiler, ir, source[index]) }
    ir_write_ascii(compiler, ir, "\\00\", align 1\n")
}

fn llvm_type_name(ty: long) -> Ascii max 8 {
    if ty == TY_INT { "i32" }
    else if ty == TY_LONG { "i64" }
    else if ty == TY_BOOL { "i1" }
    else if ty == TY_BYTE { "i32" }
    else if ty == TY_UNIT { "void" }
    else if ty == TY_NEVER { "void" }
    else if ty == TY_ADDR || (ty >= TY_ENV && ty <= TY_ARG) { "ptr" }
    else { "i32" }
}

fn binding_for_node(compiler: CompilerTables, node: long) -> long {
    for binding in 0L..compiler.bindings.count() {
        if compiler.bindings[binding].node == node { return binding }
    }
    -1L
}

fn ir_write_value_ref(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long) {
    if node >= 0L && node < compiler.facts.count() && (compiler.facts[node].flags & FACT_CONSTANT_VALUE) != 0L {
        let value = compiler.facts[node].literal
        ir_write_number(compiler, ir, value)
    } else {
        ir_write_ascii(compiler, ir, "%v")
        ir_write_number(compiler, ir, node)
    }
}

fn native_location(anchor_kind: long, anchor_node: long, byte_offset: long) -> StorageLocation {
    StorageLocation { origin: LOCATION_NATIVE, anchor_kind, anchor_node, byte_offset, copies: 1L, index: 0L, index_node: -1L, index_stride: 0L }
}

fn storage_location_with_offset(base: StorageLocation, extra_offset: long) -> StorageLocation {
    StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node,
        byte_offset: base.byte_offset + extra_offset, copies: base.copies, index: base.index,
        index_node: base.index_node, index_stride: base.index_stride }
}

fn sum_parameter_location(compiler: CompilerTables, binding: long, base: StorageLocation) -> StorageLocation {
    if binding < 0L || binding >= compiler.bindings.count() { return base }
    let type_id = compiler.bindings[binding].ty
    if !is_sum_type(compiler, type_id) { return base }
    // A sum value is one contiguous leaf in the caller's indexed lane group.
    // Keep its descriptor and apply the runtime lane index when materializing
    // the address; structs still use their existing noncontiguous geometry.
    StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node,
        byte_offset: base.byte_offset, copies: -1L, index: -1L, index_node: -1L,
        index_stride: value_type_size(compiler, type_id) }
}

fn is_indexed_sum_parameter_location(location: StorageLocation) -> bool {
    location.origin == LOCATION_NATIVE && location.anchor_kind == 3L && location.anchor_node >= 0L &&
        location.copies == -1L && location.index == -1L && location.index_node == -1L && location.index_stride > 0L
}

// E3a1 begin: resolve native-slot anchors through the per-function plan.
fn compiler_location(compiler: CompilerTables, anchor_kind: long, anchor_node: long, byte_offset: long) -> StorageLocation {
    let native = native_location(anchor_kind, anchor_node, byte_offset)
    if region_has_slot(compiler, anchor_kind, anchor_node) {
        StorageLocation { origin: LOCATION_DATA_STACK, anchor_kind, anchor_node, byte_offset, copies: 1L, index: 0L, index_node: -1L, index_stride: 0L }
    } else {
        StorageLocation { origin: native.origin, anchor_kind, anchor_node, byte_offset, copies: 1L, index: 0L, index_node: -1L, index_stride: 0L }
    }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn aggregate_destination_location(compiler: CompilerTables, kind: long, node: long) -> StorageLocation {
    if kind == 0L && node == compiler.emit_destination_node && compiler.emit_destination_kind == 1L {
        return compiler_location(compiler, 1L, compiler.emit_destination_anchor, 0L)
    }
    if kind == 0L && node == compiler.emit_destination_node && compiler.emit_destination_kind == 2L {
        return compiler_location(compiler, 9L, 0L, 0L)
    }
    if kind == 0L { compiler_location(compiler, 0L, node, 0L) }
    else if kind == 1L { compiler_location(compiler, 1L, node, 0L) }
    // User function results carry a relocatable descriptor. Core helpers keep
    // their no-growth pointer ABI and use anchor kind 4 directly.
    else if kind == 2L { compiler_location(compiler, 9L, 0L, 0L) }
    else { compiler_location(compiler, 2L, node, 0L) }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn aggregate_source_location(compiler: CompilerTables, kind: long, node: long) -> StorageLocation {
    if kind == 0L { compiler_location(compiler, 0L, node, 0L) }
    else if kind == 1L { compiler_location(compiler, 1L, node, 0L) }
    else if kind == 2L {
        let location = compiler_location(compiler, 3L, node, 0L)
        sum_parameter_location(compiler, node, location)
    }
    else { compiler_location(compiler, 2L, node, 0L) }
}
// E3a1 end

fn direct_call_argument_source_location(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> StorageLocation {
    let kind = aggregate_source_kind(tables, compiler, node)
    let source_node = aggregate_source_id(tables, compiler, node)
    if kind == 3L && tables.nodes[node].kind == NodeKind.Field &&
        place_root_binding(tables, compiler, node) >= 0L {
        place_storage_location(tables, compiler, node)
    } else {
        aggregate_source_location(compiler, kind, source_node)
    }
}

recursive fn place_storage_location(tables: ParseTables, compiler: CompilerTables, node: long) -> StorageLocation {
    if node < 0L { return compiler_location(compiler, 0L, node, 0L) }
    let kind = tables.nodes[node].kind
    if kind == NodeKind.Name {
        let binding = compiler.facts[node].binding
        if binding_is_view(compiler, binding) {
            let loop_node = compiler.bindings[binding].node
            let collection = compiler.child_first[loop_node]
            let collection_type = compiler.facts[collection].ty
            let element_type = collection_element_type(compiler, collection_type)
            let capacity = collection_capacity(compiler, collection_type)
            let base_offset = collection_element_base_offset(compiler, collection_type)
            let element_stride = if type_kind(compiler, collection_type) == TYPE_KIND_ASCII || type_kind(compiler, collection_type) == TYPE_KIND_BYTES { 1L }
                else { value_type_size(compiler, element_type) }
            let base = collection_value_location(tables, compiler, collection)
            if is_aggregate_type(compiler, element_type) {
                StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node, byte_offset: base.byte_offset + base_offset, copies: capacity, index: 0L, index_node: -2L - loop_node, index_stride: 0L }
            } else {
                StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node, byte_offset: base.byte_offset + base_offset, copies: 1L, index: 0L, index_node: -2L - loop_node, index_stride: element_stride }
            }
        } else if binding >= 0L && compiler.bindings[binding].parameter && is_aggregate_type(compiler, compiler.bindings[binding].ty) {
            let location = compiler_location(compiler, 3L, binding, 0L)
            sum_parameter_location(compiler, binding, StorageLocation { origin: location.origin, anchor_kind: location.anchor_kind, anchor_node: location.anchor_node, byte_offset: location.byte_offset, copies: -1L, index: -1L, index_node: -1L, index_stride: 0L })
        } else if binding >= 0L && compiler.bindings[binding].parameter { compiler_location(compiler, 3L, binding, 0L) }
        else { compiler_location(compiler, 1L, binding, 0L) }
    } else if kind == NodeKind.Field {
        var root = node
        for root_step in 0L..MAX_TREE_NODES {
            if root < 0L || tables.nodes[root].kind != NodeKind.Field { break }
            root = compiler.child_first[root]
        }
        if root >= 0L && tables.nodes[root].kind == NodeKind.Name {
            let root_binding = compiler.facts[root].binding
            if root_binding >= 0L && compiler.bindings[root_binding].parameter && is_aggregate_type(compiler, compiler.bindings[root_binding].ty) {
                let receiver = compiler.child_first[node]
                if receiver < 0L { return compiler_location(compiler, 2L, node, 0L) }
                let base = place_storage_location(tables, compiler, receiver)
                let receiver_type = compiler.facts[receiver].ty
                let field_index = compiler.facts[node].literal
                if type_kind(compiler, receiver_type) != TYPE_KIND_STRUCT || field_index < 0L {
                    return compiler_location(compiler, 2L, node, 0L)
                }
                let field = compiler.struct_fields[field_index]
                return StorageLocation {
                    origin: base.origin,
                    anchor_kind: base.anchor_kind,
                    anchor_node: base.anchor_node,
                    byte_offset: base.byte_offset + field.offset,
                    copies: 1L,
                    index: 0L,
                    index_node: -1L,
                    index_stride: 0L,
                }
            }
        }
        let receiver = compiler.child_first[node]
        if receiver < 0L { return compiler_location(compiler, 0L, node, 0L) }
        let base = place_storage_location(tables, compiler, receiver)
        let receiver_type = compiler.facts[receiver].ty
        let field_index = compiler.facts[node].literal
        if type_kind(compiler, receiver_type) != TYPE_KIND_STRUCT || field_index < 0L { return compiler_location(compiler, 2L, node, 0L) }
        let field = compiler.struct_fields[field_index]
        let field_offset = if base.copies > 1L && base.index_node != -1L {
            let field_start = type_record(compiler, receiver_type).field_start
            collection_field_lane_offset(compiler, receiver_type, base.copies, field_index - field_start)
        } else { field.offset }
        let stride = if base.index_node != -1L && (!is_aggregate_type(compiler, field.ty) || type_kind(compiler, field.ty) == TYPE_KIND_BYTES) { value_type_size(compiler, field.ty) } else { 0L }
        StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node, byte_offset: base.byte_offset + field_offset, copies: base.copies, index: base.index, index_node: base.index_node, index_stride: stride }
    } else if kind == NodeKind.Index {
        let receiver = compiler.child_first[node]
        let index_node = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
        if receiver < 0L || index_node < 0L { return compiler_location(compiler, 2L, node, 0L) }
        let collection_type = compiler.facts[receiver].ty
        let element_type = collection_element_type(compiler, collection_type)
        let capacity = collection_capacity(compiler, collection_type)
        let base_offset = collection_element_base_offset(compiler, collection_type)
        let base = place_storage_location(tables, compiler, receiver)
        if element_type < 0L || capacity < 0L || base_offset < 0L { return compiler_location(compiler, 2L, node, 0L) }
        if is_aggregate_type(compiler, element_type) {
            StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node, byte_offset: base.byte_offset + base_offset, copies: capacity, index: 0L, index_node, index_stride: 0L }
        } else {
            StorageLocation { origin: base.origin, anchor_kind: base.anchor_kind, anchor_node: base.anchor_node, byte_offset: base.byte_offset + base_offset, copies: 1L, index: 0L, index_node, index_stride: value_type_size(compiler, element_type) }
        }
    } else { compiler_location(compiler, 0L, node, 0L) }
}



// E3a1 begin: materialize a movable address immediately before its use.
fn emit_location_pointer_materialization(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    location: StorageLocation,
    ) -> long {
    if !is_indexed_sum_parameter_location(location) && (location.copies != 1L || location.index != 0L) {
        compiler.ir_overflow = true
        return -1L
    }
    let serial = next_location_serial(ir)
    if location.origin == LOCATION_DATA_STACK {
        let slot = region_find_slot(compiler, location.anchor_kind, location.anchor_node)
        if slot < 0L { compiler.ir_overflow = true; return -1L }
        if location.byte_offset == 0L { ir_write_ascii(compiler, ir, "  %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %region.offset."); ir_write_number(compiler, ir, slot); ir_write_ascii(compiler, ir, ", 0\n") }
        else { ir_write_ascii(compiler, ir, "  %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %region.offset."); ir_write_number(compiler, ir, slot); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.byte_offset); ir_write_ascii(compiler, ir, "\n") }
        ir_write_ascii(compiler, ir, "  %loc.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = call ptr "); emit_context_runtime_symbol(compiler, ir, "nl_context_current_base", "nlc_context_current_base"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  %loc.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %loc.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", i64 %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, "\n")
        return serial
    } else if location.anchor_kind == 3L || location.anchor_kind == 9L {
        if location.anchor_kind == 3L {
            ir_write_ascii(compiler, ir, "  %loc.anchor."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = select i1 true, ptr %arg.anchor."); ir_write_number(compiler, ir, location.anchor_node); ir_write_ascii(compiler, ir, ", ptr %arg.anchor."); ir_write_number(compiler, ir, location.anchor_node); ir_push_byte(compiler, ir, 10)
            if is_indexed_sum_parameter_location(location) {
                ir_write_ascii(compiler, ir, "  %loc.offset.index."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = mul i64 %arg.index."); ir_write_number(compiler, ir, location.anchor_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.index_stride); ir_push_byte(compiler, ir, 10)
                ir_write_ascii(compiler, ir, "  %loc.offset.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %arg.offset."); ir_write_number(compiler, ir, location.anchor_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
                ir_write_ascii(compiler, ir, "  %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %loc.offset.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", %loc.offset.index."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
            } else {
                ir_write_ascii(compiler, ir, "  %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %arg.offset."); ir_write_number(compiler, ir, location.anchor_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
            }
        } else {
            ir_write_ascii(compiler, ir, "  %loc.anchor."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = select i1 true, ptr %nl.dest.anchor, ptr %nl.dest.anchor\n  %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 %nl.dest.offset, "); ir_write_number(compiler, ir, location.byte_offset); ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "  %loc.is.stack."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = icmp eq ptr %loc.anchor."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", null\n  %loc.native.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %loc.anchor."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", i64 %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, "\n  %loc.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = call ptr "); emit_context_runtime_symbol(compiler, ir, "nl_context_current_base", "nlc_context_current_base"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  %loc.stack.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %loc.base."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", i64 %loc.offset."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, "\n  %loc.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = select i1 %loc.is.stack."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %loc.stack.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, ", ptr %loc.native.pointer."); ir_write_number(compiler, ir, serial); ir_push_byte(compiler, ir, 10)
        return serial
    } else if location.byte_offset != 0L {
        let base_location = StorageLocation {
            origin: location.origin,
            anchor_kind: location.anchor_kind,
            anchor_node: location.anchor_node,
            byte_offset: 0L,
            copies: 1L,
            index: 0L,
            index_node: -1L,
            index_stride: 0L,
        }
        ir_write_ascii(compiler, ir, "  %loc.pointer."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, base_location, -1L)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
        serial
    } else { -1L }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_location_pointer_reference(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, location: StorageLocation, serial: long) {
    if serial >= 0L { ir_write_ascii(compiler, ir, "%loc.pointer."); ir_write_number(compiler, ir, serial) }
    else if location.anchor_kind == 0L { ir_write_ascii(compiler, ir, "%agg."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 1L { ir_write_ascii(compiler, ir, "%local."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 2L { ir_write_ascii(compiler, ir, "%addr."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 10L { ir_write_ascii(compiler, ir, "%optional.call.receiver.snapshot."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 4L { ir_write_ascii(compiler, ir, "%nl.dest") }
    else if location.anchor_kind == 5L { ir_write_ascii(compiler, ir, "%nl.source") }
    else if location.anchor_kind == 6L { ir_write_ascii(compiler, ir, "%nl.left") }
    else if location.anchor_kind == 7L { ir_write_ascii(compiler, ir, "%nl.right") }
    else if location.anchor_kind == 8L { ir_write_ascii(compiler, ir, "%nl.value") }
    else { compiler.ir_overflow = true }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_location_pointer(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, location: StorageLocation) {
    let serial = emit_location_pointer_materialization(compiler, ir, location)
    emit_location_pointer_reference(compiler, ir, location, serial)
}
// E3a1 end


fn lower_scope_exit(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    scope_id: long,
    exit_kind: long,
    target_kind: long,
    target: long,
    value_ty: long,
    value_node: long,
) {
    // One invocation lowers one exited scope. A multi-scope exit invokes this
    // in innermost-first order; E2i has no cleanup records to run.
    for cleanup_step in 0L..compiler.exit_cleanups.count() {
        let cleanup = compiler.exit_cleanups[compiler.exit_cleanups.count() - cleanup_step - 1L]
        if cleanup.scope_id == scope_id { emit_registered_exit_cleanup(compiler, ir, cleanup) }
    }
    // E3a1 begin
    // Restore the incoming top on function exits. Loop resets are emitted at
    // branch sites, which know the loop body's region scope.
    if !compiler.core_mode && (exit_kind == EXIT_RETURN || exit_kind == EXIT_RETURN_VALUE || exit_kind == EXIT_TEST_SUCCESS || exit_kind == EXIT_TEST_FAILURE || exit_kind == EXIT_FALLTHROUGH) {
        if compiler.region_max_size > 0L {
            ir_write_ascii(compiler, ir, "  call void @nl_context_set_top_offset(ptr %nl.ctx, i64 %nl.top)\n")
        }
    } else { () }
    // E3a1 end
    if exit_kind == EXIT_RETURN { ir_write_ascii(compiler, ir, "  ret void\n") }
    else if exit_kind == EXIT_RETURN_VALUE {
        ir_write_ascii(compiler, ir, "  ret "); ir_write_ascii(compiler, ir, llvm_type_name(value_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, "\n")
    } else if exit_kind == EXIT_TEST_SUCCESS { ir_write_ascii(compiler, ir, "  ret i32 0\n") }
    else if exit_kind == EXIT_TEST_FAILURE { ir_write_ascii(compiler, ir, "  ret i32 1\n") }
    else if exit_kind == EXIT_FALLTHROUGH {
        if target_kind == 1L { ir_write_ascii(compiler, ir, "  ret i32 0\n") }
        else if value_ty == TY_UNIT || value_ty == TY_NEVER || is_aggregate_type(compiler, value_ty) { ir_write_ascii(compiler, ir, "  ret void\n") }
        else { ir_write_ascii(compiler, ir, "  ret "); ir_write_ascii(compiler, ir, llvm_type_name(value_ty)); ir_write_ascii(compiler, ir, " 0\n") }
    } else if exit_kind == EXIT_BREAK || exit_kind == EXIT_CONTINUE {
        if target_kind == 1L {
            if exit_kind == EXIT_BREAK { ir_write_ascii(compiler, ir, "  br label %while.end.") }
            else { ir_write_ascii(compiler, ir, "  br label %while.step.") }
        } else if exit_kind == EXIT_BREAK { ir_write_ascii(compiler, ir, "  br label %for.end.") }
        else { ir_write_ascii(compiler, ir, "  br label %for.increment.") }
        ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, "\n")
    } else if exit_kind == EXIT_BRANCH {
        ir_write_ascii(compiler, ir, "  br label %")
        if target_kind == BRANCH_IF_END { ir_write_ascii(compiler, ir, "if.end.") }
        else if target_kind == BRANCH_IF_EXPR_END { ir_write_ascii(compiler, ir, "if.expr.end.") }
        else if target_kind == BRANCH_FOR_INCREMENT { ir_write_ascii(compiler, ir, "for.increment.") }
        else if target_kind == BRANCH_WHILE_STEP { ir_write_ascii(compiler, ir, "while.step.") }
        else { compiler.ir_overflow = true }
        ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, "\n")
    } else { compiler.ir_overflow = true }
}

// E3a1 begin: shared compiler integration.
fn emit_layout_address(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    result_node: long,
    location: StorageLocation,
) {
    if is_indexed_sum_parameter_location(location) {
        let pointer_location = StorageLocation {
            origin: location.origin,
            anchor_kind: location.anchor_kind,
            anchor_node: location.anchor_node,
            byte_offset: 0L,
            copies: location.copies,
            index: location.index,
            index_node: location.index_node,
            index_stride: location.index_stride,
        }
        let pointer_serial = emit_location_pointer_materialization(compiler, ir, pointer_location)
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, result_node)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, pointer_location, pointer_serial)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
        return
    }
    if location.origin != LOCATION_NATIVE || location.copies != 1L || location.index != 0L {
        if location.origin != LOCATION_DATA_STACK || location.copies != 1L || location.index != 0L { compiler.ir_overflow = true; return }
    }
    let pointer_location = compiler_location(compiler, location.anchor_kind, location.anchor_node, 0L)
    let pointer_serial = emit_location_pointer_materialization(compiler, ir, pointer_location)
    ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, result_node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
    emit_location_pointer_reference(compiler, ir, pointer_location, pointer_serial)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_write_ascii(compiler, ir, "\n")
}
// E3a1 end

recursive fn emit_collection_field_path_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    address_id: long,
) -> bool {
    compiler.type_walk.clear()
    var current = node
    for path_step in 0L..MAX_TREE_NODES {
        if current < 0L || tables.nodes[current].kind != NodeKind.Field { break }
        compiler.type_walk.push(TypeWalkFrame { type_index: current, field_index: -1L, size: 0L, align: 0L, case_index: 0L, max_size: 0L }).unwrap()
        current = compiler.child_first[current]
    }
    if current < 0L || tables.nodes[current].kind != NodeKind.Index {
        compiler.type_walk.clear()
        return false
    }
    let collection_node = compiler.child_first[current]
    let index_node = if collection_node >= 0L { compiler.child_next[collection_node] } else { -1L }
    if collection_node < 0L || index_node < 0L { compiler.type_walk.clear(); return false }
    let collection_type = compiler.facts[collection_node].ty
    let element_type = collection_element_type(compiler, collection_type)
    let copies = collection_capacity(compiler, collection_type)
    var byte_offset = collection_element_base_offset(compiler, collection_type)
    if type_kind(compiler, element_type) != TYPE_KIND_STRUCT || copies < 0L || byte_offset < 0L { compiler.type_walk.clear(); return false }
    for path_index in 0L..compiler.type_walk.count() {
        let field_node = compiler.type_walk[compiler.type_walk.count() - path_index - 1L].type_index
        let receiver = compiler.child_first[field_node]
        let receiver_type = compiler.facts[receiver].ty
        let field_index = compiler.facts[field_node].literal
        let field_number = field_index - type_record(compiler, receiver_type).field_start
        let field_offset = collection_field_lane_offset(compiler, receiver_type, copies, field_number)
        if field_offset < 0L { compiler.ir_overflow = true; compiler.type_walk.clear(); return true }
        byte_offset += field_offset
    }
    var location = collection_value_location(tables, compiler, collection_node)
    if tables.nodes[collection_node].kind == NodeKind.Field {
        let collection_address = emit_late_place_address(tables, compiler, ir, collection_node)
        location = compiler_location(compiler, 2L, collection_address, 0L)
    }
    let pointer = emit_location_pointer_materialization(compiler, ir, location)
    let field_type = compiler.facts[node].ty
    let stride = if is_aggregate_type(compiler, field_type) &&
        type_kind(compiler, field_type) != TYPE_KIND_BYTES && !is_sum_type(compiler, field_type) {
        0L
    } else { value_type_size(compiler, field_type) }
    if stride > 0L {
        ir_write_ascii(compiler, ir, "  %coll.field.index.bytes."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = mul i64 "); ir_write_value_ref(compiler, ir, index_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.field.index.offset."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, byte_offset); ir_write_ascii(compiler, ir, ", %coll.field.index.bytes."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", i64 %coll.field.index.offset."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
    } else {
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, byte_offset); ir_push_byte(compiler, ir, 10)
    }
    compiler.type_walk.clear()
    true
}

recursive fn emit_dynamic_group_size_for_descriptor(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies_binding: long,
) -> long {
    let kind = type_kind(compiler, type_id)
    if kind == TYPE_KIND_STRUCT {
        let record = type_record(compiler, type_id)
        var offset_serial = -1L
        var alignment = 1L
        for field_number in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_number]
            let field_align = value_type_align(compiler, field.ty)
            if field_align < 0L { compiler.ir_overflow = true; return -1L }
            if field_align > alignment { alignment = field_align }
            let rounded = next_location_serial(ir)
            ir_write_ascii(compiler, ir, "  %coll.desc.align.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = add i64 ")
            if offset_serial >= 0L { ir_write_ascii(compiler, ir, "%coll.desc.group.add."); ir_write_number(compiler, ir, offset_serial) }
            else { ir_write_ascii(compiler, ir, "0") }
            ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, field_align - 1L); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "  %coll.desc.align.mask."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = and i64 %coll.desc.align.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, ", -"); ir_write_number(compiler, ir, field_align); ir_push_byte(compiler, ir, 10)
            let size_serial = emit_dynamic_group_size_for_descriptor(compiler, ir, field.ty, copies_binding)
            if size_serial < 0L { return -1L }
            let added = next_location_serial(ir)
            ir_write_ascii(compiler, ir, "  %coll.desc.group.add."); ir_write_number(compiler, ir, added); ir_write_ascii(compiler, ir, " = add i64 %coll.desc.align.mask."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, ", %coll.desc.group.size."); ir_write_number(compiler, ir, size_serial); ir_push_byte(compiler, ir, 10)
            offset_serial = added
        }
        let rounded = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.final.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = add i64 ")
        if offset_serial >= 0L { ir_write_ascii(compiler, ir, "%coll.desc.group.add."); ir_write_number(compiler, ir, offset_serial) }
        else { ir_write_ascii(compiler, ir, "0") }
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, alignment - 1L); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.desc.group.size."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = and i64 %coll.desc.final.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, ", -"); ir_write_number(compiler, ir, alignment); ir_push_byte(compiler, ir, 10)
        rounded
    } else if kind == TYPE_KIND_ARRAY || kind == TYPE_KIND_LIST {
        // E3a2 forbids a collection-bearing struct as a collection element,
        // so descriptors that reach this branch have the standalone geometry
        // (one copy). Its inline collection storage has a static exact size.
        let size = value_type_size(compiler, type_id)
        if size < 0L { compiler.ir_overflow = true; return -1L }
        let serial = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.group.size."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_number(compiler, ir, size); ir_push_byte(compiler, ir, 10)
        serial
    } else {
        let size = value_type_size(compiler, type_id)
        if size < 0L { compiler.ir_overflow = true; return -1L }
        let serial = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.group.size."); ir_write_number(compiler, ir, serial); ir_write_ascii(compiler, ir, " = mul i64 %arg.copies."); ir_write_number(compiler, ir, copies_binding); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, size); ir_push_byte(compiler, ir, 10)
        serial
    }
}

fn emit_dynamic_field_lane_offset_for_descriptor(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    copies_binding: long,
    wanted_field: long,
) -> long {
    if type_kind(compiler, type_id) != TYPE_KIND_STRUCT { compiler.ir_overflow = true; return -1L }
    let record = type_record(compiler, type_id)
    if wanted_field < 0L || wanted_field >= record.field_count { compiler.ir_overflow = true; return -1L }
    var offset_serial = -1L
    for field_number in 0L..wanted_field + 1L {
        let field = compiler.struct_fields[record.field_start + field_number]
        let field_align = value_type_align(compiler, field.ty)
        let rounded = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.field.align.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = add i64 ")
        if offset_serial >= 0L { ir_write_ascii(compiler, ir, "%coll.desc.field.offset."); ir_write_number(compiler, ir, offset_serial) }
        else { ir_write_ascii(compiler, ir, "0") }
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, field_align - 1L); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %coll.desc.field.offset."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, " = and i64 %coll.desc.field.align.add."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, ", -"); ir_write_number(compiler, ir, field_align); ir_push_byte(compiler, ir, 10)
        if field_number == wanted_field { return rounded }
        let size_serial = emit_dynamic_group_size_for_descriptor(compiler, ir, field.ty, copies_binding)
        if size_serial < 0L { return -1L }
        let added = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.field.offset."); ir_write_number(compiler, ir, added); ir_write_ascii(compiler, ir, " = add i64 %coll.desc.field.offset."); ir_write_number(compiler, ir, rounded); ir_write_ascii(compiler, ir, ", %coll.desc.group.size."); ir_write_number(compiler, ir, size_serial); ir_push_byte(compiler, ir, 10)
        offset_serial = added
    }
    compiler.ir_overflow = true
    -1L
}

fn emit_parameter_field_path_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    address_id: long,
) -> bool {
    compiler.type_walk.clear()
    var current = node
    for path_step in 0L..MAX_TREE_NODES {
        if current < 0L || tables.nodes[current].kind != NodeKind.Field { break }
        compiler.type_walk.push(TypeWalkFrame { type_index: current, field_index: -1L, size: 0L, align: 0L, case_index: 0L, max_size: 0L }).unwrap()
        current = compiler.child_first[current]
    }
    if current < 0L || tables.nodes[current].kind != NodeKind.Name {
        compiler.type_walk.clear()
        return false
    }
    let binding = compiler.facts[current].binding
    if binding_is_view(compiler, binding) {
        let loop_node = compiler.bindings[binding].node
        let collection = compiler.child_first[loop_node]
        let collection_type = compiler.facts[collection].ty
        let copies = collection_capacity(compiler, collection_type)
        var field_type = compiler.bindings[binding].ty
        var byte_offset = collection_element_base_offset(compiler, collection_type)
        for path_index in 0L..compiler.type_walk.count() {
            let field_node = compiler.type_walk[compiler.type_walk.count() - path_index - 1L].type_index
            let field_number = compiler.facts[field_node].literal - type_record(compiler, field_type).field_start
            let lane_offset = collection_field_lane_offset(compiler, field_type, copies, field_number)
            if lane_offset < 0L { compiler.type_walk.clear(); compiler.ir_overflow = true; return true }
            byte_offset += lane_offset
            field_type = compiler.facts[field_node].ty
        }
        let base = collection_value_location(tables, compiler, collection)
        let pointer_location = compiler_location(compiler, base.anchor_kind, base.anchor_node, base.byte_offset)
        let pointer = emit_location_pointer_materialization(compiler, ir, pointer_location)
        if (!is_aggregate_type(compiler, field_type) || type_kind(compiler, field_type) == TYPE_KIND_BYTES || is_sum_type(compiler, field_type)) && field_type != TY_UNIT {
            let stride = value_type_size(compiler, field_type)
            ir_write_ascii(compiler, ir, "  %coll.view.index.bytes."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = mul i64 %for.each.current."); ir_write_number(compiler, ir, loop_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "  %coll.view.index.offset."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, byte_offset); ir_write_ascii(compiler, ir, ", %coll.view.index.bytes."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, pointer_location, pointer)
        ir_write_ascii(compiler, ir, ", i64 ")
        if (!is_aggregate_type(compiler, field_type) || type_kind(compiler, field_type) == TYPE_KIND_BYTES || is_sum_type(compiler, field_type)) && field_type != TY_UNIT { ir_write_ascii(compiler, ir, "%coll.view.index.offset."); ir_write_number(compiler, ir, address_id) }
        else { ir_write_number(compiler, ir, byte_offset) }
        ir_push_byte(compiler, ir, 10)
        compiler.type_walk.clear()
        return true
    }
    if binding < 0L || !compiler.bindings[binding].parameter || !is_aggregate_type(compiler, compiler.bindings[binding].ty) {
        compiler.type_walk.clear()
        return false
    }
    var field_type = compiler.bindings[binding].ty
    var total_serial = -1L
    for path_index in 0L..compiler.type_walk.count() {
        let field_node = compiler.type_walk[compiler.type_walk.count() - path_index - 1L].type_index
        let field_index = compiler.facts[field_node].literal
        let field_number = field_index - type_record(compiler, field_type).field_start
        let lane_serial = emit_dynamic_field_lane_offset_for_descriptor(compiler, ir, field_type, binding, field_number)
        if lane_serial < 0L { compiler.type_walk.clear(); return true }
        let sum = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.path.offset."); ir_write_number(compiler, ir, sum); ir_write_ascii(compiler, ir, " = add i64 ")
        if total_serial < 0L { ir_write_ascii(compiler, ir, "0") }
        else { ir_write_ascii(compiler, ir, "%coll.desc.path.offset."); ir_write_number(compiler, ir, total_serial) }
        ir_write_ascii(compiler, ir, ", %coll.desc.field.offset."); ir_write_number(compiler, ir, lane_serial); ir_push_byte(compiler, ir, 10)
        total_serial = sum
        field_type = compiler.facts[field_node].ty
    }
    if (!is_aggregate_type(compiler, field_type) || type_kind(compiler, field_type) == TYPE_KIND_BYTES || is_sum_type(compiler, field_type)) && field_type != TY_UNIT {
        let stride = value_type_size(compiler, field_type)
        let index_serial = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.element.index."); ir_write_number(compiler, ir, index_serial); ir_write_ascii(compiler, ir, " = mul i64 %arg.index."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
        let sum = next_location_serial(ir)
        ir_write_ascii(compiler, ir, "  %coll.desc.path.offset."); ir_write_number(compiler, ir, sum); ir_write_ascii(compiler, ir, " = add i64 %coll.desc.path.offset."); ir_write_number(compiler, ir, total_serial); ir_write_ascii(compiler, ir, ", %coll.desc.element.index."); ir_write_number(compiler, ir, index_serial); ir_push_byte(compiler, ir, 10)
        total_serial = sum
    }
    let base = compiler_location(compiler, 3L, binding, 0L)
    let pointer = emit_location_pointer_materialization(compiler, ir, base)
    ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
    emit_location_pointer_reference(compiler, ir, base, pointer)
    ir_write_ascii(compiler, ir, ", i64 %coll.desc.path.offset."); ir_write_number(compiler, ir, total_serial); ir_push_byte(compiler, ir, 10)
    compiler.type_walk.clear()
    true
}

fn emit_collection_view_name_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) -> bool {
    let binding = compiler.facts[node].binding
    if !binding_is_view(compiler, binding) || is_aggregate_type(compiler, compiler.bindings[binding].ty) { return false }
    let loop_node = compiler.bindings[binding].node
    let collection = compiler.child_first[loop_node]
    let collection_type = compiler.facts[collection].ty
    let element_type = collection_element_type(compiler, collection_type)
    let stride = if type_kind(compiler, collection_type) == TYPE_KIND_ASCII || type_kind(compiler, collection_type) == TYPE_KIND_BYTES { 1L }
        else { value_type_size(compiler, element_type) }
    let base_offset = collection_element_base_offset(compiler, collection_type)
    if stride < 0L || base_offset < 0L { compiler.ir_overflow = true; return true }
    let base = collection_value_location(tables, compiler, collection)
    let pointer_location = compiler_location(compiler, base.anchor_kind, base.anchor_node, base.byte_offset)
    let pointer = emit_location_pointer_materialization(compiler, ir, pointer_location)
    ir_write_ascii(compiler, ir, "  %coll.view.bytes."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = mul i64 %for.each.current."); ir_write_number(compiler, ir, loop_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %coll.view.offset."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, ", %coll.view.bytes."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, pointer_location, pointer); ir_write_ascii(compiler, ir, ", i64 %coll.view.offset."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 10)
    true
}

// E3a1 begin: shared compiler integration.
fn emit_aggregate_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let field_index = compiler.facts[node].literal
    let field = compiler.struct_fields[field_index]
    let receiver = compiler.child_first[node]
    if emit_collection_field_path_address(tables, compiler, ir, node, node) { return }
    if emit_parameter_field_path_address(tables, compiler, ir, node, node) { return }
    if tables.nodes[receiver].kind == NodeKind.Name {
        let binding = compiler.facts[receiver].binding
        if compiler.bindings[binding].parameter { emit_layout_address(compiler, ir, node, compiler_location(compiler, 3L, binding, field.offset)) }
        else { emit_layout_address(compiler, ir, node, compiler_location(compiler, 1L, binding, field.offset)) }
    } else if tables.nodes[receiver].kind == NodeKind.Field {
        emit_layout_address(compiler, ir, node, compiler_location(compiler, 2L, receiver, field.offset))
    } else {
        emit_layout_address(compiler, ir, node, compiler_location(compiler, 0L, receiver, field.offset))
    }
}
// E3a1 end

fn emit_field_path_value(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    compiler.type_walk.clear()
    var current = node
    for path_step in 0L..MAX_TREE_NODES {
        if current < 0L || tables.nodes[current].kind != NodeKind.Field { break }
        compiler.type_walk.push(TypeWalkFrame { type_index: current, field_index: -1L, size: 0L, align: 0L, case_index: 0L, max_size: 0L }).unwrap()
        current = compiler.child_first[current]
    }
    for path_index in 0L..compiler.type_walk.count() {
        let field_node = compiler.type_walk[compiler.type_walk.count() - path_index - 1L].type_index
        emit_aggregate_address(tables, compiler, ir, field_node)
        let field_ty = compiler.facts[field_node].ty
        if field_node == node && !is_aggregate_type(compiler, field_ty) && field_ty != TY_UNIT {
            emit_load_scalar(compiler, ir, field_node, field_ty)
        }
    }
    compiler.type_walk.clear()
}

// E3a1 begin: shared compiler integration.
fn emit_aggregate_copy(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    destination: StorageLocation,
    source: StorageLocation,
) {
    if type_kind(compiler, type_id) == TYPE_KIND_TEXT && text_read_view_binding(compiler, source) >= 0L {
        emit_text_read_view_copy(compiler, ir, type_id, destination, source)
        return
    }
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
    ir_write_ascii(compiler, ir, "  call void ")
    emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY)
    ir_push_byte(compiler, ir, 40)
    ir_write_ascii(compiler, ir, "ptr %nl.ctx, ptr ")
    emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", ")
    ir_write_ascii(compiler, ir, "ptr ")
    emit_location_pointer_reference(compiler, ir, source, source_pointer)
    ir_write_ascii(compiler, ir, ")\n")
    emit_text_assert_storage(compiler, ir, type_id, destination)
}
// E3a1 end

fn emit_aggregate_copy_to_place(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    destination_node: long,
    source_node: long,
    fallback_destination: StorageLocation,
) {
    let destination = place_storage_location(tables, compiler, destination_node)
    if destination.index_node != -1L && destination.copies > 0L && type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
        let base = compiler_location(compiler, destination.anchor_kind, destination.anchor_node, 0L)
        let destination_pointer = emit_location_pointer_materialization(compiler, ir, base)
        let source_kind = aggregate_source_kind(tables, compiler, source_node)
        let source_id = aggregate_source_id(tables, compiler, source_node)
        let source = aggregate_source_location(compiler, source_kind, source_id)
        let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
        emit_collection_store_element_fields(compiler, ir, type_id, destination.copies, 0L,
            destination.index_node, destination.byte_offset, 0L, base, source, destination_pointer, source_pointer)
    } else {
        let source_kind = aggregate_source_kind(tables, compiler, source_node)
        let source_id = aggregate_source_id(tables, compiler, source_node)
        emit_aggregate_copy(compiler, ir, type_id, fallback_destination, aggregate_source_location(compiler, source_kind, source_id))
    }
}

fn emit_type_helper_symbol(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    operation: long,
) {
    if !is_aggregate_type(compiler, type_id) || !has_type_helper(compiler, type_id, operation) {
        compiler.ir_overflow = true
        return
    }
    if operation == HELPER_COPY {
        if compiler.core_mode { ir_write_ascii(compiler, ir, "@nl.core.copy.") } else { ir_write_ascii(compiler, ir, "@nl.copy.") }
    }
    else if operation == HELPER_EQUAL {
        if compiler.core_mode { ir_write_ascii(compiler, ir, "@nl.core.eq.") } else { ir_write_ascii(compiler, ir, "@nl.eq.") }
    }
    else if operation == HELPER_PRINT {
        if compiler.core_mode { ir_write_ascii(compiler, ir, "@nl.core.print.") } else { ir_write_ascii(compiler, ir, "@nl.print.") }
    }
    else if operation == HELPER_FILL {
        if compiler.core_mode { ir_write_ascii(compiler, ir, "@nl.core.fill.") } else { ir_write_ascii(compiler, ir, "@nl.fill.") }
    }
    else { compiler.ir_overflow = true }
    ir_write_number(compiler, ir, type_id)
}

fn emit_default_field_helper_symbol(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    field_index: long,
) {
    if !has_type_helper(compiler, type_id, HELPER_DEFAULT) { compiler.ir_overflow = true }
    if compiler.core_mode { ir_write_ascii(compiler, ir, "@nl.core.default.") } else { ir_write_ascii(compiler, ir, "@nl.default.") }
    ir_write_number(compiler, ir, type_id)
    ir_push_byte(compiler, ir, 46)
    ir_write_number(compiler, ir, field_index)
}

// E3a1 begin: shared compiler integration.
fn emit_type_helper_call_one(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    operation: long,
    operand: StorageLocation,
    pointer: long,
) {
    let text_view_binding = text_read_view_binding(compiler, operand)
    if operation == HELPER_PRINT && type_kind(compiler, type_id) == TYPE_KIND_TEXT && text_view_binding >= 0L {
        emit_context_runtime_symbol(compiler, ir, "nl_print_ascii", "nlc_print_ascii")
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr ")
        emit_location_pointer_reference(compiler, ir, operand, pointer)
        ir_write_ascii(compiler, ir, ", i64 %arg.copies."); ir_write_number(compiler, ir, text_view_binding); ir_push_byte(compiler, ir, 41)
        return
    }
    emit_type_helper_symbol(compiler, ir, type_id, operation)
    ir_push_byte(compiler, ir, 40)
    ir_write_ascii(compiler, ir, "ptr %nl.ctx, ")
    ir_write_ascii(compiler, ir, "ptr ")
    emit_location_pointer_reference(compiler, ir, operand, pointer)
    ir_push_byte(compiler, ir, 41)
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_type_helper_call_two(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    operation: long,
    first: StorageLocation,
    second: StorageLocation,
    first_pointer: long,
    second_pointer: long,
) {
    emit_type_helper_symbol(compiler, ir, type_id, operation)
    ir_push_byte(compiler, ir, 40)
    ir_write_ascii(compiler, ir, "ptr %nl.ctx, ")
    ir_write_ascii(compiler, ir, "ptr ")
    emit_location_pointer_reference(compiler, ir, first, first_pointer)
    ir_write_ascii(compiler, ir, ", ")
    ir_write_ascii(compiler, ir, "ptr ")
    emit_location_pointer_reference(compiler, ir, second, second_pointer)
    ir_push_byte(compiler, ir, 41)
}
// E3a1 end

fn is_enum_case_field(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    if node < 0L || node >= tables.nodes.count() ||
        tables.nodes[node].kind != NodeKind.Field ||
        compiler.facts[node].binding >= 0L ||
        type_kind(compiler, compiler.facts[node].ty) != TYPE_KIND_ENUM {
        return false
    }
    // A qualified case keeps its type-name receiver unevaluated. A field
    // read from a temporary can also have no binding, so binding alone is
    // not enough to classify an enum-valued field as a constructor.
    let receiver = compiler.child_first[node]
    receiver >= 0L && tables.nodes[receiver].kind == NodeKind.Name &&
        compiler.facts[receiver].binding < 0L && compiler.facts[receiver].ty < 0L
}

fn aggregate_source_kind(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    if is_enum_case_field(tables, compiler, node) { 0L }
    else if tables.nodes[node].kind == NodeKind.Field { 3L }
    else if tables.nodes[node].kind == NodeKind.Name {
        let binding = compiler.facts[node].binding
        if binding < 0L { 0L }
        else if binding_is_view(compiler, binding) { 0L }
        else if compiler.bindings[binding].parameter { 2L } else { 1L }
    } else { 0L }
}

fn aggregate_source_id(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    if tables.nodes[node].kind == NodeKind.Name && binding_is_view(compiler, compiler.facts[node].binding) { node }
    else if tables.nodes[node].kind == NodeKind.Name && compiler.facts[node].binding >= 0L { compiler.facts[node].binding }
    else { node }
}

fn aggregate_source_location_for_node(
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
) -> StorageLocation {
    let kind = aggregate_source_kind(tables, compiler, node)
    let source_id = aggregate_source_id(tables, compiler, node)
    aggregate_source_location(compiler, kind, source_id)
}

fn emit_store_scalar(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    ty: long,
    value_node: long,
) {
    if ty == TY_BOOL {
        ir_write_ascii(compiler, ir, "  %bool.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, " to i8\n  store i8 %bool.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1")
    } else {
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1")
    }
    emit_program_storage_tbaa(compiler, ir)
    ir_push_byte(compiler, ir, 10)
}

// Recompute a place pointer after evaluating the assignment value. A call on
// the right hand side can grow the data stack and move every stack slot, so an
// address emitted while evaluating the left hand side is only for reading.
recursive fn emit_late_place_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) -> long {
    let address_id = MAX_TREE_NODES * 1024L + next_location_serial(ir) * MAX_TREE_NODES + node
    if tables.nodes[node].kind == NodeKind.Field {
        if emit_collection_field_path_address(tables, compiler, ir, node, address_id) { return address_id }
        if emit_parameter_field_path_address(tables, compiler, ir, node, address_id) { return address_id }
    }
    if tables.nodes[node].kind == NodeKind.Index {
        let collection = compiler.child_first[node]
        let index_node = if collection >= 0L { compiler.child_next[collection] } else { -1L }
        if collection >= 0L && index_node >= 0L && tables.nodes[collection].kind == NodeKind.Field {
            let collection_address = emit_late_place_address(tables, compiler, ir, collection)
            let base = compiler_location(compiler, 2L, collection_address, 0L)
            let pointer = emit_location_pointer_materialization(compiler, ir, base)
            let type_id = compiler.facts[collection].ty
            let element_type = collection_element_type(compiler, type_id)
            let stride = value_type_size(compiler, element_type)
            let base_offset = collection_element_base_offset(compiler, type_id)
            if stride < 0L || base_offset < 0L { compiler.ir_overflow = true; return address_id }
            ir_write_ascii(compiler, ir, "  %late.place.index."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = mul i64 "); ir_write_value_ref(compiler, ir, index_node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, stride); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "  %late.place.offset."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = add i64 %late.place.index."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, base_offset); ir_push_byte(compiler, ir, 10)
            ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
            emit_location_pointer_reference(compiler, ir, base, pointer)
            ir_write_ascii(compiler, ir, ", i64 %late.place.offset."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
            return address_id
        }
    }
    let location = place_storage_location(tables, compiler, node)
    if location.copies != 1L { compiler.ir_overflow = true; return address_id }
    let base = StorageLocation {
        origin: location.origin,
        anchor_kind: location.anchor_kind,
        anchor_node: location.anchor_node,
        byte_offset: 0L,
        copies: 1L,
        index: 0L,
        index_node: -1L,
        index_stride: 0L,
    }
    let pointer = emit_location_pointer_materialization(compiler, ir, base)
    if location.index_node != -1L {
        if location.index_stride <= 0L { compiler.ir_overflow = true; return address_id }
        ir_write_ascii(compiler, ir, "  %late.place.index."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = mul i64 ")
        emit_location_index_value(compiler, ir, location)
        ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, location.index_stride); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %late.place.offset."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_write_ascii(compiler, ir, ", %late.place.index."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, base, pointer)
        ir_write_ascii(compiler, ir, ", i64 %late.place.offset."); ir_write_number(compiler, ir, address_id); ir_push_byte(compiler, ir, 10)
    } else {
        ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
        emit_location_pointer_reference(compiler, ir, base, pointer)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_push_byte(compiler, ir, 10)
    }
    address_id
}

fn emit_store_scalar_to_place(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    ty: long,
    value_node: long,
) {
    let address_id = emit_late_place_address(tables, compiler, ir, node)
    if ty == TY_BOOL {
        ir_write_ascii(compiler, ir, "  %late.bool.store."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, " to i8\n  store i8 %late.bool.store."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", align 1")
    } else {
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", align 1")
    }
    emit_program_storage_tbaa(compiler, ir)
    ir_push_byte(compiler, ir, 10)
}

fn emit_load_scalar(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    ty: long,
) {
    if ty == TY_BOOL {
        ir_write_ascii(compiler, ir, "  %bool.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i8 %bool.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i1\n")
    } else {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    }
}

fn ir_write_token_text(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    file_index: long,
    token: long,
) {
    let start = files[file_index].base + tokens[token].start
    for index in 0L..tokens[token].length { ir_push_byte(compiler, ir, source[start + index]) }
}

// E3a1 begin: shared compiler integration.
fn core_external_symbol(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    token: long,
) -> bool {
    token_is_word_at(source, tokens, files, file_index, token, "nl_core_start") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_core_init") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_create") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_base_offset") ||
    // E3a1 subsection
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_current_base") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_current_limit") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_reservation_bytes") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_set_top_offset") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_note_peak") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_set_entry_name") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_stack_grow") ||
    // E3a1 subsection end
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_destroy") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_env_create") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_env_destroy") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_register_files") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_test_selected_index") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_set_test_mode") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_int") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_long") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_bool") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_int_raw") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_long_raw") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_bool_raw") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_ascii") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_print_newline") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_fail") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_expect_fail_compare") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_expect_fail_bool") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_expect_fail_header") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_expect_fail_left") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_expect_fail_right") ||
    token_is_word_at(source, tokens, files, file_index, token, "memcpy") ||
    token_is_word_at(source, tokens, files, file_index, token, "memmove") ||
    token_is_word_at(source, tokens, files, file_index, token, "memset") ||
    token_is_word_at(source, tokens, files, file_index, token, "memcmp") ||
    token_is_word_at(source, tokens, files, file_index, token, "bcmp")
}
// E3a1 end

// E3a1 begin: core helpers carry the job context unless they create it or
// are freestanding memory/startup primitives.
fn core_function_has_context(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    function: FunctionRecord,
) -> bool {
    files[function.file].name != b"memory.nl" &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "nl_context_create") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "map") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "protect") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "unmap") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "nl_core_start") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "auxiliary_value") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "count_entries") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "startup_write_all") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "startup_write_z") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "startup_write_digit") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "startup_write_number") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "write_context_startup_failure") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "find_environment_in") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "startup_string_length") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "context_header_bytes") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "core_state_bytes") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "stack_poison_record_bytes") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "stack_poison_record_capacity") &&
        !token_is_word_at(source, tokens, files, function.file, function.name_token, "stack_default_bytes")
}
// E3a1 end

fn ir_write_core_function_symbol(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    function: FunctionRecord,
    function_id: long,
) {
    if !compiler.core_mode {
        ir_write_ascii(compiler, ir, "@nl_fn_")
        ir_write_number(compiler, ir, function_id)
        return
    }
    if !core_external_symbol(source, tokens, files, function.file, function.name_token) {
        ir_write_ascii(compiler, ir, "@nl_core_")
    } else {
        ir_push_byte(compiler, ir, 64)
    }
    ir_write_token_text(source, files, tokens, compiler, ir, function.file, function.name_token)
}

// E3a1 begin: shared compiler integration.
fn emit_runtime_failure(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    kind: long,
) {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].anchor, compiler)
    ir_write_ascii(compiler, ir, "  br i1 %ov.flag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %ov.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %ov.ok."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nov.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if compiler.memory_closure { ir_write_ascii(compiler, ir, "  call void @llvm.trap()\n  unreachable\n") }
    else {
        ir_write_ascii(compiler, ir, "  call void ")
        emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail")
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 "); ir_write_number(compiler, ir, kind); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\n")
    }
    ir_write_ascii(compiler, ir, "ov.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_checked_division(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    left: long,
    right: long,
    ty: long,
    is_remainder: bool,
) {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].anchor, compiler)
    let llvm_ty = llvm_type_name(ty)
    ir_write_ascii(compiler, ir, "  %div.zero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", 0\n  br i1 %div.zero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.zero.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.nonzero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ndiv.zero.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 9, i32 "); ir_write_number(compiler, ir, file_index); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\ndiv.nonzero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    let minimum = if ty == TY_INT { "-2147483648" } else { "-9223372036854775808" }
    let overflow_kind = if ty == TY_INT { 12L } else { 13L }
    ir_write_ascii(compiler, ir, "  %div.min."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, minimum); ir_write_ascii(compiler, ir, "\n  %div.minusone."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", -1\n  %div.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = and i1 %div.min."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %div.minusone."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
    if is_remainder {
        ir_write_ascii(compiler, ir, "  br i1 %div.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %rem.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %rem.compute."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nrem.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  store "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " 0, ptr %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  br label %rem.join."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nrem.compute."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %rem.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = srem "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, "\n  store "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " %rem.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  br label %rem.join."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nrem.join."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, ", ptr %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    } else {
        ir_write_ascii(compiler, ir, "  br i1 %div.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.overflow."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.safe."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ndiv.overflow."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 "); ir_write_number(compiler, ir, overflow_kind); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, file_index); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\ndiv.safe."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sdiv "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, "\n")
    }
}
// E3a1 end

fn emit_checked_shift(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    left: long,
    right: long,
    ty: long,
    is_left: bool,
) {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].anchor, compiler)
    let llvm_ty = llvm_type_name(ty)
    let width = if ty == TY_INT { 32L } else { 64L }
    ir_write_ascii(compiler, ir, "  %shift.negative."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp slt "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", 0\n  %shift.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sge "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, width); ir_write_ascii(compiler, ir, "\n  %shift.bad."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i1 %shift.negative."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %shift.high."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  br i1 %shift.bad."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %shift.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %shift.good."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nshift.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 11, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\nshift.good."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ");
    if is_left { ir_write_ascii(compiler, ir, "shl ") } else { ir_write_ascii(compiler, ir, "ashr ") }
    ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_push_byte(compiler, ir, 10)
}

fn emit_compound_assignment(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    target: long,
    binding: long,
    value: long,
    ty: long,
    op: long,
) {
    if op == 1L && type_kind(compiler, ty) == TYPE_KIND_ASCII {
        emit_ascii_append_assignment(tables, compiler, ir, node, target, binding, value)
        return
    }
    let field_target = tables.nodes[target].kind == NodeKind.Field
    let place_target = field_target || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, binding) || binding_is_view(compiler, binding)
    if !place_target { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
    if op == 1L || op == 2L || op == 3L {
        let binary_op = op - 1L
        ir_write_ascii(compiler, ir, "  %ov.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } @llvm.s")
        if binary_op == 0L { ir_write_ascii(compiler, ir, "add") } else if binary_op == 1L { ir_write_ascii(compiler, ir, "sub") } else { ir_write_ascii(compiler, ir, "mul") }
        ir_write_ascii(compiler, ir, ".with.overflow."); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ")\n")
        ir_write_ascii(compiler, ir, "  %asgn.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n  %ov.flag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n")
        let failure_kind = if ty == TY_INT { binary_op + 1L } else { binary_op + 5L }
        emit_runtime_failure(files, tables, compiler, ir, node, file_index, failure_kind)
        let address_id = if place_target { emit_late_place_address(tables, compiler, ir, target) } else { -1L }
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %asgn.value."); ir_write_number(compiler, ir, node)
        if place_target { ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", align 1") }
        else { ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1") }
        emit_program_storage_tbaa(compiler, ir)
        ir_push_byte(compiler, ir, 10)
    } else {
        if op == 4L || op == 5L { emit_checked_division(files, tables, compiler, ir, node, file_index, target, value, ty, op == 5L) }
        else if op == 6L || op == 7L { emit_checked_shift(files, tables, compiler, ir, node, file_index, target, value, ty, op == 7L) }
        else {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ")
            if op == 8L { ir_write_ascii(compiler, ir, "and ") }
            else if op == 9L { ir_write_ascii(compiler, ir, "or ") }
            else { ir_write_ascii(compiler, ir, "xor ") }
            ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, value); ir_push_byte(compiler, ir, 10)
        }
        let address_id = if place_target { emit_late_place_address(tables, compiler, ir, target) } else { -1L }
        if place_target {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address_id); ir_write_ascii(compiler, ir, ", align 1")
        } else {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1")
        }
        emit_program_storage_tbaa(compiler, ir)
        ir_push_byte(compiler, ir, 10)
    }
}

fn core_syscall_number(operation: long) -> long {
    if operation == SYS_WRITE { 1L }
    else if operation == SYS_EXIT_GROUP { 231L }
    else if operation == SYS_MAP { 9L }
    else if operation == SYS_PROTECT { 10L }
    else if operation == SYS_IOCTL { 16L }
    else if operation == SYS_STATX { 332L }
    else if operation == SYS_SIGACTION { 13L }
    else if operation == SYS_OPENAT { 257L }
    else if operation == SYS_CLOSE { 3L }
    // E3a1 begin
    else if operation == SYS_REMAP { 25L }
    else if operation == SYS_UNMAP { 11L }
    else if operation == SYS_CLOCK_GETTIME { 228L }
    // E3a1 end
    else { -1L }
}

// E3a1 begin: these helpers read the one core declaration and never mirror
// byte offsets in compiler source.
fn context_struct_index(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
) -> long {
    for type_index in 0L..struct_type_count(compiler) {
        let record = struct_record(compiler, type_index)
        if token_is_word_at(source, tokens, files, record.file, record.name_token, "DataStackContext") {
            return type_index
        }
    }
    -1L
}

fn context_core_state_field_index(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
) -> long {
    let context_index = context_struct_index(source, tokens, files, compiler)
    if context_index < 0L { return -1L }
    let record = struct_record(compiler, context_index)
    for field_offset in 0L..record.field_count {
        let field_index = record.field_start + field_offset
        if token_is_word_at(source, tokens, files, record.file, compiler.struct_fields[field_index].name_token, "core_state") {
            return field_offset
        }
    }
    -1L
}

fn context_base_field_index(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
) -> long {
    let context_index = context_struct_index(source, tokens, files, compiler)
    if context_index < 0L { return -1L }
    let record = struct_record(compiler, context_index)
    for field_offset in 0L..record.field_count {
        let field_index = record.field_start + field_offset
        if token_is_word_at(source, tokens, files, record.file, compiler.struct_fields[field_index].name_token, "base") {
            return field_offset
        }
    }
    -1L
}

fn context_field_offset(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    field_index: long,
) -> long {
    let context_index = context_struct_index(source, tokens, files, compiler)
    if context_index < 0L { return -1L }
    let record = struct_record(compiler, context_index)
    if field_index < 0L || field_index >= record.field_count { return -1L }
    compiler.struct_fields[record.field_start + field_index].offset
}

fn is_stack_address_node(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    file_index: long,
) -> bool {
    tables.nodes[node].kind == NodeKind.MethodCall &&
        is_core_sys_receiver(source, tokens, files, tables, compiler, node, file_index) &&
        core_sys_operation(source, tokens, files, file_index, tables.nodes[node].token) == SYS_STACK_ADDR
}

fn is_context_base_load(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    file_index: long,
) -> bool {
    if !compiler.core_mode { return false }
    for function_id in 0L..compiler.functions.count() {
        let function = compiler.functions[function_id]
        if function.file != file_index || !token_is_word_at(source, tokens, files, function.file, function.name_token, "nl_context_current_base") { continue }
        let body = function.body
        let first = body - tables.nodes[body].subtree + 1L
        if node >= first && node <= body { return true }
    }
    false
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_sys_method(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let syntax = tables.nodes[node]
    let operation = core_sys_operation(source, tokens, files, file_index, syntax.token)
    let collection_operation = compiler.facts[node].literal
    if collection_operation >= COLLECTION_METHOD_LEN && collection_operation <= COLLECTION_METHOD_POP {
        emit_collection_method(source, files, tables, compiler, ir, node, file_index, collection_operation)
        return
    }
    let receiver = compiler.child_first[node]
    var first_arg = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
    if operation == SYS_NULL {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = inttoptr i64 0 to ptr\n")
        return
    }
    // E3a1 subsection
    if operation == SYS_IS_TEST_BUILD {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i1 0, ")
        ir_write_ascii(compiler, ir, if compiler_test_build(compiler) { "true\n" } else { "false\n" })
        return
    }
    if operation == SYS_CONTEXT {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.ctx, i64 0\n")
        return
    }
    if operation == SYS_CONTEXT_OFFSET {
        let field_arg = first_arg
        let context_index = context_struct_index(source, tokens, files, compiler)
        if context_index < 0L { compiler.ir_overflow = true; return }
        let context_record = struct_record(compiler, context_index)
        if tables.nodes[field_arg].kind == NodeKind.Integer {
            let field_index = compiler.facts[field_arg].literal
            let byte_offset = context_field_offset(source, tokens, files, compiler, field_index)
            if byte_offset < 0L { compiler.ir_overflow = true; return }
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_number(compiler, ir, byte_offset); ir_write_ascii(compiler, ir, "\n")
        } else {
            for field_index in 0L..context_record.field_count {
                let byte_offset = context_field_offset(source, tokens, files, compiler, field_index)
                ir_write_ascii(compiler, ir, "  %sys.context.offset.match."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = icmp eq i64 "); ir_write_value_ref(compiler, ir, field_arg); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\n  %sys.context.offset.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = select i1 %sys.context.offset.match."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, byte_offset); ir_write_ascii(compiler, ir, ", i64 ")
                if field_index == 0L { ir_write_ascii(compiler, ir, "-1\n") }
                else { ir_write_ascii(compiler, ir, "%sys.context.offset.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, field_index - 1L); ir_write_ascii(compiler, ir, "\n") }
            }
            let last = context_record.field_count - 1L
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 true, i64 %sys.context.offset.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, last); ir_write_ascii(compiler, ir, ", i64 %sys.context.offset.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, last); ir_write_ascii(compiler, ir, "\n")
        }
        return
    }
    if operation == SYS_CONTEXT_SIZE {
        let context_index = context_struct_index(source, tokens, files, compiler)
        if context_index < 0L { compiler.ir_overflow = true; return }
        let context_type = struct_type_id(compiler, context_index)
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_number(compiler, ir, value_type_size(compiler, context_type)); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_STACK_ADDR {
        let context_arg = first_arg
        let offset_arg = compiler.child_next[context_arg]
        let base_field = context_base_field_index(source, tokens, files, compiler)
        let base_offset = context_field_offset(source, tokens, files, compiler, base_field)
        if base_offset < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %sys.stack.addr.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, context_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n")
        ir_write_ascii(compiler, ir, "  %sys.stack.addr.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load ptr, ptr %sys.stack.addr.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n")
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %sys.stack.addr.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_STACK_LOAD8 || operation == SYS_STACK_STORE8 {
        let context_arg = first_arg
        let offset_arg = compiler.child_next[context_arg]
        let base_field = context_base_field_index(source, tokens, files, compiler)
        let base_offset = context_field_offset(source, tokens, files, compiler, base_field)
        if base_offset < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %sys.stack.base.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, context_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %sys.stack.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load ptr, ptr %sys.stack.base.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n  %sys.stack.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %sys.stack.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n")
        if operation == SYS_STACK_LOAD8 {
            ir_write_ascii(compiler, ir, "  %sys.stack.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i8, ptr %sys.stack.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i8 %sys.stack.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i32\n")
        } else {
            let value_arg = compiler.child_next[offset_arg]
            ir_write_ascii(compiler, ir, "  %sys.stack.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i32 "); ir_write_value_ref(compiler, ir, value_arg); ir_write_ascii(compiler, ir, " to i8\n  store i8 %sys.stack.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %sys.stack.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        return
    }
    // E3a1 subsection end
    if operation == SYS_STATE {
        let field_index = context_core_state_field_index(source, tokens, files, compiler)
        let byte_offset = context_field_offset(source, tokens, files, compiler, field_index)
        if byte_offset < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %sys.state.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %nl.ctx, i64 "); ir_write_number(compiler, ir, byte_offset); ir_write_ascii(compiler, ir, "\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load ptr, ptr %sys.state.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 8\n")
        return
    }
    if operation == SYS_LIT {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", i64 0\n")
        return
    }
    if operation == SYS_IS_NULL {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", null\n")
        return
    }
    if operation == SYS_OFFSET {
        let offset_arg = compiler.child_next[first_arg]
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_DISTANCE {
        let to_arg = compiler.child_next[first_arg]
        ir_write_ascii(compiler, ir, "  %sys.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ptrtoint ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, " to i64\n  %sys.addr2."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ptrtoint ptr "); ir_write_value_ref(compiler, ir, to_arg); ir_write_ascii(compiler, ir, " to i64\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sub i64 %sys.addr2."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %sys.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_FROM_RAW {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = inttoptr i64 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, " to ptr\n")
        return
    }
    if operation == SYS_LOAD8 || operation == SYS_LOAD32 || operation == SYS_LOAD64 || operation == SYS_LOAD_ADDR {
        let offset_arg = compiler.child_next[first_arg]
        ir_write_ascii(compiler, ir, "  %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n")
        let value_type = if operation == SYS_LOAD8 { "i8" } else if operation == SYS_LOAD32 { "i32" } else if operation == SYS_LOAD64 { "i64" } else { "ptr" }
        ir_write_ascii(compiler, ir, "  %sys.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, value_type); ir_write_ascii(compiler, ir, ", ptr %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1")
        if operation == SYS_LOAD_ADDR && is_context_base_load(source, files, tokens, tables, compiler, node, file_index) {
            ir_write_ascii(compiler, ir, ", !tbaa !9002")
        }
        ir_push_byte(compiler, ir, 10)
        if operation == SYS_LOAD8 {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i8 %sys.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i32\n")
        } else {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = select i1 true, "); ir_write_ascii(compiler, ir, value_type); ir_write_ascii(compiler, ir, " %sys.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, value_type); ir_write_ascii(compiler, ir, " %sys.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        }
        return
    }
    if operation == SYS_STORE8 || operation == SYS_STORE32 || operation == SYS_STORE64 || operation == SYS_STORE_ADDR {
        let offset_arg = compiler.child_next[first_arg]
        let value_arg = compiler.child_next[offset_arg]
        let value_type = if operation == SYS_STORE8 { "i8" } else if operation == SYS_STORE32 { "i32" } else if operation == SYS_STORE64 { "i64" } else { "ptr" }
        ir_write_ascii(compiler, ir, "  %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n")
        if operation == SYS_STORE8 {
            ir_write_ascii(compiler, ir, "  %sys.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i32 "); ir_write_value_ref(compiler, ir, value_arg); ir_write_ascii(compiler, ir, " to i8\n  store i8 %sys.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
        } else {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, value_type); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_arg); ir_write_ascii(compiler, ir, ", ptr %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        return
    }
    if operation == SYS_IS_ERROR {
        ir_write_ascii(compiler, ir, "  %sys.err.lo."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sge i64 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", -4095\n  %sys.err.hi."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sle i64 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", -1\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = and i1 %sys.err.lo."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %sys.err.hi."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_REPEAT_BYTE {
        ir_write_ascii(compiler, ir, "  %sys.repeat.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i32 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, " to i8\n  %sys.repeat.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i8 %sys.repeat.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i64\n  %sys.repeat.shift8."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = shl i64 %sys.repeat.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 8\n  %sys.repeat.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i64 %sys.repeat.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %sys.repeat.shift8."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %sys.repeat.shift16."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = shl i64 %sys.repeat.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 16\n  %sys.repeat.word."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i64 %sys.repeat.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %sys.repeat.shift16."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n  %sys.repeat.shift32."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = shl i64 %sys.repeat.word."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 32\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = or i64 %sys.repeat.word."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %sys.repeat.shift32."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
        return
    }
    if operation == SYS_COPY_16 {
        let src_arg = compiler.child_next[first_arg]
        ir_write_ascii(compiler, ir, "  %sys.copy16.src."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load <16 x i8>, ptr "); ir_write_value_ref(compiler, ir, src_arg); ir_write_ascii(compiler, ir, ", align 1\n  store <16 x i8> %sys.copy16.src."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", align 1\n")
        return
    }
    if operation == SYS_FILL_16 {
        let value_arg = compiler.child_next[first_arg]
        ir_write_ascii(compiler, ir, "  %sys.fill16.half."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = bitcast i64 "); ir_write_value_ref(compiler, ir, value_arg); ir_write_ascii(compiler, ir, " to <8 x i8>\n  %sys.fill16.vector."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = shufflevector <8 x i8> %sys.fill16.half."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", <8 x i8> %sys.fill16.half."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", <16 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7>\n  store <16 x i8> %sys.fill16.vector."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", align 1\n")
        return
    }
    if operation == SYS_COPY_FORWARD_BULK {
        let src_arg = compiler.child_next[first_arg]
        let n_arg = compiler.child_next[src_arg]
        ir_write_ascii(compiler, ir, "  %sys.bulk.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call { ptr, ptr, i64 } asm sideeffect \"rep movsb\", \"={di},={si},={cx},0,1,2,~{memory},~{dirflag}\"(ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, src_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, n_arg); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    if operation == SYS_FILL_BULK {
        let value_arg = compiler.child_next[first_arg]
        let n_arg = compiler.child_next[value_arg]
        ir_write_ascii(compiler, ir, "  %sys.fill."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i32 "); ir_write_value_ref(compiler, ir, value_arg); ir_write_ascii(compiler, ir, " to i8\n  %sys.bulk.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call { ptr, i64 } asm sideeffect \"rep stosb\", \"={di},={cx},0,{ax},1,~{memory},~{dirflag}\"(ptr "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", i8 %sys.fill."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, n_arg); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    if operation == SYS_CALL_MAIN {
        let argv_arg = compiler.child_next[first_arg]
        let envp_arg = compiler.child_next[argv_arg]
        let auxv_arg = compiler.child_next[envp_arg]
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i32 @main(i32 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, argv_arg); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, envp_arg); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, auxv_arg); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    let argument_count = core_sys_argument_count(operation)
    let syscall = core_syscall_number(operation)
    for argument_index in 0L..argument_count {
        let argument = child_at(tables, compiler, node, argument_index + 1L)
        let ty = core_sys_argument_type(operation, argument_index)
        if !is_stack_address_node(source, tokens, files, tables, compiler, argument, file_index) {
            ir_write_ascii(compiler, ir, "  %sys.arg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = ")
            if ty == TY_ADDR { ir_write_ascii(compiler, ir, "ptrtoint ptr "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n") }
            else if ty == TY_INT { ir_write_ascii(compiler, ir, "sext i32 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n") }
            else if ty == TY_BOOL { ir_write_ascii(compiler, ir, "zext i1 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n") }
            else { ir_write_ascii(compiler, ir, "add i64 0, "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, "\n") }
        }
    }
    // Derive stack addresses only after all argument expressions have run.
    // There is no call between these reloads and the raw syscall below.
    for argument_index in 0L..argument_count {
        let argument = child_at(tables, compiler, node, argument_index + 1L)
        if !is_stack_address_node(source, tokens, files, tables, compiler, argument, file_index) { continue }
        let address_receiver = compiler.child_first[argument]
        let context_arg = compiler.child_next[address_receiver]
        let offset_arg = compiler.child_next[context_arg]
        let base_field = context_base_field_index(source, tokens, files, compiler)
        let base_offset = context_field_offset(source, tokens, files, compiler, base_field)
        if base_offset < 0L { compiler.ir_overflow = true; return }
        ir_write_ascii(compiler, ir, "  %sys.stack.addr.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); ir_write_value_ref(compiler, ir, context_arg); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, base_offset); ir_write_ascii(compiler, ir, "\n  %sys.stack.addr.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = load ptr, ptr %sys.stack.addr.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, ", align 8\n  %sys.stack.addr.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr %sys.stack.addr.base."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, offset_arg); ir_write_ascii(compiler, ir, "\n  %sys.arg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = ptrtoint ptr %sys.stack.addr.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " to i64\n")
    }
    if operation == SYS_EXIT_GROUP { ir_write_ascii(compiler, ir, "  ") }
    else { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ") }
    ir_write_ascii(compiler, ir, "call i64 @nl.sys.call"); ir_write_number(compiler, ir, argument_count); ir_write_ascii(compiler, ir, "(i64 "); ir_write_number(compiler, ir, syscall)
    for argument_index in 0L..argument_count {
        ir_write_ascii(compiler, ir, ", i64 %sys.arg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index)
    }
    ir_write_ascii(compiler, ir, ")\n")
    if operation == SYS_EXIT_GROUP { ir_write_ascii(compiler, ir, "  unreachable\n") }
}
// E3a1 end

fn enum_temporary_address(node: long, part: long) -> long {
    1000000000000L + node * (MAX_TREE_NODES + 1L) + part
}

fn emit_enum_tag_store(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    tag: long,
) {
    let address = enum_temporary_address(node, 0L)
    emit_layout_address(compiler, ir, address, aggregate_destination_location(compiler, 0L, node))
    ir_write_ascii(compiler, ir, "  %enum.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i32 0, "); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, "\n  store i32 %enum.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n")
}

fn emit_sum_tag_store(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    tag: long,
) {
    let address = enum_temporary_address(node, MAX_TREE_NODES * 2L + tag)
    emit_layout_address(compiler, ir, address, aggregate_destination_location(compiler, 0L, node))
    ir_write_ascii(compiler, ir, "  %sum.tag."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, " = add i32 0, "); ir_write_number(compiler, ir, tag)
    ir_write_ascii(compiler, ir, "\n  store i32 %sum.tag."); ir_write_number(compiler, ir, node); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n")
}

fn emit_enum_constructor_payload(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    constructor: long,
    case_index: long,
    payload_index: long,
    value_node: long,
) {
    let case = compiler.enum_cases[case_index]
    let payload = compiler.enum_payloads[case.payload_start + payload_index]
    if payload.ty == TY_UNIT { return }
    let address = enum_temporary_address(constructor, payload_index + 1L)
    emit_layout_address(compiler, ir, address, storage_location_with_offset(aggregate_destination_location(compiler, 0L, constructor), payload.offset))
    if is_aggregate_type(compiler, payload.ty) {
        let source_kind = aggregate_source_kind(tables, compiler, value_node)
        let source_node = aggregate_source_id(tables, compiler, value_node)
        emit_aggregate_copy(compiler, ir, payload.ty, compiler_location(compiler, 2L, address, 0L), aggregate_source_location(compiler, source_kind, source_node))
    } else {
        emit_store_scalar(compiler, ir, address, payload.ty, value_node)
    }
}

fn emit_sum_constructor_payload(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    constructor: long,
    payload_index: long,
    value_node: long,
) {
    let type_id = compiler.facts[constructor].ty
    let tag = compiler.facts[constructor].literal
    let payload = sum_payload_record(compiler, type_id, tag, payload_index)
    if payload.ty == TY_UNIT { return }
    let address = enum_temporary_address(constructor, MAX_TREE_NODES + payload_index + 1L)
    emit_layout_address(compiler, ir, address, storage_location_with_offset(aggregate_destination_location(compiler, 0L, constructor), payload.offset))
    if is_aggregate_type(compiler, payload.ty) {
        let source_kind = aggregate_source_kind(tables, compiler, value_node)
        let source_node = aggregate_source_id(tables, compiler, value_node)
        emit_aggregate_copy(compiler, ir, payload.ty, compiler_location(compiler, 2L, address, 0L), aggregate_source_location(compiler, source_kind, source_node))
    } else {
        emit_store_scalar(compiler, ir, address, payload.ty, value_node)
    }
}

fn emit_match_payload_bindings(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    match_node: long,
    arm: long,
) {
    let scrutinee = compiler.child_first[match_node]
    let pattern = compiler.child_first[arm]
    if tables.nodes[pattern].kind != NodeKind.CasePattern { return }
    let source_kind = aggregate_source_kind(tables, compiler, scrutinee)
    let source_node = aggregate_source_id(tables, compiler, scrutinee)
    let matched_ty = compiler.facts[scrutinee].ty
    let generic_sum = type_kind(compiler, matched_ty) == TYPE_KIND_OPTION || type_kind(compiler, matched_ty) == TYPE_KIND_RESULT
    let case_index = compiler.facts[pattern].binding
    if !generic_sum && case_index < 0L { return }
    let case = if generic_sum { EnumCaseRecord { owner: -1L, name_id: -1L, name_token: -1L, node: -1L, payload_start: -1L, payload_count: sum_case_payload_count(compiler, matched_ty, compiler.facts[pattern].literal), tag: compiler.facts[pattern].literal } } else { compiler.enum_cases[case_index] }
    var binding_node = compiler.child_first[pattern]
    for payload_index in 0L..case.payload_count {
        if binding_node < 0L { break }
        let payload = if generic_sum { sum_payload_record(compiler, matched_ty, compiler.facts[pattern].literal, payload_index) }
            else { compiler.enum_payloads[case.payload_start + payload_index] }
        if tables.nodes[binding_node].kind == NodeKind.PatternBinding {
            let binding = compiler.facts[binding_node].binding
            let source_address = aggregate_source_location(compiler, source_kind, source_node)
            emit_layout_address(compiler, ir, binding_node, storage_location_with_offset(source_address, payload.offset))
            if payload.ty != TY_UNIT {
                if is_aggregate_type(compiler, payload.ty) {
                    emit_aggregate_copy(compiler, ir, payload.ty, aggregate_destination_location(compiler, 1L, binding), aggregate_source_location(compiler, 3L, binding_node))
                } else if payload.ty == TY_BOOL {
                    ir_write_ascii(compiler, ir, "  %match.bool."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, ", align 1\n  store i8 %match.bool."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                } else {
                    ir_write_ascii(compiler, ir, "  %match.payload."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty)); ir_write_ascii(compiler, ir, " %match.payload."); ir_write_number(compiler, ir, binding_node); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                }
            }
        }
        binding_node = compiler.child_next[binding_node]
    }
}

fn emit_sum_payload_transfer(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    payload_ty: long,
    source: StorageLocation,
    source_offset: long,
    destination: StorageLocation,
    destination_offset: long,
    address_seed: long,
) {
    if payload_ty == TY_UNIT { return }
    let source_address = address_seed * 2L
    let destination_address = source_address + 1L
    let source_location = StorageLocation { origin: source.origin, anchor_kind: source.anchor_kind, anchor_node: source.anchor_node, byte_offset: source.byte_offset + source_offset, copies: source.copies, index: source.index, index_node: source.index_node, index_stride: source.index_stride }
    let destination_location = StorageLocation { origin: destination.origin, anchor_kind: destination.anchor_kind, anchor_node: destination.anchor_node, byte_offset: destination.byte_offset + destination_offset, copies: destination.copies, index: destination.index, index_node: destination.index_node, index_stride: destination.index_stride }
    emit_layout_address(compiler, ir, source_address, source_location)
    emit_layout_address(compiler, ir, destination_address, destination_location)
    if is_aggregate_type(compiler, payload_ty) {
        emit_aggregate_copy(compiler, ir, payload_ty, compiler_location(compiler, 2L, destination_address, 0L), compiler_location(compiler, 2L, source_address, 0L))
    } else {
        let storage_type: Ascii max 8 = if payload_ty == TY_BOOL { "i8" } else { llvm_type_name(payload_ty) }
        ir_write_ascii(compiler, ir, "  %sum.transfer.value."); ir_write_number(compiler, ir, address_seed)
        ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type)
        ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address)
        ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage_type)
        ir_write_ascii(compiler, ir, " %sum.transfer.value."); ir_write_number(compiler, ir, address_seed)
        ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, destination_address)
        ir_write_ascii(compiler, ir, ", align 1\n")
    }
}

fn emit_sum_payload_to_expression(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    payload_ty: long,
    source: StorageLocation,
    source_offset: long,
    address_seed: long,
) {
    if payload_ty == TY_UNIT { return }
    if is_aggregate_type(compiler, payload_ty) {
        emit_sum_payload_transfer(compiler, ir, payload_ty, source, source_offset, aggregate_destination_location(compiler, 0L, node), 0L, address_seed)
    } else {
        let source_address = address_seed * 2L
        let source_location = StorageLocation { origin: source.origin, anchor_kind: source.anchor_kind, anchor_node: source.anchor_node, byte_offset: source.byte_offset + source_offset, copies: source.copies, index: source.index, index_node: source.index_node, index_stride: source.index_stride }
        emit_layout_address(compiler, ir, source_address, source_location)
        if payload_ty == TY_BOOL {
            ir_write_ascii(compiler, ir, "  %sum.value.byte."); ir_write_number(compiler, ir, address_seed)
            ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, source_address)
            ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = trunc i8 %sum.value.byte."); ir_write_number(compiler, ir, address_seed); ir_write_ascii(compiler, ir, " to i1\n")
        } else {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(payload_ty))
            ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address)
            ir_write_ascii(compiler, ir, ", align 1\n")
        }
    }
}

fn emit_sum_payload_to_coalesce(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    payload_ty: long,
    source: StorageLocation,
    source_offset: long,
    address_seed: long,
) {
    if payload_ty == TY_UNIT { return }
    if is_aggregate_type(compiler, payload_ty) {
        emit_sum_payload_transfer(compiler, ir, payload_ty, source, source_offset, aggregate_destination_location(compiler, 0L, node), 0L, address_seed)
    } else {
        let source_address = address_seed * 2L
        let source_location = StorageLocation { origin: source.origin, anchor_kind: source.anchor_kind, anchor_node: source.anchor_node, byte_offset: source.byte_offset + source_offset, copies: source.copies, index: source.index, index_node: source.index_node, index_stride: source.index_stride }
        emit_layout_address(compiler, ir, source_address, source_location)
        if payload_ty == TY_BOOL {
            ir_write_ascii(compiler, ir, "  %coalesce.some.byte."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, source_address)
            ir_write_ascii(compiler, ir, ", align 1\n  %coalesce.some.value."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = trunc i8 %coalesce.some.byte."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " to i1\n  store i1 %coalesce.some.value."); ir_write_number(compiler, ir, node)
        } else {
            ir_write_ascii(compiler, ir, "  %coalesce.some.value."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(payload_ty))
            ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address)
            ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, llvm_type_name(payload_ty)); ir_push_byte(compiler, ir, 32)
            ir_write_ascii(compiler, ir, "%coalesce.some.value."); ir_write_number(compiler, ir, node)
        }
        ir_write_ascii(compiler, ir, ", ptr %coalesce.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    }
}

fn emit_option_result_method(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let receiver = compiler.child_first[node]
    let receiver_ty = compiler.facts[receiver].ty
    let receiver_kind = type_kind(compiler, receiver_ty)
    let receiver_source = aggregate_source_location_for_node(tables, compiler, receiver)
    let tag_address = enum_temporary_address(node, MAX_TREE_NODES + 5L)
    emit_layout_address(compiler, ir, tag_address, receiver_source)
    ir_write_ascii(compiler, ir, "  %method.tag."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address); ir_write_ascii(compiler, ir, ", align 1\n")
    let is_some = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "is_some")
    let is_none = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "is_none")
    let is_ok = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "is_ok")
    let is_err = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "is_err")
    let is_ok_method = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "ok")
    let is_unwrap = token_is_word_at(source, tokens, files, file_index, tables.nodes[node].token, "unwrap")
    if is_some || is_ok {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i32 %method.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
    } else if is_none || is_err {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i32 %method.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n")
    } else if is_unwrap {
        let failure_kind = if receiver_kind == TYPE_KIND_OPTION { 14L } else { 15L }
        let failure_position = position_for_offset(file_index, files[file_index].base + tables.nodes[receiver].start, compiler)
        ir_write_ascii(compiler, ir, "  %unwrap.is.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i32 %method.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n  br i1 %unwrap.is.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %unwrap.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %unwrap.success."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nunwrap.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 "); ir_write_number(compiler, ir, failure_kind); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, failure_position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, failure_position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\nunwrap.success."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        let payload = sum_payload_record(compiler, receiver_ty, 0L, 0L)
        emit_sum_payload_to_expression(compiler, ir, node, payload.ty, receiver_source, payload.offset, enum_temporary_address(node, MAX_TREE_NODES + 6L))
    } else if is_ok_method {
        let result_ty = compiler.facts[node].ty
        ir_write_ascii(compiler, ir, "  %method.is.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i32 %method.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n  br i1 %method.is.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %method.ok.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %method.ok.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmethod.ok.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_sum_tag_store(compiler, ir, node, 0L)
        let source_payload = sum_payload_record(compiler, receiver_ty, 0L, 0L)
        let destination_payload = sum_payload_record(compiler, result_ty, 0L, 0L)
        emit_sum_payload_transfer(compiler, ir, source_payload.ty, receiver_source, source_payload.offset, aggregate_destination_location(compiler, 0L, node), destination_payload.offset, enum_temporary_address(node, MAX_TREE_NODES + 7L))
        ir_write_ascii(compiler, ir, "  br label %method.ok.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmethod.ok.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_sum_tag_store(compiler, ir, node, 1L)
        ir_write_ascii(compiler, ir, "  br label %method.ok.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmethod.ok.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    } else { compiler.ir_overflow = true }
}

fn match_wildcard_ordinal(tables: ParseTables, compiler: CompilerTables, first_arm: long, first_ordinal: long, match_node: long) -> long {
    var scan = first_arm
    var ordinal = first_ordinal
    for step in 0L..tables.nodes[match_node].subtree {
        if scan < 0L { break }
        let pattern = compiler.child_first[scan]
        if pattern >= 0L && tables.nodes[pattern].kind == NodeKind.WildcardPattern { return ordinal }
        scan = compiler.child_next[scan]
        ordinal += 1L
    }
    -1L
}

fn optional_payload_location(base: StorageLocation, payload_offset: long) -> StorageLocation {
    storage_location_with_offset(base, payload_offset)
}

fn emit_optional_call_invoke(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let receiver = compiler.child_first[node]
    let target_id = compiler.facts[node].function
    if receiver < 0L || target_id < 0L { compiler.ir_overflow = true; return }
    let target = compiler.functions[target_id]
    let receiver_type = compiler.facts[receiver].ty
    let receiver_payload = sum_payload_record(compiler, receiver_type, 0L, 0L)
    let receiver_source_kind = aggregate_source_kind(tables, compiler, receiver)
    let receiver_source_node = aggregate_source_id(tables, compiler, receiver)
    let receiver_source = aggregate_source_location(compiler, receiver_source_kind, receiver_source_node)
    let receiver_parameter = compiler.parameters[target.param_start]
    let receiver_value = if is_aggregate_type(compiler, receiver_parameter.ty) {
        native_location(10L, node, 0L)
    } else {
        optional_payload_location(receiver_source, receiver_payload.offset)
    }
    let result_type = target.result_ty
    let wraps_result = type_kind(compiler, result_type) != TYPE_KIND_OPTION
    let aggregate_result = is_aggregate_type(compiler, result_type)
    var destination = aggregate_destination_location(compiler, 0L, node)
    if wraps_result {
        let output_payload = sum_payload_record(compiler, compiler.facts[node].ty, 0L, 0L)
        destination = optional_payload_location(destination, output_payload.offset)
    }
    emit_current_top_load(compiler, ir, node)
    let receiver_descriptor = MAX_TREE_NODES * 5L + node
    if aggregate_result { emit_prepare_location_descriptor(compiler, ir, destination, true, node) }
    if receiver_parameter.ty != TY_UNIT && is_aggregate_type(compiler, receiver_parameter.ty) {
        if parameter_uses_text_read_view(compiler, receiver_parameter) {
            prepare_text_parameter_descriptor(compiler, ir, receiver_payload.ty, receiver_value, node)
        } else {
            emit_prepare_location_descriptor(compiler, ir, receiver_value, true, receiver_descriptor)
        }
    } else { () }
    var argument = compiler.child_next[receiver]
    for argument_index in 1L..target.param_count {
        let parameter = compiler.parameters[target.param_start + argument_index]
        if argument < 0L { compiler.ir_overflow = true; return }
        if parameter.ty != TY_UNIT && is_aggregate_type(compiler, parameter.ty) {
            let use_snapshot = direct_call_argument_needs_snapshot(tables, compiler, node, argument)
            let argument_location = if use_snapshot { aggregate_destination_location(compiler, 0L, argument) }
                else { aggregate_source_location_for_node(tables, compiler, argument) }
            if parameter_uses_text_read_view(compiler, parameter) {
                let argument_type = compiler.facts[argument].ty
                prepare_text_parameter_descriptor(compiler, ir, argument_type, argument_location, argument)
            } else {
                emit_prepare_location_descriptor(compiler, ir, argument_location, true, argument)
            }
        }
        argument = compiler.child_next[argument]
    }
    ir_write_ascii(compiler, ir, "  ")
    if !aggregate_result && result_type != TY_UNIT && result_type != TY_NEVER {
        ir_write_ascii(compiler, ir, "%optional.call.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = ")
    }
    ir_write_ascii(compiler, ir, "call ")
    if aggregate_result || result_type == TY_UNIT || result_type == TY_NEVER { ir_write_ascii(compiler, ir, "void") }
    else { ir_write_ascii(compiler, ir, llvm_type_name(result_type)) }
    ir_write_ascii(compiler, ir, " @nl_fn_"); ir_write_number(compiler, ir, target_id); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 "); emit_current_top_reference(compiler, ir, node)
    if aggregate_result {
        ir_write_ascii(compiler, ir, ", ")
        emit_hidden_destination_argument(compiler, ir, destination)
    }
    if receiver_parameter.ty != TY_UNIT {
        ir_write_ascii(compiler, ir, ", ")
        if is_aggregate_type(compiler, receiver_parameter.ty) {
            if parameter_uses_text_read_view(compiler, receiver_parameter) {
                emit_text_parameter_descriptor(compiler, ir, receiver_payload.ty, receiver_value, node)
            } else {
                emit_location_descriptor_argument(compiler, ir, receiver_value, true, receiver_descriptor)
            }
        } else {
            ir_write_ascii(compiler, ir, llvm_type_name(receiver_parameter.ty)); ir_write_ascii(compiler, ir, " %optional.call.receiver."); ir_write_number(compiler, ir, node)
        }
    }
    argument = compiler.child_next[receiver]
    for argument_index in 1L..target.param_count {
        let parameter = compiler.parameters[target.param_start + argument_index]
        if argument < 0L { compiler.ir_overflow = true; return }
        if parameter.ty != TY_UNIT {
            ir_write_ascii(compiler, ir, ", ")
            if is_aggregate_type(compiler, parameter.ty) {
                let use_snapshot = direct_call_argument_needs_snapshot(tables, compiler, node, argument)
                let argument_location = if use_snapshot { aggregate_destination_location(compiler, 0L, argument) }
                    else { aggregate_source_location_for_node(tables, compiler, argument) }
                if parameter_uses_text_read_view(compiler, parameter) {
                    let argument_type = compiler.facts[argument].ty
                    emit_text_parameter_descriptor(compiler, ir, argument_type, argument_location, argument)
                } else {
                    emit_location_descriptor_argument(compiler, ir, argument_location, true, argument)
                }
            } else {
                ir_write_ascii(compiler, ir, llvm_type_name(parameter.ty)); ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, argument)
            }
        }
        argument = compiler.child_next[argument]
    }
    ir_write_ascii(compiler, ir, ")\n")
    if result_type == TY_NEVER { ir_write_ascii(compiler, ir, "  unreachable\n"); return }
    if wraps_result {
        if aggregate_result || result_type == TY_UNIT {
            emit_sum_tag_store(compiler, ir, node, 0L)
        } else {
            let address = enum_temporary_address(node, MAX_TREE_NODES * 80L + 2L)
            emit_layout_address(compiler, ir, address, destination)
            if result_type == TY_BOOL {
                ir_write_ascii(compiler, ir, "  %optional.call.bool."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i1 %optional.call.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i8\n  store i8 %optional.call.bool."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n")
            } else {
                ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(result_type)); ir_write_ascii(compiler, ir, " %optional.call.result."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n")
            }
            emit_sum_tag_store(compiler, ir, node, 0L)
        }
    }
}

fn emit_optional_call_start(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) -> bool {
    let receiver = compiler.child_first[node]
    let receiver_type = compiler.facts[receiver].ty
    let receiver_payload = sum_payload_record(compiler, receiver_type, 0L, 0L)
    let receiver_source = aggregate_source_location_for_node(tables, compiler, receiver)
    let tag_address = enum_temporary_address(node, MAX_TREE_NODES * 80L + 3L)
    emit_layout_address(compiler, ir, tag_address, receiver_source)
    ir_write_ascii(compiler, ir, "  %optional.call.tag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address)
    ir_write_ascii(compiler, ir, ", align 1\n  %optional.call.present."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq i32 %optional.call.tag."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", 0\n  br i1 %optional.call.present."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %optional.call.some."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %optional.call.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\noptional.call.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    emit_sum_tag_store(compiler, ir, node, 1L)
    ir_write_ascii(compiler, ir, "  br label %optional.call.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\noptional.call.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if compiler.facts[node].literal == -2L {
        let source_payload = optional_payload_location(receiver_source, receiver_payload.offset)
        let source_address = enum_temporary_address(node, MAX_TREE_NODES * 80L + 4L)
        emit_layout_address(compiler, ir, source_address, source_payload)
        ir_write_ascii(compiler, ir, "  %optional.call.int."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n  %optional.call.long."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sext i32 %optional.call.int."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i64\n")
        let output_payload = sum_payload_record(compiler, compiler.facts[node].ty, 0L, 0L)
        let output_address = enum_temporary_address(node, MAX_TREE_NODES * 80L + 5L)
        emit_layout_address(compiler, ir, output_address, optional_payload_location(aggregate_destination_location(compiler, 0L, node), output_payload.offset))
        ir_write_ascii(compiler, ir, "  store i64 %optional.call.long."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, output_address); ir_write_ascii(compiler, ir, ", align 1\n")
        emit_sum_tag_store(compiler, ir, node, 0L)
        ir_write_ascii(compiler, ir, "  br label %optional.call.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\noptional.call.end."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        true
    } else {
        let target_id = compiler.facts[node].function
        if target_id >= 0L {
            let target = compiler.functions[target_id]
            let receiver_parameter = compiler.parameters[target.param_start]
            if receiver_parameter.ty != TY_UNIT {
                let payload_receiver_source = aggregate_source_location_for_node(tables, compiler, receiver)
                let source_payload = optional_payload_location(payload_receiver_source, receiver_payload.offset)
                if is_aggregate_type(compiler, receiver_parameter.ty) {
                    let receiver_storage_ty = if parameter_uses_text_read_view(compiler, receiver_parameter) { receiver_payload.ty }
                        else { receiver_parameter.ty }
                    emit_aggregate_copy(compiler, ir, receiver_storage_ty, native_location(10L, node, 0L), source_payload)
                } else {
                    let source_address = enum_temporary_address(node, MAX_TREE_NODES * 80L + 6L)
                    emit_layout_address(compiler, ir, source_address, source_payload)
                    if receiver_parameter.ty == TY_BOOL {
                        ir_write_ascii(compiler, ir, "  %optional.call.receiver.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n  %optional.call.receiver."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = trunc i8 %optional.call.receiver.byte."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i1\n")
                    } else {
                        ir_write_ascii(compiler, ir, "  %optional.call.receiver."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(receiver_parameter.ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n")
                    }
                }
            }
        }
        false
    }
}



// E3a1 begin: shared compiler integration.
recursive fn emit_expr_linear(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    return_ty: long,
    is_test: bool,
) {
    let base_depth = compiler.expr_work.count()
    compiler.expr_work.push(EmitExprFrame { node, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
    for emit_step in 0L..MAX_PARSE_WORK {
        if compiler.expr_work.count() <= base_depth { break }
        let frame_index = compiler.expr_work.count() - 1L
        var frame = compiler.expr_work[frame_index]
        let current = frame.node
        let syntax = tables.nodes[current]
        let kind = syntax.kind
        if frame.phase == 0L {
            if kind == NodeKind.Integer || kind == NodeKind.Bool {
                let ty = compiler.facts[current].ty
                let literal = compiler.facts[current].literal
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = add "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " 0, "); ir_write_number(compiler, ir, literal); ir_write_ascii(compiler, ir, "\n")
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Name {
                let ty = compiler.facts[current].ty
                let binding = compiler.facts[current].binding
                let case_tag = compiler.facts[current].literal
                if (compiler.facts[current].flags & FACT_CONSTANT_VALUE) != 0L {
                    ()
                } else if is_sum_type(compiler, ty) && binding < 0L {
                    if type_kind(compiler, ty) == TYPE_KIND_ENUM { emit_enum_tag_store(compiler, ir, current, case_tag) }
                    else { emit_sum_tag_store(compiler, ir, current, case_tag) }
                } else if binding_is_view(compiler, binding) {
                    if !is_aggregate_type(compiler, ty) && ty != TY_UNIT {
                        let _ = emit_collection_view_name_address(tables, compiler, ir, current)
                        let view_loop = compiler.bindings[binding].node
                        let view_collection = compiler.child_first[view_loop]
                        let view_kind = type_kind(compiler, compiler.facts[view_collection].ty)
                        if ty == TY_BYTE && (view_kind == TYPE_KIND_ASCII || view_kind == TYPE_KIND_BYTES) {
                            ir_write_ascii(compiler, ir, "  %text.view.byte."); ir_write_number(compiler, ir, current)
                            ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, current)
                            ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, current)
                            ir_write_ascii(compiler, ir, " = zext i8 %text.view.byte."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " to i32\n")
                        } else { emit_load_scalar(compiler, ir, current, ty) }
                    } else if is_aggregate_type(compiler, ty) { emit_collection_gather_view_value(tables, compiler, ir, current) }
                    else { () }
                } else if ty == TY_UNIT { () }
                else if is_aggregate_type(compiler, ty) {
                    if compiler.emit_destination_node == current {
                        let source_kind = if compiler.bindings[binding].parameter { 2L } else { 1L }
                        emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 0L, current), aggregate_source_location(compiler, source_kind, binding))
                    } else { () }
                }
                else if binding_is_write_parameter(compiler, binding) {
                    emit_layout_address(compiler, ir, current, compiler_location(compiler, 3L, binding, 0L))
                    emit_load_scalar(compiler, ir, current, ty)
                }
                else if ty == TY_BOOL { ir_write_ascii(compiler, ir, "  %bool.load."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load i8, ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = trunc i8 %bool.load."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " to i1\n") }
                else { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Field {
                if is_enum_case_field(tables, compiler, current) {
                    let case_tag = compiler.facts[current].literal
                    emit_enum_tag_store(compiler, ir, current, case_tag)
                    match compiler.expr_work.pop() { some(_) => (), none => () }
                } else {
                    frame.child0 = compiler.child_first[current]
                    frame.phase = 1L
                    compiler.expr_work[frame_index] = frame
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.StructInit {
                frame.cursor = compiler.child_first[current]
                frame.phase = 50L
                compiler.expr_work[frame_index] = frame
            } else if kind == NodeKind.ArrayLiteral {
                frame.cursor = compiler.child_first[current]
                frame.auxiliary = 0L
                frame.child2 = -1L
                if type_kind(compiler, compiler.facts[current].ty) == TYPE_KIND_BYTES {
                    let destination = aggregate_destination_location(compiler, 0L, current)
                    frame.child2 = emit_location_pointer_materialization(compiler, ir, destination)
                    ir_write_ascii(compiler, ir, "  %text.bytes.literal.length.addr."); ir_write_number(compiler, ir, current)
                    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, frame.child2)
                    ir_write_ascii(compiler, ir, ", i64 0\n  store i64 "); ir_write_number(compiler, ir, count_children(tables, compiler, current))
                    ir_write_ascii(compiler, ir, ", ptr %text.bytes.literal.length.addr."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 10)
                }
                frame.phase = 72L
                compiler.expr_work[frame_index] = frame
            } else if kind == NodeKind.ListLiteral {
                let list_type = compiler.facts[current].ty
                emit_collection_zero_storage(compiler, ir, current, list_type, 0L)
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Index {
                frame.child0 = compiler.child_first[current]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.phase = 70L
                compiler.expr_work[frame_index] = frame
                if frame.child0 >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.ByteString || kind == NodeKind.BytesLiteral {
                emit_text_literal_value(source, files, tokens, tables, compiler, ir, current, file_index, is_test || compiler.test_build)
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Unary {
                frame.child0 = compiler.child_first[current]
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Binary {
                frame.child0 = compiler.child_first[current]
                frame.child1 = compiler.child_next[frame.child0]
                frame.phase = if syntax.flags == 21L { 40L } else { 1L }
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Call && (syntax.flags & FLAG_SYNTHETIC) != 0L {
                let ty = compiler.facts[current].ty
                if type_kind(compiler, ty) == TYPE_KIND_ARRAY || type_kind(compiler, ty) == TYPE_KIND_LIST {
                    emit_collection_zero_storage(compiler, ir, current, ty, 0L)
                } else if ty == TY_UNIT || ty == TY_NEVER { () }
                else { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = add "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " 0, 0\n") }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Call || kind == NodeKind.QualifiedCase {
                let is_constructor = compiler.facts[current].function < 0L && is_sum_type(compiler, compiler.facts[current].ty)
                frame.cursor = compiler.child_first[current]
                frame.phase = if is_constructor { 60L } else { 1L }
                frame.auxiliary = 0L
                compiler.expr_work[frame_index] = frame
            } else if kind == NodeKind.MethodCall {
                let receiver = compiler.child_first[current]
                let is_sys = is_core_sys_receiver(source, tokens, files, tables, compiler, current, file_index)
                let is_text_empty = compiler.facts[current].literal == TEXT_METHOD_EMPTY
                frame.child0 = receiver
                frame.cursor = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                if !is_sys && !is_text_empty && receiver >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: receiver, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.OptionalCall {
                let receiver = compiler.child_first[current]
                frame.child0 = receiver
                frame.phase = 90L
                compiler.expr_work[frame_index] = frame
                if receiver >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: receiver, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.Try {
                frame.child0 = compiler.child_first[current]
                frame.phase = 18L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Fit {
                frame.child0 = compiler.child_first[current]
                frame.phase = 2L
                compiler.expr_work[frame_index] = frame
                if frame.child0 >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.Cast {
                let type_node = compiler.child_first[current]
                frame.child0 = if type_node >= 0L { compiler.child_next[type_node] } else { -1L }
                frame.child1 = type_node
                frame.auxiliary = compiler.facts[current].ty
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                if frame.child0 >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.ToLong {
                frame.child0 = compiler.child_first[current]
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                if frame.child0 >= 0L {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else if kind == NodeKind.If {
                frame.child0 = compiler.child_first[current]
                frame.child1 = compiler.child_next[frame.child0]
                frame.child2 = compiler.child_next[frame.child1]
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Match {
                frame.child0 = compiler.child_first[current]
                frame.cursor = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.auxiliary = 0L
                frame.phase = 30L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Block {
                // E3a1 subsection
                emit_region_scope_enter(files, tables, compiler, ir, current, file_index)
                // E3a1 subsection end
                frame.cursor = compiler.child_first[current]
                frame.child0 = node_last_child(tables, compiler, current)
                frame.phase = 10L
                compiler.expr_work[frame_index] = frame
            } else if kind == NodeKind.Return {
                frame.child0 = compiler.child_first[current]
                if frame.child0 >= 0L {
                    frame.phase = 17L
                    compiler.expr_work[frame_index] = frame
                    compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                } else {
                    if is_test { lower_scope_exit(compiler, ir, -1L, EXIT_TEST_FAILURE, 0L, 0L, TY_UNIT, -1L) }
                    else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, TY_UNIT, -1L) }
                    match compiler.expr_work.pop() { some(_) => (), none => () }
                }
            } else if kind == NodeKind.LoopExit {
                let is_break = (syntax.flags & FLAG_VALUE) != 0L
                let loop = compiler.emit_loops[compiler.emit_loops.count() - 1L]
                // E3a1 subsection
                emit_region_loop_exit(tables, compiler, ir, loop.body, current)
                // E3a1 subsection end
                let target_kind = if tables.nodes[loop.node].kind == NodeKind.While { 1L } else { 0L }
                if is_break { lower_scope_exit(compiler, ir, -1L, EXIT_BREAK, target_kind, loop.node, TY_UNIT, -1L) }
                else { lower_scope_exit(compiler, ir, -1L, EXIT_CONTINUE, target_kind, loop.node, TY_UNIT, -1L) }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.Field && frame.phase == 1L {
            if compiler.c_runtime && compiler.facts[frame.child0].ty == TY_ENV {
                emit_c_runtime_environment_field(compiler, ir, current)
            } else {
                emit_aggregate_address(tables, compiler, ir, current)
                let ty = compiler.facts[current].ty
                if is_aggregate_type(compiler, ty) {
                    if compiler.emit_destination_node == current {
                        emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 0L, current), aggregate_source_location(compiler, 3L, current))
                    } else { () }
                } else if ty != TY_UNIT { emit_load_scalar(compiler, ir, current, ty) }
                else { () }
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Index && frame.phase == 70L {
            if frame.child0 >= 0L && (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if frame.child1 >= 0L {
                frame.phase = 71L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child1, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                compiler.ir_overflow = true
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.Index && frame.phase == 71L {
            if (compiler.facts[frame.child1].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else {
                emit_collection_index_address(files, tables, compiler, ir, current, file_index)
                let ty = compiler.facts[current].ty
                if is_aggregate_type(compiler, ty) { emit_collection_gather_index_value(tables, compiler, ir, current) }
                else if ty == TY_BYTE && (type_kind(compiler, compiler.facts[frame.child0].ty) == TYPE_KIND_BYTES || type_kind(compiler, compiler.facts[frame.child0].ty) == TYPE_KIND_ASCII) {
                    ir_write_ascii(compiler, ir, "  %text.index.byte."); ir_write_number(compiler, ir, current)
                    ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, current)
                    ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, current)
                    ir_write_ascii(compiler, ir, " = zext i8 %text.index.byte."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " to i32\n")
                }
                else if ty != TY_UNIT { emit_load_scalar(compiler, ir, current, ty) }
                else { () }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.ArrayLiteral && frame.phase == 72L {
            if frame.cursor >= 0L {
                let element = frame.cursor
                frame.cursor = compiler.child_next[element]
                if type_kind(compiler, compiler.facts[current].ty) == TYPE_KIND_BYTES &&
                    text_expression_may_call(tables, compiler, element) { frame.child2 = -1L }
                frame.child0 = element
                frame.phase = 73L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: element, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                let ty = compiler.facts[current].ty
                if type_kind(compiler, ty) == TYPE_KIND_LIST { emit_collection_zero_storage(compiler, ir, current, ty, frame.auxiliary) }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.ArrayLiteral && frame.phase == 73L {
            let element = frame.child0
            if (compiler.facts[element].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else {
                let collection_type = compiler.facts[current].ty
                if type_kind(compiler, collection_type) == TYPE_KIND_BYTES {
                    frame.child2 = emit_text_bytes_literal_element(compiler, ir, current, frame.auxiliary, element, frame.child2)
                } else {
                    emit_collection_literal_element(tables, compiler, ir, current, collection_type, frame.auxiliary, element)
                }
                frame.auxiliary += 1L
                frame.phase = 72L
                compiler.expr_work[frame_index] = frame
            }
        } else if kind == NodeKind.StructInit && frame.phase == 50L {
            let initializer = frame.cursor
            if initializer >= 0L {
                let value = compiler.child_first[initializer]
                frame.child0 = initializer
                frame.child1 = value
                frame.cursor = compiler.child_next[initializer]
                frame.phase = 51L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: value, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                let type_index = compiler.facts[current].literal
                let type_id = struct_type_id(compiler, type_index)
                if struct_has_defaults(compiler, type_index) {
                    let ty = struct_record(compiler, type_index)
                    var item_count = 0L
                    for field_offset in 0L..ty.field_count {
                        let field_index = ty.field_start + field_offset
                        var child = compiler.child_first[current]
                        for field_step in 0L..tables.nodes[current].subtree {
                            if child < 0L { break }
                            if compiler.facts[child].binding == field_index { item_count += 1L }
                            child = compiler.child_next[child]
                        }
                    }
                    // E3a1 subsection: materialize the current top after arguments.
                    emit_current_top_load(compiler, ir, current)
                    ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_FILL); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 "); emit_current_top_reference(compiler, ir, current); ir_write_ascii(compiler, ir, ", "); emit_location_descriptor_argument(compiler, ir, aggregate_destination_location(compiler, 0L, current), true, current); ir_write_ascii(compiler, ir, ", ptr @.nl.given."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, item_count); ir_write_ascii(compiler, ir, ")\n")
                    // E3a1 subsection end
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.StructInit && frame.phase == 51L {
            let initializer = frame.child0
            let value = frame.child1
            if (compiler.facts[value].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else {
                let field_index = compiler.facts[initializer].binding
                let field = compiler.struct_fields[field_index]
                // E3a1 subsection: region-backed aggregate destinations reload the base at use.
                let destination = aggregate_destination_location(compiler, 0L, current)
                emit_layout_address(compiler, ir, initializer, StorageLocation { origin: destination.origin, anchor_kind: destination.anchor_kind, anchor_node: destination.anchor_node, byte_offset: destination.byte_offset + field.offset, copies: destination.copies, index: destination.index, index_node: destination.index_node, index_stride: destination.index_stride })
                // E3a1 subsection end
                if is_aggregate_type(compiler, field.ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, value)
                    let source_node = aggregate_source_id(tables, compiler, value)
                    emit_aggregate_copy(compiler, ir, field.ty, aggregate_destination_location(compiler, 3L, initializer), aggregate_source_location(compiler, source_kind, source_node))
                } else if field.ty != TY_UNIT {
                    emit_store_scalar(compiler, ir, initializer, field.ty, value)
                } else { () }
                frame.phase = 50L
                compiler.expr_work[frame_index] = frame
            }
        } else if kind == NodeKind.Unary {
            let ty = compiler.facts[current].ty
            if syntax.flags == 1L {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = xor i1 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", true\n")
            } else if syntax.flags == 2L {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = xor "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", -1\n")
            } else {
                ir_write_ascii(compiler, ir, "  %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = call { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } @llvm.ssub.with.overflow."); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " 0, "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ")\n")
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 0\n  %ov.flag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 1\n")
                let failure_kind = if ty == TY_INT { 4L } else { 8L }
                emit_runtime_failure(files, tables, compiler, ir, current, file_index, failure_kind)
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Fit && frame.phase == 2L {
            let target_ty = sum_payload_record(compiler, compiler.facts[current].ty, 0L, 0L).ty
            if target_ty == TY_BYTE { emit_byte_fit(compiler, ir, current) }
            else { emit_ascii_fit(tables, compiler, ir, current) }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Cast && frame.phase == 1L {
            let source_ty = compiler.facts[frame.child0].ty
            let target_ty = frame.auxiliary
            if type_kind(compiler, target_ty) == TYPE_KIND_ASCII {
                emit_ascii_cast(files, tables, compiler, ir, current, file_index, frame.child0, target_ty)
            } else if source_ty == target_ty {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = add "); ir_write_ascii(compiler, ir, llvm_type_name(target_ty)); ir_write_ascii(compiler, ir, " 0, "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, "\n")
            } else if source_ty == TY_INT && target_ty == TY_LONG {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = sext i32 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i64\n")
            } else if source_ty == TY_BYTE && target_ty == TY_INT {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = add i32 0, "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, "\n")
            } else if target_ty == TY_BYTE {
                if (syntax.flags & FLAG_CAST_UNCHECKED) != 0L {
                    if source_ty == TY_LONG {
                        ir_write_ascii(compiler, ir, "  %cast.low8."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = and i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 255\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = trunc i64 %cast.low8."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " to i32\n")
                    } else {
                        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = and i32 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 255\n")
                    }
                } else {
                    let width: Ascii max 4 = if source_ty == TY_LONG { "i64" } else { "i32" }
                    ir_write_ascii(compiler, ir, "  %cast.low."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = icmp sge "); ir_write_ascii(compiler, ir, width); ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 0\n  %cast.high."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = icmp sle "); ir_write_ascii(compiler, ir, width); ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 255\n  %cast.ok."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = and i1 %cast.low."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", %cast.high."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\n  br i1 %cast.ok."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %cast.good."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %cast.fail."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\ncast.fail."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 10, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + syntax.start, compiler).line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + syntax.start, compiler).col); ir_write_ascii(compiler, ir, ")\n  unreachable\ncast.good."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = "); if source_ty == TY_LONG { ir_write_ascii(compiler, ir, "trunc i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i32\n") } else { ir_write_ascii(compiler, ir, "add i32 0, "); ir_write_value_ref(compiler, ir, frame.child0); ir_push_byte(compiler, ir, 10) }
                }
            } else if target_ty == TY_LONG && (source_ty == TY_BYTE || source_ty == TY_INT) {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = sext i32 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i64\n")
            } else {
                ir_write_ascii(compiler, ir, "  %cast.low."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = icmp sge i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", -2147483648\n  %cast.high."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = icmp sle i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 2147483647\n  %cast.ok."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = and i1 %cast.low."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", %cast.high."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\n  br i1 %cast.ok."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %cast.good."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %cast.fail."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\ncast.fail."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 10, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + syntax.start, compiler).line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + syntax.start, compiler).col); ir_write_ascii(compiler, ir, ")\n  unreachable\ncast.good."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = trunc i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i32\n")
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.ToLong && frame.phase == 1L {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = sext i32 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i64\n")
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Return && frame.phase == 17L {
            if is_aggregate_type(compiler, return_ty) {
                let source_kind = aggregate_source_kind(tables, compiler, frame.child0)
                let source_node = aggregate_source_id(tables, compiler, frame.child0)
                emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(compiler, 2L, 0L), aggregate_source_location(compiler, source_kind, source_node))
                lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L)
            } else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN_VALUE, 0L, 0L, return_ty, frame.child0) }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Try && frame.phase == 18L {
            let operand = frame.child0
            let operand_ty = compiler.facts[operand].ty
            let operand_kind = type_kind(compiler, operand_ty)
            let operand_source = aggregate_source_location_for_node(tables, compiler, operand)
            let tag_address = enum_temporary_address(current, MAX_TREE_NODES + 8L)
            emit_layout_address(compiler, ir, tag_address, operand_source)
            ir_write_ascii(compiler, ir, "  %try.tag."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address)
            ir_write_ascii(compiler, ir, ", align 1\n  %try.is.success."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, " = icmp eq i32 %try.tag."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", 0\n  br i1 %try.is.success."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", label %try.success."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", label %try.failure."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, "\ntry.success."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            let success = sum_payload_record(compiler, operand_ty, 0L, 0L)
            emit_sum_payload_to_expression(compiler, ir, current, success.ty, operand_source, success.offset, enum_temporary_address(current, MAX_TREE_NODES + 9L))
            ir_write_ascii(compiler, ir, "  br label %try.end."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, "\ntry.failure."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            let result_ty = return_ty
            let result_kind = type_kind(compiler, result_ty)
            let result_destination = if compiler.core_mode { compiler_location(compiler, 4L, 0L, 0L) } else { aggregate_destination_location(compiler, 2L, 0L) }
            let result_tag_address = enum_temporary_address(current, MAX_TREE_NODES + 10L)
            emit_layout_address(compiler, ir, result_tag_address, result_destination)
            ir_write_ascii(compiler, ir, "  %try.result.tag."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, " = add i32 0, 1\n  store i32 %try.result.tag."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, result_tag_address); ir_write_ascii(compiler, ir, ", align 1\n")
            if operand_kind == TYPE_KIND_RESULT && result_kind == TYPE_KIND_RESULT {
                let error = sum_payload_record(compiler, operand_ty, 1L, 0L)
                let destination_error = sum_payload_record(compiler, result_ty, 1L, 0L)
                emit_sum_payload_transfer(compiler, ir, error.ty, operand_source, error.offset, result_destination, destination_error.offset, enum_temporary_address(current, MAX_TREE_NODES + 11L))
            }
            lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, result_ty, -1L)
            ir_write_ascii(compiler, ir, "try.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Binary && frame.phase == 40L {
            let left = frame.child0
            let option_ty = compiler.facts[left].ty
            let left_source = aggregate_source_location_for_node(tables, compiler, left)
            let tag_address = enum_temporary_address(current, MAX_TREE_NODES + 2L)
            emit_layout_address(compiler, ir, tag_address, left_source)
            ir_write_ascii(compiler, ir, "  %coalesce.tag."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address)
            ir_write_ascii(compiler, ir, ", align 1\n  %coalesce.is.some."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, " = icmp eq i32 %coalesce.tag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 0\n  br i1 %coalesce.is.some."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", label %coalesce.some."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, ", label %coalesce.none."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, "\ncoalesce.some."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            let payload = sum_payload_record(compiler, option_ty, 0L, 0L)
            emit_sum_payload_to_coalesce(compiler, ir, current, payload.ty, left_source, payload.offset, enum_temporary_address(current, MAX_TREE_NODES + 3L))
            ir_write_ascii(compiler, ir, "  br label %coalesce.end."); ir_write_number(compiler, ir, current)
            ir_write_ascii(compiler, ir, "\ncoalesce.none."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            frame.phase = 41L
            compiler.expr_work[frame_index] = frame
            compiler.expr_work.push(EmitExprFrame { node: frame.child1, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
        } else if kind == NodeKind.Binary && frame.phase == 41L {
            let result_ty = compiler.facts[current].ty
            let fallback = frame.child1
            if compiler.facts[fallback].ty != TY_NEVER {
                if is_aggregate_type(compiler, result_ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, fallback)
                    let source_node = aggregate_source_id(tables, compiler, fallback)
                    emit_aggregate_copy(compiler, ir, result_ty, aggregate_destination_location(compiler, 0L, current), aggregate_source_location(compiler, source_kind, source_node))
                } else if result_ty != TY_UNIT {
                    ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty)); ir_push_byte(compiler, ir, 32)
                    ir_write_value_ref(compiler, ir, fallback); ir_write_ascii(compiler, ir, ", ptr %coalesce.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n")
                } else { () }
                ir_write_ascii(compiler, ir, "  br label %coalesce.end."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 10)
            }
            ir_write_ascii(compiler, ir, "coalesce.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            if result_ty != TY_UNIT && !is_aggregate_type(compiler, result_ty) {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty))
                ir_write_ascii(compiler, ir, ", ptr %coalesce.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n")
            }
            match compiler.expr_work.pop() { some(_) => (), none() => () }
        } else if kind == NodeKind.Binary && frame.phase == 1L {
            let op = syntax.flags
            if op == 14L || op == 15L {
                ir_write_ascii(compiler, ir, "  br i1 "); ir_write_value_ref(compiler, ir, frame.child0)
                if op == 14L {
                    ir_write_ascii(compiler, ir, ", label %logic.rhs."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %logic.short."); ir_write_number(compiler, ir, current)
                } else {
                    ir_write_ascii(compiler, ir, ", label %logic.short."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %logic.rhs."); ir_write_number(compiler, ir, current)
                }
                ir_write_ascii(compiler, ir, "\nlogic.short."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  store i1 ")
                if op == 14L { ir_write_ascii(compiler, ir, "false") } else { ir_write_ascii(compiler, ir, "true") }
                ir_write_ascii(compiler, ir, ", ptr %logic.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n  br label %logic.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\nlogic.rhs."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            }
            let comparison_snapshot = op >= 8L && op <= 13L &&
                is_aggregate_type(compiler, compiler.facts[frame.child0].ty) &&
                (tables.nodes[frame.child0].kind == NodeKind.Name || tables.nodes[frame.child0].kind == NodeKind.Field) &&
                (!is_text_comparable(compiler, compiler.facts[frame.child0].ty, compiler.facts[frame.child1].ty) ||
                    region_subtree_has_effect(tables, frame.child1, frame.child1))
            if comparison_snapshot || text_concat_left_needs_snapshot(tables, compiler, current) {
                let ty = compiler.facts[frame.child0].ty
                let source_kind = aggregate_source_kind(tables, compiler, frame.child0)
                let source_node = aggregate_source_id(tables, compiler, frame.child0)
                emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 0L, frame.child0), aggregate_source_location(compiler, source_kind, source_node))
            }
            frame.phase = 2L
            compiler.expr_work[frame_index] = frame
            compiler.expr_work.push(EmitExprFrame { node: frame.child1, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
        } else if kind == NodeKind.Binary && frame.phase == 2L {
            let left = frame.child0
            let right = frame.child1
            let op = syntax.flags
            if op == 14L || op == 15L {
                ir_write_ascii(compiler, ir, "  store i1 "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", ptr %logic.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n  br label %logic.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\nlogic.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load i1, ptr %logic.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n")
            } else if op >= 8L && op <= 13L && is_text_comparable(compiler, compiler.facts[left].ty, compiler.facts[right].ty) {
                emit_text_compare(tables, compiler, ir, current, op)
            } else if (op == 8L || op == 9L) && is_aggregate_type(compiler, compiler.facts[left].ty) {
                let ty = compiler.facts[left].ty
                let left_location = if tables.nodes[left].kind == NodeKind.Name || tables.nodes[left].kind == NodeKind.Field { compiler_location(compiler, 0L, left, 0L) }
                    else { aggregate_source_location_for_node(tables, compiler, left) }
                let right_location = aggregate_source_location_for_node(tables, compiler, right)
                let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
                let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
                ir_write_ascii(compiler, ir, "  %eq.value."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = call i1 ")
                emit_type_helper_call_two(compiler, ir, ty, HELPER_EQUAL, left_location, right_location, left_pointer, right_pointer)
                ir_push_byte(compiler, ir, 10)
                if op == 8L {
                    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = select i1 true, i1 %eq.value."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", i1 false\n")
                } else {
                    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = xor i1 %eq.value."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", true\n")
                }
            } else if op == 0L && is_text_concatenation(compiler, compiler.facts[left].ty, compiler.facts[right].ty) {
                emit_text_concat(tables, compiler, ir, current, is_test || compiler.test_build)
            } else if op == 0L || op == 1L || op == 2L {
                let ty = compiler.facts[left].ty
                let failure_kind = if ty == TY_INT { op + 1L } else { op + 5L }
                ir_write_ascii(compiler, ir, "  %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = call { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } @llvm.s")
                if op == 0L { ir_write_ascii(compiler, ir, "add") } else if op == 1L { ir_write_ascii(compiler, ir, "sub") } else { ir_write_ascii(compiler, ir, "mul") }
                ir_write_ascii(compiler, ir, ".with.overflow."); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ")\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 0\n  %ov.flag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 1\n")
                emit_runtime_failure(files, tables, compiler, ir, current, file_index, failure_kind)
            } else if op == 3L || op == 4L {
                let ty = compiler.facts[left].ty
                emit_checked_division(files, tables, compiler, ir, current, file_index, left, right, ty, op == 4L)
            } else if op == 19L || op == 20L {
                let ty = compiler.facts[left].ty
                emit_checked_shift(files, tables, compiler, ir, current, file_index, left, right, ty, op == 19L)
            } else if op == 16L || op == 17L || op == 18L {
                let ty = compiler.facts[left].ty
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = ")
                if op == 16L { ir_write_ascii(compiler, ir, "and ") }
                else if op == 17L { ir_write_ascii(compiler, ir, "or ") }
                else { ir_write_ascii(compiler, ir, "xor ") }
                ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_push_byte(compiler, ir, 10)
            } else {
                let operand_ty = compiler.facts[left].ty
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = ")
                if op == 0L { ir_write_ascii(compiler, ir, "add ") }
                else if op == 1L { ir_write_ascii(compiler, ir, "sub ") }
                else if op == 2L { ir_write_ascii(compiler, ir, "mul ") }
                else if op == 3L { ir_write_ascii(compiler, ir, "sdiv ") }
                else if op == 4L { ir_write_ascii(compiler, ir, "srem ") }
                else if op == 8L { ir_write_ascii(compiler, ir, "icmp eq ") }
                else if op == 9L { ir_write_ascii(compiler, ir, "icmp ne ") }
                else if op == 10L { ir_write_ascii(compiler, ir, "icmp slt ") }
                else if op == 11L { ir_write_ascii(compiler, ir, "icmp sle ") }
                else if op == 12L { ir_write_ascii(compiler, ir, "icmp sgt ") }
                else { ir_write_ascii(compiler, ir, "icmp sge ") }
                ir_write_ascii(compiler, ir, llvm_type_name(operand_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, "\n")
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if (kind == NodeKind.Call || kind == NodeKind.QualifiedCase) && (frame.phase == 60L || frame.phase == 61L) {
            let is_generic_sum = type_kind(compiler, compiler.facts[current].ty) == TYPE_KIND_OPTION || type_kind(compiler, compiler.facts[current].ty) == TYPE_KIND_RESULT
            let case_index = enum_case_for_tag(compiler, compiler.facts[current].ty, compiler.facts[current].literal)
            if frame.phase == 61L {
                if (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) == 0L {
                    match compiler.expr_work.pop() { some(_) => (), none() => () }
                } else {
                    if is_generic_sum { emit_sum_constructor_payload(tables, compiler, ir, current, frame.child1, frame.child0) }
                    else { emit_enum_constructor_payload(tables, compiler, ir, current, case_index, frame.child1, frame.child0) }
                    frame.auxiliary += 1L
                    frame.phase = 60L
                    compiler.expr_work[frame_index] = frame
                }
            } else if frame.cursor >= 0L {
                let argument = frame.cursor
                let payload_index = frame.auxiliary
                frame.cursor = compiler.child_next[argument]
                frame.child0 = argument
                frame.child1 = payload_index
                frame.phase = 61L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: argument, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                let case_tag = compiler.facts[current].literal
                if is_generic_sum { emit_sum_tag_store(compiler, ir, current, case_tag) }
                else { emit_enum_tag_store(compiler, ir, current, case_tag) }
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            }
        } else if kind == NodeKind.Call {
            if frame.phase == 2L {
                let argument = frame.child0
                if (compiler.facts[argument].flags & FACT_FALLS_THROUGH) == 0L {
                    match compiler.expr_work.pop() { some(_) => (), none() => () }
                } else {
                    if direct_call_argument_needs_snapshot(tables, compiler, current, argument) {
                        let ty = compiler.facts[argument].ty
                        let source_kind = aggregate_source_kind(tables, compiler, argument)
                        let source_node = aggregate_source_id(tables, compiler, argument)
                        emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 0L, argument), aggregate_source_location(compiler, source_kind, source_node))
                    }
                    frame.child0 = -1L
                    frame.phase = 1L
                    compiler.expr_work[frame_index] = frame
                }
            } else if frame.phase == 1L && frame.child0 >= 0L && (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            } else if frame.cursor >= 0L {
                let argument = frame.cursor
                frame.cursor = compiler.child_next[argument]
                frame.phase = if is_aggregate_type(compiler, compiler.facts[argument].ty) { 2L } else { 1L }
                frame.child0 = argument
                compiler.expr_work[frame_index] = frame
                if direct_call_argument_is_write(tables, compiler, current, argument) &&
                    is_aggregate_type(compiler, compiler.facts[argument].ty) && tables.nodes[argument].kind == NodeKind.Name {
                    frame.child0 = -1L
                    frame.phase = 1L
                    compiler.expr_work[frame_index] = frame
                } else {
                    compiler.expr_work.push(EmitExprFrame { node: argument, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                }
            } else {
                let is_print = token_is_word_at(source, tokens, files, file_index, syntax.token, "print")
                let is_fill = token_is_word_at(source, tokens, files, file_index, syntax.token, "fill") &&
                    compiler.facts[current].function < 0L
                let format_kind = if (compiler.facts[current].flags & FACT_FORMAT_TEXT) != 0L { compiler.facts[current].literal } else { FORMAT_TEXT_NONE }
                let first_arg = compiler.child_first[current]
                if format_kind != FORMAT_TEXT_NONE {
                    emit_format_text_builtin(source, files, tokens, tables, compiler, ir, current, file_index, is_test, format_kind)
                } else if is_print {
                    let arg_ty = compiler.facts[first_arg].ty
                    if is_aggregate_type(compiler, arg_ty) {
                        let location = aggregate_source_location_for_node(tables, compiler, first_arg)
                        let pointer = emit_location_pointer_materialization(compiler, ir, location)
                        ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_one(compiler, ir, arg_ty, HELPER_PRINT, location, pointer); ir_write_ascii(compiler, ir, "\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_newline", "nlc_print_newline"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n")
                    } else {
                        ir_write_ascii(compiler, ir, "  call void ")
                        if compiler.c_runtime && (arg_ty == TY_INT || arg_ty == TY_BYTE) {
                            emit_context_runtime_symbol(compiler, ir, "nl_print_int_raw", "nlc_print_int_raw")
                            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 ")
                        } else if compiler.c_runtime && arg_ty == TY_LONG {
                            emit_context_runtime_symbol(compiler, ir, "nl_print_long_raw", "nlc_print_long_raw")
                            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 ")
                        } else if compiler.c_runtime {
                            emit_context_runtime_symbol(compiler, ir, "nl_print_bool_raw", "nlc_print_bool_raw")
                            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i1 zeroext ")
                        } else if arg_ty == TY_INT || arg_ty == TY_BYTE {
                            ir_write_ascii(compiler, ir, "@nl_print_int(ptr %nl.ctx, i32 ")
                        } else if arg_ty == TY_LONG {
                            ir_write_ascii(compiler, ir, "@nl_print_long(ptr %nl.ctx, i64 ")
                        } else {
                            ir_write_ascii(compiler, ir, "@nl_print_bool(ptr %nl.ctx, i1 zeroext ")
                        }
                        ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ")\n")
                        if compiler.c_runtime {
                            ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_newline", "nlc_print_newline"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n")
                        }
                    }
                } else if is_fill {
                    let fill_type = compiler.facts[current].ty
                    emit_collection_fill_array(tables, compiler, ir, current, fill_type, first_arg)
                } else {
                    let target = compiler.facts[current].function
                    let function = compiler.functions[target]
                    let call_result_ty = function.result_ty
                    let aggregate_result = is_aggregate_type(compiler, call_result_ty)
                    // E3a1 subsection: reload top after argument evaluation; calls may grow the stack.
                    if !compiler.core_mode { emit_current_top_load(compiler, ir, current) }
                    // E3a1 subsection end
                    if !compiler.core_mode {
                        var prepared_argument = first_arg
                        for argument_index in 0L..function.param_count {
                            let parameter = compiler.parameters[function.param_start + argument_index]
                            if parameter.ty != TY_UNIT {
                                if (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
                                    let location = place_storage_location(tables, compiler, prepared_argument)
                                    let geometry = is_aggregate_type(compiler, parameter.ty)
                                    emit_prepare_location_descriptor(compiler, ir, location, geometry, prepared_argument)
                                } else if is_aggregate_type(compiler, parameter.ty) {
                                    if parameter_uses_text_read_view(compiler, parameter) {
                                        let argument_type = compiler.facts[prepared_argument].ty
                                        let use_snapshot = direct_call_text_view_needs_snapshot(tables, compiler, current, prepared_argument)
                                        let location = if use_snapshot { compiler_location(compiler, 0L, prepared_argument, 0L) }
                                            else { direct_call_argument_source_location(tables, compiler, prepared_argument) }
                                        prepare_text_parameter_descriptor(compiler, ir, argument_type, location, prepared_argument)
                                    } else {
                                        let location = if direct_call_argument_needs_snapshot(tables, compiler, current, prepared_argument) {
                                            aggregate_destination_location(compiler, 0L, prepared_argument)
                                        } else {
                                            direct_call_argument_source_location(tables, compiler, prepared_argument)
                                        }
                                        emit_prepare_location_descriptor(compiler, ir, location, true, prepared_argument)
                                    }
                                } else { () }
                            }
                            prepared_argument = compiler.child_next[prepared_argument]
                        }
                    }
                    if call_result_ty != TY_UNIT && call_result_ty != TY_NEVER && !aggregate_result { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = ") } else { ir_write_ascii(compiler, ir, "  ") }
                    ir_write_ascii(compiler, ir, "call ")
                    if aggregate_result || call_result_ty == TY_UNIT || call_result_ty == TY_NEVER { ir_write_ascii(compiler, ir, "void") }
                    else { ir_write_ascii(compiler, ir, llvm_type_name(call_result_ty)) }
                    ir_push_byte(compiler, ir, 32)
                    var wrote_argument = false
                    if compiler.core_mode {
                        ir_write_core_function_symbol(source, files, tokens, compiler, ir, function, target)
                        ir_push_byte(compiler, ir, 40)
                        wrote_argument = false
                        if core_function_has_context(source, tokens, files, function) {
                            ir_write_ascii(compiler, ir, "ptr %nl.ctx")
                            wrote_argument = true
                        }
                    } else {
                        // E3a1 subsection
                        ir_write_ascii(compiler, ir, "@nl_fn_"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 "); emit_current_top_reference(compiler, ir, current)
                        // E3a1 subsection end
                    }
                    if !compiler.core_mode { wrote_argument = true }
                    if aggregate_result {
                        if wrote_argument { ir_write_ascii(compiler, ir, ", ") }
                        emit_hidden_destination_argument(compiler, ir, aggregate_destination_location(compiler, 0L, current))
                        wrote_argument = true
                    }
                    var arg = first_arg
                    for arg_index in 0L..function.param_count {
                        let parameter = compiler.parameters[function.param_start + arg_index]
                        let param_ty = parameter.ty
                        if param_ty != TY_UNIT {
                            if wrote_argument { ir_write_ascii(compiler, ir, ", ") }
                            if (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
                                emit_location_descriptor_argument(compiler, ir, place_storage_location(tables, compiler, arg), is_aggregate_type(compiler, param_ty), arg)
                            } else if is_aggregate_type(compiler, param_ty) {
                                if parameter_uses_text_read_view(compiler, parameter) {
                                    let use_snapshot = direct_call_text_view_needs_snapshot(tables, compiler, current, arg)
                                    emit_text_parameter_argument(tables, compiler, ir, arg, use_snapshot)
                                } else {
                                    let location = if direct_call_argument_needs_snapshot(tables, compiler, current, arg) {
                                        aggregate_destination_location(compiler, 0L, arg)
                                    } else {
                                        direct_call_argument_source_location(tables, compiler, arg)
                                    }
                                    emit_location_descriptor_argument(compiler, ir, location, true, arg)
                                }
                            } else {
                                ir_write_ascii(compiler, ir, llvm_type_name(param_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, arg)
                            }
                            wrote_argument = true
                        }
                        arg = compiler.child_next[arg]
                    }
                    ir_write_ascii(compiler, ir, ")\n")
                    if call_result_ty == TY_NEVER { ir_write_ascii(compiler, ir, "  unreachable\n") }
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.OptionalCall && frame.phase == 90L {
            let receiver = frame.child0
            if receiver < 0L || (compiler.facts[receiver].flags & FACT_FALLS_THROUGH) == 0L {
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            } else if emit_optional_call_start(tables, compiler, ir, current) {
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            } else {
                frame.cursor = compiler.child_next[receiver]
                frame.phase = 91L
                compiler.expr_work[frame_index] = frame
            }
        } else if kind == NodeKind.OptionalCall && frame.phase == 91L {
            if frame.cursor >= 0L {
                let argument = frame.cursor
                frame.cursor = compiler.child_next[argument]
                frame.child1 = argument
                frame.phase = 92L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: argument, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                emit_optional_call_invoke(tables, compiler, ir, current)
                if compiler.facts[current].ty != TY_NEVER {
                    ir_write_ascii(compiler, ir, "  br label %optional.call.end."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 10)
                }
                ir_write_ascii(compiler, ir, "optional.call.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            }
        } else if kind == NodeKind.OptionalCall && frame.phase == 92L {
            let argument = frame.child1
            if (compiler.facts[argument].flags & FACT_FALLS_THROUGH) == 0L {
                ir_write_ascii(compiler, ir, "optional.call.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            } else {
                if direct_call_argument_needs_snapshot(tables, compiler, current, argument) {
                    let argument_type = compiler.facts[argument].ty
                    let source_kind = aggregate_source_kind(tables, compiler, argument)
                    let source_node = aggregate_source_id(tables, compiler, argument)
                    emit_aggregate_copy(compiler, ir, argument_type, aggregate_destination_location(compiler, 0L, argument), aggregate_source_location(compiler, source_kind, source_node))
                }
                frame.child1 = -1L
                frame.phase = 91L
                compiler.expr_work[frame_index] = frame
            }
        } else if kind == NodeKind.MethodCall {
            if frame.cursor >= 0L {
                if frame.child2 < 0L && text_method_needs_receiver_metrics_capture(tables, compiler, current) {
                    emit_text_method_receiver_metrics(tables, compiler, ir, current)
                    frame.child2 = 0L
                }
                let argument = frame.cursor
                frame.cursor = compiler.child_next[argument]
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: argument, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                let receiver = compiler.child_first[current]
                let receiver_ty = compiler.facts[receiver].ty
                let receiver_kind = type_kind(compiler, receiver_ty)
                let c_method = c_runtime_method_kind(source, tokens, files, compiler, file_index, syntax.token, receiver_ty)
                if c_method != C_METHOD_NONE {
                    emit_c_runtime_method_call(tables, compiler, ir, current)
                } else if parse_number_method_kind(source, tokens, files, file_index, syntax.token) != PARSE_NUMBER_NONE {
                    emit_parse_number_method(source, files, tokens, tables, compiler, ir, current, file_index)
                } else if compiler.facts[current].literal == TEXT_METHOD_EMPTY {
                    emit_text_empty_value(compiler, ir, current, is_test || compiler.test_build)
                } else if receiver_kind == TYPE_KIND_ASCII || receiver_kind == TYPE_KIND_TEXT || receiver_kind == TYPE_KIND_BYTES {
                    emit_text_method_call(source, files, tokens, tables, compiler, ir, current, file_index, is_test || compiler.test_build)
                } else if is_sum_type(compiler, receiver_ty) && receiver_kind != TYPE_KIND_ENUM {
                    emit_option_result_method(source, files, tokens, tables, compiler, ir, current, file_index)
                } else {
                    emit_sys_method(source, files, tokens, tables, compiler, ir, current, file_index)
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.Match && frame.phase == 30L {
            let matched_type = compiler.facts[frame.child0].ty
            let wildcard_arm = match_wildcard_ordinal(tables, compiler, frame.cursor, frame.auxiliary, current)
            let default_arm = if wildcard_arm >= 0L { wildcard_arm } else { -1L }
            if is_sum_type(compiler, matched_type) {
                let source_kind = aggregate_source_kind(tables, compiler, frame.child0)
                let source_node = aggregate_source_id(tables, compiler, frame.child0)
                let source_location = aggregate_source_location(compiler, source_kind, source_node)
                let tag_address = enum_temporary_address(current, MAX_TREE_NODES)
                emit_layout_address(compiler, ir, tag_address, source_location)
                ir_write_ascii(compiler, ir, "  %match.tag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address); ir_write_ascii(compiler, ir, ", align 1\n  switch i32 %match.tag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %")
            } else {
                ir_write_ascii(compiler, ir, "  switch "); ir_write_ascii(compiler, ir, llvm_type_name(matched_type)); ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", label %")
            }
            if default_arm >= 0L { ir_write_ascii(compiler, ir, "match.arm."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, default_arm) }
            else { ir_write_ascii(compiler, ir, "match.invalid."); ir_write_number(compiler, ir, current) }
            ir_write_ascii(compiler, ir, " [\n")
            var scan = frame.cursor
            var ordinal = frame.auxiliary
            for arm_step in 0L..tables.nodes[current].subtree {
                if scan < 0L { break }
                let pattern = compiler.child_first[scan]
                if pattern >= 0L && tables.nodes[pattern].kind != NodeKind.WildcardPattern {
                    let fact = compiler.facts[pattern]
                    ir_write_ascii(compiler, ir, "    "); ir_write_ascii(compiler, ir, llvm_type_name(matched_type)); ir_push_byte(compiler, ir, 32)
                    if matched_type == TY_BOOL { if fact.literal == 1L { ir_write_ascii(compiler, ir, "true") } else { ir_write_ascii(compiler, ir, "false") } }
                    else { ir_write_number(compiler, ir, fact.literal) }
                    ir_write_ascii(compiler, ir, ", label %match.arm."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, ordinal); ir_push_byte(compiler, ir, 10)
                }
                scan = compiler.child_next[scan]
                ordinal += 1L
            }
            ir_write_ascii(compiler, ir, "  ]\n")
            if default_arm < 0L {
                ir_write_ascii(compiler, ir, "match.invalid."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  unreachable\n")
            }
            frame.phase = 32L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Match && frame.phase == 31L {
            let arm = frame.child1
            let body = frame.child2
            if compiler.facts[body].ty != TY_NEVER {
                let result_ty = compiler.facts[current].ty
                let tail = if (tables.nodes[body].flags & FLAG_HAS_TAIL) != 0L { node_last_child(tables, compiler, body) } else { -1L }
                if is_aggregate_type(compiler, result_ty) && tail >= 0L {
                    let source_kind = aggregate_source_kind(tables, compiler, tail)
                    let source_node = aggregate_source_id(tables, compiler, tail)
                    emit_aggregate_copy(compiler, ir, result_ty, aggregate_destination_location(compiler, 0L, current), aggregate_source_location(compiler, source_kind, source_node))
                }
                emit_region_scope_exit(tables, compiler, ir, arm)
                ir_write_ascii(compiler, ir, "  br label %match.arm.cont."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, frame.auxiliary); ir_push_byte(compiler, ir, 10)
                ir_write_ascii(compiler, ir, "match.arm.cont."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, frame.auxiliary); ir_write_ascii(compiler, ir, ":\n  br label %match.end."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 10)
            }
            frame.auxiliary += 1L
            frame.phase = 32L
            compiler.expr_work[frame_index] = frame
            let _ = arm
        } else if kind == NodeKind.Match && frame.phase == 32L {
            if frame.cursor >= 0L {
                let arm = frame.cursor
                let ordinal = frame.auxiliary
                let pattern = compiler.child_first[arm]
                let body = if pattern >= 0L { compiler.child_next[pattern] } else { -1L }
                ir_write_ascii(compiler, ir, "match.arm."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, ordinal); ir_write_ascii(compiler, ir, ":\n")
                emit_region_scope_enter(files, tables, compiler, ir, arm, file_index)
                emit_match_payload_bindings(tables, compiler, ir, current, arm)
                frame.cursor = compiler.child_next[arm]
                frame.child1 = arm
                frame.child2 = body
                frame.phase = 31L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: body, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if compiler.facts[current].ty != TY_NEVER {
                ir_write_ascii(compiler, ir, "match.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
                let result_ty = compiler.facts[current].ty
                if result_ty != TY_UNIT && !is_aggregate_type(compiler, result_ty) {
                    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = phi "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty)); ir_push_byte(compiler, ir, 32)
                    var scan = if compiler.child_first[current] >= 0L { compiler.child_next[compiler.child_first[current]] } else { -1L }
                    var ordinal = 0L
                    var wrote = false
                    for arm_step in 0L..tables.nodes[current].subtree {
                        if scan < 0L { break }
                        let pattern = compiler.child_first[scan]
                        let body = if pattern >= 0L { compiler.child_next[pattern] } else { -1L }
                        if body >= 0L && compiler.facts[body].ty != TY_NEVER {
                            if wrote { ir_write_ascii(compiler, ir, ", ") }
                            let tail = if (tables.nodes[body].flags & FLAG_HAS_TAIL) != 0L { node_last_child(tables, compiler, body) } else { -1L }
                            ir_write_ascii(compiler, ir, "[ "); ir_write_value_ref(compiler, ir, tail); ir_write_ascii(compiler, ir, ", %match.arm.cont."); ir_write_number(compiler, ir, current); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, ordinal); ir_write_ascii(compiler, ir, " ]")
                            wrote = true
                        }
                        scan = compiler.child_next[scan]
                        ordinal += 1L
                    }
                    ir_push_byte(compiler, ir, 10)
                }
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            } else {
                match compiler.expr_work.pop() { some(_) => (), none() => () }
            }
        } else if kind == NodeKind.If && frame.phase == 1L {
            ir_write_ascii(compiler, ir, "  br i1 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", label %if.expr.then."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %if.expr.")
            if frame.child2 >= 0L { ir_write_ascii(compiler, ir, "else.") } else { ir_write_ascii(compiler, ir, "end.") }
            ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\nif.expr.then."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
            frame.phase = 2L
            frame.cursor = 0L
            frame.reachable = true
            compiler.expr_work[frame_index] = frame
            compiler.expr_work.push(EmitExprFrame { node: frame.child1, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: current, reachable: true }).unwrap()
        } else if kind == NodeKind.If && frame.phase == 2L {
            if frame.child2 >= 0L {
                ir_write_ascii(compiler, ir, "if.expr.else."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
                frame.phase = 3L
                frame.reachable = true
                compiler.expr_work[frame_index] = frame
                if tables.nodes[frame.child2].kind == NodeKind.If {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child2, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: current, reachable: true }).unwrap()
                } else {
                    compiler.expr_work.push(EmitExprFrame { node: frame.child2, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: current, reachable: true }).unwrap()
                }
            } else {
                ir_write_ascii(compiler, ir, "if.expr.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n")
                if frame.auxiliary >= 0L {
                    lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L)
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
                if compiler.expr_work.count() > base_depth {
                    let parent_index = compiler.expr_work.count() - 1L
                    var parent = compiler.expr_work[parent_index]
                    if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = true }
                    compiler.expr_work[parent_index] = parent
                }
            }
        } else if kind == NodeKind.If && frame.phase == 3L {
            let then_falls = frame.cursor == 1L
            let else_falls = frame.reachable
            let any_falls = then_falls || else_falls
            let result_ty = compiler.facts[current].ty
            if any_falls { ir_write_ascii(compiler, ir, "if.expr.end."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n") }
            if any_falls && result_ty != TY_UNIT && result_ty != TY_NEVER {
                if !is_aggregate_type(compiler, result_ty) {
                    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty)); ir_write_ascii(compiler, ir, ", ptr %if.slot."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", align 1\n")
                }
            }
            if any_falls && frame.auxiliary >= 0L {
                if result_ty != TY_UNIT && result_ty != TY_NEVER {
                    if is_aggregate_type(compiler, result_ty) {
                        emit_aggregate_copy(compiler, ir, result_ty, aggregate_destination_location(compiler, 0L, frame.auxiliary), aggregate_source_location(compiler, 0L, current))
                    } else {
                        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, current); ir_write_ascii(compiler, ir, ", ptr %if.slot."); ir_write_number(compiler, ir, frame.auxiliary); ir_write_ascii(compiler, ir, ", align 1\n")
                    }
                }
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L)
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
            if compiler.expr_work.count() > base_depth {
                let parent_index = compiler.expr_work.count() - 1L
                var parent = compiler.expr_work[parent_index]
                if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = any_falls }
                compiler.expr_work[parent_index] = parent
            }
        } else if kind == NodeKind.Block && frame.phase == 10L {
            if !frame.reachable {
                match compiler.expr_work.pop() { some(_) => (), none => () }
                if compiler.expr_work.count() > base_depth {
                    let parent_index = compiler.expr_work.count() - 1L
                    var parent = compiler.expr_work[parent_index]
                    if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 2L { parent.cursor = 0L }
                    else if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = false }
                    else { () }
                    compiler.expr_work[parent_index] = parent
                }
            } else if frame.child2 < 0L {
                frame.child2 = 1L
                compiler.expr_work[frame_index] = frame
                let active_function_id = if compiler.work.count() > 0L { compiler.work[compiler.work.count() - 1L].function_id } else { -1L }
                let falls = emit_function_body(source, files, tokens, tables, compiler, ir, current, file_index, active_function_id, return_ty, is_test, false, true)
                frame = compiler.expr_work[frame_index]
                frame.reachable = falls
                frame.cursor = if (tables.nodes[current].flags & FLAG_HAS_TAIL) != 0L { frame.child0 } else { -1L }
                compiler.expr_work[frame_index] = frame
            } else if frame.cursor >= 0L && (frame.cursor != frame.child0 || (tables.nodes[current].flags & FLAG_HAS_TAIL) == 0L) {
                let statement = frame.cursor
                frame.cursor = compiler.child_next[statement]
                if tables.nodes[statement].kind == NodeKind.Let {
                    var value = -1L
                    var child = compiler.child_first[statement]
                    for child_step in 0L..tables.nodes[statement].subtree {
                        if child < 0L { break }
                        if tables.nodes[child].kind != NodeKind.Annotation { value = child }
                        child = compiler.child_next[child]
                    }
                    frame.child1 = statement
                    frame.child2 = value
                    frame.phase = 12L
                    compiler.expr_work[frame_index] = frame
                    compiler.expr_work.push(EmitExprFrame { node: value, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                } else if tables.nodes[statement].kind == NodeKind.Assign {
                    let target = compiler.child_first[statement]
                    frame.child1 = statement
                    frame.child2 = compiler.child_next[target]
                    frame.phase = 13L
                    compiler.expr_work[frame_index] = frame
                    if tables.nodes[target].kind == NodeKind.Field {
                        emit_field_path_value(tables, compiler, ir, target)
                    } else if binding_is_write_parameter(compiler, compiler.facts[target].binding) {
                        let binding = compiler.facts[target].binding
                        let parameter_type = compiler.facts[target].ty
                        let parameter_location = compiler_location(compiler, 3L, binding, 0L)
                        emit_layout_address(compiler, ir, target, parameter_location)
                        emit_load_scalar(compiler, ir, target, parameter_type)
                    } else { () }
                    compiler.expr_work.push(EmitExprFrame { node: frame.child2, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                } else if tables.nodes[statement].kind == NodeKind.ExpressionStatement {
                    let expression = compiler.child_first[statement]
                    if expression >= 0L {
                        frame.child1 = statement
                        frame.child2 = expression
                        frame.phase = 14L
                        compiler.expr_work[frame_index] = frame
                        compiler.expr_work.push(EmitExprFrame { node: expression, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                    } else { compiler.expr_work[frame_index] = frame }
                } else if tables.nodes[statement].kind == NodeKind.Expect {
                    let expression = compiler.child_first[statement]
                    frame.child1 = statement
                    frame.child2 = expression
                    frame.phase = 15L
                    compiler.expr_work[frame_index] = frame
                    compiler.expr_work.push(EmitExprFrame { node: expression, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                } else if tables.nodes[statement].kind == NodeKind.ReturnStatement {
                    let value = compiler.child_first[statement]
                    if value >= 0L {
                        frame.child1 = statement
                        frame.child2 = value
                        frame.phase = 16L
                        compiler.expr_work[frame_index] = frame
                        compiler.expr_work.push(EmitExprFrame { node: value, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
                    } else {
                        if is_test { lower_scope_exit(compiler, ir, -1L, EXIT_TEST_FAILURE, 0L, 0L, TY_UNIT, -1L) }
                        else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, TY_UNIT, -1L) }
                        frame.reachable = false
                        frame.cursor = -1L
                        compiler.expr_work[frame_index] = frame
                    }
                } else if tables.nodes[statement].kind == NodeKind.BreakStatement || tables.nodes[statement].kind == NodeKind.ContinueStatement {
                    let loop = compiler.emit_loops[compiler.emit_loops.count() - 1L]
                    // E3a1 subsection
                    emit_region_loop_exit(tables, compiler, ir, loop.body, statement)
                    // E3a1 subsection end
                    let target_kind = if tables.nodes[loop.node].kind == NodeKind.While { 1L } else { 0L }
                    if tables.nodes[statement].kind == NodeKind.BreakStatement { lower_scope_exit(compiler, ir, -1L, EXIT_BREAK, target_kind, loop.node, TY_UNIT, -1L) }
                    else { lower_scope_exit(compiler, ir, -1L, EXIT_CONTINUE, target_kind, loop.node, TY_UNIT, -1L) }
                    frame.reachable = false
                    frame.cursor = -1L
                    compiler.expr_work[frame_index] = frame
                } else { compiler.expr_work[frame_index] = frame }
            } else if frame.child0 >= 0L && (tables.nodes[current].flags & FLAG_HAS_TAIL) != 0L {
                frame.phase = 11L
                frame.child1 = frame.child0
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                // E3a1 subsection
                emit_region_scope_exit(tables, compiler, ir, current)
                if frame.auxiliary >= 0L {
                    lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L)
                }
                // E3a1 subsection end
                match compiler.expr_work.pop() { some(_) => (), none => () }
                if compiler.expr_work.count() > base_depth {
                    let parent_index = compiler.expr_work.count() - 1L
                    var parent = compiler.expr_work[parent_index]
                    if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 2L { parent.cursor = if frame.reachable { 1L } else { 0L } }
                    else if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = frame.reachable }
                    else { () }
                    compiler.expr_work[parent_index] = parent
                }
            }
        } else if kind == NodeKind.Block && frame.phase == 11L {
            if compiler.facts[frame.child1].ty == TY_NEVER {
                frame.reachable = false
            } else if frame.auxiliary >= 0L && compiler.facts[frame.child1].ty != TY_UNIT &&
                (compiler.facts[frame.child1].flags & FACT_PROVEN_SUCCESS) == 0L {
                let parent = frame.auxiliary
                let tail_ty = compiler.facts[frame.child1].ty
                if is_aggregate_type(compiler, tail_ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, frame.child1)
                    let source_node = aggregate_source_id(tables, compiler, frame.child1)
                    emit_aggregate_copy(compiler, ir, tail_ty, aggregate_destination_location(compiler, 0L, parent), aggregate_source_location(compiler, source_kind, source_node))
                } else {
                    ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(tail_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, frame.child1); ir_write_ascii(compiler, ir, ", ptr %if.slot."); ir_write_number(compiler, ir, parent); ir_write_ascii(compiler, ir, ", align 1\n")
                }
            } else { () }
            // E3a1 subsection
            if frame.reachable { emit_region_scope_exit(tables, compiler, ir, current) }
            if frame.reachable && frame.auxiliary >= 0L {
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L)
            }
            // E3a1 subsection end
            match compiler.expr_work.pop() { some(_) => (), none => () }
            if compiler.expr_work.count() > base_depth {
                let parent_index = compiler.expr_work.count() - 1L
                var parent = compiler.expr_work[parent_index]
                if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 2L { parent.cursor = if frame.reachable { 1L } else { 0L } }
                else if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = frame.reachable }
                else { () }
                compiler.expr_work[parent_index] = parent
            }
        } else if kind == NodeKind.Block && frame.phase == 12L {
            let statement = frame.child1
            let value = frame.child2
            let binding = compiler.facts[statement].binding
            let ty = compiler.bindings[binding].ty
            if is_aggregate_type(compiler, ty) {
                let source_kind = aggregate_source_kind(tables, compiler, value)
                let source_node = aggregate_source_id(tables, compiler, value)
                emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 1L, binding), aggregate_source_location(compiler, source_kind, source_node))
            } else if ty == TY_BOOL {
                ir_write_ascii(compiler, ir, "  %block.bool."); ir_write_number(compiler, ir, statement); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %block.bool."); ir_write_number(compiler, ir, statement); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
            } else if ty != TY_UNIT {
                ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
            } else { () }
            frame.phase = 10L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Block && frame.phase == 13L {
            let statement = frame.child1
            let value = frame.child2
            let target = compiler.child_first[statement]
            let binding = compiler.facts[target].binding
            let ty = compiler.facts[target].ty
            let op = tables.nodes[statement].flags
            if op == 0L {
                if is_aggregate_type(compiler, ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, value)
                    let source_node = aggregate_source_id(tables, compiler, value)
                    let destination = if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index { compiler_location(compiler, 2L, target, 0L) } else if binding_is_write_parameter(compiler, binding) && is_sum_type(compiler, ty) { place_storage_location(tables, compiler, target) } else if binding_is_write_parameter(compiler, binding) { compiler_location(compiler, 3L, binding, 0L) } else { aggregate_destination_location(compiler, 1L, binding) }
                    emit_aggregate_copy(compiler, ir, ty, destination, aggregate_source_location(compiler, source_kind, source_node))
                } else if ty == TY_BOOL {
                    if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, binding) || binding_is_view(compiler, binding) { emit_store_scalar_to_place(tables, compiler, ir, target, ty, value) }
                    else { ir_write_ascii(compiler, ir, "  %block.bool."); ir_write_number(compiler, ir, statement); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %block.bool."); ir_write_number(compiler, ir, statement); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
                } else if ty != TY_UNIT {
                    if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, binding) || binding_is_view(compiler, binding) { emit_store_scalar_to_place(tables, compiler, ir, target, ty, value) }
                    else {
                        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                    }
                } else { () }
            } else {
                emit_compound_assignment(files, tables, compiler, ir, statement, file_index, target, binding, value, ty, op)
            }
            frame.phase = 10L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Block && frame.phase == 14L {
            frame.phase = 10L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Block && frame.phase == 15L {
            emit_expect_after_expression(source, files, tokens, tables, compiler, ir, frame.child1, file_index, frame.child2)
            frame.phase = 10L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Block && frame.phase == 16L {
            if is_aggregate_type(compiler, return_ty) {
                let source_kind = aggregate_source_kind(tables, compiler, frame.child2)
                let source_node = aggregate_source_id(tables, compiler, frame.child2)
                emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(compiler, 2L, 0L), aggregate_source_location(compiler, source_kind, source_node))
                lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L)
            } else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN_VALUE, 0L, 0L, return_ty, frame.child2) }
            frame.reachable = false
            frame.cursor = -1L
            frame.phase = 10L
            compiler.expr_work[frame_index] = frame
        } else {
            match compiler.expr_work.pop() { some(_) => (), none => () }
        }
    }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_expect_after_expression(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
    expression: long,
) {
    let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].start, compiler)
    let start = tables.nodes[node].start
    let end = tables.nodes[node].end
    let length = end - start + 1L
    ir_write_ascii(compiler, ir, "  br i1 ")
    ir_write_value_ref(compiler, ir, expression)
    ir_write_ascii(compiler, ir, ", label %expect.pass.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %expect.fail.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nexpect.fail.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n")
    if tables.nodes[expression].kind == NodeKind.Binary && tables.nodes[expression].flags >= 8L && tables.nodes[expression].flags <= 13L {
        let left_node = compiler.child_first[expression]
        let right_node = compiler.child_next[left_node]
        let operand_ty = compiler.facts[left_node].ty
        if is_aggregate_type(compiler, operand_ty) {
            let left_location = if region_node_needs_snapshot(tables, compiler, left_node) {
                compiler_location(compiler, 0L, left_node, 0L)
            } else {
                aggregate_source_location_for_node(tables, compiler, left_node)
            }
            let right_location = aggregate_source_location_for_node(tables, compiler, right_node)
            let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
            let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
            ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_expect_fail_header", "nlc_expect_fail_header"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 "); ir_write_number(compiler, ir, file_index); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds (["); ir_write_number(compiler, ir, length); ir_write_ascii(compiler, ir, " x i8], ptr @.nl.expect."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 "); ir_write_number(compiler, ir, length - 1L); ir_write_ascii(compiler, ir, ")\n")
            ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_expect_fail_left", "nlc_expect_fail_left"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  call void "); emit_type_helper_call_one(compiler, ir, operand_ty, HELPER_PRINT, left_location, left_pointer)
            ir_write_ascii(compiler, ir, "\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_newline", "nlc_print_newline"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_expect_fail_right", "nlc_expect_fail_right"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n  call void "); emit_type_helper_call_one(compiler, ir, operand_ty, HELPER_PRINT, right_location, right_pointer); ir_write_ascii(compiler, ir, "\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_newline", "nlc_print_newline"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx)\n")
        } else {
        if operand_ty == TY_INT || operand_ty == TY_BOOL || operand_ty == TY_BYTE {
            let extension = if operand_ty == TY_INT { "sext" } else { "zext" }
            ir_write_ascii(compiler, ir, "  %expect.left.")
            ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = ")
            ir_write_ascii(compiler, ir, extension)
            ir_write_ascii(compiler, ir, " ")
            ir_write_ascii(compiler, ir, llvm_type_name(operand_ty))
            ir_write_ascii(compiler, ir, " ")
            ir_write_value_ref(compiler, ir, left_node)
            ir_write_ascii(compiler, ir, " to i64\n  %expect.right.")
            ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = ")
            ir_write_ascii(compiler, ir, extension)
            ir_write_ascii(compiler, ir, " ")
            ir_write_ascii(compiler, ir, llvm_type_name(operand_ty))
            ir_write_ascii(compiler, ir, " ")
            ir_write_value_ref(compiler, ir, right_node)
            ir_write_ascii(compiler, ir, " to i64\n")
        }
        ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_expect_fail_compare", "nlc_expect_fail_compare"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 ")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.line)
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.col)
        ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, length)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.expect.")
        ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
        ir_write_number(compiler, ir, length - 1L)
        ir_write_ascii(compiler, ir, ", i64 ")
        if operand_ty == TY_LONG { ir_write_value_ref(compiler, ir, left_node) }
        else { ir_write_ascii(compiler, ir, "%expect.left."); ir_write_number(compiler, ir, node) }
        ir_write_ascii(compiler, ir, ", i64 ")
        if operand_ty == TY_LONG { ir_write_value_ref(compiler, ir, right_node) }
        else { ir_write_ascii(compiler, ir, "%expect.right."); ir_write_number(compiler, ir, node) }
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, if operand_ty == TY_BOOL { 1L } else { 0L })
        ir_write_ascii(compiler, ir, ")\n")
        }
    } else {
        ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_expect_fail_bool", "nlc_expect_fail_bool"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 ")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.line)
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.col)
        ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, length)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.expect.")
        ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
        ir_write_number(compiler, ir, length - 1L)
        ir_write_ascii(compiler, ir, ")\n")
    }
    lower_scope_exit(compiler, ir, -1L, EXIT_TEST_FAILURE, 0L, 0L, TY_UNIT, -1L)
    ir_write_ascii(compiler, ir, "expect.pass.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n")
}
// E3a1 end

recursive fn emit_expect_statement(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let expression = compiler.child_first[node]
    emit_expr_linear(source, files, tokens, tables, compiler, ir, expression, file_index, TY_UNIT, true)
    emit_expect_after_expression(source, files, tokens, tables, compiler, ir, node, file_index, expression)
}

// E3a1 begin: shared compiler integration.
recursive fn emit_function_body(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    body: long,
    file_index: long,
    function_id: long,
    return_ty: long,
    is_test: bool,
    function_root: bool,
    stop_before_tail: bool,
) -> bool {
    var base_depth = compiler.work.count()
    var body_falls = true
    if function_root {
        compiler.work.clear()
        compiler.emit_loops.clear()
        compiler.ir_terminated = false
        base_depth = 0L
    }
    compiler.work.push(CheckFrame { node: body, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[body], child0: node_last_child(tables, compiler, body), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
    for emit_step in 0L..MAX_PARSE_WORK {
        if compiler.work.count() <= base_depth { break }
        let frame_index = compiler.work.count() - 1L
        var frame = compiler.work[frame_index]
        if frame.phase == 100L {
            if frame.child2 == 1L { lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_END, frame.node, TY_UNIT, -1L) }
            if frame.child1 >= 0L {
                ir_write_ascii(compiler, ir, "if.else."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
                // E3a1 subsection
                if tables.nodes[frame.child1].kind == NodeKind.Block { emit_region_scope_enter(files, tables, compiler, ir, frame.child1, file_index) }
                // E3a1 subsection end
                frame.phase = 101L
                frame.auxiliary = 0L
                compiler.work[frame_index] = frame
                compiler.work.push(CheckFrame { node: frame.child1, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[frame.child1], child0: node_last_child(tables, compiler, frame.child1), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
            } else {
                ir_write_ascii(compiler, ir, "if.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
                match compiler.work.pop() { some(_) => (), none => () }
                let parent_index = compiler.work.count() - 1L
                var parent = compiler.work[parent_index]
                parent.reachable = true
                compiler.work[parent_index] = parent
            }
            continue
        }
        if frame.phase == 101L {
            let then_falls = frame.child2 == 1L
            let else_falls = frame.auxiliary == 1L
            if else_falls { lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_END, frame.node, TY_UNIT, -1L) }
            if then_falls || else_falls {
                ir_write_ascii(compiler, ir, "if.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            }
            match compiler.work.pop() { some(_) => (), none => () }
            let parent_index = compiler.work.count() - 1L
            var parent = compiler.work[parent_index]
            parent.reachable = then_falls || else_falls
            compiler.work[parent_index] = parent
            continue
        }
        if frame.phase == 200L {
            if frame.auxiliary == 1L {
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_FOR_INCREMENT, frame.node, TY_UNIT, -1L)
            }
            let binding = frame.child1
            let ty = compiler.bindings[binding].ty
            ir_write_ascii(compiler, ir, "for.increment."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            ir_write_ascii(compiler, ir, "  %for.current."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
            let is_inclusive = (tables.nodes[frame.node].flags & FLAG_INCLUSIVE) != 0L
            if is_inclusive {
                ir_write_ascii(compiler, ir, "  %for.last."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %for.current."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, "\n  br i1 %for.last."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", label %for.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", label %for.increment.value."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, "\nfor.increment.value."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            }
            ir_write_ascii(compiler, ir, "  %for.next."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, " = add "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %for.current."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", 1\n  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %for.next."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n  br label %for.cond."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, "\nfor.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            match compiler.emit_loops.pop() { some(_) => (), none => () }
            match compiler.work.pop() { some(_) => (), none => () }
            continue
        }
        if frame.phase == 210L {
            if frame.auxiliary == 1L {
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_FOR_INCREMENT, frame.node, TY_UNIT, -1L)
            }
            ir_write_ascii(compiler, ir, "for.increment."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n  %for.each.next."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, " = add i64 %for.each.current."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", 1\n  store i64 %for.each.next."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", ptr %for.each.index."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", align 8\n  br label %for.cond."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, "\nfor.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            match compiler.emit_loops.pop() { some(_) => (), none => () }
            match compiler.work.pop() { some(_) => (), none => () }
            continue
        }
        if frame.phase == 220L {
            if frame.auxiliary == 1L {
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_WHILE_STEP, frame.node, TY_UNIT, -1L)
            }
            ir_write_ascii(compiler, ir, "while.step."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            if compiler.step_budget_main >= 0L {
                ir_write_ascii(compiler, ir, "  %while.steps.within."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, " = call i1 @nl_core_nl_context_step_budget_take(ptr %nl.ctx)\n  br i1 %while.steps.within."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", label %while.cond."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ", label %while.fail."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, "\nwhile.fail."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_fail", "nlc_fail"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i32 23, i32 "); ir_write_number(compiler, ir, file_index + compiler_file_id_base(compiler)); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + tables.nodes[frame.node].start, compiler).line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + tables.nodes[frame.node].start, compiler).col); ir_write_ascii(compiler, ir, ")\n  unreachable\n")
            } else { ir_write_ascii(compiler, ir, "  br label %while.cond."); ir_write_number(compiler, ir, frame.node); ir_push_byte(compiler, ir, 10) }
            ir_write_ascii(compiler, ir, "while.end."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
            match compiler.emit_loops.pop() { some(_) => (), none => () }
            match compiler.work.pop() { some(_) => (), none => () }
            continue
        }
        if !frame.reachable {
            frame.cursor = -1L
            compiler.work[frame_index] = frame
        }
        if frame.cursor < 0L {
            // E3a1 subsection
            if frame.node != body && frame.reachable {
                emit_region_scope_exit(tables, compiler, ir, frame.node)
            }
            // E3a1 subsection end
            if function_root && frame.node == body && frame.reachable {
                lower_scope_exit(compiler, ir, -1L, EXIT_FALLTHROUGH, if is_test { 1L } else { 0L }, 0L, return_ty, -1L)
            }
            if frame.node == body { body_falls = frame.reachable }
            match compiler.work.pop() { some(_) => (), none => () }
            if compiler.work.count() > base_depth {
                let parent_index = compiler.work.count() - 1L
                var parent = compiler.work[parent_index]
                if parent.phase == 100L { parent.child2 = if frame.reachable { 1L } else { 0L } }
                else if parent.phase == 101L { parent.auxiliary = if frame.reachable { 1L } else { 0L } }
                else if parent.phase == 200L || parent.phase == 210L || parent.phase == 220L { parent.auxiliary = if frame.reachable { 1L } else { 0L } }
                else if !frame.reachable { parent.reachable = false }
                else { () }
                compiler.work[parent_index] = parent
            }
            continue
        }
        let child = frame.cursor
        frame.cursor = compiler.child_next[child]
        compiler.work[frame_index] = frame
        if stop_before_tail && frame.node == body && child == frame.child0 &&
            (tables.nodes[body].flags & FLAG_HAS_TAIL) != 0L {
            compiler.work[frame_index].cursor = -1L
            continue
        }
        let is_statement = tables.nodes[child].kind == NodeKind.Let || tables.nodes[child].kind == NodeKind.Assign || tables.nodes[child].kind == NodeKind.ExpressionStatement || tables.nodes[child].kind == NodeKind.Discard || tables.nodes[child].kind == NodeKind.ReturnStatement || tables.nodes[child].kind == NodeKind.For || tables.nodes[child].kind == NodeKind.ForEach || tables.nodes[child].kind == NodeKind.While || tables.nodes[child].kind == NodeKind.Expect || tables.nodes[child].kind == NodeKind.BreakStatement || tables.nodes[child].kind == NodeKind.ContinueStatement || tables.nodes[child].kind == NodeKind.Block
        if !is_statement {
            let redirect_return = function_root && frame.node == body && child == frame.child0 &&
                (tables.nodes[body].flags & FLAG_HAS_TAIL) != 0L && is_aggregate_type(compiler, return_ty)
            let saved_destination_node = compiler.emit_destination_node
            let saved_destination_kind = compiler.emit_destination_kind
            let saved_destination_anchor = compiler.emit_destination_anchor
            if redirect_return {
                compiler.emit_destination_node = child
                compiler.emit_destination_kind = 2L
                compiler.emit_destination_anchor = -1L
            }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, child, file_index, return_ty, is_test)
            if redirect_return {
                compiler.emit_destination_node = saved_destination_node
                compiler.emit_destination_kind = saved_destination_kind
                compiler.emit_destination_anchor = saved_destination_anchor
            }
            if function_root && frame.node == body {
                if (compiler.facts[child].flags & FACT_FALLS_THROUGH) != 0L {
                    if is_test { lower_scope_exit(compiler, ir, -1L, EXIT_TEST_SUCCESS, 0L, 0L, TY_UNIT, -1L) }
                    else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
                    else if is_aggregate_type(compiler, return_ty) {
                        let source_kind = aggregate_source_kind(tables, compiler, child)
                        let source_node = aggregate_source_id(tables, compiler, child)
                        if !redirect_return {
                            emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(compiler, 2L, 0L), aggregate_source_location(compiler, source_kind, source_node))
                        }
                        lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L)
                    }
                    else {
                        lower_scope_exit(compiler, ir, -1L, EXIT_RETURN_VALUE, 0L, 0L, return_ty, child)
                    }
                }
                frame.reachable = false
                compiler.work[frame_index] = frame
            }
            continue
        }
        let kind = tables.nodes[child].kind
        if kind == NodeKind.Let {
            var value = -1L
            var sub = compiler.child_first[child]
            for sub_step in 0L..tables.nodes[child].subtree {
                if sub < 0L { break }
                if tables.nodes[sub].kind != NodeKind.Annotation { value = sub }
                sub = compiler.child_next[sub]
            }
            let binding = compiler.facts[child].binding
            let ty = compiler.bindings[binding].ty
            let redirect_value = is_aggregate_type(compiler, ty)
            let saved_destination_node = compiler.emit_destination_node
            let saved_destination_kind = compiler.emit_destination_kind
            let saved_destination_anchor = compiler.emit_destination_anchor
            if redirect_value {
                compiler.emit_destination_node = value
                compiler.emit_destination_kind = 1L
                compiler.emit_destination_anchor = binding
            }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, value, file_index, return_ty, is_test)
            if redirect_value {
                compiler.emit_destination_node = saved_destination_node
                compiler.emit_destination_kind = saved_destination_kind
                compiler.emit_destination_anchor = saved_destination_anchor
            }
            if (compiler.facts[value].flags & FACT_FALLS_THROUGH) == 0L {
                frame.reachable = false
                frame.cursor = -1L
                compiler.work[frame_index] = frame
            } else {
                if is_aggregate_type(compiler, ty) {
                    if !redirect_value {
                        let source_kind = aggregate_source_kind(tables, compiler, value)
                        let source_node = aggregate_source_id(tables, compiler, value)
                        emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(compiler, 1L, binding), aggregate_source_location(compiler, source_kind, source_node))
                    }
                } else if ty == TY_BOOL {
                    ir_write_ascii(compiler, ir, "  %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                } else if ty != TY_UNIT {
                    ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                } else { () }
            }
        } else if kind == NodeKind.Assign {
            let target = compiler.child_first[child]
            let value = compiler.child_next[target]
            if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, compiler.facts[target].binding) || binding_is_view(compiler, compiler.facts[target].binding) { emit_expr_linear(source, files, tokens, tables, compiler, ir, target, file_index, return_ty, is_test) }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, value, file_index, return_ty, is_test)
            let binding = compiler.facts[target].binding
            let ty = compiler.facts[target].ty
            let op = tables.nodes[child].flags
            if op == 0L {
                if is_aggregate_type(compiler, ty) {
                    let destination = if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index { compiler_location(compiler, 2L, target, 0L) } else if binding_is_write_parameter(compiler, binding) && is_sum_type(compiler, ty) { place_storage_location(tables, compiler, target) } else if binding_is_write_parameter(compiler, binding) { compiler_location(compiler, 3L, binding, 0L) } else { aggregate_destination_location(compiler, 1L, binding) }
                    emit_aggregate_copy_to_place(tables, compiler, ir, ty, target, value, destination)
                } else if ty == TY_BOOL {
                    if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, binding) || binding_is_view(compiler, binding) { emit_store_scalar_to_place(tables, compiler, ir, target, ty, value) }
                    else { ir_write_ascii(compiler, ir, "  %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
                } else if ty != TY_UNIT {
                    if tables.nodes[target].kind == NodeKind.Field || tables.nodes[target].kind == NodeKind.Index || binding_is_write_parameter(compiler, binding) || binding_is_view(compiler, binding) { emit_store_scalar_to_place(tables, compiler, ir, target, ty, value) }
                    else {
                        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
                    }
                } else { () }
            } else {
                emit_compound_assignment(files, tables, compiler, ir, child, file_index, target, binding, value, ty, op)
            }
        } else if kind == NodeKind.Discard {
            let expression = compiler.child_first[child]
            emit_expr_linear(source, files, tokens, tables, compiler, ir, expression, file_index, return_ty, is_test)
        } else if kind == NodeKind.ExpressionStatement {
            let expression = compiler.child_first[child]
            if expression >= 0L {
                emit_expr_linear(source, files, tokens, tables, compiler, ir, expression, file_index, return_ty, is_test)
                if (compiler.facts[expression].flags & FACT_FALLS_THROUGH) == 0L {
                    frame.reachable = false
                    frame.cursor = -1L
                    compiler.work[frame_index] = frame
                }
            }
        } else if kind == NodeKind.ReturnStatement {
            let value = compiler.child_first[child]
            if value >= 0L {
                let redirect_return = is_aggregate_type(compiler, return_ty)
                let saved_destination_node = compiler.emit_destination_node
                let saved_destination_kind = compiler.emit_destination_kind
                let saved_destination_anchor = compiler.emit_destination_anchor
                if redirect_return {
                    compiler.emit_destination_node = value
                    compiler.emit_destination_kind = 2L
                    compiler.emit_destination_anchor = -1L
                }
                emit_expr_linear(source, files, tokens, tables, compiler, ir, value, file_index, return_ty, is_test)
                if redirect_return {
                    compiler.emit_destination_node = saved_destination_node
                    compiler.emit_destination_kind = saved_destination_kind
                    compiler.emit_destination_anchor = saved_destination_anchor
                }
                if (compiler.facts[value].flags & FACT_FALLS_THROUGH) == 0L {
                    frame.reachable = false
                    frame.cursor = -1L
                    compiler.work[frame_index] = frame
                } else if is_aggregate_type(compiler, return_ty) {
                    if !redirect_return {
                        let source_kind = aggregate_source_kind(tables, compiler, value)
                        let source_node = aggregate_source_id(tables, compiler, value)
                        emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(compiler, 2L, 0L), aggregate_source_location(compiler, source_kind, source_node))
                    }
                    lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L)
                } else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
                else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN_VALUE, 0L, 0L, return_ty, value) }
            } else if is_test { lower_scope_exit(compiler, ir, -1L, EXIT_TEST_FAILURE, 0L, 0L, TY_UNIT, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
            frame.reachable = false
            compiler.work[frame_index] = frame
        } else if kind == NodeKind.Block {
            // E3a1 subsection
            emit_region_scope_enter(files, tables, compiler, ir, child, file_index)
            // E3a1 subsection end
            compiler.work.push(CheckFrame { node: child, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[child], child0: node_last_child(tables, compiler, child), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.Expect {
            emit_expect_statement(source, files, tokens, tables, compiler, ir, child, file_index)
        } else if kind == NodeKind.If || (kind == NodeKind.ExpressionStatement && compiler.child_first[child] >= 0L && tables.nodes[compiler.child_first[child]].kind == NodeKind.If) {
            let if_node = if kind == NodeKind.If { child } else { compiler.child_first[child] }
            let condition = compiler.child_first[if_node]
            let then_block = compiler.child_next[condition]
            let else_block = compiler.child_next[then_block]
            emit_expr_linear(source, files, tokens, tables, compiler, ir, condition, file_index, return_ty, is_test)
            ir_write_ascii(compiler, ir, "  br i1 "); ir_write_value_ref(compiler, ir, condition); ir_write_ascii(compiler, ir, ", label %if.then."); ir_write_number(compiler, ir, if_node); ir_write_ascii(compiler, ir, ", label %")
            if else_block >= 0L { ir_write_ascii(compiler, ir, "if.else."); ir_write_number(compiler, ir, if_node) }
            else { ir_write_ascii(compiler, ir, "if.end."); ir_write_number(compiler, ir, if_node) }
            ir_write_ascii(compiler, ir, "\nif.then."); ir_write_number(compiler, ir, if_node); ir_write_ascii(compiler, ir, ":\n")
            // E3a1 subsection
            if then_block >= 0L && tables.nodes[then_block].kind == NodeKind.Block { emit_region_scope_enter(files, tables, compiler, ir, then_block, file_index) }
            // E3a1 subsection end
            compiler.work.push(CheckFrame { node: if_node, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 100L, cursor: -1L, child0: then_block, child1: else_block, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
            compiler.work.push(CheckFrame { node: then_block, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[then_block], child0: node_last_child(tables, compiler, then_block), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.For {
            var start = -1L
            var finish = -1L
            var loop_body = -1L
            var bound_index = 0L
            var loop_child = compiler.child_first[child]
            for child_step in 0L..tables.nodes[child].subtree {
                if loop_child < 0L { break }
                if tables.nodes[loop_child].kind == NodeKind.Block { loop_body = loop_child }
                else if tables.nodes[loop_child].kind != NodeKind.Annotation {
                    if bound_index == 0L { start = loop_child; bound_index += 1L }
                    else { finish = loop_child; bound_index += 1L }
                } else { () }
                loop_child = compiler.child_next[loop_child]
            }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, start, file_index, return_ty, is_test)
            emit_expr_linear(source, files, tokens, tables, compiler, ir, finish, file_index, return_ty, is_test)
            let binding = binding_for_node(compiler, child)
            let ty = compiler.bindings[binding].ty
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, start); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n  br label %for.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nfor.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n  %for.test."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n  %for.more."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = icmp s")
            if (tables.nodes[child].flags & FLAG_INCLUSIVE) != 0L { ir_write_ascii(compiler, ir, "le ") } else { ir_write_ascii(compiler, ir, "lt ") }
            ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %for.test."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, finish); ir_write_ascii(compiler, ir, "\n  br i1 %for.more."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", label %for.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", label %for.end."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nfor.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n")
            // E3a1 subsection
            compiler.emit_loops.push(EmitLoop { node: child, body: loop_body }).unwrap()
            if loop_body >= 0L && tables.nodes[loop_body].kind == NodeKind.Block { emit_region_scope_enter(files, tables, compiler, ir, loop_body, file_index) }
            // E3a1 subsection end
            compiler.work.push(CheckFrame { node: child, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 200L, cursor: -1L, child0: finish, child1: binding, child2: -1L, result_ty: ty, auxiliary: 1L, reachable: true }).unwrap()
            compiler.work.push(CheckFrame { node: loop_body, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[loop_body], child0: node_last_child(tables, compiler, loop_body), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.ForEach {
            let collection = compiler.child_first[child]
            let loop_body = if collection >= 0L { compiler.child_next[collection] } else { -1L }
            if collection < 0L || loop_body < 0L { compiler.ir_overflow = true; continue }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, collection, file_index, return_ty, is_test)
            let collection_type = compiler.facts[collection].ty
            let collection_kind = type_kind(compiler, collection_type)
            let capacity = collection_capacity(compiler, collection_type)
            let location = collection_value_location(tables, compiler, collection)
            let pointer = emit_location_pointer_materialization(compiler, ir, location)
            if collection_kind == TYPE_KIND_LIST {
                ir_write_ascii(compiler, ir, "  %for.each.count.ptr."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", i64 0\n  %for.each.count."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = load i64, ptr %for.each.count.ptr."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", align 1\n")
            } else if collection_kind == TYPE_KIND_ASCII || collection_kind == TYPE_KIND_BYTES {
                ir_write_ascii(compiler, ir, "  %for.each.count.ptr."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", i64 0\n  %for.each.count."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = load i64, ptr %for.each.count.ptr."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", align 1\n")
            } else {
                ir_write_ascii(compiler, ir, "  %for.each.count."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_number(compiler, ir, capacity); ir_push_byte(compiler, ir, 10)
            }
            ir_write_ascii(compiler, ir, "  store i64 0, ptr %for.each.index."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", align 8\n  br label %for.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nfor.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n  %for.each.current."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = load i64, ptr %for.each.index."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", align 8\n  %for.each.more."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = icmp ult i64 %for.each.current."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", %for.each.count."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\n  br i1 %for.each.more."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", label %for.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", label %for.end."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nfor.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n")
            let view_binding = compiler.facts[child].binding
            let view_scope = compiler.bindings[view_binding].scope
            if tables.nodes[child].aux > 0L {
                let index_token = tables.extra[tables.nodes[child].extra]
                let index_binding = find_binding_in_scope(compiler, view_scope, compiler.token_name_ids[index_token])
                if index_binding >= 0L { ir_write_ascii(compiler, ir, "  store i64 %for.each.current."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, index_binding); ir_write_ascii(compiler, ir, ", align 8\n") }
            }
            compiler.emit_loops.push(EmitLoop { node: child, body: loop_body }).unwrap()
            if tables.nodes[loop_body].kind == NodeKind.Block { emit_region_scope_enter(files, tables, compiler, ir, loop_body, file_index) }
            compiler.work.push(CheckFrame { node: child, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 210L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 1L, reachable: true }).unwrap()
            compiler.work.push(CheckFrame { node: loop_body, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[loop_body], child0: node_last_child(tables, compiler, loop_body), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.While {
            let condition = compiler.child_first[child]
            let loop_body = if condition >= 0L { compiler.child_next[condition] } else { -1L }
            if condition < 0L || loop_body < 0L { compiler.ir_overflow = true; continue }
            ir_write_ascii(compiler, ir, "  br label %while.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nwhile.cond."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n")
            emit_expr_linear(source, files, tokens, tables, compiler, ir, condition, file_index, return_ty, is_test)
            ir_write_ascii(compiler, ir, "  br i1 "); ir_write_value_ref(compiler, ir, condition); ir_write_ascii(compiler, ir, ", label %while.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", label %while.end."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, "\nwhile.body."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ":\n")
            compiler.emit_loops.push(EmitLoop { node: child, body: loop_body }).unwrap()
            if tables.nodes[loop_body].kind == NodeKind.Block { emit_region_scope_enter(files, tables, compiler, ir, loop_body, file_index) }
            compiler.work.push(CheckFrame { node: child, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 220L, cursor: -1L, child0: condition, child1: loop_body, child2: -1L, result_ty: -1L, auxiliary: 1L, reachable: true }).unwrap()
            compiler.work.push(CheckFrame { node: loop_body, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[loop_body], child0: node_last_child(tables, compiler, loop_body), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.BreakStatement || kind == NodeKind.ContinueStatement {
            let loop = compiler.emit_loops[compiler.emit_loops.count() - 1L]
            // E3a1 subsection
            emit_region_loop_exit(tables, compiler, ir, loop.body, child)
            // E3a1 subsection end
            let target_kind = if tables.nodes[loop.node].kind == NodeKind.While { 1L } else { 0L }
            if kind == NodeKind.BreakStatement { lower_scope_exit(compiler, ir, -1L, EXIT_BREAK, target_kind, loop.node, TY_UNIT, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_CONTINUE, target_kind, loop.node, TY_UNIT, -1L) }
            frame.reachable = false
            compiler.work[frame_index] = frame
        } else {
            compiler.internal_emit_error_kind = 1L
            compiler.internal_emit_error_node = child
            compiler.internal_emit_error_file = file_index
            compiler.ir_overflow = true
        }
    }
    body_falls
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_function_definition(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    function_id: long,
) {
    let function = compiler.functions[function_id]
    plan_function_regions(tables, compiler, function.body, function_id)
    if compiler.core_mode { ir_write_ascii(compiler, ir, "define internal ") }
    else { ir_write_ascii(compiler, ir, "define ") }
    if is_aggregate_type(compiler, function.result_ty) || function.result_ty == TY_UNIT || function.result_ty == TY_NEVER { ir_write_ascii(compiler, ir, "void") }
    else { ir_write_ascii(compiler, ir, llvm_type_name(function.result_ty)) }
    if compiler.core_mode {
        ir_push_byte(compiler, ir, 32)
        ir_write_core_function_symbol(source, files, tokens, compiler, ir, function, function_id)
        ir_push_byte(compiler, ir, 40)
    } else {
        ir_write_ascii(compiler, ir, " @nl_fn_")
        ir_write_number(compiler, ir, function_id)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top")
        if is_aggregate_type(compiler, function.result_ty) { ir_write_ascii(compiler, ir, ", "); emit_hidden_descriptor_parameter(compiler, ir) }
    }
    var wrote_parameter = !compiler.core_mode
    // E3a1 subsection: every context-taking core function receives its job context.
    if compiler.core_mode && core_function_has_context(source, tokens, files, function) {
        ir_write_ascii(compiler, ir, "ptr %nl.ctx")
        wrote_parameter = true
    }
    // E3a1 subsection end
    if compiler.core_mode && is_aggregate_type(compiler, function.result_ty) {
        if wrote_parameter { ir_write_ascii(compiler, ir, ", ") }
        emit_hidden_descriptor_parameter(compiler, ir)
        wrote_parameter = true
    }
    for parameter_index in 0L..function.param_count {
        let parameter = compiler.parameters[function.param_start + parameter_index]
        let binding = binding_for_node(compiler, parameter.node)
        if parameter.ty == TY_UNIT { continue }
        if wrote_parameter { ir_write_ascii(compiler, ir, ", ") }
        if is_aggregate_type(compiler, parameter.ty) || (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
            emit_location_parameter(compiler, ir, binding)
            wrote_parameter = true
            continue
        }
        ir_write_ascii(compiler, ir, llvm_type_name(parameter.ty)); ir_write_ascii(compiler, ir, " %arg."); ir_write_number(compiler, ir, binding)
        wrote_parameter = true
    }
    ir_write_ascii(compiler, ir, ")")
    if compiler.core_mode {
        if function.result_ty == TY_NEVER { ir_write_ascii(compiler, ir, " noreturn") }
        ir_write_ascii(compiler, ir, " nounwind")
        if files[function.file].name == b"memory.nl" { ir_write_ascii(compiler, ir, " \"no-builtins\"=\"true\"") }
    }
    ir_write_ascii(compiler, ir, " {\nentry:\n")
    // E3a1 subsection: context-free startup helpers must not capture a process
    // global. The null value only serves checked arithmetic's unreachable
    // fail edges; startup failures themselves use direct syscalls.
    if compiler.core_mode && !core_function_has_context(source, tokens, files, function) {
        ir_write_ascii(compiler, ir, "  %nl.ctx = inttoptr i64 0 to ptr\n")
    }
    // E3a1 subsection end
    let body_first = function.body - tables.nodes[function.body].subtree + 1L
    for node in 0L..tables.nodes.count() {
        if node < body_first || node > function.body { continue }
        emit_c_runtime_method_storage(source, files, tokens, tables, compiler, ir, node, function.file)
        if tables.nodes[node].kind == NodeKind.OptionalCall && compiler.facts[node].function >= 0L {
            let target = compiler.functions[compiler.facts[node].function]
            let receiver_parameter = compiler.parameters[target.param_start]
            let receiver_type = if parameter_uses_text_read_view(compiler, receiver_parameter) {
                sum_case_payload_type(compiler, compiler.facts[compiler.child_first[node]].ty, 0L, 0L)
            } else { receiver_parameter.ty }
            if receiver_type != TY_UNIT && is_aggregate_type(compiler, receiver_type) {
                let type_info = type_record(compiler, receiver_type)
                ir_write_ascii(compiler, ir, "  %optional.call.receiver.snapshot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, type_info.size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, type_info.align); ir_write_ascii(compiler, ir, "\n")
            }
        }
        if tables.nodes[node].kind == NodeKind.ForEach {
            ir_write_ascii(compiler, ir, "  %for.each.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n")
        }
        if tables.nodes[node].kind == NodeKind.Binary && (tables.nodes[node].flags == 14L || tables.nodes[node].flags == 15L) {
            ir_write_ascii(compiler, ir, "  %logic.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i1, align 1\n")
        }
        if tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 21L && compiler.facts[node].ty != TY_UNIT && !is_aggregate_type(compiler, compiler.facts[node].ty) {
            ir_write_ascii(compiler, ir, "  %coalesce.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if tables.nodes[node].kind == NodeKind.Call && token_is_word_at(source, tokens, files, function.file, tables.nodes[node].token, "fill") &&
            compiler.facts[node].function < 0L {
            ir_write_ascii(compiler, ir, "  %coll.fill.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n")
        }
        if tables.nodes[node].kind == NodeKind.If && compiler.facts[node].ty != TY_UNIT && compiler.facts[node].ty != TY_NEVER && !is_aggregate_type(compiler, compiler.facts[node].ty) {
            ir_write_ascii(compiler, ir, "  %if.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if (tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 4L) || (tables.nodes[node].kind == NodeKind.Assign && tables.nodes[node].flags == 5L) {
            let ty = if tables.nodes[node].kind == NodeKind.Binary { compiler.facts[node].ty } else { compiler.facts[compiler.child_first[node]].ty }
            ir_write_ascii(compiler, ir, "  %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if is_aggregate_type(compiler, compiler.facts[node].ty) && region_node_is_temporary(tables, compiler, node) && !region_has_slot(compiler, 0L, node) {
            let type_info = type_record(compiler, compiler.facts[node].ty)
            let size = type_info.size
            let alignment = type_info.align
            ir_write_ascii(compiler, ir, "  %agg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, alignment); ir_write_ascii(compiler, ir, "\n")
        }
    }
    for binding_id in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_id]
        if compiler.scopes[binding.scope].function_id == function_id && !binding_is_view(compiler, binding_id) && binding.ty != TY_UNIT && !(binding.parameter && (is_aggregate_type(compiler, binding.ty) || binding.mutable)) && !region_has_slot(compiler, 1L, binding_id) {
            ir_write_ascii(compiler, ir, "  %local.")
            ir_write_number(compiler, ir, binding_id)
            ir_write_ascii(compiler, ir, " = alloca ")
            if is_aggregate_type(compiler, binding.ty) {
            let type_info = type_record(compiler, binding.ty)
                ir_write_ascii(compiler, ir, "["); ir_write_number(compiler, ir, type_info.size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, type_info.align); ir_write_ascii(compiler, ir, "\n")
            } else {
                if binding.ty == TY_BOOL { ir_write_ascii(compiler, ir, "i8") } else { ir_write_ascii(compiler, ir, llvm_type_name(binding.ty)) }
                ir_write_ascii(compiler, ir, ", align 1\n")
            }
        }
    }
    for parameter_index in 0L..function.param_count {
        let parameter = compiler.parameters[function.param_start + parameter_index]
        if parameter.ty == TY_UNIT || is_aggregate_type(compiler, parameter.ty) || (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L { continue }
        let binding = binding_for_node(compiler, parameter.node)
        if parameter.ty == TY_BOOL {
            ir_write_ascii(compiler, ir, "  %arg.bool."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " = zext i1 %arg."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " to i8\n")
            ir_write_ascii(compiler, ir, "  store i8 %arg.bool."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
        } else {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(parameter.ty)); ir_write_ascii(compiler, ir, " %arg."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
        }
    }
    if !compiler.core_mode { emit_region_prologue(files, tables, compiler, ir, function.body, function.file) }
    compiler.memory_closure = compiler.core_mode && files[function.file].name == b"memory.nl"
    let _ = emit_function_body(source, files, tokens, tables, compiler, ir, function.body, function.file, function_id, function.result_ty, false, true, false)
    compiler.memory_closure = false
    ir_write_ascii(compiler, ir, "}\n\n")
    // E3a1 subsection: synthetic helpers emitted next do not inherit this frame's
    // region plan.
    if !compiler.core_mode { clear_function_regions(compiler) }
    // E3a1 subsection end
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_test_definition(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    test_index: long,
) {
    let test = compiler.tests[test_index]
    let function_id = compiler.functions.count() + test_index
    let scope_function_id = -1L - test_index
    plan_function_regions(tables, compiler, test.body, scope_function_id)
    ir_write_ascii(compiler, ir, "define i32 @nl_fn_")
    ir_write_number(compiler, ir, function_id)
    ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top) {\nentry:\n")
    let body_first = test.body - tables.nodes[test.body].subtree + 1L
    for node in 0L..tables.nodes.count() {
        if node < body_first || node > test.body { continue }
        emit_c_runtime_method_storage(source, files, tokens, tables, compiler, ir, node, test.file)
        if tables.nodes[node].kind == NodeKind.OptionalCall && compiler.facts[node].function >= 0L {
            let target = compiler.functions[compiler.facts[node].function]
            let receiver_parameter = compiler.parameters[target.param_start]
            let receiver_type = if parameter_uses_text_read_view(compiler, receiver_parameter) {
                sum_case_payload_type(compiler, compiler.facts[compiler.child_first[node]].ty, 0L, 0L)
            } else { receiver_parameter.ty }
            if receiver_type != TY_UNIT && is_aggregate_type(compiler, receiver_type) {
                let type_info = type_record(compiler, receiver_type)
                ir_write_ascii(compiler, ir, "  %optional.call.receiver.snapshot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, type_info.size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, type_info.align); ir_write_ascii(compiler, ir, "\n")
            }
        }
        if tables.nodes[node].kind == NodeKind.ForEach {
            ir_write_ascii(compiler, ir, "  %for.each.index."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n")
        }
        if tables.nodes[node].kind == NodeKind.Binary && (tables.nodes[node].flags == 14L || tables.nodes[node].flags == 15L) {
            ir_write_ascii(compiler, ir, "  %logic.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i1, align 1\n")
        }
        if tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 21L && compiler.facts[node].ty != TY_UNIT && !is_aggregate_type(compiler, compiler.facts[node].ty) {
            ir_write_ascii(compiler, ir, "  %coalesce.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if tables.nodes[node].kind == NodeKind.Call && token_is_word_at(source, tokens, files, test.file, tables.nodes[node].token, "fill") &&
            compiler.facts[node].function < 0L {
            ir_write_ascii(compiler, ir, "  %coll.fill.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i64, align 8\n")
        }
        if tables.nodes[node].kind == NodeKind.If && compiler.facts[node].ty != TY_UNIT && compiler.facts[node].ty != TY_NEVER && !is_aggregate_type(compiler, compiler.facts[node].ty) {
            ir_write_ascii(compiler, ir, "  %if.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if (tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 4L) || (tables.nodes[node].kind == NodeKind.Assign && tables.nodes[node].flags == 5L) {
            let ty = if tables.nodes[node].kind == NodeKind.Binary { compiler.facts[node].ty } else { compiler.facts[compiler.child_first[node]].ty }
            ir_write_ascii(compiler, ir, "  %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if is_aggregate_type(compiler, compiler.facts[node].ty) && region_node_is_temporary(tables, compiler, node) && !region_has_slot(compiler, 0L, node) {
            let type_info = type_record(compiler, compiler.facts[node].ty)
            let size = type_info.size
            let alignment = type_info.align
            ir_write_ascii(compiler, ir, "  %agg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, alignment); ir_write_ascii(compiler, ir, "\n")
        }
    }
    for binding_id in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_id]
        if compiler.scopes[binding.scope].function_id == scope_function_id && !binding_is_view(compiler, binding_id) && binding.ty != TY_UNIT && !binding.parameter && !region_has_slot(compiler, 1L, binding_id) {
            ir_write_ascii(compiler, ir, "  %local.")
            ir_write_number(compiler, ir, binding_id)
            ir_write_ascii(compiler, ir, " = alloca ")
            if is_aggregate_type(compiler, binding.ty) {
                let type_info = type_record(compiler, binding.ty)
                ir_write_ascii(compiler, ir, "["); ir_write_number(compiler, ir, type_info.size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, type_info.align); ir_write_ascii(compiler, ir, "\n")
            } else {
                if binding.ty == TY_BOOL { ir_write_ascii(compiler, ir, "i8") } else { ir_write_ascii(compiler, ir, llvm_type_name(binding.ty)) }
                ir_write_ascii(compiler, ir, ", align 1\n")
            }
        }
    }
    emit_region_prologue(files, tables, compiler, ir, test.body, test.file)
    let _ = emit_function_body(source, files, tokens, tables, compiler, ir, test.body, test.file, scope_function_id, TY_UNIT, true, true, false)
    ir_write_ascii(compiler, ir, "}\n\n")
    // E3a1 subsection: keep test region offsets local to this emitted function.
    clear_function_regions(compiler)
    // E3a1 subsection end
}
// E3a1 end

fn struct_has_defaults(compiler: CompilerTables, type_index: long) -> bool {
    let ty = struct_record(compiler, type_index)
    for offset in 0L..ty.field_count {
        if compiler.struct_fields[ty.field_start + offset].default_node >= 0L { return true }
    }
    false
}

fn has_type_helper(compiler: CompilerTables, type_id: long, operation: long) -> bool {
    if type_id < 0L || type_id >= type_count(compiler) { return false }
    let bit = if operation == HELPER_COPY { 1L }
        else if operation == HELPER_EQUAL { 2L }
        else if operation == HELPER_PRINT { 4L }
        else if operation == HELPER_FILL { 8L }
        else if operation == HELPER_DEFAULT { 16L }
        else { 0L }
    let mask = type_helper_mask(compiler, type_id)
    bit != 0L && (mask / bit) % 2L == 1L
}

fn register_type_helper(compiler: write CompilerTables, type_id: long, operation: long) {
    if type_id < 0L || type_id >= type_count(compiler) { return }
    let bit = if operation == HELPER_COPY { 1L }
        else if operation == HELPER_EQUAL { 2L }
        else if operation == HELPER_PRINT { 4L }
        else if operation == HELPER_FILL { 8L }
        else if operation == HELPER_DEFAULT { 16L }
        else { 0L }
    if bit != 0L && !has_type_helper(compiler, type_id, operation) {
        set_type_helper_mask(compiler, type_id, type_helper_mask(compiler, type_id) + bit)
    }
}

fn type_has_registered_helper(compiler: CompilerTables, type_id: long) -> bool {
    has_type_helper(compiler, type_id, HELPER_COPY) ||
        has_type_helper(compiler, type_id, HELPER_EQUAL) ||
        has_type_helper(compiler, type_id, HELPER_PRINT) ||
        has_type_helper(compiler, type_id, HELPER_FILL) ||
        has_type_helper(compiler, type_id, HELPER_DEFAULT)
}

fn register_exit_cleanup(compiler: write CompilerTables, scope_id: long, kind: long, owner: long) {
    compiler.exit_cleanups.push(ExitCleanupRecord { scope_id, kind, owner }).unwrap()
}

fn emit_registered_exit_cleanup(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    cleanup: ExitCleanupRecord,
) {
    // E2i registers none. The cleanup owner adds its kind here and keeps its
    // action payload in owner; unrecognized records fail closed meanwhile.
    if cleanup.kind != 0L { compiler.ir_overflow = true }
}

fn add_type_helper_flag(compiler: write CompilerTables, ty: long, flag: long) {
    if !is_aggregate_type(compiler, ty) { return }
    if flag == 1L { register_type_helper(compiler, ty, HELPER_COPY) }
    else if flag == 2L { register_type_helper(compiler, ty, HELPER_EQUAL) }
    else if flag == 4L { register_type_helper(compiler, ty, HELPER_PRINT) }
    else { () }
}

fn mark_struct_helpers(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for type_id in 0L..type_count(compiler) { set_type_helper_mask(compiler, type_id, 0L) }
    for type_index in 0L..struct_type_count(compiler) {
        if struct_has_defaults(compiler, type_index) {
            let type_id = struct_type_id(compiler, type_index)
            register_type_helper(compiler, type_id, HELPER_FILL)
            register_type_helper(compiler, type_id, HELPER_DEFAULT)
        }
    }
    for function_id in 0L..compiler.functions.count() {
        let result_ty = compiler.functions[function_id].result_ty
        add_type_helper_flag(compiler, result_ty, 1L)
    }
    for field_index in 0L..compiler.struct_fields.count() {
        let field = compiler.struct_fields[field_index]
        if field.default_node >= 0L && is_aggregate_type(compiler, field.ty) { add_type_helper_flag(compiler, field.ty, 1L) }
    }
    for node in 0L..tables.nodes.count() {
        let syntax = tables.nodes[node]
        if syntax.kind == NodeKind.Let {
            let binding = compiler.facts[node].binding
            if binding >= 0L {
                let ty = compiler.bindings[binding].ty
                add_type_helper_flag(compiler, ty, 1L)
            }
        } else if syntax.kind == NodeKind.Assign {
            let target = compiler.child_first[node]
            if target >= 0L {
                let ty = compiler.facts[target].ty
                add_type_helper_flag(compiler, ty, 1L)
            }
        } else if syntax.kind == NodeKind.Return || syntax.kind == NodeKind.ReturnStatement {
            let value = compiler.child_first[node]
            if value >= 0L {
                let ty = compiler.facts[value].ty
                add_type_helper_flag(compiler, ty, 1L)
            }
        } else if syntax.kind == NodeKind.InitializerField || syntax.kind == NodeKind.If || syntax.kind == NodeKind.Block {
            let ty = compiler.facts[node].ty
            add_type_helper_flag(compiler, ty, 1L)
        } else if syntax.kind == NodeKind.PatternBinding {
            let binding_ty = compiler.facts[node].ty
            add_type_helper_flag(compiler, binding_ty, 1L)
        } else if syntax.kind == NodeKind.Call || syntax.kind == NodeKind.QualifiedCase || syntax.kind == NodeKind.OptionalCall {
            let resolved_type = compiler.facts[node].ty
            let is_constructor = syntax.kind == NodeKind.QualifiedCase ||
                (syntax.kind == NodeKind.Call && compiler.facts[node].function < 0L && is_sum_type(compiler, resolved_type))
            let file_index = node_file_index(tables.nodes, files, node)
            let is_print = syntax.kind == NodeKind.Call && compiler.facts[node].function < 0L && !is_constructor &&
                token_is_word_at(source, tokens, files, file_index, syntax.token, "print")
            var argument = compiler.child_first[node]
            for argument_step in 0L..tables.nodes[node].subtree {
                if argument < 0L { break }
                let argument_ty = compiler.facts[argument].ty
                if is_aggregate_type(compiler, argument_ty) {
                    if is_print { add_type_helper_flag(compiler, argument_ty, 4L) }
                    else if is_constructor || tables.nodes[argument].kind == NodeKind.Name || tables.nodes[argument].kind == NodeKind.Field {
                        add_type_helper_flag(compiler, argument_ty, 1L)
                    } else { () }
                }
                argument = compiler.child_next[argument]
            }
        } else if syntax.kind == NodeKind.Binary && (syntax.flags == 8L || syntax.flags == 9L) {
            let left = compiler.child_first[node]
            let right = if left >= 0L { compiler.child_next[left] } else { -1L }
            if left >= 0L && is_aggregate_type(compiler, compiler.facts[left].ty) {
                let ty = compiler.facts[left].ty
                add_type_helper_flag(compiler, ty, 2L)
                if tables.nodes[left].kind == NodeKind.Name || tables.nodes[left].kind == NodeKind.Field { add_type_helper_flag(compiler, ty, 1L) }
                if right >= 0L && (tables.nodes[right].kind == NodeKind.Name || tables.nodes[right].kind == NodeKind.Field) { add_type_helper_flag(compiler, ty, 1L) }
            }
        } else if syntax.kind == NodeKind.Binary && syntax.flags == 21L {
            let result_ty = compiler.facts[node].ty
            add_type_helper_flag(compiler, result_ty, 1L)
        } else if syntax.kind == NodeKind.Try || syntax.kind == NodeKind.MethodCall || syntax.kind == NodeKind.OptionalCall || syntax.kind == NodeKind.Match {
            let result_ty = compiler.facts[node].ty
            add_type_helper_flag(compiler, result_ty, 1L)
        } else { () }
        if syntax.kind == NodeKind.Expect {
            let expression = compiler.child_first[node]
            if expression >= 0L && tables.nodes[expression].kind == NodeKind.Binary && tables.nodes[expression].flags >= 8L && tables.nodes[expression].flags <= 13L {
                let left = compiler.child_first[expression]
                if left >= 0L {
                    let ty = compiler.facts[left].ty
                    add_type_helper_flag(compiler, ty, 4L)
                }
            }
        }
    }
    for pass in 0L..type_count(compiler) {
        for type_id in 0L..type_count(compiler) {
            if type_kind(compiler, type_id) == TYPE_KIND_STRUCT {
                let type_info = type_record(compiler, type_id)
                for offset in 0L..type_info.field_count {
                    let child_ty = compiler.struct_fields[type_info.field_start + offset].ty
                    if !is_aggregate_type(compiler, child_ty) { continue }
                    if has_type_helper(compiler, type_id, HELPER_COPY) { register_type_helper(compiler, child_ty, HELPER_COPY) }
                    if has_type_helper(compiler, type_id, HELPER_EQUAL) { register_type_helper(compiler, child_ty, HELPER_EQUAL) }
                    if has_type_helper(compiler, type_id, HELPER_PRINT) { register_type_helper(compiler, child_ty, HELPER_PRINT) }
                }
            } else if type_kind(compiler, type_id) == TYPE_KIND_ENUM {
                let type_info = type_record(compiler, type_id)
                for case_offset in 0L..type_info.field_count {
                    let case = compiler.enum_cases[type_info.field_start + case_offset]
                    for part_offset in 0L..case.payload_count {
                        let child_ty = compiler.enum_payloads[case.payload_start + part_offset].ty
                        if !is_aggregate_type(compiler, child_ty) { continue }
                        if has_type_helper(compiler, type_id, HELPER_COPY) { register_type_helper(compiler, child_ty, HELPER_COPY) }
                        if has_type_helper(compiler, type_id, HELPER_EQUAL) { register_type_helper(compiler, child_ty, HELPER_EQUAL) }
                        if has_type_helper(compiler, type_id, HELPER_PRINT) { register_type_helper(compiler, child_ty, HELPER_PRINT) }
                    }
                }
            } else if type_kind(compiler, type_id) == TYPE_KIND_ARRAY || type_kind(compiler, type_id) == TYPE_KIND_LIST {
                let child_ty = collection_element_type(compiler, type_id)
                if type_kind(compiler, child_ty) == TYPE_KIND_STRUCT {
                    let element = type_record(compiler, child_ty)
                    for field_offset in 0L..element.field_count {
                        let field_ty = compiler.struct_fields[element.field_start + field_offset].ty
                        if type_kind(compiler, field_ty) == TYPE_KIND_BYTES {
                            // Collection operations can copy, compare, or
                            // print a direct Bytes leaf even when no whole-
                            // collection helper is otherwise requested.
                            register_type_helper(compiler, field_ty, HELPER_COPY)
                            register_type_helper(compiler, field_ty, HELPER_EQUAL)
                            register_type_helper(compiler, field_ty, HELPER_PRINT)
                        }
                    }
                }
                if is_aggregate_type(compiler, child_ty) {
                    if has_type_helper(compiler, type_id, HELPER_COPY) { register_type_helper(compiler, child_ty, HELPER_COPY) }
                    if has_type_helper(compiler, type_id, HELPER_EQUAL) { register_type_helper(compiler, child_ty, HELPER_EQUAL) }
                    if has_type_helper(compiler, type_id, HELPER_PRINT) { register_type_helper(compiler, child_ty, HELPER_PRINT) }
                }
            } else { () }
        }
    }
}

fn propagate_sum_type_helpers(compiler: write CompilerTables) {
    for pass in 0L..type_count(compiler) {
        for type_id in 0L..type_count(compiler) {
            let kind = type_kind(compiler, type_id)
            if kind != TYPE_KIND_OPTION && kind != TYPE_KIND_RESULT { continue }
            for tag in 0L..2L {
                let part_count = sum_case_payload_count(compiler, type_id, tag)
                for part in 0L..part_count {
                    let child_ty = sum_case_payload_type(compiler, type_id, tag, part)
                    if !is_aggregate_type(compiler, child_ty) { continue }
                    if has_type_helper(compiler, type_id, HELPER_COPY) { register_type_helper(compiler, child_ty, HELPER_COPY) }
                    if has_type_helper(compiler, type_id, HELPER_EQUAL) { register_type_helper(compiler, child_ty, HELPER_EQUAL) }
                    if has_type_helper(compiler, type_id, HELPER_PRINT) { register_type_helper(compiler, child_ty, HELPER_PRINT) }
                }
            }
        }
    }
}

fn emit_enum_copy_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for enum_index in 0L..enum_type_count(compiler) {
        let ty = enum_record(compiler, enum_index)
        let type_id = enum_type_id(compiler, enum_index)
        if !has_type_helper(compiler, type_id, HELPER_COPY) { continue }
        let tag_source = MAX_TREE_NODES * 20L + type_id * 2L
        let tag_dest = tag_source + 1L
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 4L, 0L, 0L)); ir_write_ascii(compiler, ir, ", ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 5L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, tag_source, compiler_location(compiler, 5L, 0L, 0L))
        emit_layout_address(compiler, ir, tag_dest, compiler_location(compiler, 4L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %copy.tag."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_source); ir_write_ascii(compiler, ir, ", align 1\n  store i32 %copy.tag."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, tag_dest); ir_write_ascii(compiler, ir, ", align 1\n  switch i32 %copy.tag."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %copy.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " [\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "    i32 "); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ", label %copy.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "copy.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ":\n")
            for part_offset in 0L..case.payload_count {
                let payload_index = case.payload_start + part_offset
                let payload = compiler.enum_payloads[payload_index]
                if payload.ty == TY_UNIT { continue }
                let dest_address = MAX_TREE_NODES * 20L + type_count(compiler) * 2L + payload_index * 2L
                let source_address = dest_address + 1L
                emit_layout_address(compiler, ir, dest_address, compiler_location(compiler, 4L, 0L, payload.offset))
                emit_layout_address(compiler, ir, source_address, compiler_location(compiler, 5L, 0L, payload.offset))
                if is_aggregate_type(compiler, payload.ty) {
                    let destination = compiler_location(compiler, 2L, dest_address, 0L)
                    let source = compiler_location(compiler, 2L, source_address, 0L)
                    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
                    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
                    ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_two(compiler, ir, payload.ty, HELPER_COPY, destination, source, destination_pointer, source_pointer); ir_push_byte(compiler, ir, 10)
                } else {
                    let storage_type: Ascii max 8 = if payload.ty == TY_BOOL { "i8" } else { llvm_type_name(payload.ty) }
                    ir_write_ascii(compiler, ir, "  %copy.value."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, " %copy.value."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, dest_address); ir_write_ascii(compiler, ir, ", align 1\n")
                }
            }
            ir_write_ascii(compiler, ir, "  br label %copy.end."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "copy.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\ncopy.end."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret void\n}\n\n")
    }
}

fn emit_enum_equal_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for enum_index in 0L..enum_type_count(compiler) {
        let ty = enum_record(compiler, enum_index)
        let type_id = enum_type_id(compiler, enum_index)
        if !has_type_helper(compiler, type_id, HELPER_EQUAL) { continue }
        let left_tag = MAX_TREE_NODES * 30L + type_id * 2L
        let right_tag = left_tag + 1L
        ir_write_ascii(compiler, ir, "define internal i1 "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_EQUAL); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 6L, 0L, 0L)); ir_write_ascii(compiler, ir, ", ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 7L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, left_tag, compiler_location(compiler, 6L, 0L, 0L))
        emit_layout_address(compiler, ir, right_tag, compiler_location(compiler, 7L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %eq.tag.left."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, left_tag); ir_write_ascii(compiler, ir, ", align 1\n  %eq.tag.right."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, right_tag); ir_write_ascii(compiler, ir, ", align 1\n  %eq.tag.same."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = icmp eq i32 %eq.tag.left."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", %eq.tag.right."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\n  br i1 %eq.tag.same."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %eq.dispatch."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %eq.false."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, "\neq.dispatch."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  switch i32 %eq.tag.left."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %eq.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " [\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "    i32 "); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ", label %eq.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "eq.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ":\n")
            for part_offset in 0L..case.payload_count {
                let payload_index = case.payload_start + part_offset
                let payload = compiler.enum_payloads[payload_index]
                if payload.ty == TY_UNIT { continue }
                let left_address = MAX_TREE_NODES * 30L + type_count(compiler) * 2L + payload_index * 2L
                let right_address = left_address + 1L
                emit_layout_address(compiler, ir, left_address, compiler_location(compiler, 6L, 0L, payload.offset))
                emit_layout_address(compiler, ir, right_address, compiler_location(compiler, 7L, 0L, payload.offset))
                if is_aggregate_type(compiler, payload.ty) {
                    let left_location = compiler_location(compiler, 2L, left_address, 0L)
                    let right_location = compiler_location(compiler, 2L, right_address, 0L)
                    let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
                    let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
                    ir_write_ascii(compiler, ir, "  %eq.part."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = call i1 "); emit_type_helper_call_two(compiler, ir, payload.ty, HELPER_EQUAL, left_location, right_location, left_pointer, right_pointer); ir_push_byte(compiler, ir, 10)
                } else {
                    let storage_type: Ascii max 8 = if payload.ty == TY_BOOL { "i8" } else { llvm_type_name(payload.ty) }
                    ir_write_ascii(compiler, ir, "  %eq.left."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, left_address); ir_write_ascii(compiler, ir, ", align 1\n  %eq.right."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, right_address); ir_write_ascii(compiler, ir, ", align 1\n  %eq.part."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, " %eq.left."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, ", %eq.right."); ir_write_number(compiler, ir, payload_index); ir_push_byte(compiler, ir, 10)
                }
                ir_write_ascii(compiler, ir, "  br i1 %eq.part."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, ", label %eq.next."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, part_offset); ir_write_ascii(compiler, ir, ", label %eq.false."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 10)
                ir_write_ascii(compiler, ir, "eq.next."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, part_offset); ir_write_ascii(compiler, ir, ":\n")
            }
            ir_write_ascii(compiler, ir, "  ret i1 true\n")
        }
        ir_write_ascii(compiler, ir, "eq.false."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret i1 false\neq.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\n}\n\n")
    }
}


// E3a1 begin: shared compiler integration.
fn emit_struct_copy_helpers(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_COPY) { continue }
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); emit_location_argument(compiler, ir, compiler_location(compiler, 4L, 0L, 0L)); ir_write_ascii(compiler, ir, ", "); emit_location_argument(compiler, ir, compiler_location(compiler, 5L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        // E3a2: beyond the 64-byte inline tier, use the core's tuned generic
        // copy for plain structs. Collections and Bytes fields must keep
        // dispatching through their field helpers so only live values are read.
        let plain_large_copy = ty.size > 64L && !type_contains_collection(compiler, type_id, 0L) &&
            !type_contains_bytes(compiler, type_id, 0L)
        if plain_large_copy {
            let destination = compiler_location(compiler, 4L, 0L, 0L)
            let source = compiler_location(compiler, 5L, 0L, 0L)
            let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
            let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
            ir_write_ascii(compiler, ir, "  %copy.bulk."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = call ptr @memcpy(ptr ")
            emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
            ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, source, source_pointer)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, ty.size); ir_write_ascii(compiler, ir, ")\n  ret void\n}\n\n")
            continue
        }
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if field.ty == TY_UNIT { continue }
            let dest_address = MAX_TREE_NODES * 2L + field_index * 2L
            let source_address = dest_address + 1L
            emit_layout_address(compiler, ir, dest_address, compiler_location(compiler, 4L, 0L, field.offset))
            emit_layout_address(compiler, ir, source_address, compiler_location(compiler, 5L, 0L, field.offset))
            if is_aggregate_type(compiler, field.ty) {
                let destination = compiler_location(compiler, 2L, dest_address, 0L)
                let source = compiler_location(compiler, 2L, source_address, 0L)
                let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
                let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
                ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_two(compiler, ir, field.ty, HELPER_COPY, destination, source, destination_pointer, source_pointer); ir_push_byte(compiler, ir, 10)
            } else {
                let storage_type: Ascii max 8 = if field.ty == TY_BOOL { "i8" } else { llvm_type_name(field.ty) }
                ir_write_ascii(compiler, ir, "  %copy.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, " %copy.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, dest_address); ir_write_ascii(compiler, ir, ", align 1\n")
            }
        }
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_struct_eq_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_EQUAL) { continue }
        ir_write_ascii(compiler, ir, "define internal i1 "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_EQUAL); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); emit_location_argument(compiler, ir, compiler_location(compiler, 6L, 0L, 0L)); ir_write_ascii(compiler, ir, ", "); emit_location_argument(compiler, ir, compiler_location(compiler, 7L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        var previous = -1L
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if field.ty == TY_UNIT { continue }
            let left_address = MAX_TREE_NODES * 3L + field_index * 2L
            let right_address = left_address + 1L
            emit_layout_address(compiler, ir, left_address, compiler_location(compiler, 6L, 0L, field.offset))
            emit_layout_address(compiler, ir, right_address, compiler_location(compiler, 7L, 0L, field.offset))
            if is_aggregate_type(compiler, field.ty) {
                let left_location = compiler_location(compiler, 2L, left_address, 0L)
                let right_location = compiler_location(compiler, 2L, right_address, 0L)
                let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
                let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
                ir_write_ascii(compiler, ir, "  %eq.raw."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = call i1 "); emit_type_helper_call_two(compiler, ir, field.ty, HELPER_EQUAL, left_location, right_location, left_pointer, right_pointer); ir_push_byte(compiler, ir, 10)
            } else {
                let storage_type: Ascii max 8 = if field.ty == TY_BOOL { "i8" } else { llvm_type_name(field.ty) }
                ir_write_ascii(compiler, ir, "  %eq.left."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, left_address); ir_write_ascii(compiler, ir, ", align 1\n  %eq.right."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, right_address); ir_write_ascii(compiler, ir, ", align 1\n  %eq.raw."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, " %eq.left."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", %eq.right."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\n")
            }
            ir_write_ascii(compiler, ir, "  %eq.acc."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = and i1 ")
            if previous < 0L { ir_write_ascii(compiler, ir, "true") }
            else { ir_write_ascii(compiler, ir, "%eq.acc."); ir_write_number(compiler, ir, previous) }
            ir_write_ascii(compiler, ir, ", %eq.raw."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\n")
            previous = field_index
        }
        ir_write_ascii(compiler, ir, "  ret i1 ")
        if previous < 0L { ir_write_ascii(compiler, ir, "true\n") }
        else { ir_write_ascii(compiler, ir, "%eq.acc."); ir_write_number(compiler, ir, previous); ir_write_ascii(compiler, ir, "\n") }
        ir_write_ascii(compiler, ir, "}\n\n")
    }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_struct_print_text_call(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    kind: Ascii max 16,
    index: long,
    length: long,
) {
    ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_ascii", "nlc_print_ascii"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr getelementptr inbounds (["); ir_write_number(compiler, ir, length + 1L); ir_write_ascii(compiler, ir, " x i8], ptr @.nl.struct."); ir_write_ascii(compiler, ir, kind); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, index); ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 "); ir_write_number(compiler, ir, length); ir_write_ascii(compiler, ir, ")\n")
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_struct_print_helpers(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_PRINT) { continue }
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_PRINT); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); emit_location_argument(compiler, ir, compiler_location(compiler, 8L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_struct_print_text_call(compiler, ir, "type", type_index, tokens[ty.name_token].length)
        emit_struct_print_text_call(compiler, ir, "open", 0L, 3L)
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if offset > 0L { emit_struct_print_text_call(compiler, ir, "separator", 0L, 2L) }
            emit_struct_print_text_call(compiler, ir, "field", field_index, tokens[field.name_token].length)
            emit_struct_print_text_call(compiler, ir, "colon", 0L, 2L)
            let address = MAX_TREE_NODES * 5L + field_index
            emit_layout_address(compiler, ir, address, compiler_location(compiler, 8L, 0L, field.offset))
            if is_aggregate_type(compiler, field.ty) {
                let location = compiler_location(compiler, 2L, address, 0L)
                let pointer = emit_location_pointer_materialization(compiler, ir, location)
                ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_one(compiler, ir, field.ty, HELPER_PRINT, location, pointer); ir_push_byte(compiler, ir, 10)
            } else if field.ty == TY_BOOL {
                ir_write_ascii(compiler, ir, "  %print.bool.byte."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n  %print.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = trunc i8 %print.bool.byte."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " to i1\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_bool_raw", "nlc_print_bool_raw"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i1 zeroext %print.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ")\n")
            } else {
                ir_write_ascii(compiler, ir, "  %print.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(field.ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n  call void "); emit_context_runtime_symbol(compiler, ir, if field.ty == TY_LONG { "nl_print_long_raw" } else { "nl_print_int_raw" }, if field.ty == TY_LONG { "nlc_print_long_raw" } else { "nlc_print_int_raw" }); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); ir_write_ascii(compiler, ir, llvm_type_name(field.ty)); ir_write_ascii(compiler, ir, " %print.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ")\n")
            }
        }
        emit_struct_print_text_call(compiler, ir, "close", 0L, 2L)
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}
// E3a1 end

fn emit_enum_text_call(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    prefix: Ascii max 32,
    index: long,
    length: long,
) {
    ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_ascii", "nlc_print_ascii"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr getelementptr inbounds (["); ir_write_number(compiler, ir, length + 1L); ir_write_ascii(compiler, ir, " x i8], ptr @.nl.enum."); ir_write_ascii(compiler, ir, prefix); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, index); ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 "); ir_write_number(compiler, ir, length); ir_write_ascii(compiler, ir, ")\n")
}

fn emit_enum_print_helpers(
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for enum_index in 0L..enum_type_count(compiler) {
        let ty = enum_record(compiler, enum_index)
        let type_id = enum_type_id(compiler, enum_index)
        if !has_type_helper(compiler, type_id, HELPER_PRINT) { continue }
        let tag_address = MAX_TREE_NODES * 40L + type_id
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_PRINT); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); emit_location_argument(compiler, ir, compiler_location(compiler, 8L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, tag_address, compiler_location(compiler, 8L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %print.tag."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address); ir_write_ascii(compiler, ir, ", align 1\n  switch i32 %print.tag."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ", label %print.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, " [\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "    i32 "); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ", label %print.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for case_offset in 0L..ty.field_count {
            let case = compiler.enum_cases[ty.field_start + case_offset]
            ir_write_ascii(compiler, ir, "print.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, case.tag); ir_write_ascii(compiler, ir, ":\n")
            if case.name_token < 0L {
                emit_sum_builtin_text_call(compiler, ir, "Full", 4L)
            } else {
                emit_enum_text_call(compiler, ir, "case", ty.field_start + case_offset, tokens[case.name_token].length)
            }
            if case.payload_count > 0L {
                emit_enum_text_call(compiler, ir, "open", 0L, 1L)
                for part_offset in 0L..case.payload_count {
                    let payload_index = case.payload_start + part_offset
                    let payload = compiler.enum_payloads[payload_index]
                    if part_offset > 0L { emit_enum_text_call(compiler, ir, "separator", 0L, 2L) }
                    if payload.ty == TY_UNIT {
                        emit_enum_text_call(compiler, ir, "unit", 0L, 2L)
                    } else {
                        let address = MAX_TREE_NODES * 40L + type_count(compiler) + payload_index
                        emit_layout_address(compiler, ir, address, compiler_location(compiler, 8L, 0L, payload.offset))
                        if is_aggregate_type(compiler, payload.ty) {
                            let location = compiler_location(compiler, 2L, address, 0L)
                            let pointer = emit_location_pointer_materialization(compiler, ir, location)
                            ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_one(compiler, ir, payload.ty, HELPER_PRINT, location, pointer); ir_push_byte(compiler, ir, 10)
                        } else if payload.ty == TY_BOOL {
                            ir_write_ascii(compiler, ir, "  %print.bool.byte."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n  %print.bool."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = trunc i8 %print.bool.byte."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " to i1\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_bool_raw", "nlc_print_bool_raw"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i1 zeroext %print.bool."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, ")\n")
                        } else {
                            ir_write_ascii(compiler, ir, "  %print.value."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n  call void "); emit_context_runtime_symbol(compiler, ir, if payload.ty == TY_LONG { "nl_print_long_raw" } else { "nl_print_int_raw" }, if payload.ty == TY_LONG { "nlc_print_long_raw" } else { "nlc_print_int_raw" }); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty)); ir_write_ascii(compiler, ir, " %print.value."); ir_write_number(compiler, ir, payload_index); ir_write_ascii(compiler, ir, ")\n")
                        }
                    }
                }
                emit_enum_text_call(compiler, ir, "close", 0L, 1L)
            }
            ir_write_ascii(compiler, ir, "  ret void\n")
        }
        ir_write_ascii(compiler, ir, "print.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\n}\n\n")
    }
}

fn emit_sum_builtin_text_call(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    word: Ascii max 16,
    length: long,
) {
    ir_write_ascii(compiler, ir, "  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_ascii", "nlc_print_ascii"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr getelementptr inbounds ([")
    ir_write_number(compiler, ir, length + 1L)
    ir_write_ascii(compiler, ir, " x i8], ptr @.nl.sum.")
    ir_write_ascii(compiler, ir, word)
    ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
    ir_write_number(compiler, ir, length)
    ir_write_ascii(compiler, ir, ")\n")
}

fn emit_sum_copy_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_id in 0L..type_count(compiler) {
        let kind = type_kind(compiler, type_id)
        if (kind != TYPE_KIND_OPTION && kind != TYPE_KIND_RESULT) || !has_type_helper(compiler, type_id, HELPER_COPY) { continue }
        let source_tag_address = MAX_TREE_NODES * 50L + type_id * 2L
        let dest_tag_address = source_tag_address + 1L
        ir_write_ascii(compiler, ir, "define internal void ")
        emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 4L, 0L, 0L))
        ir_write_ascii(compiler, ir, ", ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 5L, 0L, 0L))
        ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, source_tag_address, compiler_location(compiler, 5L, 0L, 0L))
        emit_layout_address(compiler, ir, dest_tag_address, compiler_location(compiler, 4L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %sum.copy.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, source_tag_address)
        ir_write_ascii(compiler, ir, ", align 1\n  store i32 %sum.copy.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, dest_tag_address)
        ir_write_ascii(compiler, ir, ", align 1\n  switch i32 %sum.copy.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %sum.copy.invalid."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " [\n    i32 0, label %sum.copy.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".0\n    i32 1, label %sum.copy.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".1\n  ]\n")
        for tag in 0L..2L {
            ir_write_ascii(compiler, ir, "sum.copy.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ":\n")
            let part_count = sum_case_payload_count(compiler, type_id, tag)
            for part in 0L..part_count {
                let payload = sum_payload_record(compiler, type_id, tag, part)
                if payload.ty == TY_UNIT { continue }
                let dest_address = MAX_TREE_NODES * 50L + type_count(compiler) * 3L + payload.case_index * 2L + type_id * 2L
                let source_address = dest_address + 1L
                emit_layout_address(compiler, ir, dest_address, compiler_location(compiler, 4L, 0L, payload.offset))
                emit_layout_address(compiler, ir, source_address, compiler_location(compiler, 5L, 0L, payload.offset))
                if is_aggregate_type(compiler, payload.ty) {
                    let destination = compiler_location(compiler, 2L, dest_address, 0L)
                    let source = compiler_location(compiler, 2L, source_address, 0L)
                    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
                    let source_pointer = emit_location_pointer_materialization(compiler, ir, source)
                    ir_write_ascii(compiler, ir, "  call void ")
                    emit_type_helper_call_two(compiler, ir, payload.ty, HELPER_COPY, destination, source, destination_pointer, source_pointer)
                    ir_push_byte(compiler, ir, 10)
                } else {
                    let storage_type: Ascii max 8 = if payload.ty == TY_BOOL { "i8" } else { llvm_type_name(payload.ty) }
                    ir_write_ascii(compiler, ir, "  %sum.copy.value."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type)
                    ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address)
                    ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage_type)
                    ir_write_ascii(compiler, ir, " %sum.copy.value."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, dest_address)
                    ir_write_ascii(compiler, ir, ", align 1\n")
                }
            }
            ir_write_ascii(compiler, ir, "  br label %sum.copy.end."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 10)
        }
        ir_write_ascii(compiler, ir, "sum.copy.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\nsum.copy.end.")
        ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret void\n}\n\n")
    }
}

fn emit_sum_equal_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_id in 0L..type_count(compiler) {
        let kind = type_kind(compiler, type_id)
        if (kind != TYPE_KIND_OPTION && kind != TYPE_KIND_RESULT) || !has_type_helper(compiler, type_id, HELPER_EQUAL) { continue }
        let left_tag_address = MAX_TREE_NODES * 51L + type_id * 2L
        let right_tag_address = left_tag_address + 1L
        ir_write_ascii(compiler, ir, "define internal i1 ")
        emit_type_helper_symbol(compiler, ir, type_id, HELPER_EQUAL)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 6L, 0L, 0L))
        ir_write_ascii(compiler, ir, ", ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 7L, 0L, 0L))
        ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, left_tag_address, compiler_location(compiler, 6L, 0L, 0L))
        emit_layout_address(compiler, ir, right_tag_address, compiler_location(compiler, 7L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %sum.eq.left.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, left_tag_address)
        ir_write_ascii(compiler, ir, ", align 1\n  %sum.eq.right.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, right_tag_address)
        ir_write_ascii(compiler, ir, ", align 1\n  %sum.eq.same.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = icmp eq i32 %sum.eq.left.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", %sum.eq.right.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, "\n  br i1 %sum.eq.same.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %sum.eq.dispatch."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %sum.eq.false."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, "\nsum.eq.dispatch."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ":\n  switch i32 %sum.eq.left.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %sum.eq.invalid."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " [\n    i32 0, label %sum.eq.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".0\n    i32 1, label %sum.eq.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".1\n  ]\n")
        for tag in 0L..2L {
            ir_write_ascii(compiler, ir, "sum.eq.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ":\n")
            let part_count = sum_case_payload_count(compiler, type_id, tag)
            for part in 0L..part_count {
                let payload = sum_payload_record(compiler, type_id, tag, part)
                if payload.ty == TY_UNIT { continue }
                let left_address = MAX_TREE_NODES * 51L + type_count(compiler) * 2L + payload.case_index * 2L + type_id * 2L
                let right_address = left_address + 1L
                emit_layout_address(compiler, ir, left_address, compiler_location(compiler, 6L, 0L, payload.offset))
                emit_layout_address(compiler, ir, right_address, compiler_location(compiler, 7L, 0L, payload.offset))
                if is_aggregate_type(compiler, payload.ty) {
                    let left_location = compiler_location(compiler, 2L, left_address, 0L)
                    let right_location = compiler_location(compiler, 2L, right_address, 0L)
                    let left_pointer = emit_location_pointer_materialization(compiler, ir, left_location)
                    let right_pointer = emit_location_pointer_materialization(compiler, ir, right_location)
                    ir_write_ascii(compiler, ir, "  %sum.eq.part."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, " = call i1 ")
                    emit_type_helper_call_two(compiler, ir, payload.ty, HELPER_EQUAL, left_location, right_location, left_pointer, right_pointer)
                    ir_push_byte(compiler, ir, 10)
                } else {
                    let storage_type: Ascii max 8 = if payload.ty == TY_BOOL { "i8" } else { llvm_type_name(payload.ty) }
                    ir_write_ascii(compiler, ir, "  %sum.eq.left."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type)
                    ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, left_address)
                    ir_write_ascii(compiler, ir, ", align 1\n  %sum.eq.right."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type)
                    ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, right_address)
                    ir_write_ascii(compiler, ir, ", align 1\n  %sum.eq.part."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, storage_type)
                    ir_write_ascii(compiler, ir, " %sum.eq.left."); ir_write_number(compiler, ir, payload.case_index)
                    ir_write_ascii(compiler, ir, ", %sum.eq.right."); ir_write_number(compiler, ir, payload.case_index); ir_push_byte(compiler, ir, 10)
                }
                ir_write_ascii(compiler, ir, "  br i1 %sum.eq.part."); ir_write_number(compiler, ir, payload.case_index)
                ir_write_ascii(compiler, ir, ", label %sum.eq.next."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, part)
                ir_write_ascii(compiler, ir, ", label %sum.eq.false."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 10)
                ir_write_ascii(compiler, ir, "sum.eq.next."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, part); ir_write_ascii(compiler, ir, ":\n")
            }
            ir_write_ascii(compiler, ir, "  ret i1 true\n")
        }
        ir_write_ascii(compiler, ir, "sum.eq.false."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  ret i1 false\nsum.eq.invalid.")
        ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\n}\n\n")
    }
}

fn emit_sum_print_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_id in 0L..type_count(compiler) {
        let kind = type_kind(compiler, type_id)
        if (kind != TYPE_KIND_OPTION && kind != TYPE_KIND_RESULT) || !has_type_helper(compiler, type_id, HELPER_PRINT) { continue }
        let tag_address = MAX_TREE_NODES * 52L + type_id
        ir_write_ascii(compiler, ir, "define internal void ")
        emit_type_helper_symbol(compiler, ir, type_id, HELPER_PRINT)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ")
        emit_location_argument(compiler, ir, compiler_location(compiler, 8L, 0L, 0L))
        ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_layout_address(compiler, ir, tag_address, compiler_location(compiler, 8L, 0L, 0L))
        ir_write_ascii(compiler, ir, "  %sum.print.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " = load i32, ptr %addr."); ir_write_number(compiler, ir, tag_address)
        ir_write_ascii(compiler, ir, ", align 1\n  switch i32 %sum.print.tag."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ", label %sum.print.invalid."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, " [\n    i32 0, label %sum.print.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".0\n    i32 1, label %sum.print.case."); ir_write_number(compiler, ir, type_id)
        ir_write_ascii(compiler, ir, ".1\n  ]\n")
        for tag in 0L..2L {
            ir_write_ascii(compiler, ir, "sum.print.case."); ir_write_number(compiler, ir, type_id); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ":\n")
            let word: Ascii max 16 = if kind == TYPE_KIND_OPTION && tag == 0L { "some" }
                else if kind == TYPE_KIND_OPTION { "none" }
                else if tag == 0L { "ok" } else { "err" }
            let word_length = if kind == TYPE_KIND_OPTION { 4L } else if tag == 0L { 2L } else { 3L }
            emit_sum_builtin_text_call(compiler, ir, word, word_length)
            let part_count = sum_case_payload_count(compiler, type_id, tag)
            if part_count > 0L {
                emit_sum_builtin_text_call(compiler, ir, "lparen", 1L)
                for part in 0L..part_count {
                    let payload = sum_payload_record(compiler, type_id, tag, part)
                    if part > 0L { emit_sum_builtin_text_call(compiler, ir, "separator", 2L) }
                    if payload.ty == TY_UNIT { emit_sum_builtin_text_call(compiler, ir, "unit", 2L) }
                    else {
                        let address = MAX_TREE_NODES * 52L + type_count(compiler) + payload.case_index
                        emit_layout_address(compiler, ir, address, compiler_location(compiler, 8L, 0L, payload.offset))
                        if is_aggregate_type(compiler, payload.ty) {
                            let location = compiler_location(compiler, 2L, address, 0L)
                            let pointer = emit_location_pointer_materialization(compiler, ir, location)
                            ir_write_ascii(compiler, ir, "  call void ")
                            emit_type_helper_call_one(compiler, ir, payload.ty, HELPER_PRINT, location, pointer)
                            ir_push_byte(compiler, ir, 10)
                        } else if payload.ty == TY_BOOL {
                            ir_write_ascii(compiler, ir, "  %sum.print.bool.byte."); ir_write_number(compiler, ir, payload.case_index)
                            ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, address)
                            ir_write_ascii(compiler, ir, ", align 1\n  %sum.print.bool."); ir_write_number(compiler, ir, payload.case_index)
                            ir_write_ascii(compiler, ir, " = trunc i8 %sum.print.bool.byte."); ir_write_number(compiler, ir, payload.case_index)
                            ir_write_ascii(compiler, ir, " to i1\n  call void "); emit_context_runtime_symbol(compiler, ir, "nl_print_bool_raw", "nlc_print_bool_raw"); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i1 zeroext %sum.print.bool."); ir_write_number(compiler, ir, payload.case_index); ir_write_ascii(compiler, ir, ")\n")
                        } else {
                            ir_write_ascii(compiler, ir, "  %sum.print.value."); ir_write_number(compiler, ir, payload.case_index)
                            ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty))
                            ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address)
                            ir_write_ascii(compiler, ir, ", align 1\n  call void "); emit_context_runtime_symbol(compiler, ir, if payload.ty == TY_LONG { "nl_print_long_raw" } else { "nl_print_int_raw" }, if payload.ty == TY_LONG { "nlc_print_long_raw" } else { "nlc_print_int_raw" })
                            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, "); ir_write_ascii(compiler, ir, llvm_type_name(payload.ty))
                            ir_write_ascii(compiler, ir, " %sum.print.value."); ir_write_number(compiler, ir, payload.case_index); ir_write_ascii(compiler, ir, ")\n")
                        }
                    }
                }
                emit_sum_builtin_text_call(compiler, ir, "rparen", 1L)
            }
            ir_write_ascii(compiler, ir, "  ret void\n")
        }
        ir_write_ascii(compiler, ir, "sum.print.invalid."); ir_write_number(compiler, ir, type_id); ir_write_ascii(compiler, ir, ":\n  unreachable\n}\n\n")
    }
}

fn emit_contains_index_helper(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "define internal i1 @nl.contains.index(ptr %items, i64 %count, i64 %wanted) {\nentry:\n  br label %loop\nloop:\n  %index = phi i64 [ 0, %entry ], [ %next, %advance ]\n  %finished = icmp uge i64 %index, %count\n  br i1 %finished, label %missing, label %check\ncheck:\n  %item.ptr = getelementptr i64, ptr %items, i64 %index\n  %item = load i64, ptr %item.ptr, align 1\n  %matches = icmp eq i64 %item, %wanted\n  br i1 %matches, label %found, label %advance\nadvance:\n  %next = add i64 %index, 1\n  br label %loop\nfound:\n  ret i1 true\nmissing:\n  ret i1 false\n}\n\n")
}

// E3a1 begin: shared compiler integration.
fn emit_struct_fill_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    var any_defaults = false
    for type_index in 0L..struct_type_count(compiler) {
        let type_id = struct_type_id(compiler, type_index)
        if has_type_helper(compiler, type_id, HELPER_FILL) { any_defaults = true }
    }
    if !any_defaults { return }
    emit_contains_index_helper(compiler, ir)
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_FILL) { continue }
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_FILL); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top, "); emit_hidden_descriptor_parameter(compiler, ir); ir_write_ascii(compiler, ir, ", ptr %nl.given, i64 %nl.given.count) {\nentry:\n  %nl.region.end = add i64 %nl.top, 0\n")
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if field.default_node < 0L { continue }
            let address = MAX_TREE_NODES * 4L + field_index
            ir_write_ascii(compiler, ir, "  %given."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = call i1 @nl.contains.index(ptr %nl.given, i64 %nl.given.count, i64 "); ir_write_number(compiler, ir, offset); ir_write_ascii(compiler, ir, ")\n  br i1 %given."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", label %skip."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", label %fill."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\nfill."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ":\n")
            ir_write_ascii(compiler, ir, "  %default.dest.offset."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = add i64 %nl.dest.offset, "); ir_write_number(compiler, ir, field.offset); ir_write_ascii(compiler, ir, "\n  call void "); emit_default_field_helper_symbol(compiler, ir, type_id, field_index); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.region.end, ptr %nl.dest.anchor, i64 %default.dest.offset."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ")\n  br label %skip."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\nskip."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ":\n")
        }
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_struct_default_helpers(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for field_index in 0L..compiler.struct_fields.count() {
        let field = compiler.struct_fields[field_index]
        if field.default_node < 0L { continue }
        let field_type_id = struct_type_id(compiler, field.owner)
        if !has_type_helper(compiler, field_type_id, HELPER_DEFAULT) { continue }
        let function_id = -100000L - field_index
        let expression = field.default_node
        let default_file = struct_record(compiler, field.owner).file
        ir_write_ascii(compiler, ir, "define internal void "); emit_default_field_helper_symbol(compiler, ir, field_type_id, field_index); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top, "); emit_hidden_descriptor_parameter(compiler, ir); ir_write_ascii(compiler, ir, ") {\nentry:\n  %nl.region.end = add i64 %nl.top, 0\n")
        let first = expression - tables.nodes[expression].subtree
        for node in first..expression + 1L {
            if tables.nodes[node].kind == NodeKind.If && compiler.facts[node].ty != TY_UNIT && compiler.facts[node].ty != TY_NEVER && !is_aggregate_type(compiler, compiler.facts[node].ty) {
                ir_write_ascii(compiler, ir, "  %if.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
            }
            if (tables.nodes[node].kind == NodeKind.Binary && (tables.nodes[node].flags == 14L || tables.nodes[node].flags == 15L)) {
                ir_write_ascii(compiler, ir, "  %logic.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i1, align 1\n")
            }
            if tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 21L && compiler.facts[node].ty != TY_UNIT && !is_aggregate_type(compiler, compiler.facts[node].ty) {
                ir_write_ascii(compiler, ir, "  %coalesce.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
            }
            if is_aggregate_type(compiler, compiler.facts[node].ty) {
                let ty = type_record(compiler, compiler.facts[node].ty)
                let size = ty.size
                let alignment = ty.align
                ir_write_ascii(compiler, ir, "  %agg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, alignment); ir_write_ascii(compiler, ir, "\n")
            }
        }
        for binding_index in 0L..compiler.bindings.count() {
            let binding = compiler.bindings[binding_index]
            if compiler.scopes[binding.scope].function_id == function_id && binding.ty != TY_UNIT {
                ir_write_ascii(compiler, ir, "  %local."); ir_write_number(compiler, ir, binding_index); ir_write_ascii(compiler, ir, " = alloca ")
                if is_aggregate_type(compiler, binding.ty) {
                    let ty = type_record(compiler, binding.ty)
                    let size = ty.size
                    let alignment = ty.align
                    ir_write_ascii(compiler, ir, "["); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, alignment); ir_write_ascii(compiler, ir, "\n")
                } else {
                    if binding.ty == TY_BOOL { ir_write_ascii(compiler, ir, "i8") } else { ir_write_ascii(compiler, ir, llvm_type_name(binding.ty)) }
                    ir_write_ascii(compiler, ir, ", align 1\n")
                }
            }
        }
        emit_expr_linear(source, files, tokens, tables, compiler, ir, expression, default_file, field.ty, false)
        if is_aggregate_type(compiler, field.ty) {
            let source_kind = aggregate_source_kind(tables, compiler, expression)
            let source_node = aggregate_source_id(tables, compiler, expression)
            emit_aggregate_copy(compiler, ir, field.ty, aggregate_destination_location(compiler, 2L, 0L), aggregate_source_location(compiler, source_kind, source_node))
        } else if field.ty == TY_BOOL {
            let destination = compiler_location(compiler, 9L, 0L, 0L)
            let pointer = emit_location_pointer_materialization(compiler, ir, destination)
            ir_write_ascii(compiler, ir, "  %default.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, expression); ir_write_ascii(compiler, ir, " to i8\n  store i8 %default.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer); ir_write_ascii(compiler, ir, ", align 1\n")
        } else {
            let destination = compiler_location(compiler, 9L, 0L, 0L)
            let pointer = emit_location_pointer_materialization(compiler, ir, destination)
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(field.ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, expression); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, destination, pointer); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}
// E3a1 end

fn emit_type_helpers_for_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    kind: long,
) {
    if kind == TYPE_KIND_STRUCT {
        var has_struct_helpers = false
        for type_id in 0L..type_count(compiler) {
            if type_kind(compiler, type_id) == kind && type_has_registered_helper(compiler, type_id) {
                has_struct_helpers = true
            }
        }
        if has_struct_helpers {
            emit_struct_copy_helpers(tables, compiler, ir)
            emit_struct_eq_helpers(compiler, ir)
            emit_struct_print_helpers(source, files, tokens, compiler, ir)
            emit_struct_default_helpers(source, files, tokens, tables, compiler, ir)
            emit_struct_fill_helpers(compiler, ir)
        }
    } else if kind == TYPE_KIND_ENUM {
        var has_enum_helpers = false
        for type_id in 0L..type_count(compiler) {
            if type_kind(compiler, type_id) == kind && type_has_registered_helper(compiler, type_id) { has_enum_helpers = true }
        }
        if has_enum_helpers {
            emit_enum_copy_helpers(compiler, ir)
            emit_enum_equal_helpers(compiler, ir)
            emit_enum_print_helpers(tokens, compiler, ir)
        }
    } else if kind == TYPE_KIND_OPTION {
        emit_sum_copy_helpers(compiler, ir)
        emit_sum_equal_helpers(compiler, ir)
        emit_sum_print_helpers(compiler, ir)
    } else if kind == TYPE_KIND_RESULT {
        ()
    } else if kind == TYPE_KIND_ARRAY || kind == TYPE_KIND_LIST {
        emit_collection_copy_helpers(compiler, ir, kind)
        emit_collection_equal_helpers(compiler, ir, kind)
        emit_collection_print_helpers(compiler, ir, kind)
    } else if kind == TYPE_KIND_ASCII || kind == TYPE_KIND_TEXT || kind == TYPE_KIND_BYTES {
        emit_text_type_helpers(compiler, ir, kind)
    } else {
        for type_id in 0L..type_count(compiler) {
            if type_kind(compiler, type_id) == kind && type_has_registered_helper(compiler, type_id) { compiler.ir_overflow = true }
        }
    }
}

fn emit_registered_type_helpers(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    emit_collection_print_globals(compiler, ir)
    for kind in TYPE_KIND_STRUCT..TYPE_KIND_ADDRESS + 1L {
        emit_type_helpers_for_kind(source, files, tokens, tables, compiler, ir, kind)
    }
}

fn ir_write_struct_identifier_global(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    kind: Ascii max 16,
    index: long,
    file_index: long,
    token: long,
) {
    let length = tokens[token].length
    let start = files[file_index].base + tokens[token].start
    ir_write_ascii(compiler, ir, "@.nl.struct."); ir_write_ascii(compiler, ir, kind); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, index); ir_write_ascii(compiler, ir, " = private unnamed_addr constant ["); ir_write_number(compiler, ir, length + 1L); ir_write_ascii(compiler, ir, " x i8] c\"")
    for byte_index in 0L..length { ir_write_escaped_byte(compiler, ir, source[start + byte_index]) }
    ir_write_ascii(compiler, ir, "\\00\", align 1\n")
}

fn ir_write_enum_case_global(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    case_index: long,
) {
    let case = compiler.enum_cases[case_index]
    let owner = enum_record(compiler, case.owner)
    let length = tokens[case.name_token].length
    let start = files[owner.file].base + tokens[case.name_token].start
    ir_write_ascii(compiler, ir, "@.nl.enum.case."); ir_write_number(compiler, ir, case_index); ir_write_ascii(compiler, ir, " = private unnamed_addr constant ["); ir_write_number(compiler, ir, length + 1L); ir_write_ascii(compiler, ir, " x i8] c\"")
    for byte_index in 0L..length { ir_write_escaped_byte(compiler, ir, source[start + byte_index]) }
    ir_write_ascii(compiler, ir, "\\00\", align 1\n")
}


// E3a1 begin: shared compiler integration.
fn emit_file_globals(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for file_index in 0L..files.count() {
        ir_write_ascii(compiler, ir, "@.nl.file.")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
        ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8] c\"")
        for index in 0L..files[file_index].name.count() { ir_write_escaped_byte(compiler, ir, files[file_index].name[index]) }
        ir_write_ascii(compiler, ir, "\\00\", align 1\n")
    }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.BytesLiteral || tables.nodes[node].kind == NodeKind.ByteString {
            let syntax = tables.nodes[node]
            let literal_file = node_file_index(tables.nodes, files, node)
            let literal = if syntax.kind == NodeKind.BytesLiteral {
                decode_string_token(source, tokens, files[literal_file].base, syntax.extra, true)
            } else { decode_string_token(source, tokens, files[literal_file].base, syntax.token, false) }
            ir_write_ascii(compiler, ir, "@.nl.literal.")
            ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
            ir_write_number(compiler, ir, literal.count() + 1L)
            ir_write_ascii(compiler, ir, " x i8] c\"")
            for index in 0L..literal.count() { ir_write_escaped_byte(compiler, ir, literal[index]) }
            ir_write_ascii(compiler, ir, "\\00\", align 1\n")
        }
    }
    let first_file_id = compiler_file_id_base(compiler)
    emit_file_table_global(files, compiler, ir, first_file_id)
    let main_name: Bytes max 4096 = b"main"
    ir_write_global_string(compiler, ir, "@.nl.entry.main = private unnamed_addr constant [", main_name)
    for test_index in 0L..compiler.tests.count() {
        let test = compiler.tests[test_index]
        let name = decode_string_token(source, tokens, files[test.file].base, test.name_token, false)
        ir_write_test_global(compiler, ir, test_index, name)
    }
    ir_write_ascii(compiler, ir, "@.nl.entry.table = private constant [")
    ir_write_number(compiler, ir, compiler.tests.count() + 1L)
    ir_write_ascii(compiler, ir, " x { ptr, i64 }] [")
    ir_write_ascii(compiler, ir, "{ ptr, i64 } { ptr getelementptr inbounds ([5 x i8], ptr @.nl.entry.main, i64 0, i64 0), i64 4 }")
    for test_index in 0L..compiler.tests.count() {
        let test = compiler.tests[test_index]
        let name = decode_string_token(source, tokens, files[test.file].base, test.name_token, false)
        ir_write_ascii(compiler, ir, ", { ptr, i64 } { ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, name.count() + 8L)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.entry.test.")
        ir_write_number(compiler, ir, test_index)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 ")
        ir_write_number(compiler, ir, name.count() + 7L)
        ir_write_ascii(compiler, ir, " }")
    }
    ir_write_ascii(compiler, ir, "], align 8\n")
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.Expect { ir_write_expect_global(source, tables, compiler, ir, node) }
        if tables.nodes[node].kind == NodeKind.StructInit {
            let type_index = compiler.facts[node].literal
            let ty = struct_record(compiler, type_index)
            var item_count = 0L
            for field_offset in 0L..ty.field_count {
                let field_index = ty.field_start + field_offset
                var child = compiler.child_first[node]
                for field_step in 0L..tables.nodes[node].subtree {
                    if child < 0L { break }
                    if compiler.facts[child].binding == field_index { item_count += 1L }
                    child = compiler.child_next[child]
                }
            }
            ir_write_ascii(compiler, ir, "@.nl.given."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = private constant ["); ir_write_number(compiler, ir, item_count); ir_write_ascii(compiler, ir, " x i64] ")
            if item_count == 0L { ir_write_ascii(compiler, ir, "zeroinitializer\n") }
            else {
                ir_write_ascii(compiler, ir, "[")
                var wrote = false
                for field_offset in 0L..ty.field_count {
                    let field_index = ty.field_start + field_offset
                    var child = compiler.child_first[node]
                    for field_step in 0L..tables.nodes[node].subtree {
                        if child < 0L { break }
                        if compiler.facts[child].binding == field_index {
                            if wrote { ir_write_ascii(compiler, ir, ", ") }
                            ir_write_ascii(compiler, ir, "i64 "); ir_write_number(compiler, ir, field_offset); wrote = true
                        }
                        child = compiler.child_next[child]
                    }
                }
                ir_write_ascii(compiler, ir, "]\n")
            }
        }
    }
    let open_text: Bytes max 4096 = b" { "
    let close_text: Bytes max 4096 = b" }"
    let separator_text: Bytes max 4096 = b", "
    let colon_text: Bytes max 4096 = b": "
    let enum_open_text: Bytes max 4096 = b"("
    let enum_close_text: Bytes max 4096 = b")"
    let enum_separator_text: Bytes max 4096 = b", "
    let enum_unit_text: Bytes max 4096 = b"()"
    ir_write_global_string(compiler, ir, "@.nl.struct.open.0 = private unnamed_addr constant [", open_text)
    ir_write_global_string(compiler, ir, "@.nl.struct.close.0 = private unnamed_addr constant [", close_text)
    ir_write_global_string(compiler, ir, "@.nl.struct.separator.0 = private unnamed_addr constant [", separator_text)
    ir_write_global_string(compiler, ir, "@.nl.struct.colon.0 = private unnamed_addr constant [", colon_text)
    ir_write_global_string(compiler, ir, "@.nl.enum.open.0 = private unnamed_addr constant [", enum_open_text)
    ir_write_global_string(compiler, ir, "@.nl.enum.close.0 = private unnamed_addr constant [", enum_close_text)
    ir_write_global_string(compiler, ir, "@.nl.enum.separator.0 = private unnamed_addr constant [", enum_separator_text)
    ir_write_global_string(compiler, ir, "@.nl.enum.unit.0 = private unnamed_addr constant [", enum_unit_text)
    let sum_some: Bytes max 4096 = b"some"
    let sum_none: Bytes max 4096 = b"none"
    let sum_ok: Bytes max 4096 = b"ok"
    let sum_err: Bytes max 4096 = b"err"
    let sum_lparen: Bytes max 4096 = b"("
    let sum_rparen: Bytes max 4096 = b")"
    let sum_separator: Bytes max 4096 = b", "
    let sum_unit: Bytes max 4096 = b"()"
    let sum_full: Bytes max 4096 = b"Full"
    ir_write_global_string(compiler, ir, "@.nl.sum.some = private unnamed_addr constant [", sum_some)
    ir_write_global_string(compiler, ir, "@.nl.sum.none = private unnamed_addr constant [", sum_none)
    ir_write_global_string(compiler, ir, "@.nl.sum.ok = private unnamed_addr constant [", sum_ok)
    ir_write_global_string(compiler, ir, "@.nl.sum.err = private unnamed_addr constant [", sum_err)
    ir_write_global_string(compiler, ir, "@.nl.sum.lparen = private unnamed_addr constant [", sum_lparen)
    ir_write_global_string(compiler, ir, "@.nl.sum.rparen = private unnamed_addr constant [", sum_rparen)
    ir_write_global_string(compiler, ir, "@.nl.sum.separator = private unnamed_addr constant [", sum_separator)
    ir_write_global_string(compiler, ir, "@.nl.sum.unit = private unnamed_addr constant [", sum_unit)
    ir_write_global_string(compiler, ir, "@.nl.sum.Full = private unnamed_addr constant [", sum_full)
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        if ty.node < 0L { continue }
        ir_write_struct_identifier_global(source, files, tokens, compiler, ir, "type", type_index, ty.file, ty.name_token)
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            ir_write_struct_identifier_global(source, files, tokens, compiler, ir, "field", field_index, ty.file, field.name_token)
        }
    }
    for case_index in 0L..compiler.enum_cases.count() {
        if compiler.enum_cases[case_index].name_token >= 0L {
            ir_write_enum_case_global(source, files, tokens, compiler, ir, case_index)
        }
    }
    ir_write_ascii(compiler, ir, "\n")
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn emit_main_function(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    config: MemoryConfig,
    entry: long,
) {
    if compiler.c_runtime {
        emit_c_main_function(compiler, ir, files, config, entry)
        return
    }
    // E3a1 subsection: create the stable context before any context-passing hook.
    ir_write_ascii(compiler, ir, "define i32 @main(i32 %argc, ptr %argv, ptr %envp, ptr %auxv) {\nentry:\n  %nl.ctx = call ptr @nl_context_create(i64 4096, i64 ")
    ir_write_number(compiler, ir, config.recursion_budget)
    ir_write_ascii(compiler, ir, ", i64 ")
    ir_write_number(compiler, ir, config.step_budget_main)
    ir_write_ascii(compiler, ir, ", ptr @.nl.entry.table, i64 0, ptr %envp, ptr %auxv)\n  call void @nl_core_init(ptr %nl.ctx, i32 %argc, ptr %argv, ptr %envp, ptr %auxv)\n")
    // E3a1 subsection end
    if compiler.tests.count() > 0L {
        ir_write_ascii(compiler, ir, "  %nl.selected = call i32 @nl_test_selected_index(ptr %nl.ctx)\n  switch i32 %nl.selected, label %nl.select.default [\n")
        for test_index in 0L..compiler.tests.count() {
            ir_write_ascii(compiler, ir, "    i32 ")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ", label %nl.select.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for test_index in 0L..compiler.tests.count() {
            ir_write_ascii(compiler, ir, "nl.select.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ":\n  br label %nl.select.ready\n")
        }
        ir_write_ascii(compiler, ir, "nl.select.default:\n  br label %nl.select.ready\nnl.select.ready:\n  %nl.entry.index = phi i64 ")
        for test_index in 0L..compiler.tests.count() {
            if test_index > 0L { ir_write_ascii(compiler, ir, ", ") }
            ir_write_ascii(compiler, ir, "[ ")
            ir_write_number(compiler, ir, test_index + 1L)
            ir_write_ascii(compiler, ir, ", %nl.select.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, " ]")
        }
        ir_write_ascii(compiler, ir, ", [ ")
        if entry >= 0L { ir_write_ascii(compiler, ir, "0") } else { ir_write_ascii(compiler, ir, "1") }
        ir_write_ascii(compiler, ir, ", %nl.select.default ]\n")
        ir_write_ascii(compiler, ir, "  call void @nl_context_set_entry_name(ptr %nl.ctx, ptr @.nl.entry.table, i64 %nl.entry.index)\n")
    }
    ir_write_ascii(compiler, ir, "  %nl.top = call i64 @nl_context_base_offset(ptr %nl.ctx)\n  %nl.env = call ptr @nl_env_create(ptr %nl.ctx, i32 %argc, ptr %argv, i32 ")
    ir_write_number(compiler, ir, config.capability_mask)
    ir_write_ascii(compiler, ir, ")\n")
    ir_write_ascii(compiler, ir, "  call void @nl_register_files(ptr %nl.ctx, i32 0, ptr @.nl.file.table.0, i32 ")
    ir_write_number(compiler, ir, files.count())
    ir_write_ascii(compiler, ir, ")\n")
    ir_write_ascii(compiler, ir, "  call void @nl_core_register_files(ptr %nl.ctx)\n")
    if compiler.tests.count() > 0L {
        ir_write_ascii(compiler, ir, "  switch i32 %nl.selected, label %nl.test.fallback [\n")
        for test_index in 0L..compiler.tests.count() {
            ir_write_ascii(compiler, ir, "    i32 ")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ", label %nl.test.run.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "  ]\n")
        for test_index in 0L..compiler.tests.count() {
            ir_write_ascii(compiler, ir, "nl.test.run.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ":\n  call void @nl_set_test_mode(ptr %nl.ctx)\n  %nl.test.result.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, " = call i32 @nl_fn_")
            let test_function_id = compiler.functions.count() + test_index
            ir_write_number(compiler, ir, test_function_id)
            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top)\n  call void @nl_env_destroy(ptr %nl.ctx, ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 %nl.test.result.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, "\n")
        }
        ir_write_ascii(compiler, ir, "nl.test.fallback:\n")
    }
    if entry >= 0L {
        ir_write_ascii(compiler, ir, "  call void @nl_fn_")
        ir_write_number(compiler, ir, entry)
        ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top)\n")
    }
    ir_write_ascii(compiler, ir, "  call void @nl_env_destroy(ptr %nl.ctx, ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 0\n}\n")
}
// E3a1 end

fn core_position(file_data: Bytes max FILE_SOURCE_CAPACITY, offset: long) -> SourcePosition {
    var line = 1L
    var col = 1L
    for index in 0L..offset {
        if file_data[index] == 10 { line += 1L; col = 1L }
        else { col += 1L }
    }
    SourcePosition { line, col }
}

fn fail_core_internal(
    env: Env,
    file: Bytes max 4096,
    position: SourcePosition,
    message: Ascii max 160,
) -> never {
    match env.err.write(b"nlc: internal error in the core library: ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(file) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": ") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(message.bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(3), err(_) => env.exit(3) }
}

fn copy_core_name(name: Ascii max 64) -> Bytes max 4096 {
    var result: Bytes max 4096 = Bytes.empty()
    for index in 0L..name.len() { result.push(name.bytes()[index]).unwrap() }
    result
}

fn append_embedded_core_sources(
    env: Env,
    source: grow Bytes max SOURCE_BUFFER_CAPACITY,
    files: write list<SourceFile, MAX_SOURCE_FILES>,
    tokens: write list<Token, TOKEN_STORAGE_CAPACITY>,
    delimiters: write list<DelimiterKind, MAX_DELIMITER_NESTING>,
    tables: write ParseTables,
) {
    for file_index in 0L..embedded_core_file_count() {
        let file_name = copy_core_name(embedded_core_file_name(file_index))
        var file_data: Bytes max FILE_SOURCE_CAPACITY = Bytes.empty()
        for chunk_index in 0L..embedded_core_chunk_count(file_index) {
            let chunk = embedded_core_file_chunk(file_index, chunk_index)
            match file_data.try_append(chunk) {
                ok(_) => (),
                err(_) => fail_core_internal(env, file_name, SourcePosition { line: 1L, col: 1L }, "embedded source exceeded its fixed file buffer"),
            }
        }
        match file_data.validate_utf8() {
            ok(_) => (),
            err(error) => fail_core_internal(env, file_name, core_position(file_data, error.valid_up_to), "embedded source is not valid UTF-8"),
        }
        let file_length = file_data.count()
        let base = source.count()
        match source.try_append(file_data) {
            ok(_) => (),
            err(_) => fail_core_internal(env, file_name, SourcePosition { line: 1L, col: 1L }, "embedded source exceeded its fixed package buffer"),
        }
        let first_token = tokens.count()
        let summary = match lex_file(source, base, file_length, tokens, delimiters) {
            ok(value) => value,
            err(problem) => fail_core_internal(env, file_name, SourcePosition { line: problem.line, col: problem.col }, "embedded source has a lexer error"),
        }
        let root = match parse_file(source, tokens, tables, base, file_length, first_token, summary.token_count) {
            ok(value) => value,
            err(problem) => fail_core_internal(env, file_name, core_position(file_data, problem.offset), "embedded source has a parser error"),
        }
        let core_file = SourceFile { name: file_name, base, length: file_length, first_token, token_count: summary.token_count, end_line: summary.end_line, end_col: summary.end_col, tree_root: root }
        match files.push(core_file) {
            ok(_) => (),
            err(_) => fail_core_internal(env, b"core", SourcePosition { line: 1L, col: 1L }, "embedded file count exceeded its fixed limit"),
        }
    }
}

// E3a1 begin: shared compiler integration.
fn emit_core_file_globals(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for file_index in 0L..files.count() {
        let global_file_id = compiler_file_id_base(compiler) + file_index
        ir_write_ascii(compiler, ir, "@.nl.file.")
        ir_write_number(compiler, ir, global_file_id)
        ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
        ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8] c\"")
        for index in 0L..files[file_index].name.count() { ir_write_escaped_byte(compiler, ir, files[file_index].name[index]) }
        ir_write_ascii(compiler, ir, "\\00\", align 1\n")
    }
    let first_file_id = compiler_file_id_base(compiler)
    emit_file_table_global(files, compiler, ir, first_file_id)
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.BytesLiteral || tables.nodes[node].kind == NodeKind.ByteString {
            let syntax = tables.nodes[node]
            let literal_file = node_file_index(tables.nodes, files, node)
            let literal = if syntax.kind == NodeKind.BytesLiteral {
                decode_string_token(source, tokens, files[literal_file].base, syntax.extra, true)
            } else { decode_string_token(source, tokens, files[literal_file].base, syntax.token, false) }
            ir_write_ascii(compiler, ir, "@.nl.core.literal.")
            ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
            ir_write_number(compiler, ir, literal.count() + 1L)
            ir_write_ascii(compiler, ir, " x i8] c\"")
            for index in 0L..literal.count() { ir_write_escaped_byte(compiler, ir, literal[index]) }
            ir_write_ascii(compiler, ir, "\\00\", align 1\n")
        }
    }
}
// E3a1 end

fn syscall_register(index: long) -> Ascii max 8 {
    if index == 0L { "rdi" }
    else if index == 1L { "rsi" }
    else if index == 2L { "rdx" }
    else if index == 3L { "r10" }
    else if index == 4L { "r8" }
    else { "r9" }
}

fn emit_one_syscall_helper(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, item_count: long) {
    ir_write_ascii(compiler, ir, "define internal i64 @nl.sys.call")
    ir_write_number(compiler, ir, item_count)
    ir_write_ascii(compiler, ir, "(i64 %n")
    for index in 0L..item_count {
        ir_write_ascii(compiler, ir, ", i64 %a")
        ir_write_number(compiler, ir, index)
    }
    ir_write_ascii(compiler, ir, ") alwaysinline nounwind {\nentry:\n  %r = call i64 asm sideeffect \"syscall\", \"={rax},{rax}")
    for index in 0L..item_count {
        ir_push_byte(compiler, ir, 44)
        ir_push_byte(compiler, ir, 123)
        ir_write_ascii(compiler, ir, syscall_register(index))
        ir_push_byte(compiler, ir, 125)
    }
    ir_write_ascii(compiler, ir, ",~{rcx},~{r11},~{memory},~{dirflag},~{fpsr},~{flags}\"(i64 %n")
    for index in 0L..item_count {
        ir_write_ascii(compiler, ir, ", i64 %a")
        ir_write_number(compiler, ir, index)
    }
    ir_write_ascii(compiler, ir, ")\n  ret i64 %r\n}\n\n")
}

fn emit_syscall_helpers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    for item_count in 0L..7L { emit_one_syscall_helper(compiler, ir, item_count) }
}

fn emit_core_registration(files: list<SourceFile, MAX_SOURCE_FILES>, compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    // E3a1 begin
    let first_file_id = compiler_file_id_base(compiler)
    let file_count = files.count()
    ir_write_ascii(compiler, ir, "define internal void @nl_core_register_files(ptr %nl.ctx) nounwind {\nentry:\n")
    ir_write_ascii(compiler, ir, "  call void @nl_register_files(ptr %nl.ctx, i32 ")
    ir_write_number(compiler, ir, first_file_id)
    ir_write_ascii(compiler, ir, ", ptr @.nl.file.table.")
    ir_write_number(compiler, ir, first_file_id)
    ir_write_ascii(compiler, ir, ", i32 ")
    ir_write_number(compiler, ir, file_count)
    ir_write_ascii(compiler, ir, ")\n")
    ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    // E3a1 end
}

fn emit_core_start_assembly(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "module asm \".text\"\nmodule asm \".globl _start\"\nmodule asm \".type _start, @function\"\nmodule asm \"_start:\"\nmodule asm \"  .cfi_startproc\"\nmodule asm \"  .cfi_undefined rip\"\nmodule asm \"  xor %ebp, %ebp\"\nmodule asm \"  mov %rsp, %rdi\"\nmodule asm \"  and $-16, %rsp\"\nmodule asm \"  call nl_core_start\"\nmodule asm \"  ud2\"\nmodule asm \"  .cfi_endproc\"\nmodule asm \".size _start, . - _start\"\n")
    ir_write_ascii(compiler, ir, "@llvm.used = appending global [1 x ptr] [ptr @nl_core_start], section \"llvm.metadata\"\n")
}

// E3a1 begin: shared compiler integration.
fn compile_embedded_core(
    env: Env,
    config: MemoryConfig,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    file_id_base: long,
    test_build: bool,
    tables: write ParseTables,
    compiler: write CompilerTables,
) -> bool {
    var source: Bytes max SOURCE_BUFFER_CAPACITY = Bytes.empty()
    var files: list<SourceFile, MAX_SOURCE_FILES> = list {}
    var tokens: list<Token, TOKEN_STORAGE_CAPACITY> = list {}
    var delimiters: list<DelimiterKind, MAX_DELIMITER_NESTING> = list {}
    reset_parse_tables(tables)
    initialize_parse_tables(tables)
    append_embedded_core_sources(env, source, files, tokens, delimiters, tables)
    reset_compiler_tables(env, compiler)
    compiler.core_mode = true
    compiler.test_build = test_build
    compiler.file_id_base = file_id_base + if test_build { COMPILER_TEST_BUILD_FLAG } else { 0L }
    add_compiler_links(env, tables, compiler)
    intern_package_names(env, source, files, tokens, tables, compiler)
    build_line_start_index(env, source, files, compiler)
    register_scalar_constants(env, source, tokens, files, tables, compiler)
    index_package_enums(env, source, files, tokens, tables, compiler)
    // E3a1 subsection: embedded core context intrinsics need the sized layout.
    index_package_structs(source, files, tokens, tables, compiler)
    // E3a1 subsection end
    intern_written_type_instances(env, source, tokens, files, tables, compiler)
    size_package_types(source, files, tokens, tables, compiler)
    check_package_name_shadows(env, source, files, tokens, tables, compiler)
    check_package_eligibility(env, source, files, tokens, tables, compiler)
    check_struct_declarations(env, source, files, tokens, tables, compiler)
    register_package_declarations(env, source, files, tokens, tables, config, compiler)
    let _entry = check_entry_signature(env, source, files, tokens, tables, compiler, false)
    check_package_bodies(env, source, files, tokens, tables, config, compiler)
    check_deferred_large_value_gate(env, source, files, tokens, tables, compiler)
    add_default_call_graph_edges(tables, compiler)
    check_call_cycles(env, source, files, tokens, tables, compiler)
    mark_struct_helpers(source, files, tokens, tables, compiler)
    propagate_sum_type_helpers(compiler)
    for function_id in 0L..compiler.functions.count() {
        emit_function_definition(source, files, tokens, tables, compiler, ir, function_id)
    }
    emit_registered_type_helpers(source, files, tokens, tables, compiler, ir)
    emit_core_file_globals(source, files, tokens, tables, compiler, ir)
    emit_core_registration(files, compiler, ir)
    emit_syscall_helpers(compiler, ir)
    ir_write_ascii(compiler, ir, "@llvm.compiler.used = appending global [5 x ptr] [ptr @memcpy, ptr @memmove, ptr @memset, ptr @memcmp, ptr @bcmp], section \"llvm.metadata\"\n")
    emit_core_start_assembly(compiler, ir)
    !compiler.ir_overflow
}
// E3a1 end

// E3a1 begin: shared compiler integration.
fn compile_selfhost_package(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    config: MemoryConfig,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    want_test_build: bool,
    core_hash: Ascii max 64,
) {
    compiler.test_build = want_test_build
    check_struct_declarations(env, source, files, tokens, tables, compiler)
    register_package_declarations(env, source, files, tokens, tables, config, compiler)
    initialize_default_graph_nodes(compiler)
    let entry = check_entry_signature(env, source, files, tokens, tables, compiler, !want_test_build)
    check_struct_defaults(env, source, files, tokens, tables, config, compiler)
    check_package_bodies(env, source, files, tokens, tables, config, compiler)
    check_deferred_large_value_gate(env, source, files, tokens, tables, compiler)
    check_nested_collections_eligibility(env, source, files, tokens, tables, compiler)
    add_default_call_graph_edges(tables, compiler)
    check_call_cycles(env, source, files, tokens, tables, compiler)
    check_native_frame_budget(env, source, files, tokens, tables, compiler, entry, want_test_build)
    mark_struct_helpers(source, files, tokens, tables, compiler)
    propagate_sum_type_helpers(compiler)
    ir_write_ascii(compiler, ir, "; nlc-link-ir 2\n; nlc.build ")
    ir_write_ascii(compiler, ir, if want_test_build { "test" } else { "program" })
    ir_write_ascii(compiler, ir, "\n; nlc.stack offset\n; nlc.recursion none\n")
    ir_write_ascii(compiler, ir, if compiler.c_runtime { "; nlc.runtime c\n" } else { "; nlc.runtime core\n" })
    ir_write_ascii(compiler, ir, "; nlc.core ")
    ir_write_ascii(compiler, ir, core_hash)
    ir_write_ascii(compiler, ir, "\n")
    for test_index in 0L..compiler.tests.count() {
        let test = compiler.tests[test_index]
        let name = decode_string_token(source, tokens, files[test.file].base, test.name_token, false)
        ir_write_ascii(compiler, ir, "; nlc.test ")
        ir_write_number(compiler, ir, test_index)
        ir_write_ascii(compiler, ir, " ")
        for index in 0L..name.count() {
            ir_push_byte(compiler, ir, ir_hex_digit(name[index].to_long() / 16L, true))
            ir_push_byte(compiler, ir, ir_hex_digit(name[index].to_long() % 16L, true))
        }
        ir_write_ascii(compiler, ir, "\n")
    }
    ir_write_ascii(compiler, ir, "source_filename = \"next-lang\"\n\ndeclare { i32, i1 } @llvm.sadd.with.overflow.i32(i32, i32)\ndeclare { i32, i1 } @llvm.ssub.with.overflow.i32(i32, i32)\ndeclare { i32, i1 } @llvm.smul.with.overflow.i32(i32, i32)\ndeclare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)\ndeclare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)\ndeclare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)\ndeclare void @llvm.trap()\n")
    ir_write_ascii(compiler, ir, "\n")
    if compiler.c_runtime { emit_c_runtime_adapters(compiler, ir) }
    for function_id in 0L..compiler.functions.count() {
        emit_function_definition(source, files, tokens, tables, compiler, ir, function_id)
    }
    for test_index in 0L..compiler.tests.count() {
        emit_test_definition(source, files, tokens, tables, compiler, ir, test_index)
    }
    emit_registered_type_helpers(source, files, tokens, tables, compiler, ir)
    emit_file_globals(files, source, tokens, tables, compiler, ir)
    emit_main_function(source, compiler, ir, files, tokens, config, entry)
    let user_ir_overflow = compiler.ir_overflow
    if !compiler.c_runtime {
        if !compile_embedded_core(env, config, ir, files.count(), want_test_build, tables, compiler) {
            fail_parse_limit(env, files[0].name, "self-hosted LLVM IR buffer limit exceeded")
        }
    }
    compiler.ir_overflow = compiler.ir_overflow || user_ir_overflow
    emit_storage_tbaa_metadata(compiler, ir)
    ir_write_ascii(compiler, ir, "\n; nlc-link-ir end\n")
}
// E3a1 end

// Checker order follows checker.rs. main first loads and parses every sorted
// file, reads package.toml, builds child/sibling links and interns names, then
// runs check_package_eligibility over all nodes. That pass picks the lowest
// file/offset and the outer node at a shared offset, before any checker error.
// compile_selfhost_package then registers declarations, checks the entry,
// checks function bodies in declaration order and tests in declaration order,
// and only after every body checks call cycles. Registration is file ordered;
// each file's functions are checked before that file's tests. A function's
// built-in-name and duplicate checks precede its parameter/result types, in
// source order; test duplicates are checked while that file's tests register.
//
// Body checking uses the explicit CheckFrame stack below. Child visitation is
// source order except where expected-type inference requires Rust's order:
// check_operand_pair visits the right operand first when only the left is an
// unsuffixed literal with no expected type. Literal range checks wait until an
// annotation, parameter, result, return, or peer operand supplies context.
// Loop counter constraints from annotation, natural bound types, and body uses
// are joined before either bound is checked. Fall-through/never facts are
// finalized for each block before missing-return and unit-tail checks. These
// order points are pinned by the E1 checker-order fixtures and comparison
// harness.

