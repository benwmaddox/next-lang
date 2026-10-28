// Every command uses one package policy: list and sort .nl entries; reject an
// empty package and more than 256 regular files; then check per-file and
// package bytes, UTF-8, lexing and token counts, parsing, nodes, edges, work,
// and nesting in order. Output is staged until every file succeeds. Rooted Fs
// paths are relative to the current working directory; outside symlinks fail.

enum LexProblemKind {
    UnexpectedCharacter,
    UnsupportedEscape,
    InvalidHexEscape,
    NewlineInString,
    UnclosedString,
    DelimiterNesting,
    UnmatchedClosing,
    UnclosedParen,
    UnclosedBracket,
    TokenLimit,
}

enum DelimiterKind {
    Parenthesis,
    Bracket,
}

struct LexProblem {
    kind: LexProblemKind
    start: long
    line: long
    col: long
    byte: byte
}

struct SourceFile {
    name: Bytes max 4096
    base: long
    length: long
    first_token: long
    token_count: long
    end_line: long
    end_col: long
    tree_root: long
}

struct SourcePosition {
    line: long
    col: long
}

fn display_name(path: Path) -> Bytes max 4096 {
    var value: Bytes max 4096 = Bytes.empty()
    for index in 0L..path.count() {
        match value.push(path[index]) {
            ok(_) => (),
            err(_) => return b"<source>",
        }
    }
    match value.validate_utf8() {
        ok(_) => value,
        err(_) => b"<source>",
    }
}

fn invalid_utf8_position(value: Bytes max FILE_SOURCE_CAPACITY, offset: long) -> SourcePosition {
    var line = 1L
    var col = 1L
    for index in 0L..offset {
        if value[index] == 10 {
            line += 1L
            col = 1L
        } else {
            col += 1L
        }
    }
    SourcePosition { line, col }
}

fn argument_equals(argument: Arg, expected: Ascii max 32) -> bool {
    if argument.count() != expected.len() { return false }
    for index in 0L..expected.len() {
        match argument.get(index) {
            some(value) => {
                if value != expected.bytes()[index] { return false }
            },
            none => return false,
        }
    }
    true
}

fn write_tool_error(out: Out, message: Ascii max 160) -> Result<(), IoError> {
    out.write(b"nlc: tool failure: ")?
    out.write(message.bytes())?
    out.write(b"\n")
}

fn write_diagnostic(
    out: Out,
    file: Bytes max 4096,
    line: long,
    col: long,
    message: Ascii max 160,
) -> Result<(), IoError> {
    out.write(file)?
    out.write(b":")?
    out.write(str(line).bytes())?
    out.write(b":")?
    out.write(str(col).bytes())?
    out.write(b": error: ")?
    out.write(message.bytes())?
    out.write(b"\n")
}

fn write_lex_diagnostic(
    out: Out,
    file: Bytes max 4096,
    problem: LexProblem,
) -> Result<(), IoError> {
    out.write(file)?
    out.write(b":")?
    out.write(str(problem.line).bytes())?
    out.write(b":")?
    out.write(str(problem.col).bytes())?
    out.write(b": error: ")?
    if problem.kind == LexProblemKind.UnexpectedCharacter {
        out.write(b"unexpected character '")?
        if problem.byte < 128 {
            var character: Bytes max 2 = Bytes.empty()
            character.push(problem.byte).unwrap()
            out.write(character)?
        } else if problem.byte < 192 {
            var character: Bytes max 2 = Bytes.empty()
            character.push(194).unwrap()
            character.push(problem.byte).unwrap()
            out.write(character)?
        } else {
            var character: Bytes max 2 = Bytes.empty()
            character.push(195).unwrap()
            character.push(problem.byte - 64).unwrap()
            out.write(character)?
        }
        out.write(b"'; remove it or use a supported operator")?
    } else {
        let message: Ascii max 160 = match problem.kind {
            LexProblemKind.UnexpectedCharacter => "unexpected character",
            LexProblemKind.UnsupportedEscape => "unsupported string escape; use \", \\\\, \\n, \\t, \\0, or \\xNN",
            LexProblemKind.InvalidHexEscape => "\\x escape needs exactly two hexadecimal digits",
            LexProblemKind.NewlineInString => "string literals cannot contain a newline; escape it as \\n",
            LexProblemKind.UnclosedString => "unclosed string literal; add a closing quote",
            LexProblemKind.DelimiterNesting => "delimiter nesting limit of 2048 exceeded",
            LexProblemKind.UnmatchedClosing => "unmatched closing delimiter; add a matching opener",
            LexProblemKind.UnclosedParen => "unclosed '('; add a matching ')'",
            LexProblemKind.UnclosedBracket => "unclosed '['; add a matching ']'",
            LexProblemKind.TokenLimit => "token limit of 1000000 per file exceeded",
        }
        out.write(message.bytes())?
    }
    out.write(b"\n")
}

