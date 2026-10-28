fn fail_const_bytes_diagnostic(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    file_index: long,
    method_node: long,
    const_name_token: long,
) -> never {
    let position = position_for_offset(
        file_index,
        files[file_index].base + tables.nodes[method_node].anchor,
        compiler,
    )
    match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: const '") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[file_index].base, const_name_token) {
        ok(_) => (),
        err(_) => env.exit(3),
    }
    match env.err.write(b"' cannot call '.bytes()'; const evaluation is not implemented yet") {
        ok(_) => (),
        err(_) => env.exit(3),
    }
    match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn check_const_bytes_diagnostic(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
) {
    var has_const = false
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind == NodeKind.Const {
            has_const = true
            break
        }
    }
    if !has_const { return }

    var const_names: list<bool, TOKEN_STORAGE_CAPACITY> = list {}
    for name_id in 0L..compiler.enum_type_by_name.count() {
        const_names.push(false).unwrap()
    }
    for node in 0L..tables.nodes.count() {
        if tables.nodes[node].kind != NodeKind.Const { continue }
        let name_token = tables.nodes[node].token
        if name_token < 0L || name_token >= compiler.token_name_ids.count() { continue }
        let type_node = compiler.child_first[node]
        if type_node < 0L || type_node >= tables.nodes.count() { continue }
        let file_index = node_file_index(tables.nodes, files, node)
        let type_token = tables.nodes[type_node].token
        if !token_is_word_at(source, tokens, files, file_index, type_token, "Ascii") &&
            !token_is_word_at(source, tokens, files, file_index, type_token, "Text") &&
            !token_is_word_at(source, tokens, files, file_index, type_token, "Bytes") {
            continue
        }
        let name_id = compiler.token_name_ids[name_token]
        if name_id >= 0L && name_id < const_names.count() { const_names[name_id] = true }
        else { () }
    }
    for node in 0L..tables.nodes.count() {
        let method = tables.nodes[node]
        let file_index = node_file_index(tables.nodes, files, node)
        var name_token = -1L
        if method.kind == NodeKind.MethodCall && method.aux == 0L &&
            token_is_word_at(source, tokens, files, file_index, method.token, "bytes") {
            let receiver = node_first_direct_child(tables.nodes, node)
            if receiver >= 0L && tables.nodes[receiver].kind == NodeKind.Name {
                name_token = tables.nodes[receiver].token
            } else { () }
        } else if method.kind == NodeKind.QualifiedCase && method.aux == 0L &&
            method.extra >= 0L && method.extra < tables.extra.count() &&
            token_is_word_at(source, tokens, files, file_index, tables.extra[method.extra], "bytes") {
            // Uppercase receiver names are parsed as enum qualifiers, so the
            // source form SIGNATURE.bytes() arrives as QualifiedCase rather
            // than MethodCall. Its token is the receiver name.
            name_token = method.token
        } else { () }
        if name_token < 0L { continue }
        if name_token >= compiler.token_name_ids.count() { continue }
        let name_id = compiler.token_name_ids[name_token]
        if name_id >= 0L && name_id < const_names.count() && const_names[name_id] {
            fail_const_bytes_diagnostic(
                env,
                source,
                files,
                tokens,
                tables,
                compiler,
                file_index,
                node,
                name_token,
            )
        }
    }
}
