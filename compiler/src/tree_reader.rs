//! Reader for the self-hosted parser's versioned postorder AST wire format.
//!
//! The reader first checks every extent and tree invariant. It then constructs
//! AST values in node order, so no source parse or recursive tree walk is used.

use crate::ast::*;
use crate::lexer::{Token, TokenKind};

const MAGIC: &[u8; 8] = b"NLASTB01";
const VERSION: u32 = 1;
const HEADER_BYTES: usize = 72;
const FILE_RECORD_BYTES: usize = 64;
const TOKEN_RECORD_BYTES: usize = 24;
const NODE_RECORD_BYTES: usize = 80;
const MAX_FILES: usize = 4096;
const MAX_SOURCE_BYTES: usize = 256 * 1024 * 1024;
const MAX_TOKENS: usize = 5_000_000;
const MAX_NODES: usize = 4_000_000;
const MAX_EXTRAS: usize = 8_000_000;
const MAX_LITERALS: usize = 4_000_000;
const MAX_NAME_BYTES: usize = 1_048_576;
const MAX_WIRE_BYTES: usize = 1024 * 1024 * 1024;
const MAX_TREE_DEPTH: usize = 4096;
const MAX_PARSE_WORK: usize = 300_000_000;

// Node flags mirror selfhost/parser.nl. A wire version changes when these
// records or the parser's node meanings change.
const F_VALUE: u32 = 1;
const F_MUTABLE: u32 = 2;
const F_RECURSIVE: u32 = 4;
const F_INCLUSIVE: u32 = 8;
const F_PREFAULT: u32 = 16;
const F_NEGATIVE: u32 = 32;
const F_LONG_SUFFIX: u32 = 64;
const F_MODE_WRITE: u32 = 128;
const F_MODE_GROW: u32 = 256;
const F_SYNTHETIC: u32 = 512;
const F_POLICY_WRAP: u32 = 1024;
const F_POLICY_CLAMP: u32 = 2048;
const F_RANGE: u32 = 4096;
const F_RANGE_INCLUSIVE: u32 = 8192;
const F_HAS_ANNOTATION: u32 = 16384;
const F_HAS_TAIL: u32 = 32768;
const F_HAS_ELSE: u32 = 65536;
const F_HAS_VALUE: u32 = 131072;
const F_TYPE_FN: u32 = 262144;
const F_TYPE_UNIT: u32 = 524288;
const F_TYPE_TEXT_BYTES: u32 = 1_048_576;
const F_EFFECT_WRITES: u32 = 2_097_152;
const F_BYTESTRING_NONASCII_HEX: u32 = 4_194_304;
const KNOWN_FLAGS: u32 = 8_388_607;

#[derive(Clone, Debug)]
pub(crate) struct RebuiltFile {
    pub name: String,
    pub source: String,
    pub tokens: Vec<Token>,
    pub program: Program,
}

#[derive(Clone, Copy, Debug)]
struct FileRecord {
    name_start: usize,
    name_len: usize,
    source_start: usize,
    source_len: usize,
    token_start: usize,
    token_count: usize,
    node_start: usize,
    node_count: usize,
}

#[derive(Clone, Copy, Debug)]
struct WireToken {
    tag: u32,
    start: usize,
    len: usize,
    file: usize,
    line: usize,
    col: usize,
}

#[derive(Clone, Copy, Debug)]
struct WireNode {
    tag: u32,
    flags: u32,
    token: i64,
    start: usize,
    end: usize,
    anchor: i64,
    subtree: usize,
    extra: i64,
    aux: i64,
    meta0: i64,
    meta1: i64,
}

#[derive(Clone, Copy, Debug)]
struct Literal128([u32; 4]);

struct Tables {
    files: Vec<FileRecord>,
    names: Vec<u8>,
    source: Vec<u8>,
    tokens: Vec<WireToken>,
    nodes: Vec<WireNode>,
    extra: Vec<i64>,
    literals: Vec<Literal128>,
}

struct Cursor<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Cursor<'a> {
    fn new(bytes: &'a [u8], pos: usize) -> Self {
        Self { bytes, pos }
    }

    fn take(&mut self, len: usize, what: &str) -> Result<&'a [u8], String> {
        let end = self
            .pos
            .checked_add(len)
            .ok_or_else(|| format!("{what} extent overflowed"))?;
        let value = self
            .bytes
            .get(self.pos..end)
            .ok_or_else(|| format!("truncated {what}"))?;
        self.pos = end;
        Ok(value)
    }

    fn u32(&mut self, what: &str) -> Result<u32, String> {
        let bytes = self.take(4, what)?;
        Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    fn u64(&mut self, what: &str) -> Result<u64, String> {
        let bytes = self.take(8, what)?;
        Ok(u64::from_le_bytes([
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        ]))
    }

    fn i64(&mut self, what: &str) -> Result<i64, String> {
        let bytes = self.take(8, what)?;
        Ok(i64::from_le_bytes([
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        ]))
    }
}

fn usize_count(value: u64, max: usize, label: &str) -> Result<usize, String> {
    let value = usize::try_from(value).map_err(|_| format!("{label} count is too large"))?;
    if value > max {
        return Err(format!("{label} count exceeds the reader limit"));
    }
    Ok(value)
}

fn checked_total(parts: &[(usize, usize)], base: usize) -> Result<usize, String> {
    parts.iter().try_fold(base, |total, (count, size)| {
        total
            .checked_add(
                count
                    .checked_mul(*size)
                    .ok_or_else(|| "section extent overflowed".to_owned())?,
            )
            .ok_or_else(|| "section extent overflowed".to_owned())
    })
}

fn read_tables(bytes: &[u8]) -> Result<Tables, String> {
    if bytes.len() > MAX_WIRE_BYTES {
        return Err("binary tree exceeds the maximum wire size".to_owned());
    }
    if bytes.get(..8) != Some(MAGIC.as_slice()) {
        return Err("wrong binary tree magic".to_owned());
    }
    let mut header = Cursor::new(bytes, 8);
    let version = header.u32("header")?;
    if version != VERSION {
        return Err(format!("unsupported binary tree version {version}"));
    }
    let header_bytes = header.u32("header")? as usize;
    if header_bytes != HEADER_BYTES {
        return Err("invalid binary tree header size".to_owned());
    }
    let file_count = usize_count(header.u64("header")?, MAX_FILES, "file")?;
    let source_count = usize_count(header.u64("header")?, MAX_SOURCE_BYTES, "source byte")?;
    let token_count = usize_count(header.u64("header")?, MAX_TOKENS, "token")?;
    let node_count = usize_count(header.u64("header")?, MAX_NODES, "node")?;
    let extra_count = usize_count(header.u64("header")?, MAX_EXTRAS, "extra")?;
    let literal_count = usize_count(header.u64("header")?, MAX_LITERALS, "literal")?;
    let name_count = usize_count(header.u64("header")?, MAX_NAME_BYTES, "name byte")?;
    if file_count == 0 || node_count < file_count || token_count < file_count {
        return Err("binary tree has impossible package counts".to_owned());
    }
    let expected = checked_total(
        &[
            (file_count, FILE_RECORD_BYTES),
            (name_count, 1),
            (source_count, 1),
            (token_count, TOKEN_RECORD_BYTES),
            (node_count, NODE_RECORD_BYTES),
            (extra_count, 8),
            (literal_count, 16),
        ],
        HEADER_BYTES,
    )?;
    if expected > MAX_WIRE_BYTES || expected != bytes.len() {
        return Err("binary tree section extents do not match the file size".to_owned());
    }

    let mut cursor = Cursor::new(bytes, HEADER_BYTES);
    let mut files = Vec::with_capacity(file_count);
    for _ in 0..file_count {
        let name_start = usize::try_from(cursor.u64("file table")?)
            .map_err(|_| "file name offset is too large".to_owned())?;
        let name_len = usize::try_from(cursor.u64("file table")?)
            .map_err(|_| "file name length is too large".to_owned())?;
        let source_start = usize::try_from(cursor.u64("file table")?)
            .map_err(|_| "source offset is too large".to_owned())?;
        let source_len = usize::try_from(cursor.u64("file table")?)
            .map_err(|_| "source length is too large".to_owned())?;
        let token_start = usize::try_from(cursor.u64("file table")?)
            .map_err(|_| "token offset is too large".to_owned())?;
        let token_count = usize::try_from(cursor.u64("file table")?)
            .map_err(|_| "token length is too large".to_owned())?;
        let node_start = usize::try_from(cursor.u64("file table")?)
            .map_err(|_| "node offset is too large".to_owned())?;
        let node_count = usize::try_from(cursor.u64("file table")?)
            .map_err(|_| "node length is too large".to_owned())?;
        files.push(FileRecord {
            name_start,
            name_len,
            source_start,
            source_len,
            token_start,
            token_count,
            node_start,
            node_count,
        });
    }
    let names = cursor.take(name_count, "file names")?.to_vec();
    let source = cursor.take(source_count, "source section")?.to_vec();

    let mut tokens = Vec::with_capacity(token_count);
    for _ in 0..token_count {
        tokens.push(WireToken {
            tag: cursor.u32("token table")?,
            start: cursor.u32("token table")? as usize,
            len: cursor.u32("token table")? as usize,
            file: cursor.u32("token table")? as usize,
            line: cursor.u32("token table")? as usize,
            col: cursor.u32("token table")? as usize,
        });
    }
    let mut nodes = Vec::with_capacity(node_count);
    for _ in 0..node_count {
        nodes.push(WireNode {
            tag: cursor.u32("node table")?,
            flags: cursor.u32("node table")?,
            token: cursor.i64("node table")?,
            start: usize::try_from(cursor.u64("node table")?)
                .map_err(|_| "node start is too large".to_owned())?,
            end: usize::try_from(cursor.u64("node table")?)
                .map_err(|_| "node end is too large".to_owned())?,
            anchor: cursor.i64("node table")?,
            subtree: usize::try_from(cursor.u64("node table")?)
                .map_err(|_| "node subtree size is too large".to_owned())?,
            extra: cursor.i64("node table")?,
            aux: cursor.i64("node table")?,
            meta0: cursor.i64("node table")?,
            meta1: cursor.i64("node table")?,
        });
    }
    let mut extra = Vec::with_capacity(extra_count);
    for _ in 0..extra_count {
        extra.push(cursor.i64("extra table")?);
    }
    let mut literals = Vec::with_capacity(literal_count);
    for _ in 0..literal_count {
        literals.push(Literal128([
            cursor.u32("literal table")?,
            cursor.u32("literal table")?,
            cursor.u32("literal table")?,
            cursor.u32("literal table")?,
        ]));
    }
    if cursor.pos != bytes.len() {
        return Err("binary tree has trailing bytes".to_owned());
    }
    Ok(Tables {
        files,
        names,
        source,
        tokens,
        nodes,
        extra,
        literals,
    })
}

