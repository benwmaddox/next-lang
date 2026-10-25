struct DumpTask {
    node: long
    depth: long
    role: long
}

fn write_source_range(out: Out, source: Bytes max 67108864, start: long, end: long) -> Result<(), IoError> {
    var buffer: Bytes max 1024 = Bytes.empty()
    for index in start..end {
        buffer.push(source[index]).unwrap()
        if buffer.count() == 1024L {
            out.write(buffer)?
            buffer = Bytes.empty()
        }
    }
    if buffer.count() > 0L { out.write(buffer)? }
    ok(())
}

fn write_token_raw(
    out: Out,
    source: Bytes max 67108864,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    base: long,
    token: long,
) -> Result<(), IoError> {
    if token < 0L || token >= tokens.count() { return ok(()) }
    write_source_range(out, source, base + tokens[token].start, base + tokens[token].start + tokens[token].length)
}

fn parse_error_position(source: Bytes max 67108864, base: long, length: long, offset: long) -> SourcePosition {
    let stop = if offset < 0L { 0L } else if offset > length { length } else { offset }
    var line = 1L
    var col = 1L
    for index in 0L..stop {
        if source[base + index] == 10 {
            line += 1L
            col = 1L
        } else {
            col += 1L
        }
    }
    SourcePosition { line, col }
}

fn write_parse_diagnostic(
    out: Out,
    source: Bytes max 67108864,
    file: Bytes max 4096,
    base: long,
    length: long,
    error: ParseError,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
) -> Result<(), IoError> {
    let position = parse_error_position(source, base, length, error.offset)
    out.write(file)?
    out.write(b":")?
    out.write(str(position.line).bytes())?
    out.write(b":")?
    out.write(str(position.col).bytes())?
    out.write(b": error: ")?
    write_parse_message(out, source, base, error, tokens)?
    out.write(b"\n")
}

