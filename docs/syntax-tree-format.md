# Parse dump format, version 1

`nlc parse <package> --tokens` and `nlc parse <package> --tree` are the byte-for-byte reference output for the self-hosted lexer and parser. They read every `.nl` file in the package in filename order, lex and parse it, and never run the checker. A successful parse with no dump option prints nothing. A lexical or parse error prints one diagnostic to stderr and exits with status 2, using `file:line:col: error: message`; the first syntax error stops the package. Columns are one-based byte columns, matching the lexer. File names in dumps and diagnostics are package-relative base names.

If both dump options are supplied, the command writes `== tokens ==`, the token dump, `== tree ==`, then the tree dump. Each individual dump starts with a `file "name.nl"` header for each source file. The header is metadata, not a token or tree node.

The parser accepts at most 256 source files per package, 16 MiB per file, 64 MiB total source bytes, 1,000,000 tokens per file, and 4,000,000 tokens per package. A tree has at most 2,000,000 nodes and 2,000,000 child edges per package. The lexer limits `()` and `[]` delimiter nesting to 2,048. The parser limits grouped-expression parentheses, type nesting, and active block nesting to 1,000; a function or test body is block level one. The parser's recursive expression paths also stop at 1,000 nested expression constructs, while a terminal value at that boundary is allowed.

The completed expression-tree walk enforces expression nesting at 1,000 for all expression shapes. Its root starts at depth zero for a root `print(...)` call and depth one otherwise. Calls, accesses, unary and binary operators, casts, `if`, `match`, and the other expression nodes with expression children add a level along the visited child path. The branch block of an `if` or `match` adds one level for its contents, so that construct and its branch block together count as one. An `else if` chain counts its initial `if` as clause one, with at most 1,000 clauses.

Nesting diagnostics use the byte position of the token that crosses the limit: the 1,001st grouped-parenthesis opener, cast opener, block opener, or type start; the operator token of the first over-limit unary or binary node found by the walk; and the start token for other expression nodes. An overlong `else if` chain is rejected at the `if` keyword of clause 1,001, while parsing. The completed-tree walk pushes expression children in a fixed order for each node kind and visits them last-in-first-out; it reports the first over-limit expression node it visits. Diagnostics use `expression nesting limit of 1000 exceeded`, `type nesting limit of 1000 exceeded`, or `block nesting limit of 1000 exceeded`, according to the exhausted limit. Parse work is bounded by 72,000,000 units, counted as source bytes + tokens + tree nodes + child edges. The parser reports only its first diagnostic, so the diagnostic limit is one. Empty source files are valid and produce an empty `Program` node.

## Token lines

After a file header, each token occupies one line:

```text
kind start_byte length line col text
```

Offsets and lengths are decimal byte counts. `line` and `col` identify the token's first byte; both start at 1. `text` is the raw source spelling, encoded as a JSON string. Thus a string token's text includes its quotes and escapes, and a newline token has text `"\n"`. `Eof` has an empty text and zero length at the end of the file. Whitespace and comments are omitted except for lexer `Newline` tokens. The lexer may omit newlines inside parentheses and brackets and coalesces repeated separators according to the existing lexer rules.

Token kind names are fixed and use these spellings: `Ident`, `Number`, `String`, `Newline`, `LParen`, `RParen`, `LBrace`, `RBrace`, `LBracket`, `RBracket`, `Comma`, `Colon`, `Semicolon`, `Dot`, `Question`, `QuestionDot`, `QuestionQuestion`, `Range`, `RangeInclusive`, `Arrow`, `FatArrow`, `Plus`, `Minus`, `Star`, `Slash`, `Percent`, `WrapPlus`, `WrapMinus`, `WrapStar`, `PlusEq`, `MinusEq`, `StarEq`, `SlashEq`, `PercentEq`, `ShrEq`, `Eq`, `EqEq`, `Bang`, `BangEq`, `Lt`, `Le`, `Gt`, `Ge`, `And`, `AndAnd`, `Or`, `OrOr`, `Caret`, `Shl`, `Shr`, and `Eof`.

## Tree lines

Every tree node occupies one line. Two spaces mark each depth. A node line is:

```text
Kind start_byte..end_byte [field=value ...]
```

Spans are half-open byte ranges: the start is included and the end is excluded. A syntax node spans from the start of its first token to the end of its last token, including punctuation, operators, delimiters, and the complete spans of its children. Thus each child lies within its parent, and siblings appear in source order without overlapping. Nodes can own tokens between their children, so a parent's span may be wider than the envelope of its child spans. The `Program` root is the exception: it spans the complete source file from byte zero through EOF, including trailing whitespace and comments. Parentheses have no node of their own: a parenthesised expression's node spans its parentheses too (`-(2)` dumps `Unary` over `-(2)` and `Integer` over `(2)`).

Three AST nodes represent syntax without their own source delimiters. A `Call name="default"` synthesized for a typed `let` without an initializer has a zero-width span immediately after the annotation. A `Block` synthesized for a match arm with an expression body has the same span as that expression. A `Block` synthesized for an `else if` has the same span as its nested `If`. These synthetic nodes still lie within their parents and preserve child source order. The formatter restores the written `pool<T, N, Owner>` type-argument order even though the AST stores its type and constant arguments separately. The file header identifies which file's byte offsets are being shown.