fn node_name(tag: u32) -> Option<&'static str> {
    Some(match tag {
        0 => "Program",
        1 => "Enum",
        2 => "EnumCase",
        3 => "Struct",
        4 => "StructField",
        5 => "TypeAlias",
        6 => "Const",
        7 => "Global",
        8 => "Function",
        9 => "Test",
        10 => "Parameter",
        11 => "Block",
        12 => "FunctionType",
        13 => "FunctionTypeParameter",
        14 => "Effect",
        15 => "ParameterType",
        16 => "ResultType",
        17 => "Annotation",
        18 => "FieldType",
        19 => "PayloadType",
        20 => "AliasedType",
        21 => "DeclaredType",
        22 => "TypeArgument",
        23 => "FitType",
        24 => "CastType",
        25 => "Let",
        26 => "Assign",
        27 => "ReturnStatement",
        28 => "ExpressionStatement",
        29 => "For",
        30 => "ForEach",
        31 => "Discard",
        32 => "Expect",
        33 => "BreakStatement",
        34 => "ContinueStatement",
        35 => "Unit",
        36 => "Integer",
        37 => "Bool",
        38 => "ByteString",
        39 => "BytesLiteral",
        40 => "Take",
        41 => "Name",
        42 => "Call",
        43 => "IndirectCall",
        44 => "QualifiedCase",
        45 => "MethodCall",
        46 => "Index",
        47 => "OptionalCall",
        48 => "Field",
        49 => "StructInit",
        50 => "InitializerField",
        51 => "ArrayLiteral",
        52 => "ListLiteral",
        53 => "PoolLiteral",
        54 => "MapLiteral",
        55 => "SetLiteral",
        56 => "QueueLiteral",
        57 => "RingLiteral",
        58 => "GridIndex",
        59 => "Fit",
        60 => "Try",
        61 => "Return",
        62 => "LoopExit",
        63 => "Match",
        64 => "MatchArm",
        65 => "ToLong",
        66 => "Cast",
        67 => "Unary",
        68 => "Binary",
        69 => "If",
        70 => "WildcardPattern",
        71 => "BoolPattern",
        72 => "CasePattern",
        73 => "PatternBinding",
        74 => "IgnoredPatternBinding",
        _ => return None,
    })
}

fn direct_children(
    nodes: &[WireNode],
    file_start: usize,
    index: usize,
) -> Result<Vec<usize>, String> {
    let node = nodes
        .get(index)
        .ok_or_else(|| "node index is out of range".to_owned())?;
    let first = index
        .checked_add(1)
        .and_then(|after| after.checked_sub(node.subtree))
        .ok_or_else(|| {
            format!(
                "impossible node subtree partition at node {index} (subtree {})",
                node.subtree
            )
        })?;
    if first < file_start || first > index {
        return Err(format!("impossible node subtree partition at node {index} (first {first}, file start {file_start})"));
    }
    let mut children = Vec::new();
    let mut child_end = index;
    while child_end > first {
        let child = child_end - 1;
        let child_first = child
            .checked_add(1)
            .and_then(|end| end.checked_sub(nodes[child].subtree))
            .ok_or_else(|| format!("impossible child subtree extent at node {child}"))?;
        if child_first < first {
            return Err(format!("impossible node subtree partition at node {index} (child {child} starts before {first})"));
        }
        children.push(child);
        child_end = child_first;
    }
    if child_end != first {
        return Err(format!("impossible node subtree partition at node {index} (expected start {first}, reached {child_end})"));
    }
    children.reverse();
    Ok(children)
}

fn extra_slice(tables: &Tables, index: i64, count: usize) -> Result<&[i64], String> {
    if count == 0 && index == -1 {
        return Ok(&[]);
    }
    let start = usize::try_from(index).map_err(|_| "extra table index is invalid".to_owned())?;
    let end = start
        .checked_add(count)
        .filter(|end| *end <= tables.extra.len())
        .ok_or_else(|| "extra table range is invalid".to_owned())?;
    Ok(&tables.extra[start..end])
}

fn is_type_tag(tag: u32) -> bool {
    (15..=24).contains(&tag)
}