fn write_parse_message(
    out: Out,
    source: Bytes max 67108864,
    base: long,
    error: ParseError,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
) -> Result<(), IoError> {
    let token = error.token
    match error.kind {
        ParseProblemKind.ExpectedFunction => out.write(b"expected a function declaration starting with 'fn'")?,
        ParseProblemKind.ExpectedFnAfterRecursive => out.write(b"expected 'fn' after 'recursive'")?,
        ParseProblemKind.ExpectedFunctionName => out.write(b"expected a function name after 'fn'")?,
        ParseProblemKind.ExpectedGenericName => out.write(b"expected a generic parameter name")?,
        ParseProblemKind.ExpectedEnumName => out.write(b"expected an enum name after 'enum'")?,
        ParseProblemKind.ExpectedTypePathPart => out.write(b"expected a name after '.' in a type path")?,
        ParseProblemKind.ExpectedFunctionParen => out.write(b"expected '(' after the function name")?,
        ParseProblemKind.ExpectedConstEq => out.write(b"expected '=' in a constant declaration")?,
        ParseProblemKind.ExpectedStructOpen => out.write(b"expected '{' after the struct name")?,
        ParseProblemKind.ExpectedStructClose => out.write(b"expected '}' to close the struct")?,
        ParseProblemKind.ExpectedEnumOpen => out.write(b"expected '{' after the enum name")?,
        ParseProblemKind.ExpectedEnumClose => out.write(b"expected '}' to close the enum")?,
        ParseProblemKind.ExpectedCollectionOpen => out.write(b"expected '{' after a collection name")?,
        ParseProblemKind.ExpectedCollectionClose => out.write(b"expected '}' after an empty collection literal")?,
        ParseProblemKind.ExpectedStructLiteralOpen => out.write(b"expected '{' to start a struct literal")?,
        ParseProblemKind.ExpectedStructLiteralClose => out.write(b"expected '}' to close the struct literal")?,
        ParseProblemKind.ExpectedEnumComma => out.write(b"expected a comma or newline between enum cases")?,
        ParseProblemKind.EmptyList => out.write(b"list literals start empty; push values after construction")?,
        ParseProblemKind.EmptyPool => out.write(b"pool literals start empty; add values after construction")?,
        ParseProblemKind.EmptyMap => out.write(b"map literals start empty; set values after construction")?,
        ParseProblemKind.EmptySet => out.write(b"set literals start empty; add values after construction")?,
        ParseProblemKind.EmptyQueue => out.write(b"queue literals start empty; push values after construction")?,
        ParseProblemKind.EmptyRing => out.write(b"ring literals start empty; push values after construction")?,
        ParseProblemKind.ExpectedListClose => out.write(b"expected '}' after the empty list literal")?,
        ParseProblemKind.ExpectedPoolClose => out.write(b"expected '}' after the empty pool literal")?,
        ParseProblemKind.ExpectedMapClose => out.write(b"expected '}' after the empty map literal")?,
        ParseProblemKind.ExpectedSetClose => out.write(b"expected '}' after the empty set literal")?,
        ParseProblemKind.ExpectedQueueClose => out.write(b"expected '}' after the empty queue literal")?,
        ParseProblemKind.ExpectedRingClose => out.write(b"expected '}' after the empty ring literal")?,
        ParseProblemKind.ExpectedConstName => out.write(b"expected a constant name")?,
        ParseProblemKind.ExpectedGlobalName => out.write(b"expected a global name")?,
        ParseProblemKind.ExpectedStructName => out.write(b"expected a struct name")?,
        ParseProblemKind.ExpectedTypeName => out.write(b"expected a type name")?,
        ParseProblemKind.ExpectedAliasEq => out.write(b"expected '=' in a type alias")?,
        ParseProblemKind.ExpectedConstColon => out.write(b"expected ':' after the constant name")?,
        ParseProblemKind.ExpectedGlobalColon => out.write(b"expected ':' after the global name")?,
        ParseProblemKind.LockedGlobal => out.write(b"'locked' globals are unsupported; remove the modifier instead of silently ignoring it")?,
        ParseProblemKind.ExpectedGlobalEq => out.write(b"expected '=' in a global declaration")?,
        ParseProblemKind.DuplicatePrefault => out.write(b"'prefault' may only appear once on a global")?,
        ParseProblemKind.EnumEmpty => out.write(b"an enum needs at least one case")?,
        ParseProblemKind.ExpectedComma => out.write(b"expected a comma or newline between struct fields")?,
        ParseProblemKind.ExpectedBrace => out.write(b"expected '{'")?,
        ParseProblemKind.ExpectedEnumCase => out.write(b"expected an enum case name")?,
        ParseProblemKind.ExpectedEnumPayloadClose => out.write(b"expected ')' after enum payload types")?,
        ParseProblemKind.ExpectedTestName => out.write(b"expected a quoted test name after 'test'")?,
        ParseProblemKind.ExpectedTestParamName => out.write(b"expected a test parameter name")?,
        ParseProblemKind.ExpectedTestParamColon => out.write(b"expected ':' after the test parameter name")?,
        ParseProblemKind.ExpectedTestParamClose => out.write(b"expected ')' after the test parameters")?,
        ParseProblemKind.ExpectedParameterName => out.write(b"expected a parameter name")?,
        ParseProblemKind.ExpectedParameterColon => out.write(b"expected ':' after the parameter name")?,
        ParseProblemKind.ExpectedParameterClose => out.write(b"expected ')' after the parameters")?,
        ParseProblemKind.ExpectedResult => out.write(b"expected a result type")?,
        ParseProblemKind.ExpectedBlock => out.write(b"expected a block")?,
        ParseProblemKind.ExpectedSeparator => out.write(b"expected a newline or ';' after the function")?,
        ParseProblemKind.ExpectedFieldName => out.write(b"expected a field name")?,
        ParseProblemKind.ExpectedFieldColon => out.write(b"expected ':' after the field name")?,
        ParseProblemKind.ExpectedTypeClose => out.write(b"expected '>'")?,
        ParseProblemKind.ExpectedGenericClose => out.write(b"expected '>' after generic parameters")?,
        ParseProblemKind.ExpectedTypeArgsClose => out.write(b"expected '>' after generic type arguments")?,
        ParseProblemKind.ExpectedFitTypeClose => out.write(b"expected '>' after the fit type")?,
        ParseProblemKind.TypeDepth => out.write(b"type nesting limit of 1000 exceeded")?,
        ParseProblemKind.BlockDepth => out.write(b"block nesting limit of 1000 exceeded")?,
        ParseProblemKind.ExpressionDepth => out.write(b"expression nesting limit of 1000 exceeded")?,
        ParseProblemKind.CastDepth => out.write(b"expression nesting limit of 1000 exceeded")?,
        ParseProblemKind.ExpectedGridWidth => out.write(b"expected a width after the grid element type")?,
        ParseProblemKind.ExpectedGridHeight => out.write(b"expected a height after the grid width")?,
        ParseProblemKind.ExpectedMapValue => out.write(b"expected a value type after the map key type")?,
        ParseProblemKind.ExpectedMapCapacity => out.write(b"expected a capacity after the map value type")?,
        ParseProblemKind.ExpectedSetCapacity => out.write(b"expected a capacity after the set key type")?,
        ParseProblemKind.ExpectedTextMax => out.write(b"expected 'max' after 'Text bytes'")?,
        ParseProblemKind.ExpectedTypeRange => out.write(b"expected '..' or '..=' in a range type")?,
        ParseProblemKind.RangeBound => out.write(b"range bounds must be integer literals")?,
        ParseProblemKind.RangeTooLarge => out.write(b"range bound is too large to represent")?,
        ParseProblemKind.PolicyNeedsRange => out.write(b"'wrap' and 'clamp' need an integer range type")?,
        ParseProblemKind.ExpectedFunctionTypeParen => out.write(b"expected '(' after 'fn'")?,
        ParseProblemKind.UnsupportedGenericFunctionType => out.write(b"owner- or capacity-generic function values are not supported yet; use a concrete signature")?,
        ParseProblemKind.ExpectedFunctionTypeClose => out.write(b"expected ')' after function type parameters")?,
        ParseProblemKind.ExpectedEffect => out.write(b"expected an effect after 'effects'")?,
        ParseProblemKind.ExpectedFsEffect => out.write(b"expected '.read' or '.write' after 'fs'")?,
        ParseProblemKind.ExpectedFsOperation => out.write(b"expected 'read' or 'write' after 'fs.'")?,
        ParseProblemKind.BadFsEffect => out.write(b"filesystem effects are 'fs.read' and 'fs.write'")?,
        ParseProblemKind.ExpectedReadsPath => out.write(b"expected a global path after 'reads'")?,
        ParseProblemKind.ExpectedWritesPath => out.write(b"expected a global path after 'writes'")?,
        ParseProblemKind.ExpectedEffectPathPart => out.write(b"expected a field name after '.'")?,
        ParseProblemKind.UnknownEffect => {
            out.write(b"unknown function effect '")?
            write_token_raw(out, source, tokens, base, token)?
            out.write(b"'; use out, env, fs.read, fs.write, reads global, or writes global")?
        },
        ParseProblemKind.DuplicateGeneric => {
            out.write(b"generic parameter '")?
            write_token_raw(out, source, tokens, base, token)?
            out.write(b"' is repeated")?
        },
        ParseProblemKind.ExpectedBlockOpen => out.write(b"expected '{' to start a block")?,
        ParseProblemKind.ExpectedBlockClose => out.write(b"expected '}' to close this block")?,
        ParseProblemKind.ExpectedStmtSeparator => out.write(b"expected a newline or ';' between statements")?,
        ParseProblemKind.ExpectedExpectBool => out.write(b"expected a bool expression after 'expect'")?,
        ParseProblemKind.ExpectedLetName => out.write(b"expected a binding name after 'let' or 'var'")?,
        ParseProblemKind.ExpectedLetValue => out.write(b"expected '=' and an initial value; an omitted value needs an explicit type with a valid default")?,
        ParseProblemKind.ExpectedStackPeakOpen => out.write(b"expected '(' after 'stack_peak'")?,
        ParseProblemKind.ExpectedStackPeakName => out.write(b"expected a function name inside 'stack_peak'")?,
        ParseProblemKind.ExpectedStackPeakClose => out.write(b"expected ')' after the function name")?,
        ParseProblemKind.ExpectedStackPeakLt => out.write(b"expected '<' after stack_peak(function); write a byte budget such as '2 MB'")?,
        ParseProblemKind.ExpectedStackPeakBudget => out.write(b"expected a byte budget after '<'")?,
        ParseProblemKind.StackPeakTooLarge => out.write(b"stack_peak byte budget is too large; use a smaller value")?,
        ParseProblemKind.BadAssignTarget => out.write(b"the left side of an assignment must be a variable name")?,
        ParseProblemKind.ExpectedForName => out.write(b"expected a counter name after 'for'")?,
        ParseProblemKind.ExpectedIndexName => out.write(b"expected an index name after ','")?,
        ParseProblemKind.ExpectedSecondIndex => out.write(b"expected a second index name after ','")?,
        ParseProblemKind.TooManyForBindings => out.write(b"collection loops support at most three bindings")?,
        ParseProblemKind.ExpectedForIn => out.write(b"expected 'in' after the loop counter")?,
        ParseProblemKind.RangeForBindings => out.write(b"range loops have one counter; use 'for value, index in collection' for collection iteration")?,
        ParseProblemKind.CollectionForAnnotation => out.write(b"collection loop bindings take their element type from the collection; remove the annotation")?,
        ParseProblemKind.ExpectedValue => out.write(b"expected a value, a function call, or an if expression")?,
        ParseProblemKind.AnonymousFunction => out.write(b"anonymous functions are not supported; use a named top-level function")?,
        ParseProblemKind.ExpectedCloseParen => out.write(b"expected ')' after the arguments")?,
        ParseProblemKind.ExpectedCloseBracket => out.write(b"expected ']' after the array capacity")?,
        ParseProblemKind.EmptyCollectionOnly => out.write(b"collection literals start empty; add values after construction")?,
        ParseProblemKind.ExpectedCallOpen => out.write(b"expected '('")?,
        ParseProblemKind.ExpectedOptionalName => out.write(b"expected a function name after '?.'")?,
        ParseProblemKind.ExpectedOptionalOpen => out.write(b"expected '(' after the optional call name")?,
        ParseProblemKind.ExpectedMethodName => out.write(b"expected a method name after '.'")?,
        ParseProblemKind.ExpectedFitClose => out.write(b"expected ')' after the fit type")?,
        ParseProblemKind.ExpectedFitCall => out.write(b"expected '()' after the fit type")?,
        ParseProblemKind.FitNoArgs => out.write(b"fit takes no arguments")?,
        ParseProblemKind.ExpectedSliceRange => out.write(b"slice expects a range: slice(start..end)")?,
        ParseProblemKind.ExpectedSliceClose => out.write(b"expected ')' after the slice range")?,
        ParseProblemKind.ExpectedStructField => out.write(b"expected a field name in the struct literal")?,
        ParseProblemKind.ExpectedArrayClose => out.write(b"expected ']' after the array literal")?,
        ParseProblemKind.ExpectedIndexClose => out.write(b"expected ']' after the index")?,
        ParseProblemKind.ExpectedGridClose => out.write(b"expected ']' after the grid indexes")?,
        ParseProblemKind.ExpectedMatchOpen => out.write(b"expected '{' after the match value")?,
        ParseProblemKind.ExpectedMatchArrow => out.write(b"expected '=>' after the match pattern")?,
        ParseProblemKind.ExpectedMatchClose => out.write(b"expected '}' to close the match")?,
        ParseProblemKind.ExpectedMatchSeparator => out.write(b"expected a comma or newline between match arms")?,
        ParseProblemKind.ExpectedPattern => out.write(b"expected an enum case, bool or integer literal, or '_' pattern")?,
        ParseProblemKind.ExpectedPatternNumber => out.write(b"expected an integer literal after '-' in a pattern")?,
        ParseProblemKind.ExpectedPatternEnumCase => out.write(b"expected an enum case after '.'")?,
        ParseProblemKind.ExpectedPatternBinding => out.write(b"expected a payload name or '_' in this pattern")?,
        ParseProblemKind.ExpectedPatternClose => out.write(b"expected ')' after pattern payload")?,
        ParseProblemKind.ExpectedIfBlockOrIf => out.write(b"expected a block or another 'if' after 'else'")?,
        ParseProblemKind.ExpectedElseBlock => out.write(b"expected a block after 'else'")?,
        ParseProblemKind.IntegerSeparators => out.write(b"underscores in integer literals must appear between digits")?,
        ParseProblemKind.IntegerTooLarge => out.write(b"integer literal is too large to represent; use a smaller value")?,
        ParseProblemKind.ParseNodeLimit => out.write(b"node limit of 2000000 per package exceeded")?,
        ParseProblemKind.ParseEdgeLimit => out.write(b"child edge limit of 2000000 per package exceeded")?,
        ParseProblemKind.ParseWorkLimit => out.write(b"parse work limit of 72000000 units per package exceeded")?,
        ParseProblemKind.InternalCapacity => {
            out.write(b"self-hosted parser capacity exceeded node=")?
            out.write(str(error.token).bytes())?
        },
    }
    ok(())
}

