// Interpolated strings, $"text {hole} text", as the compiler sees them: a left-leaning chain of `+` over string pieces and
// hole calls, every node marked with INTERP_MARK in its `extra`. The checker types the chain like a concatenation; the code
// is generated flat: the root writes every piece one after another into one destination (its own value, or straight into the
// builder it is appended to), so no piece has a value of its own and nothing is copied twice. Only a Text result (non-ASCII
// text, which needs code points counted) keeps the pairwise concatenation.

const INTERP_MARK: long = -9L

fn interp_node(tables: ParseTables, node: long) -> bool {
    node >= 0L && node < tables.nodes.count() &&
        (tables.nodes[node].kind == NodeKind.Binary || tables.nodes[node].kind == NodeKind.Call) &&
        tables.nodes[node].extra == INTERP_MARK
}

// The node that owns the chain `node` is part of: the topmost `+` of the chain, or a hole that stands alone.
fn interp_chain_root(tables: ParseTables, compiler: CompilerTables, node: long) -> long {
    var current = node
    if tables.nodes[node].kind == NodeKind.Call {
        let parent = region_parent_node(tables, node)
        if !(parent >= 0L && interp_node(tables, parent) && tables.nodes[parent].kind == NodeKind.Binary) { return node }
        current = parent
    }
    for step in 0L..tables.nodes.count() {
        let parent = region_parent_node(tables, current)
        if parent < 0L || !interp_node(tables, parent) || tables.nodes[parent].kind != NodeKind.Binary ||
            compiler.child_first[parent] != current {
            break
        }
        current = parent
    }
    current
}

// Whether the chain is written flat: its value is Ascii, Bytes or Text (a Text also counts its code points as it goes).
fn interp_chain_is_flat(tables: ParseTables, compiler: CompilerTables, root: long) -> bool {
    let kind = type_kind(compiler, compiler.facts[root].ty)
    kind == TYPE_KIND_ASCII || kind == TYPE_KIND_BYTES || kind == TYPE_KIND_TEXT
}

fn interp_root_is_text(compiler: CompilerTables, root: long) -> bool {
    type_kind(compiler, compiler.facts[root].ty) == TYPE_KIND_TEXT
}

// Whether the leaf is text copied from a literal or a text hole (its code points come from the source), not a number or a bool.
fn interp_leaf_copies_text(tables: ParseTables, compiler: CompilerTables, leaf: long) -> bool {
    if tables.nodes[leaf].kind != NodeKind.Call { return true }
    let hole_kind = type_kind(compiler, compiler.facts[compiler.child_first[leaf]].ty)
    hole_kind == TYPE_KIND_ASCII || hole_kind == TYPE_KIND_BYTES || hole_kind == TYPE_KIND_TEXT
}

// A piece or hole, or `+`, that is written by its chain's root and has no code of its own.
fn interp_is_flat_member(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    if !interp_node(tables, node) { return false }
    let root = interp_chain_root(tables, compiler, node)
    root != node && interp_chain_is_flat(tables, compiler, root)
}

fn interp_is_flat_root(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    interp_node(tables, node) && interp_chain_root(tables, compiler, node) == node && interp_chain_is_flat(tables, compiler, node)
}

fn interp_leaf_count(tables: ParseTables, compiler: CompilerTables, root: long) -> long {
    var count = 1L
    var current = root
    for step in 0L..tables.nodes.count() {
        if tables.nodes[current].kind != NodeKind.Binary { break }
        count += 1L
        current = compiler.child_first[current]
    }
    count
}

// The k-th leaf, counting from the left.
fn interp_leaf(tables: ParseTables, compiler: CompilerTables, root: long, index: long) -> long {
    let count = interp_leaf_count(tables, compiler, root)
    if count == 1L { return root }
    var spine = root
    // the spine node whose right child is leaf `index` (index >= 1), or whose left child is leaf 0
    let steps = if index == 0L { count - 2L } else { count - 1L - index }
    for step in 0L..steps { spine = compiler.child_first[spine] }
    if index == 0L { compiler.child_first[spine] } else { compiler.child_next[compiler.child_first[spine]] }
}