fn write_source_invalid_utf8(
    out: Out,
    file: Bytes max 4096,
    position: SourcePosition,
) -> Result<(), IoError> {
    write_diagnostic(out, file, position.line, position.col, "source is not valid UTF-8; save the file as UTF-8")
}

fn write_file_byte_limit(out: Out, file: Bytes max 4096) -> Result<(), IoError> {
    write_diagnostic(out, file, 1L, 1L, "source byte limit of 16777216 per file exceeded")
}

fn write_package_byte_limit(out: Out, file: Bytes max 4096) -> Result<(), IoError> {
    write_diagnostic(out, file, 1L, 1L, "source byte limit of 67108864 per package exceeded")
}

fn write_package_token_limit(out: Out, file: Bytes max 4096) -> Result<(), IoError> {
    write_diagnostic(out, file, 1L, 1L, "token limit of 4000000 per package exceeded")
}

fn write_file_count_limit(out: Out) -> Result<(), IoError> {
    write_diagnostic(out, b"<package>", 1L, 1L, "source file limit of 256 per package exceeded")
}

fn fail_tool(env: Env, message: Ascii max 160) -> never {
    match write_tool_error(env.err, message) {
        ok(_) => env.exit(3),
        err(_) => env.exit(3),
    }
}

fn fail_diagnostic(env: Env, result: Result<(), IoError>) -> never {
    match result {
        ok(_) => env.exit(2),
        err(_) => env.exit(3),
    }
}

fn fail_lex(env: Env, file: Bytes max 4096, problem: LexProblem) -> never {
    match write_lex_diagnostic(env.err, file, problem) {
        ok(_) => env.exit(2),
        err(_) => env.exit(3),
    }
}

fn is_parse_limit_error(kind: ParseProblemKind) -> bool {
    kind == ParseProblemKind.TypeDepth ||
    kind == ParseProblemKind.BlockDepth ||
    kind == ParseProblemKind.ExpressionDepth ||
    kind == ParseProblemKind.CastDepth ||
    kind == ParseProblemKind.ParseNodeLimit ||
    kind == ParseProblemKind.ParseEdgeLimit ||
    kind == ParseProblemKind.ParseWorkLimit
}

