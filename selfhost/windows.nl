// Unbounded text: `arena<N>` and `Window<arena>` (provisional names; see docs/design/text-arena.md).
//
// An arena is a pool of one-byte octets: a 24-byte header (bytes used, capacity, open-builder mark + 1 or 0) followed by N
// bytes. It is owned by its declaring local, parameter or struct field and never copied (it is a pool, so the pool-owner pass
// applies). A window is a plain long: start in the high 32 bits, length in the low 32. It never owns bytes and is read-only
// (nothing writes into the middle of an arena), so a slice is a smaller window and nothing is copied. The arena only grows, so
// a window never dangles; arena memory lives and ends with the owner of the arena.
//
// A window's type names its arena (`Window<src>`), checked like a pool id by pool_owners.nl. Operations that read the bytes
// (`w[i]`, `==`, `<`, print, to_bytes, ...) find the arena through that owner: pool_owners.nl records the owner's binding in the
// node's fact (`binding`) and this file's emitter loads the arena's address from it. The bytes are read by small helper
// functions (`@nlw_*`) written once into the module.

// The provisional type name `Window` is spelled in compiler_types.nl (resolution), pool_owners.nl (owner argument), compiler_tables.nl
// (builtin names) and compiler_unsupported_core_sys.nl: search for "Window" to rename it.

const FACT_WINDOW_OP: long = 65536L

const WOP_LEN: long = 1L
const WOP_SLICE: long = 2L
const WOP_AT: long = 3L
const WOP_EQ: long = 4L
const WOP_NE: long = 5L
const WOP_LT: long = 6L
const WOP_LE: long = 7L
const WOP_GT: long = 8L
const WOP_GE: long = 9L
const WOP_PRINT: long = 10L
const WOP_TO_BYTES: long = 11L
const WOP_STARTS_WITH: long = 12L
const WOP_ENDS_WITH: long = 13L
const WOP_FIND: long = 14L
const WOP_CONTAINS: long = 15L
const WOP_ADD: long = 20L
const WOP_USED: long = 21L
const WOP_BEGIN: long = 22L
const WOP_PUSH: long = 23L
const WOP_APPEND: long = 24L
const WOP_FINISH: long = 25L

fn type_is_arena(compiler: CompilerTables, type_id: long) -> bool {
    type_kind(compiler, type_id) == TYPE_KIND_POOL && collection_element_type(compiler, type_id) == TY_OCTET
}

// Whether the window operation reads the arena's bytes through the window's owner (the others need no arena, or have the arena
// as their receiver).
fn window_op_needs_owner(op: long) -> bool {
    op >= WOP_AT && op <= WOP_CONTAINS
}

// The operation a method name stands for on a window (receiver) or an arena, or 0.
fn window_method_op(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    method_token: long,
    receiver_is_arena: bool,
) -> long {
    if receiver_is_arena {
        if token_is_word_at(source, tokens, files, file_index, method_token, "add") { WOP_ADD }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "used") { WOP_USED }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "begin") { WOP_BEGIN }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "push") { WOP_PUSH }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "append") { WOP_APPEND }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "finish") { WOP_FINISH }
        else { 0L }
    } else {
        if token_is_word_at(source, tokens, files, file_index, method_token, "len") { WOP_LEN }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "slice") { WOP_SLICE }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "to_bytes") { WOP_TO_BYTES }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "starts_with") { WOP_STARTS_WITH }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "ends_with") { WOP_ENDS_WITH }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "find") { WOP_FIND }
        else if token_is_word_at(source, tokens, files, file_index, method_token, "contains") { WOP_CONTAINS }
        else { 0L }
    }
}

