fn check_one_body(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    config: MemoryConfig,
    compiler: write CompilerTables,
    body: long,
    file_index: long,
    function_id: long,
    result_ty: long,
    is_test: bool,
    root_scope: long,
) {
    compiler.work.clear()
    compiler.loop_push_proofs.clear()
    compiler.collection_count_changes.clear()
    compiler.collection_count_branch_values.clear()
    compiler.collection_count_joins.clear()
    compiler.loop_count_snapshots.clear()
    push_check_frame(env, files, compiler, CheckFrame {
        node: body,
        scope: root_scope,
        expected: result_ty,
        function_id,
        loop_depth: 0L,
        is_test,
        phase: 0L,
        cursor: -1L,
        child0: -1L,
        child1: -1L,
        child2: -1L,
        result_ty: -1L,
        auxiliary: 1L,
        reachable: true,
    })
    for work_step in 0L..MAX_PARSE_WORK {
        if compiler.work.count() == 0L { break }
        let frame_index = compiler.work.count() - 1L
        var frame = compiler.work[frame_index]
        let node = frame.node
        let syntax = tables.nodes[node]
        let kind = syntax.kind
        if kind == NodeKind.Match && frame.phase == 0L {
            frame.child0 = compiler.child_first[node]
            frame.cursor = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
            frame.auxiliary = begin_collection_count_join(compiler, node, 1L)
            frame.phase = 70L
            compiler.work[frame_index] = frame
            if frame.child0 >= 0L {
                push_check_frame(env, files, compiler, CheckFrame {
                    node: frame.child0,
                    scope: frame.scope,
                    expected: -1L,
                    function_id,
                    loop_depth: frame.loop_depth,
                    is_test,
                    phase: 0L,
                    cursor: -1L,
                    child0: -1L,
                    child1: -1L,
                    child2: -1L,
                    result_ty: -1L,
                    auxiliary: 0L,
                    reachable: true,
                })
            }
            continue
        }
        if kind == NodeKind.Match && frame.phase == 70L {
            let matched_type = compiler.facts[frame.child0].ty
            if !compiler.collection_count_joins[frame.auxiliary].started {
                start_collection_count_join(compiler, frame.auxiliary)
            }
            if !is_sum_type(compiler, matched_type) && !is_numeric_type(matched_type) && matched_type != TY_BYTE && matched_type != TY_BOOL {
                fail_match_requires_supported_type(env, source, files, tokens, tables, compiler, file_index, node, matched_type)
            }
            let arm = frame.cursor
            if arm < 0L {
                if !match_has_prior_wildcard(tables, compiler, node, -1L) {
                    if is_sum_type(compiler, matched_type) {
                        if match_covered_count(tables, compiler, node, MATCH_PATTERN_CASE) != sum_case_count(compiler, matched_type) {
                            fail_match_exhaustiveness(env, source, files, tokens, tables, compiler, file_index, node, matched_type)
                        }
                    } else if matched_type == TY_BOOL {
                        if match_covered_count(tables, compiler, node, MATCH_PATTERN_BOOL) != 2L {
                            fail_match_exhaustiveness(env, source, files, tokens, tables, compiler, file_index, node, matched_type)
                        }
                    } else {
                        fail_match_exhaustiveness(env, source, files, tokens, tables, compiler, file_index, node, matched_type)
                    }
                }
                let match_result_ty = if frame.result_ty < 0L { TY_NEVER } else { frame.result_ty }
                if frame.expected >= 0L && match_result_ty != TY_NEVER && match_result_ty != frame.expected {
                    require_type(env, files, compiler, file_index, node, frame.expected, match_result_ty, tables)
                }
                finish_match_collection_count_join(compiler, frame.auxiliary)
                compiler.facts[node] = NodeFact { ty: match_result_ty, flags: if match_result_ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
                match compiler.work.pop() { some(_) => (), none() => () }
                continue
            }
            let pattern = compiler.child_first[arm]
            let body_node = if pattern >= 0L { compiler.child_next[pattern] } else { -1L }
            let pattern_kind = tables.nodes[pattern].kind
            let has_wildcard = match_has_prior_wildcard(tables, compiler, node, arm)
            if pattern_kind == NodeKind.WildcardPattern {
                var already_total = false
                if is_sum_type(compiler, matched_type) {
                    already_total = match_covered_count(tables, compiler, node, MATCH_PATTERN_CASE) == sum_case_count(compiler, matched_type)
                } else if matched_type == TY_BOOL {
                    already_total = match_covered_count(tables, compiler, node, MATCH_PATTERN_BOOL) == 2L
                } else { () }
                if has_wildcard || already_total {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[arm].start, "unreachable match arm; previous patterns already cover this value")
                }
                compiler.facts[pattern] = NodeFact { ty: matched_type, flags: MATCH_PATTERN_WILDCARD, binding: -1L, function: -1L, literal: 0L }
            } else if pattern_kind == NodeKind.Integer {
                if !is_numeric_type(matched_type) && matched_type != TY_BYTE {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "integer patterns require an int, long, byte, or numeric refinement match value")
                }
                if has_wildcard { fail_at_message(env, files, compiler, file_index, tables.nodes[arm].start, "unreachable match arm after '_'") }
                let pattern_ty = if (tables.nodes[pattern].flags & FLAG_LONG_SUFFIX) != 0L { TY_LONG } else { matched_type }
                require_type(env, files, compiler, file_index, pattern, matched_type, pattern_ty, tables)
                let value = literal_value(env, source, tokens, files, compiler, tables, file_index, pattern, pattern_ty)
                if match_prior_pattern(tables, compiler, node, arm, MATCH_PATTERN_INTEGER, value) {
                    fail_match_scalar_duplicate(env, files, tables, compiler, file_index, arm, value, false)
                }
                compiler.facts[pattern] = NodeFact { ty: matched_type, flags: MATCH_PATTERN_INTEGER, binding: -1L, function: -1L, literal: value }
            } else if pattern_kind == NodeKind.BoolPattern {
                if matched_type != TY_BOOL {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "bool patterns require a bool match value")
                }
                let value = if (tables.nodes[pattern].flags & FLAG_VALUE) != 0L { 1L } else { 0L }
                if has_wildcard || match_prior_pattern(tables, compiler, node, arm, MATCH_PATTERN_BOOL, value) {
                    fail_match_scalar_duplicate(env, files, tables, compiler, file_index, arm, value, true)
                }
                compiler.facts[pattern] = NodeFact { ty: TY_BOOL, flags: MATCH_PATTERN_BOOL, binding: -1L, function: -1L, literal: value }
            } else if pattern_kind == NodeKind.CasePattern {
                if !is_sum_type(compiler, matched_type) {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "enum case patterns require an enum, Option, or Result match value")
                }
                if has_wildcard { fail_at_message(env, files, compiler, file_index, tables.nodes[arm].start, "unreachable match arm after '_'") }
                let generic_sum = type_kind(compiler, matched_type) == TYPE_KIND_OPTION || type_kind(compiler, matched_type) == TYPE_KIND_RESULT
                if (tables.nodes[pattern].flags & FLAG_HAS_ANNOTATION) != 0L {
                    let qualifier = tables.nodes[pattern].extra
                    if generic_sum {
                        let qualifier_matches = (type_kind(compiler, matched_type) == TYPE_KIND_OPTION && token_is_word_at(source, tokens, files, file_index, qualifier, "Option")) ||
                            (type_kind(compiler, matched_type) == TYPE_KIND_RESULT && token_is_word_at(source, tokens, files, file_index, qualifier, "Result"))
                        if !qualifier_matches { fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "qualified match case does not match the Option or Result scrutinee") } else { () }
                    } else if enum_type_matches(compiler, compiler.token_name_ids[qualifier]) != matched_type {
                        fail_match_qualifier(env, source, files, tokens, tables, compiler, file_index, pattern, matched_type)
                    } else { () }
                }
                let tag = if generic_sum {
                    sum_case_tag_for_name(source, tokens, files, file_index, compiler, matched_type, tables.nodes[pattern].token)
                } else {
                    let found_case = enum_case_matches(compiler, matched_type, compiler.token_name_ids[tables.nodes[pattern].token])
                    if found_case >= 0L { compiler.enum_cases[found_case].tag } else { -1L }
                }
                if tag < 0L {
                    if generic_sum { fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "unknown Option or Result match case") }
                    else { fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "unknown enum match case") }
                }
                let case_index = if generic_sum { -1L } else { enum_case_matches(compiler, matched_type, compiler.token_name_ids[tables.nodes[pattern].token]) }
                let payload_count = if generic_sum { sum_case_payload_count(compiler, matched_type, tag) } else { compiler.enum_cases[case_index].payload_count }
                let binding_count = count_children(tables, compiler, pattern)
                if binding_count != payload_count {
                    if generic_sum { fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "Option or Result match case has the wrong number of payload bindings") }
                    else { fail_match_case_arity(env, source, files, tokens, tables, compiler, file_index, pattern, matched_type, case_index, binding_count) }
                }
                if match_prior_pattern(tables, compiler, node, arm, MATCH_PATTERN_CASE, tag) {
                    if generic_sum { fail_at_message(env, files, compiler, file_index, tables.nodes[arm].start, "duplicate Option or Result match case") }
                    else { fail_match_duplicate_case(env, source, files, tokens, tables, compiler, file_index, arm, matched_type, case_index) }
                }
                compiler.facts[pattern] = NodeFact { ty: matched_type, flags: MATCH_PATTERN_CASE, binding: case_index, function: -1L, literal: tag }
                let arm_scope = create_scope(env, files, compiler, frame.scope, function_id, arm, file_index)
                let body_scope = if tables.nodes[body_node].kind == NodeKind.Block { create_scope(env, files, compiler, arm_scope, function_id, body_node, file_index) } else { arm_scope }
                var binding_node = compiler.child_first[pattern]
                for payload_index in 0L..payload_count {
                    if binding_node < 0L { fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "internal match pattern payload count mismatch") }
                    let payload_ty = if generic_sum { sum_case_payload_type(compiler, matched_type, tag, payload_index) }
                        else { compiler.enum_payloads[compiler.enum_cases[case_index].payload_start + payload_index].ty }
                    if tables.nodes[binding_node].kind == NodeKind.PatternBinding {
                        let binding = add_local_binding(env, source, files, tokens, tables, compiler, file_index, binding_node, tables.nodes[binding_node].token, arm_scope, payload_ty, false, false, false)
                        compiler.facts[binding_node] = NodeFact { ty: payload_ty, flags: FACT_FALLS_THROUGH, binding, function: -1L, literal: payload_index }
                    } else {
                        compiler.facts[binding_node] = NodeFact { ty: payload_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: payload_index }
                    }
                    binding_node = compiler.child_next[binding_node]
                }
                frame.child1 = arm
                frame.child2 = body_node
                frame.phase = 71L
                compiler.work[frame_index] = frame
                push_check_frame(env, files, compiler, CheckFrame {
                    node: body_node,
                    scope: body_scope,
                    expected: frame.expected,
                    function_id,
                    loop_depth: frame.loop_depth,
                    is_test,
                    phase: 0L,
                    cursor: -1L,
                    child0: -1L,
                    child1: -1L,
                    child2: -1L,
                    result_ty: -1L,
                    auxiliary: 1L,
                    reachable: true,
                })
                continue
            } else {
                fail_at_message(env, files, compiler, file_index, tables.nodes[pattern].start, "unsupported match pattern")
            }
            let arm_scope = create_scope(env, files, compiler, frame.scope, function_id, arm, file_index)
            let body_scope = if tables.nodes[body_node].kind == NodeKind.Block { create_scope(env, files, compiler, arm_scope, function_id, body_node, file_index) } else { arm_scope }
            frame.child1 = arm
            frame.child2 = body_node
            frame.phase = 71L
            compiler.work[frame_index] = frame
            push_check_frame(env, files, compiler, CheckFrame {
                node: body_node,
                scope: body_scope,
                expected: frame.expected,
                function_id,
                loop_depth: frame.loop_depth,
                is_test,
                phase: 0L,
                cursor: -1L,
                child0: -1L,
                child1: -1L,
                child2: -1L,
                result_ty: -1L,
                auxiliary: 1L,
                reachable: true,
            })
            continue
        }
        if kind == NodeKind.Match && frame.phase == 71L {
            let arm_type = compiler.facts[frame.child2].ty
            record_collection_count_branch(
                compiler,
                frame.auxiliary,
                frame.child1,
                (compiler.facts[frame.child2].flags & FACT_FALLS_THROUGH) != 0L,
            )
            if arm_type != TY_NEVER {
                if frame.result_ty < 0L {
                    frame.result_ty = arm_type
                } else if frame.result_ty != arm_type {
                    if type_kind(compiler, frame.result_ty) == TYPE_KIND_ASCII && type_kind(compiler, arm_type) == TYPE_KIND_ASCII {
                        let result_maximum = text_max_bytes(compiler, frame.result_ty)
                        let arm_maximum = text_max_bytes(compiler, arm_type)
                        if arm_maximum > result_maximum {
                            frame.result_ty = intern_text_type(compiler, TYPE_KIND_ASCII, arm_maximum, 0L, file_index, node, -1L, -1L)
                            if frame.result_ty < 0L {
                                fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child1].start,
                                    "Ascii match result exceeds compiler capacity")
                            }
                        }
                    } else {
                        fail_match_arm_type(env, source, files, tokens, tables, compiler, file_index, frame.child1, frame.result_ty, arm_type)
                    }
                } else { () }
            }
            frame.cursor = compiler.child_next[frame.child1]
            frame.child1 = -1L
            frame.child2 = -1L
            frame.phase = 70L
            compiler.work[frame_index] = frame
            continue
        }
        if kind == NodeKind.If && frame.phase == 0L {
            frame.child0 = compiler.child_first[node]
            frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
            frame.child2 = if frame.child1 >= 0L { compiler.child_next[frame.child1] } else { -1L }
            frame.auxiliary = begin_collection_count_join(compiler, node, 0L)
            frame.phase = 200L
            compiler.work[frame_index] = frame
            push_check_frame(env, files, compiler, CheckFrame {
                node: frame.child0,
                scope: frame.scope,
                expected: TY_BOOL,
                function_id,
                loop_depth: frame.loop_depth,
                is_test,
                phase: 0L,
                cursor: -1L,
                child0: -1L,
                child1: -1L,
                child2: -1L,
                result_ty: -1L,
                auxiliary: 0L,
                reachable: true,
            })
            continue
        }
        if kind == NodeKind.If && frame.phase == 200L {
            start_collection_count_join(compiler, frame.auxiliary)
            frame.phase = 201L
            compiler.work[frame_index] = frame
            let expected = body_child_expected(source, tokens, files, tables, compiler, node, frame.child1, frame, 1L, file_index, config)
            push_check_frame(env, files, compiler, CheckFrame {
                node: frame.child1,
                scope: frame.scope,
                expected,
                function_id,
                loop_depth: frame.loop_depth,
                is_test,
                phase: 0L,
                cursor: -1L,
                child0: -1L,
                child1: -1L,
                child2: -1L,
                result_ty: -1L,
                auxiliary: 0L,
                reachable: true,
            })
            continue
        }
        if kind == NodeKind.If && frame.phase == 201L {
            let condition_falls = (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) != 0L
            let then_falls = condition_falls && (compiler.facts[frame.child1].flags & FACT_FALLS_THROUGH) != 0L
            compiler.collection_count_joins[frame.auxiliary].branch0_falls = then_falls
            record_collection_count_branch(compiler, frame.auxiliary, 0L, then_falls)
            if frame.child2 >= 0L {
                frame.phase = 202L
                compiler.work[frame_index] = frame
                let expected = body_child_expected(source, tokens, files, tables, compiler, node, frame.child2, frame, 2L, file_index, config)
                push_check_frame(env, files, compiler, CheckFrame {
                    node: frame.child2,
                    scope: frame.scope,
                    expected,
                    function_id,
                    loop_depth: frame.loop_depth,
                    is_test,
                    phase: 0L,
                    cursor: -1L,
                    child0: -1L,
                    child1: -1L,
                    child2: -1L,
                    result_ty: -1L,
                    auxiliary: 0L,
                    reachable: true,
                })
            } else {
                compiler.collection_count_joins[frame.auxiliary].branch1_falls = condition_falls
                finish_if_collection_count_join(compiler, frame.auxiliary)
                frame.phase = 2L
                compiler.work[frame_index] = frame
            }
            continue
        }
        if kind == NodeKind.If && frame.phase == 202L {
            let condition_falls = (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) != 0L
            let else_falls = condition_falls && (compiler.facts[frame.child2].flags & FACT_FALLS_THROUGH) != 0L
            compiler.collection_count_joins[frame.auxiliary].branch1_falls = else_falls
            record_collection_count_branch(compiler, frame.auxiliary, 1L, else_falls)
            finish_if_collection_count_join(compiler, frame.auxiliary)
            frame.phase = 2L
            compiler.work[frame_index] = frame
            continue
        }
        if frame.phase == 0L {
            if function_id <= -100000L && (kind == NodeKind.Return || kind == NodeKind.ReturnStatement) {
                fail_at_message(env, files, compiler, file_index, syntax.start, "return is not allowed in a field default")
            }
            if kind == NodeKind.StructInit {
                let type_index = struct_type_matches(compiler, compiler.token_name_ids[syntax.token])
                if type_index < 0L {
                    if is_builtin_type_name(source, tokens, files, compiler, file_index, syntax.token) {
                        fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start, "'", syntax.token, "' is not a struct type")
                    }
                    fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start, "unknown struct '", syntax.token, "'; declare it with struct")
                }
                frame.result_ty = struct_type_id(compiler, type_index)
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Field {
                let receiver = compiler.child_first[node]
                if receiver >= 0L && tables.nodes[receiver].kind == NodeKind.Name &&
                    find_binding_in_scope(compiler, frame.scope, compiler.token_name_ids[tables.nodes[receiver].token]) < 0L {
                    let type_id = enum_type_matches(compiler, compiler.token_name_ids[tables.nodes[receiver].token])
                    if type_id >= 0L {
                        let case_index = enum_case_matches(compiler, type_id, compiler.token_name_ids[syntax.token])
                        if case_index >= 0L {
                            let case = compiler.enum_cases[case_index]
                            if case.payload_count > 0L { fail_enum_case_needs_payload(env, source, files, tokens, tables, compiler, file_index, node, case.owner, case_index) }
                            let ty = type_id
                            if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                            compiler.facts[node] = NodeFact { ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: case.tag }
                            match compiler.work.pop() { some(_) => (), none() => () }
                            continue
                        }
                    }
                }
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Block {
                if frame.auxiliary == 1L { frame.auxiliary = 0L }
                else { frame.scope = create_scope(env, files, compiler, frame.scope, function_id, node, file_index) }
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Let {
                var annotation = -1L
                var value = -1L
                var child = compiler.child_first[node]
                for child_step in 0L..syntax.subtree {
                    if child < 0L { break }
                    if tables.nodes[child].kind == NodeKind.Annotation { annotation = child } else { value = child }
                    child = compiler.child_next[child]
                }
                frame.child0 = value
                frame.child1 = if annotation >= 0L { parse_scalar_type(env, source, tokens, files, tables, compiler, file_index, annotation) } else { -1L }
                frame.cursor = value
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Index {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.ArrayLiteral {
                let collection_ty = frame.expected
                let collection_kind = type_kind(compiler, collection_ty)
                if collection_kind != TYPE_KIND_ARRAY && !collection_kind_is_list(collection_kind) && collection_kind != TYPE_KIND_BYTES {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer whether this literal is an array or list; add a T[N] or list<T, N> annotation")
                }
                let element_count = count_children(tables, compiler, node)
                let capacity = if collection_kind == TYPE_KIND_BYTES { text_max_bytes(compiler, collection_ty) } else { collection_capacity(compiler, collection_ty) }
                if collection_kind == TYPE_KIND_ARRAY && element_count != capacity {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "array literal has the wrong number of elements for its array type")
                }
                if collection_kind_is_list(collection_kind) && element_count > capacity {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "list literal exceeds its capacity")
                }
                frame.result_ty = collection_ty
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.QueueLiteral {
                if type_kind(compiler, frame.expected) != TYPE_KIND_QUEUE {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the capacity for 'queue {}'; add a queue<T, N> type annotation")
                }
                compiler.facts[node] = NodeFact { ty: frame.expected, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                match compiler.work.pop() { some(_) => (), none() => () }
                continue
            }
            if kind == NodeKind.PoolLiteral {
                if type_kind(compiler, frame.expected) != TYPE_KIND_POOL && mailbox_role_of_type(compiler, frame.expected) != MAILBOX_ROLE_MAILBOX {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the capacity for 'pool {}'; add a pool<T, N> type annotation")
                }
                compiler.facts[node] = NodeFact { ty: frame.expected, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                match compiler.work.pop() { some(_) => (), none() => () }
                continue
            }
            if kind == NodeKind.MapLiteral {
                if type_kind(compiler, frame.expected) != TYPE_KIND_MAP {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the key and value types for 'map {}'; add a map<K, V, N> type annotation")
                }
                compiler.facts[node] = NodeFact { ty: frame.expected, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                match compiler.work.pop() { some(_) => (), none() => () }
                continue
            }
            if kind == NodeKind.ListLiteral {
                if type_kind(compiler, frame.expected) != TYPE_KIND_LIST {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the capacity for 'list {}'; add a list<T, N> type annotation")
                }
                compiler.facts[node] = NodeFact { ty: frame.expected, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                match compiler.work.pop() { some(_) => (), none() => () }
                continue
            }
            if kind == NodeKind.Assign {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.result_ty = -1L
                frame.cursor = 0L
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Return || kind == NodeKind.ReturnStatement || kind == NodeKind.ExpressionStatement || kind == NodeKind.Discard || kind == NodeKind.Spawn || kind == NodeKind.Expect {
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Call && (syntax.flags & FLAG_SYNTHETIC) != 0L {
                if frame.expected < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "an omitted initializer needs an explicit type") }
                compiler.facts[node] = NodeFact { ty: frame.expected, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                match compiler.work.pop() { some(_) => (), none() => () }
                continue
            }
            if kind == NodeKind.Call {
                let target = find_function_by_name(compiler, compiler.token_name_ids[syntax.token])
                if target < 0L {
                    if builtin_sum_case_name(source, tokens, files, file_index, syntax.token) &&
                        user_case_matches(compiler, compiler.token_name_ids[syntax.token]) == -1L {
                        let constructor_kind = if token_is_word_at(source, tokens, files, file_index, syntax.token, "some") || token_is_word_at(source, tokens, files, file_index, syntax.token, "none") { TYPE_KIND_OPTION } else { TYPE_KIND_RESULT }
                        let constructor_tag = if token_is_word_at(source, tokens, files, file_index, syntax.token, "some") || token_is_word_at(source, tokens, files, file_index, syntax.token, "ok") { 0L } else { 1L }
                        let constructor_code = if constructor_kind == TYPE_KIND_OPTION && constructor_tag == 0L { 21L }
                            else if constructor_kind == TYPE_KIND_OPTION { 22L }
                            else if constructor_tag == 0L { 23L } else { 24L }
                        let expected_kind = type_kind(compiler, frame.expected)
                        let expected_sum = if expected_kind == constructor_kind { frame.expected } else { -1L }
                        let actual = count_children(tables, compiler, node)
                        let wanted = if constructor_code == 22L { 0L } else { 1L }
                        if actual != wanted { fail_at_message(env, files, compiler, file_index, syntax.start, "built-in sum constructor has the wrong number of arguments") }
                        if constructor_kind == TYPE_KIND_OPTION && constructor_tag == 1L && expected_sum < 0L {
                            fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the missing type parameter for 'none'; add an Option<T> expected type")
                        }
                        if constructor_kind == TYPE_KIND_RESULT && expected_sum < 0L {
                            let message: Ascii max 160 = if constructor_tag == 0L { "cannot infer the missing type parameter for 'ok'; add a Result<T, E> expected type" } else { "cannot infer the missing type parameter for 'err'; add a Result<T, E> expected type" }
                            fail_at_message(env, files, compiler, file_index, syntax.start, message)
                        }
                        if frame.expected >= 0L && expected_sum < 0L && constructor_kind == TYPE_KIND_OPTION {
                            fail_at_message(env, files, compiler, file_index, syntax.start, "expected Option<T> for this constructor")
                        }
                        frame.result_ty = expected_sum
                        frame.auxiliary = constructor_code
                        frame.cursor = compiler.child_first[node]
                        frame.phase = 1L
                        compiler.work[frame_index] = frame
                        continue
                    }
                    var case_index = -1L
                    var case_type = -1L
                    if type_kind(compiler, frame.expected) == TYPE_KIND_ENUM {
                        let expected_case = enum_case_matches(compiler, frame.expected, compiler.token_name_ids[syntax.token])
                        if expected_case >= 0L { case_index = expected_case; case_type = frame.expected }
                    }
                    if case_index < 0L {
                        case_index = user_case_matches(compiler, compiler.token_name_ids[syntax.token])
                        if case_index == -2L { fail_ambiguous_enum_case(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token) }
                        if case_index >= 0L { case_type = enum_case_owner_type_id(compiler, case_index) }
                    }
                    if case_index >= 0L {
                        let actual = count_children(tables, compiler, node)
                        if actual != compiler.enum_cases[case_index].payload_count { fail_enum_constructor_arity(env, source, files, tokens, tables, compiler, file_index, node, case_index, actual) }
                        frame.result_ty = case_type
                        frame.child2 = case_index
                        frame.cursor = compiler.child_first[node]
                        frame.phase = 1L
                        compiler.work[frame_index] = frame
                        continue
                    }
                }
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.OptionalCall {
                let receiver = compiler.child_first[node]
                if receiver < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "malformed optional call") }
                frame.child0 = receiver
                frame.cursor = receiver
                frame.auxiliary = -2L
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.QualifiedCase {
                let type_id = enum_type_matches(compiler, compiler.token_name_ids[syntax.token])
                if type_id < 0L {
                    fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start, "unknown enum '", syntax.token, "'; declare it with enum")
                }
                let case_token = tables.extra[syntax.extra]
                let case_index = enum_case_matches(compiler, type_id, compiler.token_name_ids[case_token])
                if case_index < 0L { fail_unknown_enum_case(env, source, files, tokens, tables, compiler, file_index, tokens[case_token].start, case_token, type_id) }
                let actual = count_children(tables, compiler, node)
                if actual != compiler.enum_cases[case_index].payload_count { fail_enum_constructor_arity(env, source, files, tokens, tables, compiler, file_index, node, case_index, actual) }
                frame.result_ty = type_id
                frame.child2 = case_index
                frame.cursor = compiler.child_first[node]
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.MethodCall {
                let receiver = compiler.child_first[node]
                let empty_kind = text_empty_constructor_kind(source, tokens, files, tables, compiler, file_index, frame.scope, node)
                if empty_kind != 0L {
                    let text_ty = intern_text_type(compiler, empty_kind, 0L, 0L, file_index, node, -1L, -1L)
                    if text_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "empty text type exceeds compiler capacity") }
                    frame.child0 = receiver
                    frame.cursor = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                    frame.auxiliary = TEXT_METHOD_EMPTY
                    frame.result_ty = text_ty
                } else if is_core_sys_receiver(source, tokens, files, tables, compiler, node, file_index) {
                    let operation = core_sys_operation(source, tokens, files, file_index, syntax.token)
                    if operation < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "unknown core system operation") }
                    frame.cursor = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                    frame.auxiliary = operation
                } else {
                    frame.child0 = receiver
                    frame.cursor = receiver
                    frame.auxiliary = -1L
                }
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Cast {
                let type_node = compiler.child_first[node]
                let value_node = if type_node >= 0L { compiler.child_next[type_node] } else { -1L }
                if type_node < 0L || value_node < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "malformed cast expression") }
                let target_text_kind = text_type_syntax_kind(source, tokens, files, file_index, tables.nodes[type_node])
                let target_ty = if target_text_kind == TYPE_KIND_ASCII {
                    intern_text_type_syntax(env, source, tokens, files, tables, compiler, file_index, type_node)
                } else { parse_scalar_type(env, source, tokens, files, tables, compiler, file_index, type_node) }
                if !is_numeric_type(target_ty) && target_ty != TY_BYTE && target_ty != TY_DOUBLE && type_kind(compiler, target_ty) != TYPE_KIND_ASCII {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "casts in this subset require int, long, byte, or a bounded Ascii type")
                }
                frame.child0 = value_node
                frame.child1 = type_node
                frame.result_ty = target_ty
                frame.cursor = value_node
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Fit {
                let value_node = compiler.child_first[node]
                let target_node = if value_node >= 0L { compiler.child_next[value_node] } else { -1L }
                if value_node < 0L || target_node < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "malformed fit expression") }
                let target_ty = compiler.facts[target_node].ty
                if type_kind(compiler, target_ty) != TYPE_KIND_ASCII && target_ty != TY_BYTE {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "fit<T>() needs an int or long refinement type")
                }
                frame.child0 = value_node
                frame.child1 = target_node
                frame.result_ty = target_ty
                frame.cursor = value_node
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.ToLong {
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Try {
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Unary {
                frame.child0 = compiler.child_first[node]
                frame.cursor = frame.child0
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.Binary {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.cursor = 0L
                if syntax.flags == 21L {
                    let known = natural_node_type(source, tokens, files, tables, compiler, frame.child0, frame.scope, file_index)
                    let value_ty = if is_aggregate_type(compiler, frame.expected) || is_numeric_type(frame.expected) || frame.expected == TY_BOOL || frame.expected == TY_UNIT {
                        frame.expected
                    } else { natural_node_type(source, tokens, files, tables, compiler, frame.child1, frame.scope, file_index) }
                    if known < 0L && value_ty >= 0L {
                        let file = node_file_index(tables.nodes, files, node)
                        let _ = intern_sum_type(compiler, TYPE_KIND_OPTION, value_ty, -1L, file, node, -1L, -1L)
                    }
                }
                if frame.child0 >= 0L && frame.child1 >= 0L && is_unsuffixed_integer(tables, frame.child0) && frame.expected < 0L { frame.auxiliary = 1L }
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.If {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.child2 = if frame.child1 >= 0L { compiler.child_next[frame.child1] } else { -1L }
                frame.cursor = 0L
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.For {
                var annotation = -1L
                var start = -1L
                var finish = -1L
                var body_node = -1L
                var child = compiler.child_first[node]
                var bound_index = 0L
                for child_step in 0L..syntax.subtree {
                    if child < 0L { break }
                    if tables.nodes[child].kind == NodeKind.Annotation { annotation = child }
                    else if tables.nodes[child].kind == NodeKind.Block { body_node = child }
                    else if bound_index == 0L { start = child; bound_index += 1L }
                    else { finish = child; bound_index += 1L }
                    child = compiler.child_next[child]
                }
                var loop_ty = -1L
                if annotation >= 0L {
                    loop_ty = parse_scalar_type(env, source, tokens, files, tables, compiler, file_index, annotation)
                    if !is_numeric_type(loop_ty) { fail_at_message(env, files, compiler, file_index, tables.nodes[annotation].start, "a loop counter must be int or long; use one of those types") }
                }
                for bound_slot in 0L..2L {
                    let bound = if bound_slot == 0L { start } else { finish }
                    let bound_ty = natural_loop_bound_type(source, tokens, files, tables, compiler, bound, frame.scope, file_index)
                    if bound_ty < 0L { continue }
                    if !is_numeric_type(bound_ty) { fail_loop_bound_type(env, files, compiler, file_index, tables.nodes[bound].start, bound_ty) }
                    if loop_ty < 0L { loop_ty = bound_ty }
                    if loop_ty >= 0L && loop_ty != bound_ty { fail_loop_type_conflict(env, files, compiler, file_index, syntax.start, loop_ty, bound_ty) }
                }
                let counter_name_id = compiler.token_name_ids[syntax.token]
                let body_first = body_node - tables.nodes[body_node].subtree + 1L
                for candidate in body_first..body_node + 1L {
                    if tables.nodes[candidate].kind != NodeKind.Call { continue }
                    let use_ty = loop_body_call_parameter_type(source, tokens, files, tables, compiler, candidate, counter_name_id, file_index)
                    if use_ty < 0L { continue }
                    if loop_ty < 0L { loop_ty = use_ty }
                    if loop_ty != use_ty { fail_loop_type_conflict(env, files, compiler, file_index, syntax.start, loop_ty, use_ty) }
                }
                if loop_ty < 0L { loop_ty = TY_INT }
                let loop_scope = create_scope(env, files, compiler, frame.scope, function_id, node, file_index)
                let _ = add_local_binding(env, source, files, tokens, tables, compiler, file_index, node, syntax.token, loop_scope, loop_ty, false, true, false)
                frame.child0 = start
                frame.child1 = finish
                frame.child2 = body_node
                frame.result_ty = loop_ty
                frame.auxiliary = loop_scope
                frame.cursor = 0L
                frame.phase = 1L
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.While {
                frame.child0 = compiler.child_first[node]
                frame.child1 = if frame.child0 >= 0L { compiler.child_next[frame.child0] } else { -1L }
                frame.cursor = 0L
                frame.phase = 1L
                begin_loop_count_snapshot(compiler, node)
                compiler.work[frame_index] = frame
                continue
            }
            if kind == NodeKind.ForEach {
                let collection = compiler.child_first[node]
                let body_node = if collection >= 0L { compiler.child_next[collection] } else { -1L }
                if collection < 0L || body_node < 0L || tables.nodes[body_node].kind != NodeKind.Block {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "malformed collection loop")
                }
                frame.child0 = collection
                frame.child1 = body_node
                frame.phase = 80L
                compiler.work[frame_index] = frame
                push_check_frame(env, files, compiler, CheckFrame {
                    node: collection,
                    scope: frame.scope,
                    expected: -1L,
                    function_id,
                    loop_depth: frame.loop_depth,
                    is_test,
                    phase: 0L,
                    cursor: -1L,
                    child0: -1L,
                    child1: -1L,
                    child2: -1L,
                    result_ty: -1L,
                    auxiliary: 0L,
                    reachable: true,
                })
                continue
            }
            if kind == NodeKind.Unit {
                compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            } else if kind == NodeKind.BytesLiteral {
                if compiler.core_mode {
                    compiler.facts[node] = NodeFact { ty: TY_ADDR, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                } else {
                    let literal = decode_string_token(source, tokens, files[file_index].base, syntax.extra, true)
                    let text_ty = intern_text_type(compiler, TYPE_KIND_BYTES, literal.count(), 0L, file_index, node, -1L, -1L)
                    if frame.expected >= 0L { require_type(env, files, compiler, file_index, node, frame.expected, text_ty, tables) }
                    compiler.facts[node] = NodeFact { ty: text_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
                }
            } else if kind == NodeKind.ByteString {
                if (syntax.flags & FLAG_BYTESTRING_NONASCII_HEX) != 0L {
                    fail_at_message(env, files, compiler, file_index, syntax.start,
                        "non-ASCII \\xNN escapes are not allowed in Text or Ascii literals; write the character as UTF-8 or use a byte-string literal")
                }
                let literal = decode_string_token(source, tokens, files[file_index].base, syntax.token, false)
                var literal_ty = -1L
                if decoded_text_is_ascii(literal) {
                    if type_kind(compiler, frame.expected) == TYPE_KIND_TEXT {
                        literal_ty = intern_text_type(compiler, TYPE_KIND_TEXT, literal.count(), literal.count(), file_index, node, -1L, -1L)
                    } else {
                        literal_ty = intern_text_type(compiler, TYPE_KIND_ASCII, literal.count(), 0L, file_index, node, -1L, -1L)
                    }
                } else {
                    literal_ty = intern_text_type(compiler, TYPE_KIND_TEXT, literal.count(), decoded_text_codepoints(literal), file_index, node, -1L, -1L)
                }
                if frame.expected >= 0L { require_type(env, files, compiler, file_index, node, frame.expected, literal_ty, tables) }
                compiler.facts[node] = NodeFact { ty: literal_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            } else if kind == NodeKind.Integer && (syntax.flags & FLAG_FLOAT) != 0L {
                if !compiler.c_runtime {
                    report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node, offset: syntax.start, category: UNSUPPORTED_FLOAT, token: syntax.token })
                }
                if frame.expected >= 0L && frame.expected != TY_DOUBLE { require_type(env, files, compiler, file_index, node, frame.expected, TY_DOUBLE, tables) }
                compiler.facts[node] = NodeFact { ty: TY_DOUBLE, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            } else if kind == NodeKind.Integer {
                let ty = if (syntax.flags & FLAG_LONG_SUFFIX) != 0L { TY_LONG } else if is_numeric_type(frame.expected) || frame.expected == TY_BYTE { frame.expected } else { TY_INT }
                if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                let value = literal_value(env, source, tokens, files, compiler, tables, file_index, node, ty)
                compiler.facts[node] = NodeFact { ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: value }
            } else if kind == NodeKind.Bool {
                if frame.expected >= 0L && frame.expected != TY_BOOL { require_type(env, files, compiler, file_index, node, frame.expected, TY_BOOL, tables) }
                compiler.facts[node] = NodeFact { ty: TY_BOOL, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: if (syntax.flags & FLAG_VALUE) != 0L { 1L } else { 0L } }
            } else if kind == NodeKind.Name {
                let binding = find_binding_in_scope(compiler, frame.scope, compiler.token_name_ids[syntax.token])
                if binding < 0L {
                    let constant = find_constant_declaration(tables, compiler, compiler.token_name_ids[syntax.token])
                    if constant >= 0L && (compiler.facts[constant].flags & (FACT_CONSTANT_TEXT | FACT_CONSTANT_ARRAY)) != 0L {
                        let constant_ty = compiler.facts[constant].ty
                        if frame.expected >= 0L && frame.expected != constant_ty {
                            require_type(env, files, compiler, file_index, node, frame.expected, constant_ty, tables)
                        }
                        compiler.facts[node] = NodeFact {
                            ty: constant_ty,
                            flags: FACT_FALLS_THROUGH | (compiler.facts[constant].flags & (FACT_CONSTANT_TEXT | FACT_CONSTANT_ARRAY)),
                            binding: -1L,
                            function: -1L,
                            literal: compiler.facts[constant].literal,
                        }
                        match compiler.work.pop() { some(_) => (), none() => () }
                        continue
                    }
                    if constant >= 0L && (compiler.facts[constant].flags & FACT_CONSTANT_EVALUATED) != 0L {
                        let constant_ty = compiler.facts[constant].ty
                        if frame.expected >= 0L && frame.expected != constant_ty {
                            require_type(env, files, compiler, file_index, node, frame.expected, constant_ty, tables)
                        }
                        compiler.facts[node] = NodeFact {
                            ty: constant_ty,
                            flags: FACT_FALLS_THROUGH | FACT_CONSTANT_VALUE,
                            binding: -1L,
                            function: -1L,
                            literal: compiler.facts[constant].literal,
                        }
                        match compiler.work.pop() { some(_) => (), none() => () }
                        continue
                    }
                    let function = find_function_by_name(compiler, compiler.token_name_ids[syntax.token])
                    if function >= 0L && is_sort_comparator_name(source, tokens, files, tables, compiler, file_index, node) {
                        compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function, literal: 0L }
                        match compiler.work.pop() { some(_) => (), none() => () }
                        continue
                    }
                    if function >= 0L { report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node, offset: syntax.start, category: UNSUPPORTED_NODE, token: syntax.token }) }
                    var case_index = -1L
                    var case_type = -1L
                    let sum_tag = if token_is_word_at(source, tokens, files, file_index, syntax.token, "none") && type_kind(compiler, frame.expected) == TYPE_KIND_OPTION { 1L } else { -1L }
                    if sum_tag >= 0L {
                        compiler.facts[node] = NodeFact { ty: frame.expected, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: sum_tag }
                        match compiler.work.pop() { some(_) => (), none() => () }
                        continue
                    }
                    if token_is_word_at(source, tokens, files, file_index, syntax.token, "none") && frame.expected < 0L {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the missing type parameter for 'none'; add an Option<T> expected type")
                    }
                    if type_kind(compiler, frame.expected) == TYPE_KIND_ENUM {
                    let expected_case = enum_case_matches(compiler, frame.expected, compiler.token_name_ids[syntax.token])
                        if expected_case >= 0L { case_index = expected_case; case_type = frame.expected }
                    } else if frame.expected < 0L {
                        case_index = user_case_matches(compiler, compiler.token_name_ids[syntax.token])
                        if case_index == -2L { fail_ambiguous_enum_case(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token) }
                        if case_index >= 0L { case_type = enum_case_owner_type_id(compiler, case_index) }
                    } else { () }
                    if case_index >= 0L {
                        let case = compiler.enum_cases[case_index]
                        if case.payload_count > 0L { fail_enum_constructor_arity(env, source, files, tokens, tables, compiler, file_index, node, case_index, 0L) }
                        if frame.expected >= 0L && frame.expected != case_type { require_type(env, files, compiler, file_index, node, frame.expected, case_type, tables) }
                        compiler.facts[node] = NodeFact { ty: case_type, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: case.tag }
                        match compiler.work.pop() { some(_) => (), none() => () }
                        continue
                    }
                    fail_name_error(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token, frame.scope, false)
                }
                let ty = compiler.bindings[binding].ty
                if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                compiler.facts[node] = NodeFact { ty, flags: FACT_FALLS_THROUGH, binding, function: -1L, literal: 0L }
            } else if kind == NodeKind.InitializerField {
                fail_at_message(env, files, compiler, file_index, syntax.start, "internal struct initializer checker dispatch failure")
            } else if kind == NodeKind.BreakStatement || kind == NodeKind.ContinueStatement || kind == NodeKind.LoopExit {
                let is_break = kind == NodeKind.BreakStatement || (kind == NodeKind.LoopExit && (syntax.flags & FLAG_VALUE) != 0L)
                if frame.loop_depth == 0L {
                    if function_id <= -100000L {
                        fail_at_message(env, files, compiler, file_index, syntax.start, if is_break { "'break' is only valid inside a loop" } else { "'continue' is only valid inside a loop" })
                    }
                    fail_at_message(env, files, compiler, file_index, syntax.start, if is_break { "'break' is only valid inside a loop; move it into a for body" } else { "'continue' is only valid inside a loop; move it into a for body" })
                }
                compiler.facts[node] = NodeFact { ty: TY_NEVER, flags: FACT_NEVER, binding: -1L, function: -1L, literal: 0L }
            } else {
                fail_at_message(env, files, compiler, file_index, syntax.start, "internal self-hosted checker node dispatch failure")
            }
            match compiler.work.pop() { some(_) => (), none => () }
            continue
        }
        if kind == NodeKind.ForEach && frame.phase == 80L {
            let collection_type = compiler.facts[frame.child0].ty
            let collection_kind = type_kind(compiler, collection_type)
            if collection_kind == TYPE_KIND_MAP {
                report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node: frame.child0, offset: tables.nodes[frame.child0].start, category: UNSUPPORTED_MAP_USE, token: tables.nodes[frame.child0].token })
            }
            if collection_kind == TYPE_KIND_QUEUE {
                report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node: frame.child0, offset: tables.nodes[frame.child0].start, category: UNSUPPORTED_QUEUE_USE, token: tables.nodes[frame.child0].token })
            }
            if collection_kind == TYPE_KIND_POOL {
                report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node: frame.child0, offset: tables.nodes[frame.child0].start, category: UNSUPPORTED_POOL_USE, token: tables.nodes[frame.child0].token })
            }
            if collection_kind != TYPE_KIND_ARRAY && collection_kind != TYPE_KIND_LIST &&
                collection_kind != TYPE_KIND_ASCII && collection_kind != TYPE_KIND_BYTES {
                fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start, "for-each loops require an array, list, Ascii, or Bytes")
            }
            let collection_binding = place_root_binding(tables, compiler, frame.child0)
            if !is_assignable_place(tables, frame.child0) || collection_binding < 0L {
                fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start, "collection iteration needs a local, parameter, or field place; bind the value to a local first")
            }
            let mutable_view = compiler.bindings[collection_binding].mutable
            let view_scope = create_scope(env, files, compiler, frame.scope, function_id, node, file_index)
            let element_type = collection_element_type(compiler, collection_type)
            let view_binding = add_local_binding(env, source, files, tokens, tables, compiler, file_index, node, syntax.token, view_scope, element_type, mutable_view, false, false)
            var view_record = compiler.bindings[view_binding]
            view_record.name_token = 0L - 1L - view_record.name_token
            compiler.bindings[view_binding] = view_record
            if syntax.aux > 0L {
                let index_token = tables.extra[syntax.extra]
                let _ = add_local_binding(env, source, files, tokens, tables, compiler, file_index, node, index_token, view_scope, TY_LONG, false, true, false)
            }
            frame.phase = 81L
            frame.result_ty = element_type
            frame.auxiliary = view_scope
            frame.child2 = frame.child1
            let iterations = if collection_binding >= 0L && compiler.bindings[collection_binding].collection_count >= 0L {
                compiler.bindings[collection_binding].collection_count
            } else { collection_capacity(compiler, collection_type) }
            prepare_loop_push_proofs(source, tokens, files, tables, compiler, node, frame.child2, frame.scope, iterations, file_index, frame.loop_depth + 1L)
            compiler.work[frame_index] = frame
            push_check_frame(env, files, compiler, CheckFrame {
                node: frame.child2,
                scope: view_scope,
                expected: TY_UNIT,
                function_id,
                loop_depth: frame.loop_depth + 1L,
                is_test,
                phase: 0L,
                cursor: -1L,
                child0: -1L,
                child1: -1L,
                child2: -1L,
                result_ty: -1L,
                auxiliary: 1L,
                reachable: true,
            })
            continue
        }
        if kind == NodeKind.ForEach && frame.phase == 81L {
            finish_loop_push_proofs(compiler, node)
            let view_binding = binding_for_node(compiler, node)
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: view_binding, function: -1L, literal: compiler.facts[frame.child0].ty }
            match compiler.work.pop() { some(_) => (), none() => () }
            continue
        }
        if frame.phase == 1L {
            var child = -1L
            var child_scope = frame.scope
            var child_loop_depth = frame.loop_depth
            var child_index = -1L
            if kind == NodeKind.Block || kind == NodeKind.Call || kind == NodeKind.QualifiedCase || kind == NodeKind.MethodCall || kind == NodeKind.OptionalCall || kind == NodeKind.Index || kind == NodeKind.ArrayLiteral {
                child = frame.cursor
                if child >= 0L { frame.cursor = compiler.child_next[child] }
                child_index = 0L
                if kind == NodeKind.Call || kind == NodeKind.QualifiedCase || kind == NodeKind.MethodCall || kind == NodeKind.OptionalCall {
                    var sibling = compiler.child_first[node]
                    var position = 0L
                    for item_count in 0L..tables.nodes[node].subtree {
                        if sibling < 0L || sibling == child { break }
                        position += 1L
                        sibling = compiler.child_next[sibling]
                    }
                    child_index = position - if kind == NodeKind.MethodCall || kind == NodeKind.OptionalCall { 1L } else { 0L }
                }
            } else if kind == NodeKind.Field {
                child = frame.cursor
                frame.cursor = -1L
            } else if kind == NodeKind.StructInit {
                let initializer = frame.cursor
                if initializer >= 0L {
                    let type_index = struct_type_index(compiler, frame.result_ty)
                    let field_index = struct_field_matches(compiler, type_index, compiler.token_name_ids[tables.nodes[initializer].token])
                    if field_index < 0L {
                        fail_unknown_struct_field(env, source, files, tokens, tables, compiler, file_index, tables.nodes[initializer].start, type_index, tables.nodes[initializer].token, true)
                    }
                    var previous = compiler.child_first[node]
                    for previous_step in 0L..tables.nodes[node].subtree {
                        if previous < 0L || previous == initializer { break }
                        if compiler.facts[previous].binding == field_index {
                            let first_position = position_for_offset(file_index, files[file_index].base + tables.nodes[previous].start, compiler)
                            let current_position = position_for_offset(file_index, files[file_index].base + tables.nodes[initializer].start, compiler)
                            match env.err.write(files[file_index].name) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(str(current_position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(str(current_position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b": error: field '") { ok(_) => (), err(_) => env.exit(3) }
                            match write_token_raw(env.err, source, tokens, files[file_index].base, tables.nodes[initializer].token) { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(b"' is supplied more than once (first on line ") { ok(_) => (), err(_) => env.exit(3) }
                            match env.err.write(str(first_position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b")") { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(compiler.default_context) { ok(_) => (), err(_) => env.exit(3) }
            match env.err.write(b"\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
                        }
                        previous = compiler.child_next[previous]
                    }
                    compiler.facts[initializer] = NodeFact { ty: compiler.struct_fields[field_index].ty, flags: FACT_FALLS_THROUGH, binding: field_index, function: -1L, literal: 0L }
                    frame.auxiliary = compiler.struct_fields[field_index].ty
                    child = compiler.child_first[initializer]
                    frame.cursor = compiler.child_next[initializer]
                }
            } else if kind == NodeKind.Let {
                child = frame.cursor
                frame.cursor = -1L
            } else if kind == NodeKind.Assign {
                if frame.cursor == 0L { child = frame.child0; frame.cursor = 1L }
                else if frame.cursor == 1L {
                    frame.result_ty = if frame.child0 >= 0L { compiler.facts[frame.child0].ty } else { -1L }
                    child = frame.child1
                    frame.cursor = 2L
                }
                else { () }
            } else if kind == NodeKind.Return || kind == NodeKind.ReturnStatement || kind == NodeKind.ExpressionStatement || kind == NodeKind.Discard || kind == NodeKind.Spawn || kind == NodeKind.Expect || kind == NodeKind.Unary || kind == NodeKind.Cast || kind == NodeKind.Fit || kind == NodeKind.ToLong || kind == NodeKind.Try {
                child = frame.cursor
                frame.cursor = -1L
            } else if kind == NodeKind.Binary {
                if frame.cursor < 2L {
                    let order = if frame.auxiliary == 1L { 1L - frame.cursor } else { frame.cursor }
                    child = if order == 0L { frame.child0 } else { frame.child1 }
                    frame.cursor += 1L
                    child_index = order
                }
            } else if kind == NodeKind.If {
                if frame.cursor < 3L {
                    if frame.cursor == 0L { child = frame.child0 }
                    else if frame.cursor == 1L { child = frame.child1 }
                    else { child = frame.child2 }
                    child_index = frame.cursor
                    frame.cursor += 1L
                } else { () }
            } else if kind == NodeKind.For {
                if frame.cursor < 3L {
                    if frame.cursor == 0L { child = frame.child0 }
                    else if frame.cursor == 1L { child = frame.child1 }
                    else {
                        child = frame.child2
                        child_scope = frame.auxiliary
                        child_loop_depth += 1L
                        let inclusive = (tables.nodes[node].flags & FLAG_INCLUSIVE) != 0L
                        let iterations = loop_iteration_count(tables, compiler, frame.child0, frame.child1, inclusive)
                        prepare_loop_push_proofs(source, tokens, files, tables, compiler, node, child, frame.scope, iterations, file_index, frame.loop_depth + 1L)
                    }
                    child_index = frame.cursor
                    frame.cursor += 1L
                } else { () }
            } else if kind == NodeKind.While {
                if frame.cursor < 2L {
                    child = if frame.cursor == 0L { frame.child0 } else { frame.child1 }
                    child_index = frame.cursor
                    if frame.cursor == 1L { child_loop_depth += 1L }
                    frame.cursor += 1L
                } else { () }
            } else {
                ()
            }
            compiler.work[frame_index] = frame
            if child >= 0L {
                let expected = body_child_expected(source, tokens, files, tables, compiler, node, child, frame, child_index, file_index, config)
                push_check_frame(env, files, compiler, CheckFrame {
                    node: child,
                    scope: child_scope,
                    expected,
                    function_id,
                    loop_depth: child_loop_depth,
                    is_test,
                    phase: 0L,
                    cursor: -1L,
                    child0: -1L,
                    child1: -1L,
                    child2: -1L,
                    result_ty: -1L,
                    auxiliary: 0L,
                    reachable: true,
                })
            } else {
                frame.phase = 2L
                compiler.work[frame_index] = frame
            }
            continue
        }
        if kind == NodeKind.Let {
            let value = frame.child0
            let value_fact = compiler.facts[value]
            if type_kind(compiler, value_fact.ty) == TYPE_KIND_POOL && tables.nodes[value].kind != NodeKind.PoolLiteral {
                report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node: value, offset: tables.nodes[value].start, category: UNSUPPORTED_POOL_USE, token: tables.nodes[value].token })
            }
            if is_bytes_view_value(tables, compiler, value) {
                fail_at_message(env, files, compiler, file_index, tables.nodes[value].start,
                    "a .bytes() view is temporary and cannot be stored or returned; index and count the Ascii or Bytes itself (name[i], name.len()) or call .bytes() where it is used")
            }
            if value_fact.ty == TY_NEVER {
                fail_at_message(env, files, compiler, file_index, tables.nodes[value].start, "a binding needs a value; functions and if expressions used here must return int, long, or bool")
            }
            let ty = if frame.child1 >= 0L { frame.child1 } else { value_fact.ty }
            require_type(env, files, compiler, file_index, value, ty, value_fact.ty, tables)
            let binding = add_local_binding(env, source, files, tokens, tables, compiler, file_index, node, syntax.token, frame.scope, ty, (syntax.flags & FLAG_MUTABLE) != 0L, false, false)
            if collection_kind_is_list(type_kind(compiler, ty)) {
                if tables.nodes[value].kind == NodeKind.ListLiteral || (tables.nodes[value].kind == NodeKind.Call && (tables.nodes[value].flags & FLAG_SYNTHETIC) != 0L) {
                    set_binding_collection_count(compiler, binding, 0L)
                } else { () }
            } else if deferred_text_kind(type_kind(compiler, ty)) {
                let byte_length = known_text_byte_length(source, tokens, files, tables, compiler, file_index, value, 0L)
                set_binding_collection_count(compiler, binding, byte_length)
            } else { () }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: if (value_fact.flags & FACT_FALLS_THROUGH) != 0L { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding, function: -1L, literal: 0L }
        } else if kind == NodeKind.ArrayLiteral {
            let ty = frame.result_ty
            let flags = if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }
            compiler.facts[node] = NodeFact { ty, flags, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Index {
            let receiver = frame.child0
            let index = frame.child1
            let collection_ty = if receiver >= 0L { compiler.facts[receiver].ty } else { -1L }
            let collection_kind = type_kind(compiler, collection_ty)
            if collection_kind == TYPE_KIND_QUEUE {
                report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node, offset: syntax.start, category: UNSUPPORTED_QUEUE_USE, token: syntax.token })
            }
            if collection_kind != TYPE_KIND_ARRAY && collection_kind != TYPE_KIND_LIST && collection_kind != TYPE_KIND_BYTES && collection_kind != TYPE_KIND_ASCII {
                fail_at_message(env, files, compiler, file_index, syntax.start, "this value cannot be indexed; use an array, list, Bytes, or Ascii")
            }
            let index_ty = if index >= 0L { compiler.facts[index].ty } else { -1L }
            if index_ty != TY_LONG {
                if index_ty == TY_INT { fail_at_message(env, files, compiler, file_index, tables.nodes[index].start, "collection indexes are long; cast an int index with .to_long()") }
                else { fail_at_message(env, files, compiler, file_index, tables.nodes[index].start, "collection indexes must be long") }
            }
            let element_ty = if collection_kind == TYPE_KIND_BYTES || collection_kind == TYPE_KIND_ASCII { TY_BYTE } else { collection_element_type(compiler, collection_ty) }
            if frame.expected >= 0L && frame.expected != element_ty { require_type(env, files, compiler, file_index, node, frame.expected, element_ty, tables) }
            let flags = if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }
            compiler.facts[node] = NodeFact { ty: element_ty, flags, binding: compiler.facts[receiver].binding, function: -1L, literal: collection_ty }
        } else if kind == NodeKind.Field {
            let receiver = frame.child0
            let receiver_ty = compiler.facts[receiver].ty
            let environment_field = if receiver_ty == TY_ENV {
                c_runtime_environment_field_kind(source, tokens, files, compiler, file_index, syntax.token)
            } else { 0L }
            if receiver_ty == TY_ENV {
                let field_ty = c_runtime_environment_field_type(environment_field)
                if field_ty < 0L {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "Env has no field with this name")
                }
                if frame.expected >= 0L && frame.expected != field_ty { require_type(env, files, compiler, file_index, node, frame.expected, field_ty, tables) }
                compiler.facts[node] = NodeFact { ty: field_ty, flags: FACT_FALLS_THROUGH, binding: compiler.facts[receiver].binding, function: -1L, literal: environment_field }
            } else if !is_aggregate_type(compiler, receiver_ty) {
                let message: Ascii max 160 = "value has no fields; cannot read this field"
                fail_at_message(env, files, compiler, file_index, syntax.anchor, message)
            } else {
                let type_index = struct_type_index(compiler, receiver_ty)
                let field_index = struct_field_matches(compiler, type_index, compiler.token_name_ids[syntax.token])
                if field_index < 0L {
                    fail_unknown_struct_field(env, source, files, tokens, tables, compiler, file_index, syntax.anchor, type_index, syntax.token, false)
                }
                let field_ty = compiler.struct_fields[field_index].ty
                if frame.expected >= 0L && frame.expected != field_ty { require_type(env, files, compiler, file_index, node, frame.expected, field_ty, tables) }
                compiler.facts[node] = NodeFact { ty: field_ty, flags: FACT_FALLS_THROUGH, binding: compiler.facts[receiver].binding, function: -1L, literal: field_index }
            }
        } else if kind == NodeKind.StructInit {
            let type_index = struct_type_index(compiler, frame.result_ty)
            let ty = struct_record(compiler, type_index)
            var values_fall_through = true
            var supplied_value = compiler.child_first[node]
            for value_step in 0L..syntax.subtree {
                if supplied_value < 0L { break }
                let field_value = compiler.child_first[supplied_value]
                if field_value >= 0L && (compiler.facts[field_value].flags & FACT_FALLS_THROUGH) == 0L { values_fall_through = false }
                supplied_value = compiler.child_next[supplied_value]
            }
            for offset in 0L..ty.field_count {
                let field_index = ty.field_start + offset
                var supplied = false
                var initializer = compiler.child_first[node]
                for field_step in 0L..tables.nodes[node].subtree {
                    if initializer < 0L { break }
                    if compiler.facts[initializer].binding == field_index { supplied = true }
                    initializer = compiler.child_next[initializer]
                }
                if !supplied && compiler.struct_fields[field_index].default_node < 0L {
                    fail_missing_struct_field(env, source, files, tokens, tables, compiler, file_index, syntax.start, type_index, field_index)
                }
            }
            if frame.expected >= 0L && frame.expected != frame.result_ty { require_type(env, files, compiler, file_index, node, frame.expected, frame.result_ty, tables) }
            compiler.facts[node] = NodeFact { ty: frame.result_ty, flags: if values_fall_through { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: type_index }
        } else if kind == NodeKind.Assign {
            let target = frame.child0
            let value = frame.child1
            if target < 0L || (tables.nodes[target].kind != NodeKind.Name && tables.nodes[target].kind != NodeKind.Field && tables.nodes[target].kind != NodeKind.Index) { fail_at_message(env, files, compiler, file_index, syntax.start, "assignment target must be a local name, field path, or collection element") }
            let target_fact = compiler.facts[target]
            let binding = target_fact.binding
            if type_kind(compiler, target_fact.ty) == TYPE_KIND_POOL {
                report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node: target, offset: tables.nodes[target].start, category: UNSUPPORTED_POOL_USE, token: tables.nodes[target].token })
            }
            if binding < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "assignment target must be a writable local, field, or collection element") }
            if !compiler.bindings[binding].mutable { fail_assignment_error(env, source, files, tokens, tables, compiler, file_index, node, binding) }
            // A text field cannot be replaced through a loop view (stage 0 refuses it too); scalar fields can.
            let text_through_view = tables.nodes[target].kind == NodeKind.Field && binding_is_view(compiler, binding) && collection_text_leaf(type_kind(compiler, target_fact.ty))
            if text_through_view || active_view_overlaps_place(tables, compiler, frame.scope, target) {
                fail_at_message(env, files, compiler, file_index, tables.nodes[target].start, "cannot replace or modify storage that contains a live collection view")
            }
            let op = syntax.flags
            let value_fact = compiler.facts[value]
            if is_ascii_append_assignment(op, target_fact.ty, compiler) {
                require_type(env, files, compiler, file_index, value, target_fact.ty, value_fact.ty, tables)
                if binding_is_write_parameter(compiler, binding) && !binding_is_grow_parameter(compiler, binding) {
                    fail_at_message(env, files, compiler, file_index, syntax.start,
                        "appending through a parameter requires 'grow' mode; 'write' cannot increase its length")
                }
                let maximum = text_max_bytes(compiler, target_fact.ty)
                let tracked_length = if binding >= 0L && binding < compiler.bindings.count() &&
                    compiler.bindings[binding].ty == target_fact.ty {
                    compiler.bindings[binding].collection_count
                } else { -1L }
                let current_maximum = if tracked_length >= 0L { tracked_length } else { maximum }
                let appended_length = known_text_byte_length(source, tokens, files, tables, compiler, file_index, value, 0L)
                let appended_maximum = if appended_length >= 0L { appended_length } else { text_max_bytes(compiler, value_fact.ty) }
                let loop_proven = frame.loop_depth == 0L || appended_maximum == 0L ||
                    loop_push_is_proven(compiler, binding, frame.loop_depth)
                if maximum < 0L || current_maximum > maximum || appended_maximum < 0L ||
                    appended_maximum > maximum - current_maximum || !loop_proven {
                    let conditional_loop = conditional_builder_loop_ancestor(tables, node)
                    if !loop_proven && conditional_loop >= 0L {
                        report_typed_unsupported(env, source, files, tokens, tables, compiler,
                            file_index, conditional_loop, UNSUPPORTED_CONDITIONAL_BUILDER_LOOP)
                    }
                    fail_ascii_append_unproven(env, source, files, tokens, tables, compiler, file_index, node, target, maximum)
                }
                if binding >= 0L && binding < compiler.bindings.count() && compiler.bindings[binding].ty == target_fact.ty {
                    if tracked_length >= 0L && appended_length >= 0L {
                        set_binding_collection_count(compiler, binding, tracked_length + appended_length)
                    } else { set_binding_collection_count(compiler, binding, -1L) }
                }
            } else { () }
            if is_bytes_view_value(tables, compiler, value) {
                fail_at_message(env, files, compiler, file_index, tables.nodes[value].start,
                    "a .bytes() view is temporary and cannot be stored or returned; index and count the Ascii or Bytes itself (name[i], name.len()) or call .bytes() where it is used")
            }
            if op == 0L {
                require_type(env, files, compiler, file_index, value, target_fact.ty, value_fact.ty, tables)
                if deferred_text_kind(type_kind(compiler, target_fact.ty)) &&
                    binding >= 0L && binding < compiler.bindings.count() && compiler.bindings[binding].ty == target_fact.ty {
                    set_binding_collection_count(compiler, binding,
                        known_text_byte_length(source, tokens, files, tables, compiler, file_index, value, 0L))
                }
            } else if is_ascii_append_assignment(op, target_fact.ty, compiler) { () }
            else {
                if target_fact.ty == TY_DOUBLE && op > 4L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "double supports += -= *= /= only") }
                if !is_numeric_type(target_fact.ty) && target_fact.ty != TY_DOUBLE { fail_at_message(env, files, compiler, file_index, syntax.anchor, "compound assignment requires int, long or double") }
                require_type(env, files, compiler, file_index, value, target_fact.ty, value_fact.ty, tables)
            }
            if collection_kind_is_list(type_kind(compiler, target_fact.ty)) && binding < compiler.bindings.count() {
                set_binding_collection_count(compiler, binding, -1L)
            } else if deferred_text_kind(type_kind(compiler, target_fact.ty)) && op != 0L && !is_ascii_append_assignment(op, target_fact.ty, compiler) && binding < compiler.bindings.count() {
                set_binding_collection_count(compiler, binding, -1L)
            } else { () }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding, function: -1L, literal: 0L }
        } else if kind == NodeKind.Return || kind == NodeKind.ReturnStatement {
            if is_test { fail_at_message(env, files, compiler, file_index, syntax.start, "a test cannot return; let the test finish so all expectations run") }
            if frame.child0 < 0L {
                if result_ty != TY_UNIT { fail_no_return_value(env, source, files, tokens, compiler, file_index, syntax.start, result_ty, compiler.functions[function_id]) }
                else { compiler.facts[node] = NodeFact { ty: TY_NEVER, flags: FACT_NEVER, binding: -1L, function: -1L, literal: 0L } }
            } else {
                if is_bytes_view_value(tables, compiler, frame.child0) {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start,
                        "a .bytes() view is temporary and cannot be stored or returned; index and count the Ascii or Bytes itself (name[i], name.len()) or call .bytes() where it is used")
                }
                let actual = compiler.facts[frame.child0].ty
                require_type(env, files, compiler, file_index, frame.child0, result_ty, actual, tables)
                compiler.facts[node] = NodeFact { ty: TY_NEVER, flags: FACT_NEVER, binding: -1L, function: -1L, literal: 0L }
            }
        } else if kind == NodeKind.Spawn {
            let call = frame.child0
            if call < 0L || tables.nodes[call].kind != NodeKind.Call || compiler.facts[call].function < 0L {
                fail_at_message(env, files, compiler, file_index, syntax.start, "spawn starts a call of one of your functions: spawn worker(arguments)")
            }
            let target = compiler.functions[compiler.facts[call].function]
            if target.result_ty != TY_UNIT {
                fail_at_message(env, files, compiler, file_index, syntax.start, "a spawned function returns nothing")
            }
            for parameter_index in 0L..target.param_count {
                let parameter = compiler.parameters[target.param_start + parameter_index]
                let numeric = parameter.ty == TY_INT || parameter.ty == TY_LONG || parameter.ty == TY_BOOL || parameter.ty == TY_BYTE || parameter.ty == TY_DOUBLE
                let handle = mailbox_role_of_type(compiler, parameter.ty) != 0L || parameter.ty == TY_ENV ||
                    (type_kind(compiler, parameter.ty) == TYPE_KIND_STRUCT && job_copyable_type(compiler, parameter.ty))
                if (!numeric && !handle) || (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[call].start, "a spawned function takes numbers, bools, the env, mailbox handles and structs of plain data (no pools or maps inside)")
                }
            }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: compiler.facts[call].function, literal: 0L }
        } else if kind == NodeKind.Discard {
            let value = frame.child0
            // discard drops a number, a bool or other plain value outright, and the built-in operations whose only error is Full
            // (collection adds, try_append, a mailbox send); it never drops an arbitrary Result or Option
            let dropped_kind = if value >= 0L { type_kind(compiler, compiler.facts[value].ty) } else { TYPE_KIND_RESULT }
            let plain_value = value >= 0L && dropped_kind != TYPE_KIND_RESULT && dropped_kind != TYPE_KIND_OPTION
            if value < 0L || (!plain_value && (tables.nodes[value].kind != NodeKind.MethodCall ||
                (compiler.facts[value].literal != COLLECTION_METHOD_PUSH && compiler.facts[value].literal != COLLECTION_METHOD_INSERT &&
                    compiler.facts[value].literal != TEXT_METHOD_TRY_APPEND && compiler.facts[value].literal != TEXT_METHOD_PUSH &&
                    compiler.facts[value].literal != COLLECTION_METHOD_POOL_ADD && compiler.facts[value].literal != MAILBOX_METHOD_SEND))) {
                fail_at_message(env, files, compiler, file_index, syntax.start, "discard drops a plain value or a built-in operation whose only error is Full (a collection add, try_append, a mailbox send), not an arbitrary Result or Option")
            }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: if (compiler.facts[value].flags & FACT_FALLS_THROUGH) != 0L { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.ExpressionStatement {
            let ty = if frame.child0 >= 0L { compiler.facts[frame.child0].ty } else { TY_UNIT }
            let proven_success = frame.child0 >= 0L && (compiler.facts[frame.child0].flags & FACT_PROVEN_SUCCESS) != 0L
            if type_kind(compiler, ty) == TYPE_KIND_RESULT && !proven_success {
                let operation = if frame.child0 >= 0L { compiler.facts[frame.child0].literal } else { 0L }
                let is_collection_capacity_result = frame.child0 >= 0L && tables.nodes[frame.child0].kind == NodeKind.MethodCall &&
                    (operation == COLLECTION_METHOD_PUSH || operation == COLLECTION_METHOD_INSERT)
                let is_builder_capacity_result = frame.child0 >= 0L && tables.nodes[frame.child0].kind == NodeKind.MethodCall &&
                    (operation == TEXT_METHOD_TRY_APPEND || operation == TEXT_METHOD_PUSH)
                if frame.child0 >= 0L && tables.nodes[frame.child0].kind == NodeKind.MethodCall && operation == COLLECTION_METHOD_POOL_ADD {
                    report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node: frame.child0, offset: tables.nodes[frame.child0].start, category: UNSUPPORTED_POOL_USE, token: tables.nodes[frame.child0].token })
                }
                let message: Ascii max 160 = if is_collection_capacity_result { "collection Result with error Full is unused; handle it or write 'discard' to drop Full" }
                    else if is_builder_capacity_result { "builder Result with error Full is unused; handle it or write 'discard' to drop Full" }
                    else { "this Result value is unused; handle it with '?', 'match', or '??' where supported" }
                fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start, message)
            }
            compiler.facts[node] = NodeFact { ty: if ty == TY_NEVER { TY_NEVER } else { TY_UNIT }, flags: if ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Expect {
            if !is_test { fail_at_message(env, files, compiler, file_index, syntax.start, "'expect' is only valid inside a test block") }
            let actual = if frame.child0 >= 0L { compiler.facts[frame.child0].ty } else { -1L }
            if actual >= 0L { require_type(env, files, compiler, file_index, frame.child0, TY_BOOL, actual, tables) }
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Call {
            let name_id = compiler.token_name_ids[syntax.token]
            let arg_count = count_children(tables, compiler, node)
            if frame.child2 >= 0L {
                let ty = frame.result_ty
                if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                let case = compiler.enum_cases[frame.child2]
                compiler.facts[node] = NodeFact { ty, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: case.tag }
            } else if frame.auxiliary >= 21L && frame.auxiliary <= 24L {
                let tag = if frame.auxiliary == 21L || frame.auxiliary == 23L { 0L } else { 1L }
                let sum_kind = if frame.auxiliary == 21L || frame.auxiliary == 22L { TYPE_KIND_OPTION } else { TYPE_KIND_RESULT }
                let payload = if frame.auxiliary == 22L { -1L } else { compiler.facts[compiler.child_first[node]].ty }
                let ty = if frame.result_ty >= 0L { frame.result_ty }
                    else { intern_sum_type(compiler, sum_kind, payload, -1L, file_index, node, -1L, -1L) }
                if ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "cannot infer the type of this Option or Result constructor") }
                if type_state(compiler, ty) != 2L { let _ = layout_sum_instance(compiler, ty) }
                if sum_layout_has_invalid_overflow(compiler, ty) { fail_at_message(env, files, compiler, file_index, syntax.start, "Option or Result value layout is too large") }
                if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
                compiler.facts[node] = NodeFact { ty, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: tag }
            } else if is_builtin_fill_call(source, tokens, files, compiler, file_index, syntax.token, frame.scope) {
                if arg_count != 1L { fail_at_message(env, files, compiler, file_index, syntax.start, "fill takes one value, but got an invalid number") }
                if frame.expected < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "fill needs an expected array type; add a T[N] annotation") }
                if type_kind(compiler, frame.expected) != TYPE_KIND_ARRAY { fail_at_message(env, files, compiler, file_index, syntax.start, "fill constructs a fixed array; add an array type annotation") }
                let argument = compiler.child_first[node]
                let element_type = collection_element_type(compiler, frame.expected)
                require_type(env, files, compiler, file_index, argument, element_type, compiler.facts[argument].ty, tables)
                compiler.facts[node] = NodeFact { ty: frame.expected, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: 0L }
            } else if token_is_word_at(source, tokens, files, file_index, syntax.token, "print") {
                if (config.capability_mask & 2L) == 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "package manifest must grant capability 'out' in the 'capabilities' key") }
                if arg_count != 1L { fail_at_message(env, files, compiler, file_index, syntax.start, "print takes one argument, but got an invalid number; call print(value)") }
                let argument = child_at(tables, compiler, node, 0L)
                let arg_ty = compiler.facts[argument].ty
                if !is_numeric_type(arg_ty) && arg_ty != TY_BOOL && arg_ty != TY_BYTE && !is_aggregate_type(compiler, arg_ty) {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "print supports int, long, bool, Ascii, enum, struct, array, list, queue, ring, grid, map, set, pool, and function values")
                }
                compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: 0L }
            } else if sort_builtin_kind(source, tokens, files, compiler, file_index, syntax.token, frame.scope) != SORT_NONE {
                let sort_kind = sort_builtin_kind(source, tokens, files, compiler, file_index, syntax.token, frame.scope)
                let comparator = check_sort_builtin(env, source, tokens, files, tables, compiler, file_index, node, frame.scope, sort_kind)
                if frame.expected >= 0L && frame.expected != TY_UNIT { require_type(env, files, compiler, file_index, node, frame.expected, TY_UNIT, tables) }
                if comparator >= 0L && function_id >= 0L {
                    let sort_edge = compiler.call_edges.count()
                    let sort_next = compiler.edge_first[function_id]
                    compiler.call_edges.push(CallEdge { from: function_id, to: comparator, node, next: sort_next }).unwrap()
                    compiler.edge_first[function_id] = sort_edge
                }
                compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: (if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }) | FACT_SORT_BUILTIN, binding: -1L, function: -1L, literal: comparator }
            } else if numeric_builtin_kind(source, tokens, files, compiler, file_index, syntax.token, frame.scope) != NUMERIC_BUILTIN_NONE {
                let builtin_kind = numeric_builtin_kind(source, tokens, files, compiler, file_index, syntax.token, frame.scope)
                let required_args = if builtin_kind == NUMERIC_BUILTIN_ABS { 1L } else if builtin_kind == NUMERIC_BUILTIN_CLAMP { 3L } else { 2L }
                if arg_count != required_args {
                    let shape: Ascii max 160 = if builtin_kind == NUMERIC_BUILTIN_ABS { " takes one int or long value" }
                        else if builtin_kind == NUMERIC_BUILTIN_CLAMP { " takes a value, a lower bound and an upper bound" }
                        else { " takes two values" }
                    fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start, "", syntax.token, shape)
                }
                let first_argument = child_at(tables, compiler, node, 0L)
                let ty = compiler.facts[first_argument].ty
                if ty != TY_INT && ty != TY_LONG {
                    fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, tables.nodes[first_argument].start, "", syntax.token, " needs int or long values")
                }
                for argument_index in 1L..required_args {
                    let argument = child_at(tables, compiler, node, argument_index)
                    if compiler.facts[argument].ty != ty { require_type(env, files, compiler, file_index, argument, ty, compiler.facts[argument].ty, tables) }
                }
                if builtin_kind == NUMERIC_BUILTIN_CLAMP {
                    let lower_operand = child_at(tables, compiler, node, 1L)
                    let upper_operand = child_at(tables, compiler, node, 2L)
                    let lower_known = tables.nodes[lower_operand].kind == NodeKind.Integer || (compiler.facts[lower_operand].flags & FACT_CONSTANT_VALUE) != 0L
                    let upper_known = tables.nodes[upper_operand].kind == NodeKind.Integer || (compiler.facts[upper_operand].flags & FACT_CONSTANT_VALUE) != 0L
                    if lower_known && upper_known && compiler.facts[lower_operand].literal > compiler.facts[upper_operand].literal {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "clamp lower bound is greater than its upper bound")
                    }
                }
                // stage 0 infers the range of clamp(v, lo, hi) from literal bounds, so a clamp with bounds inside
                // 0..255 fits a byte; the result is computed as an int and narrowed.
                var builtin_result_ty = ty
                var recorded_kind = builtin_kind
                if builtin_kind == NUMERIC_BUILTIN_CLAMP && frame.expected == TY_BYTE && ty == TY_INT {
                    let lower_bound = child_at(tables, compiler, node, 1L)
                    let upper_bound = child_at(tables, compiler, node, 2L)
                    if tables.nodes[lower_bound].kind == NodeKind.Integer && tables.nodes[upper_bound].kind == NodeKind.Integer &&
                        compiler.facts[lower_bound].literal >= 0L && compiler.facts[upper_bound].literal <= 255L {
                        builtin_result_ty = TY_BYTE
                        recorded_kind = builtin_kind + NUMERIC_BUILTIN_NARROW_TO_BYTE
                    }
                }
                if frame.expected >= 0L && frame.expected != builtin_result_ty { require_type(env, files, compiler, file_index, node, frame.expected, builtin_result_ty, tables) }
                let builtin_flags = if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }
                compiler.facts[node] = NodeFact { ty: builtin_result_ty, flags: builtin_flags | FACT_NUMERIC_BUILTIN, binding: -1L, function: -1L, literal: recorded_kind }
            } else if format_text_builtin_kind(source, tokens, files, tables, compiler, file_index, node) != FORMAT_TEXT_NONE {
                let format_kind = format_text_builtin_kind(source, tokens, files, tables, compiler, file_index, node)
                let ty = check_format_text_builtin(env, source, tokens, files, tables, compiler, file_index, node, frame.expected)
                let flags = if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }
                compiler.facts[node] = NodeFact { ty, flags: flags | FACT_FORMAT_TEXT, binding: -1L, function: -1L, literal: format_kind }
            } else {
                let target = find_function_by_name(compiler, name_id)
                if target < 0L {
                    let local = find_binding_in_scope(compiler, frame.scope, name_id)
                    if local >= 0L {
                        let local_ty = compiler.bindings[local].ty
                        if local_ty == TY_INT || local_ty == TY_LONG || local_ty == TY_BOOL || local_ty == TY_BYTE {
                            let typed_suffix: Ascii max 160 = if local_ty == TY_INT { "' has type int and cannot be called; use a function-typed value" }
                                else if local_ty == TY_LONG { "' has type long and cannot be called; use a function-typed value" }
                                else if local_ty == TY_BOOL { "' has type bool and cannot be called; use a function-typed value" }
                                else { "' has type byte and cannot be called; use a function-typed value" }
                            fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start, "value '", syntax.token, typed_suffix)
                        } else {
                            fail_dynamic_checker_error(env, source, files, tokens, compiler, file_index, syntax.start, "value '", syntax.token, "' is not callable; use a function-typed value")
                        }
                    }
                    fail_name_error(env, source, files, tokens, compiler, file_index, syntax.start, syntax.token, frame.scope, true)
                }
                let function = compiler.functions[target]
                check_call_count(env, source, files, tokens, tables, compiler, function, node, file_index)
                check_call_write_modes(env, source, files, tokens, tables, compiler, function, node, file_index, frame.scope)
                var read_text_argument = compiler.child_first[node]
                for argument_index in 0L..function.param_count {
                    if read_text_argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "call is missing an argument") }
                    let parameter = compiler.parameters[function.param_start + argument_index]
                    if parameter_uses_text_read_view(compiler, parameter) {
                        require_text_read_argument(env, files, compiler, file_index, read_text_argument,
                            parameter.ty, compiler.facts[read_text_argument].ty, tables)
                    }
                    read_text_argument = compiler.child_next[read_text_argument]
                }
                invalidate_collection_counts_for_write_call(compiler, function, node)
                if function_id >= 0L {
                    let edge_id = compiler.call_edges.count()
                    let next_edge = compiler.edge_first[function_id]
                    compiler.call_edges.push(CallEdge { from: function_id, to: target, node, next: next_edge }).unwrap()
                    compiler.edge_first[function_id] = edge_id
                }
                let ty = function.result_ty
                compiler.facts[node] = NodeFact { ty, flags: if ty == TY_NEVER || !node_children_fall_through(tables, compiler, node) { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: target, literal: 0L }
            }
        } else if kind == NodeKind.OptionalCall {
            let receiver = frame.child0
            let receiver_ty = if receiver >= 0L { compiler.facts[receiver].ty } else { -1L }
            let receiver_kind = type_kind(compiler, receiver_ty)
            if receiver_kind == TYPE_KIND_RESULT {
                fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional chaining requires Option; convert a Result with .ok() first")
            }
            if receiver_kind != TYPE_KIND_OPTION {
                fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional chaining requires an Option<T> receiver")
            }
            let inner_ty = sum_case_payload_type(compiler, receiver_ty, 0L, 0L)
            let argument_count = count_children(tables, compiler, node) - 1L
            let method_is_to_long = token_is_word_at(source, tokens, files, file_index, syntax.token, "to_long")
            var optional_result_ty = -1L
            if method_is_to_long {
                if argument_count != 0L || inner_ty != TY_INT {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional method 'to_long()' takes no arguments and requires Option<int>")
                }
                optional_result_ty = intern_sum_type(compiler, TYPE_KIND_OPTION, TY_LONG, -1L, file_index, node, -1L, -1L)
            } else {
                let target = find_function_by_name(compiler, compiler.token_name_ids[syntax.token])
                if target < 0L { fail_name_error(env, source, files, tokens, compiler, file_index, syntax.anchor, syntax.token, frame.scope, true) }
                let function = compiler.functions[target]
                if function.param_count != argument_count + 1L {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional call has the wrong number of arguments")
                }
                let receiver_parameter = compiler.parameters[function.param_start]
                if (parameter_mode(receiver_parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional chaining cannot call a function whose receiver parameter is write")
                }
                if parameter_uses_text_read_view(compiler, receiver_parameter) {
                    require_text_read_argument(env, files, compiler, file_index, receiver,
                        receiver_parameter.ty, inner_ty, tables)
                } else {
                    require_type(env, files, compiler, file_index, receiver, receiver_parameter.ty, inner_ty, tables)
                }
                var argument = compiler.child_next[receiver]
                for argument_index in 1L..function.param_count {
                    let parameter = compiler.parameters[function.param_start + argument_index]
                    if argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "optional call is missing an argument") }
                    if (parameter_mode(parameter) & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L {
                        fail_at_message(env, files, compiler, file_index, syntax.anchor, "optional calls cannot pass a write parameter; call a function directly with an assignable place")
                    }
                    if parameter_uses_text_read_view(compiler, parameter) {
                        require_text_read_argument(env, files, compiler, file_index, argument,
                            parameter.ty, compiler.facts[argument].ty, tables)
                    } else {
                        require_type(env, files, compiler, file_index, argument, parameter.ty, compiler.facts[argument].ty, tables)
                    }
                    argument = compiler.child_next[argument]
                }
                optional_result_ty = if type_kind(compiler, function.result_ty) == TYPE_KIND_OPTION { function.result_ty }
                    else { intern_sum_type(compiler, TYPE_KIND_OPTION, function.result_ty, -1L, file_index, node, -1L, -1L) }
                if sum_layout_has_invalid_overflow(compiler, optional_result_ty) {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "optional call result has an invalid Option layout")
                }
                if frame.function_id >= 0L {
                    let edge_id = compiler.call_edges.count()
                    let next_edge = compiler.edge_first[frame.function_id]
                    compiler.call_edges.push(CallEdge { from: frame.function_id, to: target, node, next: next_edge }).unwrap()
                    compiler.edge_first[frame.function_id] = edge_id
                }
                compiler.facts[node] = NodeFact { ty: optional_result_ty, flags: if (compiler.facts[receiver].flags & FACT_FALLS_THROUGH) != 0L { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: target, literal: 0L }
            }
            if frame.expected >= 0L && frame.expected != optional_result_ty { require_type(env, files, compiler, file_index, node, frame.expected, optional_result_ty, tables) }
            if method_is_to_long || optional_result_ty >= 0L {
                compiler.facts[node] = NodeFact { ty: optional_result_ty, flags: if (compiler.facts[receiver].flags & FACT_FALLS_THROUGH) != 0L { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: if method_is_to_long { -1L } else { compiler.facts[node].function }, literal: if method_is_to_long { -2L } else { 0L } }
            }
        } else if kind == NodeKind.QualifiedCase {
            let ty = frame.result_ty
            if frame.expected >= 0L && frame.expected != ty { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
            let case = compiler.enum_cases[frame.child2]
            compiler.facts[node] = NodeFact { ty, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: case.tag }
        } else if kind == NodeKind.MethodCall && frame.child0 >= 0L &&
            struct_method_target(source, files, tokens, compiler, compiler.facts[frame.child0].ty, syntax.token, file_index) >= 0L {
            // x.m(args) on a user struct: a call of Type_m(x, args)
            let target = struct_method_target(source, files, tokens, compiler, compiler.facts[frame.child0].ty, syntax.token, file_index)
            let function = compiler.functions[target]
            let receiver_node = frame.child0
            check_call_count(env, source, files, tokens, tables, compiler, function, node, file_index)
            check_call_write_modes(env, source, files, tokens, tables, compiler, function, node, file_index, frame.scope)
            let receiver_parameter = compiler.parameters[function.param_start]
            if parameter_uses_text_read_view(compiler, receiver_parameter) {
                require_text_read_argument(env, files, compiler, file_index, receiver_node, receiver_parameter.ty, compiler.facts[receiver_node].ty, tables)
            } else {
                require_type(env, files, compiler, file_index, receiver_node, receiver_parameter.ty, compiler.facts[receiver_node].ty, tables)
            }
            var method_argument = compiler.child_first[node]
            for argument_index in 0L..function.param_count {
                if method_argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "call is missing an argument") }
                let parameter = compiler.parameters[function.param_start + argument_index]
                if parameter_uses_text_read_view(compiler, parameter) {
                    require_text_read_argument(env, files, compiler, file_index, method_argument, parameter.ty, compiler.facts[method_argument].ty, tables)
                }
                method_argument = compiler.child_next[method_argument]
            }
            invalidate_collection_counts_for_write_call(compiler, function, node)
            if function_id >= 0L {
                let edge_id = compiler.call_edges.count()
                let next_edge = compiler.edge_first[function_id]
                compiler.call_edges.push(CallEdge { from: function_id, to: target, node, next: next_edge }).unwrap()
                compiler.edge_first[function_id] = edge_id
            }
            let method_ty = function.result_ty
            if frame.expected >= 0L && frame.expected != method_ty { require_type(env, files, compiler, file_index, node, frame.expected, method_ty, tables) }
            let method_flags = if method_ty == TY_NEVER || !node_children_fall_through(tables, compiler, node) { FACT_NEVER } else { FACT_FALLS_THROUGH }
            compiler.facts[node] = NodeFact { ty: method_ty, flags: method_flags | FACT_STRUCT_METHOD, binding: -1L, function: target, literal: 0L }
        } else if kind == NodeKind.MethodCall {
            let operation = frame.auxiliary
            let receiver = frame.child0
            let receiver_ty = if receiver >= 0L { compiler.facts[receiver].ty } else { -1L }
            let receiver_kind = type_kind(compiler, receiver_ty)
            let c_method = if receiver >= 0L { c_runtime_method_kind(source, tokens, files, compiler, file_index, syntax.token, receiver_ty) } else { C_METHOD_NONE }
            if c_method != C_METHOD_NONE {
                let method_result = c_runtime_check_method(env, source, files, tokens, tables, compiler, file_index, node, frame.scope, receiver_ty, frame.expected)
                compiler.facts[node] = NodeFact { ty: method_result, flags: if method_result == TY_NEVER || !node_children_fall_through(tables, compiler, node) { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: c_method }
            } else if check_parse_number_method(env, source, files, tokens, tables, compiler, file_index, node, frame.expected) {
                ()
            } else if double_method_kind(source, tokens, files, compiler, file_index, syntax.token, receiver_ty) != 0L {
                let double_method = double_method_kind(source, tokens, files, compiler, file_index, syntax.token, receiver_ty)
                if count_children(tables, compiler, node) != 1L { fail_at_message(env, files, compiler, file_index, syntax.start, "this method takes no arguments") }
                let double_result_ty = if double_method == DOUBLE_METHOD_TO_DOUBLE { TY_DOUBLE } else { intern_sum_type(compiler, TYPE_KIND_OPTION, TY_DOUBLE, -1L, file_index, node, -1L, -1L) }
                if frame.expected >= 0L && frame.expected != double_result_ty { require_type(env, files, compiler, file_index, node, frame.expected, double_result_ty, tables) }
                compiler.facts[node] = NodeFact { ty: double_result_ty, flags: (if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }) | FACT_DOUBLE_METHOD, binding: -1L, function: -1L, literal: double_method }
            } else if operation == TEXT_METHOD_EMPTY {
                if count_children(tables, compiler, node) != 1L {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "empty takes no arguments")
                }
                let method_result_ty = frame.result_ty
                if frame.expected >= 0L && frame.expected != method_result_ty {
                    require_type(env, files, compiler, file_index, node, frame.expected, method_result_ty, tables)
                }
                compiler.facts[node] = NodeFact { ty: method_result_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: TEXT_METHOD_EMPTY }
            } else if mailbox_role_of_type(compiler, receiver_ty) != 0L {
                let record = mailbox_record_of_type(compiler, receiver_ty)
                var method = 0L
                if record.role == MAILBOX_ROLE_MAILBOX {
                    if token_is_word_at(source, tokens, files, file_index, syntax.token, "sender") { method = MAILBOX_METHOD_SENDER }
                    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "receiver") { method = MAILBOX_METHOD_RECEIVER }
                    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "close") { method = MAILBOX_METHOD_CLOSE }
                    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "release") { method = MAILBOX_METHOD_RELEASE }
                } else if record.role == MAILBOX_ROLE_SENDER {
                    if token_is_word_at(source, tokens, files, file_index, syntax.token, "send") { method = MAILBOX_METHOD_SEND }
                    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "close") { method = MAILBOX_METHOD_CLOSE }
                    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "is_closed") { method = MAILBOX_METHOD_IS_CLOSED }
                } else {
                    if token_is_word_at(source, tokens, files, file_index, syntax.token, "recv") { method = MAILBOX_METHOD_RECV }
                    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "recv_wait") { method = MAILBOX_METHOD_RECV_WAIT }
                    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "recv_for") { method = MAILBOX_METHOD_RECV_FOR }
                    else if token_is_word_at(source, tokens, files, file_index, syntax.token, "is_closed") { method = MAILBOX_METHOD_IS_CLOSED }
                }
                if method == 0L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "no matching mailbox method is available on this value") }
                let actual_count = count_children(tables, compiler, node) - 1L
                let wanted_count = if method == MAILBOX_METHOD_SEND || method == MAILBOX_METHOD_RECV_FOR { 1L } else { 0L }
                if actual_count != wanted_count { fail_at_message(env, files, compiler, file_index, syntax.start, "mailbox method has the wrong number of arguments") }
                var mailbox_result = TY_UNIT
                if method == MAILBOX_METHOD_SENDER {
                    mailbox_result = intern_mailbox_type(compiler, MAILBOX_ROLE_SENDER, record.element, 0L, file_index)
                } else if method == MAILBOX_METHOD_RECEIVER {
                    mailbox_result = intern_mailbox_type(compiler, MAILBOX_ROLE_RECEIVER, record.element, 0L, file_index)
                } else if method == MAILBOX_METHOD_SEND {
                    let message = compiler.child_next[receiver]
                    require_type(env, files, compiler, file_index, message, record.element, compiler.facts[message].ty, tables)
                    let full_ty = builtin_full_type_id(compiler)
                    if full_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "internal capacity error type is unavailable") }
                    mailbox_result = intern_sum_type(compiler, TYPE_KIND_RESULT, TY_UNIT, full_ty, file_index, node, -1L, -1L)
                } else if method == MAILBOX_METHOD_RECV || method == MAILBOX_METHOD_RECV_WAIT || method == MAILBOX_METHOD_RECV_FOR {
                    if method == MAILBOX_METHOD_RECV_FOR {
                        let wait_ms = compiler.child_next[receiver]
                        require_type(env, files, compiler, file_index, wait_ms, TY_LONG, compiler.facts[wait_ms].ty, tables)
                    }
                    mailbox_result = intern_sum_type(compiler, TYPE_KIND_OPTION, record.element, -1L, file_index, node, -1L, -1L)
                } else if method == MAILBOX_METHOD_IS_CLOSED {
                    mailbox_result = TY_BOOL
                } else { () }
                if frame.expected >= 0L && frame.expected != mailbox_result { require_type(env, files, compiler, file_index, node, frame.expected, mailbox_result, tables) }
                let mailbox_flags = if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }
                compiler.facts[node] = NodeFact { ty: mailbox_result, flags: mailbox_flags, binding: compiler.facts[receiver].binding, function: -1L, literal: method }
            } else if receiver_kind == TYPE_KIND_MAP {
                let method = map_method_kind(source, tokens, files, file_index, syntax.token)
                if method == 0L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "no matching map method is available on this value") }
                let actual_count = count_children(tables, compiler, node) - 1L
                let wanted_count = if method == COLLECTION_METHOD_COUNT { 0L } else if method == COLLECTION_METHOD_MAP_SET { 2L } else { 1L }
                if actual_count != wanted_count { fail_at_message(env, files, compiler, file_index, syntax.start, "map method has the wrong number of arguments") }
                let key_argument = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                var operation_result_type = TY_LONG
                if method != COLLECTION_METHOD_COUNT {
                    require_type(env, files, compiler, file_index, key_argument, map_key_type(compiler, receiver_ty), compiler.facts[key_argument].ty, tables)
                }
                if method == COLLECTION_METHOD_MAP_SET || method == COLLECTION_METHOD_MAP_REMOVE {
                    let receiver_binding = compiler.facts[receiver].binding
                    if receiver_binding < 0L || !compiler.bindings[receiver_binding].mutable { fail_at_message(env, files, compiler, file_index, syntax.start, "map mutation requires a writable local, parameter or field") }
                    if active_view_overlaps_place(tables, compiler, frame.scope, receiver) {
                        fail_view_live_method(env, source, files, tokens, compiler, file_index, syntax.anchor, receiver_ty, syntax.token)
                    }
                }
                if method == COLLECTION_METHOD_MAP_SET {
                    let value_argument = compiler.child_next[key_argument]
                    require_type(env, files, compiler, file_index, value_argument, map_value_type(compiler, receiver_ty), compiler.facts[value_argument].ty, tables)
                    let full_ty = builtin_full_type_id(compiler)
                    if full_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "internal capacity error type is unavailable") }
                    operation_result_type = intern_sum_type(compiler, TYPE_KIND_RESULT, TY_UNIT, full_ty, file_index, node, -1L, -1L)
                } else if method == COLLECTION_METHOD_MAP_GET || method == COLLECTION_METHOD_MAP_REMOVE {
                    operation_result_type = intern_sum_type(compiler, TYPE_KIND_OPTION, map_value_type(compiler, receiver_ty), -1L, file_index, node, -1L, -1L)
                } else if method == COLLECTION_METHOD_MAP_CONTAINS {
                    operation_result_type = TY_BOOL
                } else { () }
                if frame.expected >= 0L && frame.expected != operation_result_type { require_type(env, files, compiler, file_index, node, frame.expected, operation_result_type, tables) }
                let map_fact_flags = if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }
                compiler.facts[node] = NodeFact { ty: operation_result_type, flags: map_fact_flags, binding: compiler.facts[receiver].binding, function: -1L, literal: method }
            } else if receiver_kind == TYPE_KIND_ARRAY || collection_kind_is_list(receiver_kind) {
                let method = collection_method_kind(source, tokens, files, file_index, syntax.token, receiver_kind)
                if method == 0L && receiver_kind == TYPE_KIND_POOL {
                    report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node, offset: syntax.start, category: UNSUPPORTED_POOL_USE, token: syntax.token })
                }
                if method == 0L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "no matching array or list method is available on this value") }
                if receiver_kind == TYPE_KIND_QUEUE && method != COLLECTION_METHOD_COUNT {
                    let queue_element = collection_element_type(compiler, receiver_ty)
                    if queue_element != TY_INT && queue_element != TY_LONG {
                        report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node, offset: syntax.start, category: UNSUPPORTED_QUEUE_ELEMENT, token: syntax.token })
                    }
                }
                let actual_count = count_children(tables, compiler, node) - 1L
                let wanted_count = if method == COLLECTION_METHOD_PUSH || method == COLLECTION_METHOD_REMOVE || method == COLLECTION_METHOD_POOL_ADD || method == COLLECTION_METHOD_POOL_GET { 1L }
                    else if method == COLLECTION_METHOD_INSERT { 2L } else { 0L }
                if actual_count != wanted_count { fail_at_message(env, files, compiler, file_index, syntax.start, "collection method has the wrong number of arguments") }
                var argument = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                var operation_result_type = TY_UNIT
                if method == COLLECTION_METHOD_LEN {
                    operation_result_type = TY_LONG
                } else if method == COLLECTION_METHOD_COUNT {
                    operation_result_type = TY_LONG
                } else if method == COLLECTION_METHOD_REMOVE {
                    if argument < 0L || compiler.facts[argument].ty != TY_LONG { fail_at_message(env, files, compiler, file_index, if argument >= 0L { tables.nodes[argument].start } else { syntax.start }, "collection indexes are long; cast an int index with .to_long()") }
                    if active_view_overlaps_place(tables, compiler, frame.scope, receiver) {
                        fail_view_live_method(env, source, files, tokens, compiler, file_index, syntax.anchor, receiver_ty, syntax.token)
                    }
                    operation_result_type = collection_element_type(compiler, receiver_ty)
                } else if method == COLLECTION_METHOD_POOL_GET {
                    if argument < 0L || compiler.facts[argument].ty != TY_LONG { fail_at_message(env, files, compiler, file_index, if argument >= 0L { tables.nodes[argument].start } else { syntax.start }, "a pool is looked up by id; pass the id that add returned") }
                    operation_result_type = intern_sum_type(compiler, TYPE_KIND_OPTION, collection_element_type(compiler, receiver_ty), -1L, file_index, node, -1L, -1L)
                } else if method == COLLECTION_METHOD_POOL_ADD {
                    let receiver_binding = compiler.facts[receiver].binding
                    if receiver_binding < 0L || !compiler.bindings[receiver_binding].mutable {
                        report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node, offset: syntax.start, category: UNSUPPORTED_POOL_USE, token: syntax.token })
                    }
                    if argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "pool.add is missing its element") }
                    require_type(env, files, compiler, file_index, argument, collection_element_type(compiler, receiver_ty), compiler.facts[argument].ty, tables)
                    let full_ty = builtin_full_type_id(compiler)
                    if full_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "internal capacity error type is unavailable") }
                    operation_result_type = intern_sum_type(compiler, TYPE_KIND_RESULT, TY_LONG, full_ty, file_index, node, -1L, -1L)
                } else if method == COLLECTION_METHOD_PEEK {
                    operation_result_type = intern_sum_type(compiler, TYPE_KIND_OPTION, collection_element_type(compiler, receiver_ty), -1L, file_index, node, -1L, -1L)
                } else if method == COLLECTION_METHOD_POP {
                    let receiver_binding = compiler.facts[receiver].binding
                    if receiver_binding < 0L || !compiler.bindings[receiver_binding].mutable { fail_at_message(env, files, compiler, file_index, syntax.start, "list mutation requires a writable local, parameter, or field place") }
                    if active_view_overlaps_place(tables, compiler, frame.scope, receiver) {
                        fail_view_live_method(env, source, files, tokens, compiler, file_index, syntax.anchor, receiver_ty, syntax.token)
                    }
                    operation_result_type = intern_sum_type(compiler, TYPE_KIND_OPTION, collection_element_type(compiler, receiver_ty), -1L, file_index, node, -1L, -1L)
                } else if method == COLLECTION_METHOD_PUSH || method == COLLECTION_METHOD_INSERT {
                    let receiver_binding = compiler.facts[receiver].binding
                    if receiver_binding < 0L || !compiler.bindings[receiver_binding].mutable { fail_at_message(env, files, compiler, file_index, syntax.start, "list mutation requires a writable local, parameter, or field place") }
                    if method == COLLECTION_METHOD_INSERT && active_view_overlaps_place(tables, compiler, frame.scope, receiver) {
                        fail_view_live_method(env, source, files, tokens, compiler, file_index, syntax.anchor, receiver_ty, syntax.token)
                    }
                    if method == COLLECTION_METHOD_INSERT {
                        if argument < 0L || compiler.facts[argument].ty != TY_LONG { fail_at_message(env, files, compiler, file_index, if argument >= 0L { tables.nodes[argument].start } else { syntax.start }, "collection indexes are long; cast an int index with .to_long()") }
                        argument = compiler.child_next[argument]
                    }
                    if argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "list mutation is missing its element") }
                    let element_type = collection_element_type(compiler, receiver_ty)
                    require_type(env, files, compiler, file_index, argument, element_type, compiler.facts[argument].ty, tables)
                    let full_ty = builtin_full_type_id(compiler)
                    if full_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "internal capacity error type is unavailable") }
                    operation_result_type = intern_sum_type(compiler, TYPE_KIND_RESULT, TY_UNIT, full_ty, file_index, node, -1L, -1L)
                } else if method == COLLECTION_METHOD_CLEAR {
                    let receiver_binding = compiler.facts[receiver].binding
                    if receiver_binding < 0L || !compiler.bindings[receiver_binding].mutable { fail_at_message(env, files, compiler, file_index, syntax.start, "list mutation requires a writable local, parameter, or field place") }
                    if active_view_overlaps_place(tables, compiler, frame.scope, receiver) {
                        fail_view_live_method(env, source, files, tokens, compiler, file_index, syntax.anchor, receiver_ty, syntax.token)
                    }
                } else { fail_at_message(env, files, compiler, file_index, syntax.start, "unsupported collection method") }
                if frame.expected >= 0L && frame.expected != operation_result_type { require_type(env, files, compiler, file_index, node, frame.expected, operation_result_type, tables) }
                let receiver_binding = compiler.facts[receiver].binding
                let tracks_root = receiver_binding >= 0L && receiver_binding < compiler.bindings.count() && compiler.bindings[receiver_binding].ty == receiver_ty
                let proven = method == COLLECTION_METHOD_PUSH && collection_push_is_proven(compiler, receiver, frame.loop_depth)
                if tracks_root {
                    if method == COLLECTION_METHOD_PUSH {
                        if proven { set_binding_collection_count(compiler, receiver_binding, compiler.bindings[receiver_binding].collection_count + 1L) }
                        else { set_binding_collection_count(compiler, receiver_binding, collection_capacity(compiler, receiver_ty)) }
                    } else if method == COLLECTION_METHOD_CLEAR { set_binding_collection_count(compiler, receiver_binding, 0L) }
                    else if method == COLLECTION_METHOD_POOL_ADD { set_binding_collection_count(compiler, receiver_binding, -1L) }
                    else if method == COLLECTION_METHOD_INSERT || method == COLLECTION_METHOD_POP || method == COLLECTION_METHOD_REMOVE {
                        set_binding_collection_count(compiler, receiver_binding, -1L)
                    } else { () }
                }
                let fact_flags = (if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }) |
                    (if proven { FACT_PROVEN_SUCCESS } else { 0L })
                compiler.facts[node] = NodeFact { ty: operation_result_type, flags: fact_flags, binding: compiler.facts[receiver].binding, function: -1L, literal: method }
            } else if receiver_kind == TYPE_KIND_ASCII || receiver_kind == TYPE_KIND_TEXT || receiver_kind == TYPE_KIND_BYTES {
                let method = text_method_kind(source, tokens, files, file_index, syntax.token, receiver_kind)
                if method == 0L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "no matching text method is available on this value") }
                if method == TEXT_METHOD_TRY_APPEND || method == TEXT_METHOD_PUSH {
                    let method_result_ty = check_text_builder_method(env, source, files, tokens, tables, compiler,
                        file_index, frame.scope, node, receiver, receiver_ty, frame.expected)
                    let receiver_binding = compiler.facts[receiver].binding
                    let tracks_root = receiver_binding >= 0L && receiver_binding < compiler.bindings.count() &&
                        compiler.bindings[receiver_binding].ty == receiver_ty
                    let proven = method == TEXT_METHOD_PUSH && builder_push_is_proven(compiler, receiver, frame.loop_depth)
                    if tracks_root {
                        if method == TEXT_METHOD_PUSH && proven {
                            set_binding_collection_count(compiler, receiver_binding, compiler.bindings[receiver_binding].collection_count + 1L)
                        } else {
                            set_binding_collection_count(compiler, receiver_binding, -1L)
                        }
                    }
                    let fact_flags = (if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }) |
                        (if proven { FACT_PROVEN_SUCCESS } else { 0L })
                    compiler.facts[node] = NodeFact { ty: method_result_ty, flags: fact_flags, binding: receiver_binding, function: -1L, literal: method }
                } else {
                let actual_count = count_children(tables, compiler, node) - 1L
                let wanted_count = if method == TEXT_METHOD_SLICE { 2L }
                    else if method == TEXT_METHOD_CONTAINS || method == TEXT_METHOD_STARTS_WITH { 1L }
                    else { 0L }
                if actual_count != wanted_count { fail_at_message(env, files, compiler, file_index, syntax.start, "text method has the wrong number of arguments") }
                var argument = if receiver >= 0L { compiler.child_next[receiver] } else { -1L }
                var method_result_ty = TY_LONG
                if method == TEXT_METHOD_SLICE {
                    for bound in 0L..2L {
                        if argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "slice is missing a bound") }
                        if compiler.facts[argument].ty != TY_LONG {
                            fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "slice bounds must be long")
                        }
                        argument = compiler.child_next[argument]
                    }
                    method_result_ty = receiver_ty
                } else if method == TEXT_METHOD_BYTES {
                    method_result_ty = intern_text_type(compiler, TYPE_KIND_BYTES, text_max_bytes(compiler, receiver_ty), 0L, file_index, node, -1L, -1L)
                    if method_result_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "Bytes view type exceeds the supported value size") }
                } else if method == TEXT_METHOD_VALIDATE_UTF8 {
                    let error_ty = builtin_synthetic_type_id(compiler, -3L)
                    if error_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "Utf8Error built-in type is unavailable") }
                    method_result_ty = intern_sum_type(compiler, TYPE_KIND_RESULT, TY_UNIT, error_ty, file_index, node, -1L, -1L)
                    if sum_layout_has_invalid_overflow(compiler, method_result_ty) {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "Bytes.validate_utf8 result has an invalid layout")
                    }
                } else if method == TEXT_METHOD_TO_TEXT {
                    let error_ty = builtin_synthetic_type_id(compiler, -3L)
                    if error_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "Utf8Error built-in type is unavailable") }
                    let maximum = text_max_bytes(compiler, receiver_ty)
                    if maximum < 0L || maximum > MAX_VALUE_SIZE - 16L {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "Bytes.to_text Text maximum overflows; reduce the Bytes maximum")
                    }
                    let text_ty = intern_text_type(compiler, TYPE_KIND_TEXT, maximum, maximum, file_index, node, -1L, -1L)
                    if text_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "Bytes.to_text Text result exceeds the supported value size") }
                    method_result_ty = intern_sum_type(compiler, TYPE_KIND_RESULT, text_ty, error_ty, file_index, node, -1L, -1L)
                    if sum_layout_has_invalid_overflow(compiler, method_result_ty) {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "Bytes.to_text Result layout overflows; reduce the Bytes maximum")
                    }
                } else if method == TEXT_METHOD_TO_ASCII {
                    let error_ty = builtin_synthetic_type_id(compiler, -2L)
                    if error_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "TextError built-in type is unavailable") }
                    let maximum = text_max_bytes(compiler, receiver_ty)
                    if maximum < 0L || maximum > MAX_VALUE_SIZE - 8L {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "to_ascii Ascii maximum overflows; reduce the source maximum")
                    }
                    let ascii_ty = intern_text_type(compiler, TYPE_KIND_ASCII, maximum, 0L, file_index, node, -1L, -1L)
                    if ascii_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "to_ascii Ascii result exceeds the supported value size") }
                    method_result_ty = intern_sum_type(compiler, TYPE_KIND_RESULT, ascii_ty, error_ty, file_index, node, -1L, -1L)
                    if sum_layout_has_invalid_overflow(compiler, method_result_ty) {
                        fail_at_message(env, files, compiler, file_index, syntax.start, "to_ascii Result layout overflows; reduce the source maximum")
                    }
                } else if method == TEXT_METHOD_CONTAINS || method == TEXT_METHOD_STARTS_WITH {
                    if argument < 0L || type_kind(compiler, compiler.facts[argument].ty) != TYPE_KIND_ASCII {
                        fail_at_message(env, files, compiler, file_index, if argument >= 0L { tables.nodes[argument].start } else { syntax.start }, "Ascii string methods require an Ascii argument")
                    }
                    require_type(env, files, compiler, file_index, argument, receiver_ty, compiler.facts[argument].ty, tables)
                    method_result_ty = TY_BOOL
                } else { method_result_ty = TY_LONG }
                if frame.expected >= 0L && frame.expected != method_result_ty {
                    require_type(env, files, compiler, file_index, node, frame.expected, method_result_ty, tables)
                }
                compiler.facts[node] = NodeFact { ty: method_result_ty, flags: if node_children_fall_through(tables, compiler, node) { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: method }
                }
            } else if operation < 0L {
                if count_children(tables, compiler, node) != 1L {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "Option and Result methods take no arguments")
                }
                let method_is_some = token_is_word_at(source, tokens, files, file_index, syntax.token, "is_some")
                let method_is_none = token_is_word_at(source, tokens, files, file_index, syntax.token, "is_none")
                let method_is_ok = token_is_word_at(source, tokens, files, file_index, syntax.token, "is_ok")
                let method_is_err = token_is_word_at(source, tokens, files, file_index, syntax.token, "is_err")
                let method_ok = token_is_word_at(source, tokens, files, file_index, syntax.token, "ok")
                let method_unwrap = token_is_word_at(source, tokens, files, file_index, syntax.token, "unwrap")
                var method_result_ty = -1L
                if receiver_kind == TYPE_KIND_OPTION && (method_is_some || method_is_none) { method_result_ty = TY_BOOL }
                else if receiver_kind == TYPE_KIND_OPTION && method_unwrap { method_result_ty = sum_case_payload_type(compiler, receiver_ty, 0L, 0L) }
                else if receiver_kind == TYPE_KIND_RESULT && (method_is_ok || method_is_err) { method_result_ty = TY_BOOL }
                else if receiver_kind == TYPE_KIND_RESULT && method_unwrap { method_result_ty = sum_case_payload_type(compiler, receiver_ty, 0L, 0L) }
                else if receiver_kind == TYPE_KIND_RESULT && method_ok {
                    let value_ty = sum_case_payload_type(compiler, receiver_ty, 0L, 0L)
                    method_result_ty = intern_sum_type(compiler, TYPE_KIND_OPTION, value_ty, -1L, file_index, node, -1L, -1L)
                    if sum_layout_has_invalid_overflow(compiler, method_result_ty) { fail_at_message(env, files, compiler, file_index, syntax.start, "Option value from Result.ok() has an invalid layout") }
                } else {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "no matching Option or Result method is available on this value")
                }
                if frame.expected >= 0L && frame.expected != method_result_ty { require_type(env, files, compiler, file_index, node, frame.expected, method_result_ty, tables) }
                compiler.facts[node] = NodeFact { ty: method_result_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            } else {
                let expected_count = core_sys_argument_count(operation)
                let actual_count = count_children(tables, compiler, node) - 1L
                if expected_count < 0L || actual_count != expected_count {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "core system operation has the wrong number of arguments")
                }
                var argument = compiler.child_first[node]
                if argument >= 0L { argument = compiler.child_next[argument] }
                for argument_index in 0L..expected_count {
                    if argument < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "core system operation is missing an argument") }
                    let expected_ty = core_sys_argument_type(operation, argument_index)
                    if expected_ty < 0L { fail_at_message(env, files, compiler, file_index, syntax.start, "invalid core system operation signature") }
                    require_type(env, files, compiler, file_index, argument, expected_ty, compiler.facts[argument].ty, tables)
                    if operation == SYS_LIT && tables.nodes[argument].kind != NodeKind.BytesLiteral {
                        fail_at_message(env, files, compiler, file_index, tables.nodes[argument].start, "sys.lit requires a byte-string literal")
                    }
                    argument = compiler.child_next[argument]
                }
                let syscall_result_ty = core_sys_result_type(operation)
                if frame.expected >= 0L && frame.expected != syscall_result_ty && syscall_result_ty != TY_NEVER {
                    require_type(env, files, compiler, file_index, node, frame.expected, syscall_result_ty, tables)
                }
                compiler.facts[node] = NodeFact { ty: syscall_result_ty, flags: if syscall_result_ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: operation }
            }
        } else if kind == NodeKind.Fit {
            let source_ty = compiler.facts[frame.child0].ty
            let target_ty = frame.result_ty
            if type_kind(compiler, target_ty) == TYPE_KIND_ASCII {
                if type_kind(compiler, source_ty) != TYPE_KIND_ASCII {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start,
                        "fit input must be Ascii")
                }
            } else if target_ty == TY_BYTE {
                if source_ty != TY_INT {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start,
                        "fit input must have base type int")
                }
            } else {
                fail_at_message(env, files, compiler, file_index, tables.nodes[frame.child0].start,
                    "fit<T>() needs an int or long refinement type")
            }
            let option_ty = intern_sum_type(compiler, TYPE_KIND_OPTION, target_ty, -1L, file_index, node, -1L, -1L)
            if sum_layout_has_invalid_overflow(compiler, option_ty) {
                fail_at_message(env, files, compiler, file_index, syntax.start, "fit result Option layout overflows; reduce the target maximum")
            }
            if frame.expected >= 0L && frame.expected != option_ty { require_type(env, files, compiler, file_index, node, frame.expected, option_ty, tables) }
            compiler.facts[node] = NodeFact { ty: option_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Cast {
            let source_ty = compiler.facts[frame.child0].ty
            let target_ty = frame.result_ty
            if type_kind(compiler, target_ty) == TYPE_KIND_ASCII {
                if type_kind(compiler, source_ty) != TYPE_KIND_ASCII {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "Ascii casts require an Ascii input")
                } else { () }
            } else if (!is_numeric_type(source_ty) && source_ty != TY_BYTE && source_ty != TY_DOUBLE) || (!is_numeric_type(target_ty) && target_ty != TY_BYTE && target_ty != TY_DOUBLE) {
                fail_at_message(env, files, compiler, file_index, syntax.start, "casts in this subset require int, long, or byte")
            } else { () }
            if frame.expected >= 0L && frame.expected != target_ty {
                require_type(env, files, compiler, file_index, node, frame.expected, target_ty, tables)
            }
            compiler.facts[node] = NodeFact { ty: target_ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.ToLong {
            let value_ty = compiler.facts[frame.child0].ty
            if value_ty != TY_INT && value_ty != TY_BYTE {
                let message: Ascii max 160 = if value_ty == TY_LONG { "no method 'to_long' on long; 'to_long' is available on int" }
                    else if value_ty == TY_BOOL { "no method 'to_long' on bool; 'to_long' is available on int" }
                    else if value_ty == TY_UNIT { "no method 'to_long' on (); 'to_long' is available on int" }
                    else if value_ty == TY_ADDR { "no method 'to_long' on sys.Addr; 'to_long' is available on int" }
                    else { "no method 'to_long' on never; 'to_long' is available on int" }
                fail_at_message(env, files, compiler, file_index, syntax.anchor, message)
            }
            if frame.expected >= 0L && frame.expected != TY_LONG {
                require_type(env, files, compiler, file_index, node, frame.expected, TY_LONG, tables)
            }
            compiler.facts[node] = NodeFact { ty: TY_LONG, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Unary {
            let child = frame.child0
            let value = compiler.facts[child]
            if syntax.flags == 1L {
                require_type(env, files, compiler, file_index, child, TY_BOOL, value.ty, tables)
                compiler.facts[node] = NodeFact { ty: TY_BOOL, flags: value.flags, binding: -1L, function: -1L, literal: 0L }
            } else {
                if !is_numeric_type(value.ty) && !(value.ty == TY_DOUBLE && syntax.flags != 2L) {
                    if syntax.flags == 2L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "unary '~' requires int or long") }
                    else { fail_at_message(env, files, compiler, file_index, syntax.anchor, "unary '-' requires int or long") }
                }
                compiler.facts[node] = NodeFact { ty: value.ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
            }
        } else if kind == NodeKind.Binary {
            var left = compiler.facts[frame.child0]
            var right = compiler.facts[frame.child1]
            let op = syntax.flags
            // A byte next to an int is an int (two bytes are not: byte arithmetic needs a cast).
            if left.ty == TY_BYTE && right.ty == TY_INT { left.ty = TY_INT }
            else if left.ty == TY_INT && right.ty == TY_BYTE { right.ty = TY_INT }
            else { () }
            var ty = -1L
            if op == 14L || op == 15L {
                require_type(env, files, compiler, file_index, frame.child0, TY_BOOL, left.ty, tables)
                require_type(env, files, compiler, file_index, frame.child1, TY_BOOL, right.ty, tables)
                ty = TY_BOOL
            } else if op == 21L {
                if type_kind(compiler, left.ty) == TYPE_KIND_RESULT {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "'??' works on Option only; use 'match' to handle a Result or '?' to pass its error up")
                }
                if type_kind(compiler, left.ty) != TYPE_KIND_OPTION {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "'??' requires an Option<T> value")
                }
                ty = sum_case_payload_type(compiler, left.ty, 0L, 0L)
                require_type(env, files, compiler, file_index, frame.child1, ty, right.ty, tables)
            } else if op == 0L && is_text_concatenation(compiler, left.ty, right.ty) {
                let left_kind = type_kind(compiler, left.ty)
                let right_kind = type_kind(compiler, right.ty)
                let result_kind = if left_kind == TYPE_KIND_BYTES { TYPE_KIND_BYTES }
                    else if left_kind == TYPE_KIND_TEXT || right_kind == TYPE_KIND_TEXT { TYPE_KIND_TEXT }
                    else { TYPE_KIND_ASCII }
                let left_bytes = text_max_bytes(compiler, left.ty)
                let right_bytes = text_max_bytes(compiler, right.ty)
                if left_bytes < 0L || right_bytes < 0L || left_bytes > 9223372036854775807L - right_bytes {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "text concatenation maximum overflows; reduce an operand maximum")
                }
                let result_bytes = left_bytes + right_bytes
                let result_header = if result_kind == TYPE_KIND_TEXT { 16L } else { 8L }
                if result_bytes > MAX_VALUE_SIZE - result_header {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor,
                        "text concatenation maximum overflows; reduce an operand maximum")
                }
                let result_points = if result_kind == TYPE_KIND_TEXT {
                    let left_points = text_max_codepoints(compiler, left.ty)
                    let right_points = text_max_codepoints(compiler, right.ty)
                    if left_points < 0L || right_points < 0L || left_points > 9223372036854775807L - right_points {
                        fail_at_message(env, files, compiler, file_index, syntax.anchor, "Text concatenation code-point maximum overflows; reduce an operand maximum")
                    }
                    left_points + right_points
                } else { 0L }
                var concat_result_ty = intern_text_type(compiler, result_kind, result_bytes, result_points, file_index, node, -1L, -1L)
                if concat_result_ty < 0L {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor,
                        "text concatenation result exceeds the supported value size")
                }
                if frame.expected >= 0L {
                    if text_width_fits(compiler, concat_result_ty, frame.expected) { concat_result_ty = frame.expected }
                    else { fail_type_mismatch(env, files, compiler, file_index, syntax.anchor, frame.expected, concat_result_ty) }
                }
                ty = concat_result_ty
            } else if op >= 8L && op <= 13L {
                let text_pair = is_text_comparable(compiler, left.ty, right.ty)
                if left.ty != right.ty && !text_pair { fail_mixed_types(env, files, compiler, file_index, syntax.anchor, left.ty, right.ty) }
                if (op == 8L || op == 9L) && (left.ty == TY_UNIT || left.ty == TY_NEVER) {
                    fail_at_message(env, files, compiler, file_index, syntax.anchor, "equality requires values other than ()")
                }
                if op >= 10L && !is_numeric_type(left.ty) && left.ty != TY_BYTE && left.ty != TY_DOUBLE && !text_pair { fail_at_message(env, files, compiler, file_index, syntax.anchor, "ordered comparisons require int, long, or byte values") }
                ty = TY_BOOL
            } else if op >= 16L && op <= 20L {
                if !is_numeric_type(left.ty) { fail_at_message(env, files, compiler, file_index, syntax.anchor, "bitwise operators require int or long values") }
                if left.ty != right.ty { fail_mixed_types(env, files, compiler, file_index, syntax.anchor, left.ty, right.ty) }
                require_type(env, files, compiler, file_index, frame.child1, left.ty, right.ty, tables)
                ty = left.ty
            } else {
                if left.ty == TY_DOUBLE && op > 3L { fail_at_message(env, files, compiler, file_index, syntax.anchor, "double supports + - * / and comparisons only") }
                if !is_numeric_type(left.ty) && left.ty != TY_DOUBLE { fail_at_message(env, files, compiler, file_index, syntax.anchor, "arithmetic operators require int or long values") }
                if (is_numeric_type(right.ty) || right.ty == TY_DOUBLE) && left.ty != right.ty { fail_mixed_types(env, files, compiler, file_index, syntax.anchor, left.ty, right.ty) }
                require_type(env, files, compiler, file_index, frame.child1, left.ty, right.ty, tables)
                ty = left.ty
            }
            if frame.expected >= 0L && ty != TY_NEVER && ty != frame.expected { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
            compiler.facts[node] = NodeFact { ty, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.If {
            let condition = compiler.facts[frame.child0]
            require_type(env, files, compiler, file_index, frame.child0, TY_BOOL, condition.ty, tables)
            let then_ty = compiler.facts[frame.child1].ty
            let else_ty = if frame.child2 >= 0L { compiler.facts[frame.child2].ty } else { TY_UNIT }
            var ty = -1L
            if then_ty == TY_NEVER { ty = else_ty }
            else if else_ty == TY_NEVER { ty = then_ty }
            else if then_ty == else_ty { ty = then_ty }
            else if type_kind(compiler, then_ty) == TYPE_KIND_ASCII && type_kind(compiler, else_ty) == TYPE_KIND_ASCII {
                let then_maximum = text_max_bytes(compiler, then_ty)
                let else_maximum = text_max_bytes(compiler, else_ty)
                let maximum = if then_maximum > else_maximum { then_maximum } else { else_maximum }
                ty = intern_text_type(compiler, TYPE_KIND_ASCII, maximum, 0L, file_index, node, -1L, -1L)
                if ty < 0L {
                    fail_at_message(env, files, compiler, file_index, syntax.start,
                        "Ascii conditional result exceeds compiler capacity")
                }
            }
            else { fail_type_mismatch(env, files, compiler, file_index, syntax.start, then_ty, else_ty) }
            if frame.expected >= 0L && ty != TY_NEVER && ty != frame.expected { require_type(env, files, compiler, file_index, node, frame.expected, ty, tables) }
            compiler.facts[node] = NodeFact { ty, flags: if then_ty == TY_NEVER && else_ty == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.For {
            finish_loop_push_proofs(compiler, node)
            let start_ty = compiler.facts[frame.child0].ty
            let end_ty = compiler.facts[frame.child1].ty
            require_type(env, files, compiler, file_index, frame.child0, frame.result_ty, start_ty, tables)
            require_type(env, files, compiler, file_index, frame.child1, frame.result_ty, end_ty, tables)
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.While {
            let condition = compiler.facts[frame.child0]
            require_type(env, files, compiler, file_index, frame.child0, TY_BOOL, condition.ty, tables)
            finish_loop_push_proofs(compiler, node)
            compiler.facts[node] = NodeFact { ty: TY_UNIT, flags: FACT_FALLS_THROUGH, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Block {
            let has_tail = (syntax.flags & FLAG_HAS_TAIL) != 0L
            let last = node_last_child(tables, compiler, node)
            let tail_proven_success = has_tail && last >= 0L && (compiler.facts[last].flags & FACT_PROVEN_SUCCESS) != 0L
            let tail_ty = if !has_tail || last < 0L || tail_proven_success { TY_UNIT } else { compiler.facts[last].ty }
            var can_reach = true
            var child = compiler.child_first[node]
            for child_step in 0L..syntax.subtree {
                if child < 0L { break }
                if child != last || !has_tail {
                    if can_reach && (compiler.facts[child].flags & FACT_FALLS_THROUGH) == 0L { can_reach = false }
                }
                child = compiler.child_next[child]
            }
            if frame.expected == TY_UNIT && can_reach && has_tail && tail_ty != TY_UNIT && tail_ty != TY_NEVER {
                if type_kind(compiler, tail_ty) == TYPE_KIND_RESULT {
                    if tables.nodes[last].kind == NodeKind.MethodCall && compiler.facts[last].literal == COLLECTION_METHOD_POOL_ADD {
                        report_unsupported(env, source, files, tokens, tables, compiler, UnsupportedHit { found: true, file: file_index, node: last, offset: tables.nodes[last].start, category: UNSUPPORTED_POOL_USE, token: tables.nodes[last].token })
                    }
                    fail_at_message(env, files, compiler, file_index, tables.nodes[last].start, "this Result value is unused; handle it with '?', 'match', or '??' where supported")
                }
                let message: Ascii max 160 = "block value must be discarded or returned as unit"
                fail_at_message(env, files, compiler, file_index, tables.nodes[last].start, message)
            }
            child = compiler.child_first[node]
            for child_step in 0L..syntax.subtree {
                if child < 0L { break }
                if (child != last || !has_tail) &&
                    (tables.nodes[child].kind == NodeKind.Block || tables.nodes[child].kind == NodeKind.If) &&
                    type_kind(compiler, compiler.facts[child].ty) == TYPE_KIND_RESULT &&
                    (compiler.facts[child].flags & FACT_PROVEN_SUCCESS) == 0L {
                    fail_at_message(env, files, compiler, file_index, tables.nodes[child].start, "this Result value is unused; handle it with '?', 'match', or '??' where supported")
                }
                child = compiler.child_next[child]
            }
            if frame.expected >= 0L && frame.expected != TY_UNIT && can_reach && has_tail && tail_ty != TY_NEVER { require_type(env, files, compiler, file_index, last, frame.expected, tail_ty, tables) }
            let result = if !can_reach { TY_NEVER } else if has_tail { tail_ty } else { TY_UNIT }
            compiler.facts[node] = NodeFact { ty: result, flags: if !can_reach || result == TY_NEVER { FACT_NEVER } else { FACT_FALLS_THROUGH }, binding: -1L, function: -1L, literal: 0L }
        } else if kind == NodeKind.Try {
            if function_id <= -100000L {
                fail_at_message(env, files, compiler, file_index, syntax.start, "'?' is not allowed in a field default")
            }
            if is_test {
                fail_at_message(env, files, compiler, file_index, syntax.start, "a test cannot use '?'; let the test finish so all expectations run")
            }
            let operand_ty = compiler.facts[frame.child0].ty
            let operand_kind = type_kind(compiler, operand_ty)
            var success_ty = -1L
            if operand_kind == TYPE_KIND_OPTION {
                if type_kind(compiler, result_ty) != TYPE_KIND_OPTION {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "'?' on Option requires the enclosing function to return Option")
                }
                success_ty = sum_case_payload_type(compiler, operand_ty, 0L, 0L)
            } else if operand_kind == TYPE_KIND_RESULT {
                if type_kind(compiler, result_ty) != TYPE_KIND_RESULT {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "'?' on Result requires the enclosing function to return Result")
                }
                let operand_error = sum_case_payload_type(compiler, operand_ty, 1L, 0L)
                let return_error = sum_case_payload_type(compiler, result_ty, 1L, 0L)
                if operand_error != return_error {
                    fail_at_message(env, files, compiler, file_index, syntax.start, "'?' error type does not match the enclosing Result error type")
                }
                success_ty = sum_case_payload_type(compiler, operand_ty, 0L, 0L)
            } else {
                fail_at_message(env, files, compiler, file_index, syntax.start, "'?' requires an Option or Result value")
            }
            if frame.expected >= 0L && frame.expected != success_ty { require_type(env, files, compiler, file_index, node, frame.expected, success_ty, tables) }
            compiler.facts[node] = NodeFact { ty: success_ty, flags: if (compiler.facts[frame.child0].flags & FACT_FALLS_THROUGH) != 0L { FACT_FALLS_THROUGH } else { FACT_NEVER }, binding: -1L, function: -1L, literal: 0L }
        } else {
            fail_at_message(env, files, compiler, file_index, syntax.start, "internal self-hosted checker finalization failure")
        }
        match compiler.work.pop() { some(_) => (), none => () }
    }
    if compiler.work.count() > 0L { fail_parse_limit(env, files[file_index].name, "self-hosted checker work limit exceeded") }
    let body_fact = compiler.facts[body]
    if tables.nodes[body].kind == NodeKind.Block && result_ty != TY_UNIT && (body_fact.flags & FACT_FALLS_THROUGH) != 0L && (tables.nodes[body].flags & FLAG_HAS_TAIL) == 0L {
        fail_missing_return(env, source, files, tokens, compiler, compiler.functions[function_id], result_ty, tables.nodes[body].start)
    }
    if tables.nodes[body].kind == NodeKind.Block && result_ty == TY_UNIT && (body_fact.flags & FACT_FALLS_THROUGH) != 0L && body_fact.ty != TY_UNIT && body_fact.ty != TY_NEVER {
        fail_at_message(env, files, compiler, file_index, tables.nodes[body].start, "unit function body has a non-unit tail expression")
    }
}

fn check_package_bodies(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    config: MemoryConfig,
    compiler: write CompilerTables,
) {
    for function_id in 0L..compiler.functions.count() {
        let function = compiler.functions[function_id]
        let scope = create_scope(env, files, compiler, -1L, function_id, function.node, function.file)
        for parameter_index in 0L..function.param_count {
            let parameter = compiler.parameters[function.param_start + parameter_index]
            let parameter_token = parameter_name_token(parameter)
            let parameter_mode_flags = parameter_mode(parameter)
            let _ = add_local_binding(env, source, files, tokens, tables, compiler, function.file, parameter.node, parameter_token, scope, parameter.ty, (parameter_mode_flags & (FLAG_MODE_WRITE | FLAG_MODE_GROW)) != 0L, false, true)
        }
        check_one_body(env, source, files, tokens, tables, config, compiler, function.body, function.file, function_id, function.result_ty, false, scope)
    }
    for test_index in 0L..compiler.tests.count() {
        let test = compiler.tests[test_index]
        let scope = create_scope(env, files, compiler, -1L, -1L - test_index, test.node, test.file)
        check_one_body(env, source, files, tokens, tables, config, compiler, test.body, test.file, -1L - test_index, TY_UNIT, true, scope)
    }
}

fn initialize_default_graph_nodes(compiler: write CompilerTables) {
    for function_id in 0L..compiler.functions.count() {
        compiler.frame_own_bytes.push(0L).unwrap()
        compiler.frame_path_bytes.push(0L).unwrap()
        compiler.frame_visit.push(0L).unwrap()
    }
    for field_index in 0L..compiler.struct_fields.count() {
        compiler.edge_first.push(-1L).unwrap()
        compiler.cycle_seen.push(0L).unwrap()
        compiler.frame_own_bytes.push(0L).unwrap()
        compiler.frame_path_bytes.push(0L).unwrap()
        compiler.frame_visit.push(0L).unwrap()
    }
    for test_index in 0L..compiler.tests.count() {
        compiler.edge_first.push(-1L).unwrap()
        compiler.cycle_seen.push(0L).unwrap()
        compiler.frame_own_bytes.push(0L).unwrap()
        compiler.frame_path_bytes.push(0L).unwrap()
        compiler.frame_visit.push(0L).unwrap()
    }
}

fn default_graph_node(compiler: CompilerTables, field_index: long) -> long {
    compiler.functions.count() + field_index
}

fn test_graph_node(compiler: CompilerTables, test_index: long) -> long {
    compiler.functions.count() + compiler.struct_fields.count() + test_index
}

fn struct_literal_omits_field(
    tables: ParseTables,
    compiler: CompilerTables,
    literal: long,
    field_index: long,
) -> bool {
    var initializer = compiler.child_first[literal]
    for step in 0L..tables.nodes[literal].subtree {
        if initializer < 0L { break }
        if compiler.facts[initializer].binding == field_index { return false }
        initializer = compiler.child_next[initializer]
    }
    true
}

fn push_call_graph_edge(compiler: write CompilerTables, from: long, to: long, syntax_node: long) {
    let edge_id = compiler.call_edges.count()
    let next_edge = compiler.edge_first[from]
    compiler.call_edges.push(CallEdge { from, to, node: syntax_node, next: next_edge }).unwrap()
    compiler.edge_first[from] = edge_id
}

fn fail_default_cycle(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: CompilerTables,
    field_index: long,
) -> never {
    let field = compiler.struct_fields[field_index]
    let ty = struct_record(compiler, field.owner)
    let position = position_for_offset(ty.file, files[ty.file].base + tables.nodes[field.default_node].start, compiler)
    match env.err.write(files[ty.file].name) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.line).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b":") { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(str(position.col).bytes()) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b": error: field defaults form a cycle through ") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, ty.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b".") { ok(_) => (), err(_) => env.exit(3) }
    match write_token_raw(env.err, source, tokens, files[ty.file].base, field.name_token) { ok(_) => (), err(_) => env.exit(3) }
    match env.err.write(b"; give one of these fields an explicit value\n") { ok(_) => env.exit(2), err(_) => env.exit(3) }
}

