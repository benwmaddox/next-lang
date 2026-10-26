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
const TY_STRUCT_BASE: long = 6L
const MAX_VALUE_SIZE: long = 4097L

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

const LOCATION_NATIVE: long = 0L
const LOCATION_DATA_STACK: long = 1L
const LOCATION_GLOBAL: long = 2L

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

const FACT_NEVER: long = 1L
const FACT_FALLS_THROUGH: long = 2L

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
}

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

struct TypeWalkFrame {
    type_index: long
    field_index: long
    size: long
    align: long
}

struct NodeFact {
    ty: long
    flags: long
    binding: long
    function: long
    literal: long
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
    binding: long
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
}

struct CompilerTables {
    child_first: list<long, CHILD_LINK_CAPACITY>
    child_next: list<long, CHILD_LINK_CAPACITY>
    facts: list<NodeFact, TYPED_FACT_CAPACITY>
    expected: list<long, TYPED_FACT_CAPACITY>
    token_name_ids: list<long, TOKEN_STORAGE_CAPACITY>
    intern_slots: list<NameSlot, INTERN_HASH_CAPACITY>
    functions: list<FunctionRecord, FUNCTION_TABLE_CAPACITY>
    parameters: list<ParameterRecord, BINDING_TABLE_CAPACITY>
    type_records: list<TypeRecord, TYPE_TABLE_CAPACITY>
    exit_cleanups: list<ExitCleanupRecord, EXIT_CLEANUP_CAPACITY>
    struct_fields: list<StructFieldRecord, FIELD_TABLE_CAPACITY>
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
    scopes: list<ScopeRecord, SCOPE_TABLE_CAPACITY>
    work: list<CheckFrame, CHECK_FRAME_CAPACITY>
    line_starts: list<long, SOURCE_LINE_START_CAPACITY>
    file_line_ranges: list<FileLineRange, MAX_SOURCE_FILES>
    default_context: Bytes max 4096
    table_failed: bool
    ir_overflow: bool
    ir_terminated: bool
    core_mode: bool
    file_id_base: long
    memory_closure: bool
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

fn seed_builtin_types(types: write list<TypeRecord, TYPE_TABLE_CAPACITY>) {
    types.push(builtin_type_record(TYPE_KIND_SCALAR, 4L, 4L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_SCALAR, 8L, 8L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_SCALAR, 1L, 1L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_UNIT, 0L, 1L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_NEVER, 0L, 1L)).unwrap()
    types.push(builtin_type_record(TYPE_KIND_ADDRESS, 8L, 8L)).unwrap()
}

fn empty_compiler_tables() -> CompilerTables {
    CompilerTables {
        child_first: list {},
        child_next: list {},
        facts: list {},
        expected: list {},
        token_name_ids: list {},
        intern_slots: list {},
        functions: list {},
        parameters: list {},
        type_records: list {},
        exit_cleanups: list {},
        struct_fields: list {},
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
        scopes: list {},
        work: list {},
        line_starts: list {},
        file_line_ranges: list {},
        default_context: Bytes.empty(),
        table_failed: false,
        ir_overflow: false,
        ir_terminated: false,
        core_mode: false,
        file_id_base: 0L,
        memory_closure: false,
    }
}

fn reset_compiler_tables(compiler: write CompilerTables) {
    compiler.child_first.clear()
    compiler.child_next.clear()
    compiler.facts.clear()
    compiler.expected.clear()
    compiler.token_name_ids.clear()
    compiler.intern_slots.clear()
    compiler.functions.clear()
    compiler.parameters.clear()
    compiler.type_records.clear()
    compiler.exit_cleanups.clear()
    seed_builtin_types(compiler.type_records)
    compiler.struct_fields.clear()
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
    compiler.scopes.clear()
    compiler.work.clear()
    compiler.line_starts.clear()
    compiler.file_line_ranges.clear()
    compiler.default_context = Bytes.empty()
    compiler.table_failed = false
    compiler.ir_overflow = false
    compiler.ir_terminated = false
    compiler.core_mode = false
    compiler.file_id_base = 0L
    compiler.memory_closure = false
}

fn add_compiler_links(tables: write ParseTables, compiler: write CompilerTables) {
    for node in 0L..tables.nodes.count() {
        compiler.child_first.push(-1L).unwrap()
        compiler.child_next.push(-1L).unwrap()
        compiler.facts.push(NodeFact { ty: -1L, flags: 0L, binding: -1L, function: -1L, literal: 0L }).unwrap()
        compiler.expected.push(-1L).unwrap()
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
        let length = tokens[binding.name_token].length
        let distance = identifier_distance(source, tokens, files, file_index, token, binding.file, binding.name_token)
        let threshold = if name_length > length { name_length / 3L + 1L } else { length / 3L + 1L }
        if distance <= 2L && distance <= threshold && (best.token < 0L || distance < best.distance || (distance == best.distance && length < best.length)) {
            best = NameCandidate { token: binding.name_token, file: binding.file, distance, length }
        }
    }
    best
}

fn block_for_node(
    tables: ParseTables,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    node: long,
    file_index: long,
) -> long {
    var found = -1L
    var smallest = 9223372036854775807L
    let value = tables.nodes[node]
    for candidate in 0L..tables.nodes.count() {
        if tables.nodes[candidate].kind != NodeKind.Block || node_file_index(tables.nodes, files, candidate) != file_index { continue }
        let block = tables.nodes[candidate]
        if block.start <= value.start && block.end >= value.end && block.end - block.start < smallest {
            found = candidate
            smallest = block.end - block.start
        }
    }
    found
}

fn is_shadowed_function_value(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    file_index: long,
    name_id: long,
) -> bool {
    let reference = tables.nodes[node]
    var unused = 0L
    for candidate in 0L..tables.nodes.count() {
        let kind = tables.nodes[candidate].kind
        if kind != NodeKind.Function && kind != NodeKind.Test { continue }
        if node_file_index(tables.nodes, files, candidate) != file_index { continue }
        let owner = tables.nodes[candidate]
        if owner.start <= reference.start && owner.end >= reference.end {
            unused += 1L
            break
        }
    }
    if unused == 0L { return false }
    let reference_block = block_for_node(tables, files, node, file_index)
    for candidate in 0L..tables.nodes.count() {
        let kind = tables.nodes[candidate].kind
        if node_file_index(tables.nodes, files, candidate) != file_index { continue }
        let declaration = tables.nodes[candidate]
        if kind == NodeKind.Parameter && compiler.token_name_ids[declaration.token] == name_id {
            var belongs = false
            for owner in 0L..tables.nodes.count() {
                if tables.nodes[owner].kind == NodeKind.Function && node_file_index(tables.nodes, files, owner) == file_index && tables.nodes[owner].start <= declaration.start && tables.nodes[owner].end >= reference.end { belongs = true }
            }
            if belongs { return true }
        }
        if kind == NodeKind.Let && compiler.token_name_ids[declaration.token] == name_id && declaration.end < reference.start {
            let declaration_block = block_for_node(tables, files, candidate, file_index)
            if declaration_block >= 0L && reference_block >= 0L && tables.nodes[declaration_block].start <= tables.nodes[reference_block].start && tables.nodes[declaration_block].end >= tables.nodes[reference_block].end { return true }
        }
        if kind == NodeKind.For && compiler.token_name_ids[declaration.token] == name_id {
            let body = node_children_of_kind(tables, compiler, candidate, NodeKind.Block)
            if body >= 0L && tables.nodes[body].start <= reference.start && tables.nodes[body].end >= reference.end { return true }
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
    function_exists_by_name(tables, files, compiler, name_id) && !is_shadowed_function_value(files, tables, compiler, node, file_index, name_id)
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
    token_is_word_at(source, tokens, files, file_index, token, "NonAscii")
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
    token_is_word_at(source, tokens, files, file_index, token, "byte") ||
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

fn append_type_record(compiler: write CompilerTables, record: TypeRecord) -> long {
    let type_id = compiler.type_records.count()
    compiler.type_records.push(record).unwrap()
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
    type_record(compiler, struct_type_id(compiler, struct_index))
}

fn struct_type_count(compiler: CompilerTables) -> long {
    var count = 0L
    for type_id in 0L..compiler.type_records.count() {
        if type_record_kind(compiler.type_records[type_id]) == TYPE_KIND_STRUCT { count += 1L }
    }
    count
}

fn type_kind(compiler: CompilerTables, type_id: long) -> long {
    type_record_kind(type_record(compiler, type_id))
}

fn type_state(compiler: CompilerTables, type_id: long) -> long {
    type_record_state(type_record(compiler, type_id))
}

fn type_count(compiler: CompilerTables) -> long { compiler.type_records.count() }

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
    let syntax = tables.nodes[node]
    if (syntax.flags & FLAG_TYPE_UNIT) != 0L { return TY_UNIT }
    if syntax.kind == NodeKind.ResultType && token_is_word_at(source, tokens, files, file_index, syntax.token, "never") { return TY_NEVER }
    if compiler.core_mode && syntax.meta0 == 2L &&
        token_is_word_at(source, tokens, files, file_index, tables.extra[syntax.extra], "sys") &&
        token_is_word_at(source, tokens, files, file_index, tables.extra[syntax.extra + 1L], "Addr") { return TY_ADDR }
    if token_is_word_at(source, tokens, files, file_index, syntax.token, "int") { return TY_INT }
    if token_is_word_at(source, tokens, files, file_index, syntax.token, "long") { return TY_LONG }
    if token_is_word_at(source, tokens, files, file_index, syntax.token, "bool") { return TY_BOOL }
    if syntax.token < 0L { return -1L }
    let name_id = compiler.token_name_ids[syntax.token]
    let type_index = struct_type_matches(compiler, name_id)
    if type_index >= 0L { return struct_type_id(compiler, type_index) }
    -1L
}

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
                append_type_record(compiler, TypeRecord {
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

fn size_package_structs(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    compiler.type_walk.clear()
    for root_type in 0L..struct_type_count(compiler) {
        if type_state(compiler, struct_type_id(compiler, root_type)) != 0L { continue }
        set_type_state(compiler, struct_type_id(compiler, root_type), 1L)
        compiler.type_walk.push(TypeWalkFrame { type_index: root_type, field_index: 0L, size: 0L, align: 1L }).unwrap()
        for walk_step in 0L..MAX_TREE_NODES {
            if compiler.type_walk.count() == 0L { break }
            let frame_index = compiler.type_walk.count() - 1L
            var frame = compiler.type_walk[frame_index]
            let type_info = struct_record(compiler, frame.type_index)
            if frame.field_index >= type_info.field_count {
                set_type_layout(compiler, struct_type_id(compiler, frame.type_index), size_align_saturated(frame.size, frame.align), frame.align, 2L)
                let _ = compiler.type_walk.pop()
                continue
            }
            let field_index = type_info.field_start + frame.field_index
            let field = compiler.struct_fields[field_index]
            let file_index = struct_record(compiler, frame.type_index).file
            let ty = resolve_value_type(source, tokens, files, tables, compiler, file_index, field.type_node)
            compiler.struct_fields[field_index].ty = ty
            let field_size = value_type_size(compiler, ty)
            let field_align = value_type_align(compiler, ty)
            if field_size < 0L || field_align < 0L {
                if type_kind(compiler, ty) == TYPE_KIND_STRUCT {
                    let nested = struct_type_index(compiler, ty)
                    if nested >= 0L && nested < struct_type_count(compiler) && type_state(compiler, struct_type_id(compiler, nested)) == 0L {
                        set_type_state(compiler, ty, 1L)
                        compiler.type_walk.push(TypeWalkFrame { type_index: nested, field_index: 0L, size: 0L, align: 1L }).unwrap()
                        continue
                    }
                    if nested >= 0L && nested < struct_type_count(compiler) && type_state(compiler, struct_type_id(compiler, nested)) == 1L {
                        set_type_state(compiler, struct_type_id(compiler, frame.type_index), 4L)
                    } else if nested >= 0L && nested < struct_type_count(compiler) && type_state(compiler, struct_type_id(compiler, nested)) == 4L {
                        set_type_state(compiler, struct_type_id(compiler, frame.type_index), 4L)
                    } else {
                        set_type_state(compiler, struct_type_id(compiler, frame.type_index), 3L)
                    }
                } else {
                    set_type_state(compiler, struct_type_id(compiler, frame.type_index), 3L)
                }
                let _ = compiler.type_walk.pop()
                continue
            }
            let offset = size_align_saturated(frame.size, field_align)
            compiler.struct_fields[field_index].offset = offset
            frame.size = size_add_saturated(offset, field_size)
            if field_align > frame.align { frame.align = field_align }
            frame.field_index += 1L
            compiler.type_walk[frame_index] = frame
        }
        if compiler.type_walk.count() > 0L {
            set_type_state(compiler, struct_type_id(compiler, root_type), 3L)
            compiler.type_walk.clear()
        }
    }
}

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
    value_type_size(compiler, ty) > 4096L
}
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

fn core_sys_argument_count(operation: long) -> long {
    if operation == SYS_NULL || operation == SYS_STATE { 0L }
    else if operation == SYS_LIT || operation == SYS_REPEAT_BYTE { 1L }
    else if operation == SYS_IS_NULL || operation == SYS_FROM_RAW || operation == SYS_IS_ERROR || operation == SYS_EXIT_GROUP || operation == SYS_CLOSE { 1L }
    else if operation == SYS_OFFSET || operation == SYS_DISTANCE || operation == SYS_LOAD8 || operation == SYS_LOAD32 || operation == SYS_LOAD64 || operation == SYS_LOAD_ADDR || operation == SYS_COPY_16 || operation == SYS_FILL_16 { 2L }
    else if operation == SYS_PROTECT || operation == SYS_IOCTL || operation == SYS_FILL_BULK { 3L }
    else if operation == SYS_STORE8 || operation == SYS_STORE32 || operation == SYS_STORE64 || operation == SYS_STORE_ADDR || operation == SYS_COPY_FORWARD_BULK || operation == SYS_WRITE || operation == SYS_CALL_MAIN { 3L }
    else if operation == SYS_OPENAT || operation == SYS_SIGACTION { 4L }
    else if operation == SYS_STATX { 5L }
    else if operation == SYS_MAP { 6L }
    else { -1L }
}

fn core_sys_argument_type(operation: long, index: long) -> long {
    if operation == SYS_IS_NULL && index == 0L { TY_ADDR }
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
    else if operation == SYS_LIT && index == 0L { TY_ADDR }
    else { -1L }
}

fn core_sys_result_type(operation: long) -> long {
    if operation == SYS_IS_NULL || operation == SYS_IS_ERROR { TY_BOOL }
    else if operation == SYS_NULL || operation == SYS_OFFSET || operation == SYS_FROM_RAW || operation == SYS_LOAD_ADDR || operation == SYS_STATE || operation == SYS_LIT { TY_ADDR }
    else if operation == SYS_LOAD8 || operation == SYS_LOAD32 { TY_INT }
    else if operation == SYS_LOAD64 || operation == SYS_DISTANCE || operation == SYS_WRITE || operation == SYS_MAP || operation == SYS_PROTECT || operation == SYS_IOCTL || operation == SYS_STATX || operation == SYS_SIGACTION || operation == SYS_OPENAT || operation == SYS_CLOSE { TY_LONG }
    else if operation == SYS_REPEAT_BYTE { TY_LONG }
    else if operation == SYS_CALL_MAIN { TY_INT }
    else if operation == SYS_EXIT_GROUP { TY_NEVER }
    else { TY_UNIT }
}

fn unsupported_category_for_node(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: CompilerTables,
    node: long,
    file_index: long,
) -> long {
    let value = tables.nodes[node]
    match value.kind {
        NodeKind.Program => 0L,
        NodeKind.Enum => UNSUPPORTED_NODE,
        NodeKind.Struct => {
            if value.aux > 0L { UNSUPPORTED_NODE }
            else {
                var oversized = false
                for type_index in 0L..struct_type_count(compiler) {
                    if struct_record(compiler, type_index).node == node && type_state(compiler, struct_type_id(compiler, type_index)) == 2L && struct_record(compiler, type_index).size > 4096L { oversized = true }
                }
                if oversized { UNSUPPORTED_LARGE_VALUE } else { 0L }
            }
        },
        NodeKind.StructField => 0L,
        NodeKind.FieldType => if type_node_is_oversized(source, tokens, files, tables, compiler, node, file_index) { UNSUPPORTED_LARGE_VALUE } else { 0L },
        NodeKind.TypeAlias => UNSUPPORTED_NODE,
        NodeKind.Const => UNSUPPORTED_NODE,
        NodeKind.Global => UNSUPPORTED_NODE,
        NodeKind.ForEach => UNSUPPORTED_NODE,
        NodeKind.Discard => UNSUPPORTED_NODE,
        NodeKind.Match => UNSUPPORTED_NODE,
        NodeKind.Cast => 0L,
        NodeKind.CastType => {
            if token_is_word_at(source, tokens, files, file_index, value.token, "int") ||
                token_is_word_at(source, tokens, files, file_index, value.token, "long") { 0L }
            else { UNSUPPORTED_NODE }
        },
        NodeKind.Fit => UNSUPPORTED_NODE,
        NodeKind.Try => UNSUPPORTED_NODE,
        NodeKind.MethodCall => if is_core_sys_receiver(source, tokens, files, tables, compiler, node, file_index) { 0L } else { UNSUPPORTED_NODE },
        NodeKind.IndirectCall => UNSUPPORTED_NODE,
        NodeKind.Index => UNSUPPORTED_NODE,
        NodeKind.OptionalCall => UNSUPPORTED_NODE,
        NodeKind.Field => 0L,
        NodeKind.QualifiedCase => UNSUPPORTED_NODE,
        NodeKind.StructInit => 0L,
        NodeKind.InitializerField => 0L,
        NodeKind.ArrayLiteral => UNSUPPORTED_NODE,
        NodeKind.ListLiteral => UNSUPPORTED_NODE,
        NodeKind.PoolLiteral => UNSUPPORTED_NODE,
        NodeKind.MapLiteral => UNSUPPORTED_NODE,
        NodeKind.SetLiteral => UNSUPPORTED_NODE,
        NodeKind.QueueLiteral => UNSUPPORTED_NODE,
        NodeKind.RingLiteral => UNSUPPORTED_NODE,
        NodeKind.GridIndex => UNSUPPORTED_NODE,
        NodeKind.ToLong => 0L,
        NodeKind.WildcardPattern => UNSUPPORTED_NODE,
        NodeKind.BoolPattern => UNSUPPORTED_NODE,
        NodeKind.CasePattern => UNSUPPORTED_NODE,
        NodeKind.PatternBinding => UNSUPPORTED_NODE,
        NodeKind.IgnoredPatternBinding => UNSUPPORTED_NODE,
        NodeKind.MatchArm => UNSUPPORTED_NODE,
        NodeKind.FunctionType => UNSUPPORTED_NODE,
        NodeKind.FunctionTypeParameter => UNSUPPORTED_NODE,
        NodeKind.Effect => UNSUPPORTED_NODE,
        NodeKind.PayloadType => UNSUPPORTED_NODE,
        NodeKind.AliasedType => UNSUPPORTED_NODE,
        NodeKind.DeclaredType => UNSUPPORTED_NODE,
        NodeKind.TypeArgument => UNSUPPORTED_TYPE_FORM,
        NodeKind.FitType => UNSUPPORTED_NODE,
        NodeKind.ParameterType => {
            if is_core_addr_type(source, tokens, files, tables, compiler, file_index, node) { 0L }
            else if (value.flags & FLAG_TYPE_UNIT) != 0L { 0L }
            else if type_node_is_oversized(source, tokens, files, tables, compiler, node, file_index) { UNSUPPORTED_LARGE_VALUE }
            else if is_aggregate_type(compiler, resolve_value_type(source, tokens, files, tables, compiler, file_index, node)) { 0L }
            else if known_non_scalar_type(source, tokens, files, file_index, value.token) { UNSUPPORTED_TYPE }
            else if value.meta0 > 1L || (value.meta1 & 2097151L) > 0L || ((value.meta1 >> 21L) & 2097151L) > 0L || ((value.meta1 >> 42L) & 2097151L) > 0L || (value.flags & FLAG_RANGE) != 0L { UNSUPPORTED_TYPE_FORM }
            else { 0L }
        },
        NodeKind.ResultType => {
            if is_core_addr_type(source, tokens, files, tables, compiler, file_index, node) { 0L }
            else if (value.flags & FLAG_TYPE_UNIT) != 0L { 0L }
            else if token_is_word_at(source, tokens, files, file_index, value.token, "never") { 0L }
            else if type_node_is_oversized(source, tokens, files, tables, compiler, node, file_index) { UNSUPPORTED_LARGE_VALUE }
            else if is_aggregate_type(compiler, resolve_value_type(source, tokens, files, tables, compiler, file_index, node)) { 0L }
            else if known_non_scalar_type(source, tokens, files, file_index, value.token) { UNSUPPORTED_TYPE }
            else if value.meta0 > 1L || (value.meta1 & 2097151L) > 0L || ((value.meta1 >> 21L) & 2097151L) > 0L || ((value.meta1 >> 42L) & 2097151L) > 0L || (value.flags & FLAG_RANGE) != 0L { UNSUPPORTED_TYPE_FORM }
            else { 0L }
        },
        NodeKind.Annotation => {
            if is_core_addr_type(source, tokens, files, tables, compiler, file_index, node) { 0L }
            else if (value.flags & FLAG_TYPE_UNIT) != 0L { 0L }
            else if type_node_is_oversized(source, tokens, files, tables, compiler, node, file_index) { UNSUPPORTED_LARGE_VALUE }
            else if is_aggregate_type(compiler, resolve_value_type(source, tokens, files, tables, compiler, file_index, node)) { 0L }
            else if known_non_scalar_type(source, tokens, files, file_index, value.token) { UNSUPPORTED_TYPE }
            else if value.meta0 > 1L || (value.meta1 & 2097151L) > 0L || ((value.meta1 >> 21L) & 2097151L) > 0L || ((value.meta1 >> 42L) & 2097151L) > 0L || (value.flags & FLAG_RANGE) != 0L { UNSUPPORTED_TYPE_FORM }
            else { 0L }
        },
        NodeKind.Function => {
            if !is_top_level_function(tables, compiler, node) || value.aux > 0L { UNSUPPORTED_NODE }
            else if (value.flags & FLAG_RECURSIVE) != 0L { UNSUPPORTED_NODE }
            else { 0L }
        },
        NodeKind.Parameter => if (value.flags & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L { UNSUPPORTED_NODE } else { 0L },
        NodeKind.Test => if value.aux > 0L { UNSUPPORTED_NODE } else { 0L },
        NodeKind.Block => 0L,
        NodeKind.Let => 0L,
        NodeKind.Assign => if value.flags < 0L || value.flags > 5L { UNSUPPORTED_ASSIGNMENT } else { 0L },
        NodeKind.ReturnStatement => 0L,
        NodeKind.ExpressionStatement => 0L,
        NodeKind.For => 0L,
        NodeKind.Expect => 0L,
        NodeKind.BreakStatement => 0L,
        NodeKind.ContinueStatement => 0L,
        NodeKind.Unit => 0L,
        NodeKind.Integer => 0L,
        NodeKind.Bool => 0L,
        NodeKind.BytesLiteral => if compiler.core_mode { 0L } else { UNSUPPORTED_NODE },
        NodeKind.Name => {
            if is_function_value_name(files, tables, compiler, node, file_index) { UNSUPPORTED_FUNCTION_VALUE }
            else if builtin_case_name(source, tokens, files, file_index, value.token) { UNSUPPORTED_CASE }
            else { 0L }
        },
        NodeKind.Return => 0L,
        NodeKind.LoopExit => 0L,
        NodeKind.Unary => 0L,
        NodeKind.If => 0L,
        NodeKind.Binary => if value.flags < 0L || value.flags > 15L || value.flags == 5L || value.flags == 6L || value.flags == 7L { UNSUPPORTED_OPERATOR } else { 0L },
        NodeKind.Call => {
            if builtin_function_name(source, tokens, files, file_index, value.token) {
                let id = compiler.token_name_ids[value.token]
                if function_exists_by_name(tables, files, compiler, id) { 0L } else { UNSUPPORTED_CALLEE }
            } else if builtin_case_name(source, tokens, files, file_index, value.token) {
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
        NodeKind.Function => "generic or recursive functions",
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
    } else if hit.category == UNSUPPORTED_FRAME_BUDGET {
        match env.err.write(b"aggregate locals over 1 MiB on one call path") { ok(_) => (), err(_) => env.exit(3) }
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
    var hit = UnsupportedHit { found: false, file: 0L, node: -1L, offset: 0L, category: 0L, token: -1L }
    for node in 0L..tables.nodes.count() {
        let file_index = node_file_index(tables.nodes, files, node)
        let category = unsupported_category_for_node(source, tokens, files, tables, compiler, node, file_index)
        if category == 0L { continue }
        let start = if category == UNSUPPORTED_OPERATOR { tables.nodes[node].anchor } else { tables.nodes[node].start }
        let is_earlier = !hit.found || file_index < hit.file || (file_index == hit.file && (start < hit.offset || (start == hit.offset && (tables.nodes[node].end > tables.nodes[hit.node].end || (tables.nodes[node].end == tables.nodes[hit.node].end && node > hit.node)))))
        if is_earlier {
            hit = UnsupportedHit { found: true, file: file_index, node, offset: start, category, token: tables.nodes[node].token }
        }
    }
    if hit.found { report_unsupported(env, source, files, tokens, tables, compiler, hit) }
}

fn ascii_space(value: byte) -> bool {
    value == 32 || value == 9 || value == 10 || value == 13
}

fn trim_start(bytes: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> long {
    var index = start
    for step in 0L..end - start {
        if index >= end || !ascii_space(bytes[index]) { break }
        index += 1L
    }
    index
}

fn trim_end(bytes: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> long {
    var index = end
    for step in 0L..end - start {
        if index <= start || !ascii_space(bytes[index - 1L]) { break }
        index -= 1L
    }
    index
}

fn manifest_equals(bytes: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long, expected: Ascii max 64) -> bool {
    if end - start != expected.len() { return false }
    for index in 0L..expected.len() {
        if bytes[start + index] != expected.bytes()[index] { return false }
    }
    true
}

fn manifest_number(bytes: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> long {
    if start >= end { return -1L }
    var value = 0L
    var had_digit = false
    for index in start..end {
        let digit = bytes[index]
        if digit == 95 { continue }
        if digit < 48 || digit > 57 { return -1L }
        had_digit = true
        if value > 922337203685477580L { return -1L }
        value = value * 10L + (digit.to_long() - 48L)
        if value < 0L { return -1L }
    }
    if !had_digit { -1L } else { value }
}

fn manifest_memory(bytes: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> long {
    let unit_start = trim_start(bytes, start, end)
    let trimmed_end = trim_end(bytes, unit_start, end)
    var number_end = trimmed_end
    var multiplier = 1048576L
    if trimmed_end - unit_start >= 3L && bytes[trimmed_end - 3L] == 71 && bytes[trimmed_end - 2L] == 105 && bytes[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 3L
        multiplier = 1073741824L
    } else if trimmed_end - unit_start >= 3L && bytes[trimmed_end - 3L] == 77 && bytes[trimmed_end - 2L] == 105 && bytes[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 3L
        multiplier = 1048576L
    } else if trimmed_end - unit_start >= 3L && bytes[trimmed_end - 3L] == 75 && bytes[trimmed_end - 2L] == 105 && bytes[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 3L
        multiplier = 1024L
    } else if trimmed_end - unit_start >= 2L && bytes[trimmed_end - 2L] == 71 && bytes[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 2L
        multiplier = 1000000000L
    } else if trimmed_end - unit_start >= 2L && bytes[trimmed_end - 2L] == 77 && bytes[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 2L
        multiplier = 1000000L
    } else if trimmed_end - unit_start >= 2L && bytes[trimmed_end - 2L] == 75 && bytes[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 2L
        multiplier = 1000L
    } else if trimmed_end - unit_start >= 1L && bytes[trimmed_end - 1L] == 66 {
        number_end = trimmed_end - 1L
        multiplier = 1L
    } else {
        ()
    }
    let trimmed_number_end = trim_end(bytes, unit_start, number_end)
    let value = manifest_number(bytes, unit_start, trimmed_number_end)
    if value < 0L || value > 9223372036854775807L / multiplier { return -1L }
    value * multiplier
}

fn write_manifest_range(out: Out, bytes: Bytes max FILE_SOURCE_CAPACITY, start: long, end: long) -> Result<(), IoError> {
    var value: Bytes max 4096 = Bytes.empty()
    for index in start..end {
        match value.push(bytes[index]) {
            ok(_) => (),
            err(Full) => return err(IoError.TooLarge),
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
    var config = MemoryConfig { capability_mask: 2L, job_headroom: 268435456L, globals_budget: 67108864L, recursion_budget: 0L }
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
    file_index: long,
    token: long,
) -> bool {
    token_is_word_at(source, tokens, files, file_index, token, "int") ||
    token_is_word_at(source, tokens, files, file_index, token, "long") ||
    token_is_word_at(source, tokens, files, file_index, token, "bool") ||
    token_is_word_at(source, tokens, files, file_index, token, "Ascii") ||
    token_is_word_at(source, tokens, files, file_index, token, "Text") ||
    token_is_word_at(source, tokens, files, file_index, token, "Bytes") ||
    token_is_word_at(source, tokens, files, file_index, token, "Option") ||
    token_is_word_at(source, tokens, files, file_index, token, "Result") ||
    token_is_word_at(source, tokens, files, file_index, token, "Full") ||
    token_is_word_at(source, tokens, files, file_index, token, "TextError") ||
    token_is_word_at(source, tokens, files, file_index, token, "Utf8Error")
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
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        if is_builtin_type_name(source, tokens, files, ty.file, ty.name_token) {
            fail_dynamic_checker_error(env, source, files, tokens, compiler, ty.file, tables.nodes[ty.node].start, "type '", ty.name_token, "' is declared more than once or shadows a built-in type")
        }
        for previous in 0L..type_index {
            if struct_record(compiler, previous).name_id == ty.name_id {
                fail_dynamic_checker_error(env, source, files, tokens, compiler, ty.file, tables.nodes[ty.node].start, "type '", ty.name_token, "' is declared more than once or shadows a built-in type")
            }
        }
    }
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
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
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        if type_state(compiler, struct_type_id(compiler, type_index)) == 4L {
            fail_dynamic_checker_error(env, source, files, tokens, compiler, ty.file, tables.nodes[ty.node].start, "value type '", ty.name_token, "' contains itself directly or through Option/Result and would have infinite size")
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
    var count = 0L
    var child = compiler.child_first[parent]
    for step in 0L..tables.nodes[parent].subtree {
        if child < 0L { break }
        if tables.nodes[child].kind == wanted { count += 1L }
        child = compiler.child_next[child]
    }
    count
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
                        compiler.parameters.push(ParameterRecord { node: member, file: file_index, name_id: compiler.token_name_ids[param_node.token], name_token: param_node.token, ty }).unwrap()
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
    if signature.param_count != 0L || signature.result_ty != TY_UNIT {
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
    var count = 0L
    var child = compiler.child_first[parent]
    for step in 0L..tables.nodes[parent].subtree {
        if child < 0L { break }
        count += 1L
        child = compiler.child_next[child]
    }
    count
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
    if compiler.bindings.count() >= BINDING_TABLE_CAPACITY {
        fail_parse_limit(env, files[file_index].name, "self-hosted binding table limit exceeded")
    }
    let id = compiler.bindings.count()
    compiler.bindings.push(BindingRecord { name_id, name_token, file: file_index, ty, mutable, loop_counter, parameter, scope, node }).unwrap()
    id
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
    if actual == TY_NEVER || actual == expected { return }
    let offset = tables.nodes[node].start
    fail_type_mismatch(env, files, compiler, file_index, offset, expected, actual)
}

fn is_unsuffixed_integer(tables: ParseTables, node: long) -> bool {
    node >= 0L && tables.nodes[node].kind == NodeKind.Integer && (tables.nodes[node].flags & FLAG_LONG_SUFFIX) == 0L
}

fn natural_node_type(
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
            let binding = find_binding_in_scope(compiler, scope, compiler.token_name_ids[value.token])
            if binding >= 0L { compiler.bindings[binding].ty } else { -1L }
        },
        NodeKind.Call => {
            if token_is_word_at(source, tokens, files, file_index, value.token, "print") { TY_UNIT }
            else {
                let id = compiler.token_name_ids[value.token]
                let function = find_function_by_name(compiler, id)
                if function >= 0L { compiler.functions[function].result_ty }
                else { -1L }
            }
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
            else { -1L }
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
    let max_low = if ty == TY_INT { if negative { 2147483648L } else { 2147483647L } }
        else if negative { 0L } else { 4294967295L }
    let max_high = if ty == TY_INT { 0L } else { if negative { 2147483648L } else { 2147483647L } }
    let too_big = magnitude.limb3 != 0L || magnitude.limb2 != 0L || magnitude.limb1 > max_high || (magnitude.limb1 == max_high && magnitude.limb0 > max_low)
    if too_big {
        let file = files[file_index]
        let position = position_for_offset(file_index, file.base + syntax.start, compiler)
        match env.err.write(file.name) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
        match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
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
    match write_token_raw(env.err, source, tokens, files[binding.file].base, binding.name_token) { ok(_) => (), err(_) => env.exit(3) }
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
    } else if kind == NodeKind.Field {
        -1L
    } else if kind == NodeKind.Return || kind == NodeKind.ReturnStatement {
        if frame.function_id >= 0L { compiler.functions[frame.function_id].result_ty } else { TY_UNIT }
    } else if kind == NodeKind.ExpressionStatement {
        -1L
    } else if kind == NodeKind.Expect {
        TY_BOOL
    } else if kind == NodeKind.Call {
        if token_is_word_at(source, tokens, files, file_index, tables.nodes[parent].token, "print") { -1L }
        else {
            let function = find_function_by_name(compiler, compiler.token_name_ids[tables.nodes[parent].token])
            if function >= 0L && child_index < compiler.functions[function].param_count {
                compiler.parameters[compiler.functions[function].param_start + child_index].ty
            } else { -1L }
        }
    } else if kind == NodeKind.MethodCall && is_core_sys_receiver(source, tokens, files, tables, compiler, parent, file_index) {
        core_sys_argument_type(core_sys_operation(source, tokens, files, file_index, tables.nodes[parent].token), child_index)
    } else if kind == NodeKind.Cast && child == frame.child0 {
        -1L
    } else if kind == NodeKind.Unary {
        if tables.nodes[parent].flags == 1L { TY_BOOL } else { frame.expected }
    } else if kind == NodeKind.Binary {
        let op = tables.nodes[parent].flags
        if op == 14L || op == 15L { TY_BOOL }
        else if op >= 8L && op <= 13L {
            if is_unsuffixed_integer(tables, child) {
                let other = if child == frame.child0 { frame.child1 } else { frame.child0 }
                let known = natural_node_type(source, tokens, files, tables, compiler, other, frame.scope, file_index)
                if known >= 0L { known } else { -1L }
            } else { -1L }
        } else if frame.expected >= TY_INT && frame.expected <= TY_LONG { frame.expected }
        else {
            let other = if child == frame.child0 { frame.child1 } else { frame.child0 }
            let known = natural_node_type(source, tokens, files, tables, compiler, other, frame.scope, file_index)
            if is_numeric_type(known) && is_unsuffixed_integer(tables, child) { known } else { -1L }
        }
    } else if kind == NodeKind.If {
        if child == frame.child0 { TY_BOOL } else { frame.expected }
    } else if kind == NodeKind.For {
        if child_index < 2L { frame.result_ty } else { -1L }
    } else {
        -1L
    }
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
        if frame.phase == 0L {
            if function_id <= -100000L && (kind == NodeKind.Return || kind == NodeKind.ReturnStatement) {
                fail_at_message(env, files, compiler, file_index, syntax.start, "return is not allowed in a field default")
            }
            if kind == NodeKind.StructInit {
                let type_index = struct_type_matches(compiler, compiler.token_name_ids[syntax.token])
                if type_index < 0L {
                    if is_builtin_type_name(source, tokens, files, file_index, syntax.token) {
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
            if kind == NodeKind.Assign {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.result_ty = -1L
                frame.cursor = 0L
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Return || kind == NodeKind.ReturnStatement || kind == NodeKind.ExpressionStatement || kind == NodeKind.Expect {
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Call {
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.MethodCall {
                if !is_core_sys_receiver(source, tokens, files, tables, compiler, node, file_index) {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "system operations are available only to the core library")
                }
                let operation = core_sys_operation(source, tokens, files, file_index, syntax.token)
                if operation < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "unknown core system operation") }
                let receiver = compiler.child_first[node]
                frame.cursor = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                frame.auxiliary = operation
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Cast {
                let type_node = compiler.child_first[node]
                let value_node = if type_node >= 0L { compiler.child_next[type_node] } else { -1L }
                if type_node < 0L || value_node < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "malformed cast expression") }
                let target_ty = parse_scalar_type(env, source, tokens, files, tables, compiler, file_index, type_node)
                if !is_numeric_type(target_ty) { fail_at_message(env, files, compiler, file_index, syntax.start, "casts in this subset require int or long") }
                frame.child0 = value_node
                frame.child1 = type_node
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
                for bound_index in 0L..2L {
                    let bound = if bound_index == 0L { start } else { finish }
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
                add_local_binding(env, source, files, tokens, tables, compiler, file_index, node, syntax.token, loop_scope, loop_ty, false, true, false)
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
            if kind == NodeKind.Unit {
                compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            } else if kind == NodeKind.BytesLiteral {
                compiler.facts[node] = NodeFact { ty: TY_ADDR, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            } else if kind == NodeKind.Integer {
                let ty = if (syntax.flags & FLAG_LONG_SUFFIX) != 0L { TY_LONG } else if is_numeric_type(frame.expected) { frame.expected } else { TY_INT }
                if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                let value = literal_value(env, files, compiler, tables, file_index, node, ty)
                compiler.facts[node] = NodeFact { ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: value }
            } else if kind == NodeKind.Bool {
                if frame.expected >= 0L && frame.expected != TY_BOOL { require_type(env, files, compiler, file_index, node, frame.expected, TY_BOOL, tables) }
                compiler.facts[node] = NodeFact { ty: TY_BOOL, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: if (syntax.flags & FLAG_VALUE) != 0L { 1L } else { 0L } }
            } else if kind == NodeKind.Name {
                let binding = find_binding_in_scope(compiler, frame.scope, compiler.token_name_ids[syntax.token])
                if binding < 0L {
                    let function = find_function_by_name(compiler, compiler.token_name_ids[syntax.token])
                    if function >= 0L { report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node, offset: syntax.start, category: UNSUPPORTED_NODE, token: syntax.token }) }
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
        if frame.phase == 1L {
            var child = -1L
            var child_scope = frame.scope
            var child_loop_depth = frame.loop_depth
            var child_index = -1L
            if kind == NodeKind.Block || kind == NodeKind.Call || kind == NodeKind.MethodCall {
                child = frame.cursor
                if child >= 0L { frame.cursor = compiler.child_next[child] }
                child_index = 0L
                if kind == NodeKind.Call || kind == NodeKind.MethodCall {
                    var sibling = compiler.child_first[node]
                    var position = 0L
                    for count in 0L..tables.nodes[node].subtree {
                        if sibling < 0L || sibling == child { break }
                        position += 1L
                        sibling = compiler.child_next[sibling]
                    }
                    child_index = position - if kind == NodeKind.MethodCall { 1L } else { 0L }
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
            } else if kind == NodeKind.Return || kind == NodeKind.ReturnStatement || kind == NodeKind.ExpressionStatement || kind == NodeKind.Expect || kind == NodeKind.Unary || kind == NodeKind.Cast || kind == NodeKind.ToLong {
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
                    else { child = frame.child2; child_scope = frame.auxiliary; child_loop_depth += 1L }
                    child_index = frame.cursor
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
            if value_fact.ty == TY_NEVER {
                fail_at_message(env, files, compiler, file_index, tables.nodes[value].start, "a binding needs a value; functions and if expressions used here must return int, long, or bool")
            }
            let ty = if frame.child1 >= 0L { frame.child1 } else { value_fact.ty }
            require_type(env, files, compiler, file_index, value, ty, value_fact.ty, tables)
            let binding = add_local_binding(env, source, files, tokens, tables, compiler, file_index, node, syntax.token, frame.scope, ty, (syntax.flags & FLAG_MUTABLE) != 0L, false, false)
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding, function: -1L, literal: 0L }
        } else if kind == NodeKind.Field {
            let receiver = frame.child0
            let receiver_ty = compiler.facts[receiver].ty
            if !is_aggregate_type(compiler, receiver_ty) {
                let message: Ascii max 160 = "value has no fields; cannot read this field"
                fail_at_message(env, files, compiler, file_index, syntax.anchor, message)
            }
            let type_index = struct_type_index(compiler, receiver_ty)
            let field_index = struct_field_matches(compiler, type_index, compiler.token_name_ids[syntax.token])
            if field_index < 0L {
                fail_unknown_struct_field(env, source, files, tokens, tables, compiler, file_index, syntax.anchor, type_index, syntax.token, false)
            }
            let field_ty = compiler.struct_fields[field_index].ty
            if frame.expected >= 0L && frame.expected != field_ty { require_type(env, files, compiler, file_index, node, frame.expected, field_ty, tables) }
            compiler.facts[node] = NodeFact { ty: field_ty, flags: FACT_FALLS_THROUGH, binding: compiler.facts[receiver].binding, function: -1L, literal: field_index }
        } else if kind == NodeKind.StructInit {
            let type_index = struct_type_index(compiler, frame.result_ty)
            let ty = struct_record(compiler, type_index)
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
            compiler.facts[node] = NodeFact { ty: frame.result_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: type_index }
        } else if kind == NodeKind.Assign {
            let target = frame.child0
            let value = frame.child1
            if target < 0L || (tables.nodes[target].kind != NodeKind.Name && tables.nodes[target].kind != NodeKind.Field) { fail_at_message(env, files, compiler, file_index, syntax.start, "assignment target must be a local name or field path") }
            let target_fact = compiler.facts[target]
            let binding = target_fact.binding
            if binding < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "assignment target must be a local name or field path") }
            if !compiler.bindings[binding].mutable { fail_assignment_error(env, source, files, tokens, tables, compiler, file_index, node, binding) }
            let op = syntax.flags
            let value_fact = compiler.facts[value]
            if op == 0L { require_type(env, files, compiler, file_index, value, target_fact.ty, value_fact.ty, tables) }
            else {
                if !is_numeric_type(target_fact.ty) { fail_at_message(env, files, compiler, file_index, syntax.anchor, "compound assignment requires int or long") }
                require_type(env, files, compiler, file_index, value, target_fact.ty, value_fact.ty, tables)
            }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding, function: -1L, literal: 0L }
        } else if kind == NodeKind.Return || kind == NodeKind.ReturnStatement {
            if is_test { fail_at_message(env, files, compiler, file_index, syntax.start, "a test cannot return; let the test finish so all expectations run") }
            if frame.child0 < 0L {
                if result_ty != TY_UNIT { fail_no_return_value(env, source, files, tokens, compiler, file_index, syntax.start, result_ty, compiler.functions[function_id]) }
                else { compiler.facts[node] = NodeFact { ty: TY_NEVER, flags: FACT_NEVER, binding: -1L, function: -1L, literal: 0L } }
            } else {
                let actual = compiler.facts[frame.child0].ty
                require_type(env, files, compiler, file_index, frame.child0, result_ty, actual, tables)
                compiler.facts[node] = NodeFact { ty: TY_NEVER, flags: FACT_NEVER, binding: -1L, function: -1L, literal: 0L }
            }
        } else if kind == NodeKind.ExpressionStatement {
            let ty = if frame.child0 >= 0L { compiler.facts[frame.child0].ty } else { TY_UNIT }
            compiler.facts[node] = NodeFact { ty: if ty == TY_NEVER { TY_NEVER } else { TY_UNIT }, flags: if ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Expect {
            if !is_test { fail_at_message(env, files, compiler, file_index, syntax.start, "'expect' is only valid inside a test block") }
            let actual = if frame.child0 >= 0L { compiler.facts[frame.child0].ty } else { -1L }
            if actual >= 0L { require_type(env, files, compiler, file_index, frame.child0, TY_BOOL, actual, tables) }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Call {
            let name_id = compiler.token_name_ids[syntax.token]
            let arg_count = count_children(tables, compiler, node)
            if token_is_word_at(source, tokens, files, file_index, syntax.token, "print") {
                if (config.capability_mask & 2L) == 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "package manifest must grant capability 'out' in the 'capabilities' key") }
                if arg_count != 1L { fail_at_message(env, files, compiler, file_index, syntax.start, "print takes one argument, but got an invalid number; call print(value)") }
                let argument = child_at(tables, compiler, node, 0L)
                let arg_ty = compiler.facts[argument].ty
                if !is_numeric_type(arg_ty) && arg_ty != TY_BOOL && !is_aggregate_type(compiler, arg_ty) {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "print supports int, long, bool, Ascii, enum, struct, array, list, queue, ring, grid, map, set, pool, and function values")
                }
                compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            } else {
                let target = find_function_by_name(compiler, name_id)
                if target < 0L { fail_name_error(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token, frame.scope, true) }
                let function = compiler.functions[target]
                check_call_count(env, source, files, tokens, tables, compiler, function, node, file_index)
                if function_id >= 0L {
                    let edge_id = compiler.call_edges.count()
                    let next_edge = compiler.edge_first[function_id]
                    compiler.call_edges.push(CallEdge { from: function_id, to: target, node, next: next_edge }).unwrap()
                    compiler.edge_first[function_id] = edge_id
                }
                let ty = function.result_ty
                compiler.facts[node] = NodeFact { ty, flags: if ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: target, literal: 0L }
            }
        } else if kind == NodeKind.MethodCall {
            let operation = frame.auxiliary
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
            let result_ty = core_sys_result_type(operation)
            if frame.expected >= 0L && frame.expected != result_ty && result_ty != TY_NEVER {
                require_type(env, files, compiler, file_index, node, frame.expected, result_ty, tables)
            }
            compiler.facts[node] = NodeFact { ty: result_ty, flags: if result_ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: operation }
        } else if kind == NodeKind.Cast {
            let source_ty = compiler.facts[frame.child0].ty
            let target_ty = frame.result_ty
            if !is_numeric_type(source_ty) || !is_numeric_type(target_ty) {
                fail_at_message(env, files, compiler, file_index, syntax.start, "casts in this subset require int and long")
            }
            if frame.expected >= 0L && frame.expected != target_ty {
                require_type(env, files, compiler, file_index, node, frame.expected, target_ty, tables)
            }
            compiler.facts[node] = NodeFact { ty: target_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.ToLong {
            let value_ty = compiler.facts[frame.child0].ty
            if value_ty != TY_INT {
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
                if !is_numeric_type(value.ty) { fail_at_message(env, files, compiler, file_index, syntax.anchor, "unary '-' requires int or long") }
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
            } else if op >= 8L && op <= 13L {
                if left.ty != right.ty { fail_mixed_types(env, files, compiler, file_index, syntax.anchor, left.ty, right.ty) }
                if (op == 8L || op == 9L) && (left.ty == TY_UNIT || left.ty == TY_NEVER) {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "equality requires values other than ()")
                }
                if op >= 10L && !is_numeric_type(left.ty) { fail_at_message(env, files, compiler, file_index, syntax.anchor, "ordered comparisons require int or long values") }
                ty = TY_BOOL
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
            else { fail_type_mismatch(env, files, compiler, file_index, syntax.start, then_ty, else_ty) }
            if frame.expected >= 0L && ty != TY_NEVER && ty != frame.expected { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
            compiler.facts[node] = NodeFact { ty, flags: if then_ty == TY_NEVER && else_ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.For {
            let start_ty = compiler.facts[frame.child0].ty
            let end_ty = compiler.facts[frame.child1].ty
            require_type(env, files, compiler, file_index, frame.child0, frame.result_ty, start_ty, tables)
            require_type(env, files, compiler, file_index, frame.child1, frame.result_ty, end_ty, tables)
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Block {
            let has_tail = (syntax.flags & FLAG_HAS_TAIL) != 0L
            let last = node_last_child(tables, compiler, node)
            let tail_ty = if has_tail && last >= 0L { compiler.facts[last].ty } else { TY_UNIT }
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
                let message: Ascii max 160 = "block value must be discarded or returned as unit"
                fail_at_message(env, files, compiler, file_index, tables.nodes[last].start, message)
            }
            if frame.expected >= 0L && frame.expected != TY_UNIT && can_reach && has_tail && tail_ty != TY_NEVER { require_type(env, files, compiler, file_index, last, frame.expected, tail_ty, tables) }
            let result = if !can_reach { TY_NEVER } else if has_tail { tail_ty } else { TY_UNIT }
            compiler.facts[node] = NodeFact { ty: result, flags: if !can_reach || result == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
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
            add_local_binding(env, source, files, tokens, tables, compiler, function.file, parameter.node, parameter.name_token, scope, parameter.ty, false, false, true)
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
    if size > 0L { compiler.frame_own_bytes[graph_node] += size }
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

fn compute_frame_slot_paths(compiler: write CompilerTables) {
    let graph_count = compiler.edge_first.count()
    for node in 0L..graph_count {
        compiler.frame_visit[node] = 0L
        compiler.frame_path_bytes[node] = 0L
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
                var successor = compiler.edge_first[node]
                for edge_step in 0L..compiler.call_edges.count() {
                    if successor < 0L { break }
                    let edge = compiler.call_edges[successor]
                    if edge.to >= 0L && edge.to < graph_count && compiler.frame_path_bytes[edge.to] > largest_child {
                        largest_child = compiler.frame_path_bytes[edge.to]
                    }
                    successor = edge.next
                }
                compiler.frame_path_bytes[node] = compiler.frame_own_bytes[node] + largest_child
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
    compute_frame_slot_paths(compiler)
    if want_test_build {
        for test_index in 0L..compiler.tests.count() {
            let graph_node = test_graph_node(compiler, test_index)
            if compiler.frame_path_bytes[graph_node] > 1048576L {
                let test = compiler.tests[test_index]
                report_frame_budget_unsupported(env, source, files, tokens, tables, compiler, test.file, test.node)
            }
        }
    } else if entry >= 0L && compiler.frame_path_bytes[entry] > 1048576L {
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
        if belongs {
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
        err(Full) => { compiler.ir_overflow = true },
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
    if value >= 32 && value <= 126 && value != 34 && value != 92 {
        ir_push_byte(compiler, ir, value)
    } else {
        ir_push_byte(compiler, ir, 92)
        ir_push_byte(compiler, ir, ir_hex_digit(value.to_long() / 16L, false))
        ir_push_byte(compiler, ir, ir_hex_digit(value.to_long() % 16L, false))
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
    else if ty == TY_UNIT { "void" }
    else if ty == TY_NEVER { "void" }
    else if ty == TY_ADDR { "ptr" }
    else { "i32" }
}

fn binding_for_node(compiler: CompilerTables, node: long) -> long {
    for binding in 0L..compiler.bindings.count() {
        if compiler.bindings[binding].node == node { return binding }
    }
    -1L
}

fn ir_write_value_ref(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long) {
    ir_write_ascii(compiler, ir, "%v")
    ir_write_number(compiler, ir, node)
}

fn native_location(anchor_kind: long, anchor_node: long, byte_offset: long) -> StorageLocation {
    StorageLocation { origin: LOCATION_NATIVE, anchor_kind, anchor_node, byte_offset, copies: 1L, index: 0L }
}

fn aggregate_destination_location(kind: long, node: long) -> StorageLocation {
    if kind == 0L { native_location(0L, node, 0L) }
    else if kind == 1L { native_location(1L, node, 0L) }
    else if kind == 2L { native_location(4L, 0L, 0L) }
    else { native_location(2L, node, 0L) }
}

fn aggregate_source_location(kind: long, node: long) -> StorageLocation {
    if kind == 0L { native_location(0L, node, 0L) }
    else if kind == 1L { native_location(1L, node, 0L) }
    else if kind == 2L { native_location(3L, node, 0L) }
    else { native_location(2L, node, 0L) }
}

fn emit_location_pointer(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    location: StorageLocation,
) {
    // E2i has native slots only; other origins and lane geometry fail closed
    // until the region and collection owners implement them.
    if location.origin != LOCATION_NATIVE || location.copies != 1L || location.index != 0L || location.byte_offset != 0L {
        compiler.ir_overflow = true
        return
    }
    if location.anchor_kind == 0L { ir_write_ascii(compiler, ir, "%agg."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 1L { ir_write_ascii(compiler, ir, "%local."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 2L { ir_write_ascii(compiler, ir, "%addr."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 3L { ir_write_ascii(compiler, ir, "%arg."); ir_write_number(compiler, ir, location.anchor_node) }
    else if location.anchor_kind == 4L { ir_write_ascii(compiler, ir, "%nl.dest") }
    else if location.anchor_kind == 5L { ir_write_ascii(compiler, ir, "%nl.source") }
    else if location.anchor_kind == 6L { ir_write_ascii(compiler, ir, "%nl.left") }
    else if location.anchor_kind == 7L { ir_write_ascii(compiler, ir, "%nl.right") }
    else if location.anchor_kind == 8L { ir_write_ascii(compiler, ir, "%nl.value") }
    else { compiler.ir_overflow = true }
}

fn emit_location_argument(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    location: StorageLocation,
) {
    ir_write_ascii(compiler, ir, "ptr ")
    emit_location_pointer(compiler, ir, location)
}

fn emit_location_parameter(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    binding: long,
) {
    emit_location_argument(compiler, ir, native_location(3L, binding, 0L))
}

fn emit_hidden_destination_argument(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    destination: StorageLocation,
) {
    emit_location_argument(compiler, ir, destination)
}

fn emit_hidden_destination_parameter(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    emit_location_argument(compiler, ir, native_location(4L, 0L, 0L))
}

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
        if exit_kind == EXIT_BREAK { ir_write_ascii(compiler, ir, "  br label %for.end.") }
        else { ir_write_ascii(compiler, ir, "  br label %for.increment.") }
        ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, "\n")
    } else if exit_kind == EXIT_BRANCH {
        ir_write_ascii(compiler, ir, "  br label %")
        if target_kind == BRANCH_IF_END { ir_write_ascii(compiler, ir, "if.end.") }
        else if target_kind == BRANCH_IF_EXPR_END { ir_write_ascii(compiler, ir, "if.expr.end.") }
        else if target_kind == BRANCH_FOR_INCREMENT { ir_write_ascii(compiler, ir, "for.increment.") }
        else { compiler.ir_overflow = true }
        ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, "\n")
    } else { compiler.ir_overflow = true }
}

fn emit_layout_address(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    result_node: long,
    location: StorageLocation,
) {
    if location.origin != LOCATION_NATIVE || location.copies != 1L || location.index != 0L {
        compiler.ir_overflow = true
        return
    }
    ir_write_ascii(compiler, ir, "  %addr."); ir_write_number(compiler, ir, result_node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr ")
    let pointer_location = native_location(location.anchor_kind, location.anchor_node, 0L)
    emit_location_pointer(compiler, ir, pointer_location)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, location.byte_offset); ir_write_ascii(compiler, ir, "\n")
}

fn emit_aggregate_address(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
) {
    let field_index = compiler.facts[node].literal
    let field = compiler.struct_fields[field_index]
    let receiver = compiler.child_first[node]
    if tables.nodes[receiver].kind == NodeKind.Name {
        let binding = compiler.facts[receiver].binding
        if compiler.bindings[binding].parameter { emit_layout_address(compiler, ir, node, native_location(3L, binding, field.offset)) }
        else { emit_layout_address(compiler, ir, node, native_location(1L, binding, field.offset)) }
    } else if tables.nodes[receiver].kind == NodeKind.Field {
        emit_layout_address(compiler, ir, node, native_location(2L, receiver, field.offset))
    } else {
        emit_layout_address(compiler, ir, node, native_location(0L, receiver, field.offset))
    }
}

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
        compiler.type_walk.push(TypeWalkFrame { type_index: current, field_index: -1L, size: 0L, align: 0L }).unwrap()
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

fn emit_aggregate_copy(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    destination: StorageLocation,
    source: StorageLocation,
) {
    ir_write_ascii(compiler, ir, "  call void ")
    emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY)
    ir_push_byte(compiler, ir, 40)
    emit_location_argument(compiler, ir, destination)
    ir_write_ascii(compiler, ir, ", ")
    emit_location_argument(compiler, ir, source)
    ir_write_ascii(compiler, ir, ")\n")
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
    if operation == HELPER_COPY { ir_write_ascii(compiler, ir, "@nl.copy.") }
    else if operation == HELPER_EQUAL { ir_write_ascii(compiler, ir, "@nl.eq.") }
    else if operation == HELPER_PRINT { ir_write_ascii(compiler, ir, "@nl.print.") }
    else if operation == HELPER_FILL { ir_write_ascii(compiler, ir, "@nl.fill.") }
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
    ir_write_ascii(compiler, ir, "@nl.default.")
    ir_write_number(compiler, ir, type_id)
    ir_push_byte(compiler, ir, 46)
    ir_write_number(compiler, ir, field_index)
}

fn emit_type_helper_call_one(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    operation: long,
    operand: StorageLocation,
) {
    emit_type_helper_symbol(compiler, ir, type_id, operation)
    ir_push_byte(compiler, ir, 40)
    emit_location_argument(compiler, ir, operand)
    ir_push_byte(compiler, ir, 41)
}

fn emit_type_helper_call_two(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    type_id: long,
    operation: long,
    first: StorageLocation,
    second: StorageLocation,
) {
    emit_type_helper_symbol(compiler, ir, type_id, operation)
    ir_push_byte(compiler, ir, 40)
    emit_location_argument(compiler, ir, first)
    ir_write_ascii(compiler, ir, ", ")
    emit_location_argument(compiler, ir, second)
    ir_push_byte(compiler, ir, 41)
}

fn aggregate_source_kind(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    if tables.nodes[node].kind == NodeKind.Field { 3L }
    else if tables.nodes[node].kind == NodeKind.Name {
        let binding = compiler.facts[node].binding
        if compiler.bindings[binding].parameter { 2L } else { 1L }
    } else { 0L }
}

fn aggregate_source_id(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    if tables.nodes[node].kind == NodeKind.Name { compiler.facts[node].binding }
    else { node }
}

fn emit_store_scalar(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    ty: long,
    value_node: long,
) {
    if ty == TY_BOOL {
        ir_write_ascii(compiler, ir, "  %bool.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, " to i8\n  store i8 %bool.store."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    } else {
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value_node); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    }
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
    token_is_word_at(source, tokens, files, file_index, token, "nl_context_destroy") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_env_create") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_env_destroy") ||
    token_is_word_at(source, tokens, files, file_index, token, "nl_register_file") ||
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
    else { ir_write_ascii(compiler, ir, "  call void @nl_fail(i32 "); ir_write_number(compiler, ir, kind); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, file_index + compiler.file_id_base); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\n") }
    ir_write_ascii(compiler, ir, "ov.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
}

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
    ir_write_ascii(compiler, ir, "  %div.zero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", 0\n  br i1 %div.zero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.zero.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.nonzero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ndiv.zero.fail."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void @nl_fail(i32 9, i32 "); ir_write_number(compiler, ir, file_index); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\ndiv.nonzero."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    let minimum = if ty == TY_INT { "-2147483648" } else { "-9223372036854775808" }
    let overflow_kind = if ty == TY_INT { 12L } else { 13L }
    ir_write_ascii(compiler, ir, "  %div.min."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, minimum); ir_write_ascii(compiler, ir, "\n  %div.minusone."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp eq "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, ", -1\n  %div.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = and i1 %div.min."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", %div.minusone."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\n")
    if is_remainder {
        ir_write_ascii(compiler, ir, "  br i1 %div.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %rem.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %rem.compute."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nrem.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  store "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " 0, ptr %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  br label %rem.join."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nrem.compute."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %rem.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = srem "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, "\n  store "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " %rem.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n  br label %rem.join."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nrem.join."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, ", ptr %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
    } else {
        ir_write_ascii(compiler, ir, "  br i1 %div.special."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.overflow."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %div.safe."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\ndiv.overflow."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  call void @nl_fail(i32 "); ir_write_number(compiler, ir, overflow_kind); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, file_index); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ")\n  unreachable\ndiv.safe."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = sdiv "); ir_write_ascii(compiler, ir, llvm_ty); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, left); ir_write_ascii(compiler, ir, ", "); ir_write_value_ref(compiler, ir, right); ir_write_ascii(compiler, ir, "\n")
    }
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
    let field_target = tables.nodes[target].kind == NodeKind.Field
    if !field_target { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
    if op == 1L || op == 2L || op == 3L {
        let binary_op = op - 1L
        ir_write_ascii(compiler, ir, "  %ov.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } @llvm.s")
        if binary_op == 0L { ir_write_ascii(compiler, ir, "add") } else if binary_op == 1L { ir_write_ascii(compiler, ir, "sub") } else { ir_write_ascii(compiler, ir, "mul") }
        ir_write_ascii(compiler, ir, ".with.overflow."); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, ", "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ")\n")
        ir_write_ascii(compiler, ir, "  %asgn.value."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n  %ov.flag."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 1\n")
        let failure_kind = if ty == TY_INT { binary_op + 1L } else { binary_op + 5L }
        emit_runtime_failure(files, tables, compiler, ir, node, file_index, failure_kind)
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %asgn.value."); ir_write_number(compiler, ir, node)
        if field_target { ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, target) }
        else { ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding) }
        ir_write_ascii(compiler, ir, ", align 1\n")
    } else {
        emit_checked_division(files, tables, compiler, ir, node, file_index, target, value, ty, op == 5L)
        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " %v"); ir_write_number(compiler, ir, node)
        if field_target { ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, target) }
        else { ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding) }
        ir_write_ascii(compiler, ir, ", align 1\n")
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
    else { -1L }
}

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
    let receiver = compiler.child_first[node]
    var first_arg = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
    if operation == SYS_NULL {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = inttoptr i64 0 to ptr\n")
        return
    }
    if operation == SYS_STATE {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr inbounds ["); ir_write_number(compiler, ir, embedded_core_state_bytes()); ir_write_ascii(compiler, ir, " x i8], ptr @nl.core.state, i64 0, i64 0\n")
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
        ir_write_ascii(compiler, ir, "  %sys.load."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, value_type); ir_write_ascii(compiler, ir, ", ptr %sys.ptr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
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
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i32 @main(i32 "); ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, argv_arg); ir_write_ascii(compiler, ir, ", ptr "); ir_write_value_ref(compiler, ir, envp_arg); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    let argument_count = core_sys_argument_count(operation)
    let syscall = core_syscall_number(operation)
    for argument_index in 0L..argument_count {
        let argument = child_at(tables, compiler, node, argument_index + 1L)
        let ty = core_sys_argument_type(operation, argument_index)
        ir_write_ascii(compiler, ir, "  %sys.arg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, argument_index); ir_write_ascii(compiler, ir, " = ")
        if ty == TY_ADDR { ir_write_ascii(compiler, ir, "ptrtoint ptr "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n") }
        else if ty == TY_INT { ir_write_ascii(compiler, ir, "sext i32 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n") }
        else if ty == TY_BOOL { ir_write_ascii(compiler, ir, "zext i1 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n") }
        else { ir_write_ascii(compiler, ir, "add i64 0, "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, "\n") }
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

fn emit_expr_linear(
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
    compiler.expr_work.clear()
    compiler.expr_work.push(EmitExprFrame { node, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
    for emit_step in 0L..MAX_PARSE_WORK {
        if compiler.expr_work.count() == 0L { break }
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
                if ty == TY_UNIT || is_aggregate_type(compiler, ty) { () }
                else if ty == TY_BOOL { ir_write_ascii(compiler, ir, "  %bool.load."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load i8, ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = trunc i8 %bool.load."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " to i1\n") }
                else { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Field {
                frame.child0 = compiler.child_first[current]
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.StructInit {
                frame.cursor = compiler.child_first[current]
                frame.phase = 50L
                compiler.expr_work[frame_index] = frame
            } else if kind == NodeKind.BytesLiteral {
                let literal = decode_string_token(source, tokens, files[file_index].base, syntax.extra, true)
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = getelementptr inbounds ["); ir_write_number(compiler, ir, literal.count() + 1L); ir_write_ascii(compiler, ir, " x i8], ptr @.nl.core.literal."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", i64 0, i64 0\n")
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else if kind == NodeKind.Unary {
                frame.child0 = compiler.child_first[current]
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Binary {
                frame.child0 = compiler.child_first[current]
                frame.child1 = compiler.child_next[frame.child0]
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: frame.child0, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else if kind == NodeKind.Call {
                frame.cursor = compiler.child_first[current]
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
            } else if kind == NodeKind.MethodCall {
                let receiver = compiler.child_first[current]
                frame.cursor = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
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
            } else if kind == NodeKind.Block {
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
                if is_break { lower_scope_exit(compiler, ir, -1L, EXIT_BREAK, 0L, loop.node, TY_UNIT, -1L) }
                else { lower_scope_exit(compiler, ir, -1L, EXIT_CONTINUE, 0L, loop.node, TY_UNIT, -1L) }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            } else {
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.Field && frame.phase == 1L {
            emit_aggregate_address(tables, compiler, ir, current)
            let ty = compiler.facts[current].ty
            if !is_aggregate_type(compiler, ty) && ty != TY_UNIT { emit_load_scalar(compiler, ir, current, ty) }
            match compiler.expr_work.pop() { some(_) => (), none => () }
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
                    var count = 0L
                    for field_offset in 0L..ty.field_count {
                        let field_index = ty.field_start + field_offset
                        var child = compiler.child_first[current]
                        for field_step in 0L..tables.nodes[current].subtree {
                            if child < 0L { break }
                            if compiler.facts[child].binding == field_index { count += 1L }
                            child = compiler.child_next[child]
                        }
                    }
                    ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_FILL); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top, "); emit_location_argument(compiler, ir, native_location(0L, current, 0L)); ir_write_ascii(compiler, ir, ", ptr @.nl.given."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, count); ir_write_ascii(compiler, ir, ")\n")
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.StructInit && frame.phase == 51L {
            let initializer = frame.child0
            let value = frame.child1
            let field_index = compiler.facts[initializer].binding
            let field = compiler.struct_fields[field_index]
            emit_layout_address(compiler, ir, initializer, native_location(0L, current, field.offset))
            if is_aggregate_type(compiler, field.ty) {
                var source_kind = 0L
                var source_node = value
                if tables.nodes[value].kind == NodeKind.Name {
                    let binding = compiler.facts[value].binding
                    if compiler.bindings[binding].parameter { source_kind = 2L; source_node = binding }
                    else { source_kind = 1L; source_node = binding }
                } else if tables.nodes[value].kind == NodeKind.Field { source_kind = 3L }
                else { () }
                emit_aggregate_copy(compiler, ir, field.ty, aggregate_destination_location(3L, initializer), aggregate_source_location(source_kind, source_node))
            } else if field.ty != TY_UNIT {
                emit_store_scalar(compiler, ir, initializer, field.ty, value)
            } else { () }
            frame.phase = 50L
            compiler.expr_work[frame_index] = frame
        } else if kind == NodeKind.Unary {
            let ty = compiler.facts[current].ty
            if syntax.flags == 1L {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = xor i1 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", true\n")
            } else {
                ir_write_ascii(compiler, ir, "  %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = call { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } @llvm.ssub.with.overflow."); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " 0, "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ")\n")
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 0\n  %ov.flag."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = extractvalue { "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", i1 } %ov.pair."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", 1\n")
                let failure_kind = if ty == TY_INT { 4L } else { 8L }
                emit_runtime_failure(files, tables, compiler, ir, current, file_index, failure_kind)
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Cast && frame.phase == 1L {
            let source_ty = compiler.facts[frame.child0].ty
            let target_ty = frame.auxiliary
            if source_ty == target_ty {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = add "); ir_write_ascii(compiler, ir, llvm_type_name(target_ty)); ir_write_ascii(compiler, ir, " 0, "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, "\n")
            } else if source_ty == TY_INT && target_ty == TY_LONG {
                ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = sext i32 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i64\n")
            } else {
                ir_write_ascii(compiler, ir, "  %cast.low."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = icmp sge i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", -2147483648\n  %cast.high."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = icmp sle i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, ", 2147483647\n  %cast.ok."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = and i1 %cast.low."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", %cast.high."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\n  br i1 %cast.ok."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %cast.good."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", label %cast.fail."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, "\ncast.fail."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  call void @nl_fail(i32 10, i32 "); ir_write_number(compiler, ir, file_index + compiler.file_id_base); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + syntax.anchor, compiler).line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position_for_offset(file_index, files[file_index].base + syntax.anchor, compiler).col); ir_write_ascii(compiler, ir, ")\n  unreachable\ncast.good."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ":\n  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = trunc i64 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i32\n")
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.ToLong && frame.phase == 1L {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = sext i32 "); ir_write_value_ref(compiler, ir, frame.child0); ir_write_ascii(compiler, ir, " to i64\n")
            match compiler.expr_work.pop() { some(_) => (), none => () }
        } else if kind == NodeKind.Return && frame.phase == 17L {
            if is_aggregate_type(compiler, return_ty) {
                let source_kind = aggregate_source_kind(tables, compiler, frame.child0)
                let source_node = aggregate_source_id(tables, compiler, frame.child0)
                emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(2L, 0L), aggregate_source_location(source_kind, source_node))
                lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L)
            } else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN_VALUE, 0L, 0L, return_ty, frame.child0) }
            match compiler.expr_work.pop() { some(_) => (), none => () }
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
            if (op == 8L || op == 9L) && is_aggregate_type(compiler, compiler.facts[frame.child0].ty) &&
                (tables.nodes[frame.child0].kind == NodeKind.Name || tables.nodes[frame.child0].kind == NodeKind.Field) {
                let ty = compiler.facts[frame.child0].ty
                let source_kind = aggregate_source_kind(tables, compiler, frame.child0)
                let source_node = aggregate_source_id(tables, compiler, frame.child0)
                emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(0L, frame.child0), aggregate_source_location(source_kind, source_node))
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
            } else if (op == 8L || op == 9L) && is_aggregate_type(compiler, compiler.facts[left].ty) {
                let ty = compiler.facts[left].ty
                ir_write_ascii(compiler, ir, "  %eq.value."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = call i1 ")
                let left_location = if tables.nodes[left].kind == NodeKind.Name || tables.nodes[left].kind == NodeKind.Field { native_location(0L, left, 0L) }
                    else { aggregate_source_location(aggregate_source_kind(tables, compiler, left), aggregate_source_id(tables, compiler, left)) }
                let right_location = aggregate_source_location(aggregate_source_kind(tables, compiler, right), aggregate_source_id(tables, compiler, right))
                emit_type_helper_call_two(compiler, ir, ty, HELPER_EQUAL, left_location, right_location)
                ir_push_byte(compiler, ir, 10)
                if op == 8L {
                    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = select i1 true, i1 %eq.value."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", i1 false\n")
                } else {
                    ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = xor i1 %eq.value."); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, ", true\n")
                }
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
        } else if kind == NodeKind.Call {
            if frame.phase == 2L {
                let argument = frame.child0
                if tables.nodes[argument].kind == NodeKind.Name || tables.nodes[argument].kind == NodeKind.Field {
                    let ty = compiler.facts[argument].ty
                    let source_kind = aggregate_source_kind(tables, compiler, argument)
                    let source_node = aggregate_source_id(tables, compiler, argument)
                    emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(0L, argument), aggregate_source_location(source_kind, source_node))
                }
                frame.phase = 1L
                compiler.expr_work[frame_index] = frame
            } else if frame.cursor >= 0L {
                let argument = frame.cursor
                frame.cursor = compiler.child_next[argument]
                frame.phase = if is_aggregate_type(compiler, compiler.facts[argument].ty) { 2L } else { 1L }
                frame.child0 = argument
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: argument, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                let is_print = token_is_word_at(source, tokens, files, file_index, syntax.token, "print")
                let first_arg = compiler.child_first[current]
                if is_print {
                    let arg_ty = compiler.facts[first_arg].ty
                    if is_aggregate_type(compiler, arg_ty) {
                        ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_one(compiler, ir, arg_ty, HELPER_PRINT, aggregate_source_location(aggregate_source_kind(tables, compiler, first_arg), aggregate_source_id(tables, compiler, first_arg))); ir_write_ascii(compiler, ir, "\n  call void @nl_print_newline()\n")
                    } else {
                        ir_write_ascii(compiler, ir, "  call void @nl_print_")
                        if arg_ty == TY_INT { ir_write_ascii(compiler, ir, "int(i32 ") }
                        else if arg_ty == TY_LONG { ir_write_ascii(compiler, ir, "long(i64 ") }
                        else { ir_write_ascii(compiler, ir, "bool(i1 zeroext ") }
                        ir_write_value_ref(compiler, ir, first_arg); ir_write_ascii(compiler, ir, ")\n")
                    }
                } else {
                    let target = compiler.facts[current].function
                    let function = compiler.functions[target]
                    let return_ty = function.result_ty
                    let aggregate_result = is_aggregate_type(compiler, return_ty)
                    if return_ty != TY_UNIT && return_ty != TY_NEVER && !aggregate_result { ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, current); ir_write_ascii(compiler, ir, " = ") } else { ir_write_ascii(compiler, ir, "  ") }
                    ir_write_ascii(compiler, ir, "call ")
                    if aggregate_result || return_ty == TY_UNIT || return_ty == TY_NEVER { ir_write_ascii(compiler, ir, "void") }
                    else { ir_write_ascii(compiler, ir, llvm_type_name(return_ty)) }
                    ir_push_byte(compiler, ir, 32)
                    if compiler.core_mode {
                        ir_write_core_function_symbol(source, files, tokens, compiler, ir, function, target)
                        ir_push_byte(compiler, ir, 40)
                    } else {
                        ir_write_ascii(compiler, ir, "@nl_fn_"); ir_write_number(compiler, ir, target); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top")
                    }
                    var wrote_argument = !compiler.core_mode
                    if aggregate_result {
                        if wrote_argument { ir_write_ascii(compiler, ir, ", ") }
                        emit_hidden_destination_argument(compiler, ir, native_location(0L, current, 0L))
                        wrote_argument = true
                    }
                    var arg = first_arg
                    for arg_index in 0L..function.param_count {
                        let param_ty = compiler.parameters[function.param_start + arg_index].ty
                        if param_ty != TY_UNIT {
                            if wrote_argument { ir_write_ascii(compiler, ir, ", ") }
                            if is_aggregate_type(compiler, param_ty) {
                                emit_location_argument(compiler, ir, native_location(0L, arg, 0L))
                            } else {
                                ir_write_ascii(compiler, ir, llvm_type_name(param_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, arg)
                            }
                            wrote_argument = true
                        }
                        arg = compiler.child_next[arg]
                    }
                    ir_write_ascii(compiler, ir, ")\n")
                    if return_ty == TY_NEVER { ir_write_ascii(compiler, ir, "  unreachable\n") }
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
            }
        } else if kind == NodeKind.MethodCall {
            if frame.cursor >= 0L {
                let argument = frame.cursor
                frame.cursor = compiler.child_next[argument]
                compiler.expr_work[frame_index] = frame
                compiler.expr_work.push(EmitExprFrame { node: argument, phase: 0L, cursor: -1L, child0: -1L, child1: -1L, child2: -1L, auxiliary: -1L, reachable: true }).unwrap()
            } else {
                emit_sys_method(source, files, tokens, tables, compiler, ir, current, file_index)
                match compiler.expr_work.pop() { some(_) => (), none => () }
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
                if compiler.expr_work.count() > 0L {
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
                        emit_aggregate_copy(compiler, ir, result_ty, aggregate_destination_location(0L, frame.auxiliary), aggregate_source_location(0L, current))
                    } else {
                        ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(result_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, current); ir_write_ascii(compiler, ir, ", ptr %if.slot."); ir_write_number(compiler, ir, frame.auxiliary); ir_write_ascii(compiler, ir, ", align 1\n")
                    }
                }
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L)
            }
            match compiler.expr_work.pop() { some(_) => (), none => () }
            if compiler.expr_work.count() > 0L {
                let parent_index = compiler.expr_work.count() - 1L
                var parent = compiler.expr_work[parent_index]
                if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = any_falls }
                compiler.expr_work[parent_index] = parent
            }
        } else if kind == NodeKind.Block && frame.phase == 10L {
            if !frame.reachable {
                match compiler.expr_work.pop() { some(_) => (), none => () }
                if compiler.expr_work.count() > 0L {
                    let parent_index = compiler.expr_work.count() - 1L
                    var parent = compiler.expr_work[parent_index]
                    if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 2L { parent.cursor = 0L }
                    else if tables.nodes[parent.node].kind == NodeKind.If && parent.phase == 3L { parent.reachable = false }
                    else { () }
                    compiler.expr_work[parent_index] = parent
                }
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
                    }
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
                    if tables.nodes[statement].kind == NodeKind.BreakStatement { lower_scope_exit(compiler, ir, -1L, EXIT_BREAK, 0L, loop.node, TY_UNIT, -1L) }
                    else { lower_scope_exit(compiler, ir, -1L, EXIT_CONTINUE, 0L, loop.node, TY_UNIT, -1L) }
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
                if frame.auxiliary >= 0L {
                    lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L)
                }
                match compiler.expr_work.pop() { some(_) => (), none => () }
                if compiler.expr_work.count() > 0L {
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
            } else if frame.auxiliary >= 0L && compiler.facts[frame.child1].ty != TY_UNIT {
                let parent = frame.auxiliary
                let tail_ty = compiler.facts[frame.child1].ty
                if is_aggregate_type(compiler, tail_ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, frame.child1)
                    let source_node = aggregate_source_id(tables, compiler, frame.child1)
                    emit_aggregate_copy(compiler, ir, tail_ty, aggregate_destination_location(0L, parent), aggregate_source_location(source_kind, source_node))
                } else {
                    ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(tail_ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, frame.child1); ir_write_ascii(compiler, ir, ", ptr %if.slot."); ir_write_number(compiler, ir, parent); ir_write_ascii(compiler, ir, ", align 1\n")
                }
                lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, parent, TY_UNIT, -1L)
            } else if frame.auxiliary >= 0L { lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_EXPR_END, frame.auxiliary, TY_UNIT, -1L) } else { () }
            match compiler.expr_work.pop() { some(_) => (), none => () }
            if compiler.expr_work.count() > 0L {
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
                emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(1L, binding), aggregate_source_location(source_kind, source_node))
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
                    let destination_kind = if tables.nodes[target].kind == NodeKind.Field { 3L } else { 1L }
                    let destination_node = if tables.nodes[target].kind == NodeKind.Field { target } else { binding }
                    let source_kind = aggregate_source_kind(tables, compiler, value)
                    let source_node = aggregate_source_id(tables, compiler, value)
                    emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(destination_kind, destination_node), aggregate_source_location(source_kind, source_node))
                } else if ty == TY_BOOL {
                    if tables.nodes[target].kind == NodeKind.Field { emit_store_scalar(compiler, ir, target, ty, value) }
                    else { ir_write_ascii(compiler, ir, "  %block.bool."); ir_write_number(compiler, ir, statement); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %block.bool."); ir_write_number(compiler, ir, statement); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
                } else if ty != TY_UNIT {
                    ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value)
                    if tables.nodes[target].kind == NodeKind.Field { ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, target) }
                    else { ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding) }
                    ir_write_ascii(compiler, ir, ", align 1\n")
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
                emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(2L, 0L), aggregate_source_location(source_kind, source_node))
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
            ir_write_ascii(compiler, ir, "  call void @nl_expect_fail_header(i32 "); ir_write_number(compiler, ir, file_index); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.line); ir_write_ascii(compiler, ir, ", i32 "); ir_write_number(compiler, ir, position.col); ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds (["); ir_write_number(compiler, ir, length); ir_write_ascii(compiler, ir, " x i8], ptr @.nl.expect."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 0, i64 0))\n")
            ir_write_ascii(compiler, ir, "  call void @nl_expect_fail_left()\n  call void "); emit_type_helper_call_one(compiler, ir, operand_ty, HELPER_PRINT, native_location(0L, left_node, 0L))
            ir_write_ascii(compiler, ir, "\n  call void @nl_print_newline()\n  call void @nl_expect_fail_right()\n  call void "); emit_type_helper_call_one(compiler, ir, operand_ty, HELPER_PRINT, aggregate_source_location(aggregate_source_kind(tables, compiler, right_node), aggregate_source_id(tables, compiler, right_node))); ir_write_ascii(compiler, ir, "\n  call void @nl_print_newline()\n")
        } else {
        if operand_ty == TY_INT || operand_ty == TY_BOOL {
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
        ir_write_ascii(compiler, ir, "  call void @nl_expect_fail_compare(i32 ")
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
        ir_write_ascii(compiler, ir, "  call void @nl_expect_fail_bool(i32 ")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.line)
        ir_write_ascii(compiler, ir, ", i32 ")
        ir_write_number(compiler, ir, position.col)
        ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, length)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.expect.")
        ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0))\n")
    }
    lower_scope_exit(compiler, ir, -1L, EXIT_TEST_FAILURE, 0L, 0L, TY_UNIT, -1L)
    ir_write_ascii(compiler, ir, "expect.pass.")
    ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ":\n")
}

fn emit_expect_statement(
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

fn emit_function_body(
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
) {
    compiler.work.clear()
    compiler.emit_loops.clear()
    compiler.ir_terminated = false
    compiler.work.push(CheckFrame { node: body, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[body], child0: node_last_child(tables, compiler, body), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
    for emit_step in 0L..MAX_PARSE_WORK {
        if compiler.work.count() == 0L { break }
        let frame_index = compiler.work.count() - 1L
        var frame = compiler.work[frame_index]
        if frame.phase == 100L {
            if frame.child2 == 1L { lower_scope_exit(compiler, ir, -1L, EXIT_BRANCH, BRANCH_IF_END, frame.node, TY_UNIT, -1L) }
            if frame.child1 >= 0L {
                ir_write_ascii(compiler, ir, "if.else."); ir_write_number(compiler, ir, frame.node); ir_write_ascii(compiler, ir, ":\n")
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
        if !frame.reachable {
            frame.cursor = -1L
            compiler.work[frame_index] = frame
        }
        if frame.cursor < 0L {
            if frame.node == body && frame.reachable {
                lower_scope_exit(compiler, ir, -1L, EXIT_FALLTHROUGH, if is_test { 1L } else { 0L }, 0L, return_ty, -1L)
            }
            match compiler.work.pop() { some(_) => (), none => () }
            if compiler.work.count() > 0L {
                let parent_index = compiler.work.count() - 1L
                var parent = compiler.work[parent_index]
                if parent.phase == 100L { parent.child2 = if frame.reachable { 1L } else { 0L } }
                else if parent.phase == 101L { parent.auxiliary = if frame.reachable { 1L } else { 0L } }
                else if parent.phase == 200L { parent.auxiliary = if frame.reachable { 1L } else { 0L } }
                else if !frame.reachable { parent.reachable = false }
                else { () }
                compiler.work[parent_index] = parent
            }
            continue
        }
        let child = frame.cursor
        frame.cursor = compiler.child_next[child]
        compiler.work[frame_index] = frame
        let is_statement = tables.nodes[child].kind == NodeKind.Let || tables.nodes[child].kind == NodeKind.Assign || tables.nodes[child].kind == NodeKind.ExpressionStatement || tables.nodes[child].kind == NodeKind.ReturnStatement || tables.nodes[child].kind == NodeKind.For || tables.nodes[child].kind == NodeKind.Expect || tables.nodes[child].kind == NodeKind.BreakStatement || tables.nodes[child].kind == NodeKind.ContinueStatement || tables.nodes[child].kind == NodeKind.Block
        if !is_statement {
            emit_expr_linear(source, files, tokens, tables, compiler, ir, child, file_index, return_ty, is_test)
            if frame.node == body {
                if compiler.facts[child].ty != TY_NEVER {
                    if is_test { lower_scope_exit(compiler, ir, -1L, EXIT_TEST_SUCCESS, 0L, 0L, TY_UNIT, -1L) }
                    else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
                    else if is_aggregate_type(compiler, return_ty) {
                        let source_kind = aggregate_source_kind(tables, compiler, child)
                        let source_node = aggregate_source_id(tables, compiler, child)
                        emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(2L, 0L), aggregate_source_location(source_kind, source_node))
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
            emit_expr_linear(source, files, tokens, tables, compiler, ir, value, file_index, return_ty, is_test)
            let binding = compiler.facts[child].binding
            let ty = compiler.bindings[binding].ty
            if is_aggregate_type(compiler, ty) {
                let source_kind = aggregate_source_kind(tables, compiler, value)
                let source_node = aggregate_source_id(tables, compiler, value)
                emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(1L, binding), aggregate_source_location(source_kind, source_node))
            } else if ty == TY_BOOL {
                ir_write_ascii(compiler, ir, "  %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
            } else if ty != TY_UNIT {
                ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
            } else { () }
        } else if kind == NodeKind.Assign {
            let target = compiler.child_first[child]
            let value = compiler.child_next[target]
            if tables.nodes[target].kind == NodeKind.Field { emit_expr_linear(source, files, tokens, tables, compiler, ir, target, file_index, return_ty, is_test) }
            emit_expr_linear(source, files, tokens, tables, compiler, ir, value, file_index, return_ty, is_test)
            let binding = compiler.facts[target].binding
            let ty = compiler.facts[target].ty
            let op = tables.nodes[child].flags
            if op == 0L {
                if is_aggregate_type(compiler, ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, value)
                    let source_node = aggregate_source_id(tables, compiler, value)
                    let destination_kind = if tables.nodes[target].kind == NodeKind.Field { 3L } else { 1L }
                    let destination_node = if tables.nodes[target].kind == NodeKind.Field { target } else { binding }
                    emit_aggregate_copy(compiler, ir, ty, aggregate_destination_location(destination_kind, destination_node), aggregate_source_location(source_kind, source_node))
                } else if ty == TY_BOOL {
                    if tables.nodes[target].kind == NodeKind.Field { emit_store_scalar(compiler, ir, target, ty, value) }
                    else { ir_write_ascii(compiler, ir, "  %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, value); ir_write_ascii(compiler, ir, " to i8\n  store i8 %bool.store."); ir_write_number(compiler, ir, child); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n") }
                } else if ty != TY_UNIT {
                    ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, value)
                    if tables.nodes[target].kind == NodeKind.Field { ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, target) }
                    else { ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding) }
                    ir_write_ascii(compiler, ir, ", align 1\n")
                } else { () }
            } else {
                emit_compound_assignment(files, tables, compiler, ir, child, file_index, target, binding, value, ty, op)
            }
        } else if kind == NodeKind.ExpressionStatement {
            let expression = compiler.child_first[child]
            if expression >= 0L { emit_expr_linear(source, files, tokens, tables, compiler, ir, expression, file_index, return_ty, is_test) }
        } else if kind == NodeKind.ReturnStatement {
            let value = compiler.child_first[child]
            if value >= 0L {
                emit_expr_linear(source, files, tokens, tables, compiler, ir, value, file_index, return_ty, is_test)
                if is_aggregate_type(compiler, return_ty) {
                    let source_kind = aggregate_source_kind(tables, compiler, value)
                    let source_node = aggregate_source_id(tables, compiler, value)
                    emit_aggregate_copy(compiler, ir, return_ty, aggregate_destination_location(2L, 0L), aggregate_source_location(source_kind, source_node))
                    lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L)
                } else if return_ty == TY_UNIT { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
                else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN_VALUE, 0L, 0L, return_ty, value) }
            } else if is_test { lower_scope_exit(compiler, ir, -1L, EXIT_TEST_FAILURE, 0L, 0L, TY_UNIT, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_RETURN, 0L, 0L, return_ty, -1L) }
            frame.reachable = false
            compiler.work[frame_index] = frame
        } else if kind == NodeKind.Block {
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
            compiler.emit_loops.push(EmitLoop { node: child, binding }).unwrap()
            compiler.work.push(CheckFrame { node: child, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 200L, cursor: -1L, child0: finish, child1: binding, child2: -1L, result_ty: ty, auxiliary: 1L, reachable: true }).unwrap()
            compiler.work.push(CheckFrame { node: loop_body, scope: -1L, expected: -1L, function_id, loop_depth: 0L, is_test, phase: 0L, cursor: compiler.child_first[loop_body], child0: node_last_child(tables, compiler, loop_body), child1: -1L, child2: -1L, result_ty: -1L, auxiliary: 0L, reachable: true }).unwrap()
        } else if kind == NodeKind.BreakStatement || kind == NodeKind.ContinueStatement {
            let loop = compiler.emit_loops[compiler.emit_loops.count() - 1L]
            if kind == NodeKind.BreakStatement { lower_scope_exit(compiler, ir, -1L, EXIT_BREAK, 0L, loop.node, TY_UNIT, -1L) }
            else { lower_scope_exit(compiler, ir, -1L, EXIT_CONTINUE, 0L, loop.node, TY_UNIT, -1L) }
            frame.reachable = false
            compiler.work[frame_index] = frame
        } else {
            ()
        }
    }
}

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
        if is_aggregate_type(compiler, function.result_ty) { ir_write_ascii(compiler, ir, ", "); emit_hidden_destination_parameter(compiler, ir) }
    }
    var wrote_parameter = !compiler.core_mode
    if compiler.core_mode && is_aggregate_type(compiler, function.result_ty) { emit_hidden_destination_parameter(compiler, ir); wrote_parameter = true }
    for parameter_index in 0L..function.param_count {
        let parameter = compiler.parameters[function.param_start + parameter_index]
        let binding = binding_for_node(compiler, parameter.node)
        if parameter.ty == TY_UNIT { continue }
        if wrote_parameter { ir_write_ascii(compiler, ir, ", ") }
        if is_aggregate_type(compiler, parameter.ty) {
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
    let body_first = function.body - tables.nodes[function.body].subtree + 1L
    for node in 0L..tables.nodes.count() {
        if node < body_first || node > function.body { continue }
        if tables.nodes[node].kind == NodeKind.Binary && (tables.nodes[node].flags == 14L || tables.nodes[node].flags == 15L) {
            ir_write_ascii(compiler, ir, "  %logic.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i1, align 1\n")
        }
        if tables.nodes[node].kind == NodeKind.If && compiler.facts[node].ty != TY_UNIT && compiler.facts[node].ty != TY_NEVER && !is_aggregate_type(compiler, compiler.facts[node].ty) {
            ir_write_ascii(compiler, ir, "  %if.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if (tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 4L) || (tables.nodes[node].kind == NodeKind.Assign && tables.nodes[node].flags == 5L) {
            let ty = if tables.nodes[node].kind == NodeKind.Binary { compiler.facts[node].ty } else { compiler.facts[compiler.child_first[node]].ty }
            ir_write_ascii(compiler, ir, "  %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if is_aggregate_type(compiler, compiler.facts[node].ty) {
            let type_info = type_record(compiler, compiler.facts[node].ty)
            let size = type_info.size
            let alignment = type_info.align
            ir_write_ascii(compiler, ir, "  %agg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, alignment); ir_write_ascii(compiler, ir, "\n")
        }
    }
    for binding_id in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_id]
        if compiler.scopes[binding.scope].function_id == function_id && binding.ty != TY_UNIT && !(binding.parameter && is_aggregate_type(compiler, binding.ty)) {
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
        if parameter.ty == TY_UNIT || is_aggregate_type(compiler, parameter.ty) { continue }
        let binding = binding_for_node(compiler, parameter.node)
        if parameter.ty == TY_BOOL {
            ir_write_ascii(compiler, ir, "  %arg.bool."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " = zext i1 %arg."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, " to i8\n")
            ir_write_ascii(compiler, ir, "  store i8 %arg.bool."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
        } else {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(parameter.ty)); ir_write_ascii(compiler, ir, " %arg."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", ptr %local."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", align 1\n")
        }
    }
    compiler.memory_closure = compiler.core_mode && files[function.file].name == b"memory.nl"
    emit_function_body(source, files, tokens, tables, compiler, ir, function.body, function.file, function_id, function.result_ty, false)
    compiler.memory_closure = false
    ir_write_ascii(compiler, ir, "}\n\n")
}

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
    ir_write_ascii(compiler, ir, "define i32 @nl_fn_")
    ir_write_number(compiler, ir, function_id)
    ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top) {\nentry:\n")
    let body_first = test.body - tables.nodes[test.body].subtree + 1L
    for node in 0L..tables.nodes.count() {
        if node < body_first || node > test.body { continue }
        if tables.nodes[node].kind == NodeKind.Binary && (tables.nodes[node].flags == 14L || tables.nodes[node].flags == 15L) {
            ir_write_ascii(compiler, ir, "  %logic.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i1, align 1\n")
        }
        if tables.nodes[node].kind == NodeKind.If && compiler.facts[node].ty != TY_UNIT && compiler.facts[node].ty != TY_NEVER && !is_aggregate_type(compiler, compiler.facts[node].ty) {
            ir_write_ascii(compiler, ir, "  %if.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if (tables.nodes[node].kind == NodeKind.Binary && tables.nodes[node].flags == 4L) || (tables.nodes[node].kind == NodeKind.Assign && tables.nodes[node].flags == 5L) {
            let ty = if tables.nodes[node].kind == NodeKind.Binary { compiler.facts[node].ty } else { compiler.facts[compiler.child_first[node]].ty }
            ir_write_ascii(compiler, ir, "  %div.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(ty)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        if is_aggregate_type(compiler, compiler.facts[node].ty) {
            let type_info = type_record(compiler, compiler.facts[node].ty)
            let size = type_info.size
            let alignment = type_info.align
            ir_write_ascii(compiler, ir, "  %agg."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca ["); ir_write_number(compiler, ir, size); ir_write_ascii(compiler, ir, " x i8], align "); ir_write_number(compiler, ir, alignment); ir_write_ascii(compiler, ir, "\n")
        }
    }
    let scope_function_id = -1L - test_index
    for binding_id in 0L..compiler.bindings.count() {
        let binding = compiler.bindings[binding_id]
        if compiler.scopes[binding.scope].function_id == scope_function_id && binding.ty != TY_UNIT && !binding.parameter {
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
    emit_function_body(source, files, tokens, tables, compiler, ir, test.body, test.file, scope_function_id, TY_UNIT, true)
    ir_write_ascii(compiler, ir, "}\n\n")
}

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
        } else if syntax.kind == NodeKind.Call {
            let file_index = node_file_index(tables.nodes, files, node)
            let is_print = token_is_word_at(source, tokens, files, file_index, syntax.token, "print")
            var argument = compiler.child_first[node]
            for argument_step in 0L..tables.nodes[node].subtree {
                if argument < 0L { break }
                let argument_ty = compiler.facts[argument].ty
                if is_aggregate_type(compiler, argument_ty) {
                    if is_print { add_type_helper_flag(compiler, argument_ty, 4L) }
                    else if tables.nodes[argument].kind == NodeKind.Name || tables.nodes[argument].kind == NodeKind.Field {
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
        } else { () }
        if syntax.kind == NodeKind.Expect {
            let expression = compiler.child_first[node]
            if expression >= 0L && tables.nodes[expression].kind == NodeKind.Binary && (tables.nodes[expression].flags == 8L || tables.nodes[expression].flags == 9L) {
                let left = compiler.child_first[expression]
                if left >= 0L {
                    let ty = compiler.facts[left].ty
                    add_type_helper_flag(compiler, ty, 4L)
                }
            }
        }
    }
    for pass in 0L..struct_type_count(compiler) {
        for type_index in 0L..struct_type_count(compiler) {
            let type_info = struct_record(compiler, type_index)
            let type_id = struct_type_id(compiler, type_index)
            for offset in 0L..type_info.field_count {
                let child_ty = compiler.struct_fields[type_info.field_start + offset].ty
                if !is_aggregate_type(compiler, child_ty) { continue }
                if has_type_helper(compiler, type_id, HELPER_COPY) { register_type_helper(compiler, child_ty, HELPER_COPY) }
                if has_type_helper(compiler, type_id, HELPER_EQUAL) { register_type_helper(compiler, child_ty, HELPER_EQUAL) }
                if has_type_helper(compiler, type_id, HELPER_PRINT) { register_type_helper(compiler, child_ty, HELPER_PRINT) }
            }
        }
    }
}

fn emit_struct_copy_helpers(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_COPY) { continue }
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY); ir_push_byte(compiler, ir, 40); emit_location_argument(compiler, ir, native_location(4L, 0L, 0L)); ir_write_ascii(compiler, ir, ", "); emit_location_argument(compiler, ir, native_location(5L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if field.ty == TY_UNIT { continue }
            let dest_address = MAX_TREE_NODES * 2L + field_index * 2L
            let source_address = dest_address + 1L
            emit_layout_address(compiler, ir, dest_address, native_location(4L, 0L, field.offset))
            emit_layout_address(compiler, ir, source_address, native_location(5L, 0L, field.offset))
            if is_aggregate_type(compiler, field.ty) {
                ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_two(compiler, ir, field.ty, HELPER_COPY, native_location(2L, dest_address, 0L), native_location(2L, source_address, 0L)); ir_push_byte(compiler, ir, 10)
            } else {
                let storage_type: Ascii max 8 = if field.ty == TY_BOOL { "i8" } else { llvm_type_name(field.ty) }
                ir_write_ascii(compiler, ir, "  %copy.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, source_address); ir_write_ascii(compiler, ir, ", align 1\n  store "); ir_write_ascii(compiler, ir, storage_type); ir_write_ascii(compiler, ir, " %copy.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, dest_address); ir_write_ascii(compiler, ir, ", align 1\n")
            }
        }
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}

fn emit_struct_eq_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_EQUAL) { continue }
        ir_write_ascii(compiler, ir, "define internal i1 "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_EQUAL); ir_push_byte(compiler, ir, 40); emit_location_argument(compiler, ir, native_location(6L, 0L, 0L)); ir_write_ascii(compiler, ir, ", "); emit_location_argument(compiler, ir, native_location(7L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        var previous = -1L
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if field.ty == TY_UNIT { continue }
            let left_address = MAX_TREE_NODES * 3L + field_index * 2L
            let right_address = left_address + 1L
            emit_layout_address(compiler, ir, left_address, native_location(6L, 0L, field.offset))
            emit_layout_address(compiler, ir, right_address, native_location(7L, 0L, field.offset))
            if is_aggregate_type(compiler, field.ty) {
                ir_write_ascii(compiler, ir, "  %eq.raw."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = call i1 "); emit_type_helper_call_two(compiler, ir, field.ty, HELPER_EQUAL, native_location(2L, left_address, 0L), native_location(2L, right_address, 0L)); ir_push_byte(compiler, ir, 10)
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

fn emit_struct_print_text_call(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    kind: Ascii max 16,
    index: long,
    length: long,
) {
    ir_write_ascii(compiler, ir, "  call void @nl_print_ascii(ptr getelementptr inbounds (["); ir_write_number(compiler, ir, length + 1L); ir_write_ascii(compiler, ir, " x i8], ptr @.nl.struct."); ir_write_ascii(compiler, ir, kind); ir_write_ascii(compiler, ir, "."); ir_write_number(compiler, ir, index); ir_write_ascii(compiler, ir, ", i64 0, i64 0), i64 "); ir_write_number(compiler, ir, length); ir_write_ascii(compiler, ir, ")\n")
}

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
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_PRINT); ir_push_byte(compiler, ir, 40); emit_location_argument(compiler, ir, native_location(8L, 0L, 0L)); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        emit_struct_print_text_call(compiler, ir, "type", type_index, tokens[ty.name_token].length)
        emit_struct_print_text_call(compiler, ir, "open", 0L, 3L)
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if offset > 0L { emit_struct_print_text_call(compiler, ir, "separator", 0L, 2L) }
            emit_struct_print_text_call(compiler, ir, "field", field_index, tokens[field.name_token].length)
            emit_struct_print_text_call(compiler, ir, "colon", 0L, 2L)
            let address = MAX_TREE_NODES * 5L + field_index
            emit_layout_address(compiler, ir, address, native_location(8L, 0L, field.offset))
            if is_aggregate_type(compiler, field.ty) {
                ir_write_ascii(compiler, ir, "  call void "); emit_type_helper_call_one(compiler, ir, field.ty, HELPER_PRINT, native_location(2L, address, 0L)); ir_push_byte(compiler, ir, 10)
            } else if field.ty == TY_BOOL {
                ir_write_ascii(compiler, ir, "  %print.bool.byte."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load i8, ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n  %print.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = trunc i8 %print.bool.byte."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " to i1\n  call void @nl_print_bool_raw(i1 zeroext %print.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ")\n")
            } else {
                let raw_name: Ascii max 16 = if field.ty == TY_INT { "int" } else { "long" }
                ir_write_ascii(compiler, ir, "  %print.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = load "); ir_write_ascii(compiler, ir, llvm_type_name(field.ty)); ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address); ir_write_ascii(compiler, ir, ", align 1\n  call void @nl_print_"); ir_write_ascii(compiler, ir, raw_name); ir_write_ascii(compiler, ir, "_raw("); ir_write_ascii(compiler, ir, llvm_type_name(field.ty)); ir_write_ascii(compiler, ir, " %print.value."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ")\n")
            }
        }
        emit_struct_print_text_call(compiler, ir, "close", 0L, 2L)
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}

fn emit_contains_index_helper(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "define internal i1 @nl.contains.index(ptr %items, i64 %count, i64 %wanted) {\nentry:\n  br label %loop\nloop:\n  %index = phi i64 [ 0, %entry ], [ %next, %advance ]\n  %finished = icmp uge i64 %index, %count\n  br i1 %finished, label %missing, label %check\ncheck:\n  %item.ptr = getelementptr i64, ptr %items, i64 %index\n  %item = load i64, ptr %item.ptr, align 1\n  %matches = icmp eq i64 %item, %wanted\n  br i1 %matches, label %found, label %advance\nadvance:\n  %next = add i64 %index, 1\n  br label %loop\nfound:\n  ret i1 true\nmissing:\n  ret i1 false\n}\n\n")
}

fn emit_struct_fill_helpers(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    var any_defaults = false
    for type_index in 0L..struct_type_count(compiler) {
        if has_type_helper(compiler, struct_type_id(compiler, type_index), HELPER_FILL) { any_defaults = true }
    }
    if !any_defaults { return }
    emit_contains_index_helper(compiler, ir)
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        let type_id = struct_type_id(compiler, type_index)
        if !has_type_helper(compiler, type_id, HELPER_FILL) { continue }
        ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_FILL); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top, "); emit_hidden_destination_parameter(compiler, ir); ir_write_ascii(compiler, ir, ", ptr %nl.given, i64 %nl.given.count) {\nentry:\n")
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            if field.default_node < 0L { continue }
            let address = MAX_TREE_NODES * 4L + field_index
            ir_write_ascii(compiler, ir, "  %given."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = call i1 @nl.contains.index(ptr %nl.given, i64 %nl.given.count, i64 "); ir_write_number(compiler, ir, offset); ir_write_ascii(compiler, ir, ")\n  br i1 %given."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", label %skip."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", label %fill."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\nfill."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ":\n")
            emit_layout_address(compiler, ir, address, native_location(4L, 0L, field.offset))
            ir_write_ascii(compiler, ir, "  call void "); emit_default_field_helper_symbol(compiler, ir, type_id, field_index); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top, "); emit_location_argument(compiler, ir, native_location(2L, address, 0L)); ir_write_ascii(compiler, ir, ")\n  br label %skip."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, "\nskip."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ":\n")
        }
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}

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
        if field.default_node < 0L || !has_type_helper(compiler, struct_type_id(compiler, field.owner), HELPER_DEFAULT) { continue }
        let function_id = -100000L - field_index
        let expression = field.default_node
        let default_file = struct_record(compiler, field.owner).file
        ir_write_ascii(compiler, ir, "define internal void "); emit_default_field_helper_symbol(compiler, ir, struct_type_id(compiler, field.owner), field_index); ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top, "); emit_hidden_destination_parameter(compiler, ir); ir_write_ascii(compiler, ir, ") {\nentry:\n")
        let first = expression - tables.nodes[expression].subtree
        for node in first..expression + 1L {
            if tables.nodes[node].kind == NodeKind.If && compiler.facts[node].ty != TY_UNIT && compiler.facts[node].ty != TY_NEVER && !is_aggregate_type(compiler, compiler.facts[node].ty) {
                ir_write_ascii(compiler, ir, "  %if.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(compiler.facts[node].ty)); ir_write_ascii(compiler, ir, ", align 1\n")
            }
            if (tables.nodes[node].kind == NodeKind.Binary && (tables.nodes[node].flags == 14L || tables.nodes[node].flags == 15L)) {
                ir_write_ascii(compiler, ir, "  %logic.slot."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = alloca i1, align 1\n")
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
            emit_aggregate_copy(compiler, ir, field.ty, aggregate_destination_location(2L, 0L), aggregate_source_location(source_kind, source_node))
        } else if field.ty == TY_BOOL {
            ir_write_ascii(compiler, ir, "  %default.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, expression); ir_write_ascii(compiler, ir, " to i8\n  store i8 %default.bool."); ir_write_number(compiler, ir, field_index); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer(compiler, ir, native_location(4L, 0L, 0L)); ir_write_ascii(compiler, ir, ", align 1\n")
        } else {
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(field.ty)); ir_write_ascii(compiler, ir, " "); ir_write_value_ref(compiler, ir, expression); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer(compiler, ir, native_location(4L, 0L, 0L)); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
    }
}

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
    let main_name: Bytes max 4096 = b"main"
    ir_write_global_string(compiler, ir, "@.nl.entry.main = private unnamed_addr constant [", main_name)
    for test_index in 0L..compiler.tests.count() {
        let test = compiler.tests[test_index]
        let name = decode_string_token(source, tokens, files[test.file].base, test.name_token, false)
        ir_write_test_global(compiler, ir, test_index, name)
    }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.Expect { ir_write_expect_global(source, tables, compiler, ir, node) }
        if tables.nodes[node].kind == NodeKind.StructInit {
            let type_index = compiler.facts[node].literal
            let ty = struct_record(compiler, type_index)
            var count = 0L
            for field_offset in 0L..ty.field_count {
                let field_index = ty.field_start + field_offset
                var child = compiler.child_first[node]
                for field_step in 0L..tables.nodes[node].subtree {
                    if child < 0L { break }
                    if compiler.facts[child].binding == field_index { count += 1L }
                    child = compiler.child_next[child]
                }
            }
            ir_write_ascii(compiler, ir, "@.nl.given."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = private constant ["); ir_write_number(compiler, ir, count); ir_write_ascii(compiler, ir, " x i64] ")
            if count == 0L { ir_write_ascii(compiler, ir, "zeroinitializer\n") }
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
    ir_write_global_string(compiler, ir, "@.nl.struct.open.0 = private unnamed_addr constant [", open_text)
    ir_write_global_string(compiler, ir, "@.nl.struct.close.0 = private unnamed_addr constant [", close_text)
    ir_write_global_string(compiler, ir, "@.nl.struct.separator.0 = private unnamed_addr constant [", separator_text)
    ir_write_global_string(compiler, ir, "@.nl.struct.colon.0 = private unnamed_addr constant [", colon_text)
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        ir_write_struct_identifier_global(source, files, tokens, compiler, ir, "type", type_index, ty.file, ty.name_token)
        for offset in 0L..ty.field_count {
            let field_index = ty.field_start + offset
            let field = compiler.struct_fields[field_index]
            ir_write_struct_identifier_global(source, files, tokens, compiler, ir, "field", field_index, ty.file, field.name_token)
        }
    }
    ir_write_ascii(compiler, ir, "\n")
}

fn emit_main_function(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    config: MemoryConfig,
    entry: long,
    runtime_core: bool,
) {
    if runtime_core { ir_write_ascii(compiler, ir, "define i32 @main(i32 %argc, ptr %argv, ptr %envp) {\nentry:\n  call void @nl_core_init(i32 %argc, ptr %argv, ptr %envp)\n") }
    else { ir_write_ascii(compiler, ir, "define i32 @main(i32 %argc, ptr %argv) {\nentry:\n") }
    if compiler.tests.count() > 0L {
        ir_write_ascii(compiler, ir, "  %nl.selected = call i32 @nl_test_selected_index()\n  switch i32 %nl.selected, label %nl.select.default [\n")
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
        ir_write_ascii(compiler, ir, "nl.select.default:\n  br label %nl.select.ready\nnl.select.ready:\n  %nl.entry.name = phi ptr ")
        for test_index in 0L..compiler.tests.count() {
            if test_index > 0L { ir_write_ascii(compiler, ir, ", ") }
            ir_write_ascii(compiler, ir, "[ getelementptr inbounds ([")
            let test = compiler.tests[test_index]
            let name = decode_string_token(source, tokens, files[test.file].base, test.name_token, false)
            ir_write_number(compiler, ir, name.count() + 8L)
            ir_write_ascii(compiler, ir, " x i8], ptr @.nl.entry.test.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, ", i64 0, i64 0), %nl.select.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, " ]")
        }
        ir_write_ascii(compiler, ir, ", [ getelementptr inbounds ([")
        if entry >= 0L { ir_write_ascii(compiler, ir, "5") }
        else {
            let first_test = compiler.tests[0L]
            let name = decode_string_token(source, tokens, files[first_test.file].base, first_test.name_token, false)
            ir_write_number(compiler, ir, name.count() + 8L)
        }
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.entry.")
        if entry >= 0L { ir_write_ascii(compiler, ir, "main") }
        else { ir_write_ascii(compiler, ir, "test.0") }
        ir_write_ascii(compiler, ir, ", i64 0, i64 0), %nl.select.default ]\n")
        ir_write_ascii(compiler, ir, "  %nl.ctx = call ptr @nl_context_create(i64 4096, i64 ")
        ir_write_number(compiler, ir, config.recursion_budget)
        ir_write_ascii(compiler, ir, ", ptr %nl.entry.name)\n")
    } else {
        let main_name: Bytes max 4096 = b"main"
        ir_write_ascii(compiler, ir, "  %nl.ctx = call ptr @nl_context_create(i64 4096, i64 ")
        ir_write_number(compiler, ir, config.recursion_budget)
        ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds ([5 x i8], ptr @.nl.entry.main, i64 0, i64 0))\n")
        let _ = main_name
    }
    ir_write_ascii(compiler, ir, "  %nl.top = call i64 @nl_context_base_offset(ptr %nl.ctx)\n")
    ir_write_ascii(compiler, ir, "  %nl.env = call ptr @nl_env_create(i32 %argc, ptr %argv, i32 ")
    ir_write_number(compiler, ir, config.capability_mask)
    ir_write_ascii(compiler, ir, ")\n")
    for file_index in 0L..files.count() {
        ir_write_ascii(compiler, ir, "  call void @nl_register_file(i32 ")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.file.")
        ir_write_number(compiler, ir, file_index)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0))\n")
    }
    if runtime_core { ir_write_ascii(compiler, ir, "  call void @nl_core_register_files()\n") }
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
            ir_write_ascii(compiler, ir, ":\n  call void @nl_set_test_mode()\n  %nl.test.result.")
            ir_write_number(compiler, ir, test_index)
            ir_write_ascii(compiler, ir, " = call i32 @nl_fn_")
            let test_function_id = compiler.functions.count() + test_index
            ir_write_number(compiler, ir, test_function_id)
            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, i64 %nl.top)\n  call void @nl_env_destroy(ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 %nl.test.result.")
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
    ir_write_ascii(compiler, ir, "  call void @nl_env_destroy(ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 0\n}\n")
}

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
            err(Full) => fail_core_internal(env, b"core", SourcePosition { line: 1L, col: 1L }, "embedded file count exceeded its fixed limit"),
        }
    }
}

fn emit_core_file_globals(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    for file_index in 0L..files.count() {
        let global_file_id = compiler.file_id_base + file_index
        ir_write_ascii(compiler, ir, "@.nl.file.")
        ir_write_number(compiler, ir, global_file_id)
        ir_write_ascii(compiler, ir, " = private unnamed_addr constant [")
        ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8] c\"")
        for index in 0L..files[file_index].name.count() { ir_write_escaped_byte(compiler, ir, files[file_index].name[index]) }
        ir_write_ascii(compiler, ir, "\\00\", align 1\n")
    }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.BytesLiteral {
            let syntax = tables.nodes[node]
            let literal_file = node_file_index(tables.nodes, files, node)
            let literal = decode_string_token(source, tokens, files[literal_file].base, syntax.extra, true)
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

fn syscall_register(index: long) -> Ascii max 8 {
    if index == 0L { "rdi" }
    else if index == 1L { "rsi" }
    else if index == 2L { "rdx" }
    else if index == 3L { "r10" }
    else if index == 4L { "r8" }
    else { "r9" }
}

fn emit_one_syscall_helper(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, count: long) {
    ir_write_ascii(compiler, ir, "define internal i64 @nl.sys.call")
    ir_write_number(compiler, ir, count)
    ir_write_ascii(compiler, ir, "(i64 %n")
    for index in 0L..count {
        ir_write_ascii(compiler, ir, ", i64 %a")
        ir_write_number(compiler, ir, index)
    }
    ir_write_ascii(compiler, ir, ") alwaysinline nounwind {\nentry:\n  %r = call i64 asm sideeffect \"syscall\", \"={rax},{rax}")
    for index in 0L..count {
        ir_push_byte(compiler, ir, 44)
        ir_push_byte(compiler, ir, 123)
        ir_write_ascii(compiler, ir, syscall_register(index))
        ir_push_byte(compiler, ir, 125)
    }
    ir_write_ascii(compiler, ir, ",~{rcx},~{r11},~{memory},~{dirflag},~{fpsr},~{flags}\"(i64 %n")
    for index in 0L..count {
        ir_write_ascii(compiler, ir, ", i64 %a")
        ir_write_number(compiler, ir, index)
    }
    ir_write_ascii(compiler, ir, ")\n  ret i64 %r\n}\n\n")
}

fn emit_syscall_helpers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    for count in 0L..7L { emit_one_syscall_helper(compiler, ir, count) }
}

fn emit_core_registration(files: list<SourceFile, MAX_SOURCE_FILES>, compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "define internal void @nl_core_register_files() nounwind {\nentry:\n")
    for file_index in 0L..files.count() {
        let global_file_id = compiler.file_id_base + file_index
        ir_write_ascii(compiler, ir, "  call void @nl_register_file(i32 ")
        ir_write_number(compiler, ir, global_file_id)
        ir_write_ascii(compiler, ir, ", ptr getelementptr inbounds ([")
        ir_write_number(compiler, ir, files[file_index].name.count() + 1L)
        ir_write_ascii(compiler, ir, " x i8], ptr @.nl.file.")
        ir_write_number(compiler, ir, global_file_id)
        ir_write_ascii(compiler, ir, ", i64 0, i64 0))\n")
    }
    ir_write_ascii(compiler, ir, "  ret void\n}\n\n")
}

fn emit_core_start_assembly(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "module asm \".text\"\nmodule asm \".globl _start\"\nmodule asm \".type _start, @function\"\nmodule asm \"_start:\"\nmodule asm \"  .cfi_startproc\"\nmodule asm \"  .cfi_undefined rip\"\nmodule asm \"  xor %ebp, %ebp\"\nmodule asm \"  mov %rsp, %rdi\"\nmodule asm \"  and $-16, %rsp\"\nmodule asm \"  call nl_core_start\"\nmodule asm \"  ud2\"\nmodule asm \"  .cfi_endproc\"\nmodule asm \".size _start, . - _start\"\n")
    ir_write_ascii(compiler, ir, "@llvm.used = appending global [1 x ptr] [ptr @nl_core_start], section \"llvm.metadata\"\n")
}

fn compile_embedded_core(
    env: Env,
    config: MemoryConfig,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    file_id_base: long,
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
    reset_compiler_tables(compiler)
    compiler.core_mode = true
    compiler.file_id_base = file_id_base
    add_compiler_links(tables, compiler)
    intern_package_names(env, source, files, tokens, tables, compiler)
    build_line_start_index(env, source, files, compiler)
    check_package_eligibility(env, source, files, tokens, tables, compiler)
    register_package_declarations(env, source, files, tokens, tables, config, compiler)
    let _entry = check_entry_signature(env, source, files, tokens, tables, compiler, false)
    check_package_bodies(env, source, files, tokens, tables, config, compiler)
    add_default_call_graph_edges(tables, compiler)
    check_call_cycles(env, source, files, tokens, tables, compiler)
    for function_id in 0L..compiler.functions.count() {
        emit_function_definition(source, files, tokens, tables, compiler, ir, function_id)
    }
    emit_core_file_globals(source, files, tokens, tables, compiler, ir)
    ir_write_ascii(compiler, ir, "@nl.core.state = internal global [")
    ir_write_number(compiler, ir, embedded_core_state_bytes())
    ir_write_ascii(compiler, ir, " x i8] zeroinitializer, align 64\n\n")
    emit_core_registration(files, compiler, ir)
    emit_syscall_helpers(compiler, ir)
    ir_write_ascii(compiler, ir, "@llvm.compiler.used = appending global [5 x ptr] [ptr @memcpy, ptr @memmove, ptr @memset, ptr @memcmp, ptr @bcmp], section \"llvm.metadata\"\n")
    emit_core_start_assembly(compiler, ir)
    !compiler.ir_overflow
}

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
    runtime_core: bool,
    core_hash: Ascii max 64,
) {
    check_struct_declarations(env, source, files, tokens, tables, compiler)
    register_package_declarations(env, source, files, tokens, tables, config, compiler)
    initialize_default_graph_nodes(compiler)
    let entry = check_entry_signature(env, source, files, tokens, tables, compiler, !want_test_build)
    check_struct_defaults(env, source, files, tokens, tables, config, compiler)
    check_package_bodies(env, source, files, tokens, tables, config, compiler)
    add_default_call_graph_edges(tables, compiler)
    check_call_cycles(env, source, files, tokens, tables, compiler)
    check_native_frame_budget(env, source, files, tokens, tables, compiler, entry, want_test_build)
    mark_struct_helpers(source, files, tokens, tables, compiler)
    ir_write_ascii(compiler, ir, "; nlc-link-ir 2\n; nlc.build ")
    ir_write_ascii(compiler, ir, if want_test_build { "test" } else { "program" })
    ir_write_ascii(compiler, ir, "\n; nlc.stack offset\n; nlc.recursion none\n")
    ir_write_ascii(compiler, ir, if runtime_core { "; nlc.runtime core\n" } else { "; nlc.runtime c\n" })
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
    if !runtime_core {
        ir_write_ascii(compiler, ir, "declare ptr @nl_context_create(i64, i64, ptr)\ndeclare i64 @nl_context_base_offset(ptr)\ndeclare void @nl_context_destroy(ptr)\ndeclare ptr @nl_env_create(i32, ptr, i32)\ndeclare void @nl_env_destroy(ptr)\ndeclare void @nl_register_file(i32, ptr)\ndeclare void @nl_print_int(i32)\ndeclare void @nl_print_long(i64)\ndeclare void @nl_print_bool(i1 zeroext)\ndeclare void @nl_print_int_raw(i32)\ndeclare void @nl_print_long_raw(i64)\ndeclare void @nl_print_bool_raw(i1 zeroext)\ndeclare void @nl_print_ascii(ptr, i64)\ndeclare void @nl_print_newline()\ndeclare void @nl_fail(i32, i32, i32, i32) noreturn cold nounwind\ndeclare void @nl_expect_fail_compare(i32, i32, i32, ptr, i64, i64, i32)\ndeclare void @nl_expect_fail_bool(i32, i32, i32, ptr)\ndeclare void @nl_expect_fail_header(i32, i32, i32, ptr)\ndeclare void @nl_expect_fail_left()\ndeclare void @nl_expect_fail_right()\ndeclare i32 @nl_test_selected_index()\ndeclare void @nl_set_test_mode()\n")
    }
    ir_write_ascii(compiler, ir, "\n")
    for function_id in 0L..compiler.functions.count() {
        emit_function_definition(source, files, tokens, tables, compiler, ir, function_id)
    }
    for test_index in 0L..compiler.tests.count() {
        emit_test_definition(source, files, tokens, tables, compiler, ir, test_index)
    }
    emit_registered_type_helpers(source, files, tokens, tables, compiler, ir)
    emit_file_globals(files, source, tokens, tables, compiler, ir)
    emit_main_function(source, compiler, ir, files, tokens, config, entry, runtime_core)
    if runtime_core {
        let user_ir_overflow = compiler.ir_overflow
        if !compile_embedded_core(env, config, ir, files.count(), tables, compiler) {
            fail_parse_limit(env, files[0].name, "self-hosted LLVM IR buffer limit exceeded")
        }
        compiler.ir_overflow = compiler.ir_overflow || user_ir_overflow
    }
    ir_write_ascii(compiler, ir, "\n; nlc-link-ir end\n")
}

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

