enum ParseProblemKind {
    ExpectedFunction,
    ExpectedFnAfterRecursive,
    ExpectedFunctionName,
    ExpectedGenericName,
    ExpectedEnumName,
    ExpectedTypePathPart,
    ExpectedFunctionParen,
    ExpectedConstEq,
    ExpectedStructOpen,
    ExpectedEnumOpen,
    ExpectedEnumClose,
    ExpectedCollectionOpen,
    ExpectedCollectionClose,
    ExpectedStructLiteralOpen,
    ExpectedStructLiteralClose,
    ExpectedEnumComma,
    EmptyList,
    EmptyPool,
    EmptyMap,
    EmptySet,
    EmptyQueue,
    EmptyRing,
    ExpectedListClose,
    ExpectedPoolClose,
    ExpectedMapClose,
    ExpectedSetClose,
    ExpectedQueueClose,
    ExpectedRingClose,
    ExpectedGenericClose,
    ExpectedTypeArgsClose,
    ExpectedFitTypeClose,
    ExpectedTextMax,
    ExpectedSecondIndex,
    ExpectedConstName,
    ExpectedGlobalName,
    ExpectedStructName,
    ExpectedTypeName,
    ExpectedAliasEq,
    ExpectedConstColon,
    ExpectedGlobalColon,
    LockedGlobal,
    ExpectedGlobalEq,
    DuplicatePrefault,
    EnumEmpty,
    ExpectedComma,
    ExpectedBrace,
    ExpectedEnumCase,
    ExpectedEnumPayloadClose,
    ExpectedTestName,
    ExpectedTestParamName,
    ExpectedTestParamColon,
    ExpectedTestParamClose,
    ExpectedParameterName,
    ExpectedParameterColon,
    ExpectedParameterClose,
    ExpectedResult,
    ExpectedBlock,
    ExpectedSeparator,
    ExpectedFieldName,
    ExpectedFieldColon,
    ExpectedTypeClose,
    TypeDepth,
    BlockDepth,
    ExpressionDepth,
    ExpectedGridWidth,
    ExpectedGridHeight,
    ExpectedMapValue,
    ExpectedMapCapacity,
    ExpectedSetCapacity,
    ExpectedTypeRange,
    RangeBound,
    RangeTooLarge,
    PolicyNeedsRange,
    ExpectedFunctionTypeParen,
    UnsupportedGenericFunctionType,
    ExpectedFunctionTypeClose,
    ExpectedEffect,
    ExpectedFsEffect,
    ExpectedFsOperation,
    BadFsEffect,
    ExpectedReadsPath,
    ExpectedWritesPath,
    ExpectedEffectPathPart,
    UnknownEffect,
    DuplicateGeneric,
    ExpectedBlockOpen,
    ExpectedBlockClose,
    ExpectedStmtSeparator,
    ExpectedExpectBool,
    ExpectedLetName,
    ExpectedLetValue,
    ExpectedStackPeakOpen,
    ExpectedStackPeakName,
    ExpectedStackPeakClose,
    ExpectedStackPeakLt,
    ExpectedStackPeakBudget,
    StackPeakTooLarge,
    BadAssignTarget,
    ExpectedForName,
    ExpectedIndexName,
    TooManyForBindings,
    ExpectedForIn,
    RangeForBindings,
    CollectionForAnnotation,
    ExpectedValue,
    AnonymousFunction,
    ExpectedCloseParen,
    CastDepth,
    ExpectedCloseBracket,
    EmptyCollectionOnly,
    ExpectedCallOpen,
    ExpectedOptionalName,
    ExpectedOptionalOpen,
    ExpectedMethodName,
    ExpectedFitClose,
    ExpectedFitCall,
    FitNoArgs,
    ExpectedSliceRange,
    ExpectedSliceClose,
    ExpectedStructField,
    ExpectedStructClose,
    ExpectedArrayClose,
    ExpectedIndexClose,
    ExpectedGridClose,
    ExpectedMatchOpen,
    ExpectedMatchArrow,
    ExpectedMatchClose,
    ExpectedMatchSeparator,
    ExpectedPattern,
    ExpectedPatternNumber,
    ExpectedPatternEnumCase,
    ExpectedPatternBinding,
    ExpectedPatternClose,
    ExpectedIfBlockOrIf,
    ExpectedElseBlock,
    IntegerSeparators,
    IntegerTooLarge,
    ParseNodeLimit,
    ParseEdgeLimit,
    ParseWorkLimit,
    InternalCapacity,
}

enum NodeKind {
    Program,
    Enum,
    EnumCase,
    Struct,
    StructField,
    TypeAlias,
    Const,
    Global,
    Function,
    Test,
    Parameter,
    Block,
    FunctionType,
    FunctionTypeParameter,
    Effect,
    ParameterType,
    ResultType,
    Annotation,
    FieldType,
    PayloadType,
    AliasedType,
    DeclaredType,
    TypeArgument,
    FitType,
    CastType,
    Let,
    Assign,
    ReturnStatement,
    ExpressionStatement,
    For,
    ForEach,
    Discard,
    Expect,
    BreakStatement,
    ContinueStatement,
    Unit,
    Integer,
    Bool,
    ByteString,
    BytesLiteral,
    Take,
    Name,
    Call,
    IndirectCall,
    QualifiedCase,
    MethodCall,
    Index,
    OptionalCall,
    Field,
    StructInit,
    InitializerField,
    ArrayLiteral,
    ListLiteral,
    PoolLiteral,
    MapLiteral,
    SetLiteral,
    QueueLiteral,
    RingLiteral,
    GridIndex,
    Fit,
    Try,
    Return,
    LoopExit,
    Match,
    MatchArm,
    ToLong,
    Cast,
    Unary,
    Binary,
    If,
    WildcardPattern,
    BoolPattern,
    CasePattern,
    PatternBinding,
    IgnoredPatternBinding,
}

struct Node {
    kind: NodeKind
    flags: long
    token: long
    start: long
    end: long
    anchor: long
    subtree: long
    extra: long
    aux: long
    meta0: long
    meta1: long
}

struct Literal128 {
    limb0: long
    limb1: long
    limb2: long
    limb3: long
}

struct RangeBound {
    literal: long
    negative: long
}

struct ParsedLiteral {
    index: long
    long_suffix: bool
}

struct ScaledLiteral {
    value: Literal128
    ok: bool
}

struct BinaryInfo {
    op: long
    precedence: long
}

struct NestTask {
    node: long
    depth: long
    role: long
}

struct IfFrame {
    condition: long
    then_block: long
    token: long
    start: long
    end: long
}

struct MatchFrame {
    match_token: long
    match_start: long
    scrutinee: long
    first: long
    arm_count: long
    waiting_pattern: long
    waiting_arm_start: long
}

struct ForFrame {
    first: long
    name_token: long
    start: long
    flags: long
    extra: long
    index_count: long
    body_open_token: long
    body_start: long
    body_first: long
    is_range: bool
}

struct SeenSlot {
    generation: long
    token: long
}

struct ParserState {
    pos: long
    token_end: long
    file_base: long
    file_length: long
    split_count: long
    split_index: long
    split_kind: TokenKind
    last_end: long
    expression_depth: long
    expression_depth_adjustment: long
    cast_depth: long
    parenthesis_depth: long
    block_depth: long
    type_depth: long
    allow_struct_literals: bool
    seen_generation: long
}

struct ParseTables {
    state: ParserState
    nodes: list<Node, NODE_STORAGE_CAPACITY>
    extra: list<long, EXTRA_STORAGE_CAPACITY>
    literals: list<Literal128, LITERAL_STORAGE_CAPACITY>
    nesting: list<NestTask, NESTING_TASK_CAPACITY>
    child_scratch: list<long, NESTING_TASK_CAPACITY>
    child_scratch2: list<long, NESTING_TASK_CAPACITY>
    if_frames: list<IfFrame, 1000>
    match_frames: list<MatchFrame, MAX_TOKENS_PER_FILE>
    for_frames: list<ForFrame, MAX_PARSER_DEPTH>
    seen: list<SeenSlot, GENERIC_HASH_CAPACITY>
    file_first_node: long
}

struct CursorToken {
    kind: TokenKind
    token: long
    start: long
    length: long
    virtual_piece: bool
}

struct ParseError {
    kind: ParseProblemKind
    offset: long
    token: long
}

struct ExprRef {
    node: long
    pending_kind: long
    token: long
    extra_token: long
    start: long
    end: long
}

struct ParseCandidate {
    node: long
    is_statement: bool
}

const FLAG_VALUE: long = 1L
const FLAG_MUTABLE: long = 2L
const FLAG_RECURSIVE: long = 4L
const FLAG_INCLUSIVE: long = 8L
const FLAG_PREFAULT: long = 16L
const FLAG_NEGATIVE: long = 32L
const FLAG_LONG_SUFFIX: long = 64L
const FLAG_MODE_WRITE: long = 128L
const FLAG_MODE_GROW: long = 256L
const FLAG_SYNTHETIC: long = 512L
const FLAG_POLICY_WRAP: long = 1024L
const FLAG_POLICY_CLAMP: long = 2048L
const FLAG_RANGE: long = 4096L
const FLAG_RANGE_INCLUSIVE: long = 8192L
const FLAG_HAS_ANNOTATION: long = 16384L
const FLAG_HAS_TAIL: long = 32768L
const FLAG_HAS_ELSE: long = 65536L
const FLAG_HAS_VALUE: long = 131072L
const FLAG_TYPE_FN: long = 262144L
const FLAG_TYPE_UNIT: long = 524288L
const FLAG_TYPE_TEXT_BYTES: long = 1048576L
const FLAG_EFFECT_WRITES: long = 2097152L
const FLAG_BYTESTRING_NONASCII_HEX: long = 4194304L

const PENDING_NAME: long = 1L
const PENDING_QUALIFIED: long = 2L
const NEST_EXPR: long = 0L
const NEST_BLOCK: long = 1L
const NEST_TYPE: long = 2L

fn pack_type_counts(args: long, constants: long, arrays: long) -> long {
    args | (constants << 21L) | (arrays << 42L)
}

fn empty_parse_tables() -> ParseTables {
    ParseTables {
        state: ParserState {
            pos: 0L,
            token_end: 0L,
            file_base: 0L,
            file_length: 0L,
            split_count: 0L,
            split_index: 0L,
            split_kind: TokenKind.Eof,
            last_end: 0L,
            expression_depth: 0L,
            expression_depth_adjustment: 0L,
            cast_depth: 0L,
            parenthesis_depth: 0L,
            block_depth: 0L,
            type_depth: 0L,
            allow_struct_literals: true,
            seen_generation: 0L,
        },
        nodes: list {},
        extra: list {},
        literals: list {},
        nesting: list {},
        child_scratch: list {},
        child_scratch2: list {},
        if_frames: list {},
        match_frames: list {},
        for_frames: list {},
        seen: list {},
        file_first_node: 0L,
    }
}

fn initialize_parse_tables(tables: write ParseTables) {
    for step in 0L..GENERIC_HASH_CAPACITY {
        tables.seen.push(SeenSlot { generation: 0L, token: -1L }).unwrap()
    }
}

fn same_source_word(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    token: long,
    start: long,
    length: long,
    expected: Ascii max 96,
) -> bool {
    if length != expected.len() { return false }
    for index in 0L..length {
        if source[start + index] != expected.bytes()[index] { return false }
    }
    true
}

fn token_is_word(source: Bytes max SOURCE_BUFFER_CAPACITY, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, token: long, base: long, expected: Ascii max 96) -> bool {
    if token < 0L || token >= tokens.count() { return false }
    if tokens[token].kind != TokenKind.Ident { return false }
    same_source_word(source, token, base + tokens[token].start, tokens[token].length, expected)
}

fn cursor_peek(tables: ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, ahead: long) -> CursorToken {
    let state = tables.state
    let remaining_split = state.split_count - state.split_index
    if state.split_count > 0L && ahead < remaining_split {
        let piece_index = state.split_index + ahead
        let start = tokens[state.pos].start + piece_index
        let kind = if piece_index < 2L { TokenKind.Gt } else { TokenKind.Eq }
        return CursorToken { kind, token: state.pos, start, length: 1L, virtual_piece: true }
    }
    let token_index = if state.split_count > 0L {
        state.pos + 1L + ahead - remaining_split
    } else {
        state.pos + ahead
    }
    let index = if token_index >= state.token_end { state.token_end - 1L } else { token_index }
    let token = tokens[index]
    CursorToken { kind: token.kind, token: index, start: token.start, length: token.length, virtual_piece: false }
}

fn cursor_word_is(source: Bytes max SOURCE_BUFFER_CAPACITY, tables: ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, word: Ascii max 96) -> bool {
    let token = cursor_peek(tables, tokens, 0L)
    if token.kind != TokenKind.Ident { return false }
    same_source_word(source, token.token, tables.state.file_base + token.start, token.length, word)
}

fn cursor_next(tables: write ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>) -> CursorToken {
    let token = cursor_peek(tables, tokens, 0L)
    if token.virtual_piece {
        if tables.state.split_index + 1L < tables.state.split_count {
            tables.state.split_index += 1L
        } else {
            tables.state.pos += 1L
            tables.state.split_count = 0L
            tables.state.split_index = 0L
        }
    } else if token.kind != TokenKind.Eof {
        tables.state.pos += 1L
    } else {
        ()
    }
    tables.state.last_end = token.start + token.length
    token
}

fn cursor_take(tables: write ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, kind: TokenKind) -> bool {
    if cursor_peek(tables, tokens, 0L).kind == kind {
        cursor_next(tables, tokens)
        true
    } else {
        false
    }
}

fn cursor_error(tables: ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, kind: ParseProblemKind) -> ParseError {
    let token = cursor_peek(tables, tokens, 0L)
    ParseError { kind, offset: token.start, token: token.token }
}

fn cursor_expect(tables: write ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, kind: TokenKind, problem: ParseProblemKind) -> Result<CursorToken, ParseError> {
    if cursor_peek(tables, tokens, 0L).kind == kind {
        ok(cursor_next(tables, tokens))
    } else {
        err(cursor_error(tables, tokens, problem))
    }
}

fn cursor_expect_word(source: Bytes max SOURCE_BUFFER_CAPACITY, tables: write ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, word: Ascii max 96, problem: ParseProblemKind) -> Result<CursorToken, ParseError> {
    if cursor_word_is(source, tables, tokens, word) {
        ok(cursor_next(tables, tokens))
    } else {
        err(cursor_error(tables, tokens, problem))
    }
}

fn cursor_skip_newlines(tables: write ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>) {
    for step in 0L..MAX_TOKENS_PER_FILE {
        if !cursor_take(tables, tokens, TokenKind.Newline) { break }
    }
}

fn cursor_skip_separators(tables: write ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>) -> long {
    var count = 0L
    for step in 0L..MAX_TOKENS_PER_FILE {
        if cursor_take(tables, tokens, TokenKind.Newline) || cursor_take(tables, tokens, TokenKind.Semicolon) {
            count += 1L
        } else { break }
    }
    count
}

fn cursor_expect_type_gt(tables: write ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, problem: ParseProblemKind) -> Result<CursorToken, ParseError> {
    let token = cursor_peek(tables, tokens, 0L)
    if tables.state.split_count == 0L {
        if token.kind == TokenKind.Shr {
            tables.state.split_count = 2L
            tables.state.split_index = 0L
            tables.state.split_kind = TokenKind.Shr
        } else if token.kind == TokenKind.ShrEq {
            tables.state.split_count = 3L
            tables.state.split_index = 0L
            tables.state.split_kind = TokenKind.ShrEq
        } else {
            ()
        }
    }
    cursor_expect(tables, tokens, TokenKind.Gt, problem)
}

fn append_extra(tables: write ParseTables, value: long) -> Result<long, ParseError> {
    let index = tables.extra.count()
    match tables.extra.push(value) {
        ok(_) => ok(index),
        err(Full) => err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: tables.state.last_end, token: tables.state.pos }),
    }
}

fn append_literal(tables: write ParseTables, value: Literal128) -> Result<long, ParseError> {
    let index = tables.literals.count()
    match tables.literals.push(value) {
        ok(_) => ok(index),
        err(Full) => err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: tables.state.last_end, token: tables.state.pos }),
    }
}

fn append_node(
    tables: write ParseTables,
    kind: NodeKind,
    first_child: long,
    token: long,
    start: long,
    end: long,
    anchor: long,
    flags: long,
    extra: long,
    aux: long,
) -> Result<long, ParseError> {
    let index = tables.nodes.count()
    if first_child < tables.file_first_node || first_child > index {
        return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: start, token })
    }
    // Children are appended as complete subtrees. Verify that their backward
    // subtree walk lands exactly at first_child before adding this parent.
    var child = index - 1L
    for step in 0L..index - first_child {
        if child < first_child { break }
        if tables.nodes[child].subtree <= 0L {
            return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: start, token })
        }
        let subtree_start = child - tables.nodes[child].subtree + 1L
        if subtree_start < first_child {
            return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: start, token })
        }
        child = subtree_start - 1L
    }
    if child != first_child - 1L {
        return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: start, token })
    }
    let node = Node {
        kind,
        flags,
        token,
        start,
        end,
        anchor,
        subtree: index - first_child + 1L,
        extra,
        aux,
        meta0: 0L,
        meta1: 0L,
    }
    match tables.nodes.push(node) {
        ok(_) => ok(index),
        err(Full) => err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: start, token }),
    }
}

