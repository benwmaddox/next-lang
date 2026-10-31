fn emit_c_runtime_declarations(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "declare ptr @nl_context_create(i64, i64, ptr)\ndeclare i64 @nl_context_base_offset(ptr)\ndeclare i64 @nl_context_reservation_bytes(ptr)\ndeclare void @nl_context_set_top_offset(ptr, i64)\ndeclare void @nl_context_destroy(ptr)\ndeclare ptr @nl_env_create(i32, ptr, i32)\ndeclare void @nl_env_destroy(ptr)\ndeclare ptr @nl_env_args(ptr)\ndeclare ptr @nl_env_fs(ptr)\ndeclare ptr @nl_env_out(ptr, i32)\ndeclare void @nl_env_exit(i32) noreturn nounwind\ndeclare void @nl_register_file(i32, ptr)\ndeclare i32 @nl_test_selected_index()\ndeclare void @nl_set_test_mode()\n")
    if compiler.mailbox_types.count() > 0L { emit_mailbox_functions(compiler, ir) }
    ir_write_ascii(compiler, ir, "declare ptr @nl_context_create_job(i64, i64, ptr)\n")
    ir_write_ascii(compiler, ir, "declare ptr @nl_job_args_alloc(i64)\ndeclare void @nl_job_args_free(ptr)\ndeclare void @nl_job_start(ptr, ptr)\ndeclare void @nl_jobs_join_all()\ndeclare void @nl_yield()\ndeclare i64 @nl_now_ns()\ndeclare i64 @nl_now_ms(ptr)\n@nl_mbox_spin = external global i64\ndeclare i32 @nl_park(ptr, i32, i64)\ndeclare void @nl_wake(ptr, i32)\n")
    ir_write_ascii(compiler, ir, "declare ptr @nl_env_host(ptr)\ndeclare void @nl_db_query(ptr, ptr, i64, i64, ptr)\ndeclare i64 @nl_db_row(ptr, ptr, i64, i64, ptr, ptr, i64, ptr)\ndeclare i64 @nl_db_rows(ptr, ptr, i64, i64, ptr, ptr, i64, ptr, i64, i64, i64)\ndeclare i64 @nl_cache_get(ptr, i64, ptr, i64, ptr)\ndeclare i64 @nl_cache_put(ptr, i64, ptr, i64)\ndeclare i64 @nl_db_text(ptr, ptr, i64, i64, ptr, i64, ptr)\ndeclare i64 @nl_net_listen(ptr, i64)\ndeclare i64 @nl_net_accept(ptr, i64)\ndeclare i64 @nl_net_close(ptr, i64)\ndeclare i64 @nl_http_read(ptr, i64, ptr, i64, ptr)\ndeclare i64 @nl_http_write(ptr, i64, i64, i64, ptr, i64)\ndeclare i64 @nl_http_header(ptr, i64, ptr, i64, ptr, i64, ptr)\ndeclare i64 @nl_host_cores(ptr)\ndeclare i64 @nl_host_total_cores(ptr)\ndeclare i64 @nl_host_ram_bytes(ptr)\ndeclare i64 @nl_host_page_size(ptr)\n")
    ir_write_ascii(compiler, ir, "declare i64 @nl_args_count(ptr)\ndeclare ptr @nl_args_get(ptr, i64)\ndeclare i64 @nl_arg_length(ptr)\ndeclare i32 @nl_arg_byte(ptr, i64)\ndeclare void @nl_fs_read(ptr, ptr, i32, i64, ptr, i64, ptr)\ndeclare void @nl_fs_read_string(ptr, ptr, i32, i64, ptr, i64, i32, i64, ptr, ptr, ptr)\ndeclare void @nl_fs_list(ptr, ptr, i32, i64, ptr, i64, ptr)\ndeclare void @nl_fs_write(ptr, ptr, i32, i64, ptr, i32, i64, ptr)\ndeclare void @nl_out_write(ptr, ptr, i32, i64, i32, ptr)\ndeclare void @nl_out_int(ptr, i32, ptr)\ndeclare void @nl_out_long(ptr, i64, ptr)\ndeclare void @nl_out_arg(ptr, ptr, i32, ptr)\n")
    ir_write_ascii(compiler, ir, "declare void @nl_print_int(i32)\ndeclare void @nl_print_long(i64)\ndeclare void @nl_print_bool(i1 zeroext)\ndeclare void @nl_print_text(ptr)\ndeclare void @nl_print_arg(ptr)\ndeclare void @nl_print_set_fd(i32)\ndeclare void @nl_print_error_prefix()\ndeclare i64 @nl_hash_ascii(ptr, i64, i64)\ndeclare i64 @nl_utf8_offset(ptr, i64, i64)\ndeclare i64 @nl_text_upper_copy(ptr, i64, ptr, ptr)\ndeclare i32 @nl_bytes_are_ascii(ptr, i64)\n")
    ir_write_ascii(compiler, ir, "\ndeclare ptr @nl_context_base(ptr readonly) nounwind willreturn memory(argmem: read)\ndeclare ptr @nl_context_limit(ptr)\ndeclare void @nl_context_note_peak_offset(ptr, i64)\ndeclare void @nl_fail(i32, i32, i32, i32)\ndeclare i64 @nl_stack_alloc_offset(ptr, i64, i64, i64, i32, i32, i32)\n")
    ir_write_ascii(compiler, ir, "declare void @nl_print_ascii(ptr, i64)\ndeclare void @nl_print_int_raw(i32)\ndeclare void @nl_print_long_raw(i64)\ndeclare void @nl_print_bool_raw(i1 zeroext)\ndeclare void @nl_print_newline()\n")
    ir_write_ascii(compiler, ir, "declare void @nl_expect_fail_header(i32, i32, i32, ptr)\ndeclare void @nl_expect_fail_left()\ndeclare void @nl_expect_fail_right()\ndeclare void @nl_expect_fail_compare(i32, i32, i32, ptr, i64, i64, i32)\ndeclare void @nl_expect_fail_bool(i32, i32, i32, ptr)\n")
    ir_write_ascii(compiler, ir, "declare void @nl_fs_join(ptr, ptr, i32, i64, ptr, i32, i64, ptr)\ndeclare void @nl_fs_list_with_extension(ptr, ptr, i32, i64, ptr, i64, ptr, i64, ptr)\n")
    ir_write_ascii(compiler, ir, "")
    ir_write_ascii(compiler, ir, "declare ptr @memcpy(ptr, ptr, i64)\ndeclare ptr @memmove(ptr, ptr, i64)\ndeclare ptr @memset(ptr, i32, i64)\ndeclare i32 @memcmp(ptr, ptr, i64)\ndeclare i32 @bcmp(ptr, ptr, i64)\n\n")
}