fn check_default_cycles(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for start_field in 0L..compiler.struct_fields.count() {
        if compiler.struct_fields[start_field].default_node < 0L { continue }
        let start_node = default_graph_node(compiler, start_field)
        if compiler.cycle_seen[start_node] == 2L { continue }
        compiler.cycle_seen[start_node] = 1L
        compiler.cycle_stack.clear()
        compiler.cycle_cursor.clear()
        compiler.cycle_stack.push(start_node).unwrap()
        compiler.cycle_cursor.push(compiler.edge_first[start_node]).unwrap()
        for step in 0L..MAX_PARSE_WORK {
            if compiler.cycle_stack.count() == 0L { break }
            let top = compiler.cycle_stack.count() - 1L
            let edge_id = compiler.cycle_cursor[top]
            if edge_id < 0L {
                let finished = compiler.cycle_stack[top]
                compiler.cycle_seen[finished] = 2L
                match compiler.cycle_stack.pop() { some(_) => (), none => () }
                match compiler.cycle_cursor.pop() { some(_) => (), none => () }
            } else {
                let edge = compiler.call_edges[edge_id]
                compiler.cycle_cursor[top] = edge.next
                if compiler.cycle_seen[edge.to] == 1L {
                    var cycle_start = -1L
                    for path_index in 0L..compiler.cycle_stack.count() {
                        if compiler.cycle_stack[path_index] == edge.to { cycle_start = path_index }
                    }
                    var first_cycle_field = edge.to - compiler.functions.count()
                    for path_index in cycle_start..compiler.cycle_stack.count() {
                        let candidate = compiler.cycle_stack[path_index] - compiler.functions.count()
                        if candidate < first_cycle_field { first_cycle_field = candidate }
                    }
                    fail_default_cycle(env, source, files, tokens, tables, compiler, first_cycle_field)
                } else if compiler.cycle_seen[edge.to] == 0L {
                    compiler.cycle_seen[edge.to] = 1L
                    compiler.cycle_stack.push(edge.to).unwrap()
                    compiler.cycle_cursor.push(compiler.edge_first[edge.to]).unwrap()
                } else { () }
            }
        }
    }
}

