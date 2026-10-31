// Method syntax for user structs: `x.m(args)` calls the function `Type_m(x, args)` when x is a struct named Type and such
// a function exists. It is only a spelling: the checker records the call like a direct call of that function with the
// receiver as its first argument (FACT_STRUCT_METHOD), and the emitter treats the node as a call.

const FACT_STRUCT_METHOD: long = 32768L

// The function `<struct name>_<method name>`, or -1 when the receiver is not a user struct or there is none.
fn struct_method_target(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    compiler: CompilerTables,
    receiver_ty: long,
    method_token: long,
    method_file: long,
) -> long {
    if receiver_ty < 0L || type_kind(compiler, receiver_ty) != TYPE_KIND_STRUCT { return -1L }
    let record = type_record(compiler, receiver_ty)
    if record.name_token < 0L || record.name_id < 0L { return -1L }
    let type_length = tokens[record.name_token].length
    let method_length = tokens[method_token].length
    let type_start = files[record.file].base + tokens[record.name_token].start
    let method_start = files[method_file].base + tokens[method_token].start
    for function_id in 0L..compiler.functions.count() {
        let function = compiler.functions[function_id]
        if function.name_token < 0L || tokens[function.name_token].length != type_length + 1L + method_length { continue }
        let function_start = files[function.file].base + tokens[function.name_token].start
        var same = true
        for index in 0L..type_length {
            if source[function_start + index] != source[type_start + index] { same = false; break }
        }
        if !same || source[function_start + type_length] != 95 { continue }
        for index in 0L..method_length {
            if source[function_start + type_length + 1L + index] != source[method_start + index] { same = false; break }
        }
        if same { return function_id }
    }
    -1L
}

// Whether some function is named `<anything>_<method name>`: the early scan for unsupported nodes runs before types are
// known, so it lets such a method call through and the checker decides.
fn method_function_exists(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    method_token: long,
    method_file: long,
) -> bool {
    let method_length = tokens[method_token].length
    let method_start = files[method_file].base + tokens[method_token].start
    for declaration in 0L..tables.nodes.count() {
        if tables.nodes[declaration].kind != NodeKind.Function { continue }
        let name_token = tables.nodes[declaration].token
        if name_token < 0L { continue }
        let function_length = tokens[name_token].length
        if function_length <= method_length + 1L { continue }
        let function_start = files[node_file_index(tables.nodes, files, declaration)].base + tokens[name_token].start
        let suffix_start = function_start + function_length - method_length
        if source[suffix_start - 1L] != 95 { continue }
        var same = true
        for index in 0L..method_length {
            if source[suffix_start + index] != source[method_start + index] { same = false; break }
        }
        if same { return true }
    }
    false
}