Fields are written in the order below. Boolean values are `true` or `false`; names, strings, generic names, and source snippets use JSON string escaping. JSON quoting escapes quote, backslash, newline, carriage return, tab, NUL, and other U+0000 through U+001F characters (`\u00xx`). Other Unicode characters are written as UTF-8 without escaping. Lists are bracketed and comma-separated with no spaces.

### Declaration and structural nodes

- `Program`: no fields; children are declarations.
- `Enum name="..."`: children are `EnumCase name="..."`; each payload type is a `PayloadType` child.
- `Struct name="..." generics=[...]`: children are `StructField name="..."`; each field has a `FieldType` type child and, when present, its default expression.
- `TypeAlias name="..."`: one `AliasedType` child.
- `Const name="..."`: a `DeclaredType` child followed by the value expression. `Global name="..." prefault=true|false` also records whether the `prefault` modifier was written.
- `Function name="..." recursive=true|false generics=[...]`: children are `Parameter` nodes, an optional `ResultType`, then the `Block` body.
- `Test name="..."`: children are `Parameter` nodes followed by the `Block` body.
- `Parameter name="..." mode=read|write`: one `ParameterType` child.
- `Block`: statement children followed by its optional tail expression.
- `StructField name="..."`: a `FieldType` child and optional default expression.
- `EnumCase name="..."`: zero or more `PayloadType` children.
- `InitializerField name="..."`: one value expression.
- `MatchArm`: a pattern child followed by its body `Block`.
- `FunctionType`: `FunctionTypeParameter mode=read|write` children, an optional `ResultType`, then `Effect` children.
- `Effect kind=out|env|fs.read|fs.write`: no child. `reads` and `writes` effects also have `path="..."`.

The following labels are `Type` nodes and have fields `name="..." range=... policy=checked|wrap|clamp`: `ParameterType`, `ResultType`, `Annotation`, `FieldType`, `PayloadType`, `AliasedType`, `DeclaredType`, `TypeArgument`, `FitType`, and `CastType`. A type without an integer refinement has `range=none`; otherwise range is printed in decimal as `lower..upper` or `lower..=upper`. Type children are generic type arguments, generic constant expressions, an optional `FunctionType`, then array capacities, in source order. `pool` arguments retain their written type, capacity, owner order.

### Statements and expression nodes

- `Let mutable=true|false name="..."`: optional `Annotation`, then value expression.
- `Assign op=...`: target expression, then value expression. `op` is one of `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `>>=`.
- `ReturnStatement`: optional value expression.
- `ExpressionStatement`: one expression.
- `For name="..." inclusive=true|false`: optional `Annotation`, start expression, end expression, body `Block`.
- `ForEach name="..." indexes=[...]`: collection expression, body `Block`.
- `Discard`: one expression. `Expect source="..."`: one expression.
- `BreakStatement`, `ContinueStatement`: no fields or children.
- `Unit`, `ListLiteral`, `PoolLiteral`, `MapLiteral`, `SetLiteral`, `QueueLiteral`, `RingLiteral`: no fields or children.
- `Integer magnitude=N negative=true|false long_suffix=true|false`: magnitude is the decoded, unsigned decimal value; sign and `L`/`l` suffix are separate fields.
- `Bool value=true|false`, `ByteString value="..."`, `Name name="..."`: literal or name value.
- `Call name="..."`, `QualifiedCase enum="..." case="..."`, `MethodCall name="..."`, `OptionalCall name="..."`: argument expressions follow in order; receiver is first for method and optional calls.
- `IndirectCall`: callee expression then argument expressions. `Index`: receiver then index. `GridIndex`: receiver, x index, y index. `Field name="..."`: receiver.
- `StructInit name="..."`: `InitializerField` children in written order.
- `Fit`: value then `FitType`. `Cast`: `CastType` then value. `Try` and `ToLong`: one value child.
- `Return`: optional value. `LoopExit kind=break|continue`: no children.
- `Match`: scrutinee followed by `MatchArm` children. `If`: condition, then block, optional else block.
- `Unary op=neg|not`: one value child. `Binary op=...`: left then right child. Binary names are `add`, `sub`, `mul`, `div`, `rem`, `wrap_add`, `wrap_sub`, `wrap_mul`, `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `and`, `or`, `bit_and`, `bit_or`, `bit_xor`, `shl`, `shr`, and `coalesce`.
- Pattern nodes are `WildcardPattern`, `BoolPattern value=true|false`, `CasePattern name="..." [enum="..."]`, and integer patterns (printed using the `Integer` node). Case payload positions are `PatternBinding name="..."` or `IgnoredPatternBinding`.

The parser decodes decimal, `0x` hexadecimal, and `0b` binary integer literals, removes underscores, and stores the magnitude as `u128`. The dump prints that magnitude before the checker applies `int` or `long` range rules. A magnitude through `2^128 - 1` therefore appears as its exact unsigned decimal value, even when a later check rejects it; a larger value is a syntax error. For example, `-0x80000000000000000000000000000000` is represented with magnitude `170141183460469231731687303715884105728`, `negative=true`, and `long_suffix=false`.

`ByteString` contains the decoded string bytes. Its value uses the JSON escaping above; since source files must be valid UTF-8 and the lexer decodes supported escapes to Unicode, the byte-string value is also valid UTF-8. An invalid UTF-8 source byte is reported at that byte's one-based byte column.