fn append_default_context_ascii(context: grow Bytes max 4096, value: Ascii max 64) {
    for index in 0L..value.len() { context.push(value.bytes()[index]).unwrap() }
}

fn append_default_context_token(
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    context: grow Bytes max 4096,
    file_index: long,
    token_index: long,
) {
    let token = tokens[token_index]
    let start = files[file_index].base + token.start
    for offset in 0L..token.length { context.push(source[start + offset]).unwrap() }
}

fn check_struct_defaults(
    env: Env,
    source: Bytes max SOURCE_BUFFER_CAPACITY,
    files: list<SourceFile, MAX_SOURCE_FILES>,
    tokens: list<Token, TOKEN_STORAGE_CAPACITY>,
    tables: ParseTables,
    config: MemoryConfig,
    compiler: write CompilerTables,
) {
    for type_index in 0L..struct_type_count(compiler) {
        let ty = struct_record(compiler, type_index)
        for field_offset in 0L..ty.field_count {
            let field_index = ty.field_start + field_offset
            let field = compiler.struct_fields[field_index]
            if field.default_node < 0L { continue }
            let function_id = -100000L - field_index
            var default_context: Bytes max 4096 = Bytes.empty()
            append_default_context_ascii(default_context, " (in the default for field '")
            append_default_context_token(source, files, tokens, default_context, ty.file, ty.name_token)
            append_default_context_ascii(default_context, ".")
            append_default_context_token(source, files, tokens, default_context, ty.file, field.name_token)
            append_default_context_ascii(default_context, "')")
            compiler.default_context = default_context
            let scope = create_scope(env, files, compiler, -1L, function_id, field.node, ty.file)
            check_one_body(env, source, files, tokens, tables, config, compiler, field.default_node, ty.file, function_id, field.ty, false, scope)
            let actual = compiler.facts[field.default_node].ty
            if actual != TY_NEVER && actual != field.ty { require_type(env, files, compiler, ty.file, field.default_node, field.ty, actual, tables) }
            compiler.default_context = Bytes.empty()
        }
    }
    for source_field in 0L..compiler.struct_fields.count() {
        let field = compiler.struct_fields[source_field]
        if field.default_node < 0L { continue }
        let root = field.default_node
        let first = root - tables.nodes[root].subtree + 1L
        for syntax_node in first..root + 1L {
            if tables.nodes[syntax_node].kind != NodeKind.StructInit { continue }
            let target_type = struct_type_matches(compiler, compiler.token_name_ids[tables.nodes[syntax_node].token])
            if target_type < 0L { continue }
            let target = struct_record(compiler, target_type)
            for target_offset in 0L..target.field_count {
                let target_field = target.field_start + target_offset
                if compiler.struct_fields[target_field].default_node >= 0L && struct_literal_omits_field(tables, compiler, syntax_node, target_field) {
                    let from = default_graph_node(compiler, source_field)
                    let to = default_graph_node(compiler, target_field)
                    push_call_graph_edge(compiler, from, to, syntax_node)
                }
            }
        }
    }
    check_default_cycles(env, source, files, tokens, tables, compiler)
}