// Checks a method call whose receiver is a window or an arena. Returns false when the receiver is neither (the caller goes on
// with the other method kinds); otherwise sets the node's facts (or reports the error) and returns true.
fn check_window_method(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    node: long,
    receiver: long,
    expected: long,
) -> bool {
    if receiver < 0L { return false }
    let receiver_ty = compiler.facts[receiver].ty
    let is_arena = type_is_arena(compiler, receiver_ty)
    if !is_arena && receiver_ty != TY_WINDOW { return false }
    let syntax = tables.nodes[node]
    if !compiler.c_runtime { fail_at_message(env, files, compiler, file_index, syntax.start, "arenas and windows need the C runtime") }
    let op = window_method_op(source, tokens, files, file_index, syntax.token, is_arena)
    if op == 0L {
        if is_arena { fail_at_message(env, files, compiler, file_index, syntax.anchor, "an arena has add, used, begin, push, append and finish") }
        fail_at_message(env, files, compiler, file_index, syntax.anchor, "a window has len, slice, to_bytes, starts_with, ends_with, contains and find")
    }
    let arguments = count_children(tables, compiler, node) - 1L
    var argument = compiler.child_next[receiver]
    var result_ty = TY_UNIT
    if op == WOP_LEN || op == WOP_USED || op == WOP_BEGIN || op == WOP_FINISH || op == WOP_TO_BYTES {
        if arguments != 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "this method takes no arguments") }
        result_ty = if op == WOP_LEN || op == WOP_USED { TY_LONG } else if op == WOP_FINISH { TY_WINDOW } else { TY_UNIT }
    }
    if op >= WOP_STARTS_WITH && op <= WOP_CONTAINS {
        if arguments != 1L { fail_at_message(env, files, compiler, file_index, syntax.start, "this method takes one argument") }
        let needle_ty = compiler.facts[argument].ty
        let needle_kind = type_kind(compiler, needle_ty)
        if needle_ty != TY_WINDOW && needle_kind != TYPE_KIND_ASCII && needle_kind != TYPE_KIND_BYTES {
            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "this takes a window of the same arena or a bounded Ascii or Bytes value")
        }
        result_ty = if op == WOP_FIND { TY_LONG } else { TY_BOOL }
    }
    if op == WOP_SLICE {
        if arguments != 2L { fail_at_message(env, files, compiler, file_index, syntax.start, "slice takes a range: w.slice(a..b)") }
        require_type(env, files, compiler, file_index, argument, TY_LONG, compiler.facts[argument].ty, tables)
        let upper = compiler.child_next[argument]
        require_type(env, files, compiler, file_index, upper, TY_LONG, compiler.facts[upper].ty, tables)
        result_ty = TY_WINDOW
    }
    if op == WOP_TO_BYTES {
        let expected_kind = type_kind(compiler, expected)
        if expected < 0L || (expected_kind != TYPE_KIND_BYTES && expected_kind != TYPE_KIND_ASCII) {
            fail_at_message(env, files, compiler, file_index, syntax.start, "to_bytes needs a bounded Bytes or Ascii expected type (let b: Bytes max 64 = w.to_bytes())")
        }
        result_ty = expected
    }
    if op == WOP_ADD || op == WOP_APPEND {
        if arguments != 1L { fail_at_message(env, files, compiler, file_index, syntax.start, "this method takes one argument") }
        let argument_ty = compiler.facts[argument].ty
        let argument_kind = type_kind(compiler, argument_ty)
        let is_window_argument = op == WOP_APPEND && argument_ty == TY_WINDOW
        if !is_window_argument && argument_kind != TYPE_KIND_ASCII && argument_kind != TYPE_KIND_BYTES {
            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "an arena takes a bounded Ascii or Bytes value (append also takes a window)")
        }
        result_ty = if op == WOP_ADD { TY_WINDOW } else { TY_UNIT }
    }
    if op == WOP_PUSH {
        if arguments != 1L { fail_at_message(env, files, compiler, file_index, syntax.start, "push takes one byte") }
        let argument_ty = compiler.facts[argument].ty
        if argument_ty != TY_BYTE { fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "push takes a byte") }
        result_ty = TY_UNIT
    }
    // Writing methods need a writable place: a var, a write parameter or a field.
    if op == WOP_ADD || op == WOP_BEGIN || op == WOP_PUSH || op == WOP_APPEND || op == WOP_FINISH {
        let receiver_binding = compiler.facts[receiver].binding
        let is_field = tables.nodes[receiver].kind == NodeKind.Field
        if !is_field && (receiver_binding < 0L || !compiler.bindings[receiver_binding].mutable) {
            fail_at_message(env, files, compiler, file_index, syntax.start, "adding to an arena requires a var, a write parameter or a field")
        }
    }
    if expected >= 0L && expected != result_ty && op != WOP_TO_BYTES {
        require_type(env, files, compiler, file_index, node, expected, result_ty, tables)
    }
    let flags = (if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }) | FACT_WINDOW_OP
    compiler.facts[node] = NodeFact { ty: result_ty, flags, binding: compiler.facts[receiver].binding, function: -1L, literal: op }
    true
}

