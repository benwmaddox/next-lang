fn usage(env: Env, parse_command: bool) -> never {
    if parse_command {
        match env.err.write(b"usage: nlc run selfhost -- parse <package> [--tokens] [--tree] [--binary] [--policy=parse|compile]\n") {
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

fn main(env: Env) {
    let args = env.args()
    if args.count() < 2L { usage(env, false) }

    let command = match args.get(0L) {
        some(value) => value,
        none => usage(env, false),
    }
    let is_lex = argument_equals(command, "lex")
    let is_parse = argument_equals(command, "parse")
    if !is_lex && !is_parse { usage(env, false) }
    if args.count() > 4L { usage(env, is_parse) }
    let package = match args.get(1L) {
        some(value) => value,
        none => usage(env, is_parse),
    }

    var want_tokens = false
    var want_tree = false
    var want_binary = false
    var compile_policy = false
    var policy_seen = false
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
        } else if argument_equals(flag, "--policy=compile") {
            if policy_seen { usage(env, is_parse) }
            policy_seen = true
            compile_policy = true
        } else if argument_equals(flag, "--policy=parse") {
            if policy_seen { usage(env, is_parse) }
            policy_seen = true
        } else {
            usage(env, is_parse)
        }
    }
    if want_binary && (want_tokens || want_tree || is_lex) { usage(env, is_parse) }
    var entries: list<DirEntry, MAX_DIRECTORY_ENTRIES> = list {}
    var source: Bytes max SOURCE_BUFFER_CAPACITY = Bytes.empty()
    var files: list<SourceFile, MAX_SOURCE_FILES> = list {}
    var tokens: list<Token, TOKEN_STORAGE_CAPACITY> = list {}
    var delimiters: list<DelimiterKind, MAX_DELIMITER_NESTING> = list {}
    var file_data: Bytes max FILE_SOURCE_CAPACITY = Bytes.empty()

    if is_lex {
        if want_tree { fail_tool(env, "not implemented yet") }
        load_and_lex(env, package, entries, source, files, tokens, delimiters, file_data)
        match output_token_dump(env.out, source, files, tokens) {
            ok(_) => (),
            err(_) => fail_tool(env, "cannot write token output"),
        }
    } else {
        var tables = empty_parse_tables()
        initialize_parse_tables(tables)
        load_and_parse(env, package, entries, source, files, tokens, delimiters, file_data, tables, compile_policy)
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