fn add_default_call_graph_edges(
    tables: ParseTables,
    compiler: write CompilerTables,
) {
    for function_id in 0L..compiler.functions.count() {
        let root = compiler.functions[function_id].body
        let first = root - tables.nodes[root].subtree + 1L
        for syntax_node in first..root + 1L {
            if tables.nodes[syntax_node].kind != NodeKind.StructInit { continue }
            let type_index = struct_type_matches(compiler, compiler.token_name_ids[tables.nodes[syntax_node].token])
            if type_index < 0L { continue }
            let ty = struct_record(compiler, type_index)
            for offset in 0L..ty.field_count {
                let field_index = ty.field_start + offset
                if compiler.struct_fields[field_index].default_node >= 0L && struct_literal_omits_field(tables, compiler, syntax_node, field_index) {
                    let to = default_graph_node(compiler, field_index)
                    push_call_graph_edge(compiler, function_id, to, syntax_node)
                }
            }
        }
    }
    for field_index in 0L..compiler.struct_fields.count() {
        let field = compiler.struct_fields[field_index]
        if field.default_node < 0L { continue }
        let root = field.default_node
        let first = root - tables.nodes[root].subtree + 1L
        for syntax_node in first..root + 1L {
            if tables.nodes[syntax_node].kind == NodeKind.Call {
                let target = compiler.facts[syntax_node].function
                if target >= 0L {
                    let from = default_graph_node(compiler, field_index)
                    push_call_graph_edge(compiler, from, target, syntax_node)
                }
            }
        }
    }
    for test_index in 0L..compiler.tests.count() {
        let root = compiler.tests[test_index].body
        let first = root - tables.nodes[root].subtree + 1L
        let from = test_graph_node(compiler, test_index)
        for syntax_node in first..root + 1L {
            if tables.nodes[syntax_node].kind == NodeKind.Call {
                let target = if (compiler.facts[syntax_node].flags & FACT_SORT_BUILTIN) != 0L { compiler.facts[syntax_node].literal } else { compiler.facts[syntax_node].function }
                if target >= 0L { push_call_graph_edge(compiler, from, target, syntax_node) }
            } else if tables.nodes[syntax_node].kind == NodeKind.StructInit {
                let type_index = struct_type_matches(compiler, compiler.token_name_ids[tables.nodes[syntax_node].token])
                if type_index < 0L { continue }
                let ty = struct_record(compiler, type_index)
                for offset in 0L..ty.field_count {
                    let field_index = ty.field_start + offset
                    if compiler.struct_fields[field_index].default_node >= 0L && struct_literal_omits_field(tables, compiler, syntax_node, field_index) {
                        let to = default_graph_node(compiler, field_index)
                        push_call_graph_edge(compiler, from, to, syntax_node)
                    }
                }
            } else { () }
        }
    }
}

