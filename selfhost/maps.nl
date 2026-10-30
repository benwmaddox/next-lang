// map<K, V, N>: up to N keys, hashed. A map value is [count: i64][used: i64], then N entries in
// insertion order, then an index of 4-byte slots (a power of two, at least twice N). An entry is a
// plain record [state: i64][key][value] with state 1 for a live entry and 0 for a removed one. The
// index holds entry number + 1 (0 is empty) and is probed linearly from the key hash. Entries are only
// appended, so a run of lookups in insertion order reads the entries array sequentially. A removal
// marks its entry dead; when the entries fill up with dead ones they are squeezed out (order kept) and
// the index is rebuilt. Keys and values are numbers, bools, enums or text. The operations are
// generated once per map type as small functions (find, get, set, remove, compact); a method call
// passes numbers by value and text by pointer.

const COLLECTION_METHOD_MAP_GET: long = 1009L
const COLLECTION_METHOD_MAP_SET: long = 1010L
const COLLECTION_METHOD_MAP_REMOVE: long = 1011L
const COLLECTION_METHOD_MAP_CONTAINS: long = 1012L

const MAP_HASH_MULTIPLIER: long = -7046029254386353131L
const MAP_FNV_OFFSET: long = -3750763034362895579L
const MAP_FNV_PRIME: long = 1099511628211L

fn map_method_kind(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    method_token: long,
) -> long {
    if token_is_word_at(source, tokens, files, file_index, method_token, "count") { COLLECTION_METHOD_COUNT }
    else if token_is_word_at(source, tokens, files, file_index, method_token, "get") { COLLECTION_METHOD_MAP_GET }
    else if token_is_word_at(source, tokens, files, file_index, method_token, "set") { COLLECTION_METHOD_MAP_SET }
    else if token_is_word_at(source, tokens, files, file_index, method_token, "remove") { COLLECTION_METHOD_MAP_REMOVE }
    else if token_is_word_at(source, tokens, files, file_index, method_token, "contains") { COLLECTION_METHOD_MAP_CONTAINS }
    else { 0L }
}

fn map_key_type(compiler: CompilerTables, type_id: long) -> long {
    compiler.enum_payloads[type_record(compiler, type_id).field_start].ty
}

fn map_value_type(compiler: CompilerTables, type_id: long) -> long {
    compiler.enum_payloads[type_record(compiler, type_id).field_start + 1L].ty
}

fn map_capacity(compiler: CompilerTables, type_id: long) -> long {
    type_record(compiler, type_id).field_count
}

// The number of slots: the smallest power of two that is at least twice the capacity.
fn map_slot_count(capacity: long) -> long {
    var slots = 2L
    for step in 0L..62L {
        if slots >= capacity * 2L { break }
        slots = slots * 2L
    }
    slots
}

// A key or value a map can hold: a number, bool or enum with no payload (by value), or text.
fn map_operand_is_text(compiler: CompilerTables, type_id: long) -> bool {
    collection_text_leaf(type_kind(compiler, type_id))
}

fn map_operand_is_scalar(compiler: CompilerTables, type_id: long) -> bool {
    let kind = type_kind(compiler, type_id)
    let size = value_type_size(compiler, type_id)
    (kind == TYPE_KIND_SCALAR || (kind == TYPE_KIND_ENUM && !is_sum_type(compiler, type_id))) &&
        (size == 1L || size == 4L || size == 8L)
}

fn map_operand_supported(compiler: CompilerTables, type_id: long) -> bool {
    map_operand_is_text(compiler, type_id) || map_operand_is_scalar(compiler, type_id)
}

fn map_key_offset(compiler: CompilerTables, type_id: long) -> long {
    checked_layout_size_align(8L, value_type_align(compiler, map_key_type(compiler, type_id)))
}

fn map_value_offset(compiler: CompilerTables, type_id: long) -> long {
    let key = map_key_type(compiler, type_id)
    let after_key = checked_layout_size_add(map_key_offset(compiler, type_id), value_type_size(compiler, key))
    checked_layout_size_align(after_key, value_type_align(compiler, map_value_type(compiler, type_id)))
}

fn map_slot_align(compiler: CompilerTables, type_id: long) -> long {
    var alignment = 8L
    let key_align = value_type_align(compiler, map_key_type(compiler, type_id))
    let value_align = value_type_align(compiler, map_value_type(compiler, type_id))
    if key_align > alignment { alignment = key_align }
    if value_align > alignment { alignment = value_align }
    alignment
}

fn map_slot_size(compiler: CompilerTables, type_id: long) -> long {
    let after_value = checked_layout_size_add(map_value_offset(compiler, type_id), value_type_size(compiler, map_value_type(compiler, type_id)))
    checked_layout_size_align(after_value, map_slot_align(compiler, type_id))
}

fn map_type_matches(compiler: CompilerTables, key: long, value: long, capacity: long) -> long {
    for type_id in 0L..type_count(compiler) {
        let record = type_record(compiler, type_id)
        if type_record_kind(record) == TYPE_KIND_MAP && record.field_count == capacity &&
            compiler.enum_payloads[record.field_start].ty == key &&
            compiler.enum_payloads[record.field_start + 1L].ty == value { return type_id }
    }
    -1L
}