fn materialize_pending(tables: write ParseTables, expression: ExprRef) -> Result<ExprRef, ParseError> {
    if expression.node >= 0L { return ok(expression) }
    let kind = if expression.pending_kind == PENDING_NAME { NodeKind.Name } else { NodeKind.Name }
    let first = tables.nodes.count()
    let node = append_node(tables, kind, first, expression.token, expression.start, expression.end, expression.start, 0L, -1L, 0L)?
    ok(ExprRef { node, pending_kind: 0L, token: expression.token, extra_token: expression.extra_token, start: expression.start, end: expression.end })
}

fn materialize_node(tables: write ParseTables, expression: ExprRef) -> Result<long, ParseError> {
    let materialized = materialize_pending(tables, expression)?
    ok(materialized.node)
}

fn node_first_child(nodes: list<Node, NODE_STORAGE_CAPACITY>, node: long) -> long {
    if node < 0L || node >= nodes.count() { return -1L }
    node - nodes[node].subtree + 1L
}

fn node_first_direct_child(nodes: list<Node, NODE_STORAGE_CAPACITY>, node: long) -> long {
    if node < 0L || node >= nodes.count() { return -1L }
    let first = node_first_child(nodes, node)
    if first == node { return node }
    var child = node - 1L
    for step in 0L..nodes[node].subtree {
        let subtree_start = child - nodes[child].subtree + 1L
        if subtree_start == first { return child }
        child = subtree_start - 1L
    }
    node
}

fn node_child_count(nodes: list<Node, NODE_STORAGE_CAPACITY>, node: long) -> long {
    let first = node_first_child(nodes, node)
    var child = node - 1L
    var count = 0L
    for step in 0L..nodes[node].subtree {
        if child < first { break }
        count += 1L
        child -= nodes[child].subtree
    }
    count
}

fn node_child_at(nodes: list<Node, NODE_STORAGE_CAPACITY>, node: long, wanted: long) -> long {
    let first = node_first_child(nodes, node)
    let count = node_child_count(nodes, node)
    if wanted < 0L || wanted >= count { return -1L }
    var child = node - 1L
    for step in 0L..count {
        if count - step - 1L == wanted { return child }
        child -= nodes[child].subtree
    }
    -1L
}

fn parse_empty_error(offset: long, token: long, kind: ParseProblemKind) -> ParseError {
    ParseError { kind, offset, token }
}

recursive fn parse_file(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    file_base: long,
    file_length: long,
    first_token: long,
    token_count: long,
) -> Result<long, ParseError> {
    tables.state.pos = first_token
    tables.state.token_end = first_token + token_count
    tables.state.file_base = file_base
    tables.state.file_length = file_length
    tables.state.split_count = 0L
    tables.state.split_index = 0L
    tables.state.last_end = 0L
    tables.state.expression_depth = 0L
    tables.state.expression_depth_adjustment = 0L
    tables.state.cast_depth = 0L
    tables.state.parenthesis_depth = 0L
    tables.state.block_depth = 0L
    tables.state.type_depth = 0L
    tables.state.allow_struct_literals = true
    tables.file_first_node = tables.nodes.count()
    parse_program(source, tokens, tables, file_length)
}

recursive fn parse_program(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    file_length: long,
) -> Result<long, ParseError> {
    let first = tables.file_first_node
    cursor_skip_separators(tables, tokens)
    for step in 0L..MAX_TOKENS_PER_FILE {
        if cursor_peek(tables, tokens, 0L).kind == TokenKind.Eof { break }
        var item = -1L
        if cursor_word_is(source, tables, tokens, "enum") {
            item = parse_enum_decl(source, tokens, tables)?
        } else if cursor_word_is(source, tables, tokens, "struct") {
            item = parse_struct_decl(source, tokens, tables)?
        } else if cursor_word_is(source, tables, tokens, "type") {
            item = parse_alias_decl(source, tokens, tables)?
        } else if cursor_word_is(source, tables, tokens, "const") {
            item = parse_const_decl(source, tokens, tables)?
        } else if cursor_word_is(source, tables, tokens, "global") {
            item = parse_global_decl(source, tokens, tables)?
        } else if cursor_word_is(source, tables, tokens, "test") {
            item = parse_test_decl(source, tokens, tables)?
        } else {
            item = parse_function_decl(source, tokens, tables)?
        }
        tables.nodes[item].end = tables.state.last_end
        let next = cursor_peek(tables, tokens, 0L)
        if next.kind != TokenKind.Newline && next.kind != TokenKind.Semicolon && next.kind != TokenKind.Eof {
            return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedSeparator))
        }
        cursor_skip_separators(tables, tokens)
    }
    append_node(
        tables,
        NodeKind.Program,
        first,
        -1L,
        0L,
        file_length,
        0L,
        0L,
        -1L,
        0L,
    )
}

recursive fn parse_enum_decl(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let start_token = cursor_expect_word(source, tables, tokens, "enum", ParseProblemKind.ExpectedFunction)?
    let name = parse_identifier(source, tokens, tables, ParseProblemKind.ExpectedEnumName)?
    let first = tables.nodes.count()
    cursor_skip_newlines(tables, tokens)
    cursor_expect(tables, tokens, TokenKind.LBrace, ParseProblemKind.ExpectedEnumOpen)?
    cursor_skip_separators(tables, tokens)
    var case_count = 0L
    for step in 0L..MAX_TOKENS_PER_FILE {
        if cursor_peek(tables, tokens, 0L).kind == TokenKind.RBrace || cursor_peek(tables, tokens, 0L).kind == TokenKind.Eof { break }
        let case_token = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedEnumCase)?
        let case_first = tables.nodes.count()
        var payload_count = 0L
        if cursor_take(tables, tokens, TokenKind.LParen) {
            cursor_skip_newlines(tables, tokens)
            if cursor_peek(tables, tokens, 0L).kind != TokenKind.RParen {
                for payload_step in 0L..MAX_TOKENS_PER_FILE {
                    parse_type(source, tokens, tables, NodeKind.PayloadType)?
                    payload_count += 1L
                    cursor_skip_newlines(tables, tokens)
                    if !cursor_take(tables, tokens, TokenKind.Comma) { break }
                    cursor_skip_newlines(tables, tokens)
                    if cursor_peek(tables, tokens, 0L).kind == TokenKind.RParen { break }
                }
            }
            cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedEnumPayloadClose)?
        }
        let case_end = tables.state.last_end
        append_node(tables, NodeKind.EnumCase, case_first, case_token.token, case_token.start, case_end, case_token.start, 0L, -1L, payload_count)?
        case_count += 1L
        let separated = cursor_skip_separators(tables, tokens) > 0L
        if cursor_take(tables, tokens, TokenKind.Comma) {
            cursor_skip_separators(tables, tokens)
            ()
        } else if cursor_peek(tables, tokens, 0L).kind != TokenKind.RBrace && !separated {
            return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedEnumComma))
        } else {
            ()
        }
    }
    if case_count == 0L {
        return err(ParseError { kind: ParseProblemKind.EnumEmpty, offset: start_token.start, token: start_token.token })
    }
    let close = cursor_expect(tables, tokens, TokenKind.RBrace, ParseProblemKind.ExpectedEnumClose)?
    append_node(tables, NodeKind.Enum, first, name.token, start_token.start, close.start + close.length, start_token.start, 0L, -1L, case_count)
}

recursive fn parse_struct_decl(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let start = cursor_expect_word(source, tables, tokens, "struct", ParseProblemKind.ExpectedFunction)?
    let name = parse_identifier(source, tokens, tables, ParseProblemKind.ExpectedStructName)?
    let generic_start = tables.extra.count()
    let generic_count = parse_generic_params(source, tokens, tables)?
    cursor_skip_newlines(tables, tokens)
    cursor_expect(tables, tokens, TokenKind.LBrace, ParseProblemKind.ExpectedStructOpen)?
    let first = tables.nodes.count()
    cursor_skip_separators(tables, tokens)
    var field_count = 0L
    for step in 0L..MAX_TOKENS_PER_FILE {
        if cursor_peek(tables, tokens, 0L).kind == TokenKind.RBrace || cursor_peek(tables, tokens, 0L).kind == TokenKind.Eof { break }
        let field = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedFieldName)?
        cursor_expect(tables, tokens, TokenKind.Colon, ParseProblemKind.ExpectedFieldColon)?
        let field_first = tables.nodes.count()
        parse_type(source, tokens, tables, NodeKind.FieldType)?
        if cursor_take(tables, tokens, TokenKind.Eq) {
            parse_expression(source, tokens, tables, 0L)?
        }
        let field_end = tables.state.last_end
        append_node(tables, NodeKind.StructField, field_first, field.token, field.start, field_end, field.start, 0L, -1L, 0L)?
        field_count += 1L
        let separated = cursor_skip_separators(tables, tokens) > 0L
        if cursor_take(tables, tokens, TokenKind.Comma) {
            cursor_skip_separators(tables, tokens)
            ()
        } else if cursor_peek(tables, tokens, 0L).kind != TokenKind.RBrace && !separated {
            return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedComma))
        } else {
            ()
        }
    }
    let close = cursor_expect(tables, tokens, TokenKind.RBrace, ParseProblemKind.ExpectedStructClose)?
    append_node(tables, NodeKind.Struct, first, name.token, start.start, close.start + close.length, start.start, 0L, generic_start, generic_count + field_count * 0L)
}

recursive fn parse_alias_decl(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let start = cursor_expect_word(source, tables, tokens, "type", ParseProblemKind.ExpectedFunction)?
    let name = parse_identifier(source, tokens, tables, ParseProblemKind.ExpectedTypeName)?
    cursor_expect(tables, tokens, TokenKind.Eq, ParseProblemKind.ExpectedAliasEq)?
    let first = tables.nodes.count()
    parse_type(source, tokens, tables, NodeKind.AliasedType)?
    let end = tables.state.last_end
    append_node(tables, NodeKind.TypeAlias, first, name.token, start.start, end, start.start, 0L, -1L, 0L)
}

recursive fn parse_const_decl(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let start = cursor_expect_word(source, tables, tokens, "const", ParseProblemKind.ExpectedFunction)?
    let name = parse_identifier(source, tokens, tables, ParseProblemKind.ExpectedConstName)?
    cursor_expect(tables, tokens, TokenKind.Colon, ParseProblemKind.ExpectedConstColon)?
    let first = tables.nodes.count()
    parse_type(source, tokens, tables, NodeKind.DeclaredType)?
    cursor_expect(tables, tokens, TokenKind.Eq, ParseProblemKind.ExpectedConstEq)?
    parse_expression(source, tokens, tables, 0L)?
    let end = tables.state.last_end
    append_node(tables, NodeKind.Const, first, name.token, start.start, end, start.start, 0L, -1L, 0L)
}

recursive fn parse_global_decl(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let start = cursor_expect_word(source, tables, tokens, "global", ParseProblemKind.ExpectedFunction)?
    let name = parse_identifier(source, tokens, tables, ParseProblemKind.ExpectedGlobalName)?
    cursor_expect(tables, tokens, TokenKind.Colon, ParseProblemKind.ExpectedGlobalColon)?
    let first = tables.nodes.count()
    parse_type(source, tokens, tables, NodeKind.DeclaredType)?
    var flags = 0L
    if cursor_word_is(source, tables, tokens, "prefault") {
        cursor_next(tables, tokens)
        flags = FLAG_PREFAULT
        if cursor_word_is(source, tables, tokens, "prefault") {
            let token = cursor_peek(tables, tokens, 0L)
            return err(ParseError { kind: ParseProblemKind.DuplicatePrefault, offset: token.start, token: token.token })
        }
    }
    if cursor_word_is(source, tables, tokens, "locked") {
        let token = cursor_peek(tables, tokens, 0L)
        return err(ParseError { kind: ParseProblemKind.LockedGlobal, offset: token.start, token: token.token })
    }
    cursor_expect(tables, tokens, TokenKind.Eq, ParseProblemKind.ExpectedGlobalEq)?
    parse_expression(source, tokens, tables, 0L)?
    let end = tables.state.last_end
    append_node(tables, NodeKind.Global, first, name.token, start.start, end, start.start, flags, -1L, 0L)
}

recursive fn parse_test_decl(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let start = cursor_expect_word(source, tables, tokens, "test", ParseProblemKind.ExpectedFunction)?
    let name = cursor_peek(tables, tokens, 0L)
    if name.kind != TokenKind.String {
        return err(ParseError { kind: ParseProblemKind.ExpectedTestName, offset: name.start, token: name.token })
    }
    cursor_next(tables, tokens)
    let first = tables.nodes.count()
    var param_count = 0L
    cursor_skip_newlines(tables, tokens)
    if cursor_take(tables, tokens, TokenKind.LParen) {
        cursor_skip_newlines(tables, tokens)
        if cursor_peek(tables, tokens, 0L).kind != TokenKind.RParen {
            for step in 0L..MAX_TOKENS_PER_FILE {
                parse_parameter(source, tokens, tables, true)?
                param_count += 1L
                cursor_skip_newlines(tables, tokens)
                if !cursor_take(tables, tokens, TokenKind.Comma) { break }
                cursor_skip_newlines(tables, tokens)
                if cursor_peek(tables, tokens, 0L).kind == TokenKind.RParen { break }
            }
        }
        cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedTestParamClose)?
        cursor_skip_newlines(tables, tokens)
    }
    parse_block(source, tokens, tables)?
    let end = tables.state.last_end
    append_node(tables, NodeKind.Test, first, name.token, start.start, end, start.start, 0L, -1L, param_count)
}

recursive fn parse_function_decl(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let recursive = cursor_word_is(source, tables, tokens, "recursive")
    let start = if recursive {
        let token = cursor_next(tables, tokens)
        cursor_expect_word(source, tables, tokens, "fn", ParseProblemKind.ExpectedFnAfterRecursive)?
        token
    } else {
        cursor_expect_word(source, tables, tokens, "fn", ParseProblemKind.ExpectedFunction)?
    }
    let name = parse_identifier(source, tokens, tables, ParseProblemKind.ExpectedFunctionName)?
    let generic_start = tables.extra.count()
    let generic_count = parse_generic_params(source, tokens, tables)?
    cursor_expect(tables, tokens, TokenKind.LParen, ParseProblemKind.ExpectedFunctionParen)?
    let first = tables.nodes.count()
    var param_count = 0L
    cursor_skip_newlines(tables, tokens)
    if cursor_peek(tables, tokens, 0L).kind != TokenKind.RParen {
        for step in 0L..MAX_TOKENS_PER_FILE {
            parse_parameter(source, tokens, tables, false)?
            param_count += 1L
            cursor_skip_newlines(tables, tokens)
            if !cursor_take(tables, tokens, TokenKind.Comma) { break }
            cursor_skip_newlines(tables, tokens)
            if cursor_peek(tables, tokens, 0L).kind == TokenKind.RParen { break }
        }
    }
    cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedParameterClose)?
    cursor_skip_newlines(tables, tokens)
    if cursor_take(tables, tokens, TokenKind.Arrow) {
        cursor_skip_newlines(tables, tokens)
        parse_type(source, tokens, tables, NodeKind.ResultType)?
    }
    cursor_skip_newlines(tables, tokens)
    parse_block(source, tokens, tables)?
    let flags = if recursive { FLAG_RECURSIVE } else { 0L }
    let end = tables.state.last_end
    append_node(tables, NodeKind.Function, first, name.token, start.start, end, start.start, flags, generic_start, generic_count + param_count * 0L)
}

recursive fn parse_parameter(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    is_test: bool,
) -> Result<long, ParseError> {
    cursor_skip_newlines(tables, tokens)
    let name = parse_identifier(source, tokens, tables, if is_test { ParseProblemKind.ExpectedTestParamName } else { ParseProblemKind.ExpectedParameterName })?
    cursor_expect(tables, tokens, TokenKind.Colon, if is_test { ParseProblemKind.ExpectedTestParamColon } else { ParseProblemKind.ExpectedParameterColon })?
    var flags = 0L
    if cursor_word_is(source, tables, tokens, "write") {
        cursor_next(tables, tokens)
        flags = FLAG_MODE_WRITE
    } else if cursor_word_is(source, tables, tokens, "grow") {
        cursor_next(tables, tokens)
        flags = FLAG_MODE_GROW
    } else {
        ()
    }
    let first = tables.nodes.count()
    parse_type(source, tokens, tables, NodeKind.ParameterType)?
    let end = tables.state.last_end
    append_node(tables, NodeKind.Parameter, first, name.token, name.start, end, name.start, flags, -1L, 0L)
}

recursive fn parse_identifier(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    problem: ParseProblemKind,
) -> Result<CursorToken, ParseError> {
    cursor_expect(tables, tokens, TokenKind.Ident, problem)
}

recursive fn parse_generic_params(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    if !cursor_take(tables, tokens, TokenKind.Lt) { return ok(0L) }
    tables.state.seen_generation += 1L
    if tables.state.seen_generation >= 2147483647L { tables.state.seen_generation = 1L }
    let generation = tables.state.seen_generation
    var count = 0L
    for step in 0L..MAX_TOKENS_PER_FILE {
        let name = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedGenericName)?
        var hash = 2166136261L
        for byte_index in 0L..name.length {
            hash = (hash * 16777619L + source[tables.state.file_base + name.start + byte_index].to_long()) % 4294967291L
        }
        var slot_index = hash % GENERIC_HASH_CAPACITY
        var found = false
        for probe in 0L..GENERIC_HASH_CAPACITY {
            let slot = tables.seen[slot_index]
            if slot.generation != generation {
                tables.seen[slot_index] = SeenSlot { generation, token: name.token }
                break
            }
            if same_token_spelling(source, tokens, tables.state.file_base, slot.token, name.token) {
                return err(ParseError { kind: ParseProblemKind.DuplicateGeneric, offset: name.start, token: name.token })
            }
            slot_index = (slot_index + 1L) % GENERIC_HASH_CAPACITY
            if probe + 1L == GENERIC_HASH_CAPACITY { found = true }
        }
        if found { return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: name.start, token: name.token }) }
        append_extra(tables, name.token)?
        count += 1L
        if !cursor_take(tables, tokens, TokenKind.Comma) { break }
    }
    cursor_expect_type_gt(tables, tokens, ParseProblemKind.ExpectedGenericClose)?
    if count == 0L { return ok(0L) }
    ok(count)
}

