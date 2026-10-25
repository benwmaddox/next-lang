# Self-hosted AST binary format

The self-hosted parser writes `NLASTB01`, version 1, to stdout for
`nlc run selfhost -- parse <package> --binary`. All integers are little-endian.
The Rust reader rejects unknown versions and checks the complete section layout
and every index before reconstructing an AST. The wire format stores values and
indexes; it does not expose any compiler or runtime memory layout.

## Section layout

The file is a 72-byte header followed by these sections in order:

| Section | Record size | Contents |
| --- | ---: | --- |
| Header | 72 bytes | Magic `NLASTB01` (8 bytes), version `u32`, header size `u32`, then seven `u64` counts: files, source bytes, tokens, nodes, extras, literals, name bytes. |
| File table | 64 bytes each | Eight `u64`s per file: name offset and length, source offset and length, token start and count, node start and count. Offsets address their respective sections. |
| Names | variable | Concatenated UTF-8 basenames in bytewise sorted order. Names contain no slash, backslash, or NUL. |
| Sources | variable | Original UTF-8 source bytes, concatenated in file-table order. |
| Tokens | 24 bytes each | `u32` kind, file-local byte start, byte length, file id, one-based line, and one-based byte column. The final EOF token has length zero and starts at the source end. Raw spellings are source slices, so no re-lexing is needed for `--tokens`. |
| Nodes | 80 bytes each | `u32` kind and flags; `i64` token index; `u64` start and end offsets; `i64` anchor; `u64` postorder subtree size; and `i64` extra, aux, meta0, and meta1 values. Node spans and ordinary anchors are file-local byte offsets. Token indexes are package-global. A type range uses `anchor` as an extra-table index. |
| Extras | 8 bytes each | Signed `i64` values. Their meaning is defined by the owning node kind below. |
| Literals | 16 bytes each | Four `u32` limbs, least significant first, for a full unsigned 128-bit integer magnitude. |

Files and their token and node slices are contiguous and ordered. Each file's
node slice is a postorder tree ending with one `Program` root. A node's subtree
size includes the node itself. The direct children are recovered by walking
backward from the parent using each child's subtree size, then reversing that
list. File ids are the sorted file-table positions and become `Span.file`.

Token kinds are numbered 0 through 50 in the order declared by `wire_token_tag`
in `selfhost/parse_output.nl`, ending with EOF. Node kinds are numbered 0
through 74 in the order declared by `wire_node_tag` there, beginning with
`Program` and ending with `IgnoredPatternBinding`. The Rust reader's exhaustive
tag match is the corresponding version-1 table. Node flags use the
`FLAG_*` values in `selfhost/parser.nl`; binary and assignment operator nodes
store the operator enum number directly in `flags`.

## Extra and metadata values

The `extra` field is the starting index for a node-specific slice in the extra
section; `aux` is usually a child or slice count. The reader validates each
slice against its section and checks token references against the owning file.

| Node kinds | `extra` | `aux` | `meta0` | `meta1` |
| --- | --- | --- | --- | --- |
| `Struct`, `Function` | first generic-name token index | generic-name count | 0 | 0 |
| `Effect` (`reads`/`writes`) | path token indexes | path component count | 0 | 0 |
| Named type kinds 15–24 | first qualified-name token index | 0 | qualified-name part count | packed child counts |
| Range type kinds 15–24 | first qualified-name token index | 0 | qualified-name part count | packed child counts; `anchor` points to four range values in extras |
| `ForEach` | index-name token indexes | index-name count | 0 | 0 |
| `Expect` | two absolute package-source offsets delimiting the original expression | 0 | 0 | 0 |
| `Integer` | literal-table index | 0 | 0 | 0 |
| `BytesLiteral` | string-token index (the string following `b`) | 0 | 0 | 0 |
| `QualifiedCase` | one extra value: case-name token index | argument count | 0 | 0 |
| `CasePattern` with enum qualifier | enum-name token index | 0 | 0 | 0 |
| `Call` | -1 | argument count | end offset of the callee expression, used for `Call.call_span` | 0 |

Packed type counts use 21 bits per count: argument types in bits 0–20,
constant arguments in bits 21–41, and array capacities in bits 42–62. For
`pool<T, N, Owner>`, child nodes remain in source order (`T`, `N`, `Owner`);
the reader validates these roles and places the two types in `TypeAst.args` and
the expression in `TypeAst.const_args`. Remaining trailing expressions are
array capacities. Function types put a `FunctionType` child first, followed by
array capacities. Unit types have no children. `Text bytes max N` is marked
with `F_TYPE_TEXT_BYTES` and reconstructs the `TextBytes` name.

The range extra slice is four signed values: lower literal index, lower-negative
flag, upper literal index, upper-negative flag. This preserves signed bounds
through the full `i128` range, including `i128::MIN`; the type node flags carry
inclusive/exclusive and wrap/clamp policy.

## AST fields and lossless reconstruction