fn interp_hole_argument(compiler: CompilerTables, leaf: long) -> long {
    compiler.child_first[leaf]
}

fn interp_leaf_is_hole(tables: ParseTables, leaf: long) -> bool {
    tables.nodes[leaf].kind == NodeKind.Call
}

fn interp_name(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, base: Ascii max 24, root: long, tag: long, index: long) {
    ir_write_ascii(compiler, ir, "%interp."); ir_write_ascii(compiler, ir, base)
    ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, root)
    ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, tag)
    ir_push_byte(compiler, ir, 46); ir_write_number(compiler, ir, index)
}

// Writes every piece of the flat chain at `root`, one after another, to the memory `base` names (an SSA pointer such as
// "%interp.base.12.0.0"); leaves the number of bytes written in the value %interp.off.<root>.<tag>.<pieces>. `tag` tells two
// copies of this code in one function apart.
fn emit_interp_pieces(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    root: long,
    base_root: long,
    base_tag: long,
    base_index: long,
    tag: long,
) {
    let count = interp_leaf_count(tables, compiler, root)
    for index in 0L..count {
        let leaf = interp_leaf(tables, compiler, root, index)
        // where this piece starts
        ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "dst", root, tag, index)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); interp_name(compiler, ir, "base", base_root, base_tag, base_index)
        ir_write_ascii(compiler, ir, ", i64 ")
        if index == 0L { ir_write_ascii(compiler, ir, "0") } else { interp_name(compiler, ir, "off", root, tag, index) }
        ir_push_byte(compiler, ir, 10)
        if interp_leaf_is_hole(tables, leaf) {
            let argument = interp_hole_argument(compiler, leaf)
            let argument_type = compiler.facts[argument].ty
            let argument_kind = type_kind(compiler, argument_type)
            let spec = tables.nodes[leaf].flags
            if argument_kind == TYPE_KIND_ASCII || argument_kind == TYPE_KIND_BYTES || argument_kind == TYPE_KIND_TEXT {
                let text_width = if spec == FORMAT_TEXT_PAD { compiler.child_next[argument] } else { -1L }
                emit_interp_copy(tables, compiler, ir, root, tag, index, argument, text_width)
            } else if argument_type == TY_BOOL {
                // "true" or "false": five bytes are stored, the length says how many count
                ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "len", root, tag, index)
                ir_write_ascii(compiler, ir, " = select i1 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", i64 4, i64 5\n")
                for position in 0L..5L {
                    let when_true = if position == 0L { 116L } else if position == 1L { 114L } else if position == 2L { 117L } else if position == 3L { 101L } else { 101L }
                    let when_false = if position == 0L { 102L } else if position == 1L { 97L } else if position == 2L { 108L } else if position == 3L { 115L } else { 101L }
                    ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "bool", root, tag, index * 8L + position)
                    ir_write_ascii(compiler, ir, " = select i1 "); ir_write_value_ref(compiler, ir, argument)
                    ir_write_ascii(compiler, ir, ", i8 "); ir_write_number(compiler, ir, when_true)
                    ir_write_ascii(compiler, ir, ", i8 "); ir_write_number(compiler, ir, when_false); ir_push_byte(compiler, ir, 10)
                    ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "boolp", root, tag, index * 8L + position)
                    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); interp_name(compiler, ir, "dst", root, tag, index)
                    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, position); ir_push_byte(compiler, ir, 10)
                    ir_write_ascii(compiler, ir, "  store i8 "); interp_name(compiler, ir, "bool", root, tag, index * 8L + position)
                    ir_write_ascii(compiler, ir, ", ptr "); interp_name(compiler, ir, "boolp", root, tag, index * 8L + position)
                    ir_write_ascii(compiler, ir, ", align 1\n")
                }
            } else if is_float_type(argument_type) {
                // a double or float: its shortest round-trip text is written where it goes
                let fp_id = leaf + (tag + 1L) * 100000000L
                emit_float_bits_i64(compiler, ir, fp_id, argument)
                ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "len", root, tag, index)
                ir_write_ascii(compiler, ir, " = call i64 @nl_format_float_bits(ptr %nl.ctx, i64 %fp.bits."); ir_write_number(compiler, ir, fp_id)
                ir_write_ascii(compiler, ir, if argument_type == TY_DOUBLE { ", i64 0, ptr " } else { ", i64 1, ptr " })
                interp_name(compiler, ir, "dst", root, tag, index); ir_write_ascii(compiler, ir, ")\n")
            } else {
                // a number: its digits are written where they go
                ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "num", root, tag, index); ir_write_ascii(compiler, ir, " = ")
                if argument_type == TY_LONG {
                    ir_write_ascii(compiler, ir, "add i64 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, ", 0\n")
                } else if argument_type == TY_BYTE || argument_type == TY_UINT || argument_type == TY_USHORT {
                    ir_write_ascii(compiler, ir, "zext i32 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n")
                } else if argument_type == TY_INT || argument_type == TY_SHORT || argument_type == TY_SBYTE {
                    ir_write_ascii(compiler, ir, "sext i32 "); ir_write_value_ref(compiler, ir, argument); ir_write_ascii(compiler, ir, " to i64\n")
                } else { compiler.ir_overflow = true }
                if spec == FORMAT_TEXT_PAD || spec == FORMAT_TEXT_PAD_ZERO {
                    let width_node = compiler.child_next[argument]
                    emit_interp_width(compiler, ir, root, tag, index, width_node)
                }
                ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "len", root, tag, index)
                if spec == FORMAT_TEXT_PAD || spec == FORMAT_TEXT_PAD_ZERO {
                    ir_write_ascii(compiler, ir, if spec == FORMAT_TEXT_PAD { " = call i64 @nl_core_nl_text_format_number_pad(ptr %nl.ctx, i64 " } else { " = call i64 @nl_core_nl_text_format_pad_zero(ptr %nl.ctx, i64 " })
                    interp_name(compiler, ir, "num", root, tag, index)
                    ir_write_ascii(compiler, ir, ", i64 "); interp_name(compiler, ir, "width", root, tag, index)
                } else {
                    ir_write_ascii(compiler, ir, " = call i64 @nl_core_nl_text_format_number(ptr %nl.ctx, i64 "); interp_name(compiler, ir, "num", root, tag, index)
                    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, if spec == FORMAT_TEXT_HEX { 16L } else if spec == FORMAT_TEXT_BIN { 2L } else { 10L })
                }
                ir_write_ascii(compiler, ir, ", ptr "); interp_name(compiler, ir, "dst", root, tag, index); ir_write_ascii(compiler, ir, ")\n")
            }
        } else {
            emit_interp_copy(tables, compiler, ir, root, tag, index, leaf, -1L)
        }
        ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "off", root, tag, index + 1L)
        ir_write_ascii(compiler, ir, " = add i64 ")
        if index == 0L { ir_write_ascii(compiler, ir, "0") } else { interp_name(compiler, ir, "off", root, tag, index) }
        ir_write_ascii(compiler, ir, ", "); interp_name(compiler, ir, "len", root, tag, index); ir_push_byte(compiler, ir, 10)
        if interp_root_is_text(compiler, root) {
            // the code points written so far: digits and ASCII text count one each, other text says how many it holds
            if !interp_leaf_copies_text(tables, compiler, leaf) {
                ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "plen", root, tag, index)
                ir_write_ascii(compiler, ir, " = add i64 "); interp_name(compiler, ir, "len", root, tag, index); ir_write_ascii(compiler, ir, ", 0\n")
            }
            ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "poff", root, tag, index + 1L)
            ir_write_ascii(compiler, ir, " = add i64 ")
            if index == 0L { ir_write_ascii(compiler, ir, "0") } else { interp_name(compiler, ir, "poff", root, tag, index) }
            ir_write_ascii(compiler, ir, ", "); interp_name(compiler, ir, "plen", root, tag, index); ir_push_byte(compiler, ir, 10)
        }
    }
}