fn same_token_spelling(source: Bytes max SOURCE_BUFFER_CAPACITY, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, base: long, left: long, right: long) -> bool {
    if tokens[left].length != tokens[right].length { return false }
    for index in 0L..tokens[left].length {
        if source[base + tokens[left].start + index] != source[base + tokens[right].start + index] { return false }
    }
    true
}

recursive fn parse_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    label: NodeKind,
) -> Result<long, ParseError> {
    if tables.state.type_depth >= MAX_PARSER_DEPTH {
        return err(cursor_error(tables, tokens, ParseProblemKind.TypeDepth))
    }
    tables.state.type_depth += 1L
    let parsed = parse_type_inner(source, tokens, tables, label)
    tables.state.type_depth -= 1L
    let node = parsed?
    tables.nodes[node].end = tables.state.last_end
    ok(node)
}

recursive fn parse_type_inner(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    label: NodeKind,
) -> Result<long, ParseError> {
    let current = cursor_peek(tables, tokens, 0L)
    if cursor_word_is(source, tables, tokens, "fn") {
        let first = tables.nodes.count()
        let function = parse_function_type(source, tokens, tables)?
        let start = tables.nodes[function].start
        var array_count = 0L
        for step in 0L..MAX_TOKENS_PER_FILE {
            if !cursor_take(tables, tokens, TokenKind.LBracket) { break }
            parse_expression(source, tokens, tables, 8L)?
            cursor_expect(tables, tokens, TokenKind.RBracket, ParseProblemKind.ExpectedCloseBracket)?
            array_count += 1L
        }
        let end = tables.state.last_end
        let node = append_node(tables, label, first, -1L, start, end, start, FLAG_TYPE_FN, -1L, 0L)?
        tables.nodes[node].meta1 = pack_type_counts(0L, 0L, array_count)
        ok(node)
    } else if cursor_take(tables, tokens, TokenKind.LParen) {
        let open = tables.state.last_end - 1L
        if cursor_take(tables, tokens, TokenKind.RParen) {
            let close_end = tables.state.last_end
            let first = tables.nodes.count()
            append_node(tables, label, first, -1L, open, close_end, open, FLAG_TYPE_UNIT, -1L, 0L)
        } else {
            let inner = parse_type(source, tokens, tables, label)?
            cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedCloseParen)?
            let first_child = node_first_child(tables.nodes, inner)
            let kind = tables.nodes[inner].kind
            let flags = tables.nodes[inner].flags
            let token = tables.nodes[inner].token
            let anchor = tables.nodes[inner].anchor
            let extra = tables.nodes[inner].extra
            let aux = tables.nodes[inner].aux
            let meta0 = tables.nodes[inner].meta0
            let meta1 = tables.nodes[inner].meta1
            if cursor_peek(tables, tokens, 0L).kind != TokenKind.LBracket {
                tables.nodes[inner].start = open
                tables.nodes[inner].end = tables.state.last_end
                return ok(inner)
            }
            tables.nodes.pop()
            var added_arrays = 0L
            for step in 0L..MAX_TOKENS_PER_FILE {
                if !cursor_take(tables, tokens, TokenKind.LBracket) { break }
                parse_expression(source, tokens, tables, 8L)?
                cursor_expect(tables, tokens, TokenKind.RBracket, ParseProblemKind.ExpectedCloseBracket)?
                added_arrays += 1L
            }
            let end = tables.state.last_end
            let node = append_node(tables, kind, first_child, token, open, end, anchor, flags, extra, aux)?
            tables.nodes[node].meta0 = meta0
            let old_args = meta1 & 2097151L
            let old_constants = (meta1 >> 21L) & 2097151L
            let old_arrays = (meta1 >> 42L) & 2097151L
            tables.nodes[node].meta1 = pack_type_counts(old_args, old_constants, old_arrays + added_arrays)
            ok(node)
        }
    } else {
        parse_named_type(source, tokens, tables, label, current)
    }
}

recursive fn parse_named_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    label: NodeKind,
    start_token: CursorToken,
) -> Result<long, ParseError> {
    let name = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedTypeName)?
    var flags = 0L
    let extra_start = tables.extra.count()
    var extra_names = 1L
    append_extra(tables, name.token)?
    for step in 0L..MAX_TOKENS_PER_FILE {
        if !cursor_take(tables, tokens, TokenKind.Dot) { break }
        let part = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedTypePathPart)?
        append_extra(tables, part.token)?
        extra_names += 1L
    }
    let children_first = tables.nodes.count()
    var args = 0L
    var constants = 0L
    var arrays = 0L
    if cursor_take(tables, tokens, TokenKind.Lt) {
        parse_type(source, tokens, tables, NodeKind.TypeArgument)?
        args += 1L
        if (type_name_is(source, tokens, tables, name.token, "list") || type_name_is(source, tokens, tables, name.token, "pool") || type_name_is(source, tokens, tables, name.token, "queue") || type_name_is(source, tokens, tables, name.token, "ring")) && cursor_take(tables, tokens, TokenKind.Comma) {
            cursor_skip_newlines(tables, tokens)
            parse_expression(source, tokens, tables, 8L)?
            constants += 1L
            if type_name_is(source, tokens, tables, name.token, "pool") && cursor_take(tables, tokens, TokenKind.Comma) {
                cursor_skip_newlines(tables, tokens)
                parse_type(source, tokens, tables, NodeKind.TypeArgument)?
                args += 1L
            }
        } else if type_name_is(source, tokens, tables, name.token, "grid") {
            cursor_expect(tables, tokens, TokenKind.Comma, ParseProblemKind.ExpectedGridWidth)?
            cursor_skip_newlines(tables, tokens)
            parse_expression(source, tokens, tables, 8L)?
            constants += 1L
            cursor_expect(tables, tokens, TokenKind.Comma, ParseProblemKind.ExpectedGridHeight)?
            cursor_skip_newlines(tables, tokens)
            parse_expression(source, tokens, tables, 8L)?
            constants += 1L
        } else if type_name_is(source, tokens, tables, name.token, "map") {
            cursor_expect(tables, tokens, TokenKind.Comma, ParseProblemKind.ExpectedMapValue)?
            cursor_skip_newlines(tables, tokens)
            parse_type(source, tokens, tables, NodeKind.TypeArgument)?
            args += 1L
            cursor_expect(tables, tokens, TokenKind.Comma, ParseProblemKind.ExpectedMapCapacity)?
            cursor_skip_newlines(tables, tokens)
            parse_expression(source, tokens, tables, 8L)?
            constants += 1L
        } else if type_name_is(source, tokens, tables, name.token, "set") {
            cursor_expect(tables, tokens, TokenKind.Comma, ParseProblemKind.ExpectedSetCapacity)?
            cursor_skip_newlines(tables, tokens)
            parse_expression(source, tokens, tables, 8L)?
            constants += 1L
        } else {
            for arg_step in 0L..MAX_TOKENS_PER_FILE {
                if !cursor_take(tables, tokens, TokenKind.Comma) { break }
                cursor_skip_newlines(tables, tokens)
                parse_type(source, tokens, tables, NodeKind.TypeArgument)?
                args += 1L
            }
        }
        cursor_expect_type_gt(tables, tokens, ParseProblemKind.ExpectedTypeArgsClose)?
    }
    var range_extra = -1L
    if cursor_peek(tables, tokens, 0L).kind == TokenKind.Number || cursor_peek(tables, tokens, 0L).kind == TokenKind.Minus {
        let lower = parse_range_bound(source, tokens, tables)?
        let inclusive = cursor_take(tables, tokens, TokenKind.RangeInclusive)
        if !inclusive { cursor_expect(tables, tokens, TokenKind.Range, ParseProblemKind.ExpectedTypeRange)? }
        let upper = parse_range_bound(source, tokens, tables)?
        range_extra = tables.extra.count()
        append_extra(tables, lower.literal)?
        append_extra(tables, lower.negative)?
        append_extra(tables, upper.literal)?
        append_extra(tables, upper.negative)?
        flags = flags | FLAG_RANGE
        if inclusive { flags = flags | FLAG_RANGE_INCLUSIVE }
    }
    if cursor_word_is(source, tables, tokens, "wrap") {
        cursor_next(tables, tokens)
        flags = flags | FLAG_POLICY_WRAP
    } else if cursor_word_is(source, tables, tokens, "clamp") {
        cursor_next(tables, tokens)
        flags = flags | FLAG_POLICY_CLAMP
    } else {
        ()
    }
    if (flags & (FLAG_POLICY_WRAP | FLAG_POLICY_CLAMP)) != 0L && (flags & FLAG_RANGE) == 0L {
        return err(ParseError { kind: ParseProblemKind.PolicyNeedsRange, offset: start_token.start, token: start_token.token })
    }
    if type_name_is(source, tokens, tables, name.token, "Ascii") || type_name_is(source, tokens, tables, name.token, "Bytes") {
        if cursor_word_is(source, tables, tokens, "max") {
            cursor_next(tables, tokens)
            parse_expression(source, tokens, tables, 8L)?
            constants += 1L
        }
    }
    if type_name_is(source, tokens, tables, name.token, "Text") {
        if cursor_word_is(source, tables, tokens, "max") {
            cursor_next(tables, tokens)
            parse_expression(source, tokens, tables, 8L)?
            constants += 1L
            if cursor_word_is(source, tables, tokens, "bytes") {
                cursor_next(tables, tokens)
                cursor_expect_word(source, tables, tokens, "max", ParseProblemKind.ExpectedTextMax)?
                parse_expression(source, tokens, tables, 8L)?
                constants += 1L
            }
        } else if cursor_word_is(source, tables, tokens, "bytes") {
            cursor_next(tables, tokens)
            cursor_expect_word(source, tables, tokens, "max", ParseProblemKind.ExpectedTextMax)?
            parse_expression(source, tokens, tables, 8L)?
            constants += 1L
            flags = flags | FLAG_TYPE_TEXT_BYTES
        } else {
            ()
        }
    }
    for step in 0L..MAX_TOKENS_PER_FILE {
        if !cursor_take(tables, tokens, TokenKind.LBracket) { break }
        parse_expression(source, tokens, tables, 8L)?
        cursor_expect(tables, tokens, TokenKind.RBracket, ParseProblemKind.ExpectedCloseBracket)?
        arrays += 1L
    }
    let end = tables.state.last_end
    let node = append_node(tables, label, children_first, name.token, start_token.start, end, range_extra, flags, extra_start, 0L)?
    tables.nodes[node].meta0 = extra_names
    tables.nodes[node].meta1 = pack_type_counts(args, constants, arrays)
    ok(node)
}

fn type_name_is(source: Bytes max SOURCE_BUFFER_CAPACITY, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, tables: ParseTables, token: long, expected: Ascii max 96) -> bool {
    token_is_word(source, tokens, token, tables.state.file_base, expected)
}

recursive fn parse_function_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let start = cursor_expect_word(source, tables, tokens, "fn", ParseProblemKind.ExpectedFunctionTypeParen)?
    if cursor_take(tables, tokens, TokenKind.Lt) {
        return err(ParseError { kind: ParseProblemKind.UnsupportedGenericFunctionType, offset: start.start, token: start.token })
    }
    cursor_expect(tables, tokens, TokenKind.LParen, ParseProblemKind.ExpectedFunctionTypeParen)?
    let first = tables.nodes.count()
    var param_count = 0L
    cursor_skip_newlines(tables, tokens)
    if cursor_peek(tables, tokens, 0L).kind != TokenKind.RParen {
        for step in 0L..MAX_TOKENS_PER_FILE {
            cursor_skip_newlines(tables, tokens)
            let param_start = cursor_peek(tables, tokens, 0L)
            var flags = 0L
            if cursor_word_is(source, tables, tokens, "write") {
                cursor_next(tables, tokens)
                flags = FLAG_MODE_WRITE
            } else if cursor_word_is(source, tables, tokens, "grow") {
                cursor_next(tables, tokens)
                flags = FLAG_MODE_GROW
            } else {
                ()
            }
            let type_first = tables.nodes.count()
            parse_type(source, tokens, tables, NodeKind.ParameterType)?
            let param_end = tables.state.last_end
            append_node(tables, NodeKind.FunctionTypeParameter, type_first, -1L, param_start.start, param_end, param_start.start, flags, -1L, 0L)?
            param_count += 1L
            cursor_skip_newlines(tables, tokens)
            if !cursor_take(tables, tokens, TokenKind.Comma) { break }
            cursor_skip_newlines(tables, tokens)
            if cursor_peek(tables, tokens, 0L).kind == TokenKind.RParen { break }
        }
    }
    cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedFunctionTypeClose)?
    cursor_skip_newlines(tables, tokens)
    if cursor_take(tables, tokens, TokenKind.Arrow) {
        cursor_skip_newlines(tables, tokens)
        parse_type(source, tokens, tables, NodeKind.ResultType)?
    }
    if cursor_word_is(source, tables, tokens, "effects") {
        cursor_next(tables, tokens)
        for step in 0L..MAX_TOKENS_PER_FILE {
            let effect = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedEffect)?
            var flags = 0L
            var extra_start = -1L
            var path_count = 0L
            if token_is_word(source, tokens, effect.token, tables.state.file_base, "out") {
                flags = 1L
            } else if token_is_word(source, tokens, effect.token, tables.state.file_base, "env") {
                flags = 2L
            } else if token_is_word(source, tokens, effect.token, tables.state.file_base, "fs") {
                cursor_expect(tables, tokens, TokenKind.Dot, ParseProblemKind.ExpectedFsEffect)?
                let operation = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedFsOperation)?
                if token_is_word(source, tokens, operation.token, tables.state.file_base, "read") { flags = 3L }
                else if token_is_word(source, tokens, operation.token, tables.state.file_base, "write") { flags = 4L }
                else { return err(ParseError { kind: ParseProblemKind.BadFsEffect, offset: operation.start, token: operation.token }) }
            } else if token_is_word(source, tokens, effect.token, tables.state.file_base, "reads") || token_is_word(source, tokens, effect.token, tables.state.file_base, "writes") {
                flags = if token_is_word(source, tokens, effect.token, tables.state.file_base, "writes") { FLAG_EFFECT_WRITES | 5L } else { 5L }
                let root = cursor_expect(tables, tokens, TokenKind.Ident, if (flags & FLAG_EFFECT_WRITES) != 0L { ParseProblemKind.ExpectedWritesPath } else { ParseProblemKind.ExpectedReadsPath })?
                extra_start = tables.extra.count()
                append_extra(tables, root.token)?
                path_count = 1L
                for path_step in 0L..MAX_TOKENS_PER_FILE {
                    if !cursor_take(tables, tokens, TokenKind.Dot) { break }
                    let part = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedEffectPathPart)?
                    append_extra(tables, part.token)?
                    path_count += 1L
                }
            } else {
                return err(ParseError { kind: ParseProblemKind.UnknownEffect, offset: effect.start, token: effect.token })
            }
            let end = tables.state.last_end
            let first_effect_child = tables.nodes.count()
            append_node(tables, NodeKind.Effect, first_effect_child, effect.token, effect.start, end, effect.start, flags, extra_start, path_count)?
            let next = cursor_peek(tables, tokens, 0L)
            if next.kind != TokenKind.Comma { break }
            let following = cursor_peek(tables, tokens, 1L)
            if following.kind != TokenKind.Ident { break }
            if !(token_is_word(source, tokens, following.token, tables.state.file_base, "out") || token_is_word(source, tokens, following.token, tables.state.file_base, "env") || token_is_word(source, tokens, following.token, tables.state.file_base, "fs") || token_is_word(source, tokens, following.token, tables.state.file_base, "reads") || token_is_word(source, tokens, following.token, tables.state.file_base, "writes")) { break }
            cursor_next(tables, tokens)
        }
    }
    let end = tables.state.last_end
    append_node(tables, NodeKind.FunctionType, first, start.token, start.start, end, start.start, 0L, -1L, param_count)
}