fn fail_parse(env: Env, source: Bytes max 67108864, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, file: Bytes max 4096, base: long, length: long, error: ParseError) -> never {
    match write_parse_diagnostic(env.err, source, file, base, length, error, tokens) {
        ok(_) => env.exit(2),
        err(_) => env.exit(3),
    }
}

fn fail_parse_limit(env: Env, file: Bytes max 4096, message: Ascii max 160) -> never {
    match write_diagnostic(env.err, file, 1L, 1L, message) {
        ok(_) => env.exit(2),
        err(_) => env.exit(3),
    }
}

fn dump_flush(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES) -> Result<(), IoError> {
    if buffer.count() > 0L {
        out.write(buffer)?
        buffer = Bytes.empty()
    }
    ok(())
}

fn dump_push(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, value: byte) -> Result<(), IoError> {
    if buffer.count() >= OUTPUT_BUFFER_BYTES { dump_flush(out, buffer)? }
    buffer.push(value).unwrap()
    ok(())
}

fn dump_bytes(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, value: Bytes max 64) -> Result<(), IoError> {
    for index in 0L..value.count() { dump_push(out, buffer, value[index])? }
    ok(())
}

fn dump_ascii(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, value: Ascii max 256) -> Result<(), IoError> {
    for index in 0L..value.len() { dump_push(out, buffer, value.bytes()[index])? }
    ok(())
}