Every span is rebuilt from its file-local byte offsets and the source's line
starts. The line is one plus the count of preceding newlines; the column is the
number of preceding bytes on that line plus one. This matches Rust's byte
columns, including UTF-8 source. A token span uses its token start and length.
Special spans are recorded as follows:

| AST fields | Wire source or reconstruction |
| --- | --- |
| `Span.file`, `line`, `col`, `start_offset`, `end_offset` | File id is the file-table index; offsets are wire token/node byte offsets or stated metadata offsets; line and byte column come from the source's line starts. `Span` is not an independent wire record. |
| `Program` declaration vectors | Direct declaration children, appended in source order to the matching vector. `Span` is not stored on `Program`. |
| `EnumDecl.name`, `cases`, `span`; `EnumCase.name`, `payload`, `span` | Name token and direct type/declaration children; node span. |
| `StructDecl` name, `generic_params`, fields, span | Name token; generic token slice; `StructFieldDecl` children; node span. |
| `StructFieldDecl.name`, `ty`, `default`, `span` | Name token; first type child; optional expression child; node span. |
| `StructInitField.name`, `value`, `span` | Name token and expression child; node span. Shorthand initialization uses the same name token for both fields. |
| `TypeAliasDecl.name`, `ty`, `span`; `ConstDecl.name`, `ty`, `value`, `span`; `GlobalDecl.name`, `ty`, `value`, `prefault`, `span` | Name token and ordered type/expression children; `GlobalDecl.prefault` is `F_PREFAULT`; node span. |
| `Function.name`, `recursive`, `generic_params`, `params`, `result`, `body`, `span`; `Test.name`, `params`, `body`, `span` | Function name token and generic token slice; test names are decoded from the test-name string token. Ordered children provide parameters, optional result, and final body. `Function.recursive` is `F_RECURSIVE`; node span. |
| `Param.name`, `mode`, `ty`, `span`; `FunctionTypeParam.mode`, `ty`, `span` | Name token for `Param`; `F_MODE_WRITE`/`F_MODE_GROW`; one type child; node span. |
| `TypeAst` name, args, constants, arrays, range, policy, function, span | Name token slice joined with dots; children grouped by packed counts and roles; four range extras; type flags; optional function child; node span. Unit and function names are synthesized from their type flags. |
| `TypeRangeAst.lower`, `upper`, `inclusive`, `span`; `RefinePolicy` | Four extras hold lower/upper literal indexes and sign flags; range flags hold inclusivity; span is the type-name token span. Wrap/clamp policy is encoded in type flags; absence means checked. |
| `FunctionTypeAst` params, result, effects, span | First `aux` children are parameters; remaining children contain at most one result and ordered effects; node span. |
| `FunctionEffectAst` variant, `path`, `span`, `node_span` | Effect flags and root/path token indexes. `Reads`/`Writes.path` is joined from its token indexes; `Out` and `Env` spans cover their keyword tokens; filesystem-wide effects use the node span; `Reads`/`Writes` retain the root token span and full effect node span. |
| `Block` statements, tail, span | Ordered statement children; the final child is the tail when `F_HAS_TAIL` is set; node span. |
| `Stmt.kind`, `span` | Statement node kind and node span. |
| `StmtKind::Let` fields and span | `F_MUTABLE`, `F_HAS_ANNOTATION`, name token, and ordered annotation/value children. An omitted typed initializer is a synthetic zero-width `Call` at the end of the annotation; its call span is reconstructed from the `let` token. |
| `StmtKind::Assign` target, op, operator span, value | Two expression children; numeric assignment operator in flags; operator token span. |
| `AssignOp`, `UnaryOp`, `BinaryOp`; `ParamMode` | Assignment, unary, and binary operator discriminants are stored in `flags`; parameter mode uses `F_MODE_WRITE`/`F_MODE_GROW`, with no bit meaning read. Refine policy is described above. |
| `StmtKind::Return(value)`, `Expr(value)`, `Discard(value)`, `Block(block)` | Node tag and ordered child; `Return.value` is optional. A block child is rebuilt as a `Block`; statement context wraps it as `StmtKind::Block`. |
| `StmtKind::For(name, annotation, start, end, inclusive, body)` | Name token; optional type child; ordered start/end expression and body children; `F_INCLUSIVE`; node span. |
| `StmtKind::ForEach(name, index_name, second_index_name, collection, body)` | Name and optional index-name token slice; collection and body children; node span. |
| `StmtKind::Break`, `Continue` | Leaf node kind and node span. |
| `StmtKind::Expect(value, source)` | Expression child; source offsets reconstruct `Expect.source`, retaining the `expect ` prefix; node span. |
| `Expr.kind`, `span` | Expression node tag and node span. |
| `ExprKind::Unit`, `ListLiteral`, `PoolLiteral`, `MapLiteral`, `SetLiteral`, `QueueLiteral`, `RingLiteral` | Leaf node kind. |
| `ExprKind::Integer(magnitude, negative, long_suffix)`, `Bool(value)` | Integer magnitude from four limbs and sign/suffix flags; bool value flag. |
| `ExprKind::ByteString(bytes, has_non_ascii_hex_escape)`, `BytesLiteral(bytes)` | Decoded string token bytes and hex-origin flag; bytes literal's string token is decoded without UTF-8 conversion. |
| `ExprKind::Take(value)`, `Try(value)`, `Return(value)`, `LoopExit(is_break)` | Ordered child, optional child for `Return`, or bool value flag for `LoopExit`. |
| `ExprKind::Name(name)`, `Call(name, call_span, args)` | Name token and ordered expression children. `Call.call_span` ends at `meta0`, preserving grouped and multiline callees. |
| `ExprKind::IndirectCall(callee, args)`, `QualifiedCase(enum_name, case_name, case_span, args)` | Ordered expression children; name/case tokens and exact case token span. |
| `ExprKind::MethodCall(receiver, name, method_span, args)`, `OptionalCall(receiver, name, method_span, args)` | Receiver and argument children, name token, and exact method token span. |
| `ExprKind::Index(receiver, index, index_span)`, `Field(receiver, name, field_span)` | Ordered expression child/children and name token; index span equals the index expression span; field span is its token span. |
| `ExprKind::StructInit(name, fields)`, `ArrayLiteral(elements)` | Name token and ordered `StructInitField` children; array elements are ordered expression children. |
| `ExprKind::GridIndex(receiver, x, y, x_span)` | Ordered receiver/x/y children; `x_span` is reconstructed from the x expression. |
| `ExprKind::Fit(value, ty, method_span)`, `Cast(ty, cast_span, value)` | Ordered type/expression children and exact method/cast token spans. |
| `ExprKind::Match(scrutinee, arms)`, `MatchArm(pattern, body, pattern_span, span)` | Scrutinee and ordered arm children; arm and pattern spans are reconstructed from their node/token spans. |
| `ExprKind::ToLong(value, method_span)` | Expression child and exact method token span. |
| `ExprKind::Unary(op, operator_span, value)`, `Binary(op, operator_span, left, right)` | Operator enum number in flags, ordered expression children, and exact operator token span. |
| `ExprKind::If(condition, then_block, else_block)` | Condition and ordered block children; `F_HAS_ELSE` records whether the optional else block exists. |
| `Pattern::Wildcard`, `Integer(expr)`, `Bool(value, span)` | Pattern node kind; integer expression child; bool value flag and token span. |
| `Pattern::Case(enum_name, name, name_span, bindings, binding_spans)` | Case and optional enum-name tokens; binding children and exact binding token spans. An ignored binding is a distinct leaf, preserving each `None` binding slot. |
| `StmtKind::Block` and its `Block` | A block node reconstructs as `Block` when used as a block child. When used as a statement child it is wrapped as `StmtKind::Block` with the same span, preserving both AST values represented by one syntax node. |