recursive fn parse_range_bound(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<RangeBound, ParseError> {
    let negative = cursor_take(tables, tokens, TokenKind.Minus)
    let token = cursor_next(tables, tokens)
    if token.kind != TokenKind.Number {
        return err(ParseError { kind: ParseProblemKind.RangeBound, offset: token.start, token: token.token })
    }
    let parsed = parse_literal(source, tables, token.token, token.start, token.length, token.start)?
    let literal_index = parsed.index
    let value = tables.literals[literal_index]
    let low_nonzero = value.limb0 != 0L || value.limb1 != 0L || value.limb2 != 0L
    if !negative && value.limb3 > 2147483647L || negative && (value.limb3 > 2147483648L || value.limb3 == 2147483648L && low_nonzero) {
        return err(ParseError { kind: ParseProblemKind.RangeTooLarge, offset: token.start, token: token.token })
    }
    let is_zero = value.limb0 == 0L && value.limb1 == 0L && value.limb2 == 0L && value.limb3 == 0L
    ok(RangeBound { literal: literal_index, negative: if negative && !is_zero { 1L } else { 0L } })
}

recursive fn parse_literal(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tables: write ParseTables,
    token_index: long,
    start: long,
    token_length: long,
    diagnostic_start: long,
) -> Result<ParsedLiteral, ParseError> {
    let token = token_index
    let token_start = tables.state.file_base + start
    let token_end = token_start + token_length
    var radix = 10L
    var payload_start = token_start
    var payload_end = token_end
    var long_suffix = false
    if payload_end > payload_start && (source[payload_end - 1L] == 76 || source[payload_end - 1L] == 108) {
        long_suffix = true
        payload_end -= 1L
    }
    if payload_end - payload_start >= 2L && source[payload_start] == 48 {
        if source[payload_start + 1L] == 120 || source[payload_start + 1L] == 88 {
            radix = 16L
            payload_start += 2L
        } else if source[payload_start + 1L] == 98 || source[payload_start + 1L] == 66 {
            radix = 2L
            payload_start += 2L
        } else {
            ()
        }
    }
    for at in payload_start..payload_end {
        if source[at] == 95 {
            let previous = if at > payload_start { digit_value(source[at - 1L]) } else { -1L }
            let next = if at + 1L < payload_end { digit_value(source[at + 1L]) } else { -1L }
            if previous < 0L || previous >= radix || next < 0L || next >= radix {
                return err(ParseError { kind: ParseProblemKind.IntegerSeparators, offset: diagnostic_start, token })
            }
        }
    }
    var previous_digit = false
    var any_digit = false
    var value = Literal128 { limb0: 0L, limb1: 0L, limb2: 0L, limb3: 0L }
    for at in payload_start..payload_end {
        let byte_value = source[at]
        if byte_value == 95 {
            previous_digit = false
        } else {
            let digit = digit_value(byte_value)
            if digit < 0L || digit >= radix {
                return err(ParseError { kind: ParseProblemKind.IntegerTooLarge, offset: diagnostic_start, token })
            }
            any_digit = true
            previous_digit = true
            let carry0 = value.limb0 * radix + digit
            value.limb0 = carry0 % 4294967296L
            let carry1 = value.limb1 * radix + carry0 / 4294967296L
            value.limb1 = carry1 % 4294967296L
            let carry2 = value.limb2 * radix + carry1 / 4294967296L
            value.limb2 = carry2 % 4294967296L
            let carry3 = value.limb3 * radix + carry2 / 4294967296L
            value.limb3 = carry3 % 4294967296L
            if carry3 / 4294967296L != 0L {
                return err(ParseError { kind: ParseProblemKind.IntegerTooLarge, offset: diagnostic_start, token })
            }
        }
    }
    if !any_digit { return err(ParseError { kind: ParseProblemKind.IntegerTooLarge, offset: diagnostic_start, token }) }
    let index = append_literal(tables, value)?
    ok(ParsedLiteral { index, long_suffix })
}

fn multiply_literal(value: Literal128, multiplier: long) -> ScaledLiteral {
    let p0 = value.limb0 * multiplier
    let r0 = p0 % 4294967296L
    let p1 = value.limb1 * multiplier + p0 / 4294967296L
    let r1 = p1 % 4294967296L
    let p2 = value.limb2 * multiplier + p1 / 4294967296L
    let r2 = p2 % 4294967296L
    let p3 = value.limb3 * multiplier + p2 / 4294967296L
    let r3 = p3 % 4294967296L
    ScaledLiteral {
        value: Literal128 { limb0: r0, limb1: r1, limb2: r2, limb3: r3 },
        ok: p3 / 4294967296L == 0L,
    }
}

fn digit_value(value: byte) -> long {
    if value >= 48 && value <= 57 { value.to_long() - 48L }
    else if value >= 65 && value <= 70 { value.to_long() - 55L }
    else if value >= 97 && value <= 102 { value.to_long() - 87L }
    else { -1L }
}

recursive fn parse_block(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    if tables.state.block_depth >= MAX_PARSER_DEPTH {
        return err(cursor_error(tables, tokens, ParseProblemKind.BlockDepth))
    }
    tables.state.block_depth += 1L
    let open = cursor_expect(tables, tokens, TokenKind.LBrace, ParseProblemKind.ExpectedBlockOpen)?
    let first = tables.nodes.count()
    parse_block_body(source, tokens, tables, open.token, open.start, first)
}

recursive fn parse_block_body(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    open_token: long,
    open_start: long,
    first: long,
) -> Result<long, ParseError> {
    var flags = 0L
    cursor_skip_separators(tables, tokens)
    for step in 0L..MAX_TOKENS_PER_FILE {
        let current = cursor_peek(tables, tokens, 0L)
        if current.kind == TokenKind.RBrace || current.kind == TokenKind.Eof { break }
        let candidate = parse_statement_candidate(source, tokens, tables)?
        if !candidate.is_statement {
            let separated = cursor_skip_separators(tables, tokens) > 0L
            if cursor_peek(tables, tokens, 0L).kind == TokenKind.RBrace {
                flags = flags | FLAG_HAS_TAIL
                break
            }
            if !separated {
                return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedStmtSeparator))
            }
            let expression_first = node_first_child(tables.nodes, candidate.node)
            let expression_start = tables.nodes[candidate.node].start
            let expression_end = tables.nodes[candidate.node].end
            append_node(tables, NodeKind.ExpressionStatement, expression_first, -1L, expression_start, expression_end, expression_start, 0L, -1L, 0L)?
            continue
        }
        let separated = cursor_skip_separators(tables, tokens) > 0L
        if cursor_peek(tables, tokens, 0L).kind != TokenKind.RBrace && !separated {
            return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedStmtSeparator))
        }
    }
    let close = cursor_expect(tables, tokens, TokenKind.RBrace, ParseProblemKind.ExpectedBlockClose)?
    tables.state.block_depth -= 1L
    append_node(tables, NodeKind.Block, first, open_token, open_start, close.start + close.length, open_start, flags, -1L, 0L)
}

recursive fn parse_statement_candidate(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<ParseCandidate, ParseError> {
    if cursor_word_is(source, tables, tokens, "for") {
        return ok(ParseCandidate { node: parse_for_statement(source, tokens, tables)?, is_statement: true })
    }
    if cursor_word_is(source, tables, tokens, "break") || cursor_word_is(source, tables, tokens, "continue") {
        let token = cursor_next(tables, tokens)
        let kind = if token_is_word(source, tokens, token.token, tables.state.file_base, "break") { NodeKind.BreakStatement } else { NodeKind.ContinueStatement }
        let first = tables.nodes.count()
        let node = append_node(tables, kind, first, token.token, token.start, token.start + token.length, token.start, 0L, -1L, 0L)?
        return ok(ParseCandidate { node, is_statement: true })
    }
    if cursor_word_is(source, tables, tokens, "expect") {
        return ok(ParseCandidate { node: parse_expect_statement(source, tokens, tables)?, is_statement: true })
    }
    if cursor_word_is(source, tables, tokens, "discard") {
        let start = cursor_next(tables, tokens)
        let first = tables.nodes.count()
        let value = parse_expression(source, tokens, tables, 0L)?
        let end = tables.nodes[value].end
        let node = append_node(tables, NodeKind.Discard, first, start.token, start.start, end, start.start, 0L, -1L, 0L)?
        return ok(ParseCandidate { node, is_statement: true })
    }
    if cursor_peek(tables, tokens, 0L).kind == TokenKind.LBrace {
        let node = parse_block(source, tokens, tables)?
        return ok(ParseCandidate { node, is_statement: true })
    }
    if cursor_word_is(source, tables, tokens, "let") || cursor_word_is(source, tables, tokens, "var") {
        return ok(ParseCandidate { node: parse_let_statement(source, tokens, tables)?, is_statement: true })
    }
    if cursor_word_is(source, tables, tokens, "return") {
        let start = cursor_next(tables, tokens)
        let first = tables.nodes.count()
        if cursor_peek(tables, tokens, 0L).kind != TokenKind.Newline && cursor_peek(tables, tokens, 0L).kind != TokenKind.Semicolon && cursor_peek(tables, tokens, 0L).kind != TokenKind.RBrace {
            parse_expression(source, tokens, tables, 0L)?
        }
        let end = tables.state.last_end
        let node = append_node(tables, NodeKind.ReturnStatement, first, start.token, start.start, end, start.start, 0L, -1L, 0L)?
        return ok(ParseCandidate { node, is_statement: true })
    }
    parse_expression_statement_candidate(source, tokens, tables)
}

recursive fn parse_let_statement(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let mutable = cursor_word_is(source, tables, tokens, "var")
    let start = cursor_next(tables, tokens)
    let name = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedLetName)?
    let first = tables.nodes.count()
    var flags = if mutable { FLAG_MUTABLE } else { 0L }
    if cursor_take(tables, tokens, TokenKind.Colon) {
        parse_type(source, tokens, tables, NodeKind.Annotation)?
        flags = flags | FLAG_HAS_ANNOTATION
    }
    if cursor_take(tables, tokens, TokenKind.Eq) {
        parse_expression(source, tokens, tables, 0L)?
    } else if (flags & FLAG_HAS_ANNOTATION) != 0L && (cursor_peek(tables, tokens, 0L).kind == TokenKind.Newline || cursor_peek(tables, tokens, 0L).kind == TokenKind.Semicolon || cursor_peek(tables, tokens, 0L).kind == TokenKind.RBrace) {
        let annotation = tables.nodes.count() - 1L
        let annotation_end = tables.nodes[annotation].end
        let value_first = tables.nodes.count()
        append_node(tables, NodeKind.Call, value_first, -1L, annotation_end, annotation_end, annotation_end, FLAG_SYNTHETIC, -1L, 0L)?
    } else {
        return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedLetValue))
    }
    let end = tables.state.last_end
    append_node(tables, NodeKind.Let, first, name.token, start.start, end, start.start, flags, -1L, 0L)
}

recursive fn parse_expect_statement(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let start = cursor_next(tables, tokens)
    if cursor_peek(tables, tokens, 0L).kind == TokenKind.Newline || cursor_peek(tables, tokens, 0L).kind == TokenKind.Semicolon {
        return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedExpectBool))
    }
    let value_start = cursor_peek(tables, tokens, 0L).start
    let first = tables.nodes.count()
    if cursor_word_is(source, tables, tokens, "stack_peak") {
        parse_stack_peak_comparison(source, tokens, tables)?
    } else {
        parse_expression(source, tokens, tables, 0L)?
    }
    let value_end = tables.state.last_end
    let extra = tables.extra.count()
    append_extra(tables, tables.state.file_base + value_start)?
    append_extra(tables, tables.state.file_base + value_end)?
    append_node(tables, NodeKind.Expect, first, start.token, start.start, value_end, start.start, 0L, extra, 0L)
}

recursive fn parse_stack_peak_comparison(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let start = cursor_expect_word(source, tables, tokens, "stack_peak", ParseProblemKind.ExpectedStackPeakName)?
    cursor_expect(tables, tokens, TokenKind.LParen, ParseProblemKind.ExpectedStackPeakOpen)?
    let function_name = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedStackPeakName)?
    let close = cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedStackPeakClose)?
    let operator = cursor_expect(tables, tokens, TokenKind.Lt, ParseProblemKind.ExpectedStackPeakLt)?
    let number = cursor_next(tables, tokens)
    if number.kind != TokenKind.Number {
        return err(ParseError { kind: ParseProblemKind.ExpectedStackPeakBudget, offset: number.start, token: number.token })
    }
    let parsed = parse_literal(source, tables, number.token, number.start, number.length, number.start)?
    let literal = parsed.index
    let long_suffix = parsed.long_suffix
    var value = tables.literals[literal]
    var end = number.start + number.length
    let unit = cursor_peek(tables, tokens, 0L)
    let multiplier = if token_is_word(source, tokens, unit.token, tables.state.file_base, "B") { 1L }
        else if token_is_word(source, tokens, unit.token, tables.state.file_base, "KB") { 1024L }
        else if token_is_word(source, tokens, unit.token, tables.state.file_base, "MB") { 1048576L }
        else if token_is_word(source, tokens, unit.token, tables.state.file_base, "GB") { 1073741824L }
        else { 0L }
    if multiplier > 0L {
        cursor_next(tables, tokens)
        end = tables.state.last_end
        let scaled = multiply_literal(value, multiplier)
        if !scaled.ok {
            return err(ParseError { kind: ParseProblemKind.StackPeakTooLarge, offset: number.start, token: number.token })
        }
        value = scaled.value
        tables.literals[literal] = value
    }
    let call_end = close.start + close.length
    let call_first = tables.nodes.count()
    append_node(tables, NodeKind.Name, call_first, function_name.token, function_name.start, function_name.start + function_name.length, function_name.start, 0L, -1L, 0L)?
    let call = append_node(tables, NodeKind.Call, call_first, start.token, start.start, call_end, start.start, 0L, -1L, 1L)?
    tables.nodes[call].meta0 = call_end
    let integer_first = tables.nodes.count()
    let integer = append_node(tables, NodeKind.Integer, integer_first, number.token, number.start, end, number.start, if long_suffix { FLAG_LONG_SUFFIX } else { 0L }, literal, 0L)?
    let binary_first = call_first
    append_node(tables, NodeKind.Binary, binary_first, operator.token, start.start, end, operator.start, 10L, -1L, 0L)
}

recursive fn parse_expression_statement_candidate(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<ParseCandidate, ParseError> {
    let expression = parse_expression(source, tokens, tables, 0L)?
    let next = cursor_peek(tables, tokens, 0L)
    let assignment = if next.kind == TokenKind.Eq { 0L }
        else if next.kind == TokenKind.PlusEq { 1L }
        else if next.kind == TokenKind.MinusEq { 2L }
        else if next.kind == TokenKind.StarEq { 3L }
        else if next.kind == TokenKind.SlashEq { 4L }
        else if next.kind == TokenKind.PercentEq { 5L }
        else if next.kind == TokenKind.ShrEq { 6L }
        else { -1L }
    if assignment >= 0L {
        let kind = tables.nodes[expression].kind
        if kind != NodeKind.Name && kind != NodeKind.Field && kind != NodeKind.Index && kind != NodeKind.GridIndex {
            let offset = if kind == NodeKind.Unary || kind == NodeKind.Binary { tables.nodes[expression].anchor } else { tables.nodes[expression].start }
            return err(ParseError { kind: ParseProblemKind.BadAssignTarget, offset, token: tables.nodes[expression].token })
        }
        let operator = cursor_next(tables, tokens)
        let first = node_first_child(tables.nodes, expression)
        parse_expression(source, tokens, tables, 0L)?
        let assign_start = tables.nodes[expression].start
        let assign_end = tables.state.last_end
        let node = append_node(tables, NodeKind.Assign, first, operator.token, assign_start, assign_end, operator.start, assignment, -1L, 0L)?
        return ok(ParseCandidate { node, is_statement: true })
    }
    if tables.nodes[expression].kind == NodeKind.If && (tables.nodes[expression].flags & FLAG_HAS_ELSE) == 0L {
        let first = node_first_child(tables.nodes, expression)
        let start = tables.nodes[expression].start
        let end = tables.nodes[expression].end
        let statement = append_node(tables, NodeKind.ExpressionStatement, first, -1L, start, end, start, 0L, -1L, 0L)?
        return ok(ParseCandidate { node: statement, is_statement: true })
    }
    ok(ParseCandidate { node: expression, is_statement: false })
}

recursive fn parse_for_statement(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let checkpoint = tables.for_frames.count()
    var current = parse_for_header(source, tokens, tables)?
    for step in 0L..MAX_TOKENS_PER_FILE {
        if cursor_word_is(source, tables, tokens, "for") {
            match tables.for_frames.push(current) {
                ok(_) => (),
                err(Full) => return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: tables.state.last_end, token: tables.state.pos }),
            }
            current = parse_for_header(source, tokens, tables)?
        } else {
            let body = parse_block_body(source, tokens, tables, current.body_open_token, current.body_start, current.body_first)?
            let appended = append_for_node(tables, current, body)?
            var result = appended
            for unwind in 0L..tables.for_frames.count() - checkpoint {
                let parent = match tables.for_frames.pop() {
                    some(value) => value,
                    none => return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: tables.state.last_end, token: tables.state.pos }),
                }
                let parent_body = parse_block_body(source, tokens, tables, parent.body_open_token, parent.body_start, parent.body_first)?
                result = append_for_node(tables, parent, parent_body)?
            }
            return ok(result)
        }
    }
    err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: tables.state.last_end, token: tables.state.pos })
}