fn intern_map_type(
    compiler: write CompilerTables,
    key: long,
    value: long,
    capacity: long,
    file_index: long,
    node: long,
    name_id: long,
    name_token: long,
) -> long {
    let existing = map_type_matches(compiler, key, value, capacity)
    if existing >= 0L { return existing }
    let field_start = compiler.enum_payloads.count()
    compiler.enum_payloads.push(EnumPayloadRecord { case_index: 0L, type_node: -1L, ty: key, offset: 0L }).unwrap()
    compiler.enum_payloads.push(EnumPayloadRecord { case_index: 1L, type_node: -1L, ty: value, offset: 0L }).unwrap()
    let type_id = append_type_record(compiler, TypeRecord {
        kind_state: TYPE_KIND_MAP * 16L,
        name_id,
        name_token,
        node,
        file: file_index,
        field_start,
        field_count: capacity,
        size: 0L,
        align: 8L,
        helper_mask: 0L,
    })
    if value_type_size(compiler, key) >= 0L && value_type_size(compiler, value) >= 0L {
        let slot_size = map_slot_size(compiler, type_id)
        let entries = checked_size_product(capacity, slot_size)
        let index = checked_size_product(map_slot_count(capacity), 4L)
        let size = if entries < 0L { entries } else if index < 0L { index }
            else { checked_layout_size_align(checked_layout_size_add(checked_layout_size_add(16L, entries), index), 8L) }
        if size == -2L {
            set_type_layout(compiler, type_id, -1L, 8L, TYPE_STATE_LAYOUT_OVERFLOW)
        } else if size < 0L || size >= MAX_VALUE_SIZE {
            set_type_layout(compiler, type_id, MAX_VALUE_SIZE, map_slot_align(compiler, type_id), 2L)
        } else { set_type_layout(compiler, type_id, size, map_slot_align(compiler, type_id), 2L) }
    }
    type_id
}

// ---- generated per-type functions -------------------------------------------------------------

fn map_param_type(compiler: CompilerTables, type_id: long) -> Ascii max 4 {
    if map_operand_is_text(compiler, type_id) { "ptr" } else { "i64" }
}

fn ir_map_sym(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, name: Ascii max 16, type_id: long) {
    ir_write_ascii(compiler, ir, "@nl.map."); ir_write_ascii(compiler, ir, name); ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, type_id)
}

fn ir_map_number(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, value: long) {
    ir_write_number(compiler, ir, value)
}

// Load a scalar of `size` bytes from `pointer_name` and widen it to i64 as %result_name.
fn emit_map_scalar_load(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, size: long, pointer_name: Ascii max 24, result_name: Ascii max 24) {
    if size == 8L {
        ir_write_ascii(compiler, ir, "  %"); ir_write_ascii(compiler, ir, result_name); ir_write_ascii(compiler, ir, " = load i64, ptr %"); ir_write_ascii(compiler, ir, pointer_name); ir_push_byte(compiler, ir, 10)
    } else {
        let storage = if size == 4L { "i32" } else { "i8" }
        let widen = if size == 4L { "sext" } else { "zext" }
        ir_write_ascii(compiler, ir, "  %"); ir_write_ascii(compiler, ir, result_name); ir_write_ascii(compiler, ir, ".raw = load "); ir_write_ascii(compiler, ir, storage)
        ir_write_ascii(compiler, ir, ", ptr %"); ir_write_ascii(compiler, ir, pointer_name); ir_write_ascii(compiler, ir, "\n  %"); ir_write_ascii(compiler, ir, result_name)
        ir_write_ascii(compiler, ir, " = "); ir_write_ascii(compiler, ir, widen); ir_push_byte(compiler, ir, 32); ir_write_ascii(compiler, ir, storage)
        ir_write_ascii(compiler, ir, " %"); ir_write_ascii(compiler, ir, result_name); ir_write_ascii(compiler, ir, ".raw to i64\n")
    }
}

// Store the i64 in %value_name as a scalar of `size` bytes at %pointer_name.
fn emit_map_scalar_store(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, size: long, pointer_name: Ascii max 24, value_name: Ascii max 24, tag: long) {
    if size == 8L {
        ir_write_ascii(compiler, ir, "  store i64 %"); ir_write_ascii(compiler, ir, value_name); ir_write_ascii(compiler, ir, ", ptr %"); ir_write_ascii(compiler, ir, pointer_name); ir_push_byte(compiler, ir, 10)
    } else {
        let storage = if size == 4L { "i32" } else { "i8" }
        ir_write_ascii(compiler, ir, "  %"); ir_write_ascii(compiler, ir, value_name); ir_write_ascii(compiler, ir, ".t"); ir_write_number(compiler, ir, tag)
        ir_write_ascii(compiler, ir, " = trunc i64 %"); ir_write_ascii(compiler, ir, value_name); ir_write_ascii(compiler, ir, " to "); ir_write_ascii(compiler, ir, storage)
        ir_write_ascii(compiler, ir, "\n  store "); ir_write_ascii(compiler, ir, storage); ir_write_ascii(compiler, ir, " %"); ir_write_ascii(compiler, ir, value_name)
        ir_write_ascii(compiler, ir, ".t"); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ", ptr %"); ir_write_ascii(compiler, ir, pointer_name); ir_push_byte(compiler, ir, 10)
    }
}