fn dump_number(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, value: long) -> Result<(), IoError> {
    let digits = str(value)
    for index in 0L..digits.len() { dump_push(out, buffer, digits.bytes()[index])? }
    ok(())
}

fn dump_json_byte(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, value: byte) -> Result<(), IoError> {
    if value == 34 { dump_bytes(out, buffer, b"\\\"") }
    else if value == 92 { dump_bytes(out, buffer, b"\\\\") }
    else if value == 10 { dump_bytes(out, buffer, b"\\n") }
    else if value == 13 { dump_bytes(out, buffer, b"\\r") }
    else if value == 9 { dump_bytes(out, buffer, b"\\t") }
    else if value == 0 { dump_bytes(out, buffer, b"\\u0000") }
    else if value < 32 {
        dump_bytes(out, buffer, b"\\u00")?
        if value < 16 { dump_push(out, buffer, 48)? }
        let digits = str_hex(value)
        for index in 0L..digits.len() { dump_push(out, buffer, digits.bytes()[index])? }
        ok(())
    } else {
        dump_push(out, buffer, value)
    }
}

fn dump_invalid_byte(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, value: byte) -> Result<(), IoError> {
    dump_bytes(out, buffer, b"\\u00")?
    if value < 16 { dump_push(out, buffer, 48)? }
    let digits = str_hex(value)
    for index in 0L..digits.len() { dump_push(out, buffer, digits.bytes()[index])? }
    ok(())
}

fn utf8_sequence_valid(value: Bytes max 67108864, start: long, width: long) -> bool {
    if start + width > value.count() { return false }
    let first = value[start]
    if width == 2L { return first >= 194 && first <= 223 && value[start + 1L] >= 128 && value[start + 1L] <= 191 }
    if width == 3L {
        let second = value[start + 1L]
        let third = value[start + 2L]
        return third >= 128 && third <= 191 && second >= 128 && second <= 191 && !(first == 224 && second < 160) && !(first == 237 && second > 159)
    }
    let second = value[start + 1L]
    return value[start + 2L] >= 128 && value[start + 2L] <= 191 && value[start + 3L] >= 128 && value[start + 3L] <= 191 && second >= 128 && second <= 191 && !(first == 240 && second < 144) && !(first == 244 && second > 143) && first >= 240 && first <= 244
}

fn dump_json_bytes(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, value: Bytes max 67108864) -> Result<(), IoError> {
    var index = 0L
    for step in 0L..value.count() {
        if index >= value.count() { break }
        let byte_value = value[index]
        if byte_value < 128 {
            dump_json_byte(out, buffer, byte_value)?
            index += 1L
        } else {
            let width = utf8_width(byte_value)
            if byte_value >= 194 && byte_value <= 244 && utf8_sequence_valid(value, index, width) {
                for inner in 0L..width { dump_push(out, buffer, value[index + inner])? }
                index += width
            } else {
                dump_invalid_byte(out, buffer, byte_value)?
                index += 1L
            }
        }
    }
    ok(())
}

fn dump_json_source(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, source: Bytes max 67108864, start: long, end: long) -> Result<(), IoError> {
    for index in start..end { dump_json_byte(out, buffer, source[index])? }
    ok(())
}

fn append_unicode_byte_value(value: grow Bytes max MAX_SOURCE_BYTES_PER_FILE, byte_value: byte) {
    if byte_value < 128 {
        value.push(byte_value).unwrap()
    } else {
        value.push(192 + byte_value / 64).unwrap()
        value.push(128 + byte_value % 64).unwrap()
    }
}

fn decoded_hex_byte(value: byte) -> byte {
    if value >= 48 && value <= 57 { value - 48 }
    else if value >= 65 && value <= 70 { value - 55 }
    else if value >= 97 && value <= 102 { value - 87 }
    else { 0 }
}

fn decode_string_token(
    source: Bytes max 67108864,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    base: long,
    token: long,
    raw_bytes: bool,
) -> Bytes max 16777216 {
    var value: Bytes max MAX_SOURCE_BYTES_PER_FILE = Bytes.empty()
    if token < 0L || token >= tokens.count() { return value }
    let start = base + tokens[token].start + 1L
    let end = base + tokens[token].start + tokens[token].length - 1L
    var index = start
    for step in 0L..end - start {
        if index >= end { break }
        let current = source[index]
        if current != 92 {
            value.push(current).unwrap()
            index += 1L
        } else {
            let escape = source[index + 1L]
            if escape == 34 { value.push(34).unwrap(); index += 2L }
            else if escape == 92 { value.push(92).unwrap(); index += 2L }
            else if escape == 110 { value.push(10).unwrap(); index += 2L }
            else if escape == 116 { value.push(9).unwrap(); index += 2L }
            else if escape == 48 { value.push(0).unwrap(); index += 2L }
            else {
                let high = decoded_hex_byte(source[index + 2L])
                let low = decoded_hex_byte(source[index + 3L])
                let decoded_long = high.to_long() * 16L + low.to_long()
                let decoded_int = (int)(decoded_long)
                let decoded = match decoded_int.fit<byte>() {
                    some(value_byte) => value_byte,
                    none => decoded_hex_byte(48),
                }
                if raw_bytes { value.push(decoded).unwrap() }
                else { append_unicode_byte_value(value, decoded) }
                index += 4L
            }
        }
    }
    value
}

fn dump_quoted_token(
    out: Out,
    buffer: grow Bytes max OUTPUT_BUFFER_BYTES,
    source: Bytes max 67108864,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    base: long,
    token: long,
) -> Result<(), IoError> {
    dump_push(out, buffer, 34)?
    if token >= 0L && token < tokens.count() {
        dump_json_source(out, buffer, source, base + tokens[token].start, base + tokens[token].start + tokens[token].length)?
    }
    dump_push(out, buffer, 34)
}