recursive fn parse_for_header(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<ForFrame, ParseError> {
    let start = cursor_expect_word(source, tables, tokens, "for", ParseProblemKind.ExpectedForName)?
    let name = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedForName)?
    let extra = tables.extra.count()
    var index_count = 0L
    if cursor_take(tables, tokens, TokenKind.Comma) {
        let index = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedSecondIndex)?
        append_extra(tables, index.token)?
        index_count += 1L
    }
    if cursor_take(tables, tokens, TokenKind.Comma) {
        let index = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedIndexName)?
        append_extra(tables, index.token)?
        index_count += 1L
    }
    if cursor_take(tables, tokens, TokenKind.Comma) { return err(cursor_error(tables, tokens, ParseProblemKind.TooManyForBindings)) }
    let first = tables.nodes.count()
    var flags = 0L
    if cursor_take(tables, tokens, TokenKind.Colon) {
        parse_type(source, tokens, tables, NodeKind.Annotation)?
        flags = FLAG_HAS_ANNOTATION
    }
    cursor_expect_word(source, tables, tokens, "in", ParseProblemKind.ExpectedForIn)?
    let old_allow = tables.state.allow_struct_literals
    tables.state.allow_struct_literals = false
    let collection_or_start = parse_expression(source, tokens, tables, 0L)
    tables.state.allow_struct_literals = old_allow
    let first_expr = collection_or_start?
    cursor_skip_newlines(tables, tokens)
    let inclusive = cursor_take(tables, tokens, TokenKind.RangeInclusive)
    let is_range = inclusive || cursor_take(tables, tokens, TokenKind.Range)
    if is_range {
        if index_count > 0L { return err(ParseError { kind: ParseProblemKind.RangeForBindings, offset: start.start, token: start.token }) }
        if inclusive { flags = flags | FLAG_INCLUSIVE }
        let old_allow_end = tables.state.allow_struct_literals
        tables.state.allow_struct_literals = false
        let end_expr = parse_expression(source, tokens, tables, 0L)
        tables.state.allow_struct_literals = old_allow_end
        end_expr?
        cursor_skip_newlines(tables, tokens)
    } else {
        if (flags & FLAG_HAS_ANNOTATION) != 0L { return err(ParseError { kind: ParseProblemKind.CollectionForAnnotation, offset: start.start, token: start.token }) }
    }
    if tables.state.block_depth >= MAX_PARSER_DEPTH {
        return err(cursor_error(tables, tokens, ParseProblemKind.BlockDepth))
    }
    tables.state.block_depth += 1L
    let open = cursor_expect(tables, tokens, TokenKind.LBrace, ParseProblemKind.ExpectedBlockOpen)?
    let body_first = tables.nodes.count()
    cursor_skip_separators(tables, tokens)
    ok(ForFrame { first, name_token: name.token, start: start.start, flags, extra, index_count, body_open_token: open.token, body_start: open.start, body_first, is_range })
}

fn append_for_node(tables: write ParseTables, frame: ForFrame, body: long) -> Result<long, ParseError> {
    let end = tables.nodes[body].end
    if frame.is_range {
        append_node(tables, NodeKind.For, frame.first, frame.name_token, frame.start, end, frame.start, frame.flags, -1L, 0L)
    } else {
        append_node(tables, NodeKind.ForEach, frame.first, frame.name_token, frame.start, end, frame.start, 0L, frame.extra, frame.index_count)
    }
}

recursive fn parse_expression(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    min_precedence: long,
) -> Result<long, ParseError> {
    let effective_depth = tables.state.expression_depth - tables.state.expression_depth_adjustment
    if effective_depth >= MAX_PARSER_DEPTH && expression_starts_nested(source, tokens, tables) {
        return err(cursor_error(tables, tokens, ParseProblemKind.ExpressionDepth))
    }
    let check_tree = tables.state.expression_depth == 0L
    tables.state.expression_depth += 1L
    let direct_start = cursor_peek(tables, tokens, 0L)
    let prefix = if direct_call_candidate(source, tokens, tables, direct_start) {
        let name = cursor_next(tables, tokens)
        parse_direct_call(source, tokens, tables, name)
    } else {
        parse_prefix(source, tokens, tables)
    }
    var left = match prefix {
        ok(value) => value,
        err(error) => {
            tables.state.expression_depth -= 1L
            return err(error)
        },
    }
    for step in 0L..MAX_TOKENS_PER_FILE {
        let operator = binary_info(cursor_peek(tables, tokens, 0L).kind)
        if operator.precedence < min_precedence { break }
        let pending = materialize_pending(tables, left)
        left = match pending {
            ok(value) => value,
            err(error) => {
                tables.state.expression_depth -= 1L
                return err(error)
            },
        }
        let token = cursor_next(tables, tokens)
        if operator.op == 21L && tables.state.expression_depth - tables.state.expression_depth_adjustment > MAX_PARSER_DEPTH {
            tables.state.expression_depth -= 1L
            return err(ParseError { kind: ParseProblemKind.ExpressionDepth, offset: token.start, token: token.token })
        }
        let first = node_first_child(tables.nodes, left.node)
        let next_min = if operator.op == 21L { operator.precedence } else { operator.precedence + 1L }
        let right_result = parse_expression(source, tokens, tables, next_min)
        let right = match right_result {
            ok(value) => value,
            err(error) => {
                tables.state.expression_depth -= 1L
                return err(error)
            },
        }
        let start = tables.nodes[left.node].start
        let end = tables.nodes[right].end
        let appended = append_node(tables, NodeKind.Binary, first, token.token, start, end, token.start, operator.op, -1L, 0L)
        let node = match appended {
            ok(value) => value,
            err(error) => {
                tables.state.expression_depth -= 1L
                return err(error)
            },
        }
        left = ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end }
    }
    tables.state.expression_depth -= 1L
    let node = materialize_node(tables, left)?
    tables.nodes[node].end = tables.state.last_end
    if check_tree {
        let nesting = expression_nesting_exceeded(source, tokens, tables, node)?
        match nesting {
            some(offset) => return err(ParseError { kind: ParseProblemKind.ExpressionDepth, offset, token: tables.nodes[node].token }),
            none => (),
        }
    }
    ok(node)
}

fn direct_call_candidate(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    name: CursorToken,
) -> bool {
    if name.kind != TokenKind.Ident || cursor_peek(tables, tokens, 1L).kind != TokenKind.LParen { return false }
    direct_call_name_allowed(source, tokens, tables, name)
}

fn direct_call_name_allowed(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    name: CursorToken,
) -> bool {
    !(token_is_word(source, tokens, name.token, tables.state.file_base, "true") || token_is_word(source, tokens, name.token, tables.state.file_base, "false") || token_is_word(source, tokens, name.token, tables.state.file_base, "fn") || token_is_word(source, tokens, name.token, tables.state.file_base, "break") || token_is_word(source, tokens, name.token, tables.state.file_base, "continue") || token_is_word(source, tokens, name.token, tables.state.file_base, "if") || token_is_word(source, tokens, name.token, tables.state.file_base, "match") || token_is_word(source, tokens, name.token, tables.state.file_base, "return") || token_is_word(source, tokens, name.token, tables.state.file_base, "take"))
}

recursive fn parse_direct_call(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    name: CursorToken,
) -> Result<ExprRef, ParseError> {
    let root_print = tables.state.expression_depth == 1L && token_is_word(source, tokens, name.token, tables.state.file_base, "print")
    if root_print { tables.state.expression_depth_adjustment += 1L }
    let first = tables.nodes.count()
    if !cursor_take(tables, tokens, TokenKind.LParen) {
        if root_print { tables.state.expression_depth_adjustment -= 1L }
        return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedCallOpen))
    }
    cursor_skip_newlines(tables, tokens)
    var arg_count = 0L
    if cursor_peek(tables, tokens, 0L).kind != TokenKind.RParen {
        for step in 0L..MAX_TOKENS_PER_FILE {
            let argument = parse_expression(source, tokens, tables, 0L)
            match argument {
                ok(_) => (),
                err(error) => {
                    if root_print { tables.state.expression_depth_adjustment -= 1L }
                    return err(error)
                },
            }
            arg_count += 1L
            cursor_skip_newlines(tables, tokens)
            if !cursor_take(tables, tokens, TokenKind.Comma) { break }
            cursor_skip_newlines(tables, tokens)
            if cursor_peek(tables, tokens, 0L).kind == TokenKind.RParen { break }
        }
    }
    if !cursor_take(tables, tokens, TokenKind.RParen) {
        if root_print { tables.state.expression_depth_adjustment -= 1L }
        return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedCloseParen))
    }
    if root_print { tables.state.expression_depth_adjustment -= 1L }
    let end = tables.state.last_end
    let node = append_node(tables, NodeKind.Call, first, name.token, name.start, end, name.start, 0L, -1L, arg_count)?
    tables.nodes[node].meta0 = name.start + name.length
    let call = ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: name.start, end }
    postfix_expression(source, tokens, tables, call)
}

recursive fn parse_prefix(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<ExprRef, ParseError> {
    cursor_skip_newlines(tables, tokens)
    let token = cursor_next(tables, tokens)
    if token.kind == TokenKind.Minus {
        let next = cursor_peek(tables, tokens, 0L)
        if next.kind == TokenKind.Number {
            cursor_next(tables, tokens)
            let parsed = parse_literal(source, tables, next.token, next.start, next.length, token.start)?
            let first = tables.nodes.count()
            let flags = FLAG_NEGATIVE | if parsed.long_suffix { FLAG_LONG_SUFFIX } else { 0L }
            let node = append_node(tables, NodeKind.Integer, first, next.token, token.start, next.start + next.length, token.start, flags, parsed.index, 0L)?
            return postfix_expression(source, tokens, tables, ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: token.start, end: next.start + next.length })
        }
        let value = parse_expression(source, tokens, tables, 11L)?
        let first = node_first_child(tables.nodes, value)
        let end = tables.nodes[value].end
        let node = append_node(tables, NodeKind.Unary, first, token.token, token.start, end, token.start, 0L, -1L, 0L)?
        return postfix_expression(source, tokens, tables, ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: token.start, end })
    }
    if token.kind == TokenKind.Bang {
        let value = parse_expression(source, tokens, tables, 11L)?
        let first = node_first_child(tables.nodes, value)
        let end = tables.nodes[value].end
        let node = append_node(tables, NodeKind.Unary, first, token.token, token.start, end, token.start, 1L, -1L, 0L)?
        return postfix_expression(source, tokens, tables, ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: token.start, end })
    }
    if token.kind == TokenKind.LParen {
        let expression = parse_parenthesized(source, tokens, tables, token)?
        return postfix_expression(source, tokens, tables, expression)
    }
    if token_is_word(source, tokens, token.token, tables.state.file_base, "if") {
        let expression = parse_if_expression(source, tokens, tables, token)?
        return postfix_expression(source, tokens, tables, expression)
    }
    if token_is_word(source, tokens, token.token, tables.state.file_base, "match") {
        let expression = parse_match_expression(source, tokens, tables, token)?
        return postfix_expression(source, tokens, tables, expression)
    }
    if token_is_word(source, tokens, token.token, tables.state.file_base, "return") {
        let first = tables.nodes.count()
        var flags = 0L
        let current = cursor_peek(tables, tokens, 0L)
        if current.kind != TokenKind.Newline && current.kind != TokenKind.Semicolon && current.kind != TokenKind.RBrace && current.kind != TokenKind.Comma {
            parse_expression(source, tokens, tables, 0L)?
            flags = FLAG_HAS_VALUE
        }
        let end = if (flags & FLAG_HAS_VALUE) != 0L { tables.state.last_end } else { token.start + token.length }
        let node = append_node(tables, NodeKind.Return, first, token.token, token.start, end, token.start, flags, -1L, 0L)?
        return postfix_expression(source, tokens, tables, ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: token.start, end })
    }
    if token_is_word(source, tokens, token.token, tables.state.file_base, "take") {
        let first = tables.nodes.count()
        let value = parse_expression(source, tokens, tables, 11L)?
        let end = tables.nodes[value].end
        let node = append_node(tables, NodeKind.Take, first, token.token, token.start, end, token.start, 0L, -1L, 0L)?
        return postfix_expression(source, tokens, tables, ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: token.start, end })
    }
    if token_is_word(source, tokens, token.token, tables.state.file_base, "b") {
        let string = cursor_peek(tables, tokens, 0L)
        if string.kind == TokenKind.String && string.start == token.start + 1L {
            cursor_next(tables, tokens)
            let first = tables.nodes.count()
            let node = append_node(tables, NodeKind.BytesLiteral, first, token.token, token.start, string.start + string.length, token.start, 0L, string.token, 0L)?
            return postfix_expression(source, tokens, tables, ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: token.start, end: string.start + string.length })
        }
    }
    if token.kind == TokenKind.LBracket {
        let expression = parse_array_literal(source, tokens, tables, token)?
        return postfix_expression(source, tokens, tables, expression)
    }
    if token.kind == TokenKind.Ident && cursor_peek(tables, tokens, 0L).kind == TokenKind.LParen && direct_call_name_allowed(source, tokens, tables, token) {
        return parse_direct_call(source, tokens, tables, token)
    }
    let expression = parse_prefix_leaf(source, tokens, tables, token)?
    postfix_expression(source, tokens, tables, expression)
}

recursive fn parse_prefix_leaf(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    token: CursorToken,
) -> Result<ExprRef, ParseError> {
    if token.kind == TokenKind.Number {
        let parsed = parse_literal(source, tables, token.token, token.start, token.length, token.start)?
        let first = tables.nodes.count()
        let flags = if parsed.long_suffix { FLAG_LONG_SUFFIX } else { 0L }
        let node = append_node(tables, NodeKind.Integer, first, token.token, token.start, token.start + token.length, token.start, flags, parsed.index, 0L)?
        return ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: token.start, end: token.start + token.length })
    }
    if token.kind == TokenKind.String {
        let first = tables.nodes.count()
        let high_hex = token_has_non_ascii_hex_escape(source, tables.state.file_base + token.start, token.length)
        let flags = if high_hex { FLAG_BYTESTRING_NONASCII_HEX } else { 0L }
        let node = append_node(tables, NodeKind.ByteString, first, token.token, token.start, token.start + token.length, token.start, flags, -1L, 0L)?
        return ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: token.start, end: token.start + token.length })
    }
    if token.kind == TokenKind.Ident {
        if token_is_word(source, tokens, token.token, tables.state.file_base, "true") || token_is_word(source, tokens, token.token, tables.state.file_base, "false") {
            let first = tables.nodes.count()
            let value = token_is_word(source, tokens, token.token, tables.state.file_base, "true")
            let flags = if value { FLAG_VALUE } else { 0L }
            let node = append_node(tables, NodeKind.Bool, first, token.token, token.start, token.start + token.length, token.start, flags, -1L, 0L)?
            return ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: token.start, end: token.start + token.length })
        }
        if token_is_word(source, tokens, token.token, tables.state.file_base, "fn") {
            return err(ParseError { kind: ParseProblemKind.AnonymousFunction, offset: token.start, token: token.token })
        }
        if token_is_word(source, tokens, token.token, tables.state.file_base, "break") || token_is_word(source, tokens, token.token, tables.state.file_base, "continue") {
            let first = tables.nodes.count()
            let is_break = token_is_word(source, tokens, token.token, tables.state.file_base, "break")
            let node = append_node(tables, NodeKind.LoopExit, first, token.token, token.start, token.start + token.length, token.start, if is_break { FLAG_VALUE } else { 0L }, -1L, 0L)?
            return ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: token.start, end: token.start + token.length })
        }
        return ok(ExprRef { node: -1L, pending_kind: PENDING_NAME, token: token.token, extra_token: -1L, start: token.start, end: token.start + token.length })
    }
    err(ParseError { kind: ParseProblemKind.ExpectedValue, offset: token.start, token: token.token })
}

fn token_has_non_ascii_hex_escape(source: Bytes max SOURCE_BUFFER_CAPACITY, start: long, length: long) -> bool {
    var index = 1L
    for step in 0L..length - 2L {
        if index >= length - 1L { break }
        if source[start + index] == 92 {
            if index + 3L < length - 1L && source[start + index + 1L] == 120 {
                let high = digit_value(source[start + index + 2L])
                let low = digit_value(source[start + index + 3L])
                if high * 16L + low >= 128L { return true }
                index += 4L
            } else {
                index += 2L
            }
        } else {
            index += 1L
        }
    }
    false
}

recursive fn parse_array_literal(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    open: CursorToken,
) -> Result<ExprRef, ParseError> {
    let first = tables.nodes.count()
    cursor_skip_newlines(tables, tokens)
    for step in 0L..MAX_TOKENS_PER_FILE {
        if cursor_peek(tables, tokens, 0L).kind == TokenKind.RBracket { break }
        parse_expression(source, tokens, tables, 0L)?
        cursor_skip_newlines(tables, tokens)
        if !cursor_take(tables, tokens, TokenKind.Comma) { break }
        cursor_skip_newlines(tables, tokens)
        if cursor_peek(tables, tokens, 0L).kind == TokenKind.RBracket { break }
    }
    let close = cursor_expect(tables, tokens, TokenKind.RBracket, ParseProblemKind.ExpectedArrayClose)?
    let node = append_node(tables, NodeKind.ArrayLiteral, first, open.token, open.start, close.start + close.length, open.start, 0L, -1L, 0L)?
    ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: open.start, end: close.start + close.length })
}