fn hex_value(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn validate_string_token(
    tables: &Tables,
    file: &FileRecord,
    token: WireToken,
) -> Result<bool, String> {
    let start = file
        .source_start
        .checked_add(token.start)
        .ok_or_else(|| "string source offset overflowed".to_owned())?;
    let end = start
        .checked_add(token.len)
        .ok_or_else(|| "string source extent overflowed".to_owned())?;
    let raw = tables
        .source
        .get(start..end)
        .ok_or_else(|| "string token is outside its source".to_owned())?;
    if raw.len() < 2 || raw.first() != Some(&b'"') || raw.last() != Some(&b'"') {
        return Err("string token has invalid quotes".to_owned());
    }
    let mut non_ascii_hex = false;
    let mut cursor = 1usize;
    while cursor + 1 < raw.len() {
        match raw[cursor] {
            b'"' | b'\n' | b'\r' => {
                return Err("string token contains an unescaped delimiter".to_owned())
            }
            b'\\' => {
                let escaped = *raw
                    .get(cursor + 1)
                    .ok_or_else(|| "truncated string escape".to_owned())?;
                match escaped {
                    b'"' | b'\\' | b'n' | b't' | b'0' => cursor += 2,
                    b'x' => {
                        let high = raw
                            .get(cursor + 2)
                            .and_then(|byte| hex_value(*byte))
                            .ok_or_else(|| "invalid hexadecimal string escape".to_owned())?;
                        let low = raw
                            .get(cursor + 3)
                            .and_then(|byte| hex_value(*byte))
                            .ok_or_else(|| "invalid hexadecimal string escape".to_owned())?;
                        non_ascii_hex |= high * 16 + low > 0x7f;
                        cursor += 4;
                    }
                    _ => return Err("string token has an unsupported escape".to_owned()),
                }
            }
            _ => cursor += 1,
        }
    }
    if cursor != raw.len() - 1 {
        return Err("string token ends in a partial escape".to_owned());
    }
    Ok(non_ascii_hex)
}

fn validate_flags(node: WireNode) -> Result<(), String> {
    if node.flags & !KNOWN_FLAGS != 0 {
        return Err(format!(
            "{} has unknown flags",
            node_name(node.tag).unwrap_or("node")
        ));
    }
    let allowed = match node.tag {
        7 => F_PREFAULT,
        8 => F_RECURSIVE,
        10 | 13 => F_MODE_WRITE | F_MODE_GROW,
        11 => F_SYNTHETIC | F_HAS_TAIL,
        14 => F_EFFECT_WRITES | 7,
        15..=24 => {
            F_POLICY_WRAP
                | F_POLICY_CLAMP
                | F_RANGE
                | F_RANGE_INCLUSIVE
                | F_TYPE_FN
                | F_TYPE_UNIT
                | F_TYPE_TEXT_BYTES
        }
        25 => F_MUTABLE | F_HAS_ANNOTATION,
        26 => 7,
        67 => 1,
        68 => 31,
        29 => F_INCLUSIVE | F_HAS_ANNOTATION,
        36 => F_NEGATIVE | F_LONG_SUFFIX,
        38 => F_BYTESTRING_NONASCII_HEX,
        42 => F_SYNTHETIC,
        61 => F_HAS_VALUE,
        62 | 37 | 71 => F_VALUE,
        69 => F_HAS_ELSE,
        72 => F_HAS_ANNOTATION,
        _ => 0,
    };
    if node.flags & !allowed != 0 {
        return Err(format!(
            "{} has impossible flags",
            node_name(node.tag).unwrap_or("node")
        ));
    }
    if is_type_tag(node.tag) {
        let special = node.flags & (F_TYPE_FN | F_TYPE_UNIT | F_TYPE_TEXT_BYTES);
        if special.count_ones() > 1
            || node.flags & F_RANGE_INCLUSIVE != 0 && node.flags & F_RANGE == 0
            || node.flags & (F_POLICY_WRAP | F_POLICY_CLAMP) != 0 && node.flags & F_RANGE == 0
            || node.flags & F_POLICY_WRAP != 0 && node.flags & F_POLICY_CLAMP != 0
        {
            return Err("type has impossible flags".to_owned());
        }
    }
    if node.tag == 14 {
        let effect = node.flags & 7;
        if !matches!(effect, 1..=5) || (effect != 5 && node.flags & F_EFFECT_WRITES != 0) {
            return Err("Effect has an invalid kind".to_owned());
        }
    }
    if node.tag == 26 && node.flags > 6 {
        return Err("Assign has an invalid operator".to_owned());
    }
    if node.tag == 67 && node.flags > 1 {
        return Err("Unary has an invalid operator".to_owned());
    }
    if node.tag == 68 && node.flags > 21 {
        return Err("Binary has an invalid operator".to_owned());
    }
    Ok(())
}

fn validate_tables(tables: &Tables) -> Result<Vec<String>, String> {
    let mut file_names: Vec<String> = Vec::with_capacity(tables.files.len());
    let mut next_name = 0usize;
    let mut next_source = 0usize;
    let mut next_token = 0usize;
    let mut next_node = 0usize;
    let mut total_nodes = 0usize;
    let mut total_edges = 0usize;
    for (file_id, file) in tables.files.iter().enumerate() {
        if file.name_start != next_name
            || file.source_start != next_source
            || file.token_start != next_token
            || file.node_start != next_node
        {
            return Err("file ranges are not contiguous and ordered".to_owned());
        }
        let name_end = file
            .name_start
            .checked_add(file.name_len)
            .ok_or_else(|| "file name extent overflowed".to_owned())?;
        let name = std::str::from_utf8(
            tables
                .names
                .get(file.name_start..name_end)
                .ok_or_else(|| "file name extends past its section".to_owned())?,
        )
        .map_err(|_| "file name is not valid UTF-8".to_owned())?;
        if name.is_empty() || name.contains('/') || name.contains('\\') || name.contains('\0') {
            return Err("file name is not a package-relative base name".to_owned());
        }
        if let Some(previous) = file_names.last() {
            if previous.as_str() >= name {
                return Err("file names are not in stable sorted order".to_owned());
            }
        }
        file_names.push(name.to_owned());
        let src_end = file
            .source_start
            .checked_add(file.source_len)
            .ok_or_else(|| "source file extent overflowed".to_owned())?;
        let source = tables
            .source
            .get(file.source_start..src_end)
            .ok_or_else(|| "source file extends past its section".to_owned())?;
        std::str::from_utf8(source).map_err(|_| "source file is not valid UTF-8".to_owned())?;
        let tok_end = file
            .token_start
            .checked_add(file.token_count)
            .ok_or_else(|| "file token extent overflowed".to_owned())?;
        let node_end = file
            .node_start
            .checked_add(file.node_count)
            .ok_or_else(|| "file node extent overflowed".to_owned())?;
        if file.token_count == 0
            || file.node_count == 0
            || tok_end > tables.tokens.len()
            || node_end > tables.nodes.len()
        {
            return Err("file token or node range is impossible".to_owned());
        }
        let mut line_starts = vec![0usize];
        for (offset, byte) in source.iter().enumerate() {
            if *byte == b'\n' {
                line_starts.push(offset + 1);
            }
        }
        let mut previous_end = 0usize;
        let mut eof_count = 0usize;
        for token_index in file.token_start..tok_end {
            let token = tables.tokens[token_index];
            if token.file != file_id || token.tag > 50 {
                return Err("token tag or file ownership is invalid".to_owned());
            }
            let end = token
                .start
                .checked_add(token.len)
                .ok_or_else(|| "token extent overflowed".to_owned())?;
            if end > file.source_len
                || token.start < previous_end
                || token.line == 0
                || token.col == 0
            {
                return Err("token span is outside its source file".to_owned());
            }
            let expected_line_index = line_starts
                .partition_point(|start| *start <= token.start)
                .saturating_sub(1);
            let expected_line = expected_line_index + 1;
            let expected_col = token.start - line_starts[expected_line_index] + 1;
            if token.line != expected_line || token.col != expected_col {
                return Err("token line and column do not match the source".to_owned());
            }
            if token.tag == 50 {
                eof_count += 1;
                if token.len != 0 || token.start != file.source_len || token_index + 1 != tok_end {
                    return Err("EOF token is not at the end of its file".to_owned());
                }
            } else if token.len == 0 {
                return Err("non-EOF token has an empty span".to_owned());
            }
            if token.tag == 3 && source.get(token.start) != Some(&b'\n') {
                return Err("newline token does not point to a newline".to_owned());
            }
            let token_bytes = source
                .get(token.start..end)
                .ok_or_else(|| "token bytes are outside their source".to_owned())?;
            std::str::from_utf8(token_bytes)
                .map_err(|_| "token span is not on UTF-8 boundaries".to_owned())?;
            if token.tag == 2 {
                validate_string_token(tables, file, token)?;
            }
            previous_end = end;
        }
        if eof_count != 1 {
            return Err("file must contain exactly one EOF token".to_owned());
        }

        let root_index = node_end - 1;
        if tables.nodes[root_index].tag != 0
            || tables.nodes[root_index].subtree != file.node_count
            || tables.nodes[root_index].start != 0
            || tables.nodes[root_index].end != file.source_len
        {
            return Err("file root is not a whole-file Program node".to_owned());
        }
        let mut heights = vec![0usize; file.node_count];
        for index in file.node_start..node_end {
            let node = tables.nodes[index];
            if node_name(node.tag).is_none() {
                return Err("node has an invalid tag".to_owned());
            }
            validate_flags(node)?;
            if node.subtree == 0 || node.subtree > index - file.node_start + 1 {
                return Err("node has an impossible subtree size".to_owned());
            }
            if node.start > node.end || node.end > file.source_len {
                return Err("node span is outside its source file".to_owned());
            }
            if node.token < -1 {
                return Err("node token index is negative".to_owned());
            }
            if node.token >= 0 {
                let token_index = usize::try_from(node.token)
                    .map_err(|_| "node token index is too large".to_owned())?;
                if token_index < file.token_start || token_index >= tok_end {
                    return Err("node token belongs to a different file".to_owned());
                }
            }
            let is_range_anchor = is_type_tag(node.tag) && node.flags & F_RANGE != 0;
            if is_range_anchor {
                let anchor = usize::try_from(node.anchor)
                    .map_err(|_| "range metadata index is invalid".to_owned())?;
                if anchor
                    .checked_add(4)
                    .filter(|end| *end <= tables.extra.len())
                    .is_none()
                {
                    return Err("range metadata extends past the extra table".to_owned());
                }
            } else if !(is_type_tag(node.tag) && node.anchor == -1)
                && (node.anchor < 0
                    || usize::try_from(node.anchor)
                        .map(|a| a > file.source_len)
                        .unwrap_or(true))
            {
                return Err("node anchor is outside its source file".to_owned());
            }
            let first = index + 1 - node.subtree;
            let child_indices = direct_children(&tables.nodes, file.node_start, index)?;
            for child in &child_indices {
                let c = tables.nodes[*child];
                if c.start < node.start || c.end > node.end {
                    return Err("child span lies outside its parent".to_owned());
                }
            }
            let height = child_indices
                .iter()
                .map(|child| heights[*child - file.node_start])
                .max()
                .unwrap_or(0)
                + 1;
            if height > MAX_TREE_DEPTH {
                return Err("tree depth exceeds the reader limit".to_owned());
            }
            heights[index - file.node_start] = height;
            validate_node_metadata(tables, file, node, &child_indices, first, tok_end).map_err(
                |error| {
                    format!(
                        "{} node {index}: {error}",
                        node_name(node.tag).unwrap_or("unknown")
                    )
                },
            )?;
        }
        total_nodes = total_nodes
            .checked_add(file.node_count)
            .ok_or_else(|| "node count overflowed".to_owned())?;
        total_edges = total_edges
            .checked_add(file.node_count - 1)
            .ok_or_else(|| "edge count overflowed".to_owned())?;
        next_name = name_end;
        next_source = src_end;
        next_token = tok_end;
        next_node = node_end;
    }
    if next_name != tables.names.len()
        || next_source != tables.source.len()
        || next_token != tables.tokens.len()
        || next_node != tables.nodes.len()
    {
        return Err("unowned bytes, tokens, or nodes remain in the binary tree".to_owned());
    }
    let work = tables
        .source
        .len()
        .saturating_add(tables.tokens.len())
        .saturating_add(total_nodes)
        .saturating_add(total_edges);
    if total_nodes > MAX_NODES || total_edges > MAX_NODES || work > MAX_PARSE_WORK {
        return Err("binary tree exceeds the parse work limits".to_owned());
    }
    Ok(file_names)
}

fn validate_node_metadata(
    tables: &Tables,
    file: &FileRecord,
    node: WireNode,
    children: &[usize],
    _first: usize,
    token_end: usize,
) -> Result<(), String> {
    let count = children.len();
    let expect_children = |wanted: usize| -> Result<(), String> {
        if count == wanted {
            Ok(())
        } else {
            Err(format!(
                "{} has an invalid child count",
                node_name(node.tag).unwrap_or("node")
            ))
        }
    };
    let valid_token = |value: i64, label: &str| -> Result<(), String> {
        let index =
            usize::try_from(value).map_err(|_| format!("{label} token index is invalid"))?;
        if index < file.token_start || index >= token_end || tables.tokens[index].tag != 0 {
            Err(format!("{label} does not reference an identifier token"))
        } else {
            Ok(())
        }
    };
    let valid_kind_token = |value: i64, kind: u32, label: &str| -> Result<(), String> {
        let index =
            usize::try_from(value).map_err(|_| format!("{label} token index is invalid"))?;
        if index < file.token_start || index >= token_end || tables.tokens[index].tag != kind {
            Err(format!(
                "{label} does not reference the required token kind"
            ))
        } else {
            Ok(())
        }
    };
    if node.aux < 0 && !matches!(node.tag, 15..=24 | 32 | 35..=41 | 48 | 52..=62 | 67..=71) {
        return Err(format!(
            "{} has a negative child count",
            node_name(node.tag).unwrap_or("node")
        ));
    }
    if node.meta0 < 0 || node.meta1 < 0 {
        return Err("node metadata contains a negative count".to_owned());
    }
    if !matches!(node.tag, 15..=24 | 42) && (node.meta0 != 0 || node.meta1 != 0) {
        return Err(format!(
            "{} has unexpected metadata",
            node_name(node.tag).unwrap_or("node")
        ));
    }
    if matches!(node.tag, 1..=8 | 10 | 25 | 29 | 30 | 41 | 42 | 44 | 45 | 47 | 48 | 49 | 50 | 61..=63 | 65 | 69..=73)
        && !(node.tag == 42 && node.flags & F_SYNTHETIC != 0)
    {
        valid_token(node.token, node_name(node.tag).unwrap_or("node"))?;
    }
    match node.tag {
        9 | 38 => valid_kind_token(node.token, 2, node_name(node.tag).unwrap_or("string"))?,
        36 => valid_kind_token(node.token, 1, "Integer")?,
        37 | 39 | 40 | 62 | 70 | 71 => {
            valid_kind_token(node.token, 0, node_name(node.tag).unwrap_or("node"))?
        }
        14 => valid_kind_token(node.token, 0, "Effect")?,
        66 => valid_kind_token(node.token, 4, "Cast")?,
        60 => valid_kind_token(node.token, 14, "Try")?,
        67 | 68 => {
            let token = usize::try_from(node.token)
                .map_err(|_| "operator token index is invalid".to_owned())?;
            let actual = tables
                .tokens
                .get(token)
                .filter(|_| token >= file.token_start && token < token_end)
                .map(|token| token.tag)
                .ok_or_else(|| "operator token is outside its file".to_owned())?;
            let expected = if node.tag == 67 {
                if node.flags == 0 {
                    22
                } else {
                    37
                }
            } else {
                match node.flags {
                    0 => 21,
                    1 => 22,
                    2 => 23,
                    3 => 24,
                    4 => 25,
                    5 => 26,
                    6 => 27,
                    7 => 28,
                    8 => 36,
                    9 => 38,
                    10 => 39,
                    11 => 40,
                    12 => 41,
                    13 => 42,
                    14 => 44,
                    15 => 46,
                    16 => 43,
                    17 => 45,
                    18 => 47,
                    19 => 48,
                    20 => 49,
                    21 => 16,
                    _ => return Err("Binary operator is invalid".to_owned()),
                }
            };
            if actual != expected {
                return Err("operator does not reference an operator token".to_owned());
            }
        }
        _ => (),
    }
    if node.token == -1
        && matches!(node.tag, 1..=10 | 25 | 29..=32 | 36..=42 | 44..=50 | 58..=63 | 65..=69 | 71..=73)
    {
        // Synthetic expression and structural nodes are the exceptions.
        if !(node.tag == 42 && node.flags & F_SYNTHETIC != 0) {
            return Err(format!(
                "{} is missing its token",
                node_name(node.tag).unwrap_or("node")
            ));
        }
    }
    match node.tag {
        0 => {
            if node.token != -1 || node.flags != 0 {
                return Err("Program has invalid metadata".to_owned());
            }
            if children
                .iter()
                .any(|child| !matches!(tables.nodes[*child].tag, 1 | 3 | 5..=9))
            {
                return Err("Program child is not a declaration".to_owned());
            }
        }
        1 => {
            if children.iter().any(|child| tables.nodes[*child].tag != 2) {
                return Err("Enum child is not an EnumCase".to_owned());
            }
        }
        3 => {
            if node.tag == 3 {
                let generic_count = usize::try_from(node.aux)
                    .map_err(|_| "Struct generic count is invalid".to_owned())?;
                for reference in extra_slice(tables, node.extra, generic_count)? {
                    valid_token(*reference, "Struct generic name")?;
                }
            }
            if children.iter().any(|child| tables.nodes[*child].tag != 4) {
                return Err("Struct child is not a StructField".to_owned());
            }
        }
        2 => {
            if children.iter().any(|child| tables.nodes[*child].tag != 19) {
                return Err("EnumCase payload child has the wrong role".to_owned());
            }
        }
        4 => {
            if count < 1
                || count > 2
                || tables.nodes[children[0]].tag != 18
                || count == 2 && !is_expression_tag(tables.nodes[children[1]].tag)
            {
                return Err("StructField child roles are invalid".to_owned());
            }
        }
        5 => {
            expect_children(1)?;
            if tables.nodes[children[0]].tag != 20 {
                return Err("TypeAlias child role is invalid".to_owned());
            }
        }
        6 | 7 => {
            expect_children(2)?;
            if tables.nodes[children[0]].tag != 21
                || !is_expression_tag(tables.nodes[children[1]].tag)
            {
                return Err("constant or global child roles are invalid".to_owned());
            }
        }
        8 | 9 => {
            if count == 0 || tables.nodes[*children.last().unwrap()].tag != 11 {
                return Err("function or test is missing its body".to_owned());
            }
            if node.tag == 8 {
                let generic_count = usize::try_from(node.aux)
                    .map_err(|_| "Function generic count is invalid".to_owned())?;
                for reference in extra_slice(tables, node.extra, generic_count)? {
                    valid_token(*reference, "Function generic name")?;
                }
                let mut saw_result = false;
                for child in &children[..count - 1] {
                    match tables.nodes[*child].tag {
                        10 if !saw_result => (),
                        16 if !saw_result => saw_result = true,
                        _ => {
                            return Err(
                                "Function parameter or result child order is invalid".to_owned()
                            )
                        }
                    }
                }
            } else {
                let params = usize::try_from(node.aux)
                    .map_err(|_| "Test parameter count is invalid".to_owned())?;
                if params + 1 != count
                    || children[..params]
                        .iter()
                        .any(|child| tables.nodes[*child].tag != 10)
                {
                    return Err("Test parameter child roles are invalid".to_owned());
                }
            }
        }
        10 => {
            expect_children(1)?;
            if tables.nodes[children[0]].tag != 15 {
                return Err("Parameter child role is invalid".to_owned());
            }
        }
        11 => {
            for (position, child) in children.iter().enumerate() {
                let tag = tables.nodes[*child].tag;
                if position + 1 == count && node.flags & F_HAS_TAIL != 0 {
                    if !is_expression_tag(tag) {
                        return Err("block tail is not an expression".to_owned());
                    }
                } else if !is_statement_tag(tag) && tag != 11 {
                    return Err("block statement child has the wrong role".to_owned());
                }
            }
        }
        12 => {
            let param_count = usize::try_from(node.aux)
                .map_err(|_| "function type parameter count is invalid".to_owned())?;
            if param_count > count
                || children[..param_count]
                    .iter()
                    .any(|child| tables.nodes[*child].tag != 13)
            {
                return Err("FunctionType parameter roles are invalid".to_owned());
            }
            let rest = &children[param_count..];
            let results = rest
                .iter()
                .filter(|child| tables.nodes[**child].tag == 16)
                .count();
            if results > 1
                || rest
                    .iter()
                    .any(|child| !matches!(tables.nodes[*child].tag, 14 | 16))
            {
                return Err("FunctionType result or effect roles are invalid".to_owned());
            }
        }
        13 => {
            expect_children(1)?;
            if !is_type_tag(tables.nodes[children[0]].tag) {
                return Err("function type parameter child is invalid".to_owned());
            }
        }
        14 => {
            expect_children(0)?;
            if node.flags & 7 == 5 {
                let path_count = usize::try_from(node.aux)
                    .map_err(|_| "effect path count is invalid".to_owned())?;
                let refs = extra_slice(tables, node.extra, path_count)?;
                if path_count == 0 {
                    return Err("effect path is empty".to_owned());
                }
                for reference in refs {
                    valid_token(*reference, "effect path")?;
                }
            }
        }
        15..=24 => validate_type_metadata(tables, file, node, children)?,
        25 => {
            if count != 1 + usize::from(node.flags & F_HAS_ANNOTATION != 0) {
                return Err("Let has an invalid child count".to_owned());
            }
            let value = *children
                .last()
                .ok_or_else(|| "Let has no value".to_owned())?;
            if !is_expression_tag(tables.nodes[value].tag) {
                return Err("Let value child has the wrong role".to_owned());
            }
            if node.flags & F_HAS_ANNOTATION != 0 && tables.nodes[children[0]].tag != 17 {
                return Err("Let annotation child has the wrong role".to_owned());
            }
        }
        26 => {
            expect_children(2)?;
            if !is_expression_tag(tables.nodes[children[0]].tag)
                || !is_expression_tag(tables.nodes[children[1]].tag)
            {
                return Err("Assign child roles are invalid".to_owned());
            }
            let expected = match node.flags {
                0 => 35,
                1 => 29,
                2 => 30,
                3 => 31,
                4 => 32,
                5 => 33,
                6 => 34,
                _ => return Err("Assign operator is invalid".to_owned()),
            };
            let token = usize::try_from(node.token)
                .map_err(|_| "Assign operator token is invalid".to_owned())?;
            if tables.tokens[token].tag != expected {
                return Err("Assign operator token does not match its operator".to_owned());
            }
        }
        27 => {
            if count > 1 || count == 1 && !is_expression_tag(tables.nodes[children[0]].tag) {
                return Err("ReturnStatement child role is invalid".to_owned());
            }
        }
        28 | 31 | 32 | 40 | 60 => {
            expect_children(1)?;
            if !is_expression_tag(tables.nodes[children[0]].tag) {
                return Err("expression statement child role is invalid".to_owned());
            }
            if node.tag == 32 {
                let offsets = extra_slice(tables, node.extra, 2)?;
                let start = usize::try_from(offsets[0])
                    .ok()
                    .and_then(|offset| offset.checked_sub(file.source_start));
                let end = usize::try_from(offsets[1])
                    .ok()
                    .and_then(|offset| offset.checked_sub(file.source_start));
                if start
                    .zip(end)
                    .is_none_or(|(start, end)| start > end || end > file.source_len)
                {
                    return Err("Expect source offsets are outside their file".to_owned());
                }
            }
        }
        29 => {
            let annotated = node.flags & F_HAS_ANNOTATION != 0;
            if count != 3 + usize::from(annotated)
                || !is_expression_tag(tables.nodes[children[usize::from(annotated)]].tag)
                || !is_expression_tag(tables.nodes[children[usize::from(annotated) + 1]].tag)
                || tables.nodes[*children.last().unwrap()].tag != 11
            {
                return Err("For child roles are invalid".to_owned());
            }
        }
        30 => {
            expect_children(2)?;
            if !is_expression_tag(tables.nodes[children[0]].tag)
                || tables.nodes[children[1]].tag != 11
            {
                return Err("ForEach child roles are invalid".to_owned());
            }
            let n = usize::try_from(node.aux)
                .map_err(|_| "ForEach index count is invalid".to_owned())?;
            for value in extra_slice(tables, node.extra, n)? {
                valid_token(*value, "ForEach index")?;
            }
            if n > 2 {
                return Err("ForEach has too many index names".to_owned());
            }
        }
        33 | 34 | 35 | 37 | 38 | 41 | 52..=57 | 62 | 70 | 71 | 74 => expect_children(0)?,
        36 => {
            expect_children(0)?;
            let index = usize::try_from(node.extra)
                .map_err(|_| "integer literal index is invalid".to_owned())?;
            if index >= tables.literals.len() {
                return Err("integer literal index is out of range".to_owned());
            }
        }
        39 => {
            expect_children(0)?;
            let index = usize::try_from(node.extra)
                .map_err(|_| "byte literal string token is invalid".to_owned())?;
            if index < file.token_start || index >= token_end || tables.tokens[index].tag != 2 {
                return Err("BytesLiteral does not reference a string token".to_owned());
            }
        }
        42 => {
            if usize::try_from(node.aux).ok() != Some(count)
                || children
                    .iter()
                    .any(|child| !is_expression_tag(tables.nodes[*child].tag))
            {
                return Err("Call argument count or child roles are invalid".to_owned());
            }
            if node.flags & F_SYNTHETIC == 0 {
                if node.meta0 < node.start as i64 || node.meta0 > node.end as i64 {
                    return Err("Call span is out of bounds".to_owned());
                }
            }
        }
        43 | 45 | 47 => {
            let args = usize::try_from(node.aux)
                .map_err(|_| "call argument count is invalid".to_owned())?;
            if count != args + 1
                || children
                    .iter()
                    .any(|child| !is_expression_tag(tables.nodes[*child].tag))
            {
                return Err("call child roles are invalid".to_owned());
            }
        }
        44 => {
            let args = usize::try_from(node.aux)
                .map_err(|_| "qualified case argument count is invalid".to_owned())?;
            expect_children(args)?;
            if children
                .iter()
                .any(|child| !is_expression_tag(tables.nodes[*child].tag))
            {
                return Err("QualifiedCase argument roles are invalid".to_owned());
            }
            let case = *extra_slice(tables, node.extra, 1)?
                .first()
                .ok_or_else(|| "qualified case token is missing".to_owned())?;
            valid_token(case, "qualified case")?;
        }
        46 => {
            expect_children(2)?;
            if !is_expression_tag(tables.nodes[children[0]].tag)
                || !is_expression_tag(tables.nodes[children[1]].tag)
            {
                return Err("Index child roles are invalid".to_owned());
            }
        }
        48 => {
            expect_children(1)?;
            if !is_expression_tag(tables.nodes[children[0]].tag) {
                return Err("Field child role is invalid".to_owned());
            }
        }
        49 => {
            if usize::try_from(node.aux).ok() != Some(count)
                || children.iter().any(|child| tables.nodes[*child].tag != 50)
            {
                return Err("StructInit child role is invalid".to_owned());
            }
        }
        50 => {
            expect_children(1)?;
            if !is_expression_tag(tables.nodes[children[0]].tag) {
                return Err("initializer field child role is invalid".to_owned());
            }
        }
        51 => {
            if children
                .iter()
                .any(|child| !is_expression_tag(tables.nodes[*child].tag))
            {
                return Err("ArrayLiteral child role is invalid".to_owned());
            }
        }
        58 => {
            expect_children(3)?;
            if children
                .iter()
                .any(|child| !is_expression_tag(tables.nodes[*child].tag))
            {
                return Err("GridIndex child roles are invalid".to_owned());
            }
        }
        59 => {
            expect_children(2)?;
            if !is_expression_tag(tables.nodes[children[0]].tag)
                || !is_type_tag(tables.nodes[children[1]].tag)
            {
                return Err("Fit child roles are invalid".to_owned());
            }
        }
        66 => {
            expect_children(2)?;
            if !is_type_tag(tables.nodes[children[0]].tag)
                || !is_expression_tag(tables.nodes[children[1]].tag)
            {
                return Err("Cast child roles are invalid".to_owned());
            }
        }
        61 => {
            if count > 1 || count == 1 && !is_expression_tag(tables.nodes[children[0]].tag) {
                return Err("Return child role is invalid".to_owned());
            }
        }
        63 => {
            if usize::try_from(node.aux)
                .ok()
                .is_none_or(|arms| arms + 1 != count)
                || count < 1
                || !is_expression_tag(tables.nodes[children[0]].tag)
                || children[1..]
                    .iter()
                    .any(|child| tables.nodes[*child].tag != 64)
            {
                return Err("Match child roles are invalid".to_owned());
            }
        }
        64 => {
            expect_children(2)?;
            if !is_pattern_tag(tables.nodes[children[0]].tag) && tables.nodes[children[0]].tag != 36
                || tables.nodes[children[1]].tag != 11
            {
                return Err("MatchArm child roles are invalid".to_owned());
            }
        }
        65 => {
            expect_children(1)?;
            if !is_expression_tag(tables.nodes[children[0]].tag) {
                return Err("ToLong child role is invalid".to_owned());
            }
        }
        67 => {
            expect_children(1)?;
            if !is_expression_tag(tables.nodes[children[0]].tag) {
                return Err("Unary child role is invalid".to_owned());
            }
        }
        68 => {
            expect_children(2)?;
            if children
                .iter()
                .any(|child| !is_expression_tag(tables.nodes[*child].tag))
            {
                return Err("Binary child roles are invalid".to_owned());
            }
        }
        69 => {
            let expected = if node.flags & F_HAS_ELSE != 0 { 3 } else { 2 };
            expect_children(expected)?;
            if !is_expression_tag(tables.nodes[children[0]].tag)
                || tables.nodes[children[1]].tag != 11
                || expected == 3 && tables.nodes[children[2]].tag != 11
            {
                return Err("If child roles are invalid".to_owned());
            }
        }
        72 => {
            if usize::try_from(node.aux).ok() != Some(count) {
                return Err("CasePattern binding count is invalid".to_owned());
            }
            for child in children {
                if !matches!(tables.nodes[*child].tag, 73 | 74) {
                    return Err("CasePattern binding role is invalid".to_owned());
                }
            }
            if node.flags & F_HAS_ANNOTATION != 0 {
                valid_token(node.extra, "pattern enum")?;
            }
        }
        73 => expect_children(0)?,
        _ => return Err("node tag has no validation rule".to_owned()),
    }
    Ok(())
}

fn validate_type_metadata(
    tables: &Tables,
    file: &FileRecord,
    node: WireNode,
    children: &[usize],
) -> Result<(), String> {
    let name_count =
        usize::try_from(node.meta0).map_err(|_| "type name count is invalid".to_owned())?;
    if node.flags & (F_TYPE_FN | F_TYPE_UNIT | F_TYPE_TEXT_BYTES) == 0 {
        if name_count == 0 {
            return Err("named type has no name parts".to_owned());
        }
        for value in extra_slice(tables, node.extra, name_count)? {
            let token =
                usize::try_from(*value).map_err(|_| "type name token is invalid".to_owned())?;
            if token < file.token_start
                || token >= file.token_start + file.token_count
                || tables.tokens[token].tag != 0
            {
                return Err("type name is not an identifier in this file".to_owned());
            }
        }
    }
    let packed = node.meta1 as u64;
    let args = (packed & 0x1f_ffff) as usize;
    let constants = ((packed >> 21) & 0x1f_ffff) as usize;
    let arrays = ((packed >> 42) & 0x1f_ffff) as usize;
    let function = usize::from(node.flags & F_TYPE_FN != 0);
    if args
        .checked_add(constants)
        .and_then(|n| n.checked_add(arrays))
        .and_then(|n| n.checked_add(function))
        != Some(children.len())
    {
        return Err("type child counts do not match its children".to_owned());
    }
    let mut cursor = 0;
    if function != 0 {
        if children
            .first()
            .is_none_or(|child| tables.nodes[*child].tag != 12)
        {
            return Err("function type is missing its FunctionType child".to_owned());
        }
        cursor += 1;
    }
    let array_start = children.len() - arrays;
    if children[cursor..array_start]
        .iter()
        .filter(|child| is_type_tag(tables.nodes[**child].tag))
        .count()
        != args
        || children[cursor..array_start]
            .iter()
            .filter(|child| is_expression_tag(tables.nodes[**child].tag))
            .count()
            != constants
    {
        return Err("generic type child roles do not match their counts".to_owned());
    }
    let pool_owner = name_is_pool(tables, file, node, name_count)? && args == 2 && constants == 1;
    if pool_owner {
        let base = &children[cursor..array_start];
        if base.len() != 3
            || !is_type_tag(tables.nodes[base[0]].tag)
            || !is_expression_tag(tables.nodes[base[1]].tag)
            || !is_type_tag(tables.nodes[base[2]].tag)
        {
            return Err("pool owner type child roles are invalid".to_owned());
        }
    } else {
        let base = &children[cursor..array_start];
        if base[..args]
            .iter()
            .any(|child| !is_type_tag(tables.nodes[*child].tag))
            || base[args..]
                .iter()
                .any(|child| !is_expression_tag(tables.nodes[*child].tag))
        {
            return Err("type argument or constant child has the wrong role".to_owned());
        }
    }
    if children[array_start..]
        .iter()
        .any(|child| !is_expression_tag(tables.nodes[*child].tag))
    {
        return Err("array capacity child has the wrong role".to_owned());
    }
    if node.flags & F_TYPE_UNIT != 0 && (!children.is_empty() || node.meta0 != 0 || node.meta1 != 0)
    {
        return Err("unit type has invalid children".to_owned());
    }
    if node.flags & F_TYPE_TEXT_BYTES != 0 && (args != 0 || constants != 1 || arrays != 0) {
        return Err("TextBytes type has invalid children".to_owned());
    }
    if node.flags & F_RANGE != 0 {
        let start =
            usize::try_from(node.anchor).map_err(|_| "type range index is invalid".to_owned())?;
        let values = extra_slice(tables, start as i64, 4)?;
        for pair in values.chunks_exact(2) {
            let literal = usize::try_from(pair[0])
                .map_err(|_| "range literal index is invalid".to_owned())?;
            if literal >= tables.literals.len() || !matches!(pair[1], 0 | 1) {
                return Err("range bound metadata is invalid".to_owned());
            }
        }
    }
    Ok(())
}

fn name_is_pool(
    tables: &Tables,
    file: &FileRecord,
    node: WireNode,
    name_count: usize,
) -> Result<bool, String> {
    let names = extra_slice(tables, node.extra, name_count)?;
    if names.len() != 1 {
        return Ok(false);
    }
    let token = usize::try_from(names[0]).map_err(|_| "type name token is invalid".to_owned())?;
    let value = tables
        .tokens
        .get(token)
        .ok_or_else(|| "type name token is out of range".to_owned())?;
    if value.tag != 0 {
        return Err("type name is not an identifier".to_owned());
    }
    let start = file
        .source_start
        .checked_add(value.start)
        .ok_or_else(|| "type name source offset overflowed".to_owned())?;
    let end = start
        .checked_add(value.len)
        .ok_or_else(|| "type name source extent overflowed".to_owned())?;
    Ok(tables.source.get(start..end) == Some(b"pool".as_slice()))
}

fn is_expression_tag(tag: u32) -> bool {
    matches!(tag, 35..=63 | 65..=69)
}
fn is_statement_tag(tag: u32) -> bool {
    matches!(tag, 25..=34)
}
fn is_pattern_tag(tag: u32) -> bool {
    matches!(tag, 70..=74)
}

#[derive(Debug)]
enum AstValue {
    Program(Program),
    Enum(EnumDecl),
    EnumCase(EnumCase),
    Struct(StructDecl),
    StructField(StructFieldDecl),
    TypeAlias(TypeAliasDecl),
    Constant(ConstDecl),
    Global(GlobalDecl),
    Function(Function),
    Test(Test),
    Param(Param),
    Block(Block),
    FunctionType(FunctionTypeAst),
    FunctionTypeParam(FunctionTypeParamAst),
    Effect(FunctionEffectAst),
    Type(TypeAst),
    Stmt(Stmt),
    Expr(Expr),
    InitializerField(StructInitField),
    MatchArm(MatchArm),
    Pattern(Pattern),
    Binding(Option<(String, Span)>, Span),
}

struct BuildContext<'a> {
    tables: &'a Tables,
    file: FileRecord,
    file_id: usize,
    source: &'a [u8],
    line_starts: Vec<usize>,
}