// The expected type of argument `child_index` of a window or arena method (so literals take the right type), or -1.
fn window_method_argument_type(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    compiler: CompilerTables,
    file_index: long,
    method_token: long,
    receiver_ty: long,
) -> long {
    if receiver_ty == TY_WINDOW { return if token_is_word_at(source, tokens, files, file_index, method_token, "slice") { TY_LONG } else { -1L } }
    if type_is_arena(compiler, receiver_ty) && token_is_word_at(source, tokens, files, file_index, method_token, "push") { return TY_BYTE }
    -1L
}

// Comparison operator (8 == 9 !=, 10 < 11 <= 12 > 13 >=) between two windows.
fn window_compare_op(op: long) -> long {
    if op == 8L { WOP_EQ } else if op == 9L { WOP_NE } else if op == 10L { WOP_LT } else if op == 11L { WOP_LE } else if op == 12L { WOP_GT } else { WOP_GE }
}

// ---------------------------------------------------------------------------------------------------------------------
// Emission

// Whether any arena type exists (the helpers are written only then).
fn package_has_arena(compiler: CompilerTables) -> bool {
    for type_id in 0L..type_count(compiler) {
        if type_is_arena(compiler, type_id) { return true }
    }
    false
}

// Header size of an arena (bytes used, capacity, builder mark) before its bytes.
const ARENA_HEADER_SIZE: long = 24L