fn binary_info(kind: TokenKind) -> BinaryInfo {
    if kind == TokenKind.QuestionQuestion { BinaryInfo { op: 21L, precedence: 0L } }
    else if kind == TokenKind.OrOr { BinaryInfo { op: 15L, precedence: 1L } }
    else if kind == TokenKind.AndAnd { BinaryInfo { op: 14L, precedence: 2L } }
    else if kind == TokenKind.Or { BinaryInfo { op: 17L, precedence: 3L } }
    else if kind == TokenKind.Caret { BinaryInfo { op: 18L, precedence: 4L } }
    else if kind == TokenKind.And { BinaryInfo { op: 16L, precedence: 5L } }
    else if kind == TokenKind.EqEq { BinaryInfo { op: 8L, precedence: 6L } }
    else if kind == TokenKind.BangEq { BinaryInfo { op: 9L, precedence: 6L } }
    else if kind == TokenKind.Lt { BinaryInfo { op: 10L, precedence: 7L } }
    else if kind == TokenKind.Le { BinaryInfo { op: 11L, precedence: 7L } }
    else if kind == TokenKind.Gt { BinaryInfo { op: 12L, precedence: 7L } }
    else if kind == TokenKind.Ge { BinaryInfo { op: 13L, precedence: 7L } }
    else if kind == TokenKind.Shl { BinaryInfo { op: 19L, precedence: 8L } }
    else if kind == TokenKind.Shr { BinaryInfo { op: 20L, precedence: 8L } }
    else if kind == TokenKind.Plus { BinaryInfo { op: 0L, precedence: 9L } }
    else if kind == TokenKind.Minus { BinaryInfo { op: 1L, precedence: 9L } }
    else if kind == TokenKind.WrapPlus { BinaryInfo { op: 5L, precedence: 9L } }
    else if kind == TokenKind.WrapMinus { BinaryInfo { op: 6L, precedence: 9L } }
    else if kind == TokenKind.Star { BinaryInfo { op: 2L, precedence: 10L } }
    else if kind == TokenKind.Slash { BinaryInfo { op: 3L, precedence: 10L } }
    else if kind == TokenKind.Percent { BinaryInfo { op: 4L, precedence: 10L } }
    else if kind == TokenKind.WrapStar { BinaryInfo { op: 7L, precedence: 10L } }
    else { BinaryInfo { op: -1L, precedence: -1L } }
}

recursive fn postfix_expression(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    initial: ExprRef,
) -> Result<ExprRef, ParseError> {
    var expression = initial
    for step in 0L..MAX_TOKENS_PER_FILE {
        let next = cursor_peek(tables, tokens, 0L)
        if next.kind == TokenKind.LBracket {
            expression = postfix_index(source, tokens, tables, expression)?
        } else if next.kind == TokenKind.LParen {
            expression = postfix_call(source, tokens, tables, expression)?
        } else if next.kind == TokenKind.LBrace && tables.state.allow_struct_literals && can_start_struct(source, tokens, tables, expression) {
            expression = postfix_struct_literal(source, tokens, tables, expression)?
        } else if next.kind == TokenKind.Question {
            expression = postfix_try(source, tokens, tables, expression)?
        } else if next.kind == TokenKind.QuestionDot {
            expression = postfix_optional_call(source, tokens, tables, expression)?
        } else if next.kind == TokenKind.Dot {
            expression = postfix_dot(source, tokens, tables, expression)?
        } else {
            break
        }
    }
    ok(expression)
}

recursive fn postfix_index(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    expression: ExprRef,
) -> Result<ExprRef, ParseError> {
    let receiver = materialize_node(tables, expression)?
    cursor_expect(tables, tokens, TokenKind.LBracket, ParseProblemKind.ExpectedCloseBracket)?
    let first = node_first_child(tables.nodes, receiver)
    let x = parse_expression(source, tokens, tables, 0L)?
    let index_span = tables.nodes[x].start
    if cursor_take(tables, tokens, TokenKind.Comma) {
        cursor_skip_newlines(tables, tokens)
        parse_expression(source, tokens, tables, 0L)?
        let close = cursor_expect(tables, tokens, TokenKind.RBracket, ParseProblemKind.ExpectedGridClose)?
        let start = tables.nodes[receiver].start
        let receiver_token = tables.nodes[receiver].token
        let node = append_node(tables, NodeKind.GridIndex, first, receiver_token, start, close.start + close.length, index_span, 0L, -1L, 0L)?
        ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end: close.start + close.length })
    } else {
        let close = cursor_expect(tables, tokens, TokenKind.RBracket, ParseProblemKind.ExpectedIndexClose)?
        let start = tables.nodes[receiver].start
        let receiver_token = tables.nodes[receiver].token
        let node = append_node(tables, NodeKind.Index, first, receiver_token, start, close.start + close.length, index_span, 0L, -1L, 0L)?
        ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end: close.start + close.length })
    }
}

recursive fn postfix_call(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    expression: ExprRef,
) -> Result<ExprRef, ParseError> {
    var name_token = -1L
    var qualified_enum = -1L
    var qualified_case = -1L
    var call_kind = 0L
    if expression.pending_kind == PENDING_NAME {
        // Bare names stay delayed until postfix parsing decides whether this
        // is a Name, Call, QualifiedCase, or struct-literal head.
        name_token = expression.token
        call_kind = 1L
    } else if expression.node >= 0L && tables.nodes[expression.node].kind == NodeKind.Name {
        name_token = tables.nodes[expression.node].token
        // Remove the provisional Name node so its replacement Call has no
        // ghost child and the newly parsed arguments remain contiguous.
        tables.nodes.pop()
        call_kind = 1L
    } else if expression.node >= 0L && tables.nodes[expression.node].kind == NodeKind.QualifiedCase {
        let old = tables.nodes[expression.node]
        qualified_enum = old.token
        qualified_case = tables.extra[old.extra]
        let rollback = node_first_child(tables.nodes, expression.node)
        // QualifiedCase arguments are reparsed for this postfix form, so roll
        // back the whole provisional subtree before appending its replacement.
        for pop_step in 0L..tables.nodes.count() - rollback { tables.nodes.pop() }
        call_kind = 2L
    } else {
        ()
    }
    let root_print = call_kind == 1L && tables.state.expression_depth == 1L && token_is_word(source, tokens, name_token, tables.state.file_base, "print")
    if root_print { tables.state.expression_depth_adjustment += 1L }
    let first = tables.nodes.count()
    if !cursor_take(tables, tokens, TokenKind.LParen) {
        if root_print { tables.state.expression_depth_adjustment -= 1L }
        return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedCallOpen))
    }
    cursor_skip_newlines(tables, tokens)
    var arg_count = 0L
    if cursor_peek(tables, tokens, 0L).kind != TokenKind.RParen {
        for step in 0L..MAX_TOKENS_PER_FILE {
            let argument = parse_expression(source, tokens, tables, 0L)
            match argument {
                ok(_) => (),
                err(error) => {
                    if root_print { tables.state.expression_depth_adjustment -= 1L }
                    return err(error)
                },
            }
            arg_count += 1L
            cursor_skip_newlines(tables, tokens)
            if !cursor_take(tables, tokens, TokenKind.Comma) { break }
            cursor_skip_newlines(tables, tokens)
            if cursor_peek(tables, tokens, 0L).kind == TokenKind.RParen { break }
        }
    }
    if !cursor_take(tables, tokens, TokenKind.RParen) {
        if root_print { tables.state.expression_depth_adjustment -= 1L }
        return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedCloseParen))
    }
    if root_print { tables.state.expression_depth_adjustment -= 1L }
    let end = tables.state.last_end
    if call_kind == 1L {
        let node = append_node(tables, NodeKind.Call, first, name_token, expression.start, end, expression.start, 0L, -1L, arg_count)?
        tables.nodes[node].meta0 = expression.end
        ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: expression.start, end })
    } else if call_kind == 2L {
        let extra = tables.extra.count()
        append_extra(tables, qualified_case)?
        let node = append_node(tables, NodeKind.QualifiedCase, first, qualified_enum, expression.start, end, expression.start, 0L, extra, arg_count)?
        ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: expression.start, end })
    } else {
        let receiver = materialize_node(tables, expression)?
        let first = node_first_child(tables.nodes, receiver)
        // The callee is already in the node range; arguments follow it.
        let start = tables.nodes[receiver].start
        let node = append_node(tables, NodeKind.IndirectCall, first, -1L, start, end, start, 0L, -1L, arg_count)?
        ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end })
    }
}

recursive fn parse_arguments(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    cursor_expect(tables, tokens, TokenKind.LParen, ParseProblemKind.ExpectedCallOpen)?
    cursor_skip_newlines(tables, tokens)
    var count = 0L
    if cursor_peek(tables, tokens, 0L).kind != TokenKind.RParen {
        for step in 0L..MAX_TOKENS_PER_FILE {
            parse_expression(source, tokens, tables, 0L)?
            count += 1L
            cursor_skip_newlines(tables, tokens)
            if !cursor_take(tables, tokens, TokenKind.Comma) { break }
            cursor_skip_newlines(tables, tokens)
            if cursor_peek(tables, tokens, 0L).kind == TokenKind.RParen { break }
        }
    }
    cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedCloseParen)?
    ok(count)
}

fn can_start_struct(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    expression: ExprRef,
) -> bool {
    var name_token = expression.token
    if expression.node >= 0L {
        if tables.nodes[expression.node].kind != NodeKind.Name { return false }
        name_token = tables.nodes[expression.node].token
    } else if expression.pending_kind != PENDING_NAME {
        return false
    } else {
        ()
    }
    token_is_word(source, tokens, name_token, tables.state.file_base, "list") || token_is_word(source, tokens, name_token, tables.state.file_base, "pool") || token_is_word(source, tokens, name_token, tables.state.file_base, "map") || token_is_word(source, tokens, name_token, tables.state.file_base, "set") || token_is_word(source, tokens, name_token, tables.state.file_base, "queue") || token_is_word(source, tokens, name_token, tables.state.file_base, "ring") || is_upper_ascii(source[tables.state.file_base + tokens[name_token].start])
}

fn is_upper_ascii(value: byte) -> bool { value >= 65 && value <= 90 }

recursive fn postfix_struct_literal(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    expression: ExprRef,
) -> Result<ExprRef, ParseError> {
    var name_token = expression.token
    let start = expression.start
    if expression.node >= 0L {
        name_token = tables.nodes[expression.node].token
        // StructInit replaces its bare name head in the same way as Call.
        tables.nodes.pop()
    }
    let is_list = token_is_word(source, tokens, name_token, tables.state.file_base, "list")
    let is_pool = token_is_word(source, tokens, name_token, tables.state.file_base, "pool")
    let is_map = token_is_word(source, tokens, name_token, tables.state.file_base, "map")
    let is_set = token_is_word(source, tokens, name_token, tables.state.file_base, "set")
    let is_queue = token_is_word(source, tokens, name_token, tables.state.file_base, "queue")
    let is_ring = token_is_word(source, tokens, name_token, tables.state.file_base, "ring")
    let first = tables.nodes.count()
    if is_list || is_pool || is_map || is_set || is_queue || is_ring {
        cursor_expect(tables, tokens, TokenKind.LBrace, ParseProblemKind.ExpectedCollectionOpen)?
        cursor_skip_separators(tables, tokens)
        if cursor_peek(tables, tokens, 0L).kind != TokenKind.RBrace {
            let kind = if is_list { ParseProblemKind.EmptyList } else if is_pool { ParseProblemKind.EmptyPool } else if is_map { ParseProblemKind.EmptyMap } else if is_set { ParseProblemKind.EmptySet } else if is_queue { ParseProblemKind.EmptyQueue } else { ParseProblemKind.EmptyRing }
            return err(cursor_error(tables, tokens, kind))
        }
        let close_kind = if is_list { ParseProblemKind.ExpectedListClose } else if is_pool { ParseProblemKind.ExpectedPoolClose } else if is_map { ParseProblemKind.ExpectedMapClose } else if is_set { ParseProblemKind.ExpectedSetClose } else if is_queue { ParseProblemKind.ExpectedQueueClose } else { ParseProblemKind.ExpectedRingClose }
        let close = cursor_expect(tables, tokens, TokenKind.RBrace, close_kind)?
        let node_kind = if is_list { NodeKind.ListLiteral } else if is_pool { NodeKind.PoolLiteral } else if is_map { NodeKind.MapLiteral } else if is_set { NodeKind.SetLiteral } else if is_queue { NodeKind.QueueLiteral } else { NodeKind.RingLiteral }
        let node = append_node(tables, node_kind, first, name_token, start, close.start + close.length, start, 0L, -1L, 0L)?
        ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end: close.start + close.length })
    } else {
        let count = parse_struct_init_fields(source, tokens, tables)?
        let end = tables.state.last_end
        let node = append_node(tables, NodeKind.StructInit, first, name_token, start, end, start, 0L, -1L, count)?
        ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end })
    }
}

recursive fn parse_struct_init_fields(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    cursor_expect(tables, tokens, TokenKind.LBrace, ParseProblemKind.ExpectedStructLiteralOpen)?
    cursor_skip_separators(tables, tokens)
    var count = 0L
    for step in 0L..MAX_TOKENS_PER_FILE {
        let next = cursor_peek(tables, tokens, 0L)
        if next.kind == TokenKind.RBrace || next.kind == TokenKind.Eof { break }
        let name = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedStructField)?
        let field_first = tables.nodes.count()
        if cursor_take(tables, tokens, TokenKind.Colon) {
            parse_expression(source, tokens, tables, 0L)?
        } else {
            let implicit_first = tables.nodes.count()
            append_node(tables, NodeKind.Name, implicit_first, name.token, name.start, name.start + name.length, name.start, 0L, -1L, 0L)?
        }
        let value = tables.nodes.count() - 1L
        let field_end = if tables.nodes[value].end > name.start + name.length { tables.nodes[value].end } else { name.start + name.length }
        append_node(tables, NodeKind.InitializerField, field_first, name.token, name.start, field_end, name.start, 0L, -1L, 0L)?
        count += 1L
        let separated = cursor_skip_separators(tables, tokens) > 0L
        if cursor_take(tables, tokens, TokenKind.Comma) {
            cursor_skip_separators(tables, tokens)
            ()
        } else if cursor_peek(tables, tokens, 0L).kind != TokenKind.RBrace && !separated {
            return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedComma))
        } else {
            ()
        }
    }
    cursor_expect(tables, tokens, TokenKind.RBrace, ParseProblemKind.ExpectedStructLiteralClose)?
    ok(count)
}

recursive fn postfix_try(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    expression: ExprRef,
) -> Result<ExprRef, ParseError> {
    let value = materialize_node(tables, expression)?
    let first = node_first_child(tables.nodes, value)
    let question = cursor_expect(tables, tokens, TokenKind.Question, ParseProblemKind.ExpectedValue)?
    let start = tables.nodes[value].start
    let node = append_node(tables, NodeKind.Try, first, question.token, start, question.start + question.length, question.start, 0L, -1L, 0L)?
    ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end: question.start + question.length })
}

recursive fn postfix_optional_call(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    expression: ExprRef,
) -> Result<ExprRef, ParseError> {
    let receiver = materialize_node(tables, expression)?
    cursor_expect(tables, tokens, TokenKind.QuestionDot, ParseProblemKind.ExpectedOptionalName)?
    let method = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedOptionalName)?
    cursor_expect(tables, tokens, TokenKind.LParen, ParseProblemKind.ExpectedOptionalOpen)?
    let first = node_first_child(tables.nodes, receiver)
    let args_start = tables.nodes.count()
    let count = parse_arguments_after_open(source, tokens, tables)?
    let start = tables.nodes[receiver].start
    let end = tables.state.last_end
    let node = append_node(tables, NodeKind.OptionalCall, first, method.token, start, end, method.start, 0L, -1L, count + args_start * 0L)?
    ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end })
}

recursive fn parse_arguments_after_open(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    cursor_skip_newlines(tables, tokens)
    var count = 0L
    if cursor_peek(tables, tokens, 0L).kind != TokenKind.RParen {
        for step in 0L..MAX_TOKENS_PER_FILE {
            parse_expression(source, tokens, tables, 0L)?
            count += 1L
            cursor_skip_newlines(tables, tokens)
            if !cursor_take(tables, tokens, TokenKind.Comma) { break }
            cursor_skip_newlines(tables, tokens)
            if cursor_peek(tables, tokens, 0L).kind == TokenKind.RParen { break }
        }
    }
    cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedCloseParen)?
    ok(count)
}