impl BuildContext<'_> {
    fn span(&self, start: usize, end: usize) -> Span {
        let start = start.min(self.file.source_len);
        let end = end.min(self.file.source_len).max(start);
        let line_index = self
            .line_starts
            .partition_point(|offset| *offset <= start)
            .saturating_sub(1);
        Span {
            file: self.file_id,
            line: line_index + 1,
            col: start - self.line_starts[line_index] + 1,
            start_offset: start,
            end_offset: end,
        }
    }

    fn node_span(&self, node: WireNode) -> Span {
        self.span(node.start, node.end)
    }

    fn token(&self, index: i64) -> Result<WireToken, String> {
        let index = usize::try_from(index).map_err(|_| "token index is invalid".to_owned())?;
        let token = self
            .tables
            .tokens
            .get(index)
            .copied()
            .ok_or_else(|| "token index is out of range".to_owned())?;
        if token.file != self.file_id {
            return Err("token belongs to a different file".to_owned());
        }
        Ok(token)
    }

    fn token_span(&self, index: i64) -> Result<Span, String> {
        let token = self.token(index)?;
        let end = token
            .start
            .checked_add(token.len)
            .ok_or_else(|| "token span overflowed".to_owned())?;
        Ok(self.span(token.start, end))
    }

    fn token_name(&self, index: i64) -> Result<String, String> {
        let token = self.token(index)?;
        if token.tag != 0 {
            return Err("name field does not reference an identifier".to_owned());
        }
        let end = token
            .start
            .checked_add(token.len)
            .ok_or_else(|| "name span overflowed".to_owned())?;
        let bytes = self
            .source
            .get(token.start..end)
            .ok_or_else(|| "name span is outside its file".to_owned())?;
        let name =
            std::str::from_utf8(bytes).map_err(|_| "identifier is not valid UTF-8".to_owned())?;
        Ok(name.to_owned())
    }

    fn token_at_offset(&self, offset: usize) -> Result<Span, String> {
        let end = self.file.token_start + self.file.token_count;
        let slice = &self.tables.tokens[self.file.token_start..end];
        let index = slice.binary_search_by(|token| token.start.cmp(&offset));
        let token = match index {
            Ok(index) => slice[index],
            Err(_) => return Err("synthetic call span has no source token".to_owned()),
        };
        Ok(self.span(token.start, token.start + token.len))
    }

    fn extra(&self, index: i64) -> Result<i64, String> {
        let index =
            usize::try_from(index).map_err(|_| "extra table index is invalid".to_owned())?;
        self.tables
            .extra
            .get(index)
            .copied()
            .ok_or_else(|| "extra table index is out of range".to_owned())
    }

    fn extra_range(&self, index: i64, count: usize) -> Result<&[i64], String> {
        let start =
            usize::try_from(index).map_err(|_| "extra table index is invalid".to_owned())?;
        let end = start
            .checked_add(count)
            .filter(|end| *end <= self.tables.extra.len())
            .ok_or_else(|| "extra table range is out of range".to_owned())?;
        Ok(&self.tables.extra[start..end])
    }

    fn literal(&self, index: i64) -> Result<u128, String> {
        let index = usize::try_from(index).map_err(|_| "literal index is invalid".to_owned())?;
        let value = self
            .tables
            .literals
            .get(index)
            .ok_or_else(|| "literal index is out of range".to_owned())?;
        Ok(u128::from(value.0[0])
            | (u128::from(value.0[1]) << 32)
            | (u128::from(value.0[2]) << 64)
            | (u128::from(value.0[3]) << 96))
    }

    fn source_absolute(&self, offset: i64) -> Result<usize, String> {
        let offset = usize::try_from(offset).map_err(|_| "source offset is invalid".to_owned())?;
        let local = offset
            .checked_sub(self.file.source_start)
            .ok_or_else(|| "source offset belongs to a different file".to_owned())?;
        if local > self.file.source_len {
            return Err("source offset is outside its file".to_owned());
        }
        Ok(local)
    }
}

