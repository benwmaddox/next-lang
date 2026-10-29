fn deferred_text_kind(kind: long) -> bool {
    kind == TYPE_KIND_ASCII || kind == TYPE_KIND_TEXT || kind == TYPE_KIND_BYTES
}

fn is_ascii_append_assignment(op: long, target_type: long, compiler: CompilerTables) -> bool {
    op == 1L && type_kind(compiler, target_type) == TYPE_KIND_ASCII
}
