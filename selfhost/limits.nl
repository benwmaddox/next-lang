const MAX_SOURCE_FILES: long = 256L
const MAX_SOURCE_BYTES_PER_FILE: long = 16777216L
const MAX_SOURCE_BYTES_PER_PACKAGE: long = 67108864L
const FILE_SOURCE_CAPACITY: long = 16777216L
const SOURCE_BUFFER_CAPACITY: long = 67108864L
const MAX_TOKENS_PER_FILE: long = 1000000L
const MAX_TOKENS_PER_PACKAGE: long = 4000000L
const TOKEN_STORAGE_CAPACITY: long = 4000000L
const MAX_DELIMITER_NESTING: long = 2048L
const MAX_DIRECTORY_ENTRIES: long = 4096L
const OUTPUT_BUFFER_BYTES: long = 262144L
const MAX_TREE_NODES: long = 2000000L
const MAX_TREE_EDGES: long = 2000000L
const MAX_PARSE_WORK: long = 72000000L
const NODE_STORAGE_CAPACITY: long = 4000257L
const EXTRA_STORAGE_CAPACITY: long = 8000000L
const LITERAL_STORAGE_CAPACITY: long = 4000000L
const NESTING_TASK_CAPACITY: long = 2000001L
const GENERIC_HASH_CAPACITY: long = 1048576L
const MAX_PARSER_DEPTH: long = 1000L
const TYPED_FACT_CAPACITY: long = MAX_TREE_NODES
const CHILD_LINK_CAPACITY: long = MAX_TREE_NODES
const FUNCTION_TABLE_CAPACITY: long = MAX_TREE_NODES
const TEST_TABLE_CAPACITY: long = MAX_TREE_NODES
const BINDING_TABLE_CAPACITY: long = MAX_TREE_NODES
const SCOPE_TABLE_CAPACITY: long = MAX_TREE_NODES
// Includes package calls plus per-literal/default helper edges. The graph is
// linear in syntax plus field entries for the E2 default/call closure.
const CALL_EDGE_CAPACITY: long = EXTRA_STORAGE_CAPACITY
// Seven scalar builtin slots plus the E3c TextError and Utf8Error records.
const TYPE_TABLE_CAPACITY: long = MAX_TREE_NODES + 9L
const FIELD_TABLE_CAPACITY: long = MAX_TREE_NODES + 1L
// E2i has no cleanup producers; the first cleanup owner derives and expands this.
const EXIT_CLEANUP_CAPACITY: long = 1L
const INTERN_NAME_CAPACITY: long = TOKEN_STORAGE_CAPACITY
const INTERN_HASH_CAPACITY: long = 4194304L
const CHECK_FRAME_CAPACITY: long = 4096L
const SOURCE_LINE_START_CAPACITY: long = 67109120L
// E2 helpers add one call or constant field index per syntax node, plus one
// entry-sized block for each type and field helper table entry.
const IR_BYTES_PER_NODE: long = 640L
const IR_BYTES_PER_TABLE_ENTRY: long = 256L
const IR_FIXED_BYTES: long = 8388608L

// E2b begin
const ENUM_CASE_TABLE_CAPACITY: long = MAX_TREE_NODES + 2L
const ENUM_PAYLOAD_TABLE_CAPACITY: long = MAX_TREE_NODES
// Enum declarations, cases and payload parts are distinct syntax nodes, so
// together they stay within MAX_TREE_NODES. Per enum table entry, the existing
// 256-byte allowance plus this 768-byte extension covers dispatch labels and
// copy/equality/print addresses, values and calls.
// The 640-byte per-node term covers constructor/match use-site output.
const IR_BYTES_PER_ENUM_TABLE_ENTRY: long = 768L
const IR_BUFFER_CAPACITY: long = MAX_TREE_NODES * IR_BYTES_PER_NODE + MAX_TREE_NODES * IR_BYTES_PER_TABLE_ENTRY + MAX_TREE_NODES * IR_BYTES_PER_ENUM_TABLE_ENTRY + MAX_SOURCE_BYTES_PER_PACKAGE + IR_FIXED_BYTES
// E2b end