fn dump_quoted_decoded_token(
    out: Out,
    buffer: grow Bytes max OUTPUT_BUFFER_BYTES,
    source: Bytes max 67108864,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    base: long,
    token: long,
    raw_bytes: bool,
) -> Result<(), IoError> {
    let value = decode_string_token(source, tokens, base, token, raw_bytes)
    dump_push(out, buffer, 34)?
    dump_json_bytes(out, buffer, value)?
    dump_push(out, buffer, 34)
}

fn dump_quoted_name(
    out: Out,
    buffer: grow Bytes max OUTPUT_BUFFER_BYTES,
    source: Bytes max 67108864,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    base: long,
    token: long,
) -> Result<(), IoError> {
    dump_push(out, buffer, 34)?
    if token >= 0L && token < tokens.count() {
        dump_json_source(out, buffer, source, base + tokens[token].start, base + tokens[token].start + tokens[token].length)?
    }
    dump_push(out, buffer, 34)
}

fn dump_literal_decimal(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, value: Literal128, negative: bool) -> Result<(), IoError> {
    if negative { dump_push(out, buffer, 45)? }
    var current = value
    var reverse: Bytes max 40 = Bytes.empty()
    var nonzero = current.limb0 != 0L || current.limb1 != 0L || current.limb2 != 0L || current.limb3 != 0L
    if !nonzero { reverse.push(48).unwrap() }
    for div_step in 0L..40L {
        if !nonzero { break }
        var remainder = 0L
        let c3 = remainder * 4294967296L + current.limb3
        current.limb3 = c3 / 10L
        remainder = c3 % 10L
        let c2 = remainder * 4294967296L + current.limb2
        current.limb2 = c2 / 10L
        remainder = c2 % 10L
        let c1 = remainder * 4294967296L + current.limb1
        current.limb1 = c1 / 10L
        remainder = c1 % 10L
        let c0 = remainder * 4294967296L + current.limb0
        current.limb0 = c0 / 10L
        remainder = c0 % 10L
        reverse.push(str(remainder).bytes()[0L]).unwrap()
        nonzero = current.limb0 != 0L || current.limb1 != 0L || current.limb2 != 0L || current.limb3 != 0L
    }
    for index in 0L..reverse.count() { dump_push(out, buffer, reverse[reverse.count() - index - 1L])? }
    ok(())
}

fn dump_node_kind(kind: NodeKind) -> Ascii max 24 {
    match kind {
        NodeKind.Program => "Program",
        NodeKind.Enum => "Enum",
        NodeKind.EnumCase => "EnumCase",
        NodeKind.Struct => "Struct",
        NodeKind.StructField => "StructField",
        NodeKind.TypeAlias => "TypeAlias",
        NodeKind.Const => "Const",
        NodeKind.Global => "Global",
        NodeKind.Function => "Function",
        NodeKind.Test => "Test",
        NodeKind.Parameter => "Parameter",
        NodeKind.Block => "Block",
        NodeKind.FunctionType => "FunctionType",
        NodeKind.FunctionTypeParameter => "FunctionTypeParameter",
        NodeKind.Effect => "Effect",
        NodeKind.ParameterType => "ParameterType",
        NodeKind.ResultType => "ResultType",
        NodeKind.Annotation => "Annotation",
        NodeKind.FieldType => "FieldType",
        NodeKind.PayloadType => "PayloadType",
        NodeKind.AliasedType => "AliasedType",
        NodeKind.DeclaredType => "DeclaredType",
        NodeKind.TypeArgument => "TypeArgument",
        NodeKind.FitType => "FitType",
        NodeKind.CastType => "CastType",
        NodeKind.Let => "Let",
        NodeKind.Assign => "Assign",
        NodeKind.ReturnStatement => "ReturnStatement",
        NodeKind.ExpressionStatement => "ExpressionStatement",
        NodeKind.For => "For",
        NodeKind.ForEach => "ForEach",
        NodeKind.Discard => "Discard",
        NodeKind.Expect => "Expect",
        NodeKind.BreakStatement => "BreakStatement",
        NodeKind.ContinueStatement => "ContinueStatement",
        NodeKind.Unit => "Unit",
        NodeKind.Integer => "Integer",
        NodeKind.Bool => "Bool",
        NodeKind.ByteString => "ByteString",
        NodeKind.BytesLiteral => "BytesLiteral",
        NodeKind.Take => "Take",
        NodeKind.Name => "Name",
        NodeKind.Call => "Call",
        NodeKind.IndirectCall => "IndirectCall",
        NodeKind.QualifiedCase => "QualifiedCase",
        NodeKind.MethodCall => "MethodCall",
        NodeKind.Index => "Index",
        NodeKind.OptionalCall => "OptionalCall",
        NodeKind.Field => "Field",
        NodeKind.StructInit => "StructInit",
        NodeKind.InitializerField => "InitializerField",
        NodeKind.ArrayLiteral => "ArrayLiteral",
        NodeKind.ListLiteral => "ListLiteral",
        NodeKind.PoolLiteral => "PoolLiteral",
        NodeKind.MapLiteral => "MapLiteral",
        NodeKind.SetLiteral => "SetLiteral",
        NodeKind.QueueLiteral => "QueueLiteral",
        NodeKind.RingLiteral => "RingLiteral",
        NodeKind.GridIndex => "GridIndex",
        NodeKind.Fit => "Fit",
        NodeKind.Try => "Try",
        NodeKind.Return => "Return",
        NodeKind.LoopExit => "LoopExit",
        NodeKind.Match => "Match",
        NodeKind.MatchArm => "MatchArm",
        NodeKind.ToLong => "ToLong",
        NodeKind.Cast => "Cast",
        NodeKind.Unary => "Unary",
        NodeKind.Binary => "Binary",
        NodeKind.If => "If",
        NodeKind.WildcardPattern => "WildcardPattern",
        NodeKind.BoolPattern => "BoolPattern",
        NodeKind.CasePattern => "CasePattern",
        NodeKind.PatternBinding => "PatternBinding",
        NodeKind.IgnoredPatternBinding => "IgnoredPatternBinding",
    }
}