fn take_value(values: &mut [Option<AstValue>], child: usize) -> Result<AstValue, String> {
    values
        .get_mut(child)
        .and_then(Option::take)
        .ok_or_else(|| "AST child value is missing or used more than once".to_owned())
}

macro_rules! take_as {
    ($values:expr, $child:expr, $kind:ident) => {
        match take_value($values, $child)? {
            AstValue::$kind(value) => value,
            _ => return Err(concat!("AST child is not ", stringify!($kind)).to_owned()),
        }
    };
}

fn decode_string_token(
    context: &BuildContext<'_>,
    token_index: i64,
) -> Result<(Vec<u8>, String, bool), String> {
    let token = context.token(token_index)?;
    if token.tag != 2 || token.len < 2 {
        return Err("string value does not reference a complete string token".to_owned());
    }
    let end = token
        .start
        .checked_add(token.len)
        .ok_or_else(|| "string token extent overflowed".to_owned())?;
    let raw = context
        .source
        .get(token.start..end)
        .ok_or_else(|| "string token is outside its source".to_owned())?;
    if raw.first() != Some(&b'"') || raw.last() != Some(&b'"') {
        return Err("string token has invalid quotes".to_owned());
    }
    let mut bytes = Vec::new();
    let mut value = String::new();
    let mut high_hex = false;
    let mut cursor = 1usize;
    while cursor + 1 < raw.len() {
        let byte = raw[cursor];
        if byte == b'\\' {
            let escaped = *raw
                .get(cursor + 1)
                .ok_or_else(|| "truncated string escape".to_owned())?;
            match escaped {
                b'"' => {
                    bytes.push(b'"');
                    value.push('"');
                    cursor += 2;
                }
                b'\\' => {
                    bytes.push(b'\\');
                    value.push('\\');
                    cursor += 2;
                }
                b'n' => {
                    bytes.push(b'\n');
                    value.push('\n');
                    cursor += 2;
                }
                b't' => {
                    bytes.push(b'\t');
                    value.push('\t');
                    cursor += 2;
                }
                b'0' => {
                    bytes.push(0);
                    value.push('\0');
                    cursor += 2;
                }
                b'x' => {
                    let hi = raw
                        .get(cursor + 2)
                        .and_then(|b| hex(*b))
                        .ok_or_else(|| "invalid hexadecimal string escape".to_owned())?;
                    let lo = raw
                        .get(cursor + 3)
                        .and_then(|b| hex(*b))
                        .ok_or_else(|| "invalid hexadecimal string escape".to_owned())?;
                    let decoded = hi * 16 + lo;
                    bytes.push(decoded);
                    value.push(char::from(decoded));
                    high_hex |= decoded > 0x7f;
                    cursor += 4;
                }
                _ => return Err("string token has an unsupported escape".to_owned()),
            }
        } else {
            let tail = std::str::from_utf8(&raw[cursor..raw.len() - 1])
                .map_err(|_| "string token is not UTF-8".to_owned())?;
            let ch = tail
                .chars()
                .next()
                .ok_or_else(|| "invalid string token".to_owned())?;
            let width = ch.len_utf8();
            value.push(ch);
            bytes.extend_from_slice(ch.encode_utf8(&mut [0; 4]).as_bytes());
            cursor += width;
        }
    }
    Ok((bytes, value, high_hex))
}

