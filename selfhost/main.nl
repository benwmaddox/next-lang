fn usage(env: Env, parse_command: bool) -> never {
    if parse_command {
        match env.err.write(b"usage: nlc run selfhost -- parse <package> [--tokens] [--tree] [--binary]\n") {
            ok(_) => env.exit(3),
            err(_) => env.exit(3),
        }
    } else {
        match env.err.write(b"usage: nlc run selfhost -- lex <package> [--tokens] [--tree]\n") {
            ok(_) => env.exit(3),
            err(_) => env.exit(3),
        }
    }
}

fn usage_build(env: Env) -> never { // E3a1 begin
    match env.err.write(b"usage: nlc run selfhost -- build <package> -o <file.ll> [--test] [--test-region-threshold=<bytes>] [--runtime=core|c]\n") {
        ok(_) => env.exit(3),
        err(_) => env.exit(3),
    } // E3a1 end
}

fn main(env: Env) {
    let arguments = env.args()
    if arguments.count() < 2L { usage(env, false) }

    let command = match arguments.get(0L) {
        some(value) => value,
        none => usage(env, false),
    }
    let is_lex = argument_equals(command, "lex")
    let is_parse = argument_equals(command, "parse")
    let is_build = argument_equals(command, "build")
    if !is_lex && !is_parse && !is_build { usage(env, false) } // E3a1 begin
    if is_build && (arguments.count() < 4L || arguments.count() > 7L) { usage_build(env) } // E3a1 end
    if !is_build && arguments.count() > 4L { usage(env, is_parse) }
    let package = match arguments.get(1L) {
        some(value) => value,
        none => if is_build { usage_build(env) } else { usage(env, is_parse) },
    }

    var want_tokens = false
    var want_tree = false
    var want_binary = false
    var want_test_build = false
    var runtime_seen = false // E3a1 begin
    var c_runtime = false
    var test_region_threshold = -1L // E3a1 end
    if is_build {
        let output_flag = match arguments.get(2L) { some(value) => value, none => usage_build(env) }
        if !argument_equals(output_flag, "-o") { usage_build(env) }
        let _output_path = match arguments.get(3L) { some(value) => value, none => usage_build(env) } // E3a1 begin
        for flag_index in 4L..arguments.count() {
            let flag = match arguments.get(flag_index) { some(value) => value, none => usage_build(env) }
            if argument_equals(flag, "--test") {
                if want_test_build { usage_build(env) }
                want_test_build = true
            } else if argument_equals(flag, "--runtime=core") {
                if runtime_seen { usage_build(env) }
                runtime_seen = true
            } else if argument_equals(flag, "--runtime=c") {
                if runtime_seen { usage_build(env) }
                runtime_seen = true
                c_runtime = true
            } else if test_region_threshold_argument(flag) >= 0L {
                if test_region_threshold >= 0L { usage_build(env) }
                test_region_threshold = test_region_threshold_argument(flag)
            } else {
                usage_build(env)
            }
        } // E3a1 end
    } else {
        for flag_index in 2L..arguments.count() {
            let flag = match arguments.get(flag_index) {
                some(value) => value,
                none => usage(env, is_parse),
            }
            if argument_equals(flag, "--tokens") {
                if want_tokens { usage(env, is_parse) }
                want_tokens = true
            } else if argument_equals(flag, "--tree") {
                if want_tree { usage(env, is_parse) }
                want_tree = true
            } else if argument_equals(flag, "--binary") {
                if want_binary { usage(env, is_parse) }
                want_binary = true
            } else {
                usage(env, is_parse)
            }
        }
    } // E3a1 begin
    if test_region_threshold >= 0L && !want_test_build { usage_build(env) } // E3a1 end
    if want_binary && (want_tokens || want_tree || is_lex) { usage(env, is_parse) }
    var entries: list<DirEntry, MAX_DIRECTORY_ENTRIES> = list {}
    var source: Bytes max SOURCE_BUFFER_CAPACITY = Bytes.empty()
    var files: list<SourceFile, MAX_SOURCE_FILES> = list {}
    var tokens: list<Token, TOKEN_STORAGE_CAPACITY> = list {}
    var delimiters: list<DelimiterKind, MAX_DELIMITER_NESTING> = list {}
    var file_data: Bytes max FILE_SOURCE_CAPACITY = Bytes.empty()


    var tables = empty_parse_tables()
    initialize_parse_tables(tables)
    load_and_parse(env, package, entries, source, files, tokens, delimiters, file_data, tables, is_lex)
    if is_build {
        let output_path = match arguments.get(3L) { some(value) => value, none => usage_build(env) }
        let config = load_manifest(env, package)
        if c_runtime && config.step_budget_main >= 0L {
            fail_tool(env, "the C runtime does not support step_budget.main")
        }
        var compiler = empty_compiler_tables() // E3a1 begin
        compiler.c_runtime = c_runtime
        compiler.file_id_base = if test_region_threshold < 0L { 4096L } else { test_region_threshold } // E3a1 end
        compiler.step_budget_main = config.step_budget_main
        seed_builtin_types(env, compiler.type_records)
        add_compiler_links(env, tables, compiler)
        intern_package_names(env, source, files, tokens, tables, compiler)
        build_line_start_index(env, source, files, compiler)
        register_scalar_constants(env, source, tokens, files, tables, compiler)
        index_package_enums(env, source, files, tokens, tables, compiler)
        intern_builtin_full(source, files, tokens, compiler)
        index_package_structs(source, files, tokens, tables, compiler)
        intern_builtin_text_types(source, files, tokens, compiler)
        intern_written_type_instances(env, source, tokens, files, tables, compiler)
        size_package_types(source, files, tokens, tables, compiler)
        check_package_name_shadows(env, source, files, tokens, tables, compiler)
        check_package_eligibility(env, source, files, tokens, tables, compiler)
        var ir: Bytes max IR_BUFFER_CAPACITY = Bytes.empty() // E3a1 begin
        compile_selfhost_package(env, source, files, tokens, tables, config, compiler, ir, want_test_build, embedded_core_hash()) // E3a1 end
        if compiler.internal_emit_error_kind >= 0L {
            let file_index = compiler.internal_emit_error_file
            let node = compiler.internal_emit_error_node
            let position = position_for_offset(file_index, files[file_index].base + tables.nodes[node].start, compiler)
            match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b": internal compiler error: unhandled statement kind ") { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(dump_node_kind(tables.nodes[node].kind).bytes()) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
        }
        if compiler.ir_overflow {
            fail_parse_limit(env, files[0].name, "self-hosted LLVM IR buffer limit exceeded")
        }
        match env.fs.write(output_path, ir) {
            ok(_) => (),
            err(_) => fail_tool(env, "cannot write generated LLVM IR"),
        }
        return
    }
    if is_lex {
        if want_tree { fail_tool(env, "not implemented yet") }
        match output_token_dump(env.out, source, files, tokens) {
            ok(_) => (),
            err(_) => fail_tool(env, "cannot write token output"),
        }
    } else {
        if want_binary {
            match output_binary_tree(env.out, source, files, tokens, tables) {
                ok(_) => (),
                err(_) => fail_tool(env, "cannot write binary tree output"),
            }
            return
        }
        if want_tokens && want_tree {
            match env.out.write(b"== tokens ==\n") {
                ok(_) => (),
                err(_) => fail_tool(env, "cannot write parse output"),
            }
        }
        if want_tokens {
            match output_token_dump(env.out, source, files, tokens) {
                ok(_) => (),
                err(_) => fail_tool(env, "cannot write token output"),
            }
        }
        if want_tree {
            if want_tokens {
                match env.out.write(b"== tree ==\n") {
                    ok(_) => (),
                    err(_) => fail_tool(env, "cannot write parse output"),
                }
            }
            match output_tree_dump(env.out, source, files, tokens, tables) {
                ok(_) => (),
                err(_) => fail_tool(env, "cannot write tree output"),
            }
        }
    }
}
