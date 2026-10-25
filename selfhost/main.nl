fn usage(env: Env) {
    match env.err.write(b"usage: nlc run selfhost -- lex <package> [--tokens] [--tree]\n") {
        ok(_) => env.exit(3),
        err(_) => env.exit(3),
    }
}

fn main(env: Env) {
    let args = env.args()
    if args.count() < 2L || args.count() > 4L { usage(env); env.exit(3) }

    let command = match args.get(0L) {
        some(value) => value,
        none => { usage(env); env.exit(3) },
    }
    if !argument_equals(command, "lex") { usage(env); env.exit(3) }
    let package = match args.get(1L) {
        some(value) => value,
        none => { usage(env); env.exit(3) },
    }

    var want_tokens = false
    var want_tree = false
    for flag_index in 2L..args.count() {
        let flag = match args.get(flag_index) {
            some(value) => value,
            none => { usage(env); env.exit(3) },
        }
        if argument_equals(flag, "--tokens") {
            if want_tokens { usage(env); env.exit(3) }
            want_tokens = true
        } else if argument_equals(flag, "--tree") {
            if want_tree { usage(env); env.exit(3) }
            want_tree = true
        } else {
            usage(env)
            env.exit(3)
        }
    }
    if want_tree { fail_tool(env, "not implemented yet"); env.exit(3) }

    var entries: list<DirEntry, MAX_DIRECTORY_ENTRIES> = list {}
    var source: Bytes max MAX_SOURCE_BYTES_PER_PACKAGE = Bytes.empty()
    var files: list<SourceFile, MAX_SOURCE_FILES> = list {}
    var tokens: list<Token, TOKEN_STORAGE_CAPACITY> = list {}
    var delimiters: list<DelimiterKind, MAX_DELIMITER_NESTING> = list {}
    var file_data: Bytes max MAX_SOURCE_BYTES_PER_FILE = Bytes.empty()

    load_and_lex(env, package, entries, source, files, tokens, delimiters, file_data)
    match output_token_dump(env.out, source, files, tokens) {
        ok(_) => (),
        err(_) => fail_tool(env, "cannot write token output"),
    }
}