fn add_frame_slot_bytes(compiler: write CompilerTables, graph_node: long, ty: long) {
    if !is_aggregate_type(compiler, ty) { return }
    let size = value_type_size(compiler, ty)
    if size > 0L && size <= compiler.file_id_base { compiler.frame_own_bytes[graph_node] += size }
}

fn add_body_frame_slot_bytes(
    tables: ParseTables,
    compiler: write CompilerTables,
    root: long,
    graph_node: long,
) {
    let first = root - tables.nodes[root].subtree + 1L
    for syntax_node in first..root + 1L {
        let ty = compiler.facts[syntax_node].ty
        add_frame_slot_bytes(compiler, graph_node, ty)
    }
}

fn compute_frame_slot_paths(tables: ParseTables, compiler: write CompilerTables) {
    let graph_count = compiler.edge_first.count()
    for node in 0L..graph_count {
        compiler.frame_path_bytes[node] = -1L
        if node < compiler.functions.count() && (tables.nodes[compiler.functions[node].node].flags & FLAG_RECURSIVE) != 0L {
            compiler.frame_visit[node] = 2L
        } else {
            compiler.frame_visit[node] = 0L
        }
    }
    for start in 0L..graph_count {
        if compiler.frame_visit[start] == 2L { continue }
        compiler.cycle_stack.clear()
        compiler.cycle_cursor.clear()
        compiler.frame_visit[start] = 1L
        compiler.cycle_stack.push(start).unwrap()
        compiler.cycle_cursor.push(compiler.edge_first[start]).unwrap()
        for step in 0L..MAX_PARSE_WORK {
            if compiler.cycle_stack.count() == 0L { break }
            let top = compiler.cycle_stack.count() - 1L
            let edge_id = compiler.cycle_cursor[top]
            if edge_id >= 0L {
                let edge = compiler.call_edges[edge_id]
                compiler.cycle_cursor[top] = edge.next
                if edge.to >= 0L && edge.to < graph_count && compiler.frame_visit[edge.to] == 0L {
                    compiler.frame_visit[edge.to] = 1L
                    compiler.cycle_stack.push(edge.to).unwrap()
                    compiler.cycle_cursor.push(compiler.edge_first[edge.to]).unwrap()
                }
            } else {
                let node = compiler.cycle_stack[top]
                var largest_child = 0L
                var unknown_child = false
                var successor = compiler.edge_first[node]
                for edge_step in 0L..compiler.call_edges.count() {
                    if successor < 0L { break }
                    let edge = compiler.call_edges[successor]
                    if edge.to >= 0L && edge.to < graph_count {
                        let child_path = compiler.frame_path_bytes[edge.to]
                        if child_path < 0L {
                            unknown_child = true
                        } else if child_path > largest_child {
                            largest_child = child_path
                        } else { () }
                    }
                    successor = edge.next
                }
                if unknown_child {
                    compiler.frame_path_bytes[node] = -1L
                } else {
                    compiler.frame_path_bytes[node] = compiler.frame_own_bytes[node] + largest_child
                }
                compiler.frame_visit[node] = 2L
                match compiler.cycle_stack.pop() { some(_) => (), none => () }
                match compiler.cycle_cursor.pop() { some(_) => (), none => () }
            }
        }
    }
}