fn dump_quoted_ascii(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, value: Ascii max 96) -> Result<(), IoError> {
    dump_push(out, buffer, 34)?
    for index in 0L..value.len() { dump_json_byte(out, buffer, value.bytes()[index])? }
    dump_push(out, buffer, 34)
}

fn dump_name_field(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, label: Ascii max 32, source: Bytes max 67108864, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, base: long, token: long) -> Result<(), IoError> {
    dump_ascii(out, buffer, label)?
    dump_quoted_name(out, buffer, source, tokens, base, token)
}

fn dump_bool_word(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, value: bool) -> Result<(), IoError> {
    if value { dump_bytes(out, buffer, b"true") } else { dump_bytes(out, buffer, b"false") }
}

fn dump_mode(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, flags: long) -> Result<(), IoError> {
    if (flags & FLAG_MODE_WRITE) != 0L { dump_bytes(out, buffer, b"write") }
    else if (flags & FLAG_MODE_GROW) != 0L { dump_bytes(out, buffer, b"grow") }
    else { dump_bytes(out, buffer, b"read") }
}

fn dump_name_list(
    out: Out,
    buffer: grow Bytes max OUTPUT_BUFFER_BYTES,
    source: Bytes max 67108864,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    base: long,
    first: long,
    count: long,
) -> Result<(), IoError> {
    dump_push(out, buffer, 91)?
    for index in 0L..count {
        if index > 0L { dump_push(out, buffer, 44)? }
        dump_quoted_name(out, buffer, source, tokens, base, tables.extra[first + index])?
    }
    dump_push(out, buffer, 93)
}

fn dump_type_name(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, source: Bytes max 67108864, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, tables: ParseTables, base: long, node: Node) -> Result<(), IoError> {
    if (node.flags & FLAG_TYPE_FN) != 0L { return dump_quoted_ascii(out, buffer, "fn") }
    if (node.flags & FLAG_TYPE_UNIT) != 0L { return dump_quoted_ascii(out, buffer, "()") }
    if (node.flags & FLAG_TYPE_TEXT_BYTES) != 0L { return dump_quoted_ascii(out, buffer, "TextBytes") }
    dump_push(out, buffer, 34)?
    for index in 0L..node.aux {
        if index > 0L { dump_push(out, buffer, 46)? }
        let token = tables.extra[node.extra + index]
        if token >= 0L && token < tokens.count() {
            dump_json_source(out, buffer, source, base + tokens[token].start, base + tokens[token].start + tokens[token].length)?
        }
    }
    dump_push(out, buffer, 34)
}

fn dump_range_field(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, tables: ParseTables, node: Node) -> Result<(), IoError> {
    dump_bytes(out, buffer, b" range=")?
    if (node.flags & FLAG_RANGE) == 0L { return dump_bytes(out, buffer, b"none") }
    let lower_index = tables.extra[node.anchor]
    let lower_negative = tables.extra[node.anchor + 1L] != 0L
    let upper_index = tables.extra[node.anchor + 2L]
    let upper_negative = tables.extra[node.anchor + 3L] != 0L
    dump_literal_decimal(out, buffer, tables.literals[lower_index], lower_negative)?
    if (node.flags & FLAG_RANGE_INCLUSIVE) != 0L { dump_bytes(out, buffer, b"..=")? }
    else { dump_bytes(out, buffer, b"..")? }
    dump_literal_decimal(out, buffer, tables.literals[upper_index], upper_negative)
}

fn dump_policy_field(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, flags: long) -> Result<(), IoError> {
    dump_bytes(out, buffer, b" policy=")?
    if (flags & FLAG_POLICY_WRAP) != 0L { dump_bytes(out, buffer, b"wrap") }
    else if (flags & FLAG_POLICY_CLAMP) != 0L { dump_bytes(out, buffer, b"clamp") }
    else { dump_bytes(out, buffer, b"checked") }
}

fn dump_assign_op(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, op: long) -> Result<(), IoError> {
    if op == 0L { dump_bytes(out, buffer, b"=") }
    else if op == 1L { dump_bytes(out, buffer, b"+=") }
    else if op == 2L { dump_bytes(out, buffer, b"-=") }
    else if op == 3L { dump_bytes(out, buffer, b"*=") }
    else if op == 4L { dump_bytes(out, buffer, b"/=") }
    else if op == 5L { dump_bytes(out, buffer, b"%=") }
    else { dump_bytes(out, buffer, b">>=") }
}

fn dump_binary_op(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, op: long) -> Result<(), IoError> {
    if op == 0L { dump_bytes(out, buffer, b"add") }
    else if op == 1L { dump_bytes(out, buffer, b"sub") }
    else if op == 2L { dump_bytes(out, buffer, b"mul") }
    else if op == 3L { dump_bytes(out, buffer, b"div") }
    else if op == 4L { dump_bytes(out, buffer, b"rem") }
    else if op == 5L { dump_bytes(out, buffer, b"wrap_add") }
    else if op == 6L { dump_bytes(out, buffer, b"wrap_sub") }
    else if op == 7L { dump_bytes(out, buffer, b"wrap_mul") }
    else if op == 8L { dump_bytes(out, buffer, b"eq") }
    else if op == 9L { dump_bytes(out, buffer, b"ne") }
    else if op == 10L { dump_bytes(out, buffer, b"lt") }
    else if op == 11L { dump_bytes(out, buffer, b"le") }
    else if op == 12L { dump_bytes(out, buffer, b"gt") }
    else if op == 13L { dump_bytes(out, buffer, b"ge") }
    else if op == 14L { dump_bytes(out, buffer, b"and") }
    else if op == 15L { dump_bytes(out, buffer, b"or") }
    else if op == 16L { dump_bytes(out, buffer, b"bit_and") }
    else if op == 17L { dump_bytes(out, buffer, b"bit_or") }
    else if op == 18L { dump_bytes(out, buffer, b"bit_xor") }
    else if op == 19L { dump_bytes(out, buffer, b"shl") }
    else if op == 20L { dump_bytes(out, buffer, b"shr") }
    else { dump_bytes(out, buffer, b"coalesce") }
}