fn emit_window_helpers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    if !package_has_arena(compiler) { return }
    // failure kinds: 16 index out of range, 25 arena capacity exhausted, 26 builder misuse, 27 does not fit
    ir_write_ascii(compiler, ir, "define internal i32 @nlw_at(ptr %ctx, ptr %a, i64 %w, i64 %i) {\nentry:\n  %len = and i64 %w, 4294967295\n  %ok = icmp ult i64 %i, %len\n  br i1 %ok, label %in, label %bad\nbad:\n  call void @nlc_fail(ptr %ctx, i32 16, i32 0, i32 0, i32 0)\n  unreachable\nin:\n  %start = lshr i64 %w, 32\n  %pos = add i64 %start, %i\n  %base = getelementptr i8, ptr %a, i64 24\n  %q = getelementptr i8, ptr %base, i64 %pos\n  %b = load i8, ptr %q, align 1\n  %r = zext i8 %b to i32\n  ret i32 %r\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal i64 @nlw_slice(ptr %ctx, i64 %w, i64 %a, i64 %b) {\nentry:\n  %len = and i64 %w, 4294967295\n  %c1 = icmp sge i64 %a, 0\n  %c2 = icmp sle i64 %a, %b\n  %c3 = icmp sle i64 %b, %len\n  %c12 = and i1 %c1, %c2\n  %ok = and i1 %c12, %c3\n  br i1 %ok, label %in, label %bad\nbad:\n  call void @nlc_fail(ptr %ctx, i32 16, i32 0, i32 0, i32 0)\n  unreachable\nin:\n  %start = lshr i64 %w, 32\n  %ns = add i64 %start, %a\n  %nl = sub i64 %b, %a\n  %hi = shl i64 %ns, 32\n  %r = or i64 %hi, %nl\n  ret i64 %r\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal i32 @nlw_cmp(ptr %a, i64 %x, i64 %y) {\nentry:\n  %lx = and i64 %x, 4294967295\n  %ly = and i64 %y, 4294967295\n  %sx = lshr i64 %x, 32\n  %sy = lshr i64 %y, 32\n  %lt = icmp ult i64 %lx, %ly\n  %m = select i1 %lt, i64 %lx, i64 %ly\n  %base = getelementptr i8, ptr %a, i64 24\n  %px = getelementptr i8, ptr %base, i64 %sx\n  %py = getelementptr i8, ptr %base, i64 %sy\n  %c = call i32 @memcmp(ptr %px, ptr %py, i64 %m)\n  %nz = icmp ne i32 %c, 0\n  br i1 %nz, label %diff, label %same\ndiff:\n  %neg = icmp slt i32 %c, 0\n  %r = select i1 %neg, i32 -1, i32 1\n  ret i32 %r\nsame:\n  %eq = icmp eq i64 %lx, %ly\n  %o = select i1 %lt, i32 -1, i32 1\n  %r2 = select i1 %eq, i32 0, i32 %o\n  ret i32 %r2\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal void @nlw_print(ptr %ctx, ptr %a, i64 %w) {\nentry:\n  %len = and i64 %w, 4294967295\n  %start = lshr i64 %w, 32\n  %base = getelementptr i8, ptr %a, i64 24\n  %p = getelementptr i8, ptr %base, i64 %start\n  call void @nlc_print_ascii(ptr %ctx, ptr %p, i64 %len)\n  call void @nlc_print_newline(ptr %ctx)\n  ret void\n}\n\n")
    // raw forms over (pointer, length) pairs: used when the other operand is a bounded Ascii/Bytes value
    ir_write_ascii(compiler, ir, "define internal ptr @nlw_ptr(ptr %a, i64 %w) {\nentry:\n  %start = lshr i64 %w, 32\n  %base = getelementptr i8, ptr %a, i64 24\n  %p = getelementptr i8, ptr %base, i64 %start\n  ret ptr %p\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal i32 @nlw_cmp_raw(ptr %px, i64 %lx, ptr %py, i64 %ly) {\nentry:\n  %lt = icmp ult i64 %lx, %ly\n  %m = select i1 %lt, i64 %lx, i64 %ly\n  %c = call i32 @memcmp(ptr %px, ptr %py, i64 %m)\n  %nz = icmp ne i32 %c, 0\n  br i1 %nz, label %diff, label %same\ndiff:\n  %neg = icmp slt i32 %c, 0\n  %r = select i1 %neg, i32 -1, i32 1\n  ret i32 %r\nsame:\n  %eq = icmp eq i64 %lx, %ly\n  %o = select i1 %lt, i32 -1, i32 1\n  %r2 = select i1 %eq, i32 0, i32 %o\n  ret i32 %r2\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal i1 @nlw_prefix(ptr %p, i64 %len, ptr %np, i64 %nlen) {\nentry:\n  %fits = icmp ule i64 %nlen, %len\n  br i1 %fits, label %check, label %no\ncheck:\n  %c = call i32 @memcmp(ptr %p, ptr %np, i64 %nlen)\n  %eq = icmp eq i32 %c, 0\n  ret i1 %eq\nno:\n  ret i1 false\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal i1 @nlw_suffix(ptr %p, i64 %len, ptr %np, i64 %nlen) {\nentry:\n  %fits = icmp ule i64 %nlen, %len\n  br i1 %fits, label %check, label %no\ncheck:\n  %skip = sub i64 %len, %nlen\n  %q = getelementptr i8, ptr %p, i64 %skip\n  %c = call i32 @memcmp(ptr %q, ptr %np, i64 %nlen)\n  %eq = icmp eq i32 %c, 0\n  ret i1 %eq\nno:\n  ret i1 false\n}\n\n")
    // find: the first index where the needle occurs, or -1 (an empty needle is found at 0)
    ir_write_ascii(compiler, ir, "define internal i64 @nlw_find(ptr %p, i64 %len, ptr %np, i64 %nlen) {\nentry:\n  %fits = icmp ule i64 %nlen, %len\n  br i1 %fits, label %scan, label %none\nscan:\n  %last = sub i64 %len, %nlen\n  br label %loop\nloop:\n  %i = phi i64 [ 0, %scan ], [ %next, %step ]\n  %more = icmp ule i64 %i, %last\n  br i1 %more, label %body, label %none\nbody:\n  %q = getelementptr i8, ptr %p, i64 %i\n  %c = call i32 @memcmp(ptr %q, ptr %np, i64 %nlen)\n  %eq = icmp eq i32 %c, 0\n  br i1 %eq, label %found, label %step\nstep:\n  %next = add i64 %i, 1\n  br label %loop\nfound:\n  ret i64 %i\nnone:\n  ret i64 -1\n}\n\n")
    // content hash of a window (FNV-1a over its bytes): equal text hashes equal wherever it sits in the arena
    ir_write_ascii(compiler, ir, "define internal i64 @nlw_hash(ptr %a, i64 %w) {\nentry:\n  %len = and i64 %w, 4294967295\n  %p = call ptr @nlw_ptr(ptr %a, i64 %w)\n  br label %loop\nloop:\n  %i = phi i64 [ 0, %entry ], [ %next, %body ]\n  %h = phi i64 [ -3750763034362895579, %entry ], [ %mixed, %body ]\n  %more = icmp ult i64 %i, %len\n  br i1 %more, label %body, label %done\nbody:\n  %q = getelementptr i8, ptr %p, i64 %i\n  %b = load i8, ptr %q, align 1\n  %bz = zext i8 %b to i64\n  %x = xor i64 %h, %bz\n  %mixed = mul i64 %x, 1099511628211\n  %next = add i64 %i, 1\n  br label %loop\ndone:\n  ret i64 %h\n}\n\n")
    // append: copies n bytes to the end of the arena; returns the start offset. The capacity check fails loudly.
    ir_write_ascii(compiler, ir, "define internal i64 @nlw_append(ptr %ctx, ptr %a, ptr %data, i64 %n) {\nentry:\n  %count = load i64, ptr %a, align 1\n  %capp = getelementptr i8, ptr %a, i64 8\n  %cap = load i64, ptr %capp, align 1\n  %new = add i64 %count, %n\n  %ok = icmp ule i64 %new, %cap\n  br i1 %ok, label %in, label %full\nfull:\n  call void @nlc_fail(ptr %ctx, i32 25, i32 0, i32 0, i32 0)\n  unreachable\nin:\n  %base = getelementptr i8, ptr %a, i64 24\n  %dst = getelementptr i8, ptr %base, i64 %count\n  %m = call ptr @memcpy(ptr %dst, ptr %data, i64 %n)\n  store i64 %new, ptr %a, align 1\n  ret i64 %count\n}\n\n")
    // builder state: the word at offset 16 is 0 (closed) or the builder's start mark + 1
    ir_write_ascii(compiler, ir, "define internal void @nlw_need_builder(ptr %ctx, ptr %a, i1 %want_open) {\nentry:\n  %bp = getelementptr i8, ptr %a, i64 16\n  %b = load i64, ptr %bp, align 1\n  %is_open = icmp ne i64 %b, 0\n  %ok = icmp eq i1 %is_open, %want_open\n  br i1 %ok, label %in, label %bad\nbad:\n  call void @nlc_fail(ptr %ctx, i32 26, i32 0, i32 0, i32 0)\n  unreachable\nin:\n  ret void\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal i64 @nlw_add(ptr %ctx, ptr %a, ptr %data, i64 %n) {\nentry:\n  call void @nlw_need_builder(ptr %ctx, ptr %a, i1 false)\n  %start = call i64 @nlw_append(ptr %ctx, ptr %a, ptr %data, i64 %n)\n  %hi = shl i64 %start, 32\n  %r = or i64 %hi, %n\n  ret i64 %r\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal void @nlw_begin(ptr %ctx, ptr %a) {\nentry:\n  call void @nlw_need_builder(ptr %ctx, ptr %a, i1 false)\n  %count = load i64, ptr %a, align 1\n  %mark = add i64 %count, 1\n  %bp = getelementptr i8, ptr %a, i64 16\n  store i64 %mark, ptr %bp, align 1\n  ret void\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal void @nlw_push(ptr %ctx, ptr %a, i32 %byte) {\nentry:\n  call void @nlw_need_builder(ptr %ctx, ptr %a, i1 true)\n  %count = load i64, ptr %a, align 1\n  %capp = getelementptr i8, ptr %a, i64 8\n  %cap = load i64, ptr %capp, align 1\n  %ok = icmp ult i64 %count, %cap\n  br i1 %ok, label %in, label %full\nfull:\n  call void @nlc_fail(ptr %ctx, i32 25, i32 0, i32 0, i32 0)\n  unreachable\nin:\n  %base = getelementptr i8, ptr %a, i64 24\n  %dst = getelementptr i8, ptr %base, i64 %count\n  %b8 = trunc i32 %byte to i8\n  store i8 %b8, ptr %dst, align 1\n  %new = add i64 %count, 1\n  store i64 %new, ptr %a, align 1\n  ret void\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal void @nlw_append_bytes(ptr %ctx, ptr %a, ptr %data, i64 %n) {\nentry:\n  call void @nlw_need_builder(ptr %ctx, ptr %a, i1 true)\n  %s = call i64 @nlw_append(ptr %ctx, ptr %a, ptr %data, i64 %n)\n  ret void\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal void @nlw_append_window(ptr %ctx, ptr %a, i64 %w) {\nentry:\n  %len = and i64 %w, 4294967295\n  %start = lshr i64 %w, 32\n  %base = getelementptr i8, ptr %a, i64 24\n  %p = getelementptr i8, ptr %base, i64 %start\n  call void @nlw_append_bytes(ptr %ctx, ptr %a, ptr %p, i64 %len)\n  ret void\n}\n\n")
    ir_write_ascii(compiler, ir, "define internal i64 @nlw_finish(ptr %ctx, ptr %a) {\nentry:\n  call void @nlw_need_builder(ptr %ctx, ptr %a, i1 true)\n  %bp = getelementptr i8, ptr %a, i64 16\n  %b = load i64, ptr %bp, align 1\n  %mark = sub i64 %b, 1\n  %count = load i64, ptr %a, align 1\n  %len = sub i64 %count, %mark\n  store i64 0, ptr %bp, align 1\n  %hi = shl i64 %mark, 32\n  %r = or i64 %hi, %len\n  ret i64 %r\n}\n\n")
    // copy out to a bounded value (len at offset 0, bytes at data_off); Ascii also checks that every byte is below 128
    ir_write_ascii(compiler, ir, "define internal void @nlw_to_bytes(ptr %ctx, ptr %a, i64 %w, ptr %dst, i64 %max, i64 %data_off, i1 %ascii) {\nentry:\n  %len = and i64 %w, 4294967295\n  %start = lshr i64 %w, 32\n  %fits = icmp ule i64 %len, %max\n  br i1 %fits, label %copy, label %bad\nbad:\n  call void @nlc_fail(ptr %ctx, i32 27, i32 0, i32 0, i32 0)\n  unreachable\ncopy:\n  store i64 %len, ptr %dst, align 1\n  %d = getelementptr i8, ptr %dst, i64 %data_off\n  %base = getelementptr i8, ptr %a, i64 24\n  %s = getelementptr i8, ptr %base, i64 %start\n  %m = call ptr @memcpy(ptr %d, ptr %s, i64 %len)\n  br i1 %ascii, label %loop, label %done\nloop:\n  %i = phi i64 [ 0, %copy ], [ %next, %step ]\n  %more = icmp ult i64 %i, %len\n  br i1 %more, label %body, label %done\nbody:\n  %p = getelementptr i8, ptr %s, i64 %i\n  %byte = load i8, ptr %p, align 1\n  %high = icmp slt i8 %byte, 0\n  br i1 %high, label %bad, label %step\nstep:\n  %next = add i64 %i, 1\n  br label %loop\ndone:\n  ret void\n}\n\n")
}

