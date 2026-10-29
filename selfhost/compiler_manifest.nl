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