// Parsing is deliberately interleaved with each file's read and lex stages.
// This mirrors driver.rs so an earlier syntax error wins over a later file
// failure, and successful trees remain staged until the package is complete.
fn load_and_parse(
    env: Env,
    package: Arg,
    entries: write list<DirEntry, MAX_DIRECTORY_ENTRIES>,
    source: grow Bytes max SOURCE_BUFFER_CAPACITY,
    files: write list<SourceFile, MAX_SOURCE_FILES>,
    tokens: write list<Token, TOKEN_STORAGE_CAPACITY>,
    delimiters: write list<DelimiterKind, MAX_DELIMITER_NESTING>,
    file_data: grow Bytes max FILE_SOURCE_CAPACITY,
    tables: write ParseTables,
    ignore_syntax_errors: bool,
) {
    match env.fs.list_with_extension(package, "nl", entries) {
        ok(_) => (),
        err(error) => {
            if error == IoError.TooMany {
                fail_diagnostic(env, write_file_count_limit(env.err))
            } else {
                fail_tool(env, "cannot read package directory")
            }
        },
    }

    var source_count = 0L
    for index in 0L..entries.count() {
        if entries[index].kind == FileKind.File { source_count += 1L }
    }
    if source_count == 0L { fail_tool(env, "package has no .nl source files") }
    if source_count > MAX_SOURCE_FILES {
        fail_diagnostic(env, write_file_count_limit(env.err))
    }

    var package_bytes = 0L
    var package_tokens = 0L
    var package_nodes = 0L
    var package_edges = 0L
    for entry_index in 0L..entries.count() {
        let entry = entries[entry_index]
        if entry.kind == FileKind.File {
            let file_name = display_name(entry.name)
            let path = match env.fs.join(package, entry.name) {
                ok(value) => value,
                err(_) => fail_tool(env, "cannot join source path"),
            }
            match env.fs.read(path, file_data) {
                ok(_) => (),
                err(error) => {
                    if error == IoError.TooLarge {
                        fail_diagnostic(env, write_file_byte_limit(env.err, file_name))
                    } else {
                        fail_tool(env, "cannot read source file")
                    }
                },
            }
            let file_length = file_data.count()
            if file_length > MAX_SOURCE_BYTES_PER_FILE {
                fail_diagnostic(env, write_file_byte_limit(env.err, file_name))
            }
            package_bytes += file_length
            if package_bytes > MAX_SOURCE_BYTES_PER_PACKAGE {
                fail_diagnostic(env, write_package_byte_limit(env.err, file_name))
            }
            match file_data.validate_utf8() {
                ok(_) => (),
                err(error) => {
                    let position = invalid_utf8_position(file_data, error.valid_up_to)
                    fail_diagnostic(env, write_source_invalid_utf8(env.err, file_name, position))
                },
            }

            let base = source.count()
            match source.try_append(file_data) {
                ok(_) => (),
                err(_) => fail_tool(env, "package source buffer overflow"),
            }
            let first_token = tokens.count()
            let summary = match lex_file(source, base, file_length, tokens, delimiters) {
                ok(value) => value,
                err(problem) => {
                    let current_file_tokens = tokens.count() - first_token
                    if problem.kind == LexProblemKind.TokenLimit &&
                        tokens.count() >= MAX_TOKENS_PER_PACKAGE &&
                        current_file_tokens < MAX_TOKENS_PER_FILE {
                        fail_diagnostic(env, write_package_token_limit(env.err, file_name))
                    } else {
                        fail_lex(env, file_name, problem)
                    }
                },
            }
            package_tokens += summary.token_count
            if package_tokens > MAX_TOKENS_PER_PACKAGE {
                fail_diagnostic(env, write_package_token_limit(env.err, file_name))
            }

            let prior_nodes = tables.nodes.count()
            let root = match parse_file(source, tokens, tables, base, file_length, first_token, summary.token_count) {
                ok(value) => value,
                err(problem) => {
                    if ignore_syntax_errors && !is_parse_limit_error(problem.kind) { -1L }
                    else { fail_parse(env, source, tokens, file_name, base, file_length, problem) }
                },
            }
            if root >= 0L {
                let file_nodes = tables.nodes.count() - prior_nodes
                if file_nodes > MAX_TREE_NODES {
                    fail_parse_limit(env, file_name, "node limit of 2000000 per package exceeded")
                }
                package_nodes += file_nodes
                if package_nodes > MAX_TREE_NODES {
                    fail_parse_limit(env, file_name, "node limit of 2000000 per package exceeded")
                }
                // Each file contributes one Program node, so edges are always
                // nodes - files. The node cap makes edge overflow unreachable.
                let file_edges = file_nodes - 1L
                package_edges += file_edges
                if package_edges > MAX_TREE_EDGES {
                    fail_parse_limit(env, file_name, "child edge limit of 2000000 per package exceeded")
                }
                let work = package_bytes + package_tokens + package_nodes + package_edges
                if work > MAX_PARSE_WORK {
                    fail_parse_limit(env, file_name, "parse work limit of 72000000 units per package exceeded")
                }
            }
            let source_file = SourceFile { name: file_name, base, length: file_length, first_token, token_count: summary.token_count, end_line: summary.end_line, end_col: summary.end_col, tree_root: root }
            match files.push(source_file) {
                ok(_) => (),
                err(_) => fail_diagnostic(env, write_file_count_limit(env.err)),
            }
        }
    }
}