fn dump_effect(out: Out, buffer: grow Bytes max OUTPUT_BUFFER_BYTES, source: Bytes max 67108864, tokens: list<Token, TOKEN_STORAGE_CAPACITY>, tables: ParseTables, base: long, node: Node) -> Result<(), IoError> {
    dump_bytes(out, buffer, b" kind=")?
    if node.flags == 1L { dump_bytes(out, buffer, b"out")? }
    else if node.flags == 2L { dump_bytes(out, buffer, b"env")? }
    else if node.flags == 3L { dump_bytes(out, buffer, b"fs.read")? }
    else if node.flags == 4L { dump_bytes(out, buffer, b"fs.write")? }
    else if (node.flags & 7L) == 5L {
        if (node.flags & FLAG_EFFECT_WRITES) != 0L { dump_bytes(out, buffer, b"writes")? }
        else { dump_bytes(out, buffer, b"reads")? }
    } else { () }
    if (node.flags & 7L) == 5L {
        dump_bytes(out, buffer, b" path=\"")?
        for index in 0L..node.aux {
            if index > 0L { dump_push(out, buffer, 46)? }
            let token = tables.extra[node.extra + index]
            if token >= 0L && token < tokens.count() {
                dump_json_source(out, buffer, source, base + tokens[token].start, base + tokens[token].start + tokens[token].length)?
            }
        }
        dump_push(out, buffer, 34)?
    }
    ok(())
}

