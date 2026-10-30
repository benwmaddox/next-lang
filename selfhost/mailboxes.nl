// Mailbox types. `mailbox<T, N>`, `Sender<T>` and `Receiver<T>` are each a one-field struct holding the address of a
// ring allocated when the mailbox is created (selfhost/mailbox_ring.ll); copying a handle copies the address.

const MAILBOX_METHOD_SENDER: long = 4001L
const MAILBOX_METHOD_RECEIVER: long = 4002L
const MAILBOX_METHOD_CLOSE: long = 4003L
const MAILBOX_METHOD_SEND: long = 4004L
const MAILBOX_METHOD_RECV: long = 4005L
const MAILBOX_METHOD_RECV_WAIT: long = 4006L

fn mailbox_role_of_type(compiler: CompilerTables, type_id: long) -> long {
    for index in 0L..compiler.mailbox_types.count() {
        if compiler.mailbox_types[index].type_id == type_id { return compiler.mailbox_types[index].role }
    }
    0L
}

fn mailbox_record_of_type(compiler: CompilerTables, type_id: long) -> MailboxRecord {
    for index in 0L..compiler.mailbox_types.count() {
        if compiler.mailbox_types[index].type_id == type_id { return compiler.mailbox_types[index] }
    }
    MailboxRecord { type_id: -1L, role: 0L, element: -1L, capacity: 0L }
}

// The struct type for a mailbox, sender or receiver of `element` (made on first use; -1 when the table is full).
fn intern_mailbox_type(compiler: write CompilerTables, role: long, element: long, capacity: long, file_index: long) -> long {
    for index in 0L..compiler.mailbox_types.count() {
        let record = compiler.mailbox_types[index]
        if record.role == role && record.element == element && record.capacity == capacity { return record.type_id }
    }
    let ordinal = compiler.mailbox_types.count()
    let struct_index = struct_type_count(compiler)
    let field_start = compiler.struct_fields.count()
    compiler.struct_fields.push(StructFieldRecord {
        owner: struct_index,
        name_id: -200L - role,
        name_token: -1L,
        node: -4L,
        type_node: -1L,
        ty: TY_LONG,
        offset: 0L,
        default_node: -1L,
    }).unwrap()
    let type_id = append_type_record(compiler, TypeRecord {
        kind_state: TYPE_KIND_STRUCT * 16L + 2L,
        name_id: -2000L - ordinal,
        name_token: -1L,
        node: -4L,
        file: file_index,
        field_start,
        field_count: 1L,
        size: 8L,
        align: 8L,
        helper_mask: 0L,
    })
    let record = MailboxRecord { type_id, role, element, capacity }
    match compiler.mailbox_types.push(record) {
        ok(_) => type_id,
        err(_) => -1L,
    }
}

// `mailbox<T, N>`, `Sender<T>` or `Receiver<T>` written as a type: which one, or 0.
fn mailbox_type_syntax_role(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    file_index: long,
    syntax: Node,
) -> long {
    if syntax.token < 0L { return 0L }
    if token_is_word_at(source, tokens, files, file_index, syntax.token, "mailbox") { MAILBOX_ROLE_MAILBOX }
    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "Sender") { MAILBOX_ROLE_SENDER }
    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "Receiver") { MAILBOX_ROLE_RECEIVER }
    else { 0L }
}

fn intern_mailbox_type_syntax(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tables: ParseTables,
    compiler: write CompilerTables,
    file_index: long,
    node: long,
    role: long,
) -> long {
    if !compiler.c_runtime { return -1L }
    let syntax = tables.nodes[node]
    let argument_count = syntax.meta1 & 2097151L
    let constant_count = (syntax.meta1 >> 21L) & 2097151L
    let element_node = compiler.child_first[node]
    if element_node < 0L || tables.nodes[element_node].kind != NodeKind.TypeArgument { return -1L }
    if (compiler.facts[element_node].flags & FACT_RESOLVED_TYPE) == 0L { return -1L }
    let element = compiler.facts[element_node].ty
    var capacity = 0L
    if role == MAILBOX_ROLE_MAILBOX {
        if constant_count != 1L { return -1L }
        let capacity_node = compiler.child_next[element_node]
        if capacity_node < 0L { return -1L }
        let value = evaluate_collection_capacity(tables, compiler, capacity_node, 0L)
        if !value.constant || !value.valid || value.value < 1L || value.value > 1073741824L { return -1L }
        capacity = value.value
    } else if argument_count != 1L || constant_count != 0L {
        return -1L
    } else { () }
    intern_mailbox_type(compiler, role, element, capacity, file_index)
}