fn hex(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn build_token(
    context: &BuildContext<'_>,
    token_index: usize,
    token: WireToken,
) -> Result<Token, String> {
    let end = token
        .start
        .checked_add(token.len)
        .ok_or_else(|| "token span overflowed".to_owned())?;
    let span = context.span(token.start, end);
    let source = context
        .source
        .get(token.start..end)
        .ok_or_else(|| "token span is outside source".to_owned())?;
    let kind = match token.tag {
        0 => TokenKind::Ident(
            std::str::from_utf8(source)
                .map_err(|_| "identifier token is not UTF-8".to_owned())?
                .to_owned(),
        ),
        1 => TokenKind::Number(
            std::str::from_utf8(source)
                .map_err(|_| "number token is not UTF-8".to_owned())?
                .to_owned(),
        ),
        2 => {
            let (bytes, value, has_non_ascii_hex_escape) =
                decode_string_token(context, token_index as i64)?;
            TokenKind::String {
                value,
                bytes,
                has_non_ascii_hex_escape,
            }
        }
        3 => TokenKind::Newline,
        4 => TokenKind::LParen,
        5 => TokenKind::RParen,
        6 => TokenKind::LBrace,
        7 => TokenKind::RBrace,
        8 => TokenKind::LBracket,
        9 => TokenKind::RBracket,
        10 => TokenKind::Comma,
        11 => TokenKind::Colon,
        12 => TokenKind::Semicolon,
        13 => TokenKind::Dot,
        14 => TokenKind::Question,
        15 => TokenKind::QuestionDot,
        16 => TokenKind::QuestionQuestion,
        17 => TokenKind::Range,
        18 => TokenKind::RangeInclusive,
        19 => TokenKind::Arrow,
        20 => TokenKind::FatArrow,
        21 => TokenKind::Plus,
        22 => TokenKind::Minus,
        23 => TokenKind::Star,
        24 => TokenKind::Slash,
        25 => TokenKind::Percent,
        26 => TokenKind::WrapPlus,
        27 => TokenKind::WrapMinus,
        28 => TokenKind::WrapStar,
        29 => TokenKind::PlusEq,
        30 => TokenKind::MinusEq,
        31 => TokenKind::StarEq,
        32 => TokenKind::SlashEq,
        33 => TokenKind::PercentEq,
        34 => TokenKind::ShrEq,
        35 => TokenKind::Eq,
        36 => TokenKind::EqEq,
        37 => TokenKind::Bang,
        38 => TokenKind::BangEq,
        39 => TokenKind::Lt,
        40 => TokenKind::Le,
        41 => TokenKind::Gt,
        42 => TokenKind::Ge,
        43 => TokenKind::And,
        44 => TokenKind::AndAnd,
        45 => TokenKind::Or,
        46 => TokenKind::OrOr,
        47 => TokenKind::Caret,
        48 => TokenKind::Shl,
        49 => TokenKind::Shr,
        50 => TokenKind::Eof,
        _ => return Err("token tag is invalid".to_owned()),
    };
    Ok(Token {
        kind,
        span,
        start_offset: token.start,
        end_offset: end,
    })
}

fn signed_bound(magnitude: u128, negative: bool) -> Result<i128, String> {
    if negative {
        if magnitude == (1u128 << 127) {
            Ok(i128::MIN)
        } else {
            i128::try_from(magnitude)
                .map(|value| -value)
                .map_err(|_| "range bound is outside i128".to_owned())
        }
    } else {
        i128::try_from(magnitude).map_err(|_| "range bound is outside i128".to_owned())
    }
}

fn unpack_type_counts(node: WireNode) -> (usize, usize, usize) {
    let packed = node.meta1 as u64;
    (
        (packed & 0x1f_ffff) as usize,
        ((packed >> 21) & 0x1f_ffff) as usize,
        ((packed >> 42) & 0x1f_ffff) as usize,
    )
}

#[allow(unused_assignments)]
fn build_value(
    context: &BuildContext<'_>,
    _node_index: usize,
    node: WireNode,
    child_indices: &[usize],
    values: &mut [Option<AstValue>],
) -> Result<AstValue, String> {
    let span = context.node_span(node);
    let mut at = 0usize;
    macro_rules! next {
        ($kind:ident) => {{
            let child = *child_indices
                .get(at)
                .ok_or_else(|| "AST node is missing a child".to_owned())?;
            at += 1;
            take_as!(values, child, $kind)
        }};
    }
    macro_rules! name {
        () => {
            context.token_name(node.token)?
        };
    }
    macro_rules! child_node {
        ($position:expr) => {{
            let child = *child_indices
                .get($position)
                .ok_or_else(|| "AST node is missing a child".to_owned())?;
            context.tables.nodes[context.file.node_start + child]
        }};
    }
    match node.tag {
        0 => {
            let mut program = Program {
                enums: Vec::new(),
                structs: Vec::new(),
                aliases: Vec::new(),
                constants: Vec::new(),
                globals: Vec::new(),
                functions: Vec::new(),
                tests: Vec::new(),
            };
            for child in child_indices {
                match take_value(values, *child)? {
                    AstValue::Enum(value) => program.enums.push(value),
                    AstValue::Struct(value) => program.structs.push(value),
                    AstValue::TypeAlias(value) => program.aliases.push(value),
                    AstValue::Constant(value) => program.constants.push(value),
                    AstValue::Global(value) => program.globals.push(value),
                    AstValue::Function(value) => program.functions.push(value),
                    AstValue::Test(value) => program.tests.push(value),
                    _ => return Err("Program child is not a declaration".to_owned()),
                }
            }
            Ok(AstValue::Program(program))
        }
        1 => {
            let mut cases = Vec::with_capacity(child_indices.len());
            for child in child_indices {
                cases.push(take_as!(values, *child, EnumCase));
            }
            Ok(AstValue::Enum(EnumDecl {
                name: name!(),
                cases,
                span,
            }))
        }
        2 => {
            let name = name!();
            let mut payload = Vec::with_capacity(child_indices.len());
            for child in child_indices {
                payload.push(take_as!(values, *child, Type));
            }
            Ok(AstValue::EnumCase(EnumCase {
                name,
                payload,
                span,
            }))
        }
        3 => {
            let name = name!();
            let generic_count = usize::try_from(node.aux)
                .map_err(|_| "generic parameter count is invalid".to_owned())?;
            let generic_params = context
                .extra_range(node.extra, generic_count)?
                .iter()
                .map(|token| context.token_name(*token))
                .collect::<Result<Vec<_>, _>>()?;
            let mut fields = Vec::with_capacity(child_indices.len());
            for child in child_indices {
                fields.push(take_as!(values, *child, StructField));
            }
            Ok(AstValue::Struct(StructDecl {
                name,
                generic_params,
                fields,
                span,
            }))
        }
        4 => {
            let name = name!();
            let ty = next!(Type);
            let default = if at < child_indices.len() {
                Some(next!(Expr))
            } else {
                None
            };
            Ok(AstValue::StructField(StructFieldDecl {
                name,
                ty,
                default,
                span,
            }))
        }
        5 => Ok(AstValue::TypeAlias(TypeAliasDecl {
            name: name!(),
            ty: next!(Type),
            span,
        })),
        6 => Ok(AstValue::Constant(ConstDecl {
            name: name!(),
            ty: next!(Type),
            value: next!(Expr),
            span,
        })),
        7 => Ok(AstValue::Global(GlobalDecl {
            name: name!(),
            ty: next!(Type),
            value: next!(Expr),
            prefault: node.flags & F_PREFAULT != 0,
            span,
        })),
        8 => {
            let name = name!();
            let generic_count = usize::try_from(node.aux)
                .map_err(|_| "generic parameter count is invalid".to_owned())?;
            let generic_params = context
                .extra_range(node.extra, generic_count)?
                .iter()
                .map(|token| context.token_name(*token))
                .collect::<Result<Vec<_>, _>>()?;
            let mut params = Vec::new();
            let mut result = None;
            let mut body = None;
            for child in child_indices {
                match take_value(values, *child)? {
                    AstValue::Param(value) => params.push(value),
                    AstValue::Type(value) if result.is_none() => result = Some(value),
                    AstValue::Block(value) => body = Some(value),
                    _ => return Err("Function child has an invalid role".to_owned()),
                }
            }
            Ok(AstValue::Function(Function {
                name,
                recursive: node.flags & F_RECURSIVE != 0,
                generic_params,
                params,
                result,
                body: body.ok_or_else(|| "Function body is missing".to_owned())?,
                span,
            }))
        }
        9 => {
            let (bytes, test_name, _) = decode_string_token(context, node.token)?;
            let _ = bytes;
            let mut params = Vec::new();
            let mut body = None;
            for child in child_indices {
                match take_value(values, *child)? {
                    AstValue::Param(value) => params.push(value),
                    AstValue::Block(value) => body = Some(value),
                    _ => return Err("Test child has an invalid role".to_owned()),
                }
            }
            Ok(AstValue::Test(Test {
                name: test_name,
                params,
                body: body.ok_or_else(|| "Test body is missing".to_owned())?,
                span,
            }))
        }
        10 => {
            let mode = if node.flags & F_MODE_WRITE != 0 {
                ParamMode::Write
            } else if node.flags & F_MODE_GROW != 0 {
                ParamMode::Grow
            } else {
                ParamMode::Read
            };
            Ok(AstValue::Param(Param {
                name: name!(),
                mode,
                ty: next!(Type),
                span,
            }))
        }
        11 => {
            let has_tail = node.flags & F_HAS_TAIL != 0;
            let mut statements = Vec::with_capacity(child_indices.len());
            let mut tail = None;
            for (index, child) in child_indices.iter().enumerate() {
                let value = take_value(values, *child)?;
                if has_tail && index + 1 == child_indices.len() {
                    tail = Some(Box::new(match value {
                        AstValue::Expr(value) => value,
                        _ => return Err("block tail is not an expression".to_owned()),
                    }));
                } else {
                    let statement = match value {
                        AstValue::Stmt(value) => value,
                        AstValue::Block(block) => Stmt {
                            span: block.span,
                            kind: StmtKind::Block(block),
                        },
                        _ => return Err("block child is not a statement".to_owned()),
                    };
                    statements.push(statement);
                }
            }
            Ok(AstValue::Block(Block {
                statements,
                tail,
                span,
            }))
        }
        12 => {
            let param_count = usize::try_from(node.aux)
                .map_err(|_| "function type parameter count is invalid".to_owned())?;
            let mut params = Vec::with_capacity(param_count);
            for child in child_indices.iter().take(param_count) {
                params.push(take_as!(values, *child, FunctionTypeParam));
            }
            let mut result = None;
            let mut effects = Vec::new();
            for child in child_indices.iter().skip(param_count) {
                match take_value(values, *child)? {
                    AstValue::Type(value) if result.is_none() => result = Some(Box::new(value)),
                    AstValue::Effect(value) => effects.push(value),
                    _ => return Err("FunctionType child has an invalid role".to_owned()),
                }
            }
            Ok(AstValue::FunctionType(FunctionTypeAst {
                params,
                result,
                effects,
                span,
            }))
        }
        13 => {
            let mode = if node.flags & F_MODE_WRITE != 0 {
                ParamMode::Write
            } else if node.flags & F_MODE_GROW != 0 {
                ParamMode::Grow
            } else {
                ParamMode::Read
            };
            Ok(AstValue::FunctionTypeParam(FunctionTypeParamAst {
                mode,
                ty: next!(Type),
                span,
            }))
        }
        14 => {
            let kind = node.flags & 7;
            let node_span = span;
            let effect = match kind {
                1 => FunctionEffectAst::Out {
                    span: context.token_span(node.token)?,
                },
                2 => FunctionEffectAst::Env {
                    span: context.token_span(node.token)?,
                },
                3 => FunctionEffectAst::FsRead { span: node_span },
                4 => FunctionEffectAst::FsWrite { span: node_span },
                5 => {
                    let count = usize::try_from(node.aux)
                        .map_err(|_| "effect path count is invalid".to_owned())?;
                    let parts = context
                        .extra_range(node.extra, count)?
                        .iter()
                        .map(|token| context.token_name(*token))
                        .collect::<Result<Vec<_>, _>>()?;
                    let path = parts.join(".");
                    let root_span = context.token_span(
                        *context
                            .extra_range(node.extra, 1)?
                            .first()
                            .ok_or_else(|| "effect path is empty".to_owned())?,
                    )?;
                    if node.flags & F_EFFECT_WRITES != 0 {
                        FunctionEffectAst::Writes {
                            path,
                            span: root_span,
                            node_span,
                        }
                    } else {
                        FunctionEffectAst::Reads {
                            path,
                            span: root_span,
                            node_span,
                        }
                    }
                }
                _ => return Err("Effect kind is invalid".to_owned()),
            };
            Ok(AstValue::Effect(effect))
        }
        15..=24 => build_type(context, node, child_indices, values),
        25 => {
            let mutable = node.flags & F_MUTABLE != 0;
            let has_annotation = node.flags & F_HAS_ANNOTATION != 0;
            let name = name!();
            let annotation = if has_annotation {
                Some(next!(Type))
            } else {
                None
            };
            let mut value = next!(Expr);
            if matches!(&value.kind, ExprKind::Call { name, args, .. } if name == "default" && args.is_empty())
            {
                if let ExprKind::Call { call_span, .. } = &mut value.kind {
                    *call_span = context.token_at_offset(node.anchor as usize)?;
                }
            }
            Ok(AstValue::Stmt(Stmt {
                kind: StmtKind::Let {
                    mutable,
                    name,
                    annotation,
                    value,
                },
                span,
            }))
        }
        26 => {
            let target = next!(Expr);
            let value = next!(Expr);
            let op = match node.flags {
                0 => AssignOp::Set,
                1 => AssignOp::Add,
                2 => AssignOp::Sub,
                3 => AssignOp::Mul,
                4 => AssignOp::Div,
                5 => AssignOp::Rem,
                6 => AssignOp::Shr,
                _ => return Err("Assign operator is invalid".to_owned()),
            };
            Ok(AstValue::Stmt(Stmt {
                kind: StmtKind::Assign {
                    target,
                    op,
                    operator_span: context.token_span(node.token)?,
                    value,
                },
                span,
            }))
        }
        27 => {
            let value = if child_indices.is_empty() {
                None
            } else {
                Some(next!(Expr))
            };
            Ok(AstValue::Stmt(Stmt {
                kind: StmtKind::Return(value),
                span,
            }))
        }
        28 => Ok(AstValue::Stmt(Stmt {
            kind: StmtKind::Expr(next!(Expr)),
            span,
        })),
        29 => {
            let name = name!();
            let annotation = if node.flags & F_HAS_ANNOTATION != 0 {
                Some(next!(Type))
            } else {
                None
            };
            let start = next!(Expr);
            let end = next!(Expr);
            let body = next!(Block);
            Ok(AstValue::Stmt(Stmt {
                kind: StmtKind::For {
                    name,
                    annotation,
                    start,
                    end,
                    inclusive: node.flags & F_INCLUSIVE != 0,
                    body,
                },
                span,
            }))
        }
        30 => {
            let name = name!();
            let count = usize::try_from(node.aux)
                .map_err(|_| "ForEach index count is invalid".to_owned())?;
            let indexes = context
                .extra_range(node.extra, count)?
                .iter()
                .map(|token| context.token_name(*token))
                .collect::<Result<Vec<_>, _>>()?;
            let collection = next!(Expr);
            let body = next!(Block);
            Ok(AstValue::Stmt(Stmt {
                kind: StmtKind::ForEach {
                    name,
                    index_name: indexes.first().cloned(),
                    second_index_name: indexes.get(1).cloned(),
                    collection,
                    body,
                },
                span,
            }))
        }
        31 => Ok(AstValue::Stmt(Stmt {
            kind: StmtKind::Discard(next!(Expr)),
            span,
        })),
        32 => {
            let value = next!(Expr);
            let offsets = context.extra_range(node.extra, 2)?;
            let start = context.source_absolute(offsets[0])?;
            let end = context.source_absolute(offsets[1])?;
            let expression = std::str::from_utf8(
                context
                    .source
                    .get(start..end)
                    .ok_or_else(|| "expect source range is invalid".to_owned())?,
            )
            .map_err(|_| "expect source is not UTF-8".to_owned())?;
            Ok(AstValue::Stmt(Stmt {
                kind: StmtKind::Expect {
                    value,
                    source: format!("expect {expression}"),
                },
                span,
            }))
        }
        33 => Ok(AstValue::Stmt(Stmt {
            kind: StmtKind::Break,
            span,
        })),
        34 => Ok(AstValue::Stmt(Stmt {
            kind: StmtKind::Continue,
            span,
        })),
        35 => expr(ExprKind::Unit, span),
        36 => {
            let magnitude = context.literal(node.extra)?;
            let negative = node.flags & F_NEGATIVE != 0;
            expr(
                ExprKind::Integer {
                    magnitude,
                    negative,
                    long_suffix: node.flags & F_LONG_SUFFIX != 0,
                },
                span,
            )
        }
        37 => expr(ExprKind::Bool(node.flags & F_VALUE != 0), span),
        38 => {
            let (bytes, _, high_hex) = decode_string_token(context, node.token)?;
            if high_hex != (node.flags & F_BYTESTRING_NONASCII_HEX != 0) {
                return Err("ByteString hex-origin flag does not match its token".to_owned());
            }
            expr(ExprKind::ByteString(bytes, high_hex), span)
        }
        39 => {
            let (bytes, _, _) = decode_string_token(context, node.extra)?;
            expr(ExprKind::BytesLiteral(bytes), span)
        }
        40 => expr(ExprKind::Take(Box::new(next!(Expr))), span),
        41 => expr(ExprKind::Name(name!()), span),
        42 => {
            let name = if node.flags & F_SYNTHETIC != 0 {
                "default".to_owned()
            } else {
                name!()
            };
            let call_span = if node.flags & F_SYNTHETIC != 0 {
                context.span(node.start, node.end)
            } else {
                context.span(node.start, node.meta0 as usize)
            };
            let mut args = Vec::with_capacity(child_indices.len());
            for child in child_indices {
                args.push(take_as!(values, *child, Expr));
            }
            expr(
                ExprKind::Call {
                    name,
                    call_span,
                    args,
                },
                span,
            )
        }
        43 => {
            let callee = next!(Expr);
            let mut args = Vec::new();
            while at < child_indices.len() {
                args.push(next!(Expr));
            }
            expr(
                ExprKind::IndirectCall {
                    callee: Box::new(callee),
                    args,
                },
                span,
            )
        }
        44 => {
            let enum_name = context.token_name(node.token)?;
            let case_token = context.extra(node.extra)?;
            let case_name = context.token_name(case_token)?;
            let case_span = context.token_span(case_token)?;
            let mut args = Vec::new();
            for child in child_indices {
                args.push(take_as!(values, *child, Expr));
            }
            expr(
                ExprKind::QualifiedCase {
                    enum_name,
                    case_name,
                    case_span,
                    args,
                },
                span,
            )
        }
        45 => {
            let receiver = next!(Expr);
            let name = name!();
            let method_span = context.token_span(node.token)?;
            let mut args = Vec::new();
            while at < child_indices.len() {
                args.push(next!(Expr));
            }
            expr(
                ExprKind::MethodCall {
                    receiver: Box::new(receiver),
                    name,
                    method_span,
                    args,
                },
                span,
            )
        }
        46 => {
            let receiver = next!(Expr);
            let index = next!(Expr);
            let index_span = index.span;
            expr(
                ExprKind::Index {
                    receiver: Box::new(receiver),
                    index: Box::new(index),
                    index_span,
                },
                span,
            )
        }
        47 => {
            let receiver = next!(Expr);
            let name = name!();
            let method_span = context.token_span(node.token)?;
            let mut args = Vec::new();
            while at < child_indices.len() {
                args.push(next!(Expr));
            }
            expr(
                ExprKind::OptionalCall {
                    receiver: Box::new(receiver),
                    name,
                    method_span,
                    args,
                },
                span,
            )
        }
        48 => expr(
            ExprKind::Field {
                receiver: Box::new(next!(Expr)),
                name: name!(),
                field_span: context.token_span(node.token)?,
            },
            span,
        ),
        49 => {
            let name = name!();
            let mut fields = Vec::with_capacity(child_indices.len());
            for child in child_indices {
                fields.push(take_as!(values, *child, InitializerField));
            }
            expr(ExprKind::StructInit { name, fields }, span)
        }
        50 => Ok(AstValue::InitializerField(StructInitField {
            name: name!(),
            value: next!(Expr),
            span,
        })),
        51 => {
            let mut elements = Vec::with_capacity(child_indices.len());
            for child in child_indices {
                elements.push(take_as!(values, *child, Expr));
            }
            expr(ExprKind::ArrayLiteral(elements), span)
        }
        52 => expr(ExprKind::ListLiteral, span),
        53 => expr(ExprKind::PoolLiteral, span),
        54 => expr(ExprKind::MapLiteral, span),
        55 => expr(ExprKind::SetLiteral, span),
        56 => expr(ExprKind::QueueLiteral, span),
        57 => expr(ExprKind::RingLiteral, span),
        58 => {
            let receiver = next!(Expr);
            let x = next!(Expr);
            let x_span = x.span;
            let y = next!(Expr);
            expr(
                ExprKind::GridIndex {
                    receiver: Box::new(receiver),
                    x: Box::new(x),
                    y: Box::new(y),
                    x_span,
                },
                span,
            )
        }
        59 => {
            let value = next!(Expr);
            let ty = next!(Type);
            expr(
                ExprKind::Fit {
                    value: Box::new(value),
                    ty,
                    method_span: context.token_span(node.token)?,
                },
                span,
            )
        }
        60 => expr(ExprKind::Try(Box::new(next!(Expr))), span),
        61 => {
            let value = if child_indices.is_empty() {
                None
            } else {
                Some(Box::new(next!(Expr)))
            };
            expr(ExprKind::Return(value), span)
        }
        62 => expr(ExprKind::LoopExit(node.flags & F_VALUE != 0), span),
        63 => {
            let scrutinee = next!(Expr);
            let mut arms = Vec::with_capacity(child_indices.len().saturating_sub(1));
            while at < child_indices.len() {
                arms.push(next!(MatchArm));
            }
            expr(
                ExprKind::Match {
                    scrutinee: Box::new(scrutinee),
                    arms,
                },
                span,
            )
        }
        64 => {
            let pattern_node = child_node!(0);
            let pattern = take_pattern(values, child_indices[0])?;
            at = 1;
            let body = next!(Block);
            let pattern_span = context.span(pattern_node.start, pattern_node.end);
            Ok(AstValue::MatchArm(MatchArm {
                pattern,
                body,
                pattern_span,
                span,
            }))
        }
        65 => expr(
            ExprKind::ToLong {
                value: Box::new(next!(Expr)),
                method_span: context.token_span(node.token)?,
            },
            span,
        ),
        66 => {
            let ty = next!(Type);
            let value = next!(Expr);
            expr(
                ExprKind::Cast {
                    ty,
                    cast_span: context.token_span(node.token)?,
                    value: Box::new(value),
                },
                span,
            )
        }
        67 => {
            let value = next!(Expr);
            let op = if node.flags == 0 {
                UnaryOp::Neg
            } else {
                UnaryOp::Not
            };
            expr(
                ExprKind::Unary {
                    op,
                    operator_span: context.token_span(node.token)?,
                    value: Box::new(value),
                },
                span,
            )
        }
        68 => {
            let left = next!(Expr);
            let right = next!(Expr);
            let op = match node.flags {
                0 => BinaryOp::Add,
                1 => BinaryOp::Sub,
                2 => BinaryOp::Mul,
                3 => BinaryOp::Div,
                4 => BinaryOp::Rem,
                5 => BinaryOp::WrapAdd,
                6 => BinaryOp::WrapSub,
                7 => BinaryOp::WrapMul,
                8 => BinaryOp::Eq,
                9 => BinaryOp::Ne,
                10 => BinaryOp::Lt,
                11 => BinaryOp::Le,
                12 => BinaryOp::Gt,
                13 => BinaryOp::Ge,
                14 => BinaryOp::And,
                15 => BinaryOp::Or,
                16 => BinaryOp::BitAnd,
                17 => BinaryOp::BitOr,
                18 => BinaryOp::BitXor,
                19 => BinaryOp::Shl,
                20 => BinaryOp::Shr,
                21 => BinaryOp::Coalesce,
                _ => return Err("Binary operator is invalid".to_owned()),
            };
            expr(
                ExprKind::Binary {
                    op,
                    operator_span: context.token_span(node.token)?,
                    left: Box::new(left),
                    right: Box::new(right),
                },
                span,
            )
        }
        69 => {
            let condition = next!(Expr);
            let then_block = next!(Block);
            let else_block = if at < child_indices.len() {
                Some(next!(Block))
            } else {
                None
            };
            expr(
                ExprKind::If {
                    condition: Box::new(condition),
                    then_block,
                    else_block,
                },
                span,
            )
        }
        70 => Ok(AstValue::Pattern(Pattern::Wildcard)),
        71 => Ok(AstValue::Pattern(Pattern::Bool(
            node.flags & F_VALUE != 0,
            context.token_span(node.token)?,
        ))),
        72 => {
            let enum_name = if node.flags & F_HAS_ANNOTATION != 0 {
                Some(context.token_name(node.extra)?)
            } else {
                None
            };
            let name = context.token_name(node.token)?;
            let name_span = context.token_span(node.token)?;
            let mut bindings = Vec::with_capacity(child_indices.len());
            let mut binding_spans = Vec::with_capacity(child_indices.len());
            for child in child_indices {
                match take_value(values, *child)? {
                    AstValue::Binding(value, binding_span) => {
                        bindings.push(value);
                        binding_spans.push(binding_span);
                    }
                    _ => return Err("CasePattern child is not a binding".to_owned()),
                }
            }
            Ok(AstValue::Pattern(Pattern::Case {
                enum_name,
                name,
                name_span,
                bindings,
                binding_spans,
            }))
        }
        73 => {
            let name = name!();
            Ok(AstValue::Binding(Some((name, span)), span))
        }
        74 => Ok(AstValue::Binding(None, span)),
        _ => Err("node tag has no AST reconstruction rule".to_owned()),
    }
}

fn expr(kind: ExprKind, span: Span) -> Result<AstValue, String> {
    Ok(AstValue::Expr(Expr { kind, span }))
}

fn take_pattern(values: &mut [Option<AstValue>], child: usize) -> Result<Pattern, String> {
    match take_value(values, child)? {
        AstValue::Pattern(value) => Ok(value),
        AstValue::Expr(value) if matches!(&value.kind, ExprKind::Integer { .. }) => {
            Ok(Pattern::Integer(value))
        }
        AstValue::Expr(_) => Err("integer pattern child is not an integer".to_owned()),
        _ => Err("MatchArm child is not a pattern".to_owned()),
    }
}

fn build_type(
    context: &BuildContext<'_>,
    node: WireNode,
    children: &[usize],
    values: &mut [Option<AstValue>],
) -> Result<AstValue, String> {
    let (arg_count, const_count, array_count) = unpack_type_counts(node);
    let function = node.flags & F_TYPE_FN != 0;
    let (name, child_start) = if function {
        ("fn".to_owned(), 1)
    } else if node.flags & F_TYPE_UNIT != 0 {
        ("()".to_owned(), 0)
    } else if node.flags & F_TYPE_TEXT_BYTES != 0 {
        ("TextBytes".to_owned(), 0)
    } else {
        let names = context.extra_range(node.extra, node.meta0 as usize)?;
        let mut parts = Vec::with_capacity(names.len());
        for token in names {
            parts.push(context.token_name(*token)?);
        }
        (parts.join("."), 0)
    };
    let mut at = child_start;
    let function = if function {
        match take_value(values, children[0])? {
            AstValue::FunctionType(value) => Some(value),
            _ => return Err("function type child has the wrong AST type".to_owned()),
        }
    } else {
        None
    };
    let mut args = Vec::with_capacity(arg_count);
    let mut const_args = Vec::with_capacity(const_count);
    let mut array_caps = Vec::with_capacity(array_count);
    let pool_owner = name == "pool" && arg_count == 2 && const_count == 1;
    if pool_owner {
        args.push(take_as!(values, children[at], Type));
        at += 1;
        const_args.push(take_as!(values, children[at], Expr));
        at += 1;
        args.push(take_as!(values, children[at], Type));
        at += 1;
    } else {
        for _ in 0..arg_count {
            args.push(take_as!(values, children[at], Type));
            at += 1;
        }
        for _ in 0..const_count {
            const_args.push(take_as!(values, children[at], Expr));
            at += 1;
        }
    }
    for _ in 0..array_count {
        array_caps.push(take_as!(values, children[at], Expr));
        at += 1;
    }
    if at != children.len() {
        return Err("type child roles did not consume the node".to_owned());
    }
    let range = if node.flags & F_RANGE != 0 {
        let values = context.extra_range(node.anchor, 4)?;
        Some(TypeRangeAst {
            lower: signed_bound(context.literal(values[0])?, values[1] != 0)?,
            upper: signed_bound(context.literal(values[2])?, values[3] != 0)?,
            inclusive: node.flags & F_RANGE_INCLUSIVE != 0,
            span: context.token_span(node.token)?,
        })
    } else {
        None
    };
    let policy = if node.flags & F_POLICY_WRAP != 0 {
        RefinePolicy::Wrap
    } else if node.flags & F_POLICY_CLAMP != 0 {
        RefinePolicy::Clamp
    } else {
        RefinePolicy::Checked
    };
    Ok(AstValue::Type(TypeAst {
        name,
        args,
        const_args,
        array_caps,
        range,
        policy,
        function,
        span: context.node_span(node),
    }))
}

fn build_package(bytes: &[u8]) -> Result<Vec<RebuiltFile>, String> {
    let tables = read_tables(bytes)?;
    let names = validate_tables(&tables)?;
    let mut output = Vec::with_capacity(tables.files.len());
    for (file_id, file) in tables.files.iter().copied().enumerate() {
        let source_end = file.source_start + file.source_len;
        let source_bytes = &tables.source[file.source_start..source_end];
        let source = std::str::from_utf8(source_bytes)
            .map_err(|_| "source file is not UTF-8".to_owned())?
            .to_owned();
        let mut line_starts = vec![0usize];
        for (offset, byte) in source_bytes.iter().enumerate() {
            if *byte == b'\n' {
                line_starts.push(offset + 1);
            }
        }
        let context = BuildContext {
            tables: &tables,
            file,
            file_id,
            source: source_bytes,
            line_starts,
        };
        let token_end = file.token_start + file.token_count;
        let tokens = tables.tokens[file.token_start..token_end]
            .iter()
            .copied()
            .enumerate()
            .map(|(relative, token)| build_token(&context, file.token_start + relative, token))
            .collect::<Result<Vec<_>, _>>()?;
        let node_end = file.node_start + file.node_count;
        let mut values: Vec<Option<AstValue>> = (0..file.node_count).map(|_| None).collect();
        for index in file.node_start..node_end {
            let node = tables.nodes[index];
            let children = direct_children(&tables.nodes, file.node_start, index)?
                .into_iter()
                .map(|child| child - file.node_start)
                .collect::<Vec<_>>();
            let value = build_value(&context, index, node, &children, &mut values)?;
            values[index - file.node_start] = Some(value);
        }
        let root = values
            .last_mut()
            .and_then(Option::take)
            .ok_or_else(|| "Program root was not rebuilt".to_owned())?;
        let program = match root {
            AstValue::Program(program) => program,
            _ => return Err("binary tree root did not rebuild to Program".to_owned()),
        };
        if values.iter().any(Option::is_some) {
            return Err("AST reconstruction left unowned nodes".to_owned());
        }
        output.push(RebuiltFile {
            name: names[file_id].clone(),
            source,
            tokens,
            program,
        });
    }
    Ok(output)
}

pub(crate) fn read_package(bytes: &[u8]) -> Result<Vec<RebuiltFile>, String> {
    build_package(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn put_u32(bytes: &mut Vec<u8>, value: u32) {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    fn put_u64(bytes: &mut Vec<u8>, value: u64) {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    fn put_i64(bytes: &mut Vec<u8>, value: i64) {
        bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn minimal_tree() -> Vec<u8> {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(MAGIC);
        put_u32(&mut bytes, VERSION);
        put_u32(&mut bytes, HEADER_BYTES as u32);
        for value in [1, 0, 1, 1, 0, 0, 4] {
            put_u64(&mut bytes, value);
        }
        for value in [0, 4, 0, 0, 0, 1, 0, 1] {
            put_u64(&mut bytes, value);
        }
        bytes.extend_from_slice(b"a.nl");
        // One EOF token.
        put_u32(&mut bytes, 50);
        for value in [0, 0, 0, 1, 1] {
            put_u32(&mut bytes, value);
        }
        // One empty Program root.
        put_u32(&mut bytes, 0);
        put_u32(&mut bytes, 0);
        put_i64(&mut bytes, -1);
        put_u64(&mut bytes, 0);
        put_u64(&mut bytes, 0);
        put_i64(&mut bytes, 0);
        put_u64(&mut bytes, 1);
        for value in [-1, 0, 0, 0] {
            put_i64(&mut bytes, value);
        }
        bytes
    }

    fn set_u64(bytes: &mut [u8], offset: usize, value: u64) {
        bytes[offset..offset + 8].copy_from_slice(&value.to_le_bytes());
    }

    #[test]
    fn accepts_minimal_program_and_rejects_malformed_wire_fixtures() {
        let valid = minimal_tree();
        let parsed = read_package(&valid).expect("minimal Program tree is valid");
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].name, "a.nl");
        assert_eq!(
            parsed[0].program,
            Program {
                enums: vec![],
                structs: vec![],
                aliases: vec![],
                constants: vec![],
                globals: vec![],
                functions: vec![],
                tests: vec![],
            }
        );

        let cases: &[(&str, Box<dyn Fn(&mut Vec<u8>)>)] = &[
            (
                "truncated file",
                Box::new(|bytes| {
                    bytes.pop();
                }),
            ),
            (
                "wrong version",
                Box::new(|bytes| {
                    bytes[8..12].copy_from_slice(&2u32.to_le_bytes());
                }),
            ),
            (
                "index out of range",
                Box::new(|bytes| {
                    bytes[152..156].copy_from_slice(&1u32.to_le_bytes());
                }),
            ),
            (
                "overflowing source extent",
                Box::new(|bytes| {
                    set_u64(bytes, 88, u64::MAX);
                    set_u64(bytes, 96, 1);
                }),
            ),
            (
                "section size mismatch",
                Box::new(|bytes| {
                    set_u64(bytes, 24, 1);
                }),
            ),
            (
                "bad tag",
                Box::new(|bytes| {
                    bytes[164..168].copy_from_slice(&75u32.to_le_bytes());
                }),
            ),
            (
                "impossible subtree partition",
                Box::new(|bytes| {
                    set_u64(bytes, 204, 2);
                }),
            ),
            (
                "valid-size impossible tree",
                Box::new(|bytes| {
                    bytes[164..168].copy_from_slice(&1u32.to_le_bytes());
                }),
            ),
            (
                "span out of bounds",
                Box::new(|bytes| {
                    set_u64(bytes, 188, 1);
                }),
            ),
        ];
        for (label, mutate) in cases {
            let mut malformed = valid.clone();
            mutate(&mut malformed);
            let error = read_package(&malformed).expect_err(label);
            assert!(!error.is_empty(), "{label} returned an empty error");
        }
    }
}