fn emit_c_runtime_context_adapters(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "define ptr @nlc_context_current_base(ptr %nl.ctx) alwaysinline {\nentry:\n  %base.address = getelementptr inbounds i8, ptr %nl.ctx, i64 56\n  %base = load ptr, ptr %base.address, align 8, !tbaa !9002\n  ret ptr %base\n}\n\n")
    ir_write_ascii(compiler, ir, "define ptr @nlc_context_current_limit(ptr %nl.ctx) {\nentry:\n  %limit = call ptr @nl_context_limit(ptr %nl.ctx)\n  ret ptr %limit\n}\n\n")
    ir_write_ascii(compiler, ir, "define void @nlc_context_note_peak(ptr %nl.ctx, i64 %top.offset) {\nentry:\n  call void @nl_context_note_peak_offset(ptr %nl.ctx, i64 %top.offset)\n  ret void\n}\n\n")
    // The C runtime exports allocation, not its private grow routine. Reserve
    // the requested absolute offset by allocating that many bytes from zero.
    ir_write_ascii(compiler, ir, "define void @nlc_stack_grow(ptr %nl.ctx, i64 %needed, i32 %file, i32 %line, i32 %col) {\nentry:\n  %allocation = call i64 @nl_stack_alloc_offset(ptr %nl.ctx, i64 0, i64 %needed, i64 1, i32 %file, i32 %line, i32 %col)\n  ret void\n}\n\n")
    ir_write_ascii(compiler, ir, "define void @nlc_fail(ptr %nl.ctx, i32 %kind, i32 %file, i32 %line, i32 %col) noreturn {\nentry:\n  call void @nl_fail(i32 %kind, i32 %file, i32 %line, i32 %col)\n  unreachable\n}\n\n")
}

