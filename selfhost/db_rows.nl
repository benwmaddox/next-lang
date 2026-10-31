// Env.db_row(rest_of_query, key, row): the fields of the struct `row` are the columns. For each call the compiler
// writes two constants the runtime reads: the field names joined by commas, and a table of numbers (the names'
// length, then for each field its kind, byte offset and capacity). The runtime prepares
// `select <names> <rest_of_query>` once per thread and decodes the first row into the struct.

// 1 long, 2 int, 3 bool, 4 Bytes; 0 for a type db_row cannot fill.
fn db_row_field_kind(compiler: CompilerTables, ty: long) -> long {
    if ty == TY_LONG { 1L }
    else if ty == TY_INT { 2L }
    else if ty == TY_BOOL { 3L }
    else if type_kind(compiler, ty) == TYPE_KIND_BYTES { 4L }
    else { 0L }
}

fn emit_db_row_layouts(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
) {
    if !compiler.c_runtime { return }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind != NodeKind.MethodCall ||
            (compiler.facts[node].literal != C_METHOD_ENV_DB_ROW && compiler.facts[node].literal != C_METHOD_ENV_DB_ROWS) { continue }
        let row = child_at(tables, compiler, node, 3L)
        if row < 0L { continue }
        // db_row fills a struct, db_rows the elements of a list of them
        let row_type = if compiler.facts[node].literal == C_METHOD_ENV_DB_ROWS { collection_element_type(compiler, compiler.facts[row].ty) } else { compiler.facts[row].ty }
        let record = type_record(compiler, row_type)
        var names_length = 0L
        for field_offset in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_offset]
            names_length += tokens[field.name_token].length
            if field_offset > 0L { names_length += 1L }
        }
        ir_write_ascii(compiler, ir, "@nl.dbrow."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ".names = private unnamed_addr constant ["); ir_write_number(compiler, ir, names_length)
        ir_write_ascii(compiler, ir, " x i8] c\"")
        for field_offset in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_offset]
            if field_offset > 0L { ir_push_byte(compiler, ir, 44) }
            ir_write_token_text(source, files, tokens, compiler, ir, record.file, field.name_token)
        }
        ir_write_ascii(compiler, ir, "\"\n@nl.dbrow."); ir_write_number(compiler, ir, node)
        // not unnamed_addr: the runtime tells call sites apart by this table's address, so identical tables must not be merged
        ir_write_ascii(compiler, ir, ".layout = private constant ["); ir_write_number(compiler, ir, 1L + record.field_count * 3L)
        ir_write_ascii(compiler, ir, " x i64] [i64 "); ir_write_number(compiler, ir, names_length)
        for field_offset in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_offset]
            let kind = db_row_field_kind(compiler, field.ty)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, kind)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, field.offset)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, if kind == 4L { text_max_bytes(compiler, field.ty) } else { 0L })
        }
        ir_write_ascii(compiler, ir, "]\n")
        let parameters = child_at(tables, compiler, node, 2L)
        if parameters >= 0L && is_db_parameter_struct(compiler, parameters) {
            let parameter_record = type_record(compiler, compiler.facts[parameters].ty)
            ir_write_ascii(compiler, ir, "@nl.dbparams."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = private unnamed_addr constant ["); ir_write_number(compiler, ir, 1L + parameter_record.field_count * 3L)
            ir_write_ascii(compiler, ir, " x i64] [i64 "); ir_write_number(compiler, ir, parameter_record.field_count)
            for field_offset in 0L..parameter_record.field_count {
                let field = compiler.struct_fields[parameter_record.field_start + field_offset]
                let kind = db_row_field_kind(compiler, field.ty)
                ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, kind)
                ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, field.offset)
                ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, if kind == 4L { text_max_bytes(compiler, field.ty) } else { 0L })
            }
            ir_write_ascii(compiler, ir, "]\n")
        }
        // The build checks this query against the package's schema (scripts/nlc, runtime/querycheck.c).
        ir_write_ascii(compiler, ir, "; nlc.query ")
        for field_offset in 0L..record.field_count {
            if field_offset > 0L { ir_push_byte(compiler, ir, 44) }
            ir_write_number(compiler, ir, db_row_field_kind(compiler, compiler.struct_fields[record.field_start + field_offset].ty))
        }
        ir_write_ascii(compiler, ir, " select ")
        for field_offset in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_offset]
            if field_offset > 0L { ir_push_byte(compiler, ir, 44) }
            ir_write_token_text(source, files, tokens, compiler, ir, record.file, field.name_token)
        }
        ir_push_byte(compiler, ir, 32)
        let literal = child_at(tables, compiler, node, 1L)
        let literal_file = node_file_index(tables.nodes, files, literal)
        let literal_token = tables.nodes[literal].token
        let literal_start = files[literal_file].base + tokens[literal_token].start
        // a query written over several lines goes into the single-line comment with its line breaks as spaces
        for index in 1L..(tokens[literal_token].length - 1L) {
            let query_byte = source[literal_start + index]
            ir_push_byte(compiler, ir, if query_byte == 10 || query_byte == 13 || query_byte == 9 { 32 } else { query_byte })
        }
        ir_write_ascii(compiler, ir, "\n\n")
    }
}