// Copy a text value (its length word and live bytes) from %source_name to %destination_name.
fn emit_map_text_copy(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, data_offset: long, destination_name: Ascii max 24, source_name: Ascii max 24, tag: long) {
    ir_write_ascii(compiler, ir, "  %tc.len"); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, " = load i64, ptr %"); ir_write_ascii(compiler, ir, source_name)
    ir_write_ascii(compiler, ir, "\n  %tc.n"); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, " = add i64 %tc.len"); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ", ")
    ir_write_number(compiler, ir, data_offset)
    ir_write_ascii(compiler, ir, "\n  %tc.c"); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, " = call ptr @nl.mem.copy(ptr %"); ir_write_ascii(compiler, ir, destination_name)
    ir_write_ascii(compiler, ir, ", ptr %"); ir_write_ascii(compiler, ir, source_name); ir_write_ascii(compiler, ir, ", i64 %tc.n"); ir_write_number(compiler, ir, tag); ir_write_ascii(compiler, ir, ")\n")
}

fn emit_map_functions_for_type(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, type_id: long) {
    let key = map_key_type(compiler, type_id)
    let value = map_value_type(compiler, type_id)
    let capacity = map_capacity(compiler, type_id)
    let slots = map_slot_count(capacity)
    let mask = slots - 1L
    let slot_size = map_slot_size(compiler, type_id)
    let key_offset = map_key_offset(compiler, type_id)
    let value_offset = map_value_offset(compiler, type_id)
    let key_is_text = map_operand_is_text(compiler, key)
    let value_is_text = map_operand_is_text(compiler, value)
    let key_size = value_type_size(compiler, key)
    let value_size = value_type_size(compiler, value)
    let key_data = if key_is_text { text_data_offset(compiler, key) } else { 0L }
    let value_data = if value_is_text { text_data_offset(compiler, value) } else { 0L }
    let key_param = map_param_type(compiler, key)
    let value_param = map_param_type(compiler, value)

    // hash(key)
    ir_write_ascii(compiler, ir, "define internal i64 "); ir_map_sym(compiler, ir, "hash", type_id); ir_write_ascii(compiler, ir, "(")
    ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k) {\nentry:\n")
    if key_is_text {
        ir_write_ascii(compiler, ir, "  %len = load i64, ptr %k\n  %data = getelementptr i8, ptr %k, i64 "); ir_write_number(compiler, ir, key_data)
        ir_write_ascii(compiler, ir, "\n  br label %loop\nloop:\n  %i = phi i64 [ 0, %entry ], [ %in, %body ]\n  %h = phi i64 [ "); ir_write_number(compiler, ir, MAP_FNV_OFFSET)
        ir_write_ascii(compiler, ir, ", %entry ], [ %hn, %body ]\n  %more = icmp ult i64 %i, %len\n  br i1 %more, label %body, label %done\nbody:\n")
        ir_write_ascii(compiler, ir, "  %p = getelementptr i8, ptr %data, i64 %i\n  %b = load i8, ptr %p\n  %bz = zext i8 %b to i64\n  %x = xor i64 %h, %bz\n  %hn = mul i64 %x, ")
        ir_write_number(compiler, ir, MAP_FNV_PRIME)
        ir_write_ascii(compiler, ir, "\n  %in = add i64 %i, 1\n  br label %loop\ndone:\n  %m = mul i64 %h, "); ir_write_number(compiler, ir, MAP_HASH_MULTIPLIER)
    } else {
        ir_write_ascii(compiler, ir, "  %m = mul i64 %k, "); ir_write_number(compiler, ir, MAP_HASH_MULTIPLIER)
    }
    ir_write_ascii(compiler, ir, "\n  %s = lshr i64 %m, 32\n  %r = xor i64 %m, %s\n  ret i64 %r\n}\n\n")

    // hashslot(ptr slotkey): hash of a key already stored in a slot
    ir_write_ascii(compiler, ir, "define internal i64 "); ir_map_sym(compiler, ir, "hashslot", type_id); ir_write_ascii(compiler, ir, "(ptr %p) {\nentry:\n")
    if key_is_text {
        ir_write_ascii(compiler, ir, "  %h = call i64 "); ir_map_sym(compiler, ir, "hash", type_id); ir_write_ascii(compiler, ir, "(ptr %p)\n")
    } else {
        emit_map_scalar_load(compiler, ir, key_size, "p", "k")
        ir_write_ascii(compiler, ir, "  %h = call i64 "); ir_map_sym(compiler, ir, "hash", type_id); ir_write_ascii(compiler, ir, "(i64 %k)\n")
    }
    ir_write_ascii(compiler, ir, "  ret i64 %h\n}\n\n")

    // same(key, ptr slotkey)
    ir_write_ascii(compiler, ir, "define internal i1 "); ir_map_sym(compiler, ir, "same", type_id); ir_write_ascii(compiler, ir, "(")
    ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k, ptr %p) {\nentry:\n")
    if key_is_text {
        ir_write_ascii(compiler, ir, "  %la = load i64, ptr %k\n  %lb = load i64, ptr %p\n  %eq = icmp eq i64 %la, %lb\n  br i1 %eq, label %cmp, label %no\ncmp:\n")
        ir_write_ascii(compiler, ir, "  %da = getelementptr i8, ptr %k, i64 "); ir_write_number(compiler, ir, key_data)
        ir_write_ascii(compiler, ir, "\n  %db = getelementptr i8, ptr %p, i64 "); ir_write_number(compiler, ir, key_data)
        ir_write_ascii(compiler, ir, "\n  br label %cmp.loop\ncmp.loop:\n  %ci = phi i64 [ 0, %cmp ], [ %ci1, %cmp.step ]\n  %cdone = icmp uge i64 %ci, %la\n  br i1 %cdone, label %yes, label %cmp.byte\ncmp.byte:\n  %pa = getelementptr i8, ptr %da, i64 %ci\n  %pb = getelementptr i8, ptr %db, i64 %ci\n  %ba = load i8, ptr %pa\n  %bb = load i8, ptr %pb\n  %bsame = icmp eq i8 %ba, %bb\n  br i1 %bsame, label %cmp.step, label %no\ncmp.step:\n  %ci1 = add i64 %ci, 1\n  br label %cmp.loop\nyes:\n  ret i1 true\nno:\n  ret i1 false\n}\n\n")
    } else {
        emit_map_scalar_load(compiler, ir, key_size, "p", "v")
        ir_write_ascii(compiler, ir, "  %z = icmp eq i64 %k, %v\n  ret i1 %z\n}\n\n")
    }

    let index_base = 16L + capacity * slot_size

    // link(map, hash, entry): put entry + 1 in the first empty index slot on the hash probe path
    ir_write_ascii(compiler, ir, "define internal void "); ir_map_sym(compiler, ir, "link", type_id)
    ir_write_ascii(compiler, ir, "(ptr %map, i64 %h, i64 %e) {\nentry:\n  %start = and i64 %h, "); ir_write_number(compiler, ir, mask)
    ir_write_ascii(compiler, ir, "\n  %e1 = add i64 %e, 1\n  %e32 = trunc i64 %e1 to i32\n  br label %scan\nscan:\n  %i = phi i64 [ %start, %entry ], [ %next, %scan.next ]\n  %io = mul i64 %i, 4\n  %io2 = add i64 %io, ")
    ir_write_number(compiler, ir, index_base)
    ir_write_ascii(compiler, ir, "\n  %sp = getelementptr i8, ptr %map, i64 %io2\n  %v = load i32, ptr %sp\n  %free = icmp eq i32 %v, 0\n  br i1 %free, label %fill, label %scan.next\nscan.next:\n  %i1 = add i64 %i, 1\n  %next = and i64 %i1, ")
    ir_write_number(compiler, ir, mask)
    ir_write_ascii(compiler, ir, "\n  br label %scan\nfill:\n  store i32 %e32, ptr %sp\n  ret void\n}\n\n")

    // find(map, key) -> entry index or -1
    ir_write_ascii(compiler, ir, "define internal i64 "); ir_map_sym(compiler, ir, "find", type_id); ir_write_ascii(compiler, ir, "(ptr %map, ")
    ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k) {\nentry:\n  %h = call i64 "); ir_map_sym(compiler, ir, "hash", type_id)
    ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k)\n  %start = and i64 %h, "); ir_write_number(compiler, ir, mask)
    ir_write_ascii(compiler, ir, "\n  br label %probe\nprobe:\n  %i = phi i64 [ %start, %entry ], [ %next, %advance ]\n  %n = phi i64 [ 0, %entry ], [ %n1, %advance ]\n  %io = mul i64 %i, 4\n  %io2 = add i64 %io, ")
    ir_write_number(compiler, ir, index_base)
    ir_write_ascii(compiler, ir, "\n  %sp = getelementptr i8, ptr %map, i64 %io2\n  %v = load i32, ptr %sp\n  %empty = icmp eq i32 %v, 0\n  br i1 %empty, label %miss, label %check\ncheck:\n  %e32 = sub i32 %v, 1\n  %e = zext i32 %e32 to i64\n  %eo = mul i64 %e, ")
    ir_write_number(compiler, ir, slot_size)
    ir_write_ascii(compiler, ir, "\n  %eo2 = add i64 %eo, 16\n  %ep = getelementptr i8, ptr %map, i64 %eo2\n  %st = load i64, ptr %ep\n  %live = icmp eq i64 %st, 1\n  br i1 %live, label %cmp, label %advance\ncmp:\n  %kp = getelementptr i8, ptr %ep, i64 ")
    ir_write_number(compiler, ir, key_offset)
    ir_write_ascii(compiler, ir, "\n  %same = call i1 "); ir_map_sym(compiler, ir, "same", type_id); ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, key_param)
    ir_write_ascii(compiler, ir, " %k, ptr %kp)\n  br i1 %same, label %hit, label %advance\nadvance:\n  %i1 = add i64 %i, 1\n  %next = and i64 %i1, "); ir_write_number(compiler, ir, mask)
    ir_write_ascii(compiler, ir, "\n  %n1 = add i64 %n, 1\n  %full = icmp uge i64 %n1, "); ir_write_number(compiler, ir, slots)
    ir_write_ascii(compiler, ir, "\n  br i1 %full, label %miss, label %probe\nhit:\n  ret i64 %e\nmiss:\n  ret i64 -1\n}\n\n")

    // get(map, key) -> pointer to the value or null
    ir_write_ascii(compiler, ir, "define internal ptr "); ir_map_sym(compiler, ir, "get", type_id); ir_write_ascii(compiler, ir, "(ptr %map, ")
    ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k) {\nentry:\n  %idx = call i64 "); ir_map_sym(compiler, ir, "find", type_id)
    ir_write_ascii(compiler, ir, "(ptr %map, "); ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k)\n  %found = icmp sge i64 %idx, 0\n  br i1 %found, label %some, label %none\nsome:\n  %off = mul i64 %idx, ")
    ir_write_number(compiler, ir, slot_size)
    ir_write_ascii(compiler, ir, "\n  %so = add i64 %off, "); ir_write_number(compiler, ir, 16L + value_offset)
    ir_write_ascii(compiler, ir, "\n  %vp = getelementptr i8, ptr %map, i64 %so\n  ret ptr %vp\nnone:\n  ret ptr null\n}\n\n")

    // compact(map): squeeze the removed entries out (keeping order) and rebuild the index
    ir_write_ascii(compiler, ir, "define internal void "); ir_map_sym(compiler, ir, "compact", type_id)
    ir_write_ascii(compiler, ir, "(ptr %map) {\nentry:\n  %usedp = getelementptr i8, ptr %map, i64 8\n  %used = load i64, ptr %usedp\n  br label %loop\nloop:\n  %e = phi i64 [ 0, %entry ], [ %e1, %latch ]\n  %d = phi i64 [ 0, %entry ], [ %d2, %latch ]\n  %more = icmp ult i64 %e, %used\n  br i1 %more, label %body, label %rebuild\nbody:\n  %eo = mul i64 %e, ")
    ir_write_number(compiler, ir, slot_size)
    ir_write_ascii(compiler, ir, "\n  %eo2 = add i64 %eo, 16\n  %ep = getelementptr i8, ptr %map, i64 %eo2\n  %st = load i64, ptr %ep\n  %live = icmp eq i64 %st, 1\n  br i1 %live, label %move, label %latch\nmove:\n  %do = mul i64 %d, ")
    ir_write_number(compiler, ir, slot_size)
    ir_write_ascii(compiler, ir, "\n  %do2 = add i64 %do, 16\n  %dp = getelementptr i8, ptr %map, i64 %do2\n  %mv = call ptr @nl.mem.move(ptr %dp, ptr %ep, i64 "); ir_write_number(compiler, ir, slot_size)
    ir_write_ascii(compiler, ir, ")\n  %d1 = add i64 %d, 1\n  br label %latch\nlatch:\n  %d2 = phi i64 [ %d, %body ], [ %d1, %move ]\n  %e1 = add i64 %e, 1\n  br label %loop\nrebuild:\n  store i64 %d, ptr %usedp\n  %ip = getelementptr i8, ptr %map, i64 ")
    ir_write_number(compiler, ir, index_base)
    ir_write_ascii(compiler, ir, "\n  %clr = call ptr @nl.mem.set(ptr %ip, i32 0, i64 "); ir_write_number(compiler, ir, slots * 4L)
    ir_write_ascii(compiler, ir, ")\n  br label %relink\nrelink:\n  %r = phi i64 [ 0, %rebuild ], [ %r1, %relink.body ]\n  %rm = icmp ult i64 %r, %d\n  br i1 %rm, label %relink.body, label %done\nrelink.body:\n  %ro = mul i64 %r, ")
    ir_write_number(compiler, ir, slot_size)
    ir_write_ascii(compiler, ir, "\n  %ro2 = add i64 %ro, "); ir_write_number(compiler, ir, 16L + key_offset)
    ir_write_ascii(compiler, ir, "\n  %kp = getelementptr i8, ptr %map, i64 %ro2\n  %hh = call i64 "); ir_map_sym(compiler, ir, "hashslot", type_id)
    ir_write_ascii(compiler, ir, "(ptr %kp)\n  call void "); ir_map_sym(compiler, ir, "link", type_id)
    ir_write_ascii(compiler, ir, "(ptr %map, i64 %hh, i64 %r)\n  %r1 = add i64 %r, 1\n  br label %relink\ndone:\n  ret void\n}\n\n")

    // set(map, key, value) -> true unless the map is full
    ir_write_ascii(compiler, ir, "define internal i1 "); ir_map_sym(compiler, ir, "set", type_id); ir_write_ascii(compiler, ir, "(ptr %map, ")
    ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k, "); ir_write_ascii(compiler, ir, value_param)
    ir_write_ascii(compiler, ir, " %v) {\nentry:\n  %idx = call i64 "); ir_map_sym(compiler, ir, "find", type_id); ir_write_ascii(compiler, ir, "(ptr %map, ")
    ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k)\n  %found = icmp sge i64 %idx, 0\n  br i1 %found, label %update, label %insert\nupdate:\n  %uoff = mul i64 %idx, ")
    ir_write_number(compiler, ir, slot_size)
    ir_write_ascii(compiler, ir, "\n  %uo = add i64 %uoff, "); ir_write_number(compiler, ir, 16L + value_offset)
    ir_write_ascii(compiler, ir, "\n  %up = getelementptr i8, ptr %map, i64 %uo\n")
    if value_is_text { emit_map_text_copy(compiler, ir, value_data, "up", "v", 1L) } else { emit_map_scalar_store(compiler, ir, value_size, "up", "v", 1L) }
    ir_write_ascii(compiler, ir, "  ret i1 true\ninsert:\n  %usedp = getelementptr i8, ptr %map, i64 8\n  %used = load i64, ptr %usedp\n  %roomy = icmp ult i64 %used, "); ir_write_number(compiler, ir, capacity)
    ir_write_ascii(compiler, ir, "\n  br i1 %roomy, label %place, label %packed\npacked:\n  %cnt = load i64, ptr %map\n  %slack = icmp ult i64 %cnt, "); ir_write_number(compiler, ir, capacity)
    ir_write_ascii(compiler, ir, "\n  br i1 %slack, label %squeeze, label %full\nfull:\n  ret i1 false\nsqueeze:\n  call void "); ir_map_sym(compiler, ir, "compact", type_id)
    ir_write_ascii(compiler, ir, "(ptr %map)\n  br label %place\nplace:\n  %e = load i64, ptr %usedp\n  %eoff = mul i64 %e, "); ir_write_number(compiler, ir, slot_size)
    ir_write_ascii(compiler, ir, "\n  %eo = add i64 %eoff, 16\n  %ep = getelementptr i8, ptr %map, i64 %eo\n  store i64 1, ptr %ep\n  %kp = getelementptr i8, ptr %ep, i64 "); ir_write_number(compiler, ir, key_offset); ir_push_byte(compiler, ir, 10)
    if key_is_text { emit_map_text_copy(compiler, ir, key_data, "kp", "k", 2L) } else { emit_map_scalar_store(compiler, ir, key_size, "kp", "k", 2L) }
    ir_write_ascii(compiler, ir, "  %vp = getelementptr i8, ptr %ep, i64 "); ir_write_number(compiler, ir, value_offset); ir_push_byte(compiler, ir, 10)
    if value_is_text { emit_map_text_copy(compiler, ir, value_data, "vp", "v", 3L) } else { emit_map_scalar_store(compiler, ir, value_size, "vp", "v", 3L) }
    ir_write_ascii(compiler, ir, "  %e2 = add i64 %e, 1\n  store i64 %e2, ptr %usedp\n  %cnt2o = load i64, ptr %map\n  %cnt2 = add i64 %cnt2o, 1\n  store i64 %cnt2, ptr %map\n  %h = call i64 "); ir_map_sym(compiler, ir, "hash", type_id)
    ir_write_ascii(compiler, ir, "("); ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k)\n  call void "); ir_map_sym(compiler, ir, "link", type_id)
    ir_write_ascii(compiler, ir, "(ptr %map, i64 %h, i64 %e)\n  ret i1 true\n}\n\n")

    // remove(map, key, out) -> true if the key was present; the old value is copied to out
    ir_write_ascii(compiler, ir, "define internal i1 "); ir_map_sym(compiler, ir, "remove", type_id); ir_write_ascii(compiler, ir, "(ptr %map, ")
    ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k, ptr %out) {\nentry:\n  %idx = call i64 "); ir_map_sym(compiler, ir, "find", type_id)
    ir_write_ascii(compiler, ir, "(ptr %map, "); ir_write_ascii(compiler, ir, key_param); ir_write_ascii(compiler, ir, " %k)\n  %found = icmp sge i64 %idx, 0\n  br i1 %found, label %take, label %absent\nabsent:\n  ret i1 false\ntake:\n  %toff = mul i64 %idx, ")
    ir_write_number(compiler, ir, slot_size)
    ir_write_ascii(compiler, ir, "\n  %tov = add i64 %toff, 16\n  %ep = getelementptr i8, ptr %map, i64 %tov\n  %tp = getelementptr i8, ptr %ep, i64 "); ir_write_number(compiler, ir, value_offset); ir_push_byte(compiler, ir, 10)
    if value_is_text {
        emit_map_text_copy(compiler, ir, value_data, "out", "tp", 4L)
    } else {
        ir_write_ascii(compiler, ir, "  %tc = call ptr @nl.mem.copy(ptr %out, ptr %tp, i64 "); ir_write_number(compiler, ir, value_size); ir_write_ascii(compiler, ir, ")\n")
    }
    ir_write_ascii(compiler, ir, "  store i64 0, ptr %ep\n  %rc = load i64, ptr %map\n  %rc2 = sub i64 %rc, 1\n  store i64 %rc2, ptr %map\n  ret i1 true\n}\n\n")
}

