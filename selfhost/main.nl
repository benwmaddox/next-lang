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

fn usage_build(env: Env) -> never {
    match env.err.write(b"usage: nlc run selfhost -- build <package> -o <file.ll> [--test] [--runtime=c|core]\n") {
        ok(_) => env.exit(3),
        err(_) => env.exit(3),
    }
}

fn main(env: Env) {
    let args = env.args()
    if args.count() < 2L { usage(env, false) }

    let command = match args.get(0L) {
        some(value) => value,
        none => usage(env, false),
    }
    let is_lex = argument_equals(command, "lex")
    let is_parse = argument_equals(command, "parse")
    let is_build = argument_equals(command, "build")
    if !is_lex && !is_parse && !is_build { usage(env, false) }
    if is_build && (args.count() < 4L || args.count() > 6L) { usage_build(env) }
    if !is_build && args.count() > 4L { usage(env, is_parse) }
    let package = match args.get(1L) {
        some(value) => value,
        none => if is_build { usage_build(env) } else { usage(env, is_parse) },
    }

    var want_tokens = false
    var want_tree = false
    var want_binary = false
    var want_test_build = false
    var runtime_core = true
    var runtime_seen = false
    if is_build {
        let output_flag = match args.get(2L) { some(value) => value, none => usage_build(env) }
        if !argument_equals(output_flag, "-o") { usage_build(env) }
        let _output_path = match args.get(3L) { some(value) => value, none => usage_build(env) }
        for flag_index in 4L..args.count() {
            let flag = match args.get(flag_index) { some(value) => value, none => usage_build(env) }
            if argument_equals(flag, "--test") {
                if want_test_build { usage_build(env) }
                want_test_build = true
            } else if argument_equals(flag, "--runtime=c") {
                if runtime_seen { usage_build(env) }
                runtime_seen = true
                runtime_core = false
            } else if argument_equals(flag, "--runtime=core") {
                if runtime_seen { usage_build(env) }
                runtime_seen = true
                runtime_core = true
            } else {
                usage_build(env)
            }
        }
    } else {
        for flag_index in 2L..args.count() {
            let flag = match args.get(flag_index) {
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
    }
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
        let output_path = match args.get(3L) { some(value) => value, none => usage_build(env) }
        let config = load_manifest(env, package)
        var compiler = empty_compiler_tables()
        seed_builtin_types(compiler.type_records)
        add_compiler_links(tables, compiler)
        intern_package_names(env, source, files, tokens, tables, compiler)
        build_line_start_index(env, source, files, compiler)
        index_package_enums(source, files, tokens, tables, compiler)
        index_package_structs(source, files, tokens, tables, compiler)
        intern_written_type_instances(source, tokens, files, tables, compiler)
        size_package_types(source, files, tokens, tables, compiler)
        check_package_eligibility(env, source, files, tokens, tables, compiler)
        var ir: Bytes max IR_BUFFER_CAPACITY = Bytes.empty()
        compile_selfhost_package(env, source, files, tokens, tables, config, compiler, ir, want_test_build, runtime_core, embedded_core_hash())
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