recursive fn postfix_dot(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    expression: ExprRef,
) -> Result<ExprRef, ParseError> {
    cursor_expect(tables, tokens, TokenKind.Dot, ParseProblemKind.ExpectedMethodName)?
    let method = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedMethodName)?
    if token_is_word(source, tokens, method.token, tables.state.file_base, "fit") && cursor_take(tables, tokens, TokenKind.Lt) {
        let receiver = materialize_node(tables, expression)?
        let first = node_first_child(tables.nodes, receiver)
        parse_type(source, tokens, tables, NodeKind.FitType)?
        cursor_expect_type_gt(tables, tokens, ParseProblemKind.ExpectedFitTypeClose)?
        cursor_expect(tables, tokens, TokenKind.LParen, ParseProblemKind.ExpectedFitCall)?
        cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.FitNoArgs)?
        let start = tables.nodes[receiver].start
        let end = tables.state.last_end
        let node = append_node(tables, NodeKind.Fit, first, method.token, start, end, method.start, 0L, -1L, 0L)?
        return ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end })
    }
    let is_type_qualifier = expression_name_is_upper(source, tokens, tables, expression)
    let is_builtin = builtin_method(source, tokens, method.token, tables.state.file_base)
    if cursor_peek(tables, tokens, 0L).kind == TokenKind.LParen {
        if is_type_qualifier && !is_builtin {
            var enum_token = expression.token
            if expression.node >= 0L {
                enum_token = tables.nodes[expression.node].token
                tables.nodes.pop()
            }
            let first = tables.nodes.count()
            let count = parse_arguments(source, tokens, tables)?
            let extra = tables.extra.count()
            append_extra(tables, method.token)?
            let start = expression.start
            let end = tables.state.last_end
            let node = append_node(tables, NodeKind.QualifiedCase, first, enum_token, start, end, method.start, 0L, extra, count)?
            return ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end })
        }
        let receiver = materialize_node(tables, expression)?
        let first = node_first_child(tables.nodes, receiver)
        cursor_expect(tables, tokens, TokenKind.LParen, ParseProblemKind.ExpectedCallOpen)?
        var arg_count = 0L
        if token_is_word(source, tokens, method.token, tables.state.file_base, "slice") {
            cursor_skip_newlines(tables, tokens)
            if cursor_peek(tables, tokens, 0L).kind != TokenKind.RParen {
                parse_expression(source, tokens, tables, 0L)?
                if !cursor_take(tables, tokens, TokenKind.Range) && !cursor_take(tables, tokens, TokenKind.RangeInclusive) {
                    return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedSliceRange))
                }
                cursor_skip_newlines(tables, tokens)
                parse_expression(source, tokens, tables, 0L)?
                arg_count = 2L
            }
            cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedSliceClose)?
        } else {
            arg_count = parse_arguments_after_open(source, tokens, tables)?
        }
        let start = tables.nodes[receiver].start
        let end = tables.state.last_end
        if token_is_word(source, tokens, method.token, tables.state.file_base, "to_long") && arg_count == 0L {
            let node = append_node(tables, NodeKind.ToLong, first, method.token, start, end, method.start, 0L, -1L, 0L)?
            return ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end })
        }
        let node = append_node(tables, NodeKind.MethodCall, first, method.token, start, end, method.start, 0L, -1L, arg_count)?
        ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end })
    } else {
        let receiver = materialize_node(tables, expression)?
        let first = node_first_child(tables.nodes, receiver)
        let start = tables.nodes[receiver].start
        let end = method.start + method.length
        let node = append_node(tables, NodeKind.Field, first, method.token, start, end, method.start, 0L, -1L, 0L)?
        ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start, end })
    }
}

fn builtin_method(source: Bytes max SOURCE_BUFFER_CAPACITY, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, token: long, base: long) -> bool {
    token_is_word(source, tokens, token, base, "to_long") || token_is_word(source, tokens, token, base, "ok") || token_is_word(source, tokens, token, base, "unwrap") || token_is_word(source, tokens, token, base, "is_none") || token_is_word(source, tokens, token, base, "is_some") || token_is_word(source, tokens, token, base, "is_ok") || token_is_word(source, tokens, token, base, "is_err") || token_is_word(source, tokens, token, base, "len") || token_is_word(source, tokens, token, base, "count") || token_is_word(source, tokens, token, base, "peek") || token_is_word(source, tokens, token, base, "width") || token_is_word(source, tokens, token, base, "height") || token_is_word(source, tokens, token, base, "add") || token_is_word(source, tokens, token, base, "set") || token_is_word(source, tokens, token, base, "get") || token_is_word(source, tokens, token, base, "contains") || token_is_word(source, tokens, token, base, "push") || token_is_word(source, tokens, token, base, "pop") || token_is_word(source, tokens, token, base, "insert") || token_is_word(source, tokens, token, base, "remove") || token_is_word(source, tokens, token, base, "clear") || token_is_word(source, tokens, token, base, "empty") || token_is_word(source, tokens, token, base, "try_append")
}

fn expression_name_is_upper(source: Bytes max SOURCE_BUFFER_CAPACITY, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, tables: ParseTables, expression: ExprRef) -> bool {
    var token = expression.token
    if expression.node >= 0L {
        if tables.nodes[expression.node].kind != NodeKind.Name { return false }
        token = tables.nodes[expression.node].token
    } else if expression.pending_kind != PENDING_NAME {
        return false
    } else {
        ()
    }
    is_upper_ascii(source[tables.state.file_base + tokens[token].start])
}

recursive fn parse_parenthesized(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    open: CursorToken,
) -> Result<ExprRef, ParseError> {
    if cursor_take(tables, tokens, TokenKind.RParen) {
        let first = tables.nodes.count()
        let end = tables.state.last_end
        let node = append_node(tables, NodeKind.Unit, first, open.token, open.start, end, open.start, 0L, -1L, 0L)?
        return ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: open.start, end })
    }
    if is_cast_start(source, tokens, tables) {
        return parse_cast_expression(source, tokens, tables, open)
    }
    if tables.state.parenthesis_depth >= MAX_PARSER_DEPTH {
        return err(ParseError { kind: ParseProblemKind.ExpressionDepth, offset: open.start, token: open.token })
    }
    tables.state.parenthesis_depth += 1L
    let old_allow = tables.state.allow_struct_literals
    tables.state.allow_struct_literals = true
    let parsed = parse_expression(source, tokens, tables, 0L)
    tables.state.allow_struct_literals = old_allow
    let inner = parsed?
    let close = cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedCloseParen)?
    tables.state.parenthesis_depth -= 1L
    tables.nodes[inner].start = open.start
    tables.nodes[inner].end = close.start + close.length
    ok(ExprRef { node: inner, pending_kind: 0L, token: -1L, extra_token: -1L, start: open.start, end: close.start + close.length })
}

fn is_cast_start(source: Bytes max SOURCE_BUFFER_CAPACITY, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, tables: ParseTables) -> bool {
    let first = cursor_peek(tables, tokens, 0L)
    let second = cursor_peek(tables, tokens, 1L)
    let simple = token_is_word(source, tokens, first.token, tables.state.file_base, "int") || token_is_word(source, tokens, first.token, tables.state.file_base, "long") || token_is_word(source, tokens, first.token, tables.state.file_base, "bool")
    let ascii_max = token_is_word(source, tokens, first.token, tables.state.file_base, "Ascii") && token_is_word(source, tokens, second.token, tables.state.file_base, "max")
    let uppercase = first.kind == TokenKind.Ident && is_upper_ascii(source[tables.state.file_base + first.start])
    (simple && second.kind == TokenKind.RParen) || (uppercase && (second.kind == TokenKind.RParen || ascii_max))
}

recursive fn parse_cast_expression(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    open: CursorToken,
) -> Result<ExprRef, ParseError> {
    if tables.state.cast_depth >= MAX_PARSER_DEPTH {
        return err(ParseError { kind: ParseProblemKind.CastDepth, offset: open.start, token: open.token })
    }
    tables.state.cast_depth += 1L
    let first = tables.nodes.count()
    let parsed = parse_type(source, tokens, tables, NodeKind.CastType)
    let ty = parsed?
    cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedCloseParen)?
    cursor_skip_newlines(tables, tokens)
    let value = parse_prefix(source, tokens, tables)?
    let value_node = materialize_node(tables, value)?
    let end = tables.nodes[value_node].end
    let node = append_node(tables, NodeKind.Cast, first, open.token, open.start, end, open.start, 0L, -1L, 0L)?
    tables.state.cast_depth -= 1L
    ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: open.start, end })
}

recursive fn parse_match_expression(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    start: CursorToken,
) -> Result<ExprRef, ParseError> {
    let old_allow = tables.state.allow_struct_literals
    tables.state.allow_struct_literals = false
    let parsed_scrutinee = parse_expression(source, tokens, tables, 0L)
    tables.state.allow_struct_literals = old_allow
    let scrutinee = parsed_scrutinee?
    parse_match_after_scrutinee(source, tokens, tables, start, scrutinee)
}

fn match_expression_ends_arm(source: Bytes max SOURCE_BUFFER_CAPACITY, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, tables: ParseTables) -> bool {
    var braces = 0L
    for offset in 0L..MAX_TOKENS_PER_FILE {
        let token = cursor_peek(tables, tokens, offset)
        if token.kind == TokenKind.LBrace {
            braces += 1L
        } else if token.kind == TokenKind.RBrace {
            braces -= 1L
            if braces == 0L {
                let following = cursor_peek(tables, tokens, offset + 1L).kind
                return following == TokenKind.Comma || following == TokenKind.Newline || following == TokenKind.Semicolon || following == TokenKind.RBrace || following == TokenKind.Eof
            }
        } else if token.kind == TokenKind.Eof {
            break
        } else {
            ()
        }
    }
    false
}

recursive fn parse_match_after_scrutinee(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    start: CursorToken,
    scrutinee: long,
) -> Result<ExprRef, ParseError> {
    let checkpoint = tables.match_frames.count()
    cursor_skip_newlines(tables, tokens)
    cursor_expect(tables, tokens, TokenKind.LBrace, ParseProblemKind.ExpectedMatchOpen)?
    let frame = MatchFrame { match_token: start.token, match_start: start.start, scrutinee, first: node_first_child(tables.nodes, scrutinee), arm_count: 0L, waiting_pattern: -1L, waiting_arm_start: -1L }
    match tables.match_frames.push(frame) {
        ok(_) => (),
        err(Full) => return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: start.start, token: start.token }),
    }
    cursor_skip_separators(tables, tokens)
    for step in 0L..MAX_TOKENS_PER_FILE {
        let top = tables.match_frames.count() - 1L
        let current = tables.match_frames[top]
        if cursor_peek(tables, tokens, 0L).kind == TokenKind.RBrace || cursor_peek(tables, tokens, 0L).kind == TokenKind.Eof {
            let close = cursor_expect(tables, tokens, TokenKind.RBrace, ParseProblemKind.ExpectedMatchClose)?
            let popped = match tables.match_frames.pop() {
                some(value) => value,
                none => return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: close.start, token: close.token }),
            }
            let end = close.start + close.length
            let node = append_node(tables, NodeKind.Match, popped.first, popped.match_token, popped.match_start, end, popped.match_start, 0L, -1L, popped.arm_count)?
            if tables.match_frames.count() == checkpoint {
                return ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: popped.match_start, end })
            }
            let parent_index = tables.match_frames.count() - 1L
            var parent = tables.match_frames[parent_index]
            if parent.waiting_pattern < 0L {
                return ok(ExprRef { node, pending_kind: 0L, token: -1L, extra_token: -1L, start: popped.match_start, end })
            }
            let synthetic_block = append_node(tables, NodeKind.Block, node_first_child(tables.nodes, node), -1L, popped.match_start, end, popped.match_start, FLAG_SYNTHETIC | FLAG_HAS_TAIL, -1L, 0L)?
            let arm_first = node_first_child(tables.nodes, parent.waiting_pattern)
            append_node(tables, NodeKind.MatchArm, arm_first, -1L, parent.waiting_arm_start, end, parent.waiting_arm_start, 0L, -1L, 0L)?
            parent.arm_count += 1L
            parent.waiting_pattern = -1L
            parent.waiting_arm_start = -1L
            tables.match_frames[parent_index] = parent
            let separated = cursor_skip_separators(tables, tokens) > 0L
            if cursor_take(tables, tokens, TokenKind.Comma) {
                cursor_skip_separators(tables, tokens)
                ()
            } else if cursor_peek(tables, tokens, 0L).kind != TokenKind.RBrace && !separated {
                return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedMatchSeparator))
            } else {
                ()
            }
            continue
        }
        let arm_start = cursor_peek(tables, tokens, 0L)
        let pattern = parse_pattern(source, tokens, tables)?
        cursor_expect(tables, tokens, TokenKind.FatArrow, ParseProblemKind.ExpectedMatchArrow)?
        cursor_skip_newlines(tables, tokens)
        if cursor_peek(tables, tokens, 0L).kind == TokenKind.LBrace {
            parse_block(source, tokens, tables)?
        } else if cursor_word_is(source, tables, tokens, "match") && match_expression_ends_arm(source, tokens, tables) {
            var parent = tables.match_frames[top]
            parent.waiting_pattern = pattern
            parent.waiting_arm_start = arm_start.start
            tables.match_frames[top] = parent
            let nested_start = cursor_next(tables, tokens)
            let old_allow = tables.state.allow_struct_literals
            tables.state.allow_struct_literals = false
            let parsed_nested = parse_expression(source, tokens, tables, 0L)
            tables.state.allow_struct_literals = old_allow
            let nested_scrutinee = parsed_nested?
            cursor_skip_newlines(tables, tokens)
            cursor_expect(tables, tokens, TokenKind.LBrace, ParseProblemKind.ExpectedMatchOpen)?
            let nested = MatchFrame { match_token: nested_start.token, match_start: nested_start.start, scrutinee: nested_scrutinee, first: node_first_child(tables.nodes, nested_scrutinee), arm_count: 0L, waiting_pattern: -1L, waiting_arm_start: -1L }
            match tables.match_frames.push(nested) {
                ok(_) => (),
                err(Full) => return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: nested_start.start, token: nested_start.token }),
            }
            cursor_skip_separators(tables, tokens)
            continue
        } else {
            let expression = parse_expression(source, tokens, tables, 0L)?
            let expr_start = tables.nodes[expression].start
            let expr_end = tables.nodes[expression].end
            append_node(tables, NodeKind.Block, node_first_child(tables.nodes, expression), -1L, expr_start, expr_end, expr_start, FLAG_SYNTHETIC | FLAG_HAS_TAIL, -1L, 0L)?
        }
        let arm_first = node_first_child(tables.nodes, pattern)
        let arm_end = tables.state.last_end
        append_node(tables, NodeKind.MatchArm, arm_first, -1L, arm_start.start, arm_end, arm_start.start, 0L, -1L, 0L)?
        let updated = tables.match_frames[top]
        tables.match_frames[top] = MatchFrame { match_token: updated.match_token, match_start: updated.match_start, scrutinee: updated.scrutinee, first: updated.first, arm_count: updated.arm_count + 1L, waiting_pattern: updated.waiting_pattern, waiting_arm_start: updated.waiting_arm_start }
        let separated = cursor_skip_separators(tables, tokens) > 0L
        if cursor_take(tables, tokens, TokenKind.Comma) {
            cursor_skip_separators(tables, tokens)
            ()
        } else if cursor_peek(tables, tokens, 0L).kind != TokenKind.RBrace && !separated {
            return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedMatchSeparator))
        } else {
            ()
        }
    }
    err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: tables.nodes[scrutinee].start, token: tables.nodes[scrutinee].token })
}

recursive fn parse_pattern(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<long, ParseError> {
    let token = cursor_next(tables, tokens)
    if token.kind == TokenKind.Number {
        let parsed = parse_literal(source, tables, token.token, token.start, token.length, token.start)?
        let first = tables.nodes.count()
        let flags = if parsed.long_suffix { FLAG_LONG_SUFFIX } else { 0L }
        return append_node(tables, NodeKind.Integer, first, token.token, token.start, token.start + token.length, token.start, flags, parsed.index, 0L)
    }
    if token.kind == TokenKind.Minus {
        let number = cursor_peek(tables, tokens, 0L)
        if number.kind != TokenKind.Number { return err(ParseError { kind: ParseProblemKind.ExpectedPatternNumber, offset: token.start, token: token.token }) }
        cursor_next(tables, tokens)
        let parsed = parse_literal(source, tables, number.token, number.start, number.length, token.start)?
        let first = tables.nodes.count()
        let flags = FLAG_NEGATIVE | if parsed.long_suffix { FLAG_LONG_SUFFIX } else { 0L }
        return append_node(tables, NodeKind.Integer, first, number.token, token.start, number.start + number.length, token.start, flags, parsed.index, 0L)
    }
    if token.kind != TokenKind.Ident { return err(ParseError { kind: ParseProblemKind.ExpectedPattern, offset: token.start, token: token.token }) }
    if token_is_word(source, tokens, token.token, tables.state.file_base, "_") {
        let first = tables.nodes.count()
        return append_node(tables, NodeKind.WildcardPattern, first, token.token, token.start, token.start + token.length, token.start, 0L, -1L, 0L)
    }
    if token_is_word(source, tokens, token.token, tables.state.file_base, "true") || token_is_word(source, tokens, token.token, tables.state.file_base, "false") {
        let first = tables.nodes.count()
        let flags = if token_is_word(source, tokens, token.token, tables.state.file_base, "true") { FLAG_VALUE } else { 0L }
        return append_node(tables, NodeKind.BoolPattern, first, token.token, token.start, token.start + token.length, token.start, flags, -1L, 0L)
    }
    var enum_token = -1L
    var case_token = token.token
    let pattern_start = token.start
    if cursor_take(tables, tokens, TokenKind.Dot) {
        enum_token = token.token
        let case = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedPatternEnumCase)?
        case_token = case.token
    }
    let first = tables.nodes.count()
    var binding_count = 0L
    if cursor_take(tables, tokens, TokenKind.LParen) {
        cursor_skip_newlines(tables, tokens)
        if cursor_peek(tables, tokens, 0L).kind != TokenKind.RParen {
            for step in 0L..MAX_TOKENS_PER_FILE {
                let binding = cursor_expect(tables, tokens, TokenKind.Ident, ParseProblemKind.ExpectedPatternBinding)?
                let kind = if token_is_word(source, tokens, binding.token, tables.state.file_base, "_") { NodeKind.IgnoredPatternBinding } else { NodeKind.PatternBinding }
                let bind_first = tables.nodes.count()
                append_node(tables, kind, bind_first, binding.token, binding.start, binding.start + binding.length, binding.start, 0L, -1L, 0L)?
                binding_count += 1L
                cursor_skip_newlines(tables, tokens)
                if !cursor_take(tables, tokens, TokenKind.Comma) { break }
                cursor_skip_newlines(tables, tokens)
                if cursor_peek(tables, tokens, 0L).kind == TokenKind.RParen { break }
            }
        }
        cursor_expect(tables, tokens, TokenKind.RParen, ParseProblemKind.ExpectedPatternClose)?
    }
    let extra = if enum_token >= 0L { enum_token } else { -1L }
    let flags = if enum_token >= 0L { FLAG_HAS_ANNOTATION } else { 0L }
    let end = tables.state.last_end
    append_node(tables, NodeKind.CasePattern, first, case_token, pattern_start, end, pattern_start, flags, extra, binding_count)
}

