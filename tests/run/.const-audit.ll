; nlc-link-ir 2
; nlc.build program
; nlc.stack offset
; nlc.recursion none
; nlc.runtime c
; nlc.core f2af19c6668777119ef279ca1cf80842b3c05193ed0b970845390854f49ee071
source_filename = "next-lang"

declare { i32, i1 } @llvm.sadd.with.overflow.i32(i32, i32)
declare { i32, i1 } @llvm.ssub.with.overflow.i32(i32, i32)
declare { i32, i1 } @llvm.smul.with.overflow.i32(i32, i32)
declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)
declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)
declare void @llvm.trap()

declare ptr @nl_context_create(i64, i64, ptr)
declare i64 @nl_context_base_offset(ptr)
declare i64 @nl_context_reservation_bytes(ptr)
declare void @nl_context_set_top_offset(ptr, i64)
declare void @nl_context_destroy(ptr)
declare ptr @nl_env_create(i32, ptr, i32)
declare void @nl_env_destroy(ptr)
declare ptr @nl_env_args(ptr)
declare ptr @nl_env_fs(ptr)
declare ptr @nl_env_out(ptr, i32)
declare void @nl_env_exit(i32) noreturn nounwind
declare void @nl_register_file(i32, ptr)
declare i32 @nl_test_selected_index()
declare void @nl_set_test_mode()
declare void @nl_test_var_storage_reset()
declare void @nl_test_var_storage_note(ptr, ptr, i64, i64)
declare i64 @nl_args_count(ptr)
declare ptr @nl_args_get(ptr, i64)
declare i64 @nl_arg_length(ptr)
declare i32 @nl_arg_byte(ptr, i64)
declare void @nl_fs_read(ptr, ptr, i32, i64, ptr, i64, ptr)
declare void @nl_fs_read_string(ptr, ptr, i32, i64, ptr, i64, i32, i64, ptr, ptr, ptr)
declare void @nl_fs_list(ptr, ptr, i32, i64, ptr, i64, ptr)
declare void @nl_fs_write(ptr, ptr, i32, i64, ptr, i32, i64, ptr)
declare void @nl_out_write(ptr, ptr, i32, i64, i32, ptr)
declare void @nl_out_int(ptr, i32, ptr)
declare void @nl_out_long(ptr, i64, ptr)
declare void @nl_out_arg(ptr, ptr, i32, ptr)
declare void @nl_print_int(i32)
declare void @nl_print_long(i64)
declare void @nl_print_bool(i1 zeroext)
declare void @nl_print_text(ptr)
declare void @nl_print_arg(ptr)
declare void @nl_print_set_fd(i32)
declare void @nl_print_error_prefix()
declare i64 @nl_ascii_format_pad_i64(i64, i64, i32, i32, ptr)
declare i64 @nl_ascii_format_i64(i64, ptr)
declare i64 @nl_ascii_decimal_length_i64(i64)
declare i32 @nl_ascii_compare(ptr, i64, ptr, i64)
declare i64 @nl_hash_ascii(ptr, i64, i64)
declare i64 @nl_utf8_offset(ptr, i64, i64)
declare i64 @nl_text_upper_copy(ptr, i64, ptr, ptr)
declare i32 @nl_bytes_are_ascii(ptr, i64)