String tokens contain raw source spelling. The reader decodes `\\`, `\"`, `\n`,
`\t`, `\0`, and `\xNN` to the same byte values as the Rust lexer. For a normal
string, the AST's byte vector is retained; test names decode to UTF-8 text.
Byte-string `has_non_ascii_hex_escape` is checked against the decoded token.
Identifiers and file names must be valid UTF-8; byte strings may contain any
byte produced by a valid escape.

## Validation and resource bounds

The reader checks the header and exact total file size before reserving table
storage. It caps the wire at 1 GiB, files at 4096, source at 256 MiB, tokens at
5,000,000, nodes at 4,000,000, extras at 8,000,000, literals at 4,000,000,
file-name bytes at 1 MiB, tree depth at 4096, and reader work at 300,000,000
units. The parse policy applies the Rust parse command's package limits before
the wire is written: 256 files, 16 MiB per file, 64 MiB per package, 4,000,000
tokens, 2,000,000 nodes and edges, and 72,000,000 work units. Both commands
also use the shared 1,000,000-token per-file lexer limit and 1000-level parser
nesting limits. Compile policy skips the package parse-only limits; the current
self-host buffers cap compile input at 4096 files, 16 MiB + 1 byte per file,
and 64 MiB + 1 byte total source, with storage for 5,000,000 tokens and
4,000,000 nodes. The Rust compile path currently imposes no matching file or
source-byte caps. It validates ordered file
ownership, UTF-8 names, sources and token boundaries, string escapes, token and
node spans, line/column metadata, tags and flags, all table references, child
counts and roles, subtree partitions, declaration roots, and type/range/string
metadata before AST reconstruction. Reconstruction is iterative in node order;
it does not recurse through the input tree.

## Paths and symlinks

The package path is canonicalized by `nlc`. The child runs from the canonical
package's parent and receives only the package basename, as rooted filesystem
access disallows absolute paths. The rooted I/O boundary is that parent
directory: source entries must resolve to regular files beneath it. Symlinks
may point out of the package directory to a sibling file beneath the parent;
links that escape the parent and magic links are excluded. The Rust source
selector applies the same rule.