// Writes the arena's address (a value reference) for the window operation `node`; `receiver_location` is used for arena methods.
// Returns the pointer serial to pass to emit_location_pointer_reference with the location.
fn window_arena_location(tables: ParseTables, compiler: CompilerTables, node: long, op: long) -> StorageLocation {
    if op >= WOP_ADD {
        collection_value_location(tables, compiler, compiler.child_first[node])
    } else {
        let binding = compiler.facts[node].binding
        let field_offset = if compiler.facts[node].literal >= 256L { (compiler.facts[node].literal >> 8L) - 1L } else { 0L }
        if binding >= 0L && compiler.bindings[binding].parameter { compiler_location(compiler, 3L, binding, field_offset) }
        else { compiler_location(compiler, 1L, binding, field_offset) }
    }
}

fn emit_window_op(
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    file_index: long,
) {
    let op = compiler.facts[node].literal & 255L
    let first = compiler.child_first[node]
    let second = if first >= 0L { compiler.child_next[first] } else { -1L }
    let third = if second >= 0L { compiler.child_next[second] } else { -1L }
    if op == WOP_LEN {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = and i64 "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ", 4294967295\n")
        return
    }
    if op == WOP_SLICE {
        if tables.nodes[node].extra == 1L {
            // a..=b includes b
            ir_write_ascii(compiler, ir, "  %window.upper."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 "); ir_write_value_ref(compiler, ir, third); ir_write_ascii(compiler, ir, ", 1\n")
        }
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i64 @nlw_slice(ptr %nl.ctx, i64 ")
        ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, second); ir_write_ascii(compiler, ir, ", i64 ")
        if tables.nodes[node].extra == 1L { ir_write_ascii(compiler, ir, "%window.upper."); ir_write_number(compiler, ir, node) }
        else { ir_write_value_ref(compiler, ir, third) }
        ir_write_ascii(compiler, ir, ")\n")
        return
    }
    let location = window_arena_location(tables, compiler, node, op)
    let serial = emit_location_pointer_materialization(compiler, ir, location)
    if op == WOP_USED {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, serial); ir_write_ascii(compiler, ir, ", align 1\n")
        return
    }
    if op == WOP_BEGIN {
        ir_write_ascii(compiler, ir, "  call void @nlw_begin(ptr %nl.ctx, ptr "); emit_location_pointer_reference(compiler, ir, location, serial); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    if op == WOP_FINISH {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i64 @nlw_finish(ptr %nl.ctx, ptr "); emit_location_pointer_reference(compiler, ir, location, serial); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    if op == WOP_PUSH {
        ir_write_ascii(compiler, ir, "  call void @nlw_push(ptr %nl.ctx, ptr "); emit_location_pointer_reference(compiler, ir, location, serial); ir_write_ascii(compiler, ir, ", i32 "); ir_write_value_ref(compiler, ir, second); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    if op == WOP_ADD || op == WOP_APPEND {
        let argument_ty = compiler.facts[second].ty
        if argument_ty == TY_WINDOW {
            ir_write_ascii(compiler, ir, "  call void @nlw_append_window(ptr %nl.ctx, ptr "); emit_location_pointer_reference(compiler, ir, location, serial); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, second); ir_write_ascii(compiler, ir, ")\n")
            return
        }
        let text_location = aggregate_source_location_for_node(tables, compiler, second)
        let text_serial = emit_location_pointer_materialization(compiler, ir, text_location)
        let data_offset = text_data_offset(compiler, argument_ty)
        ir_write_ascii(compiler, ir, "  %window.len."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, text_location, text_serial)
        ir_write_ascii(compiler, ir, ", align 1\n  %window.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, text_location, text_serial)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, data_offset); ir_push_byte(compiler, ir, 10)
        if op == WOP_ADD {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i64 @nlw_add(ptr %nl.ctx, ptr ")
        } else { ir_write_ascii(compiler, ir, "  call void @nlw_append_bytes(ptr %nl.ctx, ptr ") }
        emit_location_pointer_reference(compiler, ir, location, serial)
        ir_write_ascii(compiler, ir, ", ptr %window.data."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %window.len."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    // operations through the window's owner
    if op == WOP_AT {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i32 @nlw_at(ptr %nl.ctx, ptr "); emit_location_pointer_reference(compiler, ir, location, serial)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, second); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    // comparisons, starts_with, ends_with, contains, find: the other operand is a window of the same arena or a bounded value
    if (op >= WOP_EQ && op <= WOP_GE) || (op >= WOP_STARTS_WITH && op <= WOP_CONTAINS) {
        let other_ty = compiler.facts[second].ty
        // window pointer and length
        ir_write_ascii(compiler, ir, "  %window.p."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call ptr @nlw_ptr(ptr "); emit_location_pointer_reference(compiler, ir, location, serial)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ")\n  %window.l."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = and i64 "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ", 4294967295\n")
        // the other operand's pointer and length
        if other_ty == TY_WINDOW {
            ir_write_ascii(compiler, ir, "  %window.np."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call ptr @nlw_ptr(ptr "); emit_location_pointer_reference(compiler, ir, location, serial)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, second); ir_write_ascii(compiler, ir, ")\n  %window.nl."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = and i64 "); ir_write_value_ref(compiler, ir, second); ir_write_ascii(compiler, ir, ", 4294967295\n")
        } else {
            let other_location = aggregate_source_location_for_node(tables, compiler, second)
            let other_serial = emit_location_pointer_materialization(compiler, ir, other_location)
            ir_write_ascii(compiler, ir, "  %window.nl."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, other_location, other_serial)
            ir_write_ascii(compiler, ir, ", align 1\n  %window.np."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, other_location, other_serial)
            ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, text_data_offset(compiler, other_ty)); ir_push_byte(compiler, ir, 10)
        }
        if op >= WOP_EQ && op <= WOP_GE {
            ir_write_ascii(compiler, ir, "  %window.cmp."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i32 @nlw_cmp_raw(ptr %window.p."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ", i64 %window.l."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %window.np."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %window.nl."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, ")\n  %v"); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, if op == WOP_EQ { " = icmp eq" } else if op == WOP_NE { " = icmp ne" } else if op == WOP_LT { " = icmp slt" } else if op == WOP_LE { " = icmp sle" } else if op == WOP_GT { " = icmp sgt" } else { " = icmp sge" })
            ir_write_ascii(compiler, ir, " i32 %window.cmp."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
            return
        }
        if op == WOP_STARTS_WITH || op == WOP_ENDS_WITH {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, if op == WOP_STARTS_WITH { " = call i1 @nlw_prefix(ptr %window.p." } else { " = call i1 @nlw_suffix(ptr %window.p." })
        } else if op == WOP_FIND {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i64 @nlw_find(ptr %window.p.")
        } else {
            ir_write_ascii(compiler, ir, "  %window.found."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i64 @nlw_find(ptr %window.p.")
        }
        ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %window.l."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", ptr %window.np."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", i64 %window.nl."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
        if op == WOP_CONTAINS {
            ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sge i64 %window.found."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
        }
        return
    }
    if op == WOP_PRINT {
        ir_write_ascii(compiler, ir, "  call void @nlw_print(ptr %nl.ctx, ptr "); emit_location_pointer_reference(compiler, ir, location, serial); ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    if op == WOP_TO_BYTES {
        let result_ty = compiler.facts[node].ty
        let destination = aggregate_destination_location(compiler, 0L, node)
        let destination_serial = emit_location_pointer_materialization(compiler, ir, destination)
        ir_write_ascii(compiler, ir, "  call void @nlw_to_bytes(ptr %nl.ctx, ptr "); emit_location_pointer_reference(compiler, ir, location, serial)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_value_ref(compiler, ir, first); ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_serial)
        ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, text_max_bytes(compiler, result_ty)); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, text_data_offset(compiler, result_ty))
        ir_write_ascii(compiler, ir, if type_kind(compiler, result_ty) == TYPE_KIND_ASCII { ", i1 true)\n" } else { ", i1 false)\n" })
        return
    }
    compiler.ir_overflow = true
}