fn populate_frame_slot_bytes(tables: ParseTables, compiler: write CompilerTables) {
    for function_id in 0L..compiler.functions.count() {
        let function = compiler.functions[function_id]
        add_body_frame_slot_bytes(tables, compiler, function.body, function_id)
        for binding_id in 0L..compiler.bindings.count() {
            let binding = compiler.bindings[binding_id]
            if compiler.scopes[binding.scope].function_id == function_id && !binding.parameter {
                add_frame_slot_bytes(compiler, function_id, binding.ty)
            }
        }
    }
    for field_index in 0L..compiler.struct_fields.count() {
        let field = compiler.struct_fields[field_index]
        if field.default_node < 0L { continue }
        let graph_node = default_graph_node(compiler, field_index)
        add_body_frame_slot_bytes(tables, compiler, field.default_node, graph_node)
        let function_id = -100000L - field_index
        for binding_id in 0L..compiler.bindings.count() {
            let binding = compiler.bindings[binding_id]
            if compiler.scopes[binding.scope].function_id == function_id && !binding.parameter {
                add_frame_slot_bytes(compiler, graph_node, binding.ty)
            }
        }
    }
    for test_index in 0L..compiler.tests.count() {
        let body = compiler.tests[test_index].body
        let graph_node = test_graph_node(compiler, test_index)
        add_body_frame_slot_bytes(tables, compiler, body, graph_node)
        let function_id = -1L - test_index
        for binding_id in 0L..compiler.bindings.count() {
            let binding = compiler.bindings[binding_id]
            if compiler.scopes[binding.scope].function_id == function_id && !binding.parameter {
                add_frame_slot_bytes(compiler, graph_node, binding.ty)
            }
        }
    }
}