declare ptr @nl_context_base(ptr readonly) nounwind willreturn memory(argmem: read)
declare ptr @nl_context_limit(ptr)
declare void @nl_context_note_peak_offset(ptr, i64)
declare void @nl_fail(i32, i32, i32, i32)
declare i64 @nl_stack_alloc_offset(ptr, i64, i64, i64, i32, i32, i32)
declare void @nl_print_ascii(ptr, i64)
declare void @nl_print_int_raw(i32)
declare void @nl_print_long_raw(i64)
declare void @nl_print_bool_raw(i1 zeroext)
declare void @nl_print_newline()
declare void @nl_expect_fail_header(i32, i32, i32, ptr)
declare void @nl_expect_fail_left()
declare void @nl_expect_fail_right()
declare void @nl_expect_fail_compare(i32, i32, i32, ptr, i64, i64, i32)
declare void @nl_expect_fail_bool(i32, i32, i32, ptr)
declare void @nl_fs_join(ptr, ptr, i32, i64, ptr, i32, i64, ptr)
declare void @nl_fs_list_with_extension(ptr, ptr, i32, i64, ptr, i64, ptr, i64, ptr)
declare i32 @nl_utf8_validate(ptr, i64, ptr, ptr)
declare i32 @nl_utf8_count(ptr, i64, ptr)
declare void @nl_ascii_upper_copy(ptr, ptr, i64)
declare i64 @nl_ascii_format_i64_radix(i64, i32, ptr)
declare i64 @nl_ascii_format_zero_padded_i64(i64, i64, ptr)
declare i64 @nl_pad_copy(ptr, i64, i64, i64, i32, ptr)
declare i32 @nl_parse_integer(ptr, i64, i32, i32, i32, ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare ptr @memmove(ptr, ptr, i64)
declare ptr @memset(ptr, i32, i64)
declare i32 @memcmp(ptr, ptr, i64)
declare i32 @bcmp(ptr, ptr, i64)

define ptr @nlc_context_current_base(ptr %nl.ctx) {
entry:
  %base = call ptr @nl_context_base(ptr %nl.ctx)
  ret ptr %base
}

define ptr @nlc_context_current_limit(ptr %nl.ctx) {
entry:
  %limit = call ptr @nl_context_limit(ptr %nl.ctx)
  ret ptr %limit
}

define void @nlc_context_note_peak(ptr %nl.ctx, i64 %top.offset) {
entry:
  call void @nl_context_note_peak_offset(ptr %nl.ctx, i64 %top.offset)
  ret void
}

define void @nlc_stack_grow(ptr %nl.ctx, i64 %needed, i32 %file, i32 %line, i32 %col) {
entry:
  %allocation = call i64 @nl_stack_alloc_offset(ptr %nl.ctx, i64 0, i64 %needed, i64 1, i32 %file, i32 %line, i32 %col)
  ret void
}

define void @nlc_fail(ptr %nl.ctx, i32 %kind, i32 %file, i32 %line, i32 %col) noreturn {
entry:
  call void @nl_fail(i32 %kind, i32 %file, i32 %line, i32 %col)
  unreachable
}

define void @nlc_print_ascii(ptr %nl.ctx, ptr %bytes, i64 %length) {
entry:
  call void @nl_print_ascii(ptr %bytes, i64 %length)
  ret void
}

define void @nlc_print_int_raw(ptr %nl.ctx, i32 %value) {
entry:
  call void @nl_print_int_raw(i32 %value)
  ret void
}

define void @nlc_print_long_raw(ptr %nl.ctx, i64 %value) {
entry:
  call void @nl_print_long_raw(i64 %value)
  ret void
}

define void @nlc_print_bool_raw(ptr %nl.ctx, i1 zeroext %value) {
entry:
  call void @nl_print_bool_raw(i1 zeroext %value)
  ret void
}

define void @nlc_print_newline(ptr %nl.ctx) {
entry:
  call void @nl_print_newline()
  ret void
}

define void @nlc_expect_fail_header(ptr %nl.ctx, i32 %file, i32 %line, i32 %col, ptr %source, i64 %source.length) {
entry:
  call void @nl_expect_fail_header(i32 %file, i32 %line, i32 %col, ptr %source)
  ret void
}

define void @nlc_expect_fail_left(ptr %nl.ctx) {
entry:
  call void @nl_expect_fail_left()
  ret void
}

define void @nlc_expect_fail_right(ptr %nl.ctx) {
entry:
  call void @nl_expect_fail_right()
  ret void
}

define void @nlc_expect_fail_compare(ptr %nl.ctx, i32 %file, i32 %line, i32 %col, ptr %source, i64 %source.length, i64 %left, i64 %right, i32 %is.bool) {
entry:
  call void @nl_expect_fail_compare(i32 %file, i32 %line, i32 %col, ptr %source, i64 %left, i64 %right, i32 %is.bool)
  ret void
}

define void @nlc_expect_fail_bool(ptr %nl.ctx, i32 %file, i32 %line, i32 %col, ptr %source, i64 %source.length) {
entry:
  call void @nl_expect_fail_bool(i32 %file, i32 %line, i32 %col, ptr %source)
  ret void
}

define void @nlc_fs_join(ptr %nl.ctx, ptr %fs, ptr %dir, i32 %dir.kind, i64 %dir.capacity, ptr %name, i32 %name.kind, i64 %name.capacity, ptr %result) {
entry:
  %raw = alloca [16396 x i8], align 8
  call void @nl_fs_join(ptr %fs, ptr %dir, i32 %dir.kind, i64 %dir.capacity, ptr %name, i32 %name.kind, i64 %name.capacity, ptr %raw)
  %raw.tag = load i32, ptr %raw, align 1
  %is.ok = icmp eq i32 %raw.tag, 0
  br i1 %is.ok, label %join.ok, label %join.error
join.ok:
  %raw.path = getelementptr i8, ptr %raw, i64 4
  %native.path = getelementptr i8, ptr %result, i64 8
  %copied = call ptr @memcpy(ptr %native.path, ptr %raw.path, i64 16392)
  store i32 0, ptr %result, align 1
  ret void
join.error:
  %raw.error.kind.addr = getelementptr i8, ptr %raw, i64 4
  %raw.error.code.addr = getelementptr i8, ptr %raw, i64 8
  %raw.error.kind = load i32, ptr %raw.error.kind.addr, align 1
  %raw.error.code = load i32, ptr %raw.error.code.addr, align 1
  %native.error.kind.addr = getelementptr i8, ptr %result, i64 8
  %native.error.code.addr = getelementptr i8, ptr %result, i64 12
  store i32 1, ptr %result, align 1
  store i32 %raw.error.kind, ptr %native.error.kind.addr, align 1
  store i32 %raw.error.code, ptr %native.error.code.addr, align 1
  ret void
}

define void @nlc_fs_list_with_extension(ptr %nl.ctx, ptr %fs, ptr %path, i32 %path.kind, i64 %path.capacity, ptr %extension, i64 %extension.length, ptr %output, i64 %capacity, ptr %result) {
entry:
  call void @nl_fs_list_with_extension(ptr %fs, ptr %path, i32 %path.kind, i64 %path.capacity, ptr %extension, i64 %extension.length, ptr %output, i64 %capacity, ptr %result)
  %status = load i32, ptr %result, align 1
  %failed = icmp ne i32 %status, 0
  br i1 %failed, label %list.done, label %list.convert
list.convert:
  %count = load i64, ptr %output, align 1
  store i64 0, ptr %output, align 1
  %lengths = alloca i64, i64 %count, align 8
  br label %list.cache.cond
list.cache.cond:
  %cache.index = phi i64 [ 0, %list.convert ], [ %cache.next, %list.cache.body ]
  %cache.more = icmp ult i64 %cache.index, %count
  br i1 %cache.more, label %list.cache.body, label %list.cache.done
list.cache.body:
  %slot.index.bytes = mul i64 %cache.index, 16392
  %slot.length.offset = add i64 %slot.index.bytes, 8
  %slot.length.addr = getelementptr i8, ptr %output, i64 %slot.length.offset
  %slot.length = load i64, ptr %slot.length.addr, align 1
  %cache.address = getelementptr i64, ptr %lengths, i64 %cache.index
  store i64 %slot.length, ptr %cache.address, align 8
  %cache.next = add i64 %cache.index, 1
  br label %list.cache.cond
list.cache.done:
  %last = sub i64 %count, 1
  %has.entries = icmp ne i64 %count, 0
  br i1 %has.entries, label %list.move.cond, label %list.restore.cond
list.move.cond:
  %move.index = phi i64 [ %last, %list.cache.done ], [ %move.previous, %list.move.step ]
  %move.bytes = mul i64 %move.index, 16392
  %move.source.offset = add i64 %move.bytes, 16
  %move.source = getelementptr i8, ptr %output, i64 %move.source.offset
  %native.index.bytes = mul i64 %move.index, 16384
  %native.lane.offset = mul i64 %capacity, 8
  %native.bytes.offset = add i64 %native.lane.offset, %native.index.bytes
  %native.bytes.base = add i64 %native.bytes.offset, 8
  %move.destination = getelementptr i8, ptr %output, i64 %native.bytes.base
  %move.length.address = getelementptr i64, ptr %lengths, i64 %move.index
  %move.length = load i64, ptr %move.length.address, align 8
  %move.length.bytes = mul i64 %move.length, 4
  %moved = call ptr @memmove(ptr %move.destination, ptr %move.source, i64 %move.length.bytes)
  %at.first = icmp eq i64 %move.index, 0
  br i1 %at.first, label %list.restore.cond, label %list.move.step
list.move.step:
  %move.previous = sub i64 %move.index, 1
  br label %list.move.cond
list.restore.cond:
  %restore.index = phi i64 [ 0, %list.cache.done ], [ 0, %list.move.cond ], [ %restore.next, %list.restore.body ]
  %restore.more = icmp ult i64 %restore.index, %count
  br i1 %restore.more, label %list.restore.body, label %list.publish
list.restore.body:
  %restore.length.address = getelementptr i64, ptr %lengths, i64 %restore.index
  %restore.length = load i64, ptr %restore.length.address, align 8
  %restore.index.bytes = mul i64 %restore.index, 8
  %restore.offset = add i64 %restore.index.bytes, 8
  %restore.address = getelementptr i8, ptr %output, i64 %restore.offset
  store i64 %restore.length, ptr %restore.address, align 1
  %restore.next = add i64 %restore.index, 1
  br label %list.restore.cond
list.publish:
  store i64 %count, ptr %output, align 1
  br label %list.done
list.done:
  ret void
}

define void @nl_core_nl_text_assert_valid(ptr %nl.ctx, ptr %data, i64 %length) {
entry:
  %valid = call i32 @nl_utf8_validate(ptr %data, i64 %length, ptr null, ptr null)
  %is.valid = icmp ne i32 %valid, 0
  br i1 %is.valid, label %text.valid, label %text.invalid
text.invalid:
  call void @nl_fail(i32 22, i32 0, i32 0, i32 0)
  unreachable
text.valid:
  ret void
}

define i64 @nl_core_utf8_error_offset(ptr %nl.ctx, ptr %data, i64 %length) {
entry:
  %valid.offset = alloca i64, align 8
  store i64 0, ptr %valid.offset, align 8
  %valid = call i32 @nl_utf8_validate(ptr %data, i64 %length, ptr %valid.offset, ptr null)
  %offset = load i64, ptr %valid.offset, align 8
  ret i64 %offset
}

define i64 @nl_core_non_ascii_offset(ptr %nl.ctx, ptr %data, i64 %length) {
entry:
  br label %ascii.cond
ascii.cond:
  %index = phi i64 [ 0, %entry ], [ %next, %ascii.step ]
  %more = icmp ult i64 %index, %length
  br i1 %more, label %ascii.body, label %ascii.done
ascii.body:
  %address = getelementptr i8, ptr %data, i64 %index
  %value = load i8, ptr %address, align 1
  %non.ascii = icmp ugt i8 %value, 127
  br i1 %non.ascii, label %ascii.found, label %ascii.step
ascii.found:
  ret i64 %index
ascii.step:
  %next = add i64 %index, 1
  br label %ascii.cond
ascii.done:
  ret i64 %length
}

define i64 @nl_core_nl_text_codepoint_count_trusted(ptr %nl.ctx, ptr %data, i64 %length) {
entry:
  %count = alloca i64, align 8
  store i64 0, ptr %count, align 8
  %valid = call i32 @nl_utf8_count(ptr %data, i64 %length, ptr %count)
  %is.valid = icmp ne i32 %valid, 0
  br i1 %is.valid, label %count.valid, label %count.invalid
count.invalid:
  call void @nl_fail(i32 22, i32 0, i32 0, i32 0)
  unreachable
count.valid:
  %value = load i64, ptr %count, align 8
  ret i64 %value
}

define i64 @nl_core_nl_text_format_ascii_upper(ptr %nl.ctx, ptr %source, i64 %length, ptr %destination) {
entry:
  call void @nl_ascii_upper_copy(ptr %source, ptr %destination, i64 %length)
  ret i64 %length
}

define i64 @nl_core_nl_text_format_number(ptr %nl.ctx, i64 %value, i64 %radix, ptr %destination) {
entry:
  %radix.i32 = trunc i64 %radix to i32
  %length = call i64 @nl_ascii_format_i64_radix(i64 %value, i32 %radix.i32, ptr %destination)
  ret i64 %length
}

define i64 @nl_core_nl_text_format_pad_zero(ptr %nl.ctx, i64 %value, i64 %width, ptr %destination) {
entry:
  %length = call i64 @nl_ascii_format_zero_padded_i64(i64 %value, i64 %width, ptr %destination)
  ret i64 %length
}

define i64 @nl_core_nl_text_format_pad(ptr %nl.ctx, ptr %source, i64 %byte.length, i64 %codepoints, i64 %width, i1 %pad.left, ptr %destination) {
entry:
  %pad.left.i32 = zext i1 %pad.left to i32
  %length = call i64 @nl_pad_copy(ptr %source, i64 %byte.length, i64 %codepoints, i64 %width, i32 %pad.left.i32, ptr %destination)
  ret i64 %length
}

define void @nl_core_parse_integer_option(ptr %nl.ctx, ptr %source, i64 %length, i64 %radix, i1 %literal, i64 %target.bits, ptr %destination) {
entry:
  %value.address = alloca i64, align 8
  store i64 0, ptr %value.address, align 8
  %radix.i32 = trunc i64 %radix to i32
  %literal.i32 = zext i1 %literal to i32
  %target.bits.i32 = trunc i64 %target.bits to i32
  %parsed = call i32 @nl_parse_integer(ptr %source, i64 %length, i32 %radix.i32, i32 %literal.i32, i32 %target.bits.i32, ptr %value.address)
  %is.valid = icmp ne i32 %parsed, 0
  %tag = select i1 %is.valid, i32 0, i32 1
  store i32 %tag, ptr %destination, align 1
  %value = load i64, ptr %value.address, align 8
  %is.int = icmp eq i64 %target.bits, 32
  br i1 %is.int, label %parse.int, label %parse.long
parse.int:
  %int.value = trunc i64 %value to i32
  %int.destination = getelementptr i8, ptr %destination, i64 4
  store i32 %int.value, ptr %int.destination, align 1
  ret void
parse.long:
  %long.destination = getelementptr i8, ptr %destination, i64 8
  store i64 %value, ptr %long.destination, align 1
  ret void
}

define void @nl_fn_0(ptr %nl.ctx, i64 %nl.top) {
entry:
  %local.0 = alloca i32, align 1
  %v3 = add i32 0, 4
  store i32 %v3, ptr %local.0, align 1
  %v5 = load i32, ptr %local.0, align 1
  call void @nlc_print_int_raw(ptr %nl.ctx, i32 %v5)
  call void @nlc_print_newline(ptr %nl.ctx)
  ret void
}

@.nl.file.0 = private unnamed_addr constant [8 x i8] c"main.nl\00", align 1
@.nl.file.table.0 = private constant [1 x { ptr, i64 }] [{ ptr, i64 } { ptr getelementptr inbounds ([8 x i8], ptr @.nl.file.0, i64 0, i64 0), i64 7 }], align 8
@.nl.entry.main = private unnamed_addr constant [5 x i8] c"main\00", align 1
@.nl.entry.table = private constant [1 x { ptr, i64 }] [{ ptr, i64 } { ptr getelementptr inbounds ([5 x i8], ptr @.nl.entry.main, i64 0, i64 0), i64 4 }], align 8
@.nl.struct.open.0 = private unnamed_addr constant [4 x i8] c" { \00", align 1
@.nl.struct.close.0 = private unnamed_addr constant [3 x i8] c" }\00", align 1
@.nl.struct.separator.0 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.nl.struct.colon.0 = private unnamed_addr constant [3 x i8] c": \00", align 1
@.nl.enum.open.0 = private unnamed_addr constant [2 x i8] c"(\00", align 1
@.nl.enum.close.0 = private unnamed_addr constant [2 x i8] c")\00", align 1
@.nl.enum.separator.0 = private unnamed_addr constant [3 x i8] c", \00", align 1
@.nl.enum.unit.0 = private unnamed_addr constant [3 x i8] c"()\00", align 1
@.nl.sum.some = private unnamed_addr constant [5 x i8] c"some\00", align 1
@.nl.sum.none = private unnamed_addr constant [5 x i8] c"none\00", align 1
@.nl.sum.ok = private unnamed_addr constant [3 x i8] c"ok\00", align 1
@.nl.sum.err = private unnamed_addr constant [4 x i8] c"err\00", align 1
@.nl.sum.lparen = private unnamed_addr constant [2 x i8] c"(\00", align 1
@.nl.sum.rparen = private unnamed_addr constant [2 x i8] c")\00", align 1
@.nl.sum.separator = private unnamed_addr constant [3 x i8] c", \00", align 1
@.nl.sum.unit = private unnamed_addr constant [3 x i8] c"()\00", align 1
@.nl.sum.Full = private unnamed_addr constant [5 x i8] c"Full\00", align 1

define i32 @main(i32 %argc, ptr %argv, ptr %envp, ptr %auxv) {
entry:
  %nl.ctx = call ptr @nl_context_create(i64 4096, i64 0, ptr getelementptr inbounds ([8 x i8], ptr @.nl.file.0, i64 0, i64 0))
  %nl.env = call ptr @nl_env_create(i32 %argc, ptr %argv, i32 2)
  call void @nl_register_file(i32 0, ptr getelementptr inbounds ([8 x i8], ptr @.nl.file.0, i64 0, i64 0))
  %nl.top = call i64 @nl_context_base_offset(ptr %nl.ctx)
  call void @nl_fn_0(ptr %nl.ctx, i64 %nl.top)
  call void @nl_env_destroy(ptr %nl.env)
  call void @nl_context_destroy(ptr %nl.ctx)
  ret i32 0
}

!9000 = !{!"next-lang context and program storage"}
!9001 = !{!"context base", !9000}
!9002 = !{!9001, !9001, i64 0}
!9004 = !{!"program storage", !9000}
!9003 = !{!9004, !9004, i64 0}

; nlc-link-ir end
