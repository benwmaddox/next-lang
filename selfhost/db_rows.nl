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
        if tables.nodes[node].kind != NodeKind.MethodCall || compiler.facts[node].literal != C_METHOD_ENV_DB_ROW { continue }
        let row = child_at(tables, compiler, node, 3L)
        if row < 0L { continue }
        let record = type_record(compiler, compiler.facts[row].ty)
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
        ir_write_ascii(compiler, ir, ".layout = private unnamed_addr constant ["); ir_write_number(compiler, ir, 1L + record.field_count * 3L)
        ir_write_ascii(compiler, ir, " x i64] [i64 "); ir_write_number(compiler, ir, names_length)
        for field_offset in 0L..record.field_count {
            let field = compiler.struct_fields[record.field_start + field_offset]
            let kind = db_row_field_kind(compiler, field.ty)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, kind)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, field.offset)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, if kind == 4L { text_max_bytes(compiler, field.ty) } else { 0L })
        }
        ir_write_ascii(compiler, ir, "]\n")
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
        for index in 1L..(tokens[literal_token].length - 1L) { ir_push_byte(compiler, ir, source[literal_start + index]) }
        ir_write_ascii(compiler, ir, "\n\n")
    }
}