// The width of a padded hole, as an i64 named %interp.width.
fn emit_interp_width(compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, root: long, tag: long, index: long, width_node: long) {
    ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "width", root, tag, index); ir_write_ascii(compiler, ir, " = ")
    if compiler.facts[width_node].ty == TY_LONG {
        ir_write_ascii(compiler, ir, "add i64 "); ir_write_value_ref(compiler, ir, width_node); ir_write_ascii(compiler, ir, ", 0\n")
    } else {
        ir_write_ascii(compiler, ir, "sext i32 "); ir_write_value_ref(compiler, ir, width_node); ir_write_ascii(compiler, ir, " to i64\n")
    }
}

// Copies the text value of `source_node` (a literal, or the text a hole names) to this piece's place; with a width node
// the text is padded on the left to that width.
fn emit_interp_copy(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    root: long,
    tag: long,
    index: long,
    source_node: long,
    width_node: long,
) {
    let source_type = compiler.facts[source_node].ty
    let location = aggregate_source_location_for_node(tables, compiler, source_node)
    let pointer = emit_location_pointer_materialization(compiler, ir, location)
    ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "slen", root, tag, index)
    ir_write_ascii(compiler, ir, " = ")
    let binding = text_read_view_binding(compiler, location)
    if binding >= 0L {
        ir_write_ascii(compiler, ir, "add i64 %arg.copies."); ir_write_number(compiler, ir, binding); ir_write_ascii(compiler, ir, ", 0\n")
    } else {
        ir_write_ascii(compiler, ir, "load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer); ir_write_ascii(compiler, ir, ", align 1\n")
    }
    ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "src", root, tag, index)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, text_location_data_offset(compiler, source_type, location)); ir_push_byte(compiler, ir, 10)
    let counts_points = interp_root_is_text(compiler, root)
    if counts_points {
        // how many code points the source holds: Text says so, Ascii and Bytes one per byte
        emit_text_source_length(compiler, ir, location, pointer, source_node, if tag == 0L { "ipa" } else { "ipb" })
        emit_text_source_points(compiler, ir, source_type, location, pointer, source_node, if tag == 0L { "ipa" } else { "ipb" })
        ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "spts", root, tag, index)
        ir_write_ascii(compiler, ir, " = add i64 %text."); ir_write_ascii(compiler, ir, if tag == 0L { "ipa" } else { "ipb" })
        ir_write_ascii(compiler, ir, ".points."); ir_write_number(compiler, ir, source_node); ir_write_ascii(compiler, ir, ", 0\n")
    }
    if width_node >= 0L {
        emit_interp_width(compiler, ir, root, tag, index, width_node)
        ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "len", root, tag, index)
        ir_write_ascii(compiler, ir, " = call i64 @nl_core_nl_text_format_pad(ptr %nl.ctx, ptr "); interp_name(compiler, ir, "src", root, tag, index)
        ir_write_ascii(compiler, ir, ", i64 "); interp_name(compiler, ir, "slen", root, tag, index)
        ir_write_ascii(compiler, ir, ", i64 "); interp_name(compiler, ir, if counts_points { "spts" } else { "slen" }, root, tag, index)
        ir_write_ascii(compiler, ir, ", i64 "); interp_name(compiler, ir, "width", root, tag, index)
        ir_write_ascii(compiler, ir, ", i1 true, ptr "); interp_name(compiler, ir, "dst", root, tag, index); ir_write_ascii(compiler, ir, ")\n")
        if counts_points {
            // the padded text holds the wider of its width and its own code points
            ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "pwide", root, tag, index)
            ir_write_ascii(compiler, ir, " = icmp sgt i64 "); interp_name(compiler, ir, "width", root, tag, index)
            ir_write_ascii(compiler, ir, ", "); interp_name(compiler, ir, "spts", root, tag, index)
            ir_write_ascii(compiler, ir, "\n  "); interp_name(compiler, ir, "plen", root, tag, index)
            ir_write_ascii(compiler, ir, " = select i1 "); interp_name(compiler, ir, "pwide", root, tag, index)
            ir_write_ascii(compiler, ir, ", i64 "); interp_name(compiler, ir, "width", root, tag, index)
            ir_write_ascii(compiler, ir, ", i64 "); interp_name(compiler, ir, "spts", root, tag, index); ir_push_byte(compiler, ir, 10)
        }
    } else {
        ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "copy", root, tag, index)
        ir_write_ascii(compiler, ir, " = call ptr @memmove(ptr "); interp_name(compiler, ir, "dst", root, tag, index)
        ir_write_ascii(compiler, ir, ", ptr "); interp_name(compiler, ir, "src", root, tag, index)
        ir_write_ascii(compiler, ir, ", i64 "); interp_name(compiler, ir, "slen", root, tag, index); ir_write_ascii(compiler, ir, ")\n")
        ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "len", root, tag, index)
        ir_write_ascii(compiler, ir, " = add i64 "); interp_name(compiler, ir, "slen", root, tag, index); ir_write_ascii(compiler, ir, ", 0\n")
        if counts_points {
            ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "plen", root, tag, index)
            ir_write_ascii(compiler, ir, " = add i64 "); interp_name(compiler, ir, "spts", root, tag, index); ir_write_ascii(compiler, ir, ", 0\n")
        }
    }
}

