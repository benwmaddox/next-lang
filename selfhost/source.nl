// Package processing follows compiler/src/driver.rs and syntax-tree-format.md:
// list and sort .nl entries; reject an empty package and >256 regular files;
// for each sorted file, read (16 MiB temporary), check per-file bytes, package
// bytes, UTF-8, lex (delimiter and per-file token checks), then package tokens.
// Output is staged until every file succeeds. Rooted Fs paths are relative to
// the current working directory; symlinks outside that root are not readable.

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
            err(Full) => return b"<source>",
        }
    }
    match value.validate_utf8() {
        ok(_) => value,
        err(_) => b"<source>",
    }
}

fn invalid_utf8_position(value: Bytes max 16777216, offset: long) -> SourcePosition {
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

fn fail_tool(env: Env, message: Ascii max 160) {
    match write_tool_error(env.err, message) {
        ok(_) => env.exit(3),
        err(_) => env.exit(3),
    }
}

fn fail_diagnostic(env: Env, result: Result<(), IoError>) {
    match result {
        ok(_) => env.exit(2),
        err(_) => env.exit(3),
    }
}

fn fail_lex(env: Env, file: Bytes max 4096, problem: LexProblem) {
    match write_lex_diagnostic(env.err, file, problem) {
        ok(_) => env.exit(2),
        err(_) => env.exit(3),
    }
}

fn load_and_lex(
    env: Env,
    package: Arg,
    entries: write list<DirEntry, MAX_DIRECTORY_ENTRIES>,
    source: grow Bytes max MAX_SOURCE_BYTES_PER_PACKAGE,
    files: write list<SourceFile, MAX_SOURCE_FILES>,
    tokens: write list<Token, TOKEN_STORAGE_CAPACITY>,
    delimiters: write list<DelimiterKind, MAX_DELIMITER_NESTING>,
    file_data: grow Bytes max MAX_SOURCE_BYTES_PER_FILE,
) {
    match env.fs.list_with_extension(package, "nl", entries) {
        ok(_) => (),
        err(_) => fail_tool(env, "cannot read package directory"),
    }

    var source_count = 0L
    for index in 0L..entries.count() {
        if entries[index].kind == FileKind.File { source_count += 1L }
    }
    if source_count == 0L { fail_tool(env, "package has no .nl source files") }
    if source_count > MAX_SOURCE_FILES {
        fail_diagnostic(env, write_file_count_limit(env.err))
    }

    for entry_index in 0L..entries.count() {
        let entry = entries[entry_index]
        if entry.kind == FileKind.File {
            let file_name = display_name(entry.name)
            let path = match env.fs.join(package, entry.name) {
                ok(value) => value,
                err(_) => { fail_tool(env, "cannot join source path"); env.exit(3) },
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
            if source.count() + file_length > MAX_SOURCE_BYTES_PER_PACKAGE {
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
                err(Full) => fail_tool(env, "package source buffer overflow"),
            }
            let first_token = tokens.count()
            let summary = match lex_file(source, base, file_length, tokens, delimiters) {
                ok(value) => value,
                err(problem) => { fail_lex(env, file_name, problem); env.exit(2) },
            }
            if tokens.count() > MAX_TOKENS_PER_PACKAGE {
                fail_diagnostic(env, write_package_token_limit(env.err, file_name))
            }
            let source_file = SourceFile { name: file_name, base, length: file_length, first_token, token_count: summary.token_count, end_line: summary.end_line, end_col: summary.end_col }
            match files.push(source_file) {
                ok(_) => (),
                err(Full) => fail_diagnostic(env, write_file_count_limit(env.err)),
            }
        }
    }
}