fn dump_node_fields(
    out: Out,
    buffer: grow Bytes max OUTPUT_BUFFER_BYTES,
    source: Bytes max 67108864,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    base: long,
    node: Node,
) -> Result<(), IoError> {
    if node.kind == NodeKind.Enum || node.kind == NodeKind.EnumCase || node.kind == NodeKind.StructField || node.kind == NodeKind.TypeAlias || node.kind == NodeKind.Const || node.kind == NodeKind.Global || node.kind == NodeKind.Parameter || node.kind == NodeKind.FunctionTypeParameter || node.kind == NodeKind.Let || node.kind == NodeKind.For || node.kind == NodeKind.ForEach || node.kind == NodeKind.Name || node.kind == NodeKind.Field || node.kind == NodeKind.MethodCall || node.kind == NodeKind.OptionalCall || node.kind == NodeKind.StructInit || node.kind == NodeKind.InitializerField || node.kind == NodeKind.PatternBinding {
        if node.kind == NodeKind.Enum { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
        else if node.kind == NodeKind.EnumCase { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
        else if node.kind == NodeKind.StructField { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
        else if node.kind == NodeKind.TypeAlias { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
        else if node.kind == NodeKind.Const { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
        else if node.kind == NodeKind.Global {
            dump_name_field(out, buffer, " name=", source, tokens, base, node.token)?
            dump_bytes(out, buffer, b" prefault=")?
            dump_bool_word(out, buffer, (node.flags & FLAG_PREFAULT) != 0L)?
        } else if node.kind == NodeKind.Parameter {
            dump_name_field(out, buffer, " name=", source, tokens, base, node.token)?
            dump_bytes(out, buffer, b" mode=")?
            dump_mode(out, buffer, node.flags)?
        } else if node.kind == NodeKind.FunctionTypeParameter {
            dump_bytes(out, buffer, b" mode=")?
            dump_mode(out, buffer, node.flags)?
        } else if node.kind == NodeKind.Let {
            dump_bytes(out, buffer, b" mutable=")?
            dump_bool_word(out, buffer, (node.flags & FLAG_MUTABLE) != 0L)?
            dump_name_field(out, buffer, " name=", source, tokens, base, node.token)?
        } else if node.kind == NodeKind.For {
            dump_name_field(out, buffer, " name=", source, tokens, base, node.token)?
            dump_bytes(out, buffer, b" inclusive=")?
            dump_bool_word(out, buffer, (node.flags & FLAG_INCLUSIVE) != 0L)?
        } else if node.kind == NodeKind.ForEach {
            dump_name_field(out, buffer, " name=", source, tokens, base, node.token)?
            dump_bytes(out, buffer, b" indexes=")?
            dump_name_list(out, buffer, source, tokens, tables, base, node.extra, node.aux)?
        } else if node.kind == NodeKind.Name { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
        else if node.kind == NodeKind.Field { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
        else if node.kind == NodeKind.MethodCall || node.kind == NodeKind.OptionalCall { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
        else if node.kind == NodeKind.StructInit { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
        else if node.kind == NodeKind.InitializerField { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
        else { dump_name_field(out, buffer, " name=", source, tokens, base, node.token)? }
    } else if node.kind == NodeKind.Struct || node.kind == NodeKind.Function {
        dump_name_field(out, buffer, " name=", source, tokens, base, node.token)?
        if node.kind == NodeKind.Function {
            dump_bytes(out, buffer, b" recursive=")?
            dump_bool_word(out, buffer, (node.flags & FLAG_RECURSIVE) != 0L)?
        }
        dump_bytes(out, buffer, b" generics=")?
        dump_name_list(out, buffer, source, tokens, tables, base, node.extra, node.aux)?
    } else if node.kind == NodeKind.Test {
        dump_bytes(out, buffer, b" name=")?
        dump_quoted_decoded_token(out, buffer, source, tokens, base, node.token, false)?
    } else if is_type_node(node.kind) {
        dump_bytes(out, buffer, b" name=")?
        dump_type_name(out, buffer, source, tokens, tables, base, node)?
        dump_range_field(out, buffer, tables, node)?
        dump_policy_field(out, buffer, node.flags)?
    } else if node.kind == NodeKind.Effect {
        dump_effect(out, buffer, source, tokens, tables, base, node)?
    } else if node.kind == NodeKind.Expect {
        dump_bytes(out, buffer, b" source=\"expect ")?
        dump_json_source(out, buffer, source, tables.extra[node.extra], tables.extra[node.extra + 1L])?
        dump_push(out, buffer, 34)?
    } else if node.kind == NodeKind.Assign {
        dump_bytes(out, buffer, b" op=")?
        dump_assign_op(out, buffer, node.flags)?
    } else if node.kind == NodeKind.Bool || node.kind == NodeKind.BoolPattern {
        dump_bytes(out, buffer, b" value=")?
        dump_bool_word(out, buffer, (node.flags & FLAG_VALUE) != 0L)?
    } else if node.kind == NodeKind.Integer {
        dump_bytes(out, buffer, b" magnitude=")?
        dump_literal_decimal(out, buffer, tables.literals[node.extra], false)?
        dump_bytes(out, buffer, b" negative=")?
        dump_bool_word(out, buffer, (node.flags & FLAG_NEGATIVE) != 0L)?
        dump_bytes(out, buffer, b" long_suffix=")?
        dump_bool_word(out, buffer, (node.flags & FLAG_LONG_SUFFIX) != 0L)?
    } else if node.kind == NodeKind.ByteString {
        dump_bytes(out, buffer, b" value=")?
        dump_quoted_decoded_token(out, buffer, source, tokens, base, node.token, true)?
    } else if node.kind == NodeKind.BytesLiteral {
        dump_bytes(out, buffer, b" value=")?
        dump_quoted_decoded_token(out, buffer, source, tokens, base, node.extra, true)?
    } else if node.kind == NodeKind.CasePattern {
        dump_name_field(out, buffer, " name=", source, tokens, base, node.token)?
        if (node.flags & FLAG_HAS_ANNOTATION) != 0L {
            dump_name_field(out, buffer, " enum=", source, tokens, base, node.extra)?
        }
    } else if node.kind == NodeKind.Call {
        dump_bytes(out, buffer, b" name=")?
        if (node.flags & FLAG_SYNTHETIC) != 0L { dump_quoted_ascii(out, buffer, "default")? }
        else { dump_quoted_name(out, buffer, source, tokens, base, node.token)? }
    } else if node.kind == NodeKind.QualifiedCase {
        dump_name_field(out, buffer, " enum=", source, tokens, base, node.token)?
        dump_name_field(out, buffer, " case=", source, tokens, base, tables.extra[node.extra])?
    } else if node.kind == NodeKind.LoopExit {
        dump_bytes(out, buffer, b" kind=")?
        if (node.flags & FLAG_VALUE) != 0L { dump_bytes(out, buffer, b"break")? }
        else { dump_bytes(out, buffer, b"continue")? }
    } else if node.kind == NodeKind.Unary {
        dump_bytes(out, buffer, b" op=")?
        if node.flags == 0L { dump_bytes(out, buffer, b"neg")? }
        else { dump_bytes(out, buffer, b"not")? }
    } else if node.kind == NodeKind.Binary {
        dump_bytes(out, buffer, b" op=")?
        dump_binary_op(out, buffer, node.flags)?
    } else if node.kind == NodeKind.Fit || node.kind == NodeKind.Cast || node.kind == NodeKind.Try || node.kind == NodeKind.Return || node.kind == NodeKind.ToLong || node.kind == NodeKind.Take || node.kind == NodeKind.Index || node.kind == NodeKind.GridIndex || node.kind == NodeKind.IndirectCall || node.kind == NodeKind.ArrayLiteral || node.kind == NodeKind.ListLiteral || node.kind == NodeKind.PoolLiteral || node.kind == NodeKind.MapLiteral || node.kind == NodeKind.SetLiteral || node.kind == NodeKind.QueueLiteral || node.kind == NodeKind.RingLiteral || node.kind == NodeKind.Unit || node.kind == NodeKind.Block || node.kind == NodeKind.FunctionType || node.kind == NodeKind.Match || node.kind == NodeKind.MatchArm || node.kind == NodeKind.If || node.kind == NodeKind.Discard || node.kind == NodeKind.ReturnStatement || node.kind == NodeKind.ExpressionStatement || node.kind == NodeKind.BreakStatement || node.kind == NodeKind.ContinueStatement || node.kind == NodeKind.WildcardPattern {
        ()
    } else {
        ()
    }
    ok(())
}

fn dump_node_line(
    out: Out,
    buffer: grow Bytes max OUTPUT_BUFFER_BYTES,
    source: Bytes max 67108864,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    base: long,
    node_index: long,
    depth: long,
) -> Result<(), IoError> {
    let node = tables.nodes[node_index]
    for indent in 0L..depth * 2L { dump_push(out, buffer, 32)? }
    dump_ascii(out, buffer, dump_node_kind(node.kind))?
    dump_push(out, buffer, 32)?
    dump_number(out, buffer, node.start)?
    dump_bytes(out, buffer, b"..")?
    dump_number(out, buffer, node.end)?
    let first_field = buffer.count()
    dump_node_fields(out, buffer, source, tokens, tables, base, node)?
    if buffer.count() == first_field { () } else { () }
    dump_push(out, buffer, 10)
}

fn output_tree_dump(
    out: Out,
    source: Bytes max 67108864,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: write ParseTables,
) -> Result<(), IoError> {
    var buffer: Bytes max OUTPUT_BUFFER_BYTES = Bytes.empty()
    for file_index in 0L..files.count() {
        let file = files[file_index]
        dump_bytes(out, buffer, b"file ")?
        dump_push(out, buffer, 34)?
        dump_json_bytes(out, buffer, file.name)?
        dump_bytes(out, buffer, b"\"\n")?
        tables.nesting.clear()
        tables.nesting.push(NestTask { node: file.tree_root, depth: 0L, role: 0L }).unwrap()
        for step in 0L..NESTING_TASK_CAPACITY {
            let task = match tables.nesting.pop() {
                some(value) => value,
                none => break,
            }
            dump_node_line(out, buffer, source, tokens, tables, file.base, task.node, task.depth)?
            let first = node_first_child(tables.nodes, task.node)
            var child = task.node - 1L
            for child_step in 0L..tables.nodes[task.node].subtree {
                if child < first { break }
                tables.nesting.push(NestTask { node: child, depth: task.depth + 1L, role: 0L }).unwrap()
                child -= tables.nodes[child].subtree
            }
        }
    }
    dump_flush(out, buffer)
}