fn emit_map_type_functions(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    emit_map_memory_wrappers(compiler, ir)
    for type_id in 0L..type_count(compiler) {
        if type_kind(compiler, type_id) == TYPE_KIND_MAP && type_state(compiler, type_id) == 2L {
            let key = map_key_type(compiler, type_id)
            let value = map_value_type(compiler, type_id)
            if map_operand_supported(compiler, key) && map_operand_supported(compiler, value) {
                emit_map_functions_for_type(compiler, ir, type_id)
            }
        }
    }
}

// ---- method calls -----------------------------------------------------------------------------

// A key or value argument as the generated functions take it: an i64 (numbers, widened) or a
// pointer to the text value.
struct MapOperand {
    text: bool
    serial: long
    location: StorageLocation
    pointer: long
}

fn emit_map_operand_prepare(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    argument: long,
    type_id: long,
    node: long,
    slot: long,
) -> MapOperand {
    if map_operand_is_text(compiler, type_id) {
        let source_kind = if tables.nodes[argument].kind == NodeKind.Name && compiler.facts[argument].binding >= 0L {
            if compiler.bindings[compiler.facts[argument].binding].parameter { 2L } else { 1L }
        } else if tables.nodes[argument].kind == NodeKind.Field { 3L } else { 0L }
        let source_id = if source_kind == 1L || source_kind == 2L { compiler.facts[argument].binding } else { argument }
        let location = aggregate_source_location(compiler, source_kind, source_id)
        let pointer = emit_location_pointer_materialization(compiler, ir, location)
        return MapOperand { text: true, serial: 0L, location, pointer }
    }
    let serial = node * 4L + slot
    let argument_type = compiler.facts[argument].ty
    let llvm = llvm_type_name(argument_type)
    ir_write_ascii(compiler, ir, "  %map.arg."); ir_write_number(compiler, ir, serial)
    if llvm == "i64" {
        ir_write_ascii(compiler, ir, " = add i64 0, "); ir_write_value_ref(compiler, ir, argument)
    } else if llvm == "i1" {
        ir_write_ascii(compiler, ir, " = zext i1 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64")
    } else {
        ir_write_ascii(compiler, ir, " = sext "); ir_write_ascii(compiler, ir, llvm); ir_push_byte(compiler, ir, 32); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64")
    }
    ir_push_byte(compiler, ir, 10)
    MapOperand { text: false, serial, location: compiler_location(compiler, 0L, argument, 0L), pointer: -1L }
}