fn emit_c_runtime_output_adapters(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "define void @nlc_print_ascii(ptr %nl.ctx, ptr %bytes, i64 %length) {\nentry:\n  call void @nl_print_ascii(ptr %bytes, i64 %length)\n  ret void\n}\n\n")
    ir_write_ascii(compiler, ir, "define void @nlc_print_int_raw(ptr %nl.ctx, i32 %value) {\nentry:\n  call void @nl_print_int_raw(i32 %value)\n  ret void\n}\n\ndefine void @nlc_print_long_raw(ptr %nl.ctx, i64 %value) {\nentry:\n  call void @nl_print_long_raw(i64 %value)\n  ret void\n}\n\n")
    ir_write_ascii(compiler, ir, "define void @nlc_print_bool_raw(ptr %nl.ctx, i1 zeroext %value) {\nentry:\n  call void @nl_print_bool_raw(i1 zeroext %value)\n  ret void\n}\n\ndefine void @nlc_print_newline(ptr %nl.ctx) {\nentry:\n  call void @nl_print_newline()\n  ret void\n}\n\n")
    ir_write_ascii(compiler, ir, "define void @nlc_expect_fail_header(ptr %nl.ctx, i32 %file, i32 %line, i32 %col, ptr %source, i64 %source.length) {\nentry:\n  call void @nl_expect_fail_header(i32 %file, i32 %line, i32 %col, ptr %source)\n  ret void\n}\n\ndefine void @nlc_expect_fail_left(ptr %nl.ctx) {\nentry:\n  call void @nl_expect_fail_left()\n  ret void\n}\n\ndefine void @nlc_expect_fail_right(ptr %nl.ctx) {\nentry:\n  call void @nl_expect_fail_right()\n  ret void\n}\n\n")
    ir_write_ascii(compiler, ir, "define void @nlc_expect_fail_compare(ptr %nl.ctx, i32 %file, i32 %line, i32 %col, ptr %source, i64 %source.length, i64 %left, i64 %right, i32 %is.bool) {\nentry:\n  call void @nl_expect_fail_compare(i32 %file, i32 %line, i32 %col, ptr %source, i64 %left, i64 %right, i32 %is.bool)\n  ret void\n}\n\ndefine void @nlc_expect_fail_bool(ptr %nl.ctx, i32 %file, i32 %line, i32 %col, ptr %source, i64 %source.length) {\nentry:\n  call void @nl_expect_fail_bool(i32 %file, i32 %line, i32 %col, ptr %source)\n  ret void\n}\n\n")
}

fn emit_c_runtime_filesystem_adapters(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    // C packs Result<Path, IoError> with payload at +4. The selfhost compiler
    // aligns Path at +8, so translate both success and error values here.
    ir_write_ascii(compiler, ir, "define void @nlc_fs_join(ptr %nl.ctx, ptr %fs, ptr %dir, i32 %dir.kind, i64 %dir.capacity, ptr %name, i32 %name.kind, i64 %name.capacity, ptr %result) {\nentry:\n  %raw = alloca [16396 x i8], align 8\n  call void @nl_fs_join(ptr %fs, ptr %dir, i32 %dir.kind, i64 %dir.capacity, ptr %name, i32 %name.kind, i64 %name.capacity, ptr %raw)\n  %raw.tag = load i32, ptr %raw, align 1\n  %is.ok = icmp eq i32 %raw.tag, 0\n  br i1 %is.ok, label %join.ok, label %join.error\njoin.ok:\n  %raw.path = getelementptr i8, ptr %raw, i64 4\n  %native.path = getelementptr i8, ptr %result, i64 8\n  %copied = call ptr @memcpy(ptr %native.path, ptr %raw.path, i64 16392)\n  store i32 0, ptr %result, align 1\n  ret void\njoin.error:\n  %raw.error.kind.addr = getelementptr i8, ptr %raw, i64 4\n  %raw.error.code.addr = getelementptr i8, ptr %raw, i64 8\n  %raw.error.kind = load i32, ptr %raw.error.kind.addr, align 1\n  %raw.error.code = load i32, ptr %raw.error.code.addr, align 1\n  %native.error.kind.addr = getelementptr i8, ptr %result, i64 8\n  %native.error.code.addr = getelementptr i8, ptr %result, i64 12\n  store i32 1, ptr %result, align 1\n  store i32 %raw.error.kind, ptr %native.error.kind.addr, align 1\n  store i32 %raw.error.code, ptr %native.error.code.addr, align 1\n  ret void\n}\n\n")
    emit_c_runtime_list_with_extension(compiler, ir)
}

fn emit_c_runtime_text_adapters(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    ir_write_ascii(compiler, ir, "define void @nl_core_nl_text_assert_valid(ptr %nl.ctx, ptr %data, i64 %length) {\nentry:\n  %offset = call i64 @nl_core_utf8_error_offset(ptr %nl.ctx, ptr %data, i64 %length)\n  %is.valid = icmp eq i64 %offset, %length\n  br i1 %is.valid, label %text.valid, label %text.invalid\ntext.invalid:\n  call void @nl_fail(i32 22, i32 0, i32 0, i32 0)\n  unreachable\ntext.valid:\n  ret void\n}\n\n")
}

fn emit_c_runtime_adapters(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    emit_c_runtime_declarations(compiler, ir)
    emit_c_runtime_context_adapters(compiler, ir)
    emit_c_runtime_output_adapters(compiler, ir)
    emit_c_runtime_filesystem_adapters(compiler, ir)
    emit_c_runtime_text_adapters(compiler, ir)
    emit_float_text_functions(compiler, ir)
}