recursive fn parse_if_expression(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    initial_if: CursorToken,
) -> Result<ExprRef, ParseError> {
    let old_allow = tables.state.allow_struct_literals
    tables.state.allow_struct_literals = false
    let parsed_condition = parse_expression(source, tokens, tables, 0L)
    tables.state.allow_struct_literals = old_allow
    let condition = parsed_condition?
    parse_if_after_condition(source, tokens, tables, initial_if, condition)
}

recursive fn parse_if_after_condition(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
    initial_if: CursorToken,
    initial_condition: long,
) -> Result<ExprRef, ParseError> {
    let frame_checkpoint = tables.if_frames.count()
    var current_if = initial_if
    var condition = initial_condition
    var clause_count = 1L
    var expression = -1L
    for clause_step in 0L..MAX_PARSER_DEPTH {
        let then_block = parse_block(source, tokens, tables)?
        let saved_pos = tables.state.pos
        let saved_split_count = tables.state.split_count
        let saved_split_index = tables.state.split_index
        let saved_last_end = tables.state.last_end
        cursor_skip_newlines(tables, tokens)
        var else_block = -1L
        var has_else = false
        if cursor_word_is(source, tables, tokens, "else") {
            cursor_next(tables, tokens)
            cursor_skip_newlines(tables, tokens)
            if cursor_peek(tables, tokens, 0L).kind == TokenKind.LBrace {
                else_block = parse_block(source, tokens, tables)?
                has_else = true
            } else if cursor_word_is(source, tables, tokens, "if") {
                let next_if = cursor_peek(tables, tokens, 0L)
                if clause_count >= MAX_PARSER_DEPTH {
                    return err(ParseError { kind: ParseProblemKind.ExpressionDepth, offset: next_if.start, token: next_if.token })
                }
                let frame = IfFrame { condition, then_block, token: current_if.token, start: current_if.start, end: tables.nodes[then_block].end }
                match tables.if_frames.push(frame) {
                    ok(_) => (),
                    err(Full) => return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: next_if.start, token: next_if.token }),
                }
                clause_count += 1L
                current_if = cursor_next(tables, tokens)
                let old_allow = tables.state.allow_struct_literals
                tables.state.allow_struct_literals = false
                let parsed_condition = parse_expression(source, tokens, tables, 0L)
                tables.state.allow_struct_literals = old_allow
                condition = parsed_condition?
                continue
            } else {
                return err(cursor_error(tables, tokens, ParseProblemKind.ExpectedIfBlockOrIf))
            }
        } else {
            tables.state.pos = saved_pos
            tables.state.split_count = saved_split_count
            tables.state.split_index = saved_split_index
            tables.state.last_end = saved_last_end
        }
        let first = node_first_child(tables.nodes, condition)
        let flags = if has_else { FLAG_HAS_ELSE } else { 0L }
        let end = if has_else { tables.nodes[else_block].end } else { tables.nodes[then_block].end }
        expression = append_node(tables, NodeKind.If, first, current_if.token, current_if.start, end, current_if.start, flags, -1L, 0L)?
        break
    }
    for unwind in 0L..tables.if_frames.count() - frame_checkpoint {
        let frame = match tables.if_frames.pop() {
            some(value) => value,
            none => return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: tables.state.last_end, token: tables.state.pos }),
        }
        let nested_start = tables.nodes[expression].start
        let nested_end = tables.nodes[expression].end
        let synthetic_block = append_node(tables, NodeKind.Block, node_first_child(tables.nodes, expression), -1L, nested_start, nested_end, nested_start, FLAG_SYNTHETIC | FLAG_HAS_TAIL, -1L, 0L)?
        let first = node_first_child(tables.nodes, frame.condition)
        expression = append_node(tables, NodeKind.If, first, frame.token, frame.start, nested_end, frame.start, FLAG_HAS_ELSE, -1L, 0L)?
    }
    ok(ExprRef { node: expression, pending_kind: 0L, token: -1L, extra_token: -1L, start: tables.nodes[expression].start, end: tables.nodes[expression].end })
}

fn expression_has_postfix(tables: ParseTables, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, offset: long, allow_struct: bool) -> bool {
    let kind = cursor_peek(tables, tokens, offset).kind
    kind == TokenKind.LParen || kind == TokenKind.LBracket || kind == TokenKind.Question || kind == TokenKind.QuestionDot || kind == TokenKind.Dot || (allow_struct && kind == TokenKind.LBrace)
}

fn expression_starts_nested(source: Bytes max SOURCE_BUFFER_CAPACITY, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, tables: ParseTables) -> bool {
    let token = cursor_peek(tables, tokens, 0L)
    if token.kind == TokenKind.Bang { return true }
    if token.kind == TokenKind.LParen { return cursor_peek(tables, tokens, 1L).kind != TokenKind.RParen }
    if token.kind == TokenKind.Minus {
        if cursor_peek(tables, tokens, 1L).kind == TokenKind.Number { return expression_has_postfix(tables, tokens, 2L, false) }
        return true
    }
    if token.kind == TokenKind.Ident {
        if token_is_word(source, tokens, token.token, tables.state.file_base, "if") || token_is_word(source, tokens, token.token, tables.state.file_base, "match") || token_is_word(source, tokens, token.token, tables.state.file_base, "return") || token_is_word(source, tokens, token.token, tables.state.file_base, "take") { return true }
        if is_upper_ascii(source[tables.state.file_base + token.start]) { return expression_has_postfix(tables, tokens, 1L, true) }
        let byte_string = token_is_word(source, tokens, token.token, tables.state.file_base, "b") && cursor_peek(tables, tokens, 1L).kind == TokenKind.String
        return expression_has_postfix(tables, tokens, if byte_string { 2L } else { 1L }, false)
    }
    if token.kind == TokenKind.Number || token.kind == TokenKind.String {
        return expression_has_postfix(tables, tokens, 1L, false)
    }
    token.kind == TokenKind.LBracket
}

fn push_nesting_task(tables: write ParseTables, node: long, depth: long, role: long) -> Result<(), ParseError> {
    if node < tables.file_first_node || node >= tables.nodes.count() {
        return err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: tables.state.last_end, token: node })
    }
    let task = NestTask { node, depth, role }
    match tables.nesting.push(task) {
        ok(_) => ok(()),
        err(Full) => err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: tables.state.last_end, token: tables.state.pos }),
    }
}

fn expression_nesting_exceeded(source: Bytes max SOURCE_BUFFER_CAPACITY, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, tables: write ParseTables, root: long) -> Result<Option<long>, ParseError> {
    tables.nesting.clear()
    let root_depth = if tables.nodes[root].kind == NodeKind.Call && token_is_word_from_node(source, tokens, tables, root, "print") { 0L } else { 1L }
    push_nesting_task(tables, root, root_depth, NEST_EXPR)?
    for step in 0L..NESTING_TASK_CAPACITY {
        let task = match tables.nesting.pop() { some(value) => value, none => return ok(none) }
        let node = task.node
        if task.role == NEST_EXPR {
            let nested = expression_node_is_nested(tables.nodes[node].kind)
            if nested && task.depth > MAX_PARSER_DEPTH { return ok(some(expression_node_anchor(tables.nodes[node]))) }
            let child_depth = task.depth + if nested { 1L } else { 0L }
            push_expr_walk_children(tables, node, child_depth, task.depth)?
        } else if task.role == NEST_BLOCK {
            push_block_walk_children(tables, node, task.depth + 1L)?
        } else {
            push_type_walk_children(tables, node, task.depth + 1L)?
        }
    }
    err(ParseError { kind: ParseProblemKind.InternalCapacity, offset: tables.nodes[root].start, token: tables.nodes[root].token })
}

fn token_is_word_from_node(source: Bytes max SOURCE_BUFFER_CAPACITY, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, tables: ParseTables, node: long, expected: Ascii max 96) -> bool {
    let token = tables.nodes[node].token
    token >= 0L && token_is_word(source, tokens, token, tables.state.file_base, expected)
}

fn expression_node_is_nested(kind: NodeKind) -> bool {
    kind == NodeKind.Call || kind == NodeKind.IndirectCall || kind == NodeKind.QualifiedCase || kind == NodeKind.MethodCall || kind == NodeKind.Index || kind == NodeKind.OptionalCall || kind == NodeKind.Field || kind == NodeKind.StructInit || kind == NodeKind.ArrayLiteral || kind == NodeKind.GridIndex || kind == NodeKind.Fit || kind == NodeKind.Try || kind == NodeKind.Return || kind == NodeKind.Match || kind == NodeKind.ToLong || kind == NodeKind.Cast || kind == NodeKind.Take || kind == NodeKind.Unary || kind == NodeKind.Binary || kind == NodeKind.If
}

fn expression_node_anchor(node: Node) -> long {
    if node.kind == NodeKind.Unary || node.kind == NodeKind.Binary { node.anchor } else { node.start }
}

fn collect_children(tables: write ParseTables, node: long) -> long {
    tables.child_scratch.clear()
    let first = node_first_child(tables.nodes, node)
    var child = node - 1L
    for step in 0L..tables.nodes[node].subtree {
        if child < first { break }
        tables.child_scratch.push(child).unwrap()
        child -= tables.nodes[child].subtree
    }
    tables.child_scratch.count()
}

fn collect_children2(tables: write ParseTables, node: long) -> long {
    tables.child_scratch2.clear()
    let first = node_first_child(tables.nodes, node)
    var child = node - 1L
    for step in 0L..tables.nodes[node].subtree {
        if child < first { break }
        tables.child_scratch2.push(child).unwrap()
        child -= tables.nodes[child].subtree
    }
    tables.child_scratch2.count()
}

fn push_expr_walk_children(tables: write ParseTables, node: long, child_depth: long, block_depth: long) -> Result<(), ParseError> {
    let kind = tables.nodes[node].kind
    let count = collect_children(tables, node)
    if kind == NodeKind.Call || kind == NodeKind.QualifiedCase || kind == NodeKind.IndirectCall || kind == NodeKind.MethodCall || kind == NodeKind.OptionalCall || kind == NodeKind.Index || kind == NodeKind.GridIndex || kind == NodeKind.Field || kind == NodeKind.ArrayLiteral || kind == NodeKind.Binary || kind == NodeKind.Unary || kind == NodeKind.Try || kind == NodeKind.Take || kind == NodeKind.ToLong || kind == NodeKind.Return {
        for index in 0L..count {
            let child = tables.child_scratch[count - index - 1L]
            push_nesting_task(tables, child, child_depth, if is_type_node(tables.nodes[child].kind) { NEST_TYPE } else { NEST_EXPR })?
        }
    } else if kind == NodeKind.StructInit {
        for index in 0L..count {
            let child = tables.child_scratch[count - index - 1L]
            let value = node_first_direct_child(tables.nodes, child)
            push_nesting_task(tables, value, child_depth, NEST_EXPR)?
        }
    } else if kind == NodeKind.Fit || kind == NodeKind.Cast {
        var value = -1L
        var type = -1L
        for index in 0L..count {
            let child = tables.child_scratch[count - index - 1L]
            if is_type_node(tables.nodes[child].kind) { type = child } else { value = child }
        }
        if value >= 0L { push_nesting_task(tables, value, child_depth, NEST_EXPR)? }
        if type >= 0L { push_nesting_task(tables, type, child_depth, NEST_TYPE)? }
    } else if kind == NodeKind.Match {
        if count > 0L {
            let scrutinee = tables.child_scratch[count - 1L]
            push_nesting_task(tables, scrutinee, child_depth, NEST_EXPR)?
        }
        for index in 1L..count {
            let arm = tables.child_scratch[count - index - 1L]
            let body = arm - 1L
            push_nesting_task(tables, body, block_depth, NEST_BLOCK)?
        }
    } else if kind == NodeKind.If {
        for index in 0L..count {
            let child = tables.child_scratch[count - index - 1L]
            if index == 0L { push_nesting_task(tables, child, child_depth, NEST_EXPR)? }
            else { push_nesting_task(tables, child, block_depth, NEST_BLOCK)? }
        }
    } else {
        ()
    }
    ok(())
}

fn push_block_walk_children(tables: write ParseTables, node: long, child_depth: long) -> Result<(), ParseError> {
    let count = collect_children(tables, node)
    let has_tail = (tables.nodes[node].flags & FLAG_HAS_TAIL) != 0L
    if has_tail && count > 0L {
        let tail = tables.child_scratch[0L]
        push_nesting_task(tables, tail, child_depth, NEST_EXPR)?
    }
    let statement_count = count - if has_tail { 1L } else { 0L }
    for index in 0L..statement_count {
        let child = tables.child_scratch[count - index - 1L]
        let kind = tables.nodes[child].kind
        if kind == NodeKind.Let {
            var annotation = -1L
            var value = -1L
            let subcount = collect_children2(tables, child)
            for inner_index in 0L..subcount {
                let sub = tables.child_scratch2[subcount - inner_index - 1L]
                if tables.nodes[sub].kind == NodeKind.Annotation { annotation = sub } else { value = sub }
            }
            if value >= 0L { push_nesting_task(tables, value, child_depth, NEST_EXPR)? }
            if annotation >= 0L { push_nesting_task(tables, annotation, child_depth, NEST_TYPE)? }
        } else if kind == NodeKind.Assign {
            let subcount = collect_children2(tables, child)
            let target = tables.child_scratch2[subcount - 1L]
            let value = tables.child_scratch2[subcount - 2L]
            push_nesting_task(tables, target, child_depth, NEST_EXPR)?
            push_nesting_task(tables, value, child_depth, NEST_EXPR)?
        } else if kind == NodeKind.ReturnStatement || kind == NodeKind.ExpressionStatement || kind == NodeKind.Discard || kind == NodeKind.Expect {
            let subcount = collect_children2(tables, child)
            if subcount > 0L {
                let expression = tables.child_scratch2[subcount - 1L]
                push_nesting_task(tables, expression, child_depth, NEST_EXPR)?
            }
        } else if kind == NodeKind.For {
            var annotation = -1L
            var start = -1L
            var end = -1L
            var body = -1L
            let subcount = collect_children2(tables, child)
            var order = 0L
            for inner_index in 0L..subcount {
                let sub = tables.child_scratch2[subcount - inner_index - 1L]
                if tables.nodes[sub].kind == NodeKind.Annotation { annotation = sub }
                else if order == 0L { start = sub; order += 1L }
                else if order == 1L { end = sub; order += 1L }
                else { body = sub }
            }
            if start >= 0L { push_nesting_task(tables, start, child_depth, NEST_EXPR)? }
            if end >= 0L { push_nesting_task(tables, end, child_depth, NEST_EXPR)? }
            if body >= 0L { push_nesting_task(tables, body, child_depth, NEST_BLOCK)? }
            if annotation >= 0L { push_nesting_task(tables, annotation, child_depth, NEST_TYPE)? }
        } else if kind == NodeKind.ForEach {
            let subcount = collect_children2(tables, child)
            let collection = tables.child_scratch2[subcount - 1L]
            let body = tables.child_scratch2[subcount - 2L]
            push_nesting_task(tables, collection, child_depth, NEST_EXPR)?
            push_nesting_task(tables, body, child_depth, NEST_BLOCK)?
        } else if kind == NodeKind.Block {
            push_nesting_task(tables, child, child_depth, NEST_BLOCK)?
        } else {
            ()
        }
    }
    ok(())
}

fn push_type_walk_children(tables: write ParseTables, node: long, child_depth: long) -> Result<(), ParseError> {
    let count = collect_children(tables, node)
    // Rust visits all AST type arguments before constant and array arguments.
    for index in 0L..count {
        let child = tables.child_scratch[count - index - 1L]
        if tables.nodes[child].kind == NodeKind.TypeArgument {
            push_nesting_task(tables, child, child_depth, NEST_TYPE)?
        }
    }
    for index in 0L..count {
        let child = tables.child_scratch[count - index - 1L]
        let kind = tables.nodes[child].kind
        if !is_type_node(kind) && kind != NodeKind.FunctionType && kind != NodeKind.FunctionTypeParameter && kind != NodeKind.Effect {
            push_nesting_task(tables, child, child_depth, NEST_EXPR)?
        }
    }
    for index in 0L..count {
        let child = tables.child_scratch[count - index - 1L]
        if tables.nodes[child].kind == NodeKind.FunctionType {
            let param_count = collect_children2(tables, child)
            for param_index in 0L..param_count {
                let param = tables.child_scratch2[param_count - param_index - 1L]
                if tables.nodes[param].kind == NodeKind.FunctionTypeParameter {
                    let param_type = node_first_direct_child(tables.nodes, param)
                    push_nesting_task(tables, param_type, child_depth, NEST_TYPE)?
                } else if tables.nodes[param].kind == NodeKind.ResultType {
                    push_nesting_task(tables, param, child_depth, NEST_TYPE)?
                } else {
                    ()
                }
            }
        }
    }
    ok(())
}

fn is_type_node(kind: NodeKind) -> bool {
    kind == NodeKind.ParameterType || kind == NodeKind.ResultType || kind == NodeKind.Annotation || kind == NodeKind.FieldType || kind == NodeKind.PayloadType || kind == NodeKind.AliasedType || kind == NodeKind.DeclaredType || kind == NodeKind.TypeArgument || kind == NodeKind.FitType || kind == NodeKind.CastType
}