fn ir_write_map_operand(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, operand: MapOperand) {
    if operand.text {
        ir_write_ascii(compiler, ir, "ptr "); emit_location_pointer_reference(compiler, ir, operand.location, operand.pointer)
    } else {
        ir_write_ascii(compiler, ir, "i64 %map.arg."); ir_write_number(compiler, ir, operand.serial)
    }
}

fn emit_map_method(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    method: long,
) {
    let receiver = compiler.child_first[node]
    let first = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
    let type_id = compiler.facts[receiver].ty
    let key = map_key_type(compiler, type_id)
    let value = map_value_type(compiler, type_id)
    var location = collection_value_location(tables, compiler, receiver)
    if tables.nodes[receiver].kind == NodeKind.Field {
        let address_id = emit_late_place_address(tables, compiler, ir, receiver)
        location = compiler_location(compiler, 2L, address_id, 0L)
    }
    let pointer_serial = emit_location_pointer_materialization(compiler, ir, location)
    if method == COLLECTION_METHOD_COUNT {
        ir_write_ascii(compiler, ir, "  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr ")
        emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", align 1\n")
        return
    }
    let key_operand = emit_map_operand_prepare(tables, compiler, ir, first, key, node, 0L)
    if method == COLLECTION_METHOD_MAP_CONTAINS {
        ir_write_ascii(compiler, ir, "  %map.find."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i64 "); ir_map_sym(compiler, ir, "find", type_id)
        ir_write_ascii(compiler, ir, "(ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", ")
        ir_write_map_operand(compiler, ir, key_operand)
        ir_write_ascii(compiler, ir, ")\n  %v"); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp sge i64 %map.find."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", 0\n")
        return
    }
    if method == COLLECTION_METHOD_MAP_SET {
        let value_argument = compiler.child_next[first]
        let value_operand = emit_map_operand_prepare(tables, compiler, ir, value_argument, value, node, 1L)
        ir_write_ascii(compiler, ir, "  %map.set."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i1 "); ir_map_sym(compiler, ir, "set", type_id)
        ir_write_ascii(compiler, ir, "(ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", ")
        ir_write_map_operand(compiler, ir, key_operand); ir_write_ascii(compiler, ir, ", "); ir_write_map_operand(compiler, ir, value_operand)
        ir_write_ascii(compiler, ir, ")\n  br i1 %map.set."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %map.set.ok."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", label %map.set.full."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmap.set.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_collection_capacity_result_tag(compiler, ir, node, 0L)
        ir_write_ascii(compiler, ir, "  br label %map.set.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmap.set.full."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_collection_capacity_result_tag(compiler, ir, node, 1L)
        ir_write_ascii(compiler, ir, "  br label %map.set.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmap.set.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        return
    }
    // get and remove produce an Option of the value
    let result_type = compiler.facts[node].ty
    let payload = sum_payload_record(compiler, result_type, 0L, 0L)
    let address = enum_temporary_address(node, MAX_TREE_NODES * 3L + 2L)
    emit_layout_address(compiler, ir, address, storage_location_with_offset(aggregate_destination_location(compiler, 0L, node), payload.offset))
    if method == COLLECTION_METHOD_MAP_GET {
        ir_write_ascii(compiler, ir, "  %map.get."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call ptr "); ir_map_sym(compiler, ir, "get", type_id)
        ir_write_ascii(compiler, ir, "(ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", ")
        ir_write_map_operand(compiler, ir, key_operand)
        ir_write_ascii(compiler, ir, ")\n  %map.get.found."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = icmp ne ptr %map.get."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", null\n  br i1 %map.get.found."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %map.get.some."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", label %map.get.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmap.get.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        if map_operand_is_text(compiler, value) {
            let data = text_data_offset(compiler, value)
            ir_write_ascii(compiler, ir, "  %map.get.len."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = load i64, ptr %map.get."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, "\n  %map.get.n."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = add i64 %map.get.len."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", "); ir_write_number(compiler, ir, data)
            ir_write_ascii(compiler, ir, "\n  %map.get.copy."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call ptr @nl.mem.copy(ptr %addr."); ir_write_number(compiler, ir, address)
            ir_write_ascii(compiler, ir, ", ptr %map.get."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 %map.get.n."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
        } else {
            ir_write_ascii(compiler, ir, "  %map.get.copy."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call ptr @nl.mem.copy(ptr %addr."); ir_write_number(compiler, ir, address)
            ir_write_ascii(compiler, ir, ", ptr %map.get."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, value_type_size(compiler, value)); ir_write_ascii(compiler, ir, ")\n")
        }
        emit_sum_tag_store(compiler, ir, node, 0L)
        ir_write_ascii(compiler, ir, "  br label %map.get.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmap.get.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_sum_tag_store(compiler, ir, node, 1L)
        ir_write_ascii(compiler, ir, "  br label %map.get.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmap.get.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        return
    }
    // remove
    ir_write_ascii(compiler, ir, "  %map.remove."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " = call i1 "); ir_map_sym(compiler, ir, "remove", type_id)
    ir_write_ascii(compiler, ir, "(ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial); ir_write_ascii(compiler, ir, ", ")
    ir_write_map_operand(compiler, ir, key_operand)
    ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address)
    ir_write_ascii(compiler, ir, ")\n  br i1 %map.remove."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", label %map.remove.some."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %map.remove.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmap.remove.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    emit_sum_tag_store(compiler, ir, node, 0L)
    ir_write_ascii(compiler, ir, "  br label %map.remove.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmap.remove.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    emit_sum_tag_store(compiler, ir, node, 1L)
    ir_write_ascii(compiler, ir, "  br label %map.remove.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, "\nmap.remove.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
}

// `map<K, V, N>` as written in a type position.
fn intern_map_type_syntax(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    node: long,
) -> long {
    let syntax = tables.nodes[node]
    let argument_count = syntax.meta1 & 2097151L
    let constant_count = (syntax.meta1 >> 21L) & 2097151L
    let key_node = compiler.child_first[node]
    let value_node = if key_node >= 0L { compiler.child_next[key_node] } else { -1L }
    let capacity_node = if value_node >= 0L { compiler.child_next[value_node] } else { -1L }
    if argument_count != 2L || constant_count != 1L || key_node < 0L || value_node < 0L || capacity_node < 0L ||
        tables.nodes[key_node].kind != NodeKind.TypeArgument || tables.nodes[value_node].kind != NodeKind.TypeArgument {
        fail_at_message(env, files, compiler, file_index, syntax.start, "map types use map<K, V, capacity>; the capacity must be a constant")
    }
    if (compiler.facts[key_node].flags & FACT_RESOLVED_TYPE) == 0L || (compiler.facts[value_node].flags & FACT_RESOLVED_TYPE) == 0L { return -1L }
    let capacity_value = evaluate_collection_capacity(tables, compiler, capacity_node, 0L)
    if !capacity_value.constant {
        let unsupported = unsupported_collection_capacity_constant(tables, compiler, capacity_node, 0L)
        if unsupported >= 0L { return -1L }
        collection_capacity_error(env, files, compiler, file_index, tables.nodes[capacity_node].start, true, false)
    }
    if !capacity_value.valid { collection_capacity_overflow_error(env, files, compiler, file_index, syntax.start) }
    if capacity_value.value < 0L { collection_capacity_error(env, files, compiler, file_index, tables.nodes[capacity_node].start, true, true) }
    let key = compiler.facts[key_node].ty
    let value = compiler.facts[value_node].ty
    if !map_operand_supported(compiler, key) {
        report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node: key_node, offset: tables.nodes[key_node].start, category: UNSUPPORTED_MAP_ELEMENT, token: syntax.token })
    }
    if !map_operand_supported(compiler, value) {
        report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node: value_node, offset: tables.nodes[value_node].start, category: UNSUPPORTED_MAP_ELEMENT, token: syntax.token })
    }
    let map_name_id = compiler.token_name_ids[syntax.token]
    intern_map_type(compiler, key, value, capacity_value.value, file_index, node, map_name_id, syntax.token)
}

fn emit_map_copy_helpers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    for type_id in 0L..type_count(compiler) {
        if type_kind(compiler, type_id) == TYPE_KIND_MAP && has_type_helper(compiler, type_id, HELPER_COPY) {
            ir_write_ascii(compiler, ir, "define internal void "); emit_type_helper_symbol(compiler, ir, type_id, HELPER_COPY)
            ir_write_ascii(compiler, ir, "(ptr %nl.ctx, ptr %destination, ptr %source) {\nentry:\n  %copied = call ptr @nl.mem.move(ptr %destination, ptr %source, i64 ")
            ir_write_number(compiler, ir, value_type_size(compiler, type_id))
            ir_write_ascii(compiler, ir, ")\n  ret void\n}\n\n")
        }
    }
}

// Memory operations through LLVM intrinsics, wrapped so a call can keep the shape of a libc call. The backend
// turns a large or variable-size one into a call to the platform memcpy, memmove or memset.
fn emit_map_memory_wrappers(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY) {
    var any_map = false
    for type_id in 0L..type_count(compiler) {
        if type_kind(compiler, type_id) == TYPE_KIND_MAP || type_kind(compiler, type_id) == TYPE_KIND_POOL { any_map = true }
    }
    if compiler.mailbox_types.count() > 0L { any_map = true }
    if !any_map { return }
    ir_write_ascii(compiler, ir, "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)\ndeclare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1 immarg)\ndeclare void @llvm.memset.p0.i64(ptr, i8, i64, i1 immarg)\n")
    ir_write_ascii(compiler, ir, "define internal ptr @nl.mem.copy(ptr %d, ptr %s, i64 %n) {\nentry:\n  call void @llvm.memcpy.p0.p0.i64(ptr %d, ptr %s, i64 %n, i1 false)\n  ret ptr %d\n}\n")
    ir_write_ascii(compiler, ir, "define internal ptr @nl.mem.move(ptr %d, ptr %s, i64 %n) {\nentry:\n  call void @llvm.memmove.p0.p0.i64(ptr %d, ptr %s, i64 %n, i1 false)\n  ret ptr %d\n}\n")
    ir_write_ascii(compiler, ir, "define internal ptr @nl.mem.set(ptr %d, i32 %v, i64 %n) {\nentry:\n  %b = trunc i32 %v to i8\n  call void @llvm.memset.p0.i64(ptr %d, i8 %b, i64 %n, i1 false)\n  ret ptr %d\n}\n\n")
}