fn db_lower_byte(source: Bytes max SOURCE_BUFFER_CAPACITY, position: long) -> long {
    let c = source[position].to_long()
    if c >= 65L && c <= 90L { c + 32L } else { c }
}

// The N in a query literal that ends with `limit N` (the literal's text, quotes included, is source[start .. start + length]),
// or -1 when it does not end that way.
fn db_rows_limit(source: Bytes max SOURCE_BUFFER_CAPACITY, start: long, length: long) -> long {
    var end = start + length - 1L        // the closing quote
    for step in 0L..length {
        if end <= start || (source[end - 1L] != 32 && source[end - 1L] != 10 && source[end - 1L] != 13 && source[end - 1L] != 9) { break }
        end -= 1L
    }
    var digits_start = end
    for step in 0L..length {
        if digits_start <= start || source[digits_start - 1L] < 48 || source[digits_start - 1L] > 57 { break }
        digits_start -= 1L
    }
    if digits_start == end || end - digits_start > 9L { return -1L }
    var value = 0L
    for position in digits_start..end { value = value * 10L + (source[position].to_long() - 48L) }
    var word_end = digits_start
    for step in 0L..length {
        if word_end <= start || source[word_end - 1L] != 32 { break }
        word_end -= 1L
    }
    if word_end - start < 5L { return -1L }
    if db_lower_byte(source, word_end - 5L) == 108L && db_lower_byte(source, word_end - 4L) == 105L && db_lower_byte(source, word_end - 3L) == 109L &&
        db_lower_byte(source, word_end - 2L) == 105L && db_lower_byte(source, word_end - 1L) == 116L { value } else { -1L }
}

// The values bound to ?1, ?2, ... in a db_row / db_rows query: one number (the usual case) or a struct whose fields are bound in
// order (long, int, bool, Bytes as text). The compiler writes a table for the struct (the count, then kind, byte offset and
// capacity of each field); a single number needs none.
fn check_db_parameters(
    env: Env,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: write CompilerTables,
    file_index: long,
    tables: ParseTables,
    argument: long,
    name: Ascii max 32,
) {
    if type_kind(compiler, compiler.facts[argument].ty) != TYPE_KIND_STRUCT {
        require_type(env, files, compiler, file_index, argument, TY_LONG, compiler.facts[argument].ty, tables)
        return
    }
    let record = type_record(compiler, compiler.facts[argument].ty)
    for field_offset in 0L..record.field_count {
        if db_row_field_kind(compiler, compiler.struct_fields[record.field_start + field_offset].ty) == 0L {
            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "the query parameters are numbers or a struct of long, int, bool and Bytes fields")
        }
    }
}

fn is_db_parameter_struct(compiler: CompilerTables, argument: long) -> bool {
    type_kind(compiler, compiler.facts[argument].ty) == TYPE_KIND_STRUCT
}

// Where the parameter struct is (any place when the parameter is a single number, which is never read).
fn emit_db_parameters_location(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    argument: long,
) -> StorageLocation {
    if is_db_parameter_struct(compiler, argument) { c_runtime_argument_source_location(tables, compiler, ir, argument) }
    else { native_location(0L, -1L, 0L) }
}

fn ir_write_db_key(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, argument: long) {
    if is_db_parameter_struct(compiler, argument) { ir_write_ascii(compiler, ir, "0") } else { ir_write_value_ref(compiler, ir, argument) }
}

// The last two arguments of the runtime call: the parameter struct and its table, or two nulls.
fn ir_write_db_parameters(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    argument: long,
    location: StorageLocation,
    pointer: long,
) {
    if is_db_parameter_struct(compiler, argument) {
        ir_write_ascii(compiler, ir, "ptr "); emit_location_pointer_reference(compiler, ir, location, pointer)
        ir_write_ascii(compiler, ir, ", ptr @nl.dbparams."); ir_write_number(compiler, ir, node)
    } else {
        ir_write_ascii(compiler, ir, "ptr null, ptr null")
    }
}
