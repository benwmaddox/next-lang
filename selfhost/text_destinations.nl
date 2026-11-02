// Runtime calls that fill a destination with bytes (Env.http_header, http_body, http_peer, random_token) can fill a Text as well as a
// Bytes. The runtime writes the bytes as it would into a Bytes (the length at the start, the data where a Text keeps its data); the
// code after the call then checks that they are well-formed UTF-8 and within the Text's limits on bytes and code points, stores the
// code-point count, and, when they are not, leaves the destination empty and makes the call's result -1.

fn emit_http_result_prefix(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, node: long, text_destination: bool) {
    if text_destination {
        ir_write_ascii(compiler, ir, "  %c.raw.result."); ir_write_number(compiler, ir, node)
    } else {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node)
    }
}

fn emit_text_destination_check(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    location: StorageLocation,
    pointer: long,
    ty: long,
    data_name: Ascii max 24,
) {
    ir_write_ascii(compiler, ir, "  %c.tx.len."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", align 1\n")
    ir_write_ascii(compiler, ir, "  %c.tx.off."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = call i64 @nl_core_utf8_error_offset(ptr %nl.ctx, ptr %"); ir_write_ascii(compiler, ir, data_name); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %c.tx.len."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
    ir_write_ascii(compiler, ir, "  %c.tx.valid."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp eq i64 %c.tx.off."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %c.tx.len."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %c.tx.len2."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = select i1 %c.tx.valid."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %c.tx.len."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 0\n  %c.tx.points."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = call i64 @nl_core_nl_text_codepoint_count_trusted(ptr %nl.ctx, ptr %"); ir_write_ascii(compiler, ir, data_name); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %c.tx.len2."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ")\n  %c.tx.fit."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = icmp ule i64 %c.tx.points."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, text_max_codepoints(compiler, ty))
    ir_write_ascii(compiler, ir, "\n  %c.tx.ok."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = and i1 %c.tx.valid."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", %c.tx.fit."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\n  %c.tx.len3."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = select i1 %c.tx.ok."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %c.tx.len."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 0\n  %c.tx.points2."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = select i1 %c.tx.ok."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %c.tx.points."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 0\n  store i64 %c.tx.len3."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", align 1")
    emit_program_storage_tbaa(compiler, ir)
    ir_write_ascii(compiler, ir, "\n  %c.tx.points.addr."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer)
    ir_write_ascii(compiler, ir, ", i64 8\n  store i64 %c.tx.points2."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %c.tx.points.addr."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1")
    emit_program_storage_tbaa(compiler, ir)
    ir_write_ascii(compiler, ir, "\n  %v"); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = select i1 %c.tx.ok."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 %c.raw.result."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 -1\n")
}
