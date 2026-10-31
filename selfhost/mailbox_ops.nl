// Mailbox operations: the ring's address is held in a mailbox, sender or receiver value (a one-field struct).

// The ring's address in a mailbox, sender or receiver value, as a pointer.
fn emit_mailbox_handle_pointer(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    receiver: long,
) {
    var location = collection_value_location(tables, compiler, receiver)
    if tables.nodes[receiver].kind == NodeKind.Field {
        let address_id = emit_late_place_address(tables, compiler, ir, receiver)
        location = compiler_location(compiler, 2L, address_id, 0L)
    }
    let pointer_serial = emit_location_pointer_materialization(compiler, ir, location)
    ir_write_ascii(compiler, ir, "  %mb.handle."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = load i64, ptr "); emit_location_pointer_reference(compiler, ir, location, pointer_serial)
    ir_write_ascii(compiler, ir, ", align 1\n  %mb.ring."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = inttoptr i64 %mb.handle."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to ptr\n")
}

// sender(), receiver(), close(), send(x), recv(), recv_wait().
fn emit_mailbox_method(
    tables: ParseTables,
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    method: long,
) {
    let receiver = compiler.child_first[node]
    let record = mailbox_record_of_type(compiler, compiler.facts[receiver].ty)
    emit_mailbox_handle_pointer(tables, compiler, ir, node, receiver)
    if method == MAILBOX_METHOD_CLOSE {
        ir_write_ascii(compiler, ir, "  call void @nl.mbox.close(ptr %mb.ring."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    if method == MAILBOX_METHOD_RELEASE {
        // The owner gives the ring's memory back; no handle to it may be used afterwards.
        ir_write_ascii(compiler, ir, "  call void @nl_job_args_free(ptr %mb.ring."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ")\n")
        return
    }
    if method == MAILBOX_METHOD_SENDER || method == MAILBOX_METHOD_RECEIVER {
        // The same address, in the other handle type.
        let destination = aggregate_destination_location(compiler, 0L, node)
        let serial = emit_location_pointer_materialization(compiler, ir, destination)
        ir_write_ascii(compiler, ir, "  store i64 %mb.handle."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, destination, serial); ir_write_ascii(compiler, ir, ", align 1\n")
        return
    }
    let element_size = value_type_size(compiler, record.element)
    if method == MAILBOX_METHOD_SEND {
        let message = compiler.child_next[receiver]
        if is_aggregate_type(compiler, record.element) {
            let source_location = aggregate_source_location_for_node(tables, compiler, message)
            let source_pointer = emit_location_pointer_materialization(compiler, ir, source_location)
            ir_write_ascii(compiler, ir, "  %mb.message."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = getelementptr i8, ptr "); emit_location_pointer_reference(compiler, ir, source_location, source_pointer)
            ir_write_ascii(compiler, ir, ", i64 0\n")
        } else {
            ir_write_ascii(compiler, ir, "  %mb.message."); ir_write_number(compiler, ir, node)
            ir_write_ascii(compiler, ir, " = alloca "); ir_write_ascii(compiler, ir, llvm_type_name(record.element)); ir_write_ascii(compiler, ir, ", align 8\n")
            ir_write_ascii(compiler, ir, "  store "); ir_write_ascii(compiler, ir, llvm_type_name(record.element)); ir_push_byte(compiler, ir, 32)
            ir_write_value_ref(compiler, ir, message)
            ir_write_ascii(compiler, ir, ", ptr %mb.message."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ", align 1\n")
        }
        ir_write_ascii(compiler, ir, "  %mb.sent."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, " = call i1 @nl.mbox.send(ptr %mb.ring."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", ptr %mb.message."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ")\n  br i1 %mb.sent."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", label %mb.send.ok."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, ", label %mb.send.full."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, "\nmb.send.ok."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_collection_capacity_result_tag(compiler, ir, node, 0L)
        ir_write_ascii(compiler, ir, "  br label %mb.send.done."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, "\nmb.send.full."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        emit_collection_capacity_result_tag(compiler, ir, node, 1L)
        ir_write_ascii(compiler, ir, "  br label %mb.send.done."); ir_write_number(compiler, ir, node)
        ir_write_ascii(compiler, ir, "\nmb.send.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
        return
    }
    // recv and recv_wait produce an Option of the message, written straight into its payload.
    let result_type = compiler.facts[node].ty
    let payload = sum_payload_record(compiler, result_type, 0L, 0L)
    let address = enum_temporary_address(node, MAX_TREE_NODES * 3L + 5L)
    emit_layout_address(compiler, ir, address, storage_location_with_offset(aggregate_destination_location(compiler, 0L, node), payload.offset))
    ir_write_ascii(compiler, ir, "  %mb.got."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = call i1 @nl.mbox.")
    ir_write_ascii(compiler, ir, if method == MAILBOX_METHOD_RECV_WAIT { "recv_wait" } else { "recv" })
    ir_write_ascii(compiler, ir, "(ptr %mb.ring."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr %addr."); ir_write_number(compiler, ir, address)
    ir_write_ascii(compiler, ir, ")\n  br i1 %mb.got."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %mb.recv.some."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", label %mb.recv.none."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nmb.recv.some."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    emit_sum_tag_store(compiler, ir, node, 0L)
    ir_write_ascii(compiler, ir, "  br label %mb.recv.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nmb.recv.none."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    emit_sum_tag_store(compiler, ir, node, 1L)
    ir_write_ascii(compiler, ir, "  br label %mb.recv.done."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, "\nmb.recv.done."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, ":\n")
    if element_size < 0L { compiler.ir_overflow = true }
}

// `mailbox {}`: allocate the ring (never freed before the program ends), set it up, and put its address in the value.
fn emit_mailbox_literal(
    compiler: write CompilerTables,
    ir: grow Bytes max IR_BUFFER_CAPACITY,
    node: long,
    type_id: long,
) {
    let record = mailbox_record_of_type(compiler, type_id)
    let element_size = value_type_size(compiler, record.element)
    let stride = ((element_size + 15L) / 8L) * 8L
    let bytes = 128L + record.capacity * stride
    ir_write_ascii(compiler, ir, "  %mb.new."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = call ptr @nl_job_args_alloc(i64 "); ir_write_number(compiler, ir, bytes)
    ir_write_ascii(compiler, ir, ")\n  call void @nl.mbox.init(ptr %mb.new."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, record.capacity)
    ir_write_ascii(compiler, ir, ", i64 "); ir_write_number(compiler, ir, element_size); ir_write_ascii(compiler, ir, ")\n")
    ir_write_ascii(compiler, ir, "  %mb.address."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, " = ptrtoint ptr %mb.new."); ir_write_number(compiler, ir, node); ir_write_ascii(compiler, ir, " to i64\n")
    let destination = aggregate_destination_location(compiler, 0L, node)
    let serial = emit_location_pointer_materialization(compiler, ir, destination)
    ir_write_ascii(compiler, ir, "  store i64 %mb.address."); ir_write_number(compiler, ir, node)
    ir_write_ascii(compiler, ir, ", ptr "); emit_location_pointer_reference(compiler, ir, destination, serial); ir_write_ascii(compiler, ir, ", align 1\n")
}