// The value of a flat chain: every piece written into the root's own storage, then its length.
fn emit_interp_value(tables: ParseTables, compiler: write CompilerTables, ir: grow Bytes max IR_BUFFER_CAPACITY, root: long) {
    let result_type = compiler.facts[root].ty
    let destination = aggregate_destination_location(compiler, 0L, root)
    let destination_pointer = emit_location_pointer_materialization(compiler, ir, destination)
    ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "base", root, 0L, 0L)
    ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, text_data_offset(compiler, result_type)); ir_push_byte(compiler, ir, 10)
    emit_interp_pieces(tables, compiler, ir, root, root, 0L, 0L, 0L)
    let count = interp_leaf_count(tables, compiler, root)
    ir_write_ascii(compiler, ir, "  %text.format.written."); ir_write_number(compiler, ir, root)
    ir_write_ascii(compiler, ir, " = add i64 "); interp_name(compiler, ir, "off", root, 0L, count); ir_write_ascii(compiler, ir, ", 0\n")
    emit_format_text_store_length(compiler, ir, root, destination, destination_pointer)
    if interp_root_is_text(compiler, root) {
        ir_write_ascii(compiler, ir, "  "); interp_name(compiler, ir, "pointsaddr", root, 0L, 0L)
        ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, destination, destination_pointer)
        ir_write_ascii(compiler, ir, ", i64 8\n  store i64 "); interp_name(compiler, ir, "poff", root, 0L, count)
        ir_write_ascii(compiler, ir, ", ptr "); interp_name(compiler, ir, "pointsaddr", root, 0L, 0L); ir_write_ascii(compiler, ir, ", align 1")
        emit_program_storage_tbaa(compiler, ir); ir_push_byte(compiler, ir, 10)
    }
}

// A flat chain that is the argument of a Bytes or Ascii builder's try_append writes into the builder when the builder has room
// for the chain's largest value; this node then has no code of its own (the append writes, or falls back to this node's value).
fn interp_is_deferred_append(tables: ParseTables, compiler: CompilerTables, node: long) -> bool {
    if !interp_is_flat_root(tables, compiler, node) { return false }
    let parent = region_parent_node(tables, node)
    if parent < 0L || tables.nodes[parent].kind != NodeKind.MethodCall || compiler.facts[parent].literal != TEXT_METHOD_TRY_APPEND { return false }
    let receiver = compiler.child_first[parent]
    if receiver < 0L || compiler.child_next[receiver] != node { return false }
    let receiver_kind = type_kind(compiler, compiler.facts[receiver].ty)
    receiver_kind == TYPE_KIND_BYTES || receiver_kind == TYPE_KIND_ASCII || receiver_kind == TYPE_KIND_TEXT
}
