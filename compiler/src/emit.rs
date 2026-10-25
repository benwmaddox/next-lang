use crate::ast::{AssignOp, BinaryOp, ParamMode, RefinePolicy, Span, UnaryOp};
use crate::typed::*;
use std::collections::HashMap;

fn result_error_type(ty: Ty, types: &[TType]) -> Option<Ty> {
    match &types[base_type(ty, types).0].kind {
        TTypeKind::Result(ok, error) if base_type(*ok, types) == Ty::Unit => Some(*error),
        _ => None,
    }
}

fn error_printer_function(id: usize, error_ty: Ty) -> TFunction {
    let span = Span::default();
    let argument = TExpr {
        kind: TExprKind::Local(0),
        ty: error_ty,
        span,
    };
    let body = TExpr {
        kind: TExprKind::Call {
            target: CallTarget::Print,
            args: vec![argument],
            effect: Effect::Observable,
        },
        ty: Ty::Unit,
        span,
    };
    TFunction {
        id,
        name: format!("__nl_print_error_{}", error_ty.0),
        params: vec![TParam {
            id: 0,
            name: "error".to_owned(),
            ty: error_ty,
            mode: ParamMode::Read,
            span,
        }],
        result: Ty::Unit,
        body: TBlock {
            statements: Vec::new(),
            tail: Some(Box::new(body)),
            falls_through: true,
            scope_id: 0,
            span,
        },
        span,
        is_test: false,
        recursive: false,
    }
}

fn emit_entry_call(
    out: &mut String,
    program: &TProgram,
    entry: &TFunction,
    error_printer: Option<usize>,
    label_prefix: &str,
) -> bool {
    let Some(error_ty) = result_error_type(entry.result, &program.types) else {
        let mut args = vec!["ptr %nl.ctx".to_owned(), "ptr %nl.top".to_owned()];
        if entry.params.first().is_some() {
            args.push("ptr %nl.env".to_owned());
        }
        out.push_str(&format!(
            "  call void @nl_fn_{}({})\n",
            entry.id,
            args.join(", ")
        ));
        return false;
    };

    let result_ty = base_type(entry.result, &program.types);
    let result_llvm_ty = llvm_type(result_ty, &program.types);
    let result_storage = format!("%{label_prefix}.result");
    let is_large_result = is_large_type(result_ty, &program.types);
    out.push_str(&format!(
        "  {result_storage} = alloca {result_llvm_ty}, align 1\n"
    ));
    let mut args = vec!["ptr %nl.ctx".to_owned(), "ptr %nl.top".to_owned()];
    if is_large_result {
        args.push(format!("ptr {result_storage}"));
    }
    if entry.params.first().is_some() {
        args.push("ptr %nl.env".to_owned());
    }
    if is_large_result {
        out.push_str(&format!(
            "  call void @nl_fn_{}({})\n",
            entry.id,
            args.join(", ")
        ));
    } else {
        let result_value = format!("%{label_prefix}.value");
        out.push_str(&format!(
            "  {result_value} = call {result_llvm_ty} @nl_fn_{}({})\n  store {result_llvm_ty} {result_value}, ptr {result_storage}, align 1\n",
            entry.id,
            args.join(", ")
        ));
    }

    let tag_pointer = format!("%{label_prefix}.tag.ptr");
    let tag = format!("%{label_prefix}.tag");
    let is_error = format!("%{label_prefix}.is.error");
    let error_label = format!("{label_prefix}.error");
    let success_label = format!("{label_prefix}.success");
    out.push_str(&format!(
        "  {tag_pointer} = getelementptr {result_llvm_ty}, ptr {result_storage}, i32 0, i32 0\n  {tag} = load i32, ptr {tag_pointer}, align 4\n  {is_error} = icmp eq i32 {tag}, 1\n  br i1 {is_error}, label %{error_label}, label %{success_label}\n{error_label}:\n  call void @nl_print_set_fd(i32 2)\n  call void @nl_print_error_prefix()\n"
    ));
    let payload_pointer = format!("%{label_prefix}.payload.ptr");
    let error_pointer = format!("%{label_prefix}.error.ptr");
    out.push_str(&format!(
        "  {payload_pointer} = getelementptr {result_llvm_ty}, ptr {result_storage}, i32 0, i32 1\n  {error_pointer} = getelementptr i8, ptr {payload_pointer}, i64 0\n"
    ));
    let printer_id = error_printer.expect("Result entry point has an error printer");
    let printer_param = if is_large_type(error_ty, &program.types) {
        format!("ptr {error_pointer}")
    } else {
        let value = format!("%{label_prefix}.error.value");
        out.push_str(&format!(
            "  {value} = load {}, ptr {error_pointer}, align 1\n",
            llvm_type(error_ty, &program.types)
        ));
        format!("{} {value}", llvm_type(error_ty, &program.types))
    };
    out.push_str(&format!(
        "  call void @nl_fn_{printer_id}(ptr %nl.ctx, ptr %nl.top, {printer_param})\n  call void @nl_print_set_fd(i32 1)\n  call void @nl_env_destroy(ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 1\n{success_label}:\n  call void @nl_env_destroy(ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 0\n"
    ));
    true
}

pub fn emit(program: &TProgram) -> String {
    let contracts = stack_contracts(program);
    let stack_entries = entry_stack_reservations(program, &contracts);
    let mut out = String::new();
    out.push_str("; generated by nlc\nsource_filename = \"next-lang\"\n\n");
    out.push_str("declare void @nl_fail(i32, i32, i32, i32) noreturn cold nounwind\n");
    out.push_str("declare ptr @nl_context_create(i64, i64, ptr)\n");
    out.push_str("declare ptr @nl_context_base(ptr)\n");
    out.push_str("declare void @nl_context_destroy(ptr)\n");
    out.push_str("declare void @nl_context_set_top(ptr, ptr)\n");
    out.push_str("declare void @nl_recursion_check(ptr, i64, i32, i32, i32)\n");
    out.push_str("declare ptr @nl_stack_alloc(ptr, ptr, i64, i64, i32, i32, i32)\n");
    out.push_str("declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1)\n");
    out.push_str("declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)\n");
    out.push_str("declare void @nl_register_file(i32, ptr)\n");
    out.push_str("declare ptr @nl_env_create(i32, ptr, i32)\n");
    out.push_str("declare void @nl_env_destroy(ptr)\n");
    out.push_str("declare ptr @nl_env_args(ptr)\n");
    out.push_str("declare ptr @nl_env_fs(ptr)\n");
    out.push_str("declare ptr @nl_env_out(ptr, i32)\n");
    out.push_str("declare i64 @nl_args_count(ptr)\n");
    out.push_str("declare ptr @nl_args_get(ptr, i64)\n");
    out.push_str("declare i64 @nl_arg_length(ptr)\n");
    out.push_str("declare i32 @nl_arg_byte(ptr, i64)\n");
    out.push_str("declare void @nl_fs_read(ptr, ptr, i32, i64, ptr, i64, ptr)\n");
    out.push_str("declare void @nl_fs_list(ptr, ptr, i32, i64, ptr, i64, ptr)\n");
    out.push_str("declare void @nl_fs_write(ptr, ptr, i32, i64, ptr, i32, i64, ptr)\n");
    out.push_str("declare void @nl_fs_join(ptr, ptr, i32, i64, ptr, i32, i64, ptr)\n");
    out.push_str("declare void @nl_out_write(ptr, ptr, i32, i64, i32, ptr)\n");
    out.push_str("declare void @nl_out_int(ptr, i32, ptr)\n");
    out.push_str("declare void @nl_out_long(ptr, i64, ptr)\n");
    out.push_str("declare void @nl_out_arg(ptr, ptr, i32, ptr)\n");
    out.push_str("declare zeroext i1 @nl_has_argument(i32, ptr, ptr)\n");
    out.push_str("declare void @nl_claim_memory(ptr, i64, i64, i1 zeroext)\n");
    out.push_str("declare i32 @nl_test_selected_index()\n");
    out.push_str("declare void @nl_set_test_mode()\n");
    out.push_str("declare void @nl_test_var_storage_reset()\n");
    out.push_str("declare void @nl_test_var_storage_note(ptr, ptr, i64)\n");
    out.push_str("declare void @nl_expect_fail_compare(i32, i32, i32, ptr, i64, i64, i32)\n");
    out.push_str("declare void @nl_expect_fail_bool(i32, i32, i32, ptr)\n");
    out.push_str("declare void @nl_print_int(i32)\n");
    out.push_str("declare void @nl_print_long(i64)\n");
    out.push_str("declare void @nl_print_bool(i1 zeroext)\n");
    out.push_str("declare void @nl_print_int_raw(i32)\n");
    out.push_str("declare void @nl_print_long_raw(i64)\n");
    out.push_str("declare void @nl_print_bool_raw(i1 zeroext)\n");
    out.push_str("declare void @nl_print_text(ptr)\n");
    out.push_str("declare void @nl_print_ascii(ptr, i64)\n");
    out.push_str("declare i32 @nl_ascii_compare(ptr, i64, ptr, i64)\n");
    out.push_str("declare i64 @nl_hash_ascii(ptr, i64, i64)\n");
    out.push_str("declare i64 @nl_ascii_format_i64(i64, ptr)\n");
    out.push_str("declare void @nl_ascii_upper_copy(ptr, ptr, i64)\n");
    out.push_str("declare i32 @nl_utf8_count(ptr, i64, ptr)\n");
    out.push_str("declare i64 @nl_utf8_offset(ptr, i64, i64)\n");
    out.push_str("declare i64 @nl_text_upper_copy(ptr, i64, ptr, ptr)\n");
    out.push_str("declare i32 @nl_bytes_are_ascii(ptr, i64)\n");
    out.push_str(
        "declare void @nl_fs_read_string(ptr, ptr, i32, i64, ptr, i64, i32, i64, ptr, ptr, ptr)\n",
    );
    out.push_str("declare void @nl_print_newline()\n");
    out.push_str("declare void @nl_print_arg(ptr)\n");
    out.push_str("declare void @nl_print_set_fd(i32)\n");
    out.push_str("declare void @nl_print_error_prefix()\n");
    out.push_str("declare void @nl_expect_fail_header(i32, i32, i32, ptr)\n");
    out.push_str("declare void @nl_expect_fail_left()\n");
    out.push_str("declare void @nl_expect_fail_right()\n");
    for width in [32, 64] {
        for op in ["sadd", "ssub", "smul"] {
            out.push_str(&format!(
                "declare {{ i{width}, i1 }} @llvm.{op}.with.overflow.i{width}(i{width}, i{width})\n"
            ));
        }
    }
    out.push('\n');
    let mut size_cache = vec![None; program.types.len()];
    out.push_str("%nl.ascii = type <{ ptr, i64 }>\n");
    out.push_str("%nl.text = type <{ ptr, i64, i64 }>\n");
    out.push_str("%nl.bytes = type <{ ptr, i64 }>\n");
    out.push_str("%nl.option.ascii = type { i32, [16 x i8] }\n");
    out.push_str("%nl.option.text = type { i32, [24 x i8] }\n");
    out.push_str("%nl.option.bytes = type { i32, [16 x i8] }\n");
    for (id, ty) in program.types.iter().enumerate().skip(5) {
        match &ty.kind {
            TTypeKind::Refinement { .. }
            | TTypeKind::Id { .. }
            | TTypeKind::Function { .. }
            | TTypeKind::Capability(_) => {}
            TTypeKind::Ascii { .. } | TTypeKind::Text { .. } | TTypeKind::Bytes { .. } => {}
            TTypeKind::Option(inner)
                if matches!(
                    program.types[inner.0].kind,
                    TTypeKind::Ascii { .. } | TTypeKind::Text { .. } | TTypeKind::Bytes { .. }
                ) => {}
            TTypeKind::Struct(fields) => {
                let fields = fields
                    .iter()
                    .map(|field| llvm_type(field.ty, &program.types))
                    .collect::<Vec<_>>()
                    .join(", ");
                out.push_str(&format!(
                    "%nl.ty.{id} = type <{{ {fields} }}> ; {}\n",
                    ty.name
                ));
            }
            TTypeKind::Array { element, capacity } => {
                let mut lanes = collection_lane_types(*element, &program.types)
                    .iter()
                    .map(|lane| format!("[{} x {}]", capacity, llvm_type(*lane, &program.types)))
                    .collect::<Vec<_>>();
                lanes.extend(collection_var_pool_field_types(Ty(id), &program.types));
                out.push_str(&format!(
                    "%nl.ty.{id} = type <{{ {} }}> ; {}\n",
                    lanes.join(", "),
                    ty.name
                ));
            }
            TTypeKind::List { element, capacity } => {
                let mut lanes = vec!["i64".to_owned()];
                lanes.extend(
                    collection_lane_types(*element, &program.types)
                        .iter()
                        .map(|lane| {
                            format!("[{} x {}]", capacity, llvm_type(*lane, &program.types))
                        }),
                );
                lanes.extend(collection_var_pool_field_types(Ty(id), &program.types));
                out.push_str(&format!(
                    "%nl.ty.{id} = type <{{ {} }}> ; {}\n",
                    lanes.join(", "),
                    ty.name
                ));
            }
            TTypeKind::Queue { element, capacity } | TTypeKind::Ring { element, capacity } => {
                let mut lanes = vec!["i64".to_owned(), "i64".to_owned()];
                lanes.extend(
                    collection_lane_types(*element, &program.types)
                        .iter()
                        .map(|lane| {
                            format!("[{} x {}]", capacity, llvm_type(*lane, &program.types))
                        }),
                );
                lanes.extend(collection_var_pool_field_types(Ty(id), &program.types));
                out.push_str(&format!(
                    "%nl.ty.{id} = type <{{ {} }}> ; {}\n",
                    lanes.join(", "),
                    ty.name
                ));
            }
            TTypeKind::Grid {
                element, capacity, ..
            } => {
                let mut lanes = collection_lane_types(*element, &program.types)
                    .iter()
                    .map(|lane| format!("[{} x {}]", capacity, llvm_type(*lane, &program.types)))
                    .collect::<Vec<_>>();
                lanes.extend(collection_var_pool_field_types(Ty(id), &program.types));
                out.push_str(&format!(
                    "%nl.ty.{id} = type <{{ {} }}> ; {}\n",
                    lanes.join(", "),
                    ty.name
                ));
            }
            TTypeKind::Map {
                key,
                value,
                capacity,
            } => {
                let mut fields = vec![
                    "i64".to_owned(),
                    "i64".to_owned(),
                    format!("[{capacity} x i1]"),
                    format!("[{capacity} x i64]"),
                    format!("[{capacity} x i64]"),
                    format!("[{capacity} x {}]", llvm_type(*key, &program.types)),
                    format!("[{capacity} x {}]", llvm_type(*value, &program.types)),
                ];
                if let TTypeKind::Ascii { max_bytes } = program.types[key.0].kind {
                    fields.push(format!("[{capacity} x [{max_bytes} x i8]]"));
                }
                fields.extend(collection_var_pool_field_types(Ty(id), &program.types));
                out.push_str(&format!(
                    "%nl.ty.{id} = type <{{ {} }}> ; {}\n",
                    fields.join(", "),
                    ty.name
                ));
            }
            TTypeKind::Set { key, capacity } => {
                let mut fields = vec![
                    "i64".to_owned(),
                    "i64".to_owned(),
                    format!("[{capacity} x i1]"),
                    format!("[{capacity} x i64]"),
                    format!("[{capacity} x i64]"),
                    format!("[{capacity} x {}]", llvm_type(*key, &program.types)),
                ];
                if let TTypeKind::Ascii { max_bytes } = program.types[key.0].kind {
                    fields.push(format!("[{capacity} x [{max_bytes} x i8]]"));
                }
                out.push_str(&format!(
                    "%nl.ty.{id} = type <{{ {} }}> ; {}\n",
                    fields.join(", "),
                    ty.name
                ));
            }
            TTypeKind::Pool {
                element, capacity, ..
            } => {
                let mut fields = vec![
                    "i64".to_owned(),
                    "i64".to_owned(),
                    format!("[{} x i1]", capacity),
                    format!("[{} x i32]", capacity),
                    format!("[{} x i32]", capacity),
                    "i64".to_owned(),
                ];
                fields.extend(
                    collection_lane_types(*element, &program.types)
                        .iter()
                        .map(|lane| {
                            format!("[{} x {}]", capacity, llvm_type(*lane, &program.types))
                        }),
                );
                fields.extend(collection_var_pool_field_types(Ty(id), &program.types));
                out.push_str(&format!(
                    "%nl.ty.{id} = type <{{ {} }}> ; {}\n",
                    fields.join(", "),
                    ty.name
                ));
            }
            _ => {
                let payload = enum_payload_size(Ty(id), &program.types, &mut size_cache);
                out.push_str(&format!(
                    "%nl.ty.{id} = type {{ i32, [{payload} x i8] }} ; {}\n",
                    ty.name
                ));
            }
        }
    }
    out.push('\n');
    for (id, file) in program.files.iter().enumerate() {
        let encoded = llvm_bytes(file.as_bytes());
        out.push_str(&format!(
            "@.nl.file.{id} = private unnamed_addr constant [{} x i8] c\"{}\", align 1\n",
            file.len() + 1,
            encoded
        ));
    }
    let allow_option = llvm_bytes(b"--allow-overcommit");
    let allow_len = b"--allow-overcommit".len() + 1;
    out.push_str(&format!(
        "@.nl.allow.overcommit = private unnamed_addr constant [{allow_len} x i8] c\"{allow_option}\"\n"
    ));
    for constant in &program.constants {
        if base_type(constant.ty, &program.types) == Ty::Unit {
            continue;
        }
        let initializer = llvm_constant(
            constant.ty,
            &constant.value,
            &program.types,
            &program.functions,
        );
        out.push_str(&format!(
            "@nl.const.{} = private constant {} {}, align 1 ; {} declared at {}:{}:{}\n",
            constant.id,
            llvm_type(constant.ty, &program.types),
            initializer,
            constant.name,
            constant.span.file,
            constant.span.line,
            constant.span.col
        ));
    }
    if !program.globals.is_empty() {
        let mut members = Vec::new();
        let mut initializers = Vec::new();
        let mut cursor = 0usize;
        let mut cache = vec![None; program.types.len()];
        for global in &program.globals {
            let offset = global.offset as usize;
            if offset > cursor {
                let padding = offset - cursor;
                members.push(format!("[{padding} x i8]"));
                initializers.push(format!("[{padding} x i8] zeroinitializer"));
            }
            let ty = llvm_type(global.ty, &program.types);
            members.push(ty.clone());
            let initializer = match &global.initializer {
                TGlobalInitializer::Constant(value) => {
                    llvm_constant(global.ty, value, &program.types, &program.functions)
                }
                TGlobalInitializer::Runtime(_) => "zeroinitializer".to_owned(),
            };
            initializers.push(format!("{ty} {initializer}"));
            cursor = offset.saturating_add(type_size(global.ty, &program.types, &mut cache));
        }
        let total = program.global_state_bytes as usize;
        if total > cursor {
            let padding = total - cursor;
            members.push(format!("[{padding} x i8]"));
            initializers.push(format!("[{padding} x i8] zeroinitializer"));
        }
        out.push_str(&format!(
            "%nl.global.state = type <{{ {} }}>\n@nl.globals = global %nl.global.state <{{ {} }}>, align 8\n",
            members.join(", "),
            initializers.join(", ")
        ));
    }
    let mut expect_sources = Vec::<String>::new();
    for function in &program.functions {
        collect_expect_sources(&function.body, &mut expect_sources);
    }
    expect_sources.sort();
    expect_sources.dedup();
    let expect_ids = expect_sources
        .iter()
        .enumerate()
        .map(|(id, source)| (source.clone(), id))
        .collect::<HashMap<_, _>>();
    for (id, source) in expect_sources.iter().enumerate() {
        let encoded = llvm_bytes(source.as_bytes());
        out.push_str(&format!(
            "@.nl.expect.{id} = private unnamed_addr constant [{} x i8] c\"{}\", align 1\n",
            source.len() + 1,
            encoded
        ));
    }
    let mut print_texts = vec![
        "(".to_owned(),
        ")".to_owned(),
        ", ".to_owned(),
        "()".to_owned(),
        " { ".to_owned(),
        ": ".to_owned(),
        " }".to_owned(),
        "[".to_owned(),
        "queue[".to_owned(),
        "ring[".to_owned(),
        "]".to_owned(),
        "{".to_owned(),
        "pool{".to_owned(),
        ":".to_owned(),
        " => ".to_owned(),
        "}".to_owned(),
    ];
    for ty in program.types.iter().skip(5) {
        print_texts.extend(ty.cases().into_iter().map(|case| case.name));
        if let TTypeKind::Struct(fields) = &ty.kind {
            print_texts.push(ty.name.clone());
            print_texts.extend(fields.iter().map(|field| field.name.clone()));
        }
    }
    print_texts.extend(
        program
            .functions
            .iter()
            .map(|function| function.name.clone()),
    );
    print_texts.extend(stack_entries.iter().map(|entry| entry.name.clone()));
    print_texts.push("<unknown function>".to_owned());
    print_texts.sort();
    print_texts.dedup();
    let print_ids = print_texts
        .iter()
        .enumerate()
        .map(|(id, text)| (text.clone(), id))
        .collect::<HashMap<_, _>>();
    for (id, text) in print_texts.iter().enumerate() {
        let encoded = llvm_bytes(text.as_bytes());
        out.push_str(&format!(
            "@.nl.print.{id} = private unnamed_addr constant [{} x i8] c\"{}\", align 1\n",
            text.len() + 1,
            encoded
        ));
    }
    out.push('\n');
    let entry = program.functions.iter().find(|f| f.name == "main");
    let main_error_type =
        entry.and_then(|function| result_error_type(function.result, &program.types));
    let error_printer_id = main_error_type.map(|_| program.functions.len() + program.globals.len());
    for function in &program.functions {
        let mut emitter = FunctionEmitter::new(program, function, &expect_ids, &print_ids);
        out.push_str(&emitter.emit_function());
        out.push('\n');
        if appendable_ascii_result(function.result, &program.types) && !function.is_test {
            let mut append =
                FunctionEmitter::new_append_variant(program, function, &expect_ids, &print_ids);
            out.push_str(&append.emit_function());
            out.push('\n');
        }
    }
    for global in &program.globals {
        if let TGlobalInitializer::Runtime(value) = &global.initializer {
            let id = program.functions.len() + global.id;
            let init = global_initializer_function(global, value, id);
            let mut emitter = FunctionEmitter::new(program, &init, &expect_ids, &print_ids);
            out.push_str(&emitter.emit_function());
            out.push('\n');
        }
    }
    if let (Some(error_ty), Some(id)) = (main_error_type, error_printer_id) {
        let printer = error_printer_function(id, error_ty);
        let mut emitter = FunctionEmitter::new(program, &printer, &expect_ids, &print_ids);
        out.push_str(&emitter.emit_function());
        out.push('\n');
    }
    out.push_str("define i32 @main(i32 %argc, ptr %argv) {\nentry:\n");
    let main_entry = stack_entries
        .iter()
        .find(|entry| entry.name == "main")
        .or_else(|| stack_entries.first());
    if program.tests.is_empty() {
        let Some(entry) = main_entry else {
            out.push_str("  ret i32 0\n}\n");
            return out;
        };
        let name_id = print_ids[&entry.name];
        out.push_str(&format!(
            "  %nl.ctx = call ptr @nl_context_create(i64 {}, i64 {}, ptr getelementptr inbounds ([{} x i8], ptr @.nl.print.{name_id}, i64 0, i64 0))\n  %nl.top = call ptr @nl_context_base(ptr %nl.ctx)\n",
            entry.reservation_bytes,
            program.recursion_budget_bytes,
            entry.name.len() + 1
        ));
    } else {
        let default = main_entry.expect("tests have a stack reservation");
        let default_name_id = print_ids[&default.name];
        out.push_str("  %nl.test.selected = call i32 @nl_test_selected_index()\n");
        out.push_str("  switch i32 %nl.test.selected, label %nl.stack.select.default [\n");
        for index in 0..program.tests.len() {
            out.push_str(&format!(
                "    i32 {index}, label %nl.stack.select.{index}\n"
            ));
        }
        out.push_str("  ]\n");
        for index in 0..program.tests.len() {
            out.push_str(&format!(
                "nl.stack.select.{index}:\n  br label %nl.stack.select.ready\n"
            ));
        }
        out.push_str("nl.stack.select.default:\n  br label %nl.stack.select.ready\n");
        out.push_str("nl.stack.select.ready:\n");
        let mut bytes_phi = Vec::new();
        let mut name_phi = Vec::new();
        bytes_phi.push(format!(
            "[ {}, %nl.stack.select.default ]",
            default.reservation_bytes
        ));
        name_phi.push(format!(
            "[ getelementptr inbounds ([{} x i8], ptr @.nl.print.{default_name_id}, i64 0, i64 0), %nl.stack.select.default ]",
            default.name.len() + 1
        ));
        for (index, test) in program.tests.iter().enumerate() {
            let entry = stack_entries
                .iter()
                .find(|entry| entry.function_id == test.function_id)
                .expect("test entry reservation exists");
            let name_id = print_ids[&entry.name];
            bytes_phi.push(format!(
                "[ {}, %nl.stack.select.{index} ]",
                entry.reservation_bytes
            ));
            name_phi.push(format!(
                "[ getelementptr inbounds ([{} x i8], ptr @.nl.print.{name_id}, i64 0, i64 0), %nl.stack.select.{index} ]",
                entry.name.len() + 1
            ));
        }
        out.push_str(&format!(
            "  %nl.stack.bytes = phi i64 {}\n  %nl.stack.entry = phi ptr {}\n  %nl.ctx = call ptr @nl_context_create(i64 %nl.stack.bytes, i64 {}, ptr %nl.stack.entry)\n  %nl.top = call ptr @nl_context_base(ptr %nl.ctx)\n",
            bytes_phi.join(", "),
            name_phi.join(", "),
            program.recursion_budget_bytes
        ));
    }
    let capability_mask = (i32::from(program.capabilities.iter().any(|cap| cap == "fs")))
        | (i32::from(program.capabilities.iter().any(|cap| cap == "out")) << 1)
        | (i32::from(program.capabilities.iter().any(|cap| cap == "env")) << 2);
    out.push_str(&format!(
        "  %nl.env = call ptr @nl_env_create(i32 %argc, ptr %argv, i32 {capability_mask})\n"
    ));
    for (id, file) in program.files.iter().enumerate() {
        let len = file.len() + 1;
        out.push_str(&format!("  call void @nl_register_file(i32 {id}, ptr getelementptr inbounds ([{len} x i8], ptr @.nl.file.{id}, i64 0, i64 0))\n"));
    }
    if !program.globals.is_empty() {
        out.push_str(&format!(
            "  %nl.allow.overcommit = call zeroext i1 @nl_has_argument(i32 %argc, ptr %argv, ptr getelementptr inbounds ([{allow_len} x i8], ptr @.nl.allow.overcommit, i64 0, i64 0))\n"
        ));
        out.push_str(&format!(
            "  call void @nl_claim_memory(ptr @nl.globals, i64 {}, i64 {}, i1 zeroext %nl.allow.overcommit)\n",
            program.global_state_bytes, program.job_headroom_bytes
        ));
        for id in &program.global_init_order {
            if matches!(
                program.globals[*id].initializer,
                TGlobalInitializer::Runtime(_)
            ) {
                out.push_str(&format!(
                    "  call void @nl_fn_{}(ptr %nl.ctx, ptr %nl.top)\n",
                    program.functions.len() + id
                ));
            }
        }
    }
    if program.tests.is_empty() {
        let mut entry_handles_exit = false;
        if let Some(entry) = entry {
            if entry.recursive {
                out.push_str(&recursion_check_instruction(&[entry.id], entry.span));
            }
            entry_handles_exit =
                emit_entry_call(&mut out, program, entry, error_printer_id, "nl.main");
        }
        if !entry_handles_exit {
            out.push_str("  call void @nl_env_destroy(ptr %nl.env)\n");
            out.push_str("  call void @nl_context_destroy(ptr %nl.ctx)\n");
            out.push_str("  ret i32 0\n");
        }
        out.push_str("}\n");
    } else {
        out.push_str(
            "  %test.selected = add i32 %nl.test.selected, 0\n  br label %test.dispatch.0\n",
        );
        for (index, test) in program.tests.iter().enumerate() {
            out.push_str(&format!("test.dispatch.{index}:\n"));
            let next = format!("test.dispatch.{}", index + 1);
            let run = format!("test.run.{index}");
            out.push_str(&format!("  %test.is.{index} = icmp eq i32 %test.selected, {index}\n  br i1 %test.is.{index}, label %{run}, label %{next}\n"));
            let test_function = &program.functions[test.function_id];
            if test_function.params.is_empty() {
                out.push_str(&format!("{run}:\n  call void @nl_set_test_mode()\n  %test.result.{index} = call i32 @nl_fn_{}(ptr %nl.ctx, ptr %nl.top)\n  call void @nl_env_destroy(ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 %test.result.{index}\n", test.function_id));
            } else {
                out.push_str(&format!("{run}:\n  call void @nl_set_test_mode()\n  %test.result.{index} = call i32 @nl_fn_{}(ptr %nl.ctx, ptr %nl.top, ptr %nl.env)\n  call void @nl_env_destroy(ptr %nl.env)\n  call void @nl_context_destroy(ptr %nl.ctx)\n  ret i32 %test.result.{index}\n", test.function_id));
            }
        }
        out.push_str(&format!("test.dispatch.{}:\n", program.tests.len()));
        let mut entry_handles_exit = false;
        if let Some(entry) = entry {
            if entry.recursive {
                out.push_str(&recursion_check_instruction(&[entry.id], entry.span));
            }
            entry_handles_exit =
                emit_entry_call(&mut out, program, entry, error_printer_id, "nl.fallback");
        }
        if !entry_handles_exit {
            out.push_str("  call void @nl_env_destroy(ptr %nl.env)\n");
            out.push_str("  call void @nl_context_destroy(ptr %nl.ctx)\n");
            out.push_str("  ret i32 0\n");
        }
        out.push_str("}\n");
    }
    out.push_str("\n!0 = !{!\"branch_weights\", i32 1, i32 2000}\n");
    out
}

fn recursion_check_instruction(targets: &[usize], span: Span) -> String {
    let mut targets = targets.to_vec();
    targets.sort_unstable();
    targets.dedup();
    format!(
        "  call void @nl_recursion_check(ptr %nl.ctx, i64 0, i32 {}, i32 {}, i32 {}) ; nlc.recursion.targets={}\n",
        span.file,
        span.line,
        span.col,
        targets
            .iter()
            .map(usize::to_string)
            .collect::<Vec<_>>()
            .join(",")
    )
}

#[derive(Clone, Debug)]
pub struct StackContract {
    pub function: String,
    pub byte_requirement: u64,
    pub parameters: Vec<String>,
    pub result_placement: String,
    pub span: Span,
    pub reserved_regions: Vec<StackRegion>,
    pub loops: Vec<StackLoop>,
    pub copy_down_sites: Vec<StackCopyDown>,
}

#[derive(Clone, Debug)]
pub struct StackRegion {
    pub name: String,
    pub bytes: u64,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct StackLoop {
    pub growth_bytes_per_iteration: u64,
    pub iteration_limit: Option<u64>,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct StackCopyDown {
    pub name: String,
    pub bytes: u64,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub struct EntryStackReservation {
    pub name: String,
    pub function_id: usize,
    pub required_bytes: Option<u64>,
    pub reservation_bytes: u64,
    pub recursive: bool,
}

pub const STACK_PAGE_BYTES: u64 = 4096;
pub const DATA_STACK_HELPER_MARGIN: u64 = 256;
pub const UNBOUNDED_DATA_STACK_DEFAULT: u64 = 64 * 1024 * 1024;

pub fn data_stack_reservation(required_bytes: Option<u64>) -> u64 {
    let Some(required_bytes) = required_bytes else {
        return UNBOUNDED_DATA_STACK_DEFAULT;
    };
    required_bytes
        .checked_add(DATA_STACK_HELPER_MARGIN)
        .and_then(|bytes| bytes.checked_add(STACK_PAGE_BYTES - 1))
        .map(|bytes| bytes / STACK_PAGE_BYTES * STACK_PAGE_BYTES)
        .unwrap_or(UNBOUNDED_DATA_STACK_DEFAULT)
        .max(STACK_PAGE_BYTES)
}

fn expr_is_place_for_contract(expr: &TExpr) -> bool {
    match &expr.kind {
        TExprKind::Local(_) | TExprKind::Global(_) | TExprKind::Constant(_) => true,
        TExprKind::Field { receiver, .. } | TExprKind::Index { receiver, .. } => {
            expr_is_place_for_contract(receiver)
        }
        _ => false,
    }
}

fn static_ascii_length(expr: &TExpr, types: &[TType]) -> Option<usize> {
    match &expr.kind {
        TExprKind::ByteString(bytes) => Some(bytes.len()),
        TExprKind::AsciiEmpty => Some(0),
        TExprKind::Binary {
            op: BinaryOp::Add,
            left,
            right,
            ..
        } if matches!(types[left.ty.0].kind, TTypeKind::Ascii { .. })
            && matches!(types[right.ty.0].kind, TTypeKind::Ascii { .. }) =>
        {
            static_ascii_length(left, types)?.checked_add(static_ascii_length(right, types)?)
        }
        TExprKind::AsciiUpper(value) | TExprKind::AsciiCast(value) | TExprKind::Take(value) => {
            static_ascii_length(value, types)
        }
        TExprKind::AsciiFormat(value) => match value.kind {
            TExprKind::Integer(value) => {
                let digits = if value == 0 {
                    1
                } else {
                    value.unsigned_abs().ilog10() as usize + 1
                };
                Some(digits + usize::from(value < 0))
            }
            _ => None,
        },
        _ => None,
    }
}

pub fn stack_contracts(program: &TProgram) -> Vec<StackContract> {
    fn large_local_bytes(
        block: &TBlock,
        types: &[TType],
        growing_ascii: &std::collections::HashSet<usize>,
        forwarded_return: Option<usize>,
    ) -> u64 {
        let mut total = 0u64;
        for statement in &block.statements {
            match &statement.kind {
                TStmtKind::Let { id, ty, value, .. }
                    if is_large_type(*ty, types) && Some(*id) != forwarded_return =>
                {
                    let bytes = if matches!(types[ty.0].kind, TTypeKind::Ascii { .. })
                        && !growing_ascii.contains(id)
                    {
                        static_ascii_length(value, types)
                            .map(|length| 16usize.saturating_add(length))
                            .unwrap_or_else(|| stack_storage_size(*ty, types))
                    } else {
                        stack_storage_size(*ty, types)
                    };
                    total = total.saturating_add(bytes as u64);
                }
                TStmtKind::If {
                    then_block,
                    else_block,
                    ..
                } => {
                    total = total.saturating_add(large_local_bytes(
                        then_block,
                        types,
                        growing_ascii,
                        forwarded_return,
                    ));
                    if let Some(other) = else_block {
                        total = total.saturating_add(large_local_bytes(
                            other,
                            types,
                            growing_ascii,
                            forwarded_return,
                        ));
                    }
                }
                TStmtKind::For { body, .. } | TStmtKind::Block(body) => {
                    total = total.saturating_add(large_local_bytes(
                        body,
                        types,
                        growing_ascii,
                        forwarded_return,
                    ));
                }
                TStmtKind::ForEach {
                    collection, body, ..
                } => {
                    let element_ty = match &types[collection.ty.0].kind {
                        TTypeKind::Array { element, .. }
                        | TTypeKind::List { element, .. }
                        | TTypeKind::Queue { element, .. }
                        | TTypeKind::Ring { element, .. }
                        | TTypeKind::Grid { element, .. }
                        | TTypeKind::Pool { element, .. }
                        | TTypeKind::Map { value: element, .. }
                        | TTypeKind::Set { key: element, .. } => Some(*element),
                        _ => None,
                    };
                    if element_ty.is_some_and(|ty| is_large_type(ty, types)) {
                        let ty = element_ty.unwrap();
                        total = total.saturating_add(stack_storage_size(ty, types) as u64);
                    }
                    total = total.saturating_add(large_local_bytes(
                        body,
                        types,
                        growing_ascii,
                        forwarded_return,
                    ));
                }
                _ => {}
            }
        }
        total
    }

    fn type_bytes(ty: Ty, types: &[TType]) -> u64 {
        stack_storage_size(ty, types) as u64
    }

    fn large_storage(ty: Ty, count: u64, types: &[TType]) -> u64 {
        if is_large_type(ty, types) {
            type_bytes(ty, types).saturating_mul(count)
        } else {
            0
        }
    }

    fn equality_scratch(ty: Ty, types: &[TType], active: &mut [bool]) -> u64 {
        if active[ty.0] {
            return 0;
        }
        active[ty.0] = true;
        let own = match &types[ty.0].kind {
            TTypeKind::Array { element, .. }
            | TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. }
            | TTypeKind::Grid { element, .. }
            | TTypeKind::Pool { element, .. } => large_storage(ty, 2, types)
                .saturating_add(equality_scratch(*element, types, active)),
            TTypeKind::Map { key, value, .. } => large_storage(ty, 2, types)
                .saturating_add(equality_scratch(*key, types, active))
                .saturating_add(equality_scratch(*value, types, active)),
            TTypeKind::Set { key, .. } => {
                large_storage(ty, 2, types).saturating_add(equality_scratch(*key, types, active))
            }
            TTypeKind::Struct(fields) => fields.iter().fold(0u64, |total, field| {
                total.saturating_add(equality_scratch(field.ty, types, active))
            }),
            TTypeKind::Enum(_) | TTypeKind::Option(_) | TTypeKind::Result(_, _) => {
                let payload_counts = match &types[ty.0].kind {
                    TTypeKind::Enum(cases) => cases
                        .iter()
                        .map(|case| {
                            case.payload
                                .iter()
                                .filter(|field| **field != Ty::Unit)
                                .count()
                        })
                        .sum::<usize>(),
                    TTypeKind::Option(payload) => usize::from(*payload != Ty::Unit),
                    TTypeKind::Result(ok, error) => {
                        usize::from(*ok != Ty::Unit) + usize::from(*error != Ty::Unit)
                    }
                    _ => unreachable!(),
                };
                let fields = match &types[ty.0].kind {
                    TTypeKind::Enum(cases) => cases
                        .iter()
                        .flat_map(|case| case.payload.iter().copied())
                        .collect::<Vec<_>>(),
                    TTypeKind::Option(payload) => vec![*payload],
                    TTypeKind::Result(ok, error) => vec![*ok, *error],
                    _ => unreachable!(),
                };
                let own = large_storage(ty, payload_counts as u64 * 2, types);
                fields.into_iter().fold(own, |total, field| {
                    total.saturating_add(equality_scratch(field, types, active))
                })
            }
            _ => 0,
        };
        active[ty.0] = false;
        own
    }

    fn print_scratch(ty: Ty, types: &[TType], active: &mut [bool]) -> u64 {
        if active[ty.0] {
            return 0;
        }
        active[ty.0] = true;
        let own = match &types[ty.0].kind {
            TTypeKind::Array { element, .. }
            | TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. }
            | TTypeKind::Grid { element, .. }
            | TTypeKind::Pool { element, .. } => {
                large_storage(ty, 1, types).saturating_add(print_scratch(*element, types, active))
            }
            TTypeKind::Map { key, value, .. } => large_storage(ty, 1, types)
                .saturating_add(print_scratch(*key, types, active))
                .saturating_add(print_scratch(*value, types, active)),
            TTypeKind::Set { key, .. } => {
                large_storage(ty, 1, types).saturating_add(print_scratch(*key, types, active))
            }
            TTypeKind::Struct(fields) => fields.iter().fold(0u64, |total, field| {
                total.saturating_add(print_scratch(field.ty, types, active))
            }),
            TTypeKind::Enum(cases) => cases
                .iter()
                .flat_map(|case| case.payload.iter().copied())
                .fold(0u64, |total, field| {
                    if field == Ty::Unit {
                        total
                    } else {
                        total
                            .saturating_add(large_storage(ty, 1, types))
                            .saturating_add(print_scratch(field, types, active))
                    }
                }),
            _ => 0,
        };
        active[ty.0] = false;
        own
    }

    fn expression_scratch(expr: &TExpr, types: &[TType]) -> u64 {
        let mut own = 0u64;
        match &expr.kind {
            TExprKind::Call { target, args, .. } => {
                if matches!(target, CallTarget::Function(_)) && is_large_type(expr.ty, types) {
                    own = own.saturating_add(stack_storage_size(expr.ty, types) as u64);
                }
                // Large pointer arguments can need both a source temporary and a
                // by-pointer staging destination. A large struct collection element
                // also needs lane gathering, so count those even when they are places.
                own = own.saturating_add(
                    args.iter()
                        .filter(|arg| {
                            is_large_type(arg.ty, types)
                                && (matches!(types[arg.ty.0].kind, TTypeKind::Struct(_))
                                    || !expr_is_place_for_contract(arg))
                        })
                        .map(|arg| {
                            let bytes = stack_storage_size(arg.ty, types) as u64;
                            if matches!(types[arg.ty.0].kind, TTypeKind::Struct(_))
                                && expr_is_place_for_contract(arg)
                            {
                                bytes
                            } else {
                                bytes.saturating_mul(2)
                            }
                        })
                        .sum::<u64>(),
                );
                if matches!(target, CallTarget::Sort { .. } | CallTarget::SortBy { .. }) {
                    if let Some(collection) = args.first() {
                        own = own.saturating_add(stack_storage_size(collection.ty, types) as u64);
                    }
                }
                if matches!(target, CallTarget::Print) {
                    if let Some(arg) = args.first() {
                        own = own.saturating_add(print_scratch(
                            arg.ty,
                            types,
                            &mut vec![false; types.len()],
                        ));
                    }
                }
                for arg in args {
                    own = own.saturating_add(expression_scratch(arg, types));
                }
            }
            TExprKind::IndirectCall { callee, args, .. } => {
                if is_large_type(expr.ty, types) {
                    own = own.saturating_add(stack_storage_size(expr.ty, types) as u64);
                }
                own = own.saturating_add(
                    args.iter()
                        .filter(|arg| {
                            is_large_type(arg.ty, types)
                                && (matches!(types[arg.ty.0].kind, TTypeKind::Struct(_))
                                    || !expr_is_place_for_contract(arg))
                        })
                        .map(|arg| {
                            let bytes = stack_storage_size(arg.ty, types) as u64;
                            if matches!(types[arg.ty.0].kind, TTypeKind::Struct(_))
                                && expr_is_place_for_contract(arg)
                            {
                                bytes
                            } else {
                                bytes.saturating_mul(2)
                            }
                        })
                        .sum::<u64>(),
                );
                own = own.saturating_add(expression_scratch(callee, types));
                for arg in args {
                    own = own.saturating_add(expression_scratch(arg, types));
                }
            }
            TExprKind::Construct { args, .. } => {
                own = own.saturating_add(large_storage(expr.ty, 1, types));
                for arg in args {
                    own = own.saturating_add(expression_scratch(arg, types));
                }
            }
            TExprKind::Method { receiver, .. } | TExprKind::OptionalToLong(receiver) => {
                own = own.saturating_add(expression_scratch(receiver, types));
            }
            TExprKind::AsciiUpper(value)
            | TExprKind::TextUpper(value)
            | TExprKind::AsciiFormat(value)
            | TExprKind::AsciiCast(value)
            | TExprKind::BytesView(value)
            | TExprKind::TextConvert { value, .. }
            | TExprKind::Take(value)
            | TExprKind::AsciiFit { value, .. } => {
                own = own.saturating_add(expression_scratch(value, types));
            }
            TExprKind::AsciiTryAppend { receiver, argument } => {
                own = own.saturating_add(expression_scratch(receiver, types));
                own = own.saturating_add(expression_scratch(argument, types));
                own = own.saturating_add(large_storage(argument.ty, 1, types));
            }
            TExprKind::AsciiEmpty | TExprKind::TextEmpty | TExprKind::BytesEmpty => {}
            TExprKind::Field { receiver, .. } => {
                own = own.saturating_add(expression_scratch(receiver, types));
            }
            TExprKind::Index {
                receiver,
                index,
                grid,
                ..
            } => {
                // Reading a struct from a structure-of-arrays collection gathers
                // its lanes into a temporary, even though the source is a place.
                if matches!(types[expr.ty.0].kind, TTypeKind::Struct(_))
                    && is_large_type(expr.ty, types)
                {
                    own = own.saturating_add(large_storage(expr.ty, 1, types));
                }
                if is_large_type(receiver.ty, types) && !expr_is_place_for_contract(receiver) {
                    own = own.saturating_add(stack_storage_size(receiver.ty, types) as u64);
                }
                own = own.saturating_add(expression_scratch(receiver, types));
                own = own.saturating_add(expression_scratch(index, types));
                if let Some(grid) = grid {
                    own = own.saturating_add(expression_scratch(&grid.x, types));
                    own = own.saturating_add(expression_scratch(&grid.y, types));
                }
            }
            TExprKind::Fill { value, .. } => {
                own = own
                    .saturating_add(expression_scratch(value, types))
                    .saturating_add(large_storage(expr.ty, 1, types));
            }
            TExprKind::Convert { value, .. }
            | TExprKind::Fit { value, .. }
            | TExprKind::ToLong(value)
            | TExprKind::Cast { value, .. }
            | TExprKind::Unary { value, .. } => {
                own = own.saturating_add(expression_scratch(value, types));
            }
            TExprKind::Try { value, .. } => {
                own = own.saturating_add(expression_scratch(value, types));
                if is_large_type(value.ty, types) && !expr_is_place_for_contract(value) {
                    own = own.saturating_add(large_storage(value.ty, 1, types));
                }
            }
            TExprKind::CollectionOp { receiver, args, .. }
            | TExprKind::PoolOp { receiver, args, .. }
            | TExprKind::MapOp { receiver, args, .. }
            | TExprKind::SetOp { receiver, args, .. } => {
                own = own.saturating_add(expression_scratch(receiver, types));
                for arg in args {
                    own = own.saturating_add(expression_scratch(arg, types));
                }
            }
            TExprKind::StructConstruct { fields } => {
                own = own.saturating_add(large_storage(expr.ty, 1, types));
                for (_, value) in fields {
                    own = own.saturating_add(expression_scratch(value, types));
                }
            }
            TExprKind::OptionalCall { receiver, args, .. } => {
                own = own.saturating_add(expression_scratch(receiver, types));
                if is_large_type(receiver.ty, types) && !expr_is_place_for_contract(receiver) {
                    own = own.saturating_add(large_storage(receiver.ty, 1, types));
                }
                for arg in args {
                    own = own.saturating_add(expression_scratch(arg, types));
                }
                own = own.saturating_add(
                    args.iter()
                        .filter(|arg| {
                            is_large_type(arg.ty, types)
                                && (matches!(types[arg.ty.0].kind, TTypeKind::Struct(_))
                                    || !expr_is_place_for_contract(arg))
                        })
                        .map(|arg| {
                            let bytes = stack_storage_size(arg.ty, types) as u64;
                            if matches!(types[arg.ty.0].kind, TTypeKind::Struct(_))
                                && expr_is_place_for_contract(arg)
                            {
                                bytes
                            } else {
                                bytes.saturating_mul(2)
                            }
                        })
                        .sum::<u64>(),
                );
                if is_large_type(expr.ty, types) {
                    own = own.saturating_add(stack_storage_size(expr.ty, types) as u64);
                }
            }
            TExprKind::Coalesce { option, fallback } => {
                own = own.saturating_add(expression_scratch(option, types));
                own = own.saturating_add(expression_scratch(fallback, types));
                if is_large_type(option.ty, types) && !expr_is_place_for_contract(option) {
                    own = own.saturating_add(large_storage(option.ty, 1, types));
                }
            }
            TExprKind::Match { scrutinee, arms } => {
                own = own.saturating_add(expression_scratch(scrutinee, types));
                if is_large_type(scrutinee.ty, types)
                    && (!expr_is_place_for_contract(scrutinee)
                        || matches!(types[scrutinee.ty.0].kind, TTypeKind::Struct(_)))
                {
                    own = own.saturating_add(large_storage(scrutinee.ty, 1, types));
                }
                for arm in arms {
                    if let TPattern::Case {
                        ty,
                        case_index,
                        bindings,
                    } = &arm.pattern
                    {
                        let payload = &types[ty.0].cases()[*case_index].payload;
                        for (binding, field) in bindings.iter().zip(payload) {
                            if binding.is_some() && is_large_type(*field, types) {
                                own = own.saturating_add(large_storage(*field, 1, types));
                            }
                        }
                    }
                    own = own.saturating_add(block_scratch(&arm.body, types));
                }
            }
            TExprKind::Return(value) => {
                if let Some(value) = value {
                    own = own.saturating_add(expression_scratch(value, types));
                }
            }
            TExprKind::Binary {
                op, left, right, ..
            } => {
                own = own.saturating_add(expression_scratch(left, types));
                own = own.saturating_add(expression_scratch(right, types));
                if matches!(op, BinaryOp::Eq | BinaryOp::Ne) {
                    own = own.saturating_add(equality_scratch(
                        left.ty,
                        types,
                        &mut vec![false; types.len()],
                    ));
                }
            }
            TExprKind::TextSlice {
                receiver,
                start,
                end,
            }
            | TExprKind::BytesSlice {
                receiver,
                start,
                end,
            } => {
                own = own.saturating_add(expression_scratch(receiver, types));
                own = own.saturating_add(expression_scratch(start, types));
                own = own.saturating_add(expression_scratch(end, types));
            }
            TExprKind::If {
                condition,
                then_block,
                else_block,
            } => {
                own = own.saturating_add(expression_scratch(condition, types));
                own = own.saturating_add(block_scratch(then_block, types));
                if let Some(other) = else_block {
                    own = own.saturating_add(block_scratch(other, types));
                }
            }
            TExprKind::Unit
            | TExprKind::Integer(_)
            | TExprKind::Bool(_)
            | TExprKind::ByteString(_)
            | TExprKind::Local(_)
            | TExprKind::Global(_)
            | TExprKind::Constant(_)
            | TExprKind::FunctionValue(_)
            | TExprKind::EmptyArray
            | TExprKind::EmptyGrid
            | TExprKind::EmptyList
            | TExprKind::EmptyPool
            | TExprKind::EmptyMap
            | TExprKind::EmptySet
            | TExprKind::EmptyQueue
            | TExprKind::EmptyRing
            | TExprKind::LoopExit(_) => {}
        }
        own
    }

    fn expression_scratch_in_destination(expr: &TExpr, types: &[TType]) -> u64 {
        let scratch = expression_scratch(expr, types);
        let destination_bytes = match &expr.kind {
            TExprKind::Call { .. }
            | TExprKind::IndirectCall { .. }
            | TExprKind::Construct { .. }
            | TExprKind::StructConstruct { .. }
            | TExprKind::OptionalCall { .. } => large_storage(expr.ty, 1, types),
            _ => 0,
        };
        scratch.saturating_sub(destination_bytes)
    }

    fn append_expression_scratch(expr: &TExpr, types: &[TType]) -> u64 {
        match &expr.kind {
            TExprKind::Call {
                target: CallTarget::Function(_),
                args,
                ..
            } if matches!(types[expr.ty.0].kind, TTypeKind::Ascii { .. }) => {
                args.iter().map(|arg| expression_scratch(arg, types)).sum()
            }
            TExprKind::IndirectCall { callee, args, .. }
                if matches!(types[expr.ty.0].kind, TTypeKind::Ascii { .. }) =>
            {
                expression_scratch(callee, types).saturating_add(
                    args.iter()
                        .map(|arg| expression_scratch(arg, types))
                        .sum::<u64>(),
                )
            }
            TExprKind::Binary {
                op: BinaryOp::Add,
                left,
                right,
                ..
            } if matches!(types[expr.ty.0].kind, TTypeKind::Ascii { .. }) => {
                append_expression_scratch(left, types)
                    .saturating_add(append_expression_scratch(right, types))
            }
            _ => expression_scratch(expr, types),
        }
    }

    fn block_scratch(block: &TBlock, types: &[TType]) -> u64 {
        let mut total = 0u64;
        for statement in &block.statements {
            match &statement.kind {
                TStmtKind::Assign {
                    place,
                    op: AssignOp::Add,
                    value,
                    ..
                } if matches!(types[place.ty.0].kind, TTypeKind::Ascii { .. }) => {
                    total = total.saturating_add(append_expression_scratch(value, types))
                }
                TStmtKind::Let { ty, value, .. }
                    if matches!(types[ty.0].kind, TTypeKind::Ascii { .. }) =>
                {
                    total = total.saturating_add(append_expression_scratch(value, types))
                }
                TStmtKind::Let { value, .. } => {
                    total = total.saturating_add(expression_scratch_in_destination(value, types));
                }
                TStmtKind::Assign {
                    place,
                    ty,
                    op,
                    value,
                    ..
                } => {
                    total = total.saturating_add(expression_scratch(value, types));
                    if *op != AssignOp::Add && is_growing_payload(place.ty, types) {
                        // Copy-down keeps the old builder in its live region while
                        // the replacement is built above it.
                        total = total.saturating_add(stack_storage_size(*ty, types) as u64);
                    }
                }
                TStmtKind::Expr(value) | TStmtKind::Discard(value) => {
                    total = total.saturating_add(expression_scratch(value, types));
                }
                TStmtKind::Return(value) => {
                    if let Some(value) = value {
                        let scratch = if matches!(types[value.ty.0].kind, TTypeKind::Ascii { .. }) {
                            append_expression_scratch(value, types)
                        } else {
                            expression_scratch_in_destination(value, types)
                        };
                        total = total.saturating_add(scratch);
                    }
                }
                TStmtKind::If {
                    condition,
                    then_block,
                    else_block,
                } => {
                    total = total.saturating_add(expression_scratch(condition, types));
                    total = total.saturating_add(block_scratch(then_block, types));
                    if let Some(other) = else_block {
                        total = total.saturating_add(block_scratch(other, types));
                    }
                }
                TStmtKind::For {
                    start, end, body, ..
                } => {
                    total = total.saturating_add(expression_scratch(start, types));
                    total = total.saturating_add(expression_scratch(end, types));
                    total = total.saturating_add(block_scratch(body, types));
                }
                TStmtKind::ForEach {
                    collection, body, ..
                } => {
                    total = total.saturating_add(expression_scratch(collection, types));
                    total = total.saturating_add(block_scratch(body, types));
                }
                TStmtKind::Block(body) => total = total.saturating_add(block_scratch(body, types)),
                TStmtKind::Expect { kind, .. } => match kind {
                    TExpectKind::Bool(value) => {
                        total = total.saturating_add(expression_scratch(value, types));
                    }
                    TExpectKind::Compare { left, right, .. } => {
                        total = total
                            .saturating_add(expression_scratch(left, types))
                            .saturating_add(expression_scratch(right, types))
                            .saturating_add(equality_scratch(
                                left.ty,
                                types,
                                &mut vec![false; types.len()],
                            ));
                        if !matches!(base_type(left.ty, types), Ty::Int | Ty::Long | Ty::Bool) {
                            total = total.saturating_add(print_scratch(
                                left.ty,
                                types,
                                &mut vec![false; types.len()],
                            ));
                            total = total.saturating_add(print_scratch(
                                right.ty,
                                types,
                                &mut vec![false; types.len()],
                            ));
                        }
                    }
                    TExpectKind::StackPeak { .. } => {}
                },
                TStmtKind::Break | TStmtKind::Continue => {}
            }
        }
        if let Some(tail) = &block.tail {
            let scratch = if matches!(types[tail.ty.0].kind, TTypeKind::Ascii { .. }) {
                append_expression_scratch(tail, types)
            } else {
                expression_scratch_in_destination(tail, types)
            };
            total = total.saturating_add(scratch);
        }
        total
    }

    // Direct and resolved indirect edges share the typed call graph.
    fn requirement(
        id: usize,
        program: &TProgram,
        bases: &[u64],
        memo: &mut [Option<u64>],
        visiting: &mut [bool],
    ) -> u64 {
        if let Some(value) = memo[id] {
            return value;
        }
        if visiting[id] {
            // T19 permits cycles only when every function in the cycle is
            // marked recursive and proves that no data-stack region is live
            // across its recursive call. Count one traversal of that cycle;
            // deeper native recursion therefore does not multiply data use.
            return 0;
        }
        visiting[id] = true;
        let child = program.call_graph[id]
            .iter()
            .map(|edge| requirement(edge.target, program, bases, memo, visiting))
            .max()
            .unwrap_or(0);
        visiting[id] = false;
        let total = bases[id].saturating_add(child);
        memo[id] = Some(total);
        total
    }

    let bases = program
        .functions
        .iter()
        .map(|function| {
            let growing_ascii = growing_ascii_locals(function, program);
            large_local_bytes(
                &function.body,
                &program.types,
                &growing_ascii,
                returned_lazy_local(function, &program.types).or_else(|| {
                    returned_ascii_builder_local(function, &program.types, &growing_ascii)
                }),
            )
            .saturating_add(block_scratch(&function.body, &program.types))
        })
        .collect::<Vec<_>>();
    let mut memo = vec![None; program.functions.len()];
    let mut visiting = vec![false; program.functions.len()];
    program
        .functions
        .iter()
        .enumerate()
        .map(|(id, function)| {
            let parameters = function
                .params
                .iter()
                .map(|param| {
                    let mode = match param.mode {
                        ParamMode::Read => "read",
                        ParamMode::Write => "write",
                        ParamMode::Grow => "grow",
                    };
                    let size = stack_storage_size(param.ty, &program.types);
                    let placement = if is_large_type(param.ty, &program.types)
                        || matches!(program.types[param.ty.0].kind, TTypeKind::Pool { .. })
                    {
                        "pointer"
                    } else {
                        "value"
                    };
                    let type_contract = match &program.types[param.ty.0].kind {
                        TTypeKind::Function {
                            supports_append,
                            data_stack_requirement,
                            ..
                        } => format!(
                            "; function targets need up to {data_stack_requirement} data-stack bytes{}",
                            if *supports_append { "; supports append mode" } else { "" }
                        ),
                        _ => String::new(),
                    };
                    format!(
                        "{}: {mode} {placement} ({size} bytes{type_contract})",
                        param.name
                    )
                })
                .collect();
            let result_bytes = stack_storage_size(function.result, &program.types);
            let result_placement = if is_large_type(function.result, &program.types) {
                if appendable_ascii_result(function.result, &program.types) {
                    format!(
                        "caller destination ({result_bytes} bytes); fresh and append modes"
                    )
                } else {
                    format!("caller destination ({result_bytes} bytes)")
                }
            } else if function.result == Ty::Unit {
                "none".to_owned()
            } else {
                "value".to_owned()
            };
            let (reserved_regions, loops, copy_down_sites) =
                function_stack_details(function, program);
            StackContract {
                function: function.name.clone(),
                byte_requirement: requirement(id, program, &bases, &mut memo, &mut visiting),
                parameters,
                result_placement,
                span: function.span,
                reserved_regions,
                loops,
                copy_down_sites,
            }
        })
        .collect()
}

fn growing_payload_bytes(ty: Ty, types: &[TType]) -> u64 {
    match &types[ty.0].kind {
        TTypeKind::Ascii { max_bytes } | TTypeKind::Bytes { max_bytes } => *max_bytes as u64,
        TTypeKind::Text { max_bytes, .. } => *max_bytes as u64,
        _ => 0,
    }
}

fn is_growing_payload(ty: Ty, types: &[TType]) -> bool {
    matches!(
        types[ty.0].kind,
        TTypeKind::Ascii { .. } | TTypeKind::Text { .. } | TTypeKind::Bytes { .. }
    )
}

fn constant_loop_bound(start: &TExpr, end: &TExpr, inclusive: bool) -> Option<u64> {
    let (TExprKind::Integer(start), TExprKind::Integer(end)) = (&start.kind, &end.kind) else {
        return None;
    };
    let span = end.checked_sub(*start)?;
    if span < 0 {
        return Some(0);
    }
    let iterations = span.checked_add(i128::from(inclusive))?;
    u64::try_from(iterations).ok()
}

fn collection_iteration_bound(ty: Ty, types: &[TType]) -> Option<u64> {
    let capacity = match &types[ty.0].kind {
        TTypeKind::Array { capacity, .. }
        | TTypeKind::List { capacity, .. }
        | TTypeKind::Queue { capacity, .. }
        | TTypeKind::Ring { capacity, .. }
        | TTypeKind::Grid { capacity, .. }
        | TTypeKind::Pool { capacity, .. }
        | TTypeKind::Map { capacity, .. }
        | TTypeKind::Set { capacity, .. } => *capacity,
        _ => return None,
    };
    Some(capacity as u64)
}

fn block_growth_per_iteration(block: &TBlock, types: &[TType]) -> u64 {
    let mut growth = 0u64;
    for statement in &block.statements {
        match &statement.kind {
            TStmtKind::Assign {
                place,
                op: AssignOp::Add,
                value,
                ..
            } if is_growing_payload(place.ty, types) => {
                growth = growth.saturating_add(growing_payload_bytes(value.ty, types));
            }
            TStmtKind::Expr(expr) | TStmtKind::Discard(expr) => {
                growth = growth.saturating_add(expr_growth(expr, types));
            }
            TStmtKind::If {
                then_block,
                else_block,
                ..
            } => {
                growth = growth.saturating_add(block_growth_per_iteration(then_block, types));
                if let Some(other) = else_block {
                    growth = growth.saturating_add(block_growth_per_iteration(other, types));
                }
            }
            TStmtKind::For {
                start,
                end,
                inclusive,
                body,
                ..
            } => {
                let nested = block_growth_per_iteration(body, types);
                let iterations = constant_loop_bound(start, end, *inclusive).unwrap_or(u64::MAX);
                growth = growth.saturating_add(nested.saturating_mul(iterations));
            }
            TStmtKind::ForEach {
                collection, body, ..
            } => {
                let nested = block_growth_per_iteration(body, types);
                let iterations =
                    collection_iteration_bound(collection.ty, types).unwrap_or(u64::MAX);
                growth = growth.saturating_add(nested.saturating_mul(iterations));
            }
            TStmtKind::Block(body) => {
                growth = growth.saturating_add(block_growth_per_iteration(body, types));
            }
            _ => {}
        }
    }
    growth
}

fn expr_growth(expr: &TExpr, types: &[TType]) -> u64 {
    match &expr.kind {
        TExprKind::AsciiTryAppend { argument, .. } => growing_payload_bytes(argument.ty, types),
        _ => 0,
    }
}

fn function_stack_details(
    function: &TFunction,
    program: &TProgram,
) -> (Vec<StackRegion>, Vec<StackLoop>, Vec<StackCopyDown>) {
    let returned_builder = returned_ascii_builder_local(
        function,
        &program.types,
        &growing_ascii_locals(function, program),
    );
    fn walk(
        block: &TBlock,
        types: &[TType],
        names: &mut HashMap<usize, String>,
        regions: &mut Vec<StackRegion>,
        loops: &mut Vec<StackLoop>,
        copy_down_sites: &mut Vec<StackCopyDown>,
        returned_builder: Option<usize>,
    ) {
        for statement in &block.statements {
            match &statement.kind {
                TStmtKind::Let { id, name, ty, .. } => {
                    names.insert(*id, name.clone());
                    let bytes = stack_storage_size(*ty, types) as u64;
                    if is_large_type(*ty, types) && Some(*id) != returned_builder {
                        regions.push(StackRegion {
                            name: name.clone(),
                            bytes,
                            span: statement.span,
                        });
                    }
                }
                TStmtKind::Assign { place, ty, op, .. }
                    if *op != AssignOp::Add && is_growing_payload(place.ty, types) =>
                {
                    let bytes = (stack_storage_size(*ty, types) as u64).saturating_mul(2);
                    let name = names
                        .get(&place.root)
                        .cloned()
                        .unwrap_or_else(|| format!("local {}", place.root));
                    if bytes / 2 > 64 * 1024 {
                        regions.push(StackRegion {
                            name: format!("copy-down temporary for {name}"),
                            bytes: bytes / 2,
                            span: statement.span,
                        });
                    }
                    copy_down_sites.push(StackCopyDown {
                        name,
                        bytes,
                        span: statement.span,
                    });
                }
                TStmtKind::If {
                    then_block,
                    else_block,
                    ..
                } => {
                    walk(
                        then_block,
                        types,
                        names,
                        regions,
                        loops,
                        copy_down_sites,
                        returned_builder,
                    );
                    if let Some(other) = else_block {
                        walk(
                            other,
                            types,
                            names,
                            regions,
                            loops,
                            copy_down_sites,
                            returned_builder,
                        );
                    }
                }
                TStmtKind::For {
                    start,
                    end,
                    inclusive,
                    body,
                    ..
                } => {
                    loops.push(StackLoop {
                        growth_bytes_per_iteration: block_growth_per_iteration(body, types),
                        iteration_limit: constant_loop_bound(start, end, *inclusive),
                        span: statement.span,
                    });
                    walk(
                        body,
                        types,
                        names,
                        regions,
                        loops,
                        copy_down_sites,
                        returned_builder,
                    );
                }
                TStmtKind::ForEach {
                    collection, body, ..
                } => {
                    loops.push(StackLoop {
                        growth_bytes_per_iteration: block_growth_per_iteration(body, types),
                        iteration_limit: collection_iteration_bound(collection.ty, types),
                        span: statement.span,
                    });
                    walk(
                        body,
                        types,
                        names,
                        regions,
                        loops,
                        copy_down_sites,
                        returned_builder,
                    );
                }
                TStmtKind::Block(inner) => {
                    walk(
                        inner,
                        types,
                        names,
                        regions,
                        loops,
                        copy_down_sites,
                        returned_builder,
                    );
                }
                _ => {}
            }
        }
    }

    let mut names = function
        .params
        .iter()
        .map(|param| (param.id, param.name.clone()))
        .collect::<HashMap<_, _>>();
    let mut regions = Vec::new();
    let mut loops = Vec::new();
    let mut copy_down_sites = Vec::new();
    walk(
        &function.body,
        &program.types,
        &mut names,
        &mut regions,
        &mut loops,
        &mut copy_down_sites,
        returned_builder,
    );
    (regions, loops, copy_down_sites)
}

pub fn entry_stack_reservations(
    program: &TProgram,
    contracts: &[StackContract],
) -> Vec<EntryStackReservation> {
    let global_initializer_requirement = program
        .globals
        .iter()
        .filter_map(|global| match global.initializer {
            TGlobalInitializer::Runtime(ref expression) => Some(expression),
            TGlobalInitializer::Constant(_) => None,
        })
        .map(|expression| match &expression.kind {
            TExprKind::Call {
                target: CallTarget::Function(id),
                ..
            } => contracts
                .get(*id)
                .map(|contract| contract.byte_requirement)
                .unwrap_or(u64::MAX),
            TExprKind::IndirectCall { callee, .. } => match &program.types[callee.ty.0].kind {
                TTypeKind::Function {
                    data_stack_requirement,
                    ..
                } => *data_stack_requirement,
                _ => 0,
            },
            _ => 0,
        })
        .max()
        .unwrap_or(0);

    let mut entries = Vec::new();
    let recursive_reachable = {
        let mut reverse = vec![Vec::new(); program.functions.len()];
        for (caller, edges) in program.call_graph.iter().enumerate() {
            for edge in edges {
                reverse[edge.target].push(caller);
            }
        }
        let mut reachable = program
            .functions
            .iter()
            .map(|function| function.recursive)
            .collect::<Vec<_>>();
        let mut pending = reachable
            .iter()
            .enumerate()
            .filter_map(|(id, recursive)| recursive.then_some(id))
            .collect::<Vec<_>>();
        while let Some(target) = pending.pop() {
            for caller in &reverse[target] {
                if !reachable[*caller] {
                    reachable[*caller] = true;
                    pending.push(*caller);
                }
            }
        }
        reachable
    };
    if let Some(main) = program
        .functions
        .iter()
        .find(|function| function.name == "main")
    {
        entries.push(("main".to_owned(), main.id));
    }
    entries.extend(
        program
            .tests
            .iter()
            .map(|test| (format!("test '{}'", test.name), test.function_id)),
    );
    entries
        .into_iter()
        .map(|(name, function_id)| {
            let function_requirement = contracts
                .get(function_id)
                .map(|contract| contract.byte_requirement)
                .unwrap_or(u64::MAX);
            let bound = function_requirement.max(global_initializer_requirement);
            let raw_bound = (bound != u64::MAX).then_some(bound);
            let required = raw_bound.and_then(|bytes| bytes.checked_add(DATA_STACK_HELPER_MARGIN));
            let reservation = data_stack_reservation(raw_bound);
            let recursive = recursive_reachable[function_id];
            EntryStackReservation {
                name,
                function_id,
                required_bytes: required,
                reservation_bytes: reservation,
                recursive,
            }
        })
        .collect()
}

pub fn apply_function_type_stack_contracts(program: &mut TProgram, contracts: &[StackContract]) {
    for (type_id, targets) in program.function_type_targets.iter().enumerate() {
        let requirement = targets
            .iter()
            .filter_map(|target| contracts.get(*target))
            .map(|contract| contract.byte_requirement)
            .max()
            .unwrap_or(0);
        if let TTypeKind::Function {
            data_stack_requirement,
            ..
        } = &mut program.types[type_id].kind
        {
            *data_stack_requirement = requirement;
        }
    }
}

fn collect_expect_sources(block: &TBlock, sources: &mut Vec<String>) {
    for stmt in &block.statements {
        match &stmt.kind {
            TStmtKind::Expect { source, kind } => {
                sources.push(source.clone());
                match kind {
                    TExpectKind::Bool(value) => collect_expect_sources_expr(value, sources),
                    TExpectKind::Compare { left, right, .. } => {
                        collect_expect_sources_expr(left, sources);
                        collect_expect_sources_expr(right, sources);
                    }
                    TExpectKind::StackPeak { .. } => {}
                }
            }
            TStmtKind::Let { value, .. }
            | TStmtKind::Assign { value, .. }
            | TStmtKind::Expr(value) => collect_expect_sources_expr(value, sources),
            TStmtKind::Return(value) => {
                if let Some(value) = value {
                    collect_expect_sources_expr(value, sources);
                }
            }
            TStmtKind::If {
                condition,
                then_block,
                else_block,
            } => {
                collect_expect_sources_expr(condition, sources);
                collect_expect_sources(then_block, sources);
                if let Some(other) = else_block {
                    collect_expect_sources(other, sources);
                }
            }
            TStmtKind::For {
                start, end, body, ..
            } => {
                collect_expect_sources_expr(start, sources);
                collect_expect_sources_expr(end, sources);
                collect_expect_sources(body, sources)
            }
            TStmtKind::ForEach {
                collection, body, ..
            } => {
                collect_expect_sources_expr(collection, sources);
                collect_expect_sources(body, sources);
            }
            TStmtKind::Discard(value) => collect_expect_sources_expr(value, sources),
            TStmtKind::Block(body) => collect_expect_sources(body, sources),
            TStmtKind::Break | TStmtKind::Continue => {}
        }
    }
    if let Some(tail) = &block.tail {
        collect_expect_sources_expr(tail, sources);
    }
}

fn global_initializer_function(global: &TGlobal, value: &TExpr, id: usize) -> TFunction {
    TFunction {
        id,
        name: format!("__nl_init_{}", global.name),
        params: Vec::new(),
        result: Ty::Unit,
        body: TBlock {
            statements: vec![TStmt {
                kind: TStmtKind::Assign {
                    place: TPlace {
                        root: global_root(global.id),
                        fields: Vec::new(),
                        path: Vec::new(),
                        ty: global.ty,
                    },
                    ty: global.ty,
                    op: AssignOp::Set,
                    operator_span: global.span,
                    value: value.clone(),
                },
                span: global.span,
            }],
            tail: None,
            falls_through: true,
            scope_id: 0,
            span: global.span,
        },
        span: global.span,
        is_test: false,
        recursive: false,
    }
}

fn collect_expect_sources_expr(expr: &TExpr, sources: &mut Vec<String>) {
    match &expr.kind {
        TExprKind::Call { args, .. } => {
            for arg in args {
                collect_expect_sources_expr(arg, sources);
            }
        }
        TExprKind::IndirectCall { callee, args, .. } => {
            collect_expect_sources_expr(callee, sources);
            for arg in args {
                collect_expect_sources_expr(arg, sources);
            }
        }
        TExprKind::Construct { args, .. } => {
            for arg in args {
                collect_expect_sources_expr(arg, sources);
            }
        }
        TExprKind::Method { receiver, .. } => collect_expect_sources_expr(receiver, sources),
        TExprKind::AsciiUpper(value)
        | TExprKind::TextUpper(value)
        | TExprKind::AsciiFormat(value)
        | TExprKind::AsciiCast(value)
        | TExprKind::BytesView(value)
        | TExprKind::TextConvert { value, .. }
        | TExprKind::Take(value)
        | TExprKind::AsciiFit { value, .. } => collect_expect_sources_expr(value, sources),
        TExprKind::AsciiTryAppend { receiver, argument } => {
            collect_expect_sources_expr(receiver, sources);
            collect_expect_sources_expr(argument, sources);
        }
        TExprKind::Index {
            receiver,
            index,
            grid,
            ..
        } => {
            collect_expect_sources_expr(receiver, sources);
            if let Some(grid) = grid {
                collect_expect_sources_expr(&grid.x, sources);
                collect_expect_sources_expr(&grid.y, sources);
            } else {
                collect_expect_sources_expr(index, sources);
            }
        }
        TExprKind::Fill { value, .. } => collect_expect_sources_expr(value, sources),
        TExprKind::TextSlice {
            receiver,
            start,
            end,
        }
        | TExprKind::BytesSlice {
            receiver,
            start,
            end,
        } => {
            collect_expect_sources_expr(receiver, sources);
            collect_expect_sources_expr(start, sources);
            collect_expect_sources_expr(end, sources);
        }
        TExprKind::CollectionOp { receiver, args, .. }
        | TExprKind::PoolOp { receiver, args, .. }
        | TExprKind::MapOp { receiver, args, .. }
        | TExprKind::SetOp { receiver, args, .. } => {
            collect_expect_sources_expr(receiver, sources);
            for arg in args {
                collect_expect_sources_expr(arg, sources);
            }
        }
        TExprKind::OptionalToLong(receiver) => collect_expect_sources_expr(receiver, sources),
        TExprKind::Field { receiver, .. } => collect_expect_sources_expr(receiver, sources),
        TExprKind::StructConstruct { fields } => {
            for (_, value) in fields {
                collect_expect_sources_expr(value, sources);
            }
        }
        TExprKind::Convert { value, .. } | TExprKind::Fit { value, .. } => {
            collect_expect_sources_expr(value, sources)
        }
        TExprKind::OptionalCall { receiver, args, .. } => {
            collect_expect_sources_expr(receiver, sources);
            for arg in args {
                collect_expect_sources_expr(arg, sources);
            }
        }
        TExprKind::Try { value, .. } => collect_expect_sources_expr(value, sources),
        TExprKind::Coalesce { option, fallback } => {
            collect_expect_sources_expr(option, sources);
            collect_expect_sources_expr(fallback, sources);
        }
        TExprKind::Match { scrutinee, arms } => {
            collect_expect_sources_expr(scrutinee, sources);
            for arm in arms {
                collect_expect_sources(&arm.body, sources);
            }
        }
        TExprKind::Return(value) => {
            if let Some(value) = value {
                collect_expect_sources_expr(value, sources);
            }
        }
        TExprKind::ToLong(value)
        | TExprKind::Cast { value, .. }
        | TExprKind::Unary { value, .. } => {
            collect_expect_sources_expr(value, sources);
        }
        TExprKind::Binary { left, right, .. } => {
            collect_expect_sources_expr(left, sources);
            collect_expect_sources_expr(right, sources);
        }
        TExprKind::If {
            condition,
            then_block,
            else_block,
        } => {
            collect_expect_sources_expr(condition, sources);
            collect_expect_sources(then_block, sources);
            if let Some(other) = else_block {
                collect_expect_sources(other, sources);
            }
        }
        TExprKind::Integer(_)
        | TExprKind::Bool(_)
        | TExprKind::ByteString(_)
        | TExprKind::Unit
        | TExprKind::Local(_)
        | TExprKind::Global(_)
        | TExprKind::Constant(_)
        | TExprKind::FunctionValue(_)
        | TExprKind::LoopExit(_)
        | TExprKind::EmptyArray
        | TExprKind::EmptyList
        | TExprKind::EmptyPool
        | TExprKind::EmptyMap
        | TExprKind::EmptySet
        | TExprKind::EmptyGrid
        | TExprKind::EmptyQueue
        | TExprKind::EmptyRing
        | TExprKind::AsciiEmpty
        | TExprKind::TextEmpty
        | TExprKind::BytesEmpty => {}
    }
}

fn llvm_bytes(bytes: &[u8]) -> String {
    let mut out = String::new();
    for b in bytes.iter().copied().chain(std::iter::once(0)) {
        if (0x20..=0x7e).contains(&b) && b != b'"' && b != b'\\' {
            out.push(b as char);
        } else {
            out.push_str(&format!("\\{b:02X}"));
        }
    }
    out
}

fn enum_payload_size(ty: Ty, types: &[TType], cache: &mut [Option<usize>]) -> usize {
    types[ty.0]
        .cases()
        .iter()
        .map(|case| {
            case.payload
                .iter()
                .map(|field| type_size(*field, types, cache))
                .sum()
        })
        .max()
        .unwrap_or(0)
}

fn collection_lane_types(element: Ty, types: &[TType]) -> Vec<Ty> {
    match &types[element.0].kind {
        TTypeKind::Struct(fields) => fields.iter().map(|field| field.ty).collect(),
        _ => vec![element],
    }
}

#[derive(Clone)]
struct CollectionVarClass {
    bytes: usize,
    storage_field: usize,
    next_field: usize,
    free_count_field: usize,
    free_stack_field: usize,
}

#[derive(Clone)]
struct CollectionVarLane {
    lane: usize,
    ty: Ty,
    classes: Vec<CollectionVarClass>,
}

fn collection_capacity(ty: Ty, types: &[TType]) -> Option<usize> {
    match types.get(ty.0)?.kind {
        TTypeKind::Array { capacity, .. }
        | TTypeKind::List { capacity, .. }
        | TTypeKind::Queue { capacity, .. }
        | TTypeKind::Ring { capacity, .. }
        | TTypeKind::Grid { capacity, .. }
        | TTypeKind::Pool { capacity, .. }
        | TTypeKind::Map { capacity, .. }
        | TTypeKind::Set { capacity, .. } => Some(capacity),
        _ => None,
    }
}

fn collection_var_lanes(ty: Ty, types: &[TType]) -> Vec<CollectionVarLane> {
    let capacity = collection_capacity(ty, types).unwrap_or(0);
    let source = match types[ty.0].kind {
        TTypeKind::Array { element, .. }
        | TTypeKind::List { element, .. }
        | TTypeKind::Queue { element, .. }
        | TTypeKind::Ring { element, .. }
        | TTypeKind::Grid { element, .. }
        | TTypeKind::Pool { element, .. } => Some(element),
        TTypeKind::Map { value, .. } => Some(value),
        _ => None,
    };
    if capacity == 0 {
        return Vec::new();
    }
    let Some(source) = source else {
        return Vec::new();
    };
    let mut layouts = Vec::new();
    for lane in growing_collection_lanes(ty, types).unwrap_or_default() {
        let _ = source;
        let mut classes = Vec::new();
        for bytes in lane.class_bytes {
            classes.push(CollectionVarClass {
                bytes,
                storage_field: 0,
                next_field: 0,
                free_count_field: 0,
                free_stack_field: 0,
            });
        }
        layouts.push(CollectionVarLane {
            lane: lane.lane,
            ty: lane.ty,
            classes,
        });
    }
    let kind = &types[ty.0].kind;
    let mut field = match kind {
        TTypeKind::Array { .. } | TTypeKind::Grid { .. } => {
            collection_lane_types(source, types).len()
        }
        TTypeKind::List { .. } => 1 + collection_lane_types(source, types).len(),
        TTypeKind::Queue { .. } | TTypeKind::Ring { .. } => {
            2 + collection_lane_types(source, types).len()
        }
        TTypeKind::Pool { .. } => 6 + collection_lane_types(source, types).len(),
        TTypeKind::Map { key, .. } => {
            7 + usize::from(matches!(types[key.0].kind, TTypeKind::Ascii { .. }))
        }
        TTypeKind::Set { .. } => return Vec::new(),
        _ => return Vec::new(),
    };
    for lane in &mut layouts {
        for class in &mut lane.classes {
            class.storage_field = field;
            class.next_field = field + 1;
            class.free_count_field = field + 2;
            class.free_stack_field = field + 3;
            field += 4;
        }
    }
    layouts
}

fn collection_var_lane(ty: Ty, types: &[TType], lane: usize) -> Option<CollectionVarLane> {
    collection_var_lanes(ty, types)
        .into_iter()
        .find(|layout| layout.lane == lane)
}

fn collection_var_pool_field_types(ty: Ty, types: &[TType]) -> Vec<String> {
    let capacity = collection_capacity(ty, types).unwrap_or(0);
    let mut fields = Vec::new();
    for lane in collection_var_lanes(ty, types) {
        for class in lane.classes {
            fields.extend([
                format!("[{capacity} x [{} x i8]]", class.bytes),
                "i64".to_owned(),
                "i64".to_owned(),
                format!("[{capacity} x i64]"),
            ]);
        }
    }
    fields
}

fn collection_var_pool_extra_size(ty: Ty, types: &[TType]) -> usize {
    let capacity = collection_capacity(ty, types).unwrap_or(0);
    collection_var_lanes(ty, types)
        .into_iter()
        .flat_map(|lane| lane.classes)
        .map(|class| {
            capacity
                .saturating_mul(class.bytes)
                .saturating_add(16)
                .saturating_add(capacity.saturating_mul(8))
        })
        .fold(0usize, usize::saturating_add)
}

fn collection_element_type(collection: Ty, types: &[TType]) -> Ty {
    match types[collection.0].kind {
        TTypeKind::Array { element, .. }
        | TTypeKind::List { element, .. }
        | TTypeKind::Queue { element, .. }
        | TTypeKind::Ring { element, .. }
        | TTypeKind::Grid { element, .. }
        | TTypeKind::Pool { element, .. } => element,
        TTypeKind::Map { value, .. } => value,
        TTypeKind::Set { key, .. } => key,
        _ => unreachable!("collection element type requested for a non-collection"),
    }
}

fn type_size(ty: Ty, types: &[TType], cache: &mut [Option<usize>]) -> usize {
    match ty {
        Ty::Int => 4,
        Ty::Long => 8,
        Ty::Bool => 1,
        Ty::Unit | Ty::Never => 0,
        Ty(id) => {
            if let Some(size) = cache[id] {
                return size;
            }
            let size = match &types[id].kind {
                TTypeKind::Refinement { base, .. } => type_size(*base, types, cache),
                TTypeKind::Ascii { .. } | TTypeKind::Bytes { .. } => 16,
                TTypeKind::Text { .. } => 24,
                TTypeKind::Struct(fields) => fields
                    .iter()
                    .map(|field| type_size(field.ty, types, cache))
                    .sum(),
                TTypeKind::Array { element, capacity } => collection_lane_types(*element, types)
                    .iter()
                    .map(|lane| type_size(*lane, types, cache).saturating_mul(*capacity))
                    .sum::<usize>()
                    .saturating_add(collection_var_pool_extra_size(Ty(id), types)),
                TTypeKind::List { element, capacity } => 8usize
                    .saturating_add(
                        collection_lane_types(*element, types)
                            .iter()
                            .map(|lane| type_size(*lane, types, cache).saturating_mul(*capacity))
                            .sum::<usize>(),
                    )
                    .saturating_add(collection_var_pool_extra_size(Ty(id), types)),
                TTypeKind::Queue { element, capacity } | TTypeKind::Ring { element, capacity } => {
                    16usize
                        .saturating_add(
                            collection_lane_types(*element, types)
                                .iter()
                                .map(|lane| {
                                    type_size(*lane, types, cache).saturating_mul(*capacity)
                                })
                                .sum::<usize>(),
                        )
                        .saturating_add(collection_var_pool_extra_size(Ty(id), types))
                }
                TTypeKind::Grid {
                    element, capacity, ..
                } => collection_lane_types(*element, types)
                    .iter()
                    .map(|lane| type_size(*lane, types, cache).saturating_mul(*capacity))
                    .sum::<usize>()
                    .saturating_add(collection_var_pool_extra_size(Ty(id), types)),
                TTypeKind::Map {
                    key,
                    value,
                    capacity,
                } => {
                    let key_storage = match types[key.0].kind {
                        TTypeKind::Ascii { max_bytes } => capacity.saturating_mul(max_bytes),
                        _ => 0,
                    };
                    16usize
                        .saturating_add(
                            capacity.saturating_mul(
                                17usize
                                    .saturating_add(type_size(*key, types, cache))
                                    .saturating_add(type_size(*value, types, cache)),
                            ),
                        )
                        .saturating_add(key_storage)
                        .saturating_add(collection_var_pool_extra_size(Ty(id), types))
                }
                TTypeKind::Set { key, capacity } => {
                    let key_storage = match types[key.0].kind {
                        TTypeKind::Ascii { max_bytes } => capacity.saturating_mul(max_bytes),
                        _ => 0,
                    };
                    16usize
                        .saturating_add(
                            capacity.saturating_mul(
                                17usize.saturating_add(type_size(*key, types, cache)),
                            ),
                        )
                        .saturating_add(key_storage)
                        .saturating_add(collection_var_pool_extra_size(Ty(id), types))
                }
                TTypeKind::Pool {
                    element, capacity, ..
                } => 24usize
                    .saturating_add(capacity.saturating_mul(9))
                    .saturating_add(
                        collection_lane_types(*element, types)
                            .iter()
                            .map(|lane| type_size(*lane, types, cache).saturating_mul(*capacity))
                            .sum::<usize>(),
                    )
                    .saturating_add(collection_var_pool_extra_size(Ty(id), types)),
                TTypeKind::Id { .. } | TTypeKind::Capability(_) => 8,
                TTypeKind::Function { .. } => 8,
                _ => {
                    let payload = enum_payload_size(ty, types, cache);
                    (4 + payload + 3) & !3
                }
            };
            cache[id] = Some(size);
            size
        }
    }
}

fn is_large_type(ty: Ty, types: &[TType]) -> bool {
    contains_lazy_collection(ty, types, &mut vec![false; types.len()])
        || contains_growing_value(ty, types, &mut vec![false; types.len()])
        || type_size(ty, types, &mut vec![None; types.len()]) > 4_096
}

// Values containing collections with unused capacity must travel by address.
// An LLVM aggregate load/store would read or write the whole capacity even
// when only the collection header or a few elements are live.
fn contains_lazy_collection(ty: Ty, types: &[TType], active: &mut [bool]) -> bool {
    if ty.0 < 5 || active[ty.0] {
        return false;
    }
    active[ty.0] = true;
    let contains = match &types[ty.0].kind {
        TTypeKind::List { .. }
        | TTypeKind::Queue { .. }
        | TTypeKind::Ring { .. }
        | TTypeKind::Map { .. }
        | TTypeKind::Set { .. }
        | TTypeKind::Pool { .. } => true,
        TTypeKind::Array { element, .. } | TTypeKind::Grid { element, .. } => {
            contains_lazy_collection(*element, types, active)
                || contains_growing_value(*element, types, &mut vec![false; types.len()])
        }
        TTypeKind::Struct(fields) => fields
            .iter()
            .any(|field| contains_lazy_collection(field.ty, types, active)),
        TTypeKind::Option(inner) => contains_lazy_collection(*inner, types, active),
        TTypeKind::Result(ok, err) => {
            contains_lazy_collection(*ok, types, active)
                || contains_lazy_collection(*err, types, active)
        }
        TTypeKind::Enum(cases) => cases.iter().any(|case| {
            case.payload
                .iter()
                .any(|field| contains_lazy_collection(*field, types, active))
        }),
        TTypeKind::Refinement { base, .. } => contains_lazy_collection(*base, types, active),
        _ => false,
    };
    active[ty.0] = false;
    contains
}

fn contains_growing_value(ty: Ty, types: &[TType], active: &mut [bool]) -> bool {
    if ty.0 < 5 || active[ty.0] {
        return false;
    }
    active[ty.0] = true;
    let contains = match &types[ty.0].kind {
        TTypeKind::Ascii { .. } | TTypeKind::Text { .. } | TTypeKind::Bytes { .. } => true,
        TTypeKind::Array { element, .. } | TTypeKind::Grid { element, .. } => {
            contains_growing_value(*element, types, active)
        }
        TTypeKind::Struct(fields) => fields
            .iter()
            .any(|field| contains_growing_value(field.ty, types, active)),
        TTypeKind::Option(inner) => contains_growing_value(*inner, types, active),
        TTypeKind::Result(ok, err) => {
            contains_growing_value(*ok, types, active)
                || contains_growing_value(*err, types, active)
        }
        TTypeKind::Enum(cases) => cases.iter().any(|case| {
            case.payload
                .iter()
                .any(|field| contains_growing_value(*field, types, active))
        }),
        TTypeKind::Map { key, .. } | TTypeKind::Set { key, .. } => {
            matches!(types[key.0].kind, TTypeKind::Ascii { .. })
        }
        _ => false,
    };
    active[ty.0] = false;
    contains
}

fn growing_value_extra(ty: Ty, types: &[TType], active: &mut [bool]) -> usize {
    if ty.0 < 5 || active[ty.0] {
        return 0;
    }
    active[ty.0] = true;
    let extra = match &types[ty.0].kind {
        TTypeKind::Ascii { max_bytes } | TTypeKind::Bytes { max_bytes } => *max_bytes,
        TTypeKind::Text { max_bytes, .. } => *max_bytes,
        TTypeKind::Struct(fields) => fields.iter().fold(0usize, |total, field| {
            total.saturating_add(growing_value_extra(field.ty, types, active))
        }),
        TTypeKind::Option(inner) => growing_value_extra(*inner, types, active),
        TTypeKind::Result(ok, err) => {
            growing_value_extra(*ok, types, active).max(growing_value_extra(*err, types, active))
        }
        TTypeKind::Enum(cases) => cases
            .iter()
            .map(|case| {
                case.payload.iter().fold(0usize, |total, field| {
                    total.saturating_add(growing_value_extra(*field, types, active))
                })
            })
            .max()
            .unwrap_or(0),
        _ => 0,
    };
    active[ty.0] = false;
    extra
}

fn stack_storage_size(ty: Ty, types: &[TType]) -> usize {
    type_size(ty, types, &mut vec![None; types.len()]).saturating_add(growing_value_extra(
        ty,
        types,
        &mut vec![false; types.len()],
    ))
}

fn local_root(expr: &TExpr) -> Option<usize> {
    match &expr.kind {
        TExprKind::Local(id) => Some(*id),
        TExprKind::Field { receiver, .. } | TExprKind::Index { receiver, .. } => {
            local_root(receiver)
        }
        _ => None,
    }
}

fn returned_lazy_local(function: &TFunction, types: &[TType]) -> Option<usize> {
    if function.is_test
        || !contains_lazy_collection(function.result, types, &mut vec![false; types.len()])
        || contains_growing_value(function.result, types, &mut vec![false; types.len()])
    {
        return None;
    }
    let TExprKind::Local(id) = &function.body.tail.as_deref()?.kind else {
        return None;
    };
    let mut matching_local = false;
    for statement in &function.body.statements {
        match &statement.kind {
            TStmtKind::Let {
                id: local,
                ty,
                value,
                ..
            } => {
                matching_local |= *local == *id
                    && *ty == function.result
                    && !matches!(value.kind, TExprKind::Take(_));
            }
            TStmtKind::Assign { .. } | TStmtKind::Expr(_) | TStmtKind::Discard(_) => {}
            TStmtKind::Return(_)
            | TStmtKind::If { .. }
            | TStmtKind::For { .. }
            | TStmtKind::ForEach { .. }
            | TStmtKind::Block(_)
            | TStmtKind::Break
            | TStmtKind::Continue
            | TStmtKind::Expect { .. } => return None,
        }
    }
    matching_local.then_some(*id)
}

fn returned_ascii_builder_local(
    function: &TFunction,
    types: &[TType],
    growing_ascii: &std::collections::HashSet<usize>,
) -> Option<usize> {
    if function.is_test || !matches!(types.get(function.result.0)?.kind, TTypeKind::Ascii { .. }) {
        return None;
    }
    let TExprKind::Local(id) = &function.body.tail.as_deref()?.kind else {
        return None;
    };
    if !growing_ascii.contains(id) {
        return None;
    }
    function
        .body
        .statements
        .iter()
        .find_map(|statement| match &statement.kind {
            TStmtKind::Let {
                id: local,
                ty,
                value,
                ..
            } if *local == *id
                && matches!(types.get(ty.0)?.kind, TTypeKind::Ascii { .. })
                && matches!(value.kind, TExprKind::AsciiEmpty) =>
            {
                Some(*id)
            }
            _ => None,
        })
}

fn result_ascii_payload(ty: Ty, types: &[TType]) -> Option<Ty> {
    match types.get(ty.0).map(|definition| &definition.kind) {
        Some(TTypeKind::Result(ok, _))
            if matches!(
                types.get(ok.0).map(|definition| &definition.kind),
                Some(TTypeKind::Ascii { .. })
            ) =>
        {
            Some(*ok)
        }
        _ => None,
    }
}

fn appendable_ascii_result(ty: Ty, types: &[TType]) -> bool {
    matches!(
        types.get(ty.0).map(|definition| &definition.kind),
        Some(TTypeKind::Ascii { .. })
    ) || result_ascii_payload(ty, types).is_some()
}

fn returned_result_ascii_builder(function: &TFunction, types: &[TType]) -> Option<usize> {
    if result_ascii_payload(function.result, types).is_none() {
        return None;
    }
    fn collect_empty(block: &TBlock, empty: &mut std::collections::HashSet<usize>) {
        for statement in &block.statements {
            match &statement.kind {
                TStmtKind::Let { id, value, .. } if matches!(value.kind, TExprKind::AsciiEmpty) => {
                    empty.insert(*id);
                }
                TStmtKind::If {
                    then_block,
                    else_block,
                    ..
                } => {
                    collect_empty(then_block, empty);
                    if let Some(other) = else_block {
                        collect_empty(other, empty);
                    }
                }
                TStmtKind::For { body, .. }
                | TStmtKind::ForEach { body, .. }
                | TStmtKind::Block(body) => collect_empty(body, empty),
                _ => {}
            }
        }
    }
    fn returned_id(expr: &TExpr) -> Option<usize> {
        let TExprKind::Construct {
            case_index: 0,
            args,
        } = &expr.kind
        else {
            return None;
        };
        match args.first().map(|arg| &arg.kind) {
            Some(TExprKind::Local(id)) => Some(*id),
            _ => None,
        }
    }
    fn find_return(block: &TBlock) -> Option<usize> {
        for statement in &block.statements {
            match &statement.kind {
                TStmtKind::Return(Some(value)) => {
                    if let Some(id) = returned_id(value) {
                        return Some(id);
                    }
                }
                TStmtKind::If {
                    then_block,
                    else_block,
                    ..
                } => {
                    if let Some(id) = find_return(then_block) {
                        return Some(id);
                    }
                    if let Some(id) = else_block.as_ref().and_then(find_return) {
                        return Some(id);
                    }
                }
                TStmtKind::For { body, .. }
                | TStmtKind::ForEach { body, .. }
                | TStmtKind::Block(body) => {
                    if let Some(id) = find_return(body) {
                        return Some(id);
                    }
                }
                _ => {}
            }
        }
        block.tail.as_deref().and_then(returned_id)
    }
    let mut empty = std::collections::HashSet::new();
    collect_empty(&function.body, &mut empty);
    find_return(&function.body).filter(|id| empty.contains(id))
}

fn expression_uses_local_root(expr: &TExpr, root: usize) -> bool {
    if local_root(expr) == Some(root) {
        return true;
    }
    match &expr.kind {
        TExprKind::Call { args, .. }
        | TExprKind::Construct { args, .. }
        | TExprKind::CollectionOp { args, .. }
        | TExprKind::PoolOp { args, .. }
        | TExprKind::MapOp { args, .. }
        | TExprKind::SetOp { args, .. } => args
            .iter()
            .any(|value| expression_uses_local_root(value, root)),
        TExprKind::IndirectCall { callee, args, .. } => {
            expression_uses_local_root(callee, root)
                || args
                    .iter()
                    .any(|value| expression_uses_local_root(value, root))
        }
        TExprKind::OptionalCall { receiver, args, .. } => {
            expression_uses_local_root(receiver, root)
                || args
                    .iter()
                    .any(|value| expression_uses_local_root(value, root))
        }
        TExprKind::AsciiUpper(value)
        | TExprKind::AsciiFormat(value)
        | TExprKind::AsciiCast(value)
        | TExprKind::Take(value)
        | TExprKind::OptionalToLong(value)
        | TExprKind::Method {
            receiver: value, ..
        }
        | TExprKind::Field {
            receiver: value, ..
        }
        | TExprKind::ToLong(value)
        | TExprKind::Cast { value, .. }
        | TExprKind::Unary { value, .. }
        | TExprKind::Convert { value, .. }
        | TExprKind::Fit { value, .. }
        | TExprKind::Try { value, .. }
        | TExprKind::AsciiFit { value, .. } => expression_uses_local_root(value, root),
        TExprKind::AsciiTryAppend { receiver, argument } => {
            expression_uses_local_root(receiver, root) || expression_uses_local_root(argument, root)
        }
        TExprKind::Index {
            receiver,
            index,
            grid,
            ..
        } => {
            expression_uses_local_root(receiver, root)
                || expression_uses_local_root(index, root)
                || grid.as_ref().is_some_and(|grid| {
                    expression_uses_local_root(&grid.x, root)
                        || expression_uses_local_root(&grid.y, root)
                })
        }
        TExprKind::Binary { left, right, .. } => {
            expression_uses_local_root(left, root) || expression_uses_local_root(right, root)
        }
        TExprKind::Coalesce { option, fallback } => {
            expression_uses_local_root(option, root) || expression_uses_local_root(fallback, root)
        }
        TExprKind::StructConstruct { fields } => fields
            .iter()
            .any(|(_, value)| expression_uses_local_root(value, root)),
        TExprKind::Match { scrutinee, arms } => {
            expression_uses_local_root(scrutinee, root)
                || arms.iter().any(|arm| {
                    arm.body
                        .tail
                        .as_deref()
                        .is_some_and(|tail| expression_uses_local_root(tail, root))
                        || arm
                            .body
                            .statements
                            .iter()
                            .any(|statement| match &statement.kind {
                                TStmtKind::Let { value, .. }
                                | TStmtKind::Assign { value, .. }
                                | TStmtKind::Expr(value)
                                | TStmtKind::Discard(value) => {
                                    expression_uses_local_root(value, root)
                                }
                                TStmtKind::Return(Some(value)) => {
                                    expression_uses_local_root(value, root)
                                }
                                _ => false,
                            })
                })
        }
        TExprKind::If {
            condition,
            then_block,
            else_block,
        } => {
            expression_uses_local_root(condition, root)
                || then_block
                    .tail
                    .as_deref()
                    .is_some_and(|tail| expression_uses_local_root(tail, root))
                || else_block.as_ref().is_some_and(|block| {
                    block
                        .tail
                        .as_deref()
                        .is_some_and(|tail| expression_uses_local_root(tail, root))
                })
        }
        _ => false,
    }
}

fn growing_ascii_locals(
    function: &TFunction,
    program: &TProgram,
) -> std::collections::HashSet<usize> {
    fn mark_args(
        args: &[TExpr],
        modes: impl Iterator<Item = ParamMode>,
        types: &[TType],
        growing: &mut std::collections::HashSet<usize>,
    ) {
        for (arg, mode) in args.iter().zip(modes) {
            if mode == ParamMode::Grow && matches!(types[arg.ty.0].kind, TTypeKind::Ascii { .. }) {
                if let Some(root) = local_root(arg) {
                    growing.insert(root);
                }
            }
        }
    }

    fn visit_expr(
        expr: &TExpr,
        program: &TProgram,
        growing: &mut std::collections::HashSet<usize>,
        moves: &mut Vec<(usize, usize)>,
    ) {
        match &expr.kind {
            TExprKind::Call { target, args, .. } => {
                if let CallTarget::Function(id) = target {
                    mark_args(
                        args,
                        program.functions[*id].params.iter().map(|p| p.mode),
                        &program.types,
                        growing,
                    );
                }
                for arg in args {
                    visit_expr(arg, program, growing, moves);
                }
            }
            TExprKind::IndirectCall {
                callee,
                args,
                params,
                ..
            } => {
                mark_args(args, params.iter().map(|p| p.mode), &program.types, growing);
                visit_expr(callee, program, growing, moves);
                for arg in args {
                    visit_expr(arg, program, growing, moves);
                }
            }
            TExprKind::OptionalCall {
                receiver,
                function_id,
                args,
                ..
            } => {
                mark_args(
                    args,
                    program.functions[*function_id]
                        .params
                        .iter()
                        .skip(1)
                        .map(|p| p.mode),
                    &program.types,
                    growing,
                );
                visit_expr(receiver, program, growing, moves);
                for arg in args {
                    visit_expr(arg, program, growing, moves);
                }
            }
            TExprKind::AsciiTryAppend { receiver, argument } => {
                if let Some(root) = local_root(receiver) {
                    growing.insert(root);
                }
                visit_expr(receiver, program, growing, moves);
                visit_expr(argument, program, growing, moves);
            }
            TExprKind::AsciiUpper(value)
            | TExprKind::TextUpper(value)
            | TExprKind::AsciiFormat(value)
            | TExprKind::AsciiCast(value)
            | TExprKind::BytesView(value)
            | TExprKind::TextConvert { value, .. }
            | TExprKind::Take(value)
            | TExprKind::OptionalToLong(value)
            | TExprKind::Fill { value, .. }
            | TExprKind::Convert { value, .. }
            | TExprKind::Fit { value, .. }
            | TExprKind::Try { value, .. }
            | TExprKind::ToLong(value)
            | TExprKind::Cast { value, .. }
            | TExprKind::Unary { value, .. } => visit_expr(value, program, growing, moves),
            TExprKind::AsciiFit { value, .. } => visit_expr(value, program, growing, moves),
            TExprKind::TextSlice {
                receiver,
                start,
                end,
            }
            | TExprKind::BytesSlice {
                receiver,
                start,
                end,
            } => {
                visit_expr(receiver, program, growing, moves);
                visit_expr(start, program, growing, moves);
                visit_expr(end, program, growing, moves);
            }
            TExprKind::Method { receiver, .. } | TExprKind::Field { receiver, .. } => {
                visit_expr(receiver, program, growing, moves)
            }
            TExprKind::Index {
                receiver,
                index,
                grid,
                ..
            } => {
                visit_expr(receiver, program, growing, moves);
                visit_expr(index, program, growing, moves);
                if let Some(grid) = grid {
                    visit_expr(&grid.x, program, growing, moves);
                    visit_expr(&grid.y, program, growing, moves);
                }
            }
            TExprKind::Construct { args, .. }
            | TExprKind::CollectionOp { args, .. }
            | TExprKind::PoolOp { args, .. }
            | TExprKind::MapOp { args, .. }
            | TExprKind::SetOp { args, .. } => {
                for arg in args {
                    visit_expr(arg, program, growing, moves);
                }
            }
            TExprKind::StructConstruct { fields } => {
                for (_, value) in fields {
                    visit_expr(value, program, growing, moves);
                }
            }
            TExprKind::Coalesce { option, fallback } => {
                visit_expr(option, program, growing, moves);
                visit_expr(fallback, program, growing, moves);
            }
            TExprKind::Match { scrutinee, arms } => {
                visit_expr(scrutinee, program, growing, moves);
                for arm in arms {
                    visit_block(&arm.body, program, growing, moves);
                }
            }
            TExprKind::Return(value) => {
                if let Some(value) = value {
                    visit_expr(value, program, growing, moves);
                }
            }
            TExprKind::Binary { left, right, .. } => {
                visit_expr(left, program, growing, moves);
                visit_expr(right, program, growing, moves);
            }
            TExprKind::If {
                condition,
                then_block,
                else_block,
            } => {
                visit_expr(condition, program, growing, moves);
                visit_block(then_block, program, growing, moves);
                if let Some(other) = else_block {
                    visit_block(other, program, growing, moves);
                }
            }
            TExprKind::AsciiEmpty
            | TExprKind::TextEmpty
            | TExprKind::BytesEmpty
            | TExprKind::Unit
            | TExprKind::Integer(_)
            | TExprKind::Bool(_)
            | TExprKind::ByteString(_)
            | TExprKind::Local(_)
            | TExprKind::Global(_)
            | TExprKind::Constant(_)
            | TExprKind::FunctionValue(_)
            | TExprKind::EmptyArray
            | TExprKind::EmptyGrid
            | TExprKind::EmptyList
            | TExprKind::EmptyPool
            | TExprKind::EmptyMap
            | TExprKind::EmptySet
            | TExprKind::EmptyQueue
            | TExprKind::EmptyRing
            | TExprKind::LoopExit(_) => {}
        }
    }

    fn visit_block(
        block: &TBlock,
        program: &TProgram,
        growing: &mut std::collections::HashSet<usize>,
        moves: &mut Vec<(usize, usize)>,
    ) {
        for stmt in &block.statements {
            match &stmt.kind {
                TStmtKind::Let { id, value, .. } => {
                    if let TExprKind::Take(source) = &value.kind {
                        if let Some(source) = local_root(source) {
                            moves.push((*id, source));
                        }
                    }
                    visit_expr(value, program, growing, moves);
                }
                TStmtKind::Assign {
                    place, op, value, ..
                } => {
                    if matches!(program.types[place.ty.0].kind, TTypeKind::Ascii { .. }) {
                        let _ = op;
                        growing.insert(place.root);
                    }
                    if let TExprKind::Take(source) = &value.kind {
                        if let Some(source) = local_root(source) {
                            moves.push((place.root, source));
                        }
                    }
                    visit_expr(value, program, growing, moves);
                }
                TStmtKind::Return(value) => {
                    if let Some(value) = value {
                        visit_expr(value, program, growing, moves);
                    }
                }
                TStmtKind::Expr(value) | TStmtKind::Discard(value) => {
                    visit_expr(value, program, growing, moves)
                }
                TStmtKind::If {
                    condition,
                    then_block,
                    else_block,
                } => {
                    visit_expr(condition, program, growing, moves);
                    visit_block(then_block, program, growing, moves);
                    if let Some(other) = else_block {
                        visit_block(other, program, growing, moves);
                    }
                }
                TStmtKind::For {
                    start, end, body, ..
                } => {
                    visit_expr(start, program, growing, moves);
                    visit_expr(end, program, growing, moves);
                    visit_block(body, program, growing, moves);
                }
                TStmtKind::ForEach {
                    collection, body, ..
                } => {
                    visit_expr(collection, program, growing, moves);
                    visit_block(body, program, growing, moves);
                }
                TStmtKind::Block(body) => visit_block(body, program, growing, moves),
                TStmtKind::Expect { kind, .. } => match kind {
                    TExpectKind::Bool(value) => visit_expr(value, program, growing, moves),
                    TExpectKind::Compare { left, right, .. } => {
                        visit_expr(left, program, growing, moves);
                        visit_expr(right, program, growing, moves);
                    }
                    TExpectKind::StackPeak { .. } => {}
                },
                TStmtKind::Break | TStmtKind::Continue => {}
            }
        }
        if let Some(tail) = &block.tail {
            visit_expr(tail, program, growing, moves);
        }
    }

    let mut growing = std::collections::HashSet::new();
    let mut moves = Vec::new();
    visit_block(&function.body, program, &mut growing, &mut moves);
    loop {
        let mut changed = false;
        for (destination, source) in &moves {
            if growing.contains(destination) && growing.insert(*source) {
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    growing
}

fn raw_llvm_type_size(llvm_ty: &str) -> Option<usize> {
    let scalar_size = |scalar: &str| match scalar.trim() {
        "i1" | "i8" => Some(1usize),
        "i16" => Some(2),
        "i32" => Some(4),
        "i64" => Some(8),
        _ => None,
    };
    if let Some(array) = llvm_ty.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
        let (count, element) = array.split_once(" x ")?;
        return count
            .trim()
            .parse::<usize>()
            .ok()?
            .checked_mul(scalar_size(element)?);
    }
    scalar_size(llvm_ty)
}

fn llvm_constant(ty: Ty, value: &ConstValue, types: &[TType], functions: &[TFunction]) -> String {
    match &types[ty.0].kind {
        TTypeKind::Refinement { base, .. } => llvm_constant(*base, value, types, functions),
        TTypeKind::Int | TTypeKind::Long => match value {
            ConstValue::Integer(value) => value.to_string(),
            _ => unreachable!("integer constant has an aggregate value"),
        },
        TTypeKind::Bool => match value {
            ConstValue::Bool(value) => value.to_string(),
            _ => unreachable!("bool constant has a non-bool value"),
        },
        TTypeKind::Unit => "zeroinitializer".to_owned(),
        TTypeKind::Id { .. } => match value {
            ConstValue::Integer(value) => value.to_string(),
            _ => unreachable!("id constant has a non-integer value"),
        },
        TTypeKind::Function { .. } => match value {
            ConstValue::Function(id) => format!("@nl_fn_{id}"),
            _ => unreachable!("function value constant has a non-function value"),
        },
        TTypeKind::Capability(_) => unreachable!("capabilities cannot be constants"),
        TTypeKind::Ascii { .. } | TTypeKind::Text { .. } | TTypeKind::Bytes { .. } => {
            unreachable!("growing text constants are not supported")
        }
        TTypeKind::Struct(fields) => {
            let ConstValue::Struct(values) = value else {
                unreachable!("struct constant has a non-struct value")
            };
            let fields = fields
                .iter()
                .zip(values)
                .map(|(field, value)| {
                    format!(
                        "{} {}",
                        llvm_type(field.ty, types),
                        llvm_constant(field.ty, value, types, functions)
                    )
                })
                .collect::<Vec<_>>()
                .join(", ");
            format!("<{{ {fields} }}>")
        }
        TTypeKind::Array { element, capacity } => {
            let ConstValue::Array(values) = value else {
                unreachable!("array constant has a non-array value")
            };
            collection_constant(*element, *capacity, values, 0, types, functions)
        }
        TTypeKind::List { element, capacity } => {
            let ConstValue::List(values) = value else {
                unreachable!("list constant has a non-list value")
            };
            collection_constant(*element, *capacity, values, 1, types, functions)
        }
        TTypeKind::Queue { element, capacity } => {
            let ConstValue::Queue(values) = value else {
                unreachable!("queue constant has a non-queue value")
            };
            collection_constant(*element, *capacity, values, 2, types, functions)
        }
        TTypeKind::Ring { element, capacity } => {
            let ConstValue::Ring(values) = value else {
                unreachable!("ring constant has a non-ring value")
            };
            collection_constant(*element, *capacity, values, 2, types, functions)
        }
        TTypeKind::Grid {
            element, capacity, ..
        } => {
            let ConstValue::Grid(values) = value else {
                unreachable!("grid constant has a non-grid value")
            };
            collection_constant(*element, *capacity, values, 0, types, functions)
        }
        TTypeKind::Map {
            key,
            value: value_ty,
            capacity,
        } => {
            let ConstValue::Map(entries) = value else {
                unreachable!("map constant has a non-map value")
            };
            map_constant(*key, *value_ty, *capacity, entries, types, functions)
        }
        TTypeKind::Set { key, capacity } => {
            let ConstValue::Set(entries) = value else {
                unreachable!("set constant has a non-set value")
            };
            set_constant(*key, *capacity, entries, types, functions)
        }
        TTypeKind::Pool {
            element, capacity, ..
        } => {
            let ConstValue::Pool {
                slots,
                generations,
                free,
                high_water,
            } = value
            else {
                unreachable!("pool global initializer has a non-pool value")
            };
            let mut fields = vec![
                format!("i64 {}", slots.iter().filter(|slot| slot.is_some()).count()),
                format!("i64 {}", free.len()),
            ];
            let occupied = (0..*capacity)
                .map(|index| format!("i1 {}", slots.get(index).is_some_and(Option::is_some)))
                .collect::<Vec<_>>()
                .join(", ");
            fields.push(format!("[{} x i1] [{occupied}]", capacity));
            let generation_values = (0..*capacity)
                .map(|index| format!("i32 {}", generations.get(index).copied().unwrap_or(1)))
                .collect::<Vec<_>>()
                .join(", ");
            fields.push(format!("[{} x i32] [{generation_values}]", capacity));
            let free_values = (0..*capacity)
                .map(|index| format!("i32 {}", free.get(index).copied().unwrap_or(0)))
                .collect::<Vec<_>>()
                .join(", ");
            fields.push(format!("[{} x i32] [{free_values}]", capacity));
            fields.push(format!("i64 {high_water}"));
            for (lane_index, lane_ty) in collection_lane_types(*element, types).iter().enumerate() {
                let lane_values = (0..*capacity)
                    .map(|index| {
                        let value =
                            slots.get(index).and_then(Option::as_ref).and_then(
                                |value| match value {
                                    ConstValue::Struct(fields) => fields.get(lane_index),
                                    other if lane_index == 0 => Some(other),
                                    _ => None,
                                },
                            );
                        let rendered = value
                            .map(|value| llvm_constant(*lane_ty, value, types, functions))
                            .unwrap_or_else(|| "zeroinitializer".to_owned());
                        format!("{} {rendered}", llvm_type(*lane_ty, types))
                    })
                    .collect::<Vec<_>>()
                    .join(", ");
                fields.push(format!(
                    "[{} x {}] [{lane_values}]",
                    capacity,
                    llvm_type(*lane_ty, types)
                ));
            }
            format!("<{{ {} }}>", fields.join(", "))
        }
        TTypeKind::Enum(_) | TTypeKind::Option(_) | TTypeKind::Result(..) => {
            let ConstValue::Enum {
                case_index,
                payload,
            } = value
            else {
                unreachable!("enum constant has a non-enum value")
            };
            let mut cache = vec![None; types.len()];
            let payload_size = enum_payload_size(ty, types, &mut cache);
            let bytes = enum_payload_bytes(ty, *case_index, payload, types, payload_size);
            let bytes = bytes
                .iter()
                .map(|byte| format!("i8 {byte}"))
                .collect::<Vec<_>>()
                .join(", ");
            format!("{{ i32 {}, [{payload_size} x i8] [{bytes}] }}", case_index)
        }
        TTypeKind::Never => unreachable!("never cannot be stored as a constant"),
    }
}

fn collection_constant(
    element: Ty,
    capacity: usize,
    values: &[ConstValue],
    metadata: usize,
    types: &[TType],
    functions: &[TFunction],
) -> String {
    let lanes = collection_lane_types(element, types);
    let mut fields = Vec::new();
    if metadata == 1 {
        fields.push(format!("i64 {}", values.len()));
    } else if metadata == 2 {
        fields.push("i64 0".to_owned());
        fields.push(format!("i64 {}", values.len()));
    }
    for lane in lanes {
        let lane_values = values
            .iter()
            .map(|value| match (&types[element.0].kind, value) {
                (TTypeKind::Struct(_), ConstValue::Struct(fields)) => {
                    fields.first().cloned().unwrap_or(ConstValue::Unit)
                }
                _ => value.clone(),
            })
            .collect::<Vec<_>>();
        let lane_index = fields.len() - metadata;
        let lane_ty = lane;
        let values_text = (0..capacity)
            .map(|index| {
                let value = if index < lane_values.len() {
                    if matches!(types[element.0].kind, TTypeKind::Struct(_)) {
                        match &values[index] {
                            ConstValue::Struct(fields) => {
                                fields.get(lane_index).cloned().unwrap_or(ConstValue::Unit)
                            }
                            _ => ConstValue::Unit,
                        }
                    } else {
                        lane_values[index].clone()
                    }
                } else {
                    ConstValue::Unit
                };
                let inner = if index < values.len() {
                    llvm_constant(lane_ty, &value, types, functions)
                } else {
                    "zeroinitializer".to_owned()
                };
                format!("{} {}", llvm_type(lane_ty, types), inner)
            })
            .collect::<Vec<_>>()
            .join(", ");
        fields.push(format!(
            "[{} x {}] [{}]",
            capacity,
            llvm_type(lane_ty, types),
            values_text
        ));
    }
    format!("<{{ {} }}> ", fields.join(", "))
        .trim_end()
        .to_owned()
}

fn hash_fold(hash: u64, value: u64) -> u64 {
    (hash ^ value).wrapping_mul(1_099_511_628_211)
}

fn constant_hash(ty: Ty, value: &ConstValue, types: &[TType]) -> u64 {
    fn fold(ty: Ty, value: &ConstValue, types: &[TType], hash: &mut u64) {
        match &types[ty.0].kind {
            TTypeKind::Refinement { base, .. } => fold(*base, value, types, hash),
            TTypeKind::Int => {
                let ConstValue::Integer(value) = value else {
                    unreachable!()
                };
                *hash = hash_fold(*hash, (*value as i32 as i64) as u64);
            }
            TTypeKind::Long | TTypeKind::Id { .. } => {
                let ConstValue::Integer(value) = value else {
                    unreachable!()
                };
                *hash = hash_fold(*hash, *value as i64 as u64);
            }
            TTypeKind::Bool => {
                let ConstValue::Bool(value) = value else {
                    unreachable!()
                };
                *hash = hash_fold(*hash, u64::from(*value));
            }
            TTypeKind::Struct(fields) => {
                let ConstValue::Struct(values) = value else {
                    unreachable!()
                };
                for (field, value) in fields.iter().zip(values) {
                    fold(field.ty, value, types, hash);
                }
            }
            TTypeKind::Enum(_) | TTypeKind::Option(_) | TTypeKind::Result(..) => {
                let ConstValue::Enum {
                    case_index,
                    payload,
                } = value
                else {
                    unreachable!()
                };
                *hash = hash_fold(*hash, *case_index as u64);
                for (field_ty, value) in
                    types[ty.0].cases()[*case_index].payload.iter().zip(payload)
                {
                    fold(*field_ty, value, types, hash);
                }
            }
            _ => unreachable!("unhashable type reached constant hashing"),
        }
    }
    let mut hash = 1_469_598_103_934_665_603;
    fold(ty, value, types, &mut hash);
    hash
}

fn hash_index(capacity: usize, hashes: &[u64]) -> Vec<i64> {
    let mut index = vec![0i64; capacity];
    if capacity == 0 {
        return index;
    }
    for (entry, hash) in hashes.iter().enumerate() {
        let mut slot = (*hash as usize) % capacity;
        while index[slot] != 0 {
            slot = (slot + 1) % capacity;
        }
        index[slot] = entry as i64 + 1;
    }
    index
}

fn map_constant(
    key_ty: Ty,
    value_ty: Ty,
    capacity: usize,
    entries: &[(ConstValue, ConstValue)],
    types: &[TType],
    functions: &[TFunction],
) -> String {
    let hashes = entries
        .iter()
        .map(|(key, _)| constant_hash(key_ty, key, types))
        .collect::<Vec<_>>();
    let index = hash_index(capacity, &hashes);
    let active = (0..capacity)
        .map(|slot| format!("i1 {}", slot < entries.len()))
        .collect::<Vec<_>>()
        .join(", ");
    let hashes_text = (0..capacity)
        .map(|slot| format!("i64 {}", hashes.get(slot).copied().unwrap_or(0)))
        .collect::<Vec<_>>()
        .join(", ");
    let index_text = index
        .iter()
        .map(|v| format!("i64 {v}"))
        .collect::<Vec<_>>()
        .join(", ");
    let keys_text = (0..capacity)
        .map(|slot| {
            let value = entries
                .get(slot)
                .map(|entry| llvm_constant(key_ty, &entry.0, types, functions))
                .unwrap_or_else(|| "zeroinitializer".to_owned());
            format!("{} {value}", llvm_type(key_ty, types))
        })
        .collect::<Vec<_>>()
        .join(", ");
    let values_text = (0..capacity)
        .map(|slot| {
            let value = entries
                .get(slot)
                .map(|entry| llvm_constant(value_ty, &entry.1, types, functions))
                .unwrap_or_else(|| "zeroinitializer".to_owned());
            format!("{} {value}", llvm_type(value_ty, types))
        })
        .collect::<Vec<_>>()
        .join(", ");
    let ascii_key_storage = match types[key_ty.0].kind {
        TTypeKind::Ascii { max_bytes } => {
            format!(", [{} x [{} x i8]] zeroinitializer", capacity, max_bytes)
        }
        _ => String::new(),
    };
    format!(
        "<{{ i64 {}, i64 {}, [{} x i1] [{active}], [{} x i64] [{hashes_text}], [{} x i64] [{index_text}], [{} x {}] [{keys_text}], [{} x {}] [{values_text}]{} }}>",
        entries.len(),
        entries.len(),
        capacity,
        capacity,
        capacity,
        capacity,
        llvm_type(key_ty, types),
        capacity,
        llvm_type(value_ty, types),
        ascii_key_storage
    )
}

fn set_constant(
    key_ty: Ty,
    capacity: usize,
    entries: &[ConstValue],
    types: &[TType],
    functions: &[TFunction],
) -> String {
    let hashes = entries
        .iter()
        .map(|key| constant_hash(key_ty, key, types))
        .collect::<Vec<_>>();
    let index = hash_index(capacity, &hashes);
    let active = (0..capacity)
        .map(|slot| format!("i1 {}", slot < entries.len()))
        .collect::<Vec<_>>()
        .join(", ");
    let hashes_text = (0..capacity)
        .map(|slot| format!("i64 {}", hashes.get(slot).copied().unwrap_or(0)))
        .collect::<Vec<_>>()
        .join(", ");
    let index_text = index
        .iter()
        .map(|v| format!("i64 {v}"))
        .collect::<Vec<_>>()
        .join(", ");
    let keys_text = (0..capacity)
        .map(|slot| {
            let value = entries
                .get(slot)
                .map(|key| llvm_constant(key_ty, key, types, functions))
                .unwrap_or_else(|| "zeroinitializer".to_owned());
            format!("{} {value}", llvm_type(key_ty, types))
        })
        .collect::<Vec<_>>()
        .join(", ");
    let ascii_key_storage = match types[key_ty.0].kind {
        TTypeKind::Ascii { max_bytes } => {
            format!(", [{} x [{} x i8]] zeroinitializer", capacity, max_bytes)
        }
        _ => String::new(),
    };
    format!(
        "<{{ i64 {}, i64 {}, [{} x i1] [{active}], [{} x i64] [{hashes_text}], [{} x i64] [{index_text}], [{} x {}] [{keys_text}]{} }}>",
        entries.len(),
        entries.len(),
        capacity,
        capacity,
        capacity,
        capacity,
        llvm_type(key_ty, types),
        ascii_key_storage
    )
}

fn enum_payload_bytes(
    ty: Ty,
    case_index: usize,
    values: &[ConstValue],
    types: &[TType],
    payload_size: usize,
) -> Vec<u8> {
    let case = types[ty.0].cases()[case_index].clone();
    let mut bytes = Vec::with_capacity(payload_size);
    let mut cache = vec![None; types.len()];
    for (field_ty, value) in case.payload.iter().zip(values) {
        serialize_constant(*field_ty, value, types, &mut bytes, &mut cache);
    }
    bytes.resize(payload_size, 0);
    bytes
}

fn serialize_constant(
    ty: Ty,
    value: &ConstValue,
    types: &[TType],
    bytes: &mut Vec<u8>,
    cache: &mut [Option<usize>],
) {
    match &types[ty.0].kind {
        TTypeKind::Refinement { base, .. } => serialize_constant(*base, value, types, bytes, cache),
        TTypeKind::Int => {
            let ConstValue::Integer(value) = value else {
                unreachable!("int constant has a non-int value")
            };
            bytes.extend_from_slice(&(*value as i32).to_le_bytes());
        }
        TTypeKind::Long => {
            let ConstValue::Integer(value) = value else {
                unreachable!("long constant has a non-long value")
            };
            bytes.extend_from_slice(&(*value as i64).to_le_bytes());
        }
        TTypeKind::Bool => {
            let ConstValue::Bool(value) = value else {
                unreachable!("bool constant has a non-bool value")
            };
            bytes.push(u8::from(*value));
        }
        TTypeKind::Unit | TTypeKind::Never => {}
        TTypeKind::Ascii { .. } | TTypeKind::Text { .. } | TTypeKind::Bytes { .. } => {
            unreachable!("growing text constants are not supported")
        }
        TTypeKind::Id { .. } => {
            let ConstValue::Integer(value) = value else {
                unreachable!("id constant has a non-integer value")
            };
            bytes.extend_from_slice(&(*value as u64).to_le_bytes());
        }
        TTypeKind::Function { .. } => {
            unreachable!("function pointers are emitted as LLVM relocations, not serialized bytes")
        }
        TTypeKind::Capability(_) => unreachable!("capabilities cannot be serialized as constants"),
        TTypeKind::Struct(fields) => {
            let ConstValue::Struct(values) = value else {
                unreachable!("struct constant has a non-struct value")
            };
            for (field, value) in fields.iter().zip(values) {
                serialize_constant(field.ty, value, types, bytes, cache);
            }
        }
        TTypeKind::Array { element, capacity } => {
            let ConstValue::Array(values) = value else {
                unreachable!("array constant has a non-array value")
            };
            serialize_collection(*element, *capacity, values, false, types, bytes, cache);
        }
        TTypeKind::List { element, capacity } => {
            let ConstValue::List(values) = value else {
                unreachable!("list constant has a non-list value")
            };
            bytes.extend_from_slice(&(values.len() as u64).to_le_bytes());
            serialize_collection(*element, *capacity, values, true, types, bytes, cache);
        }
        TTypeKind::Queue { element, capacity } => {
            let ConstValue::Queue(values) = value else {
                unreachable!("queue value has a non-queue constant")
            };
            bytes.extend_from_slice(&0u64.to_le_bytes());
            bytes.extend_from_slice(&(values.len() as u64).to_le_bytes());
            serialize_collection(*element, *capacity, values, true, types, bytes, cache);
        }
        TTypeKind::Ring { element, capacity } => {
            let ConstValue::Ring(values) = value else {
                unreachable!("ring value has a non-ring constant")
            };
            bytes.extend_from_slice(&0u64.to_le_bytes());
            bytes.extend_from_slice(&(values.len() as u64).to_le_bytes());
            serialize_collection(*element, *capacity, values, true, types, bytes, cache);
        }
        TTypeKind::Grid {
            element, capacity, ..
        } => {
            let ConstValue::Grid(values) = value else {
                unreachable!("grid value has a non-grid constant")
            };
            serialize_collection(*element, *capacity, values, false, types, bytes, cache);
        }
        TTypeKind::Map {
            key,
            value: value_ty,
            capacity,
        } => {
            let ConstValue::Map(entries) = value else {
                unreachable!("map value has a non-map constant")
            };
            bytes.extend_from_slice(&(entries.len() as u64).to_le_bytes());
            bytes.extend_from_slice(&(entries.len() as u64).to_le_bytes());
            for index in 0..*capacity {
                bytes.push(u8::from(index < entries.len()));
            }
            let hashes = entries
                .iter()
                .map(|(key_value, _)| constant_hash(*key, key_value, types))
                .collect::<Vec<_>>();
            let table = hash_index(*capacity, &hashes);
            for index in 0..*capacity {
                bytes.extend_from_slice(&hashes.get(index).copied().unwrap_or(0).to_le_bytes());
            }
            for slot in table {
                bytes.extend_from_slice(&slot.to_le_bytes());
            }
            for index in 0..*capacity {
                if let Some((key_value, _)) = entries.get(index) {
                    serialize_constant(*key, key_value, types, bytes, cache);
                } else {
                    bytes.resize(bytes.len() + type_size(*key, types, cache), 0);
                }
            }
            for index in 0..*capacity {
                if let Some((_, value_value)) = entries.get(index) {
                    serialize_constant(*value_ty, value_value, types, bytes, cache);
                } else {
                    bytes.resize(bytes.len() + type_size(*value_ty, types, cache), 0);
                }
            }
            if let TTypeKind::Ascii { max_bytes } = types[key.0].kind {
                bytes.resize(bytes.len() + capacity.saturating_mul(max_bytes), 0);
            }
        }
        TTypeKind::Set { key, capacity } => {
            let ConstValue::Set(entries) = value else {
                unreachable!("set value has a non-set constant")
            };
            bytes.extend_from_slice(&(entries.len() as u64).to_le_bytes());
            bytes.extend_from_slice(&(entries.len() as u64).to_le_bytes());
            for index in 0..*capacity {
                bytes.push(u8::from(index < entries.len()));
            }
            let hashes = entries
                .iter()
                .map(|key_value| constant_hash(*key, key_value, types))
                .collect::<Vec<_>>();
            let table = hash_index(*capacity, &hashes);
            for index in 0..*capacity {
                bytes.extend_from_slice(&hashes.get(index).copied().unwrap_or(0).to_le_bytes());
            }
            for slot in table {
                bytes.extend_from_slice(&slot.to_le_bytes());
            }
            for index in 0..*capacity {
                if let Some(key_value) = entries.get(index) {
                    serialize_constant(*key, key_value, types, bytes, cache);
                } else {
                    bytes.resize(bytes.len() + type_size(*key, types, cache), 0);
                }
            }
            if let TTypeKind::Ascii { max_bytes } = types[key.0].kind {
                bytes.resize(bytes.len() + capacity.saturating_mul(max_bytes), 0);
            }
        }
        TTypeKind::Pool { .. } => unreachable!("pool-valued constants are rejected"),
        TTypeKind::Enum(_) | TTypeKind::Option(_) | TTypeKind::Result(..) => {
            let ConstValue::Enum {
                case_index,
                payload,
            } = value
            else {
                unreachable!("enum constant has a non-enum value")
            };
            bytes.extend_from_slice(&(*case_index as i32).to_le_bytes());
            let payload_size = enum_payload_size(ty, types, cache);
            bytes.extend(enum_payload_bytes(
                ty,
                *case_index,
                payload,
                types,
                payload_size,
            ));
            let size = type_size(ty, types, cache);
            let start = bytes.len().saturating_sub(4 + payload_size);
            let actual = bytes.len() - start;
            if actual < size {
                bytes.resize(bytes.len() + size - actual, 0);
            }
        }
    }
}

fn serialize_collection(
    element: Ty,
    capacity: usize,
    values: &[ConstValue],
    _is_list: bool,
    types: &[TType],
    bytes: &mut Vec<u8>,
    cache: &mut [Option<usize>],
) {
    let lanes = collection_lane_types(element, types);
    for (lane_index, lane) in lanes.iter().copied().enumerate() {
        for index in 0..capacity {
            let field_value = if index < values.len() {
                if matches!(types[element.0].kind, TTypeKind::Struct(_)) {
                    match &values[index] {
                        ConstValue::Struct(fields) => fields.get(lane_index).cloned(),
                        _ => None,
                    }
                } else {
                    Some(values[index].clone())
                }
            } else {
                None
            };
            if let Some(value) = field_value {
                serialize_constant(lane, &value, types, bytes, cache);
            } else {
                bytes.resize(bytes.len().saturating_add(type_size(lane, types, cache)), 0);
            }
        }
    }
}

struct FunctionEmitter<'a> {
    program: &'a TProgram,
    function: &'a TFunction,
    expect_ids: &'a HashMap<String, usize>,
    print_ids: &'a HashMap<String, usize>,
    lines: Vec<String>,
    temp: usize,
    label: usize,
    current_label: String,
    terminated: bool,
    slots: Vec<Option<Ty>>,
    loops: Vec<LoopTargets>,
    views: HashMap<usize, ViewInfo>,
    sort_scratch: HashMap<Ty, String>,
    reserved_ascii_locals: std::collections::HashSet<usize>,
    returned_ascii_builder_local: Option<usize>,
    append_variant: bool,
    append_builder_local: Option<usize>,
    append_entry_offset: Option<String>,
    prologue_end: usize,
    stack_top: String,
    entry_stack_top: String,
}

const ENTRY_STACK_TOP: &str = "__NL_ENTRY_STACK_TOP__";

#[derive(Clone)]
struct ViewInfo {
    collection_ty: Ty,
    collection_ptr: String,
    counter_id: usize,
}

#[derive(Clone)]
struct CallArgumentRegion {
    collection_ty: Ty,
    collection_ptr: String,
    index: String,
    temporary: String,
    copy_back: bool,
}

struct LoopTargets {
    latch: String,
    exit: String,
    stack_top: String,
}

impl<'a> FunctionEmitter<'a> {
    fn new(
        program: &'a TProgram,
        function: &'a TFunction,
        expect_ids: &'a HashMap<String, usize>,
        print_ids: &'a HashMap<String, usize>,
    ) -> Self {
        Self::new_mode(program, function, expect_ids, print_ids, false)
    }

    fn new_append_variant(
        program: &'a TProgram,
        function: &'a TFunction,
        expect_ids: &'a HashMap<String, usize>,
        print_ids: &'a HashMap<String, usize>,
    ) -> Self {
        Self::new_mode(program, function, expect_ids, print_ids, true)
    }

    fn new_mode(
        program: &'a TProgram,
        function: &'a TFunction,
        expect_ids: &'a HashMap<String, usize>,
        print_ids: &'a HashMap<String, usize>,
        append_variant: bool,
    ) -> Self {
        let reserved_ascii_locals = growing_ascii_locals(function, program);
        let returned_ascii_builder_local =
            returned_ascii_builder_local(function, &program.types, &reserved_ascii_locals);
        let append_builder_local = append_variant
            .then(|| {
                returned_result_ascii_builder(function, &program.types)
                    .or(returned_ascii_builder_local)
            })
            .flatten();
        let mut this = Self {
            program,
            function,
            expect_ids,
            print_ids,
            lines: Vec::new(),
            temp: 0,
            label: 0,
            current_label: "entry".to_owned(),
            terminated: false,
            slots: Vec::new(),
            loops: Vec::new(),
            views: HashMap::new(),
            sort_scratch: HashMap::new(),
            reserved_ascii_locals,
            returned_ascii_builder_local,
            append_variant,
            append_builder_local,
            append_entry_offset: None,
            prologue_end: 0,
            stack_top: ENTRY_STACK_TOP.to_owned(),
            entry_stack_top: "%nl.entry.top".to_owned(),
        };
        for param in &function.params {
            this.record_slot(param.id, param.ty);
        }
        this.collect_block(&function.body);
        this
    }

    fn lltype(&self, ty: Ty) -> String {
        llvm_type(ty, &self.program.types)
    }

    fn is_write_param(&self, id: usize) -> bool {
        self.function
            .params
            .iter()
            .any(|param| param.id == id && param.mode != ParamMode::Read)
    }

    fn is_pool_param(&self, id: usize) -> bool {
        self.function.params.iter().any(|param| {
            param.id == id && matches!(self.program.types[param.ty.0].kind, TTypeKind::Pool { .. })
        })
    }

    fn is_large_param(&self, id: usize) -> bool {
        self.function
            .params
            .iter()
            .any(|param| param.id == id && is_large_type(param.ty, &self.program.types))
    }

    fn local_pointer(&self, id: usize) -> String {
        if self.is_write_param(id) || self.is_pool_param(id) || self.is_large_param(id) {
            format!("%arg.{id}")
        } else {
            format!("%local.{id}")
        }
    }

    fn emit_function(&mut self) -> String {
        let signature = lower_signature(self.function, &self.program.types);
        let mut params = vec!["ptr %nl.ctx".to_owned(), "ptr %nl.entry.top".to_owned()];
        if self.append_variant {
            if result_ascii_payload(self.function.result, &self.program.types).is_some() {
                params.push("ptr %nl.result".to_owned());
            }
            params.extend([
                "ptr %nl.append.data".to_owned(),
                "ptr %nl.append.offset".to_owned(),
            ]);
        } else if signature.result_destination {
            params.push("ptr %nl.result".to_owned());
        }
        params.extend(
            self.function
                .params
                .iter()
                .zip(signature.params.iter())
                .map(|(p, ty)| format!("{ty} %arg.{}", p.id)),
        );
        let params = params.join(", ");
        self.lines.push("entry:".to_owned());
        let slots = self.slots.clone();
        for (id, ty) in slots.iter().enumerate() {
            if let Some(ty) = *ty {
                if self.is_write_param(id)
                    || self.is_pool_param(id)
                    || self.is_large_param(id)
                    || is_large_type(ty, &self.program.types)
                {
                    continue;
                }
                self.lines
                    .push(format!("  %local.{id} = alloca {}", self.lltype(ty)));
            }
        }
        self.prologue_end = self.lines.len();
        for param in &self.function.params {
            if param.mode == ParamMode::Read
                && !self.is_pool_param(param.id)
                && !is_large_type(param.ty, &self.program.types)
            {
                self.lines.push(format!(
                    "  store {} %arg.{}, ptr %local.{}, align 1",
                    self.lltype(param.ty),
                    param.id,
                    param.id
                ));
            }
        }
        if self.append_variant
            && result_ascii_payload(self.function.result, &self.program.types).is_some()
        {
            let entry_offset = self.entry_alloca(Ty::Long);
            let accepted = self.temp();
            self.instruction(format!(
                "{accepted} = load i64, ptr %nl.append.offset, align 1"
            ));
            self.instruction(format!("store i64 {accepted}, ptr {entry_offset}, align 1"));
            self.append_entry_offset = Some(entry_offset);
        }
        self.emit_block_contents(&self.function.body.clone());
        if !self.terminated {
            if let Some(tail) = self.function.body.tail.as_deref() {
                if self.append_variant {
                    if result_ascii_payload(self.function.result, &self.program.types).is_some() {
                        self.emit_result_ascii_append_return(tail);
                    } else {
                        self.emit_ascii_stream(tail, "%nl.append.data", "%nl.append.offset");
                    }
                    if !self.terminated {
                        self.terminate("ret void");
                    }
                    let mut out = format!(
                        "; append variant for function {}\ndefine void @nl_fn_{}_append({}) {{\n",
                        self.function.name, self.function.id, params
                    );
                    let final_top = self.entry_stack_top.clone();
                    for line in &self.lines {
                        out.push_str(line);
                        out.push('\n');
                    }
                    out.push_str("}\n");
                    return out.replace(ENTRY_STACK_TOP, &final_top);
                }
                if signature.result_destination {
                    self.emit_expr_to("%nl.result", tail);
                    if !self.terminated {
                        self.terminate("ret void");
                    }
                    let mut out = format!(
                        "; function {}\ndefine {} @nl_fn_{}({}) {{\n",
                        self.function.name, signature.result, self.function.id, params
                    );
                    let final_top = self.entry_stack_top.clone();
                    for line in &self.lines {
                        out.push_str(line);
                        out.push('\n');
                    }
                    out.push_str("}\n");
                    return out.replace(ENTRY_STACK_TOP, &final_top);
                }
                if self.function.is_test {
                    if let Some(error_ty) = result_error_type(tail.ty, &self.program.types) {
                        self.emit_test_result_tail(tail, error_ty);
                    } else {
                        let _ = self.emit_expr(tail);
                        if !self.terminated {
                            self.terminate("ret i32 0");
                        }
                    }
                } else {
                    let value = self.emit_expr(tail);
                    if !self.terminated {
                        if self.function.result == Ty::Unit {
                            self.terminate("ret void");
                        } else {
                            self.terminate(format!(
                                "ret {} {value}",
                                self.lltype(self.function.result)
                            ));
                        }
                    }
                }
            } else if self.function.is_test {
                self.terminate("ret i32 0");
            } else if self.function.result == Ty::Unit {
                self.terminate("ret void");
            } else {
                self.terminate("unreachable");
            }
        }
        let mut out = format!(
            "; {}function {}\ndefine {} @nl_fn_{}{}({}) {{\n",
            if self.append_variant {
                "append variant for "
            } else {
                ""
            },
            self.function.name,
            if self.append_variant {
                "void"
            } else {
                signature.result.as_str()
            },
            self.function.id,
            if self.append_variant { "_append" } else { "" },
            params
        );
        let final_top = self.entry_stack_top.clone();
        for line in &self.lines {
            out.push_str(line);
            out.push('\n');
        }
        out.push_str("}\n");
        out = out.replace(ENTRY_STACK_TOP, &final_top);
        out
    }

    fn emit_test_result_tail(&mut self, expr: &TExpr, error_ty: Ty) {
        let result_ty = base_type(expr.ty, &self.program.types);
        let result_llvm_ty = self.lltype(result_ty);
        let large = is_large_type(result_ty, &self.program.types);
        let storage = if large {
            Some(self.emit_expr_storage(expr))
        } else {
            None
        };
        if self.terminated {
            return;
        }
        let value = if storage.is_none() {
            self.emit_expr(expr)
        } else {
            String::new()
        };
        if self.terminated {
            return;
        }
        let tag = if let Some(storage) = &storage {
            let pointer = self.temp();
            self.instruction(format!(
                "{pointer} = getelementptr {result_llvm_ty}, ptr {storage}, i32 0, i32 0"
            ));
            let tag = self.temp();
            self.instruction(format!("{tag} = load i32, ptr {pointer}, align 4"));
            tag
        } else {
            self.emit_tag(result_ty, &value)
        };
        let is_error = self.temp();
        self.instruction(format!("{is_error} = icmp eq i32 {tag}, 1"));
        let error_label = self.new_label("test.result.error");
        let success_label = self.new_label("test.result.ok");
        self.terminate(format!(
            "br i1 {is_error}, label %{error_label}, label %{success_label}"
        ));
        self.start_block(&error_label);
        self.instruction("call void @nl_print_set_fd(i32 2)");
        self.instruction("call void @nl_print_error_prefix()");
        let error_value = if let Some(storage) = &storage {
            let payload = self.temp();
            self.instruction(format!(
                "{payload} = getelementptr {result_llvm_ty}, ptr {storage}, i32 0, i32 1"
            ));
            let pointer = self.temp();
            self.instruction(format!(
                "{pointer} = getelementptr i8, ptr {payload}, i64 0"
            ));
            let error = self.temp();
            self.instruction(format!(
                "{error} = load {}, ptr {pointer}, align 1",
                self.lltype(error_ty)
            ));
            error
        } else {
            self.emit_payload(result_ty, &value, 1, 0).1
        };
        self.emit_print_value(error_ty, &error_value);
        self.instruction("call void @nl_print_newline()");
        self.instruction("call void @nl_print_set_fd(i32 1)");
        self.terminate("ret i32 1");
        self.start_block(&success_label);
        self.terminate("ret i32 0");
    }

    fn emit_region_alloc_lines(
        &mut self,
        ptr: String,
        bytes: usize,
        span: Span,
        insert: bool,
    ) -> String {
        let after = self.temp();
        let instructions = [
            format!(
                "  {ptr} = call ptr @nl_stack_alloc(ptr %nl.ctx, ptr {}, i64 {bytes}, i64 8, i32 {}, i32 {}, i32 {})",
                self.entry_stack_top, span.file, span.line, span.col
            ),
            format!("  {after} = getelementptr i8, ptr {ptr}, i64 {bytes}"),
        ];
        if insert {
            for (offset, instruction) in instructions.into_iter().enumerate() {
                self.lines.insert(self.prologue_end + offset, instruction);
            }
            self.prologue_end += 2;
        } else {
            self.lines.extend(instructions);
        }
        self.entry_stack_top = after;
        ptr
    }

    fn emit_runtime_region_alloc(&mut self, ty: Ty, span: Span, name: Option<String>) -> String {
        let bytes = stack_storage_size(ty, &self.program.types);
        let ptr = name.unwrap_or_else(|| self.temp());
        let after = self.temp();
        self.instruction(format!(
            "{ptr} = call ptr @nl_stack_alloc(ptr %nl.ctx, ptr {}, i64 {bytes}, i64 8, i32 {}, i32 {}, i32 {})",
            self.stack_top, span.file, span.line, span.col
        ));
        self.instruction(format!(
            "{after} = getelementptr i8, ptr {ptr}, i64 {bytes}"
        ));
        self.stack_top = after;
        ptr
    }

    fn emit_runtime_region_alloc_dynamic(
        &mut self,
        bytes: &str,
        span: Span,
        name: Option<String>,
    ) -> String {
        let ptr = name.unwrap_or_else(|| self.temp());
        self.instruction(format!(
            "{ptr} = call ptr @nl_stack_alloc(ptr %nl.ctx, ptr {}, i64 {bytes}, i64 8, i32 {}, i32 {}, i32 {})",
            self.stack_top, span.file, span.line, span.col
        ));
        let after = self.temp();
        self.instruction(format!(
            "{after} = getelementptr i8, ptr {ptr}, i64 {bytes}"
        ));
        self.stack_top = after;
        ptr
    }

    fn restore_stack_top(&mut self, saved: &str) {
        if self.stack_top != saved {
            self.instruction(format!(
                "call void @nl_context_set_top(ptr %nl.ctx, ptr {saved})"
            ));
            self.stack_top = saved.to_owned();
        }
    }

    fn entry_alloca(&mut self, ty: Ty) -> String {
        let ptr = self.temp();
        if is_large_type(ty, &self.program.types) {
            let bytes = stack_storage_size(ty, &self.program.types);
            return self.emit_region_alloc_lines(ptr, bytes, self.function.span, true);
        }
        self.lines.insert(
            self.prologue_end,
            format!("  {ptr} = alloca {}", self.lltype(ty)),
        );
        self.prologue_end += 1;
        ptr
    }

    fn entry_alloca_raw(&mut self, llvm_ty: &str) -> String {
        let ptr = self.temp();
        if let Some(bytes) = raw_llvm_type_size(llvm_ty).filter(|bytes| *bytes > 4_096) {
            return self.emit_region_alloc_lines(ptr, bytes, self.function.span, true);
        }
        self.lines
            .insert(self.prologue_end, format!("  {ptr} = alloca {llvm_ty}"));
        self.prologue_end += 1;
        ptr
    }

    fn collect_block(&mut self, block: &TBlock) {
        for stmt in &block.statements {
            self.collect_stmt(stmt);
        }
        if let Some(tail) = &block.tail {
            self.collect_expr(tail);
        }
    }

    fn collect_stmt(&mut self, stmt: &TStmt) {
        match &stmt.kind {
            TStmtKind::Let { id, ty, value, .. } => {
                self.record_slot(*id, *ty);
                self.collect_expr(value);
            }
            TStmtKind::Assign { value, .. }
            | TStmtKind::Expr(value)
            | TStmtKind::Discard(value) => self.collect_expr(value),
            TStmtKind::Return(value) => {
                if let Some(value) = value {
                    self.collect_expr(value);
                }
            }
            TStmtKind::If {
                condition,
                then_block,
                else_block,
            } => {
                self.collect_expr(condition);
                self.collect_block(then_block);
                if let Some(other) = else_block {
                    self.collect_block(other);
                }
            }
            TStmtKind::For {
                id,
                ty,
                start,
                end,
                body,
                ..
            } => {
                self.record_slot(*id, *ty);
                self.collect_expr(start);
                self.collect_expr(end);
                self.collect_block(body);
            }
            TStmtKind::ForEach {
                id,
                index_id,
                second_index_id,
                counter_id,
                collection,
                body,
                ..
            } => {
                let element = match self.program.types[collection.ty.0].kind {
                    TTypeKind::Array { element, .. }
                    | TTypeKind::List { element, .. }
                    | TTypeKind::Queue { element, .. }
                    | TTypeKind::Ring { element, .. }
                    | TTypeKind::Grid { element, .. }
                    | TTypeKind::Pool { element, .. } => element,
                    TTypeKind::Map { value, .. } => value,
                    TTypeKind::Set { key, .. } => key,
                    _ => unreachable!("typed collection loop has a collection source"),
                };
                self.record_slot(*id, element);
                if let Some(index_id) = index_id {
                    let index_ty = match self.program.types[collection.ty.0].kind {
                        TTypeKind::Map { key, .. } => key,
                        _ => Ty::Long,
                    };
                    self.record_slot(*index_id, index_ty);
                }
                if let Some(second_index_id) = second_index_id {
                    self.record_slot(*second_index_id, Ty::Long);
                }
                self.record_slot(*counter_id, Ty::Long);
                self.collect_expr(collection);
                self.collect_block(body);
            }
            TStmtKind::Expect { kind, .. } => match kind {
                TExpectKind::Bool(value) => self.collect_expr(value),
                TExpectKind::Compare { left, right, .. } => {
                    self.collect_expr(left);
                    self.collect_expr(right);
                }
                TExpectKind::StackPeak { .. } => {}
            },
            TStmtKind::Block(block) => self.collect_block(block),
            TStmtKind::Break | TStmtKind::Continue => {}
        }
    }

    fn collect_expr(&mut self, expr: &TExpr) {
        match &expr.kind {
            TExprKind::Local(id) => {
                if self.slots.len() <= *id {
                    self.slots.resize(*id + 1, None);
                }
            }
            TExprKind::Call { args, .. } => {
                for arg in args {
                    self.collect_expr(arg);
                }
            }
            TExprKind::IndirectCall { callee, args, .. } => {
                self.collect_expr(callee);
                for arg in args {
                    self.collect_expr(arg);
                }
            }
            TExprKind::Construct { args, .. } => {
                for arg in args {
                    self.collect_expr(arg);
                }
            }
            TExprKind::Method { receiver, .. } => self.collect_expr(receiver),
            TExprKind::AsciiUpper(value)
            | TExprKind::TextUpper(value)
            | TExprKind::AsciiFormat(value)
            | TExprKind::AsciiCast(value)
            | TExprKind::Take(value)
            | TExprKind::BytesView(value)
            | TExprKind::TextConvert { value, .. }
            | TExprKind::AsciiFit { value, .. } => self.collect_expr(value),
            TExprKind::TextSlice {
                receiver,
                start,
                end,
            }
            | TExprKind::BytesSlice {
                receiver,
                start,
                end,
            } => {
                self.collect_expr(receiver);
                self.collect_expr(start);
                self.collect_expr(end);
            }
            TExprKind::AsciiTryAppend { receiver, argument } => {
                self.collect_expr(receiver);
                self.collect_expr(argument);
            }
            TExprKind::Index {
                receiver,
                index,
                grid,
                ..
            } => {
                self.collect_expr(receiver);
                if let Some(grid) = grid {
                    self.collect_expr(&grid.x);
                    self.collect_expr(&grid.y);
                } else {
                    self.collect_expr(index);
                }
            }
            TExprKind::Fill { value, .. } => self.collect_expr(value),
            TExprKind::CollectionOp { receiver, args, .. }
            | TExprKind::PoolOp { receiver, args, .. }
            | TExprKind::MapOp { receiver, args, .. }
            | TExprKind::SetOp { receiver, args, .. } => {
                self.collect_expr(receiver);
                for arg in args {
                    self.collect_expr(arg);
                }
            }
            TExprKind::OptionalToLong(receiver) => self.collect_expr(receiver),
            TExprKind::Field { receiver, .. } => self.collect_expr(receiver),
            TExprKind::StructConstruct { fields } => {
                for (_, value) in fields {
                    self.collect_expr(value);
                }
            }
            TExprKind::Convert { value, .. } | TExprKind::Fit { value, .. } => {
                self.collect_expr(value)
            }
            TExprKind::OptionalCall { receiver, args, .. } => {
                self.collect_expr(receiver);
                for arg in args {
                    self.collect_expr(arg);
                }
            }
            TExprKind::Try { value, .. } => self.collect_expr(value),
            TExprKind::Coalesce { option, fallback } => {
                self.collect_expr(option);
                self.collect_expr(fallback);
            }
            TExprKind::Match { scrutinee, arms } => {
                self.collect_expr(scrutinee);
                for arm in arms {
                    if let TPattern::Case {
                        bindings,
                        ty,
                        case_index,
                    } = &arm.pattern
                    {
                        let payload = self.program.types[ty.0].cases()[*case_index]
                            .payload
                            .clone();
                        for (id, field_ty) in bindings.iter().zip(payload) {
                            if let Some(id) = id {
                                self.record_slot(*id, field_ty);
                            }
                        }
                    }
                    self.collect_block(&arm.body);
                }
            }
            TExprKind::Return(value) => {
                if let Some(value) = value {
                    self.collect_expr(value);
                }
            }
            TExprKind::ToLong(v)
            | TExprKind::Cast { value: v, .. }
            | TExprKind::Unary { value: v, .. } => self.collect_expr(v),
            TExprKind::Binary { left, right, .. } => {
                self.collect_expr(left);
                self.collect_expr(right);
            }
            TExprKind::If {
                condition,
                then_block,
                else_block,
            } => {
                self.collect_expr(condition);
                self.collect_block(then_block);
                if let Some(other) = else_block {
                    self.collect_block(other);
                }
            }
            TExprKind::Integer(_)
            | TExprKind::Bool(_)
            | TExprKind::ByteString(_)
            | TExprKind::Unit
            | TExprKind::Global(_)
            | TExprKind::Constant(_)
            | TExprKind::FunctionValue(_)
            | TExprKind::LoopExit(_)
            | TExprKind::EmptyArray
            | TExprKind::EmptyList
            | TExprKind::EmptyPool
            | TExprKind::EmptyMap
            | TExprKind::EmptySet
            | TExprKind::EmptyGrid
            | TExprKind::EmptyQueue
            | TExprKind::EmptyRing
            | TExprKind::AsciiEmpty
            | TExprKind::TextEmpty
            | TExprKind::BytesEmpty => {}
        }
    }

    fn record_slot(&mut self, id: usize, ty: Ty) {
        if self.slots.len() <= id {
            self.slots.resize(id + 1, None);
        }
        self.slots[id] = Some(ty);
    }

    fn root_type(&self, id: usize) -> Ty {
        if let Some(global) = global_from_root(id) {
            return self.program.globals[global].ty;
        }
        self.function
            .params
            .iter()
            .find(|param| param.id == id)
            .map(|param| param.ty)
            .or_else(|| self.slots.get(id).and_then(|ty| *ty))
            .expect("local slot type recorded")
    }

    fn emit_collection_lane_pointer(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        index: &str,
        lane: usize,
    ) -> String {
        let (capacity, offset, element, aggregate_lane) =
            match self.program.types[collection_ty.0].kind {
                TTypeKind::Array { element, capacity } => (capacity, 0, element, false),
                TTypeKind::List { element, capacity } => (capacity, 1, element, false),
                TTypeKind::Queue { element, capacity } | TTypeKind::Ring { element, capacity } => {
                    (capacity, 2, element, false)
                }
                TTypeKind::Grid {
                    element, capacity, ..
                } => (capacity, 0, element, false),
                TTypeKind::Pool {
                    element, capacity, ..
                } => (capacity, 6, element, false),
                TTypeKind::Map {
                    value, capacity, ..
                } => (
                    capacity,
                    6,
                    value,
                    matches!(self.program.types[value.0].kind, TTypeKind::Struct(_)),
                ),
                TTypeKind::Set { key, capacity } => (capacity, 5, key, false),
                _ => unreachable!("collection lane pointer requires a fixed collection"),
            };
        let lane_ptr = self.temp();
        let collection_field = if aggregate_lane {
            offset
        } else {
            lane + offset
        };
        self.instruction(format!(
            "{lane_ptr} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 {collection_field}",
            self.lltype(collection_ty),
        ));
        if aggregate_lane {
            let item_ptr = self.temp();
            self.instruction(format!(
                "{item_ptr} = getelementptr inbounds [{} x {}], ptr {lane_ptr}, i32 0, i64 {index}",
                capacity,
                self.lltype(element)
            ));
            let result = self.temp();
            self.instruction(format!(
                "{result} = getelementptr inbounds {}, ptr {item_ptr}, i32 0, i32 {lane}",
                self.lltype(element)
            ));
            result
        } else {
            let lane_ty = collection_lane_types(element, &self.program.types)[lane];
            let item_ptr = self.temp();
            self.instruction(format!(
                "{item_ptr} = getelementptr inbounds [{} x {}], ptr {lane_ptr}, i32 0, i64 {index}",
                capacity,
                self.lltype(lane_ty)
            ));
            item_ptr
        }
    }

    fn emit_collection_var_field_ptr(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        field: usize,
    ) -> String {
        let result = self.temp();
        self.instruction(format!(
            "{result} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 {field}",
            self.lltype(collection_ty)
        ));
        result
    }

    fn emit_collection_var_slot_ptr(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        class: &CollectionVarClass,
        slot: &str,
    ) -> String {
        let capacity = collection_capacity(collection_ty, &self.program.types).unwrap_or(0);
        let storage =
            self.emit_collection_var_field_ptr(collection_ty, pointer, class.storage_field);
        let result = self.temp();
        self.instruction(format!(
            "{result} = getelementptr inbounds [{} x [{} x i8]], ptr {storage}, i32 0, i64 {slot}",
            capacity, class.bytes
        ));
        result
    }

    fn emit_var_lane_old_slot_class(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        lane: usize,
        old_data: &str,
        require_fit: Option<&str>,
    ) -> String {
        let capacity = collection_capacity(collection_ty, &self.program.types).unwrap_or(0);
        let Some(layout) = collection_var_lane(collection_ty, &self.program.types, lane) else {
            return "false".to_owned();
        };
        let old_int = self.temp();
        self.instruction(format!("{old_int} = ptrtoint ptr {old_data} to i64"));
        let mut matched = "false".to_owned();
        for class in layout.classes {
            let base =
                self.emit_collection_var_field_ptr(collection_ty, pointer, class.storage_field);
            let base_int = self.temp();
            self.instruction(format!("{base_int} = ptrtoint ptr {base} to i64"));
            let end_int = self.temp();
            self.instruction(format!(
                "{end_int} = add i64 {base_int}, {}",
                capacity.saturating_mul(class.bytes)
            ));
            let after_start = self.temp();
            self.instruction(format!(
                "{after_start} = icmp uge i64 {old_int}, {base_int}"
            ));
            let before_end = self.temp();
            self.instruction(format!("{before_end} = icmp ult i64 {old_int}, {end_int}"));
            let mut in_class = self.temp();
            self.instruction(format!("{in_class} = and i1 {after_start}, {before_end}"));
            if let Some(length) = require_fit {
                let fits = self.temp();
                self.instruction(format!("{fits} = icmp ule i64 {length}, {}", class.bytes));
                let both = self.temp();
                self.instruction(format!("{both} = and i1 {in_class}, {fits}"));
                in_class = both;
            }
            let either = self.temp();
            self.instruction(format!("{either} = or i1 {matched}, {in_class}"));
            matched = either;
        }
        matched
    }

    fn emit_free_var_lane_slot(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        lane: usize,
        old_data: &str,
    ) {
        let capacity = collection_capacity(collection_ty, &self.program.types).unwrap_or(0);
        let Some(layout) = collection_var_lane(collection_ty, &self.program.types, lane) else {
            return;
        };
        let old_int = self.temp();
        self.instruction(format!("{old_int} = ptrtoint ptr {old_data} to i64"));
        let done = self.new_label("var.slot.free.done");
        let mut next = self.new_label("var.slot.free.inspect");
        self.terminate(format!("br label %{next}"));
        for class in layout.classes {
            self.start_block(&next);
            let after_start = self.temp();
            let base =
                self.emit_collection_var_field_ptr(collection_ty, pointer, class.storage_field);
            let base_int = self.temp();
            self.instruction(format!("{base_int} = ptrtoint ptr {base} to i64"));
            let end_int = self.temp();
            self.instruction(format!(
                "{end_int} = add i64 {base_int}, {}",
                capacity.saturating_mul(class.bytes)
            ));
            self.instruction(format!(
                "{after_start} = icmp uge i64 {old_int}, {base_int}"
            ));
            let before_end = self.temp();
            self.instruction(format!("{before_end} = icmp ult i64 {old_int}, {end_int}"));
            let member = self.temp();
            self.instruction(format!("{member} = and i1 {after_start}, {before_end}"));
            let free_label = self.new_label("var.slot.free.class");
            let following = self.new_label("var.slot.free.next");
            self.terminate(format!(
                "br i1 {member}, label %{free_label}, label %{following}"
            ));
            self.start_block(&free_label);
            if class.bytes > 64 {
                let relative = self.temp();
                self.instruction(format!("{relative} = sub i64 {old_int}, {base_int}"));
                let slot = self.temp();
                self.instruction(format!("{slot} = udiv i64 {relative}, {}", class.bytes));
                let count_ptr = self.emit_collection_var_field_ptr(
                    collection_ty,
                    pointer,
                    class.free_count_field,
                );
                let count = self.temp();
                self.instruction(format!("{count} = load i64, ptr {count_ptr}, align 1"));
                let stack_ptr = self.emit_collection_var_field_ptr(
                    collection_ty,
                    pointer,
                    class.free_stack_field,
                );
                let item = self.temp();
                self.instruction(format!(
                    "{item} = getelementptr inbounds [{} x i64], ptr {stack_ptr}, i32 0, i64 {count}",
                    capacity
                ));
                self.instruction(format!("store i64 {slot}, ptr {item}, align 1"));
                let incremented = self.temp();
                self.instruction(format!("{incremented} = add i64 {count}, 1"));
                self.instruction(format!("store i64 {incremented}, ptr {count_ptr}, align 1"));
            }
            self.terminate(format!("br label %{done}"));
            next = following;
        }
        self.start_block(&next);
        self.terminate(format!("br label %{done}"));
        self.start_block(&done);
    }

    fn emit_alloc_var_lane_slot(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        class: &CollectionVarClass,
    ) -> String {
        let capacity = collection_capacity(collection_ty, &self.program.types).unwrap_or(0);
        let slot_ptr = self.entry_alloca(Ty::Long);
        let count_ptr =
            self.emit_collection_var_field_ptr(collection_ty, pointer, class.free_count_field);
        let count = self.temp();
        self.instruction(format!("{count} = load i64, ptr {count_ptr}, align 1"));
        let has_free = self.temp();
        self.instruction(format!("{has_free} = icmp ne i64 {count}, 0"));
        let reuse = self.new_label("var.slot.alloc.free");
        let fresh = self.new_label("var.slot.alloc.fresh");
        let done = self.new_label("var.slot.alloc.done");
        self.terminate(format!("br i1 {has_free}, label %{reuse}, label %{fresh}"));
        self.start_block(&reuse);
        let top = self.temp();
        self.instruction(format!("{top} = sub i64 {count}, 1"));
        let stack_ptr =
            self.emit_collection_var_field_ptr(collection_ty, pointer, class.free_stack_field);
        let stack_item = self.temp();
        self.instruction(format!(
            "{stack_item} = getelementptr inbounds [{} x i64], ptr {stack_ptr}, i32 0, i64 {top}",
            capacity
        ));
        let slot = self.temp();
        self.instruction(format!("{slot} = load i64, ptr {stack_item}, align 1"));
        self.instruction(format!("store i64 {top}, ptr {count_ptr}, align 1"));
        self.instruction(format!("store i64 {slot}, ptr {slot_ptr}, align 1"));
        self.terminate(format!("br label %{done}"));
        self.start_block(&fresh);
        let next_ptr = self.emit_collection_var_field_ptr(collection_ty, pointer, class.next_field);
        let next = self.temp();
        self.instruction(format!("{next} = load i64, ptr {next_ptr}, align 1"));
        let incremented = self.temp();
        self.instruction(format!("{incremented} = add i64 {next}, 1"));
        self.instruction(format!("store i64 {incremented}, ptr {next_ptr}, align 1"));
        self.instruction(format!("store i64 {next}, ptr {slot_ptr}, align 1"));
        self.terminate(format!("br label %{done}"));
        self.start_block(&done);
        let slot = self.temp();
        self.instruction(format!("{slot} = load i64, ptr {slot_ptr}, align 1"));
        self.emit_collection_var_slot_ptr(collection_ty, pointer, class, &slot)
    }

    fn emit_store_var_lane(
        &mut self,
        collection_ty: Ty,
        collection_pointer: &str,
        index: &str,
        lane: usize,
        source: &str,
    ) {
        let Some(layout) = collection_var_lane(collection_ty, &self.program.types, lane) else {
            return;
        };
        let descriptor =
            self.emit_collection_lane_pointer(collection_ty, collection_pointer, index, lane);
        let old_data_field = self.temp();
        self.instruction(format!(
            "{old_data_field} = getelementptr {}, ptr {descriptor}, i32 0, i32 0",
            self.lltype(layout.ty)
        ));
        let old_data = self.temp();
        self.instruction(format!(
            "{old_data} = load ptr, ptr {old_data_field}, align 1"
        ));
        let source_data_field = self.temp();
        self.instruction(format!(
            "{source_data_field} = getelementptr {}, ptr {source}, i32 0, i32 0",
            self.lltype(layout.ty)
        ));
        let source_data = self.temp();
        self.instruction(format!(
            "{source_data} = load ptr, ptr {source_data_field}, align 1"
        ));
        let source_len_field = self.temp();
        self.instruction(format!(
            "{source_len_field} = getelementptr {}, ptr {source}, i32 0, i32 1",
            self.lltype(layout.ty)
        ));
        let source_len = self.temp();
        self.instruction(format!(
            "{source_len} = load i64, ptr {source_len_field}, align 1"
        ));
        let can_reuse = self.emit_var_lane_old_slot_class(
            collection_ty,
            collection_pointer,
            lane,
            &old_data,
            Some(&source_len),
        );
        let chosen_ptr = self.entry_alloca_raw("ptr");
        let reuse_flag = self.entry_alloca_raw("i1");
        let reuse_label = self.new_label("var.store.reuse");
        let allocate_label = self.new_label("var.store.allocate");
        let select = self.new_label("var.store.select");
        let done = self.new_label("var.store.done");
        self.terminate(format!(
            "br i1 {can_reuse}, label %{reuse_label}, label %{allocate_label}"
        ));
        self.start_block(&reuse_label);
        self.instruction(format!("store ptr {old_data}, ptr {chosen_ptr}, align 1"));
        self.instruction(format!("store i1 true, ptr {reuse_flag}, align 1"));
        self.terminate(format!("br label %{select}"));
        let mut selection = allocate_label;
        for (class_index, class) in layout.classes.iter().enumerate() {
            self.start_block(&selection);
            if class_index + 1 == layout.classes.len() {
                let slot = self.emit_alloc_var_lane_slot(collection_ty, collection_pointer, class);
                self.instruction(format!("store ptr {slot}, ptr {chosen_ptr}, align 1"));
                self.instruction(format!("store i1 false, ptr {reuse_flag}, align 1"));
                self.terminate(format!("br label %{select}"));
            } else {
                let fits = self.temp();
                self.instruction(format!(
                    "{fits} = icmp ule i64 {source_len}, {}",
                    class.bytes
                ));
                let selected = self.new_label("var.store.class");
                let following = self.new_label("var.store.nextclass");
                self.terminate(format!(
                    "br i1 {fits}, label %{selected}, label %{following}"
                ));
                self.start_block(&selected);
                let slot = self.emit_alloc_var_lane_slot(collection_ty, collection_pointer, class);
                self.instruction(format!("store ptr {slot}, ptr {chosen_ptr}, align 1"));
                self.instruction(format!("store i1 false, ptr {reuse_flag}, align 1"));
                self.terminate(format!("br label %{select}"));
                selection = following;
            }
        }
        self.start_block(&select);
        let target_data = self.temp();
        self.instruction(format!(
            "{target_data} = load ptr, ptr {chosen_ptr}, align 1"
        ));
        self.instruction(format!("call void @llvm.memmove.p0.p0.i64(ptr {target_data}, ptr {source_data}, i64 {source_len}, i1 false)"));
        self.instruction(format!(
            "store ptr {target_data}, ptr {old_data_field}, align 1"
        ));
        let destination_len_field = self.temp();
        self.instruction(format!(
            "{destination_len_field} = getelementptr {}, ptr {descriptor}, i32 0, i32 1",
            self.lltype(layout.ty)
        ));
        self.instruction(format!(
            "store i64 {source_len}, ptr {destination_len_field}, align 1"
        ));
        if self.is_text_type(layout.ty) {
            let source_chars_field = self.temp();
            self.instruction(format!(
                "{source_chars_field} = getelementptr {}, ptr {source}, i32 0, i32 2",
                self.lltype(layout.ty)
            ));
            let source_chars = self.temp();
            self.instruction(format!(
                "{source_chars} = load i64, ptr {source_chars_field}, align 1"
            ));
            let destination_chars_field = self.temp();
            self.instruction(format!(
                "{destination_chars_field} = getelementptr {}, ptr {descriptor}, i32 0, i32 2",
                self.lltype(layout.ty)
            ));
            self.instruction(format!(
                "store i64 {source_chars}, ptr {destination_chars_field}, align 1"
            ));
        }
        let reused = self.temp();
        self.instruction(format!("{reused} = load i1, ptr {reuse_flag}, align 1"));
        let free_label = self.new_label("var.store.free.old");
        self.terminate(format!(
            "br i1 {reused}, label %{done}, label %{free_label}"
        ));
        self.start_block(&free_label);
        self.emit_free_var_lane_slot(collection_ty, collection_pointer, lane, &old_data);
        self.terminate(format!("br label %{done}"));
        self.start_block(&done);
        self.instruction(format!(
            "call void @nl_test_var_storage_note(ptr {descriptor}, ptr {target_data}, i64 {source_len})"
        ));
    }

    fn emit_empty_var_pools(&mut self, collection_ty: Ty, destination: &str) {
        for class in collection_var_lanes(collection_ty, &self.program.types)
            .into_iter()
            .flat_map(|lane| lane.classes)
        {
            for field in [class.next_field, class.free_count_field] {
                let field_ptr =
                    self.emit_collection_var_field_ptr(collection_ty, destination, field);
                self.instruction(format!("store i64 0, ptr {field_ptr}, align 1"));
            }
        }
    }

    fn emit_init_var_collection_element(
        &mut self,
        collection_ty: Ty,
        destination: &str,
        index: &str,
    ) {
        for lane in collection_var_lanes(collection_ty, &self.program.types) {
            let descriptor =
                self.emit_collection_lane_pointer(collection_ty, destination, index, lane.lane);
            let data_field = self.temp();
            self.instruction(format!(
                "{data_field} = getelementptr {}, ptr {descriptor}, i32 0, i32 0",
                self.lltype(lane.ty)
            ));
            if let Some(inline) = lane.classes.iter().find(|class| class.bytes <= 64) {
                let data =
                    self.emit_collection_var_slot_ptr(collection_ty, destination, inline, index);
                self.instruction(format!("store ptr {data}, ptr {data_field}, align 1"));
            } else {
                self.instruction(format!("store ptr null, ptr {data_field}, align 1"));
            }
            let length = self.temp();
            self.instruction(format!(
                "{length} = getelementptr {}, ptr {descriptor}, i32 0, i32 1",
                self.lltype(lane.ty)
            ));
            self.instruction(format!("store i64 0, ptr {length}, align 1"));
            if self.is_text_type(lane.ty) {
                let chars = self.temp();
                self.instruction(format!(
                    "{chars} = getelementptr {}, ptr {descriptor}, i32 0, i32 2",
                    self.lltype(lane.ty)
                ));
                self.instruction(format!("store i64 0, ptr {chars}, align 1"));
            }
        }
    }

    fn emit_clear_collection_element(&mut self, collection_ty: Ty, pointer: &str, index: &str) {
        self.instruction("call void @nl_test_var_storage_reset()".to_owned());
        for lane in collection_var_lanes(collection_ty, &self.program.types) {
            let descriptor =
                self.emit_collection_lane_pointer(collection_ty, pointer, index, lane.lane);
            let data_field = self.temp();
            self.instruction(format!(
                "{data_field} = getelementptr {}, ptr {descriptor}, i32 0, i32 0",
                self.lltype(lane.ty)
            ));
            let data = self.temp();
            self.instruction(format!("{data} = load ptr, ptr {data_field}, align 1"));
            self.emit_free_var_lane_slot(collection_ty, pointer, lane.lane, &data);
            if let Some(inline) = lane.classes.iter().find(|class| class.bytes <= 64) {
                let inline_data =
                    self.emit_collection_var_slot_ptr(collection_ty, pointer, inline, index);
                self.instruction(format!(
                    "store ptr {inline_data}, ptr {data_field}, align 1"
                ));
            } else {
                self.instruction(format!("store ptr null, ptr {data_field}, align 1"));
            }
            let length_field = self.temp();
            self.instruction(format!(
                "{length_field} = getelementptr {}, ptr {descriptor}, i32 0, i32 1",
                self.lltype(lane.ty)
            ));
            self.instruction(format!("store i64 0, ptr {length_field}, align 1"));
            if self.is_text_type(lane.ty) {
                let chars_field = self.temp();
                self.instruction(format!(
                    "{chars_field} = getelementptr {}, ptr {descriptor}, i32 0, i32 2",
                    self.lltype(lane.ty)
                ));
                self.instruction(format!("store i64 0, ptr {chars_field}, align 1"));
            }
        }
    }

    fn emit_collection_element(&mut self, collection_ty: Ty, pointer: &str, index: &str) -> String {
        let element = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { element, .. }
            | TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. }
            | TTypeKind::Grid { element, .. }
            | TTypeKind::Pool { element, .. } => element,
            TTypeKind::Map { value, .. } => value,
            TTypeKind::Set { key, .. } => key,
            _ => unreachable!(),
        };
        let index = if matches!(
            self.program.types[collection_ty.0].kind,
            TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
        ) {
            self.emit_queue_ring_physical_index(collection_ty, pointer, index)
        } else {
            index.to_owned()
        };
        if let TTypeKind::Struct(fields) = self.program.types[element.0].kind.clone() {
            let mut value = "zeroinitializer".to_owned();
            for (lane, field) in fields.iter().enumerate() {
                let ptr = self.emit_collection_lane_pointer(collection_ty, pointer, &index, lane);
                let loaded = self.temp();
                self.instruction(format!(
                    "{loaded} = load {}, ptr {ptr}, align 1",
                    self.lltype(field.ty)
                ));
                let next = self.temp();
                self.instruction(format!(
                    "{next} = insertvalue {} {value}, {} {loaded}, {lane}",
                    self.lltype(element),
                    self.lltype(field.ty)
                ));
                value = next;
            }
            value
        } else {
            let ptr = self.emit_collection_lane_pointer(collection_ty, pointer, &index, 0);
            let value = self.temp();
            self.instruction(format!(
                "{value} = load {}, ptr {ptr}, align 1",
                self.lltype(element)
            ));
            value
        }
    }

    fn emit_store_collection_element(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        index: &str,
        value: &str,
    ) {
        let element = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { element, .. }
            | TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. }
            | TTypeKind::Grid { element, .. }
            | TTypeKind::Pool { element, .. } => element,
            TTypeKind::Map { value, .. } => value,
            _ => unreachable!(),
        };
        if !collection_var_lanes(collection_ty, &self.program.types).is_empty() {
            let bytes = stack_storage_size(element, &self.program.types);
            let staged = self.entry_alloca_raw(&format!("[{bytes} x i8]"));
            self.instruction(format!(
                "store {} {value}, ptr {staged}, align 1",
                self.lltype(element)
            ));
            self.emit_scatter_collection_element(collection_ty, pointer, index, &staged);
            return;
        }
        if let TTypeKind::Struct(fields) = self.program.types[element.0].kind.clone() {
            for (lane, field) in fields.iter().enumerate() {
                let lane_value = self.temp();
                self.instruction(format!(
                    "{lane_value} = extractvalue {} {value}, {lane}",
                    self.lltype(element)
                ));
                let ptr = self.emit_collection_lane_pointer(collection_ty, pointer, index, lane);
                self.instruction(format!(
                    "store {} {lane_value}, ptr {ptr}, align 1",
                    self.lltype(field.ty)
                ));
            }
        } else {
            let ptr = self.emit_collection_lane_pointer(collection_ty, pointer, index, 0);
            self.instruction(format!(
                "store {} {value}, ptr {ptr}, align 1",
                self.lltype(element)
            ));
        }
    }

    fn emit_store_collection_element_value(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        index: &str,
        value: &str,
        value_storage: Option<&str>,
    ) {
        if let Some(source) = value_storage {
            self.emit_scatter_collection_element(collection_ty, pointer, index, source);
        } else {
            self.emit_store_collection_element(collection_ty, pointer, index, value);
        }
    }

    fn emit_gather_collection_element(
        &mut self,
        collection_ty: Ty,
        collection_pointer: &str,
        index: &str,
        destination: &str,
    ) {
        let element = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { element, .. }
            | TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. }
            | TTypeKind::Grid { element, .. }
            | TTypeKind::Pool { element, .. } => element,
            TTypeKind::Map { value, .. } => value,
            _ => unreachable!("collection element gather requires an indexed collection"),
        };
        if let TTypeKind::Struct(fields) = self.program.types[element.0].kind.clone() {
            let mut extra_offset = 0usize;
            for (lane, field) in fields.iter().enumerate() {
                if field.ty == Ty::Unit {
                    continue;
                }
                let source = self.emit_collection_lane_pointer(
                    collection_ty,
                    collection_pointer,
                    index,
                    lane,
                );
                let destination_field = self.temp();
                self.instruction(format!(
                    "{destination_field} = getelementptr inbounds {}, ptr {destination}, i32 0, i32 {lane}",
                    self.lltype(element)
                ));
                self.emit_copy_value_rooted(
                    &destination_field,
                    &source,
                    field.ty,
                    destination,
                    element,
                    extra_offset,
                );
                extra_offset = extra_offset.saturating_add(growing_value_extra(
                    field.ty,
                    &self.program.types,
                    &mut vec![false; self.program.types.len()],
                ));
            }
        } else {
            let source =
                self.emit_collection_lane_pointer(collection_ty, collection_pointer, index, 0);
            self.emit_copy_value_storage(destination, &source, element);
        }
    }

    fn emit_scatter_collection_element(
        &mut self,
        collection_ty: Ty,
        collection_pointer: &str,
        index: &str,
        source: &str,
    ) {
        let element = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { element, .. }
            | TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. }
            | TTypeKind::Grid { element, .. }
            | TTypeKind::Pool { element, .. } => element,
            TTypeKind::Map { value, .. } => value,
            _ => unreachable!("collection element scatter requires an indexed collection"),
        };
        let staged = if collection_var_lanes(collection_ty, &self.program.types).is_empty() {
            source.to_owned()
        } else {
            let bytes = stack_storage_size(element, &self.program.types);
            let staged = self.entry_alloca_raw(&format!("[{bytes} x i8]"));
            self.emit_copy_value_storage(&staged, source, element);
            staged
        };
        if let TTypeKind::Struct(fields) = self.program.types[element.0].kind.clone() {
            for (lane, field) in fields.iter().enumerate() {
                if field.ty == Ty::Unit {
                    continue;
                }
                let source_field = self.temp();
                self.instruction(format!(
                    "{source_field} = getelementptr inbounds {}, ptr {staged}, i32 0, i32 {lane}",
                    self.lltype(element)
                ));
                let destination = self.emit_collection_lane_pointer(
                    collection_ty,
                    collection_pointer,
                    index,
                    lane,
                );
                if collection_var_lane(collection_ty, &self.program.types, lane).is_some() {
                    self.emit_store_var_lane(
                        collection_ty,
                        collection_pointer,
                        index,
                        lane,
                        &source_field,
                    );
                } else {
                    self.emit_copy_value_storage(&destination, &source_field, field.ty);
                }
            }
        } else {
            let destination =
                self.emit_collection_lane_pointer(collection_ty, collection_pointer, index, 0);
            if collection_var_lane(collection_ty, &self.program.types, 0).is_some() {
                self.emit_store_var_lane(collection_ty, collection_pointer, index, 0, &staged);
            } else {
                self.emit_copy_value_storage(&destination, &staged, element);
            }
        }
    }

    fn emit_collection_element_storage(
        &mut self,
        collection_ty: Ty,
        collection_pointer: &str,
        logical_index: &str,
        destination: &str,
    ) {
        let index = if matches!(
            self.program.types[collection_ty.0].kind,
            TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
        ) {
            self.emit_queue_ring_physical_index(collection_ty, collection_pointer, logical_index)
        } else {
            logical_index.to_owned()
        };
        self.emit_gather_collection_element(collection_ty, collection_pointer, &index, destination);
    }

    fn emit_sum_payload_pointer(
        &mut self,
        ty: Ty,
        value: &str,
        case_index: usize,
        payload_index: usize,
    ) -> String {
        let case = self.program.types[ty.0].cases()[case_index].clone();
        let offset = case
            .payload
            .iter()
            .take(payload_index)
            .map(|field| {
                type_size(
                    *field,
                    &self.program.types,
                    &mut vec![None; self.program.types.len()],
                )
            })
            .sum::<usize>();
        let payload = self.temp();
        self.instruction(format!(
            "{payload} = getelementptr {}, ptr {value}, i32 0, i32 1",
            self.lltype(ty)
        ));
        let field = self.temp();
        self.instruction(format!(
            "{field} = getelementptr i8, ptr {payload}, i64 {offset}"
        ));
        field
    }

    fn emit_sum_tag_to(&mut self, ty: Ty, destination: &str, case_index: usize) {
        let tag = self.temp();
        self.instruction(format!(
            "{tag} = getelementptr {}, ptr {destination}, i32 0, i32 0",
            self.lltype(ty)
        ));
        self.instruction(format!("store i32 {case_index}, ptr {tag}, align 4"));
    }

    fn emit_sum_empty_case_to(&mut self, ty: Ty, destination: &str, case_index: usize) {
        self.emit_sum_tag_to(ty, destination, case_index);
    }

    fn emit_sum_collection_case_to(
        &mut self,
        ty: Ty,
        destination: &str,
        case_index: usize,
        collection_ty: Ty,
        collection_pointer: &str,
        index: &str,
    ) {
        let field_ty = self.program.types[ty.0].cases()[case_index].payload[0];
        let field_destination = self.emit_sum_payload_pointer(ty, destination, case_index, 0);
        self.emit_collection_element_storage(
            collection_ty,
            collection_pointer,
            index,
            &field_destination,
        );
        self.emit_sum_tag_to(ty, destination, case_index);
        let _ = field_ty;
    }

    fn emit_collection_count(&mut self, collection_ty: Ty, pointer: &str) -> String {
        let count_offset = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { .. } | TTypeKind::Grid { .. } => return "0".to_owned(),
            TTypeKind::Queue { .. } | TTypeKind::Ring { .. } => 1,
            _ => 0,
        };
        let ptr = self.temp();
        self.instruction(format!(
            "{ptr} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 {count_offset}",
            self.lltype(collection_ty)
        ));
        let count = self.temp();
        self.instruction(format!("{count} = load i64, ptr {ptr}, align 1"));
        count
    }

    fn emit_queue_ring_physical_index(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        logical_index: &str,
    ) -> String {
        let capacity = match self.program.types[collection_ty.0].kind {
            TTypeKind::Queue { capacity, .. } | TTypeKind::Ring { capacity, .. } => capacity,
            _ => unreachable!("queue/ring index conversion requires a queue or ring"),
        };
        if capacity == 0 {
            return "0".to_owned();
        }
        let head_ptr = self.temp();
        self.instruction(format!(
            "{head_ptr} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 0",
            self.lltype(collection_ty)
        ));
        let head = self.temp();
        self.instruction(format!("{head} = load i64, ptr {head_ptr}, align 1"));
        let sum = self.temp();
        self.instruction(format!("{sum} = add i64 {head}, {logical_index}"));
        let physical = self.temp();
        self.instruction(format!("{physical} = urem i64 {sum}, {capacity}"));
        physical
    }

    fn emit_queue_ring_meta_ptr(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        field: usize,
    ) -> String {
        let result = self.temp();
        self.instruction(format!(
            "{result} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 {field}",
            self.lltype(collection_ty)
        ));
        result
    }

    fn emit_grid_coord_guard(&mut self, index: &str, bound: usize, span: Span) {
        let negative = self.temp();
        self.instruction(format!("{negative} = icmp slt i64 {index}, 0"));
        let upper = self.temp();
        self.instruction(format!("{upper} = icmp uge i64 {index}, {bound}"));
        let bad = self.temp();
        self.instruction(format!("{bad} = or i1 {negative}, {upper}"));
        self.guard(bad, Failure::IndexOutOfRange, span);
    }

    fn emit_grid_index_value(&mut self, grid: &GridIndexInfo) -> String {
        let x = self.emit_expr(&grid.x);
        if self.terminated {
            return String::new();
        }
        if !grid.proven_x {
            self.emit_grid_coord_guard(&x, grid.width, grid.x.span);
        }
        let y = self.emit_expr(&grid.y);
        if self.terminated {
            return String::new();
        }
        if !grid.proven_y {
            self.emit_grid_coord_guard(&y, grid.height, grid.y.span);
        }
        let row = self.temp();
        self.instruction(format!("{row} = mul i64 {y}, {}", grid.width));
        let flat = self.temp();
        self.instruction(format!("{flat} = add i64 {row}, {x}"));
        flat
    }

    fn emit_projection_index(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        index: &TExpr,
        grid: Option<&GridIndexInfo>,
        proven: bool,
        is_map: bool,
    ) -> String {
        if let Some(grid) = grid {
            return self.emit_grid_index_value(grid);
        }
        let index_value = self.emit_expr(index);
        if !proven && !is_map {
            self.emit_index_guard(collection_ty, pointer, &index_value, false, index.span);
        }
        if matches!(
            self.program.types[collection_ty.0].kind,
            TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
        ) {
            self.emit_queue_ring_physical_index(collection_ty, pointer, &index_value)
        } else {
            index_value
        }
    }

    fn emit_pool_meta_ptr(&mut self, pool_ty: Ty, pointer: &str, field: usize) -> String {
        let result = self.temp();
        self.instruction(format!(
            "{result} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 {field}",
            self.lltype(pool_ty)
        ));
        result
    }

    fn emit_pool_slot_ptr(
        &mut self,
        pool_ty: Ty,
        pointer: &str,
        field: usize,
        index: &str,
    ) -> String {
        let result = self.temp();
        self.instruction(format!(
            "{result} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 {field}, i64 {index}",
            self.lltype(pool_ty)
        ));
        result
    }

    fn emit_map_meta_ptr(&mut self, map_ty: Ty, pointer: &str, field: usize) -> String {
        let result = self.temp();
        self.instruction(format!(
            "{result} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 {field}",
            self.lltype(map_ty)
        ));
        result
    }

    fn emit_map_array_ptr(
        &mut self,
        map_ty: Ty,
        pointer: &str,
        field: usize,
        capacity: usize,
        element_ty: Ty,
        index: &str,
    ) -> String {
        let array = self.emit_map_meta_ptr(map_ty, pointer, field);
        let result = self.temp();
        self.instruction(format!(
            "{result} = getelementptr inbounds [{} x {}], ptr {array}, i32 0, i64 {index}",
            capacity,
            self.lltype(element_ty)
        ));
        result
    }

    fn emit_map_entry_ptr(
        &mut self,
        map_ty: Ty,
        pointer: &str,
        index: &str,
        is_value: bool,
    ) -> String {
        let (capacity, field, element) = match self.program.types[map_ty.0].kind {
            TTypeKind::Map {
                key,
                value,
                capacity,
            } => (
                capacity,
                if is_value { 6 } else { 5 },
                if is_value { value } else { key },
            ),
            TTypeKind::Set { key, capacity } => (capacity, 5, key),
            _ => unreachable!("map entry pointer requires a map or set"),
        };
        self.emit_map_array_ptr(map_ty, pointer, field, capacity, element, index)
    }

    fn emit_map_store_key(
        &mut self,
        map_ty: Ty,
        pointer: &str,
        key_ty: Ty,
        index: &str,
        value: &str,
    ) {
        let Some(max_bytes) = self.ascii_max(key_ty) else {
            let destination = self.emit_map_entry_ptr(map_ty, pointer, index, false);
            self.instruction(format!(
                "store {} {value}, ptr {destination}, align 1",
                self.lltype(key_ty)
            ));
            return;
        };
        let capacity = match self.program.types[map_ty.0].kind {
            TTypeKind::Map { capacity, .. } | TTypeKind::Set { capacity, .. } => capacity,
            _ => unreachable!("ASCII map keys belong to a map or set"),
        };
        let backing_field = match self.program.types[map_ty.0].kind {
            TTypeKind::Map { .. } => 7,
            TTypeKind::Set { .. } => 6,
            _ => unreachable!("ASCII map keys belong to a map or set"),
        };
        let backing = self.emit_map_meta_ptr(map_ty, pointer, backing_field);
        let data = self.temp();
        self.instruction(format!(
            "{data} = getelementptr inbounds [{} x [{} x i8]], ptr {backing}, i32 0, i64 {index}, i64 0",
            capacity, max_bytes
        ));
        let source_data = self.ascii_field(value, key_ty, 0);
        let length = self.ascii_field(value, key_ty, 1);
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {data}, ptr {source_data}, i64 {length}, i1 false)"
        ));
        let destination = self.emit_map_entry_ptr(map_ty, pointer, index, false);
        let data_field = self.temp();
        self.instruction(format!(
            "{data_field} = getelementptr {}, ptr {destination}, i32 0, i32 0",
            self.lltype(key_ty)
        ));
        self.instruction(format!("store ptr {data}, ptr {data_field}, align 1"));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(key_ty)
        ));
        self.instruction(format!("store i64 {length}, ptr {length_field}, align 1"));
    }

    fn emit_hash_fold(&mut self, ty: Ty, value: &str, hash: &str) -> String {
        match &self.program.types[ty.0].kind {
            TTypeKind::Refinement { base, .. } => self.emit_hash_fold(*base, value, hash),
            TTypeKind::Ascii { .. } => {
                let data = self.ascii_field(value, ty, 0);
                let length = self.ascii_field(value, ty, 1);
                let result = self.temp();
                self.instruction(format!(
                    "{result} = call i64 @nl_hash_ascii(ptr {data}, i64 {length}, i64 {hash})"
                ));
                result
            }
            TTypeKind::Int => {
                let widened = self.temp();
                self.instruction(format!("{widened} = sext i32 {value} to i64"));
                self.emit_hash_word(hash, &widened)
            }
            TTypeKind::Long | TTypeKind::Id { .. } => self.emit_hash_word(hash, value),
            TTypeKind::Bool => {
                let widened = self.temp();
                self.instruction(format!("{widened} = zext i1 {value} to i64"));
                self.emit_hash_word(hash, &widened)
            }
            TTypeKind::Struct(fields) => {
                let mut current = hash.to_owned();
                for (index, field) in fields.iter().enumerate() {
                    let item = self.temp();
                    self.instruction(format!(
                        "{item} = extractvalue {} {value}, {index}",
                        self.lltype(ty)
                    ));
                    current = self.emit_hash_fold(field.ty, &item, &current);
                }
                current
            }
            TTypeKind::Enum(_) | TTypeKind::Option(_) | TTypeKind::Result(..) => {
                let tag = self.emit_tag(ty, value);
                let wide_tag = self.temp();
                self.instruction(format!("{wide_tag} = zext i32 {tag} to i64"));
                let with_tag = self.emit_hash_word(hash, &wide_tag);
                let cases = self.program.types[ty.0].cases();
                let labels = (0..cases.len())
                    .map(|_| self.new_label("hash.case"))
                    .collect::<Vec<_>>();
                let invalid = self.new_label("hash.invalid");
                let merge = self.new_label("hash.end");
                let switch = labels
                    .iter()
                    .enumerate()
                    .map(|(index, label)| format!("i32 {index}, label %{label}"))
                    .collect::<Vec<_>>()
                    .join(" ");
                self.terminate(format!("switch i32 {tag}, label %{invalid} [ {switch} ]"));
                self.start_block(&invalid);
                self.terminate("unreachable");
                let mut incoming = Vec::new();
                for (case_index, case) in cases.iter().enumerate() {
                    self.start_block(&labels[case_index]);
                    let mut current = with_tag.clone();
                    for field_index in 0..case.payload.len() {
                        let field = self.emit_payload(ty, value, case_index, field_index).1;
                        current = self.emit_hash_fold(case.payload[field_index], &field, &current);
                    }
                    let predecessor = self.current_label.clone();
                    self.terminate(format!("br label %{merge}"));
                    incoming.push((current, predecessor));
                }
                self.start_block(&merge);
                let result = self.temp();
                let values = incoming
                    .iter()
                    .map(|(value, predecessor)| format!("[ {value}, %{predecessor} ]"))
                    .collect::<Vec<_>>()
                    .join(", ");
                self.instruction(format!("{result} = phi i64 {values}"));
                result
            }
            _ => unreachable!("unhashable key reached native hashing"),
        }
    }

    fn emit_hash_word(&mut self, hash: &str, word: &str) -> String {
        let mixed = self.temp();
        self.instruction(format!("{mixed} = xor i64 {hash}, {word}"));
        let result = self.temp();
        self.instruction(format!("{result} = mul i64 {mixed}, 1099511628211"));
        result
    }

    fn emit_hash(&mut self, ty: Ty, value: &str) -> String {
        self.emit_hash_fold(ty, value, "1469598103934665603")
    }

    fn emit_map_lookup(
        &mut self,
        map_ty: Ty,
        pointer: &str,
        key_ty: Ty,
        key: &str,
        capacity: usize,
    ) -> (String, String, String) {
        if capacity == 0 {
            return ("-1".to_owned(), "-1".to_owned(), "0".to_owned());
        }
        let hash = self.emit_hash(key_ty, key);
        let entry_out = self.entry_alloca(Ty::Long);
        let bucket_out = self.entry_alloca(Ty::Long);
        let first_tombstone = self.entry_alloca(Ty::Long);
        let slot_ptr = self.entry_alloca(Ty::Long);
        let probe_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 -1, ptr {entry_out}, align 1"));
        self.instruction(format!("store i64 -1, ptr {bucket_out}, align 1"));
        self.instruction(format!("store i64 -1, ptr {first_tombstone}, align 1"));
        self.instruction(format!("store i64 0, ptr {probe_ptr}, align 1"));
        let initial_slot = self.temp();
        self.instruction(format!("{initial_slot} = urem i64 {hash}, {capacity}"));
        self.instruction(format!("store i64 {initial_slot}, ptr {slot_ptr}, align 1"));
        let condition = self.new_label("map.lookup.cond");
        let inspect = self.new_label("map.lookup.inspect");
        let empty = self.new_label("map.lookup.empty");
        let tombstone = self.new_label("map.lookup.tombstone");
        let occupied = self.new_label("map.lookup.occupied");
        let live = self.new_label("map.lookup.live");
        let found = self.new_label("map.lookup.found");
        let advance = self.new_label("map.lookup.advance");
        let done = self.new_label("map.lookup.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let probe = self.temp();
        self.instruction(format!("{probe} = load i64, ptr {probe_ptr}, align 1"));
        let within = self.temp();
        self.instruction(format!("{within} = icmp ult i64 {probe}, {capacity}"));
        self.terminate(format!("br i1 {within}, label %{inspect}, label %{done}"));
        self.start_block(&inspect);
        let slot = self.temp();
        self.instruction(format!("{slot} = load i64, ptr {slot_ptr}, align 1"));
        let bucket_ptr = self.emit_map_array_ptr(map_ty, pointer, 4, capacity, Ty::Long, &slot);
        let bucket = self.temp();
        self.instruction(format!("{bucket} = load i64, ptr {bucket_ptr}, align 1"));
        let is_empty = self.temp();
        self.instruction(format!("{is_empty} = icmp eq i64 {bucket}, 0"));
        self.terminate(format!(
            "br i1 {is_empty}, label %{empty}, label %{occupied}"
        ));
        self.start_block(&empty);
        let first = self.temp();
        self.instruction(format!(
            "{first} = load i64, ptr {first_tombstone}, align 1"
        ));
        let has_tombstone = self.temp();
        self.instruction(format!("{has_tombstone} = icmp sge i64 {first}, 0"));
        let candidate = self.temp();
        self.instruction(format!(
            "{candidate} = select i1 {has_tombstone}, i64 {first}, i64 {slot}"
        ));
        self.instruction(format!("store i64 {candidate}, ptr {bucket_out}, align 1"));
        self.terminate(format!("br label %{done}"));
        self.start_block(&occupied);
        let is_tombstone = self.temp();
        self.instruction(format!("{is_tombstone} = icmp slt i64 {bucket}, 0"));
        self.terminate(format!(
            "br i1 {is_tombstone}, label %{tombstone}, label %{live}"
        ));
        self.start_block(&tombstone);
        let previous_tombstone = self.temp();
        self.instruction(format!(
            "{previous_tombstone} = load i64, ptr {first_tombstone}, align 1"
        ));
        let first_empty = self.temp();
        self.instruction(format!(
            "{first_empty} = icmp slt i64 {previous_tombstone}, 0"
        ));
        let keep = self.temp();
        self.instruction(format!(
            "{keep} = select i1 {first_empty}, i64 {slot}, i64 {previous_tombstone}"
        ));
        self.instruction(format!("store i64 {keep}, ptr {first_tombstone}, align 1"));
        self.terminate(format!("br label %{advance}"));
        self.start_block(&live);
        let is_live = self.temp();
        self.instruction(format!("{is_live} = icmp sgt i64 {bucket}, 0"));
        let continue_label = self.new_label("map.lookup.continue");
        self.terminate(format!(
            "br i1 {is_live}, label %{continue_label}, label %{advance}"
        ));
        self.start_block(&continue_label);
        let entry = self.temp();
        self.instruction(format!("{entry} = sub i64 {bucket}, 1"));
        let stored_hash_ptr =
            self.emit_map_array_ptr(map_ty, pointer, 3, capacity, Ty::Long, &entry);
        let stored_hash = self.temp();
        self.instruction(format!(
            "{stored_hash} = load i64, ptr {stored_hash_ptr}, align 1"
        ));
        let same_hash = self.temp();
        self.instruction(format!("{same_hash} = icmp eq i64 {stored_hash}, {hash}"));
        let compare = self.new_label("map.lookup.compare");
        self.terminate(format!(
            "br i1 {same_hash}, label %{compare}, label %{advance}"
        ));
        self.start_block(&compare);
        let stored_key_ptr = self.emit_map_entry_ptr(map_ty, pointer, &entry, false);
        let stored_key = self.temp();
        self.instruction(format!(
            "{stored_key} = load {}, ptr {stored_key_ptr}, align 1",
            self.lltype(key_ty)
        ));
        let equal = self.emit_binary(BinaryOp::Eq, key_ty, &stored_key, key, Span::default());
        self.terminate(format!("br i1 {equal}, label %{found}, label %{advance}"));
        self.start_block(&found);
        self.instruction(format!("store i64 {entry}, ptr {entry_out}, align 1"));
        self.instruction(format!("store i64 {slot}, ptr {bucket_out}, align 1"));
        self.terminate(format!("br label %{done}"));
        self.start_block(&advance);
        let next_slot = self.temp();
        self.instruction(format!("{next_slot} = add i64 {slot}, 1"));
        let wraps = self.temp();
        self.instruction(format!("{wraps} = icmp eq i64 {next_slot}, {capacity}"));
        let wrapped_slot = self.temp();
        self.instruction(format!(
            "{wrapped_slot} = select i1 {wraps}, i64 0, i64 {next_slot}"
        ));
        self.instruction(format!("store i64 {wrapped_slot}, ptr {slot_ptr}, align 1"));
        let next_probe = self.temp();
        self.instruction(format!("{next_probe} = add i64 {probe}, 1"));
        self.instruction(format!("store i64 {next_probe}, ptr {probe_ptr}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
        let result_entry = self.temp();
        let result_bucket = self.temp();
        self.instruction(format!(
            "{result_entry} = load i64, ptr {entry_out}, align 1"
        ));
        self.instruction(format!(
            "{result_bucket} = load i64, ptr {bucket_out}, align 1"
        ));
        let has_bucket = self.temp();
        self.instruction(format!("{has_bucket} = icmp sge i64 {result_bucket}, 0"));
        let tombstone = self.temp();
        self.instruction(format!(
            "{tombstone} = load i64, ptr {first_tombstone}, align 1"
        ));
        let has_tombstone = self.temp();
        self.instruction(format!("{has_tombstone} = icmp sge i64 {tombstone}, 0"));
        let no_bucket = self.temp();
        self.instruction(format!("{no_bucket} = xor i1 {has_bucket}, true"));
        let use_tombstone = self.temp();
        self.instruction(format!(
            "{use_tombstone} = and i1 {has_tombstone}, {no_bucket}"
        ));
        let final_bucket = self.temp();
        self.instruction(format!(
            "{final_bucket} = select i1 {use_tombstone}, i64 {tombstone}, i64 {result_bucket}"
        ));
        (result_entry, final_bucket, hash)
    }

    fn emit_map_compact(
        &mut self,
        map_ty: Ty,
        pointer: &str,
        capacity: usize,
        value_ty: Option<Ty>,
    ) {
        if capacity == 0 {
            return;
        }
        let end_ptr = self.emit_map_meta_ptr(map_ty, pointer, 1);
        let old_end = self.temp();
        self.instruction(format!("{old_end} = load i64, ptr {end_ptr}, align 1"));
        let source_ptr = self.entry_alloca(Ty::Long);
        let destination_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {source_ptr}, align 1"));
        self.instruction(format!("store i64 0, ptr {destination_ptr}, align 1"));
        let condition = self.new_label("map.compact.cond");
        let inspect = self.new_label("map.compact.inspect");
        let copy = self.new_label("map.compact.copy");
        let skip = self.new_label("map.compact.skip");
        let copied = self.new_label("map.compact.copied");
        let moved = self.new_label("map.compact.moved");
        let step = self.new_label("map.compact.step");
        let done = self.new_label("map.compact.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let source = self.temp();
        self.instruction(format!("{source} = load i64, ptr {source_ptr}, align 1"));
        let within = self.temp();
        self.instruction(format!("{within} = icmp ult i64 {source}, {old_end}"));
        self.terminate(format!("br i1 {within}, label %{inspect}, label %{done}"));
        self.start_block(&inspect);
        let active_ptr = self.emit_map_array_ptr(map_ty, pointer, 2, capacity, Ty::Bool, &source);
        let active = self.temp();
        self.instruction(format!("{active} = load i1, ptr {active_ptr}, align 1"));
        self.terminate(format!("br i1 {active}, label %{copy}, label %{skip}"));
        self.start_block(&copy);
        let destination = self.temp();
        self.instruction(format!(
            "{destination} = load i64, ptr {destination_ptr}, align 1"
        ));
        let key_ty = match self.program.types[map_ty.0].kind {
            TTypeKind::Map { key, .. } | TTypeKind::Set { key, .. } => key,
            _ => unreachable!(),
        };
        let key_source = self.emit_map_entry_ptr(map_ty, pointer, &source, false);
        let key_value = self.temp();
        self.instruction(format!(
            "{key_value} = load {}, ptr {key_source}, align 1",
            self.lltype(key_ty)
        ));
        self.emit_map_store_key(map_ty, pointer, key_ty, &destination, &key_value);
        let hash_source = self.emit_map_array_ptr(map_ty, pointer, 3, capacity, Ty::Long, &source);
        let hash_value = self.temp();
        self.instruction(format!(
            "{hash_value} = load i64, ptr {hash_source}, align 1"
        ));
        let hash_destination =
            self.emit_map_array_ptr(map_ty, pointer, 3, capacity, Ty::Long, &destination);
        self.instruction(format!(
            "store i64 {hash_value}, ptr {hash_destination}, align 1"
        ));
        if let Some(value_ty) = value_ty {
            let value_source = self.emit_map_entry_ptr(map_ty, pointer, &source, true);
            if collection_var_lanes(map_ty, &self.program.types).is_empty() {
                let value_destination =
                    self.emit_map_entry_ptr(map_ty, pointer, &destination, true);
                self.emit_copy_value_storage(&value_destination, &value_source, value_ty);
            } else {
                self.emit_copy_collection_element(pointer, pointer, map_ty, &destination, &source);
            }
        }
        let active_destination =
            self.emit_map_array_ptr(map_ty, pointer, 2, capacity, Ty::Bool, &destination);
        self.instruction(format!("store i1 true, ptr {active_destination}, align 1"));
        let same = self.temp();
        self.instruction(format!("{same} = icmp eq i64 {source}, {destination}"));
        self.terminate(format!("br i1 {same}, label %{copied}, label %{moved}"));
        self.start_block(&moved);
        let inactive_source =
            self.emit_map_array_ptr(map_ty, pointer, 2, capacity, Ty::Bool, &source);
        self.instruction(format!("store i1 false, ptr {inactive_source}, align 1"));
        self.terminate(format!("br label %{step}"));
        self.start_block(&copied);
        self.terminate(format!("br label %{step}"));
        self.start_block(&step);
        let destination = self.temp();
        self.instruction(format!(
            "{destination} = load i64, ptr {destination_ptr}, align 1"
        ));
        let next_destination = self.temp();
        self.instruction(format!("{next_destination} = add i64 {destination}, 1"));
        self.instruction(format!(
            "store i64 {next_destination}, ptr {destination_ptr}, align 1"
        ));
        let source = self.temp();
        self.instruction(format!("{source} = load i64, ptr {source_ptr}, align 1"));
        let next_source = self.temp();
        self.instruction(format!("{next_source} = add i64 {source}, 1"));
        self.instruction(format!(
            "store i64 {next_source}, ptr {source_ptr}, align 1"
        ));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&skip);
        let source = self.temp();
        self.instruction(format!("{source} = load i64, ptr {source_ptr}, align 1"));
        let next_source = self.temp();
        self.instruction(format!("{next_source} = add i64 {source}, 1"));
        self.instruction(format!(
            "store i64 {next_source}, ptr {source_ptr}, align 1"
        ));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
        let new_end = self.temp();
        self.instruction(format!(
            "{new_end} = load i64, ptr {destination_ptr}, align 1"
        ));
        let count_ptr = self.emit_map_meta_ptr(map_ty, pointer, 0);
        self.instruction(format!("store i64 {new_end}, ptr {count_ptr}, align 1"));
        self.instruction(format!("store i64 {new_end}, ptr {end_ptr}, align 1"));
        let bucket_clear_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {bucket_clear_ptr}, align 1"));
        let clear_cond = self.new_label("map.compact.clear.cond");
        let clear_body = self.new_label("map.compact.clear.body");
        let clear_done = self.new_label("map.compact.clear.done");
        self.terminate(format!("br label %{clear_cond}"));
        self.start_block(&clear_cond);
        let clear_index = self.temp();
        self.instruction(format!(
            "{clear_index} = load i64, ptr {bucket_clear_ptr}, align 1"
        ));
        let clear_more = self.temp();
        self.instruction(format!(
            "{clear_more} = icmp ult i64 {clear_index}, {capacity}"
        ));
        self.terminate(format!(
            "br i1 {clear_more}, label %{clear_body}, label %{clear_done}"
        ));
        self.start_block(&clear_body);
        let bucket = self.emit_map_array_ptr(map_ty, pointer, 4, capacity, Ty::Long, &clear_index);
        self.instruction(format!("store i64 0, ptr {bucket}, align 1"));
        let clear_next = self.temp();
        self.instruction(format!("{clear_next} = add i64 {clear_index}, 1"));
        self.instruction(format!(
            "store i64 {clear_next}, ptr {bucket_clear_ptr}, align 1"
        ));
        self.terminate(format!("br label %{clear_cond}"));
        self.start_block(&clear_done);
        let rehash_index_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {rehash_index_ptr}, align 1"));
        let rehash_cond = self.new_label("map.compact.rehash.cond");
        let rehash_body = self.new_label("map.compact.rehash.body");
        let probe_cond = self.new_label("map.compact.probe.cond");
        let probe_body = self.new_label("map.compact.probe.body");
        let probe_advance = self.new_label("map.compact.probe.advance");
        let rehash_done = self.new_label("map.compact.rehash.done");
        let all_rehashed = self.new_label("map.compact.rehash.all_done");
        self.terminate(format!("br label %{rehash_cond}"));
        self.start_block(&rehash_cond);
        let rehash_index = self.temp();
        self.instruction(format!(
            "{rehash_index} = load i64, ptr {rehash_index_ptr}, align 1"
        ));
        let rehash_more = self.temp();
        self.instruction(format!(
            "{rehash_more} = icmp ult i64 {rehash_index}, {new_end}"
        ));
        self.terminate(format!(
            "br i1 {rehash_more}, label %{rehash_body}, label %{all_rehashed}"
        ));
        self.start_block(&rehash_body);
        let stored_hash_ptr =
            self.emit_map_array_ptr(map_ty, pointer, 3, capacity, Ty::Long, &rehash_index);
        let stored_hash = self.temp();
        self.instruction(format!(
            "{stored_hash} = load i64, ptr {stored_hash_ptr}, align 1"
        ));
        let initial = self.temp();
        self.instruction(format!("{initial} = urem i64 {stored_hash}, {capacity}"));
        let rehash_slot_ptr = self.entry_alloca(Ty::Long);
        let rehash_probe_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!(
            "store i64 {initial}, ptr {rehash_slot_ptr}, align 1"
        ));
        self.instruction(format!("store i64 0, ptr {rehash_probe_ptr}, align 1"));
        self.terminate(format!("br label %{probe_cond}"));
        self.start_block(&probe_cond);
        let rehash_slot = self.temp();
        self.instruction(format!(
            "{rehash_slot} = load i64, ptr {rehash_slot_ptr}, align 1"
        ));
        let rehash_bucket_ptr =
            self.emit_map_array_ptr(map_ty, pointer, 4, capacity, Ty::Long, &rehash_slot);
        let rehash_bucket = self.temp();
        self.instruction(format!(
            "{rehash_bucket} = load i64, ptr {rehash_bucket_ptr}, align 1"
        ));
        let empty_bucket = self.temp();
        self.instruction(format!("{empty_bucket} = icmp eq i64 {rehash_bucket}, 0"));
        let probe = self.temp();
        self.instruction(format!(
            "{probe} = load i64, ptr {rehash_probe_ptr}, align 1"
        ));
        let probe_bound = self.temp();
        self.instruction(format!("{probe_bound} = icmp ult i64 {probe}, {capacity}"));
        let can_insert = self.temp();
        self.instruction(format!(
            "{can_insert} = and i1 {empty_bucket}, {probe_bound}"
        ));
        self.terminate(format!(
            "br i1 {can_insert}, label %{probe_body}, label %{probe_advance}"
        ));
        self.start_block(&probe_body);
        let encoded = self.temp();
        self.instruction(format!("{encoded} = add i64 {rehash_index}, 1"));
        self.instruction(format!(
            "store i64 {encoded}, ptr {rehash_bucket_ptr}, align 1"
        ));
        self.terminate(format!("br label %{rehash_done}"));
        self.start_block(&probe_advance);
        let continue_label = self.new_label("map.compact.probe.next");
        self.terminate(format!(
            "br i1 {probe_bound}, label %{continue_label}, label %{rehash_done}"
        ));
        self.start_block(&continue_label);
        let rehash_slot = self.temp();
        self.instruction(format!(
            "{rehash_slot} = load i64, ptr {rehash_slot_ptr}, align 1"
        ));
        let next_slot = self.temp();
        self.instruction(format!("{next_slot} = add i64 {rehash_slot}, 1"));
        let wraps = self.temp();
        self.instruction(format!("{wraps} = icmp eq i64 {next_slot}, {capacity}"));
        let wrapped = self.temp();
        self.instruction(format!(
            "{wrapped} = select i1 {wraps}, i64 0, i64 {next_slot}"
        ));
        self.instruction(format!(
            "store i64 {wrapped}, ptr {rehash_slot_ptr}, align 1"
        ));
        let probe = self.temp();
        self.instruction(format!(
            "{probe} = load i64, ptr {rehash_probe_ptr}, align 1"
        ));
        let next_probe = self.temp();
        self.instruction(format!("{next_probe} = add i64 {probe}, 1"));
        self.instruction(format!(
            "store i64 {next_probe}, ptr {rehash_probe_ptr}, align 1"
        ));
        self.terminate(format!("br label %{probe_cond}"));
        self.start_block(&rehash_done);
        let rehash_index = self.temp();
        self.instruction(format!(
            "{rehash_index} = load i64, ptr {rehash_index_ptr}, align 1"
        ));
        let next_index = self.temp();
        self.instruction(format!("{next_index} = add i64 {rehash_index}, 1"));
        self.instruction(format!(
            "store i64 {next_index}, ptr {rehash_index_ptr}, align 1"
        ));
        self.terminate(format!("br label %{rehash_cond}"));
        self.start_block(&all_rehashed);
    }

    fn emit_map_insert_entry(
        &mut self,
        map_ty: Ty,
        pointer: &str,
        key_ty: Ty,
        key: &str,
        hash: &str,
        bucket: &str,
        value_ty: Option<Ty>,
        value: Option<&str>,
        value_storage: Option<&str>,
        capacity: usize,
    ) {
        debug_assert!(capacity > 0);
        let end_ptr = self.emit_map_meta_ptr(map_ty, pointer, 1);
        let end = self.temp();
        self.instruction(format!("{end} = load i64, ptr {end_ptr}, align 1"));
        let needs_compaction = self.temp();
        self.instruction(format!(
            "{needs_compaction} = icmp uge i64 {end}, {capacity}"
        ));
        let compact = self.new_label("map.insert.compact");
        let append = self.new_label("map.insert.append");
        let ready = self.new_label("map.insert.ready");
        self.terminate(format!(
            "br i1 {needs_compaction}, label %{compact}, label %{append}"
        ));
        self.start_block(&append);
        let append_pred = self.current_label.clone();
        self.terminate(format!("br label %{ready}"));
        self.start_block(&compact);
        let value_kind = match self.program.types[map_ty.0].kind {
            TTypeKind::Map { value, .. } => Some(value),
            TTypeKind::Set { .. } => None,
            _ => unreachable!(),
        };
        self.emit_map_compact(map_ty, pointer, capacity, value_kind);
        let (_, compact_bucket, _) = self.emit_map_lookup(map_ty, pointer, key_ty, key, capacity);
        let compact_pred = self.current_label.clone();
        self.terminate(format!("br label %{ready}"));
        self.start_block(&ready);
        let final_bucket = self.temp();
        self.instruction(format!(
            "{final_bucket} = phi i64 [ {bucket}, %{append_pred} ], [ {compact_bucket}, %{compact_pred} ]"
        ));
        let entry = self.temp();
        self.instruction(format!("{entry} = load i64, ptr {end_ptr}, align 1"));
        self.emit_init_var_collection_element(map_ty, pointer, &entry);
        self.emit_map_store_key(map_ty, pointer, key_ty, &entry, key);
        let hash_ptr = self.emit_map_array_ptr(map_ty, pointer, 3, capacity, Ty::Long, &entry);
        self.instruction(format!("store i64 {hash}, ptr {hash_ptr}, align 1"));
        let active_ptr = self.emit_map_array_ptr(map_ty, pointer, 2, capacity, Ty::Bool, &entry);
        self.instruction(format!("store i1 true, ptr {active_ptr}, align 1"));
        if let (Some(value_ty), Some(value)) = (value_ty, value) {
            let value_ptr = self.emit_map_entry_ptr(map_ty, pointer, &entry, true);
            if let Some(source) = value_storage {
                if collection_var_lanes(map_ty, &self.program.types).is_empty() {
                    self.emit_copy_value_storage(&value_ptr, source, value_ty);
                } else {
                    self.emit_scatter_collection_element(map_ty, pointer, &entry, source);
                }
            } else {
                self.instruction(format!(
                    "store {} {value}, ptr {value_ptr}, align 1",
                    self.lltype(value_ty)
                ));
            }
        }
        let encoded = self.temp();
        self.instruction(format!("{encoded} = add i64 {entry}, 1"));
        let bucket_ptr =
            self.emit_map_array_ptr(map_ty, pointer, 4, capacity, Ty::Long, &final_bucket);
        self.instruction(format!("store i64 {encoded}, ptr {bucket_ptr}, align 1"));
        let count_ptr = self.emit_map_meta_ptr(map_ty, pointer, 0);
        let count = self.temp();
        self.instruction(format!("{count} = load i64, ptr {count_ptr}, align 1"));
        let count_next = self.temp();
        self.instruction(format!("{count_next} = add i64 {count}, 1"));
        self.instruction(format!("store i64 {count_next}, ptr {count_ptr}, align 1"));
        let end_next = self.temp();
        self.instruction(format!("{end_next} = add i64 {entry}, 1"));
        self.instruction(format!("store i64 {end_next}, ptr {end_ptr}, align 1"));
    }

    fn emit_map_op(
        &mut self,
        expr: &TExpr,
        op: MapOp,
        receiver: &TExpr,
        args: &[TExpr],
        capacity: usize,
        proven_success: bool,
        result_destination: Option<&str>,
    ) -> String {
        let map_ty = receiver.ty;
        let (key_ty, value_ty) = match self.program.types[map_ty.0].kind {
            TTypeKind::Map { key, value, .. } => (key, value),
            _ => unreachable!(),
        };
        let pointer = if Self::expr_place(receiver).is_some() {
            self.emit_place_pointer_expr(receiver)
        } else {
            self.emit_expr_storage(receiver)
        };
        if self.terminated {
            return String::new();
        }
        if op == MapOp::Count {
            return self.emit_collection_count(map_ty, &pointer);
        }
        let mut values = Vec::with_capacity(args.len());
        let mut value_storages = Vec::with_capacity(args.len());
        for (index, arg) in args.iter().enumerate() {
            if index != 0 && is_large_type(arg.ty, &self.program.types) {
                values.push("zeroinitializer".to_owned());
                value_storages.push(Some(self.emit_expr_storage(arg)));
            } else {
                values.push(self.emit_expr(arg));
                value_storages.push(None);
            }
            if self.terminated {
                return String::new();
            }
        }
        let (entry, bucket, hash) =
            self.emit_map_lookup(map_ty, &pointer, key_ty, &values[0], capacity);
        match op {
            MapOp::Get | MapOp::Remove => {
                let found = self.temp();
                self.instruction(format!("{found} = icmp sge i64 {entry}, 0"));
                let present = self.new_label("map.get.present");
                let absent = self.new_label("map.get.absent");
                let merge = self.new_label("map.get.end");
                self.terminate(format!("br i1 {found}, label %{present}, label %{absent}"));
                self.start_block(&absent);
                if let Some(destination) = result_destination {
                    self.emit_sum_empty_case_to(expr.ty, destination, 1);
                    self.terminate(format!("br label %{merge}"));
                    self.start_block(&present);
                    let value_ptr = self.emit_map_entry_ptr(map_ty, &pointer, &entry, true);
                    let payload = self.emit_sum_payload_pointer(expr.ty, destination, 0, 0);
                    self.emit_copy_value_storage(&payload, &value_ptr, value_ty);
                    if op == MapOp::Remove {
                        self.emit_clear_collection_element(map_ty, &pointer, &entry);
                        let active_ptr = self.emit_map_array_ptr(
                            map_ty,
                            &pointer,
                            2,
                            capacity,
                            Ty::Bool,
                            &entry,
                        );
                        self.instruction(format!("store i1 false, ptr {active_ptr}, align 1"));
                        let bucket_ptr = self.emit_map_array_ptr(
                            map_ty,
                            &pointer,
                            4,
                            capacity,
                            Ty::Long,
                            &bucket,
                        );
                        self.instruction(format!("store i64 -1, ptr {bucket_ptr}, align 1"));
                        let count_ptr = self.emit_map_meta_ptr(map_ty, &pointer, 0);
                        let count = self.temp();
                        self.instruction(format!("{count} = load i64, ptr {count_ptr}, align 1"));
                        let next = self.temp();
                        self.instruction(format!("{next} = sub i64 {count}, 1"));
                        self.instruction(format!("store i64 {next}, ptr {count_ptr}, align 1"));
                    }
                    self.emit_sum_tag_to(expr.ty, destination, 0);
                    self.terminate(format!("br label %{merge}"));
                    self.start_block(&merge);
                    return String::new();
                }
                let none = self.emit_construct_values(expr.ty, 1, Vec::new());
                let absent_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&present);
                let value_ptr = self.emit_map_entry_ptr(map_ty, &pointer, &entry, true);
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {value_ptr}, align 1",
                    self.lltype(value_ty)
                ));
                if op == MapOp::Remove {
                    self.emit_clear_collection_element(map_ty, &pointer, &entry);
                    let active_ptr =
                        self.emit_map_array_ptr(map_ty, &pointer, 2, capacity, Ty::Bool, &entry);
                    self.instruction(format!("store i1 false, ptr {active_ptr}, align 1"));
                    let bucket_ptr =
                        self.emit_map_array_ptr(map_ty, &pointer, 4, capacity, Ty::Long, &bucket);
                    self.instruction(format!("store i64 -1, ptr {bucket_ptr}, align 1"));
                    let count_ptr = self.emit_map_meta_ptr(map_ty, &pointer, 0);
                    let count = self.temp();
                    self.instruction(format!("{count} = load i64, ptr {count_ptr}, align 1"));
                    let next = self.temp();
                    self.instruction(format!("{next} = sub i64 {count}, 1"));
                    self.instruction(format!("store i64 {next}, ptr {count_ptr}, align 1"));
                }
                let some = self.emit_construct_values(expr.ty, 0, vec![(value_ty, value)]);
                let present_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&merge);
                let result = self.temp();
                self.instruction(format!(
                    "{result} = phi {} [ {none}, %{absent_pred} ], [ {some}, %{present_pred} ]",
                    self.lltype(expr.ty)
                ));
                result
            }
            MapOp::Contains => {
                let found = self.temp();
                self.instruction(format!("{found} = icmp sge i64 {entry}, 0"));
                found
            }
            MapOp::Set => {
                let found = self.temp();
                self.instruction(format!("{found} = icmp sge i64 {entry}, 0"));
                let update = self.new_label("map.set.update");
                let insert_or_full = self.new_label("map.set.new");
                let merge = self.new_label("map.set.end");
                self.terminate(format!(
                    "br i1 {found}, label %{update}, label %{insert_or_full}"
                ));
                self.start_block(&update);
                let value_ptr = self.emit_map_entry_ptr(map_ty, &pointer, &entry, true);
                if let Some(source) = value_storages[1].as_deref() {
                    if collection_var_lanes(map_ty, &self.program.types).is_empty() {
                        self.emit_copy_value_storage(&value_ptr, source, value_ty);
                    } else {
                        self.emit_scatter_collection_element(map_ty, &pointer, &entry, source);
                    }
                } else {
                    self.instruction(format!(
                        "store {} {}, ptr {value_ptr}, align 1",
                        self.lltype(value_ty),
                        values[1]
                    ));
                }
                let ok = self.emit_construct_values(expr.ty, 0, vec![(Ty::Unit, String::new())]);
                let update_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&insert_or_full);
                let insert = self.new_label("map.set.insert");
                let full = self.new_label("map.set.full");
                if proven_success {
                    self.terminate(format!("br label %{insert}"));
                } else {
                    let count = self.emit_collection_count(map_ty, &pointer);
                    let is_full = self.temp();
                    self.instruction(format!("{is_full} = icmp uge i64 {count}, {capacity}"));
                    self.terminate(format!("br i1 {is_full}, label %{full}, label %{insert}"));
                }
                self.start_block(&full);
                let error_ty = self.program.types[expr.ty.0].cases()[1].payload[0];
                let full_value = self.emit_construct_values(error_ty, 0, Vec::new());
                let failed = self.emit_construct_values(expr.ty, 1, vec![(error_ty, full_value)]);
                let full_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&insert);
                if capacity > 0 {
                    self.emit_map_insert_entry(
                        map_ty,
                        &pointer,
                        key_ty,
                        &values[0],
                        &hash,
                        &bucket,
                        Some(value_ty),
                        Some(&values[1]),
                        value_storages[1].as_deref(),
                        capacity,
                    );
                }
                let inserted =
                    self.emit_construct_values(expr.ty, 0, vec![(Ty::Unit, String::new())]);
                let insert_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&merge);
                let result = self.temp();
                self.instruction(format!("{result} = phi {} [ {ok}, %{update_pred} ], [ {failed}, %{full_pred} ], [ {inserted}, %{insert_pred} ]", self.lltype(expr.ty)));
                result
            }
            MapOp::Count => unreachable!(),
        }
    }

    fn emit_set_op(
        &mut self,
        expr: &TExpr,
        op: SetOp,
        receiver: &TExpr,
        args: &[TExpr],
        capacity: usize,
        proven_success: bool,
    ) -> String {
        let set_ty = receiver.ty;
        let key_ty = match self.program.types[set_ty.0].kind {
            TTypeKind::Set { key, .. } => key,
            _ => unreachable!(),
        };
        let pointer = if Self::expr_place(receiver).is_some() {
            self.emit_place_pointer_expr(receiver)
        } else {
            self.emit_expr_storage(receiver)
        };
        if self.terminated {
            return String::new();
        }
        if op == SetOp::Count {
            return self.emit_collection_count(set_ty, &pointer);
        }
        let key = self.emit_expr(&args[0]);
        if self.terminated {
            return String::new();
        }
        let (entry, bucket, hash) = self.emit_map_lookup(set_ty, &pointer, key_ty, &key, capacity);
        match op {
            SetOp::Contains => {
                let found = self.temp();
                self.instruction(format!("{found} = icmp sge i64 {entry}, 0"));
                found
            }
            SetOp::Remove => {
                let found = self.temp();
                self.instruction(format!("{found} = icmp sge i64 {entry}, 0"));
                let remove = self.new_label("set.remove");
                let absent = self.new_label("set.absent");
                let merge = self.new_label("set.remove.end");
                self.terminate(format!("br i1 {found}, label %{remove}, label %{absent}"));
                self.start_block(&remove);
                let active_ptr =
                    self.emit_map_array_ptr(set_ty, &pointer, 2, capacity, Ty::Bool, &entry);
                self.instruction(format!("store i1 false, ptr {active_ptr}, align 1"));
                let bucket_ptr =
                    self.emit_map_array_ptr(set_ty, &pointer, 4, capacity, Ty::Long, &bucket);
                self.instruction(format!("store i64 -1, ptr {bucket_ptr}, align 1"));
                let count_ptr = self.emit_map_meta_ptr(set_ty, &pointer, 0);
                let count = self.temp();
                self.instruction(format!("{count} = load i64, ptr {count_ptr}, align 1"));
                let next = self.temp();
                self.instruction(format!("{next} = sub i64 {count}, 1"));
                self.instruction(format!("store i64 {next}, ptr {count_ptr}, align 1"));
                let removed_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&absent);
                let absent_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&merge);
                let result = self.temp();
                self.instruction(format!(
                    "{result} = phi i1 [ true, %{removed_pred} ], [ false, %{absent_pred} ]"
                ));
                result
            }
            SetOp::Add => {
                let found = self.temp();
                self.instruction(format!("{found} = icmp sge i64 {entry}, 0"));
                let present = self.new_label("set.add.present");
                let new = self.new_label("set.add.new");
                let merge = self.new_label("set.add.end");
                self.terminate(format!("br i1 {found}, label %{present}, label %{new}"));
                self.start_block(&present);
                let ok_present =
                    self.emit_construct_values(expr.ty, 0, vec![(Ty::Unit, String::new())]);
                let present_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&new);
                let insert = self.new_label("set.add.insert");
                let full = self.new_label("set.add.full");
                if proven_success {
                    self.terminate(format!("br label %{insert}"));
                } else {
                    let count = self.emit_collection_count(set_ty, &pointer);
                    let is_full = self.temp();
                    self.instruction(format!("{is_full} = icmp uge i64 {count}, {capacity}"));
                    self.terminate(format!("br i1 {is_full}, label %{full}, label %{insert}"));
                }
                self.start_block(&full);
                let error_ty = self.program.types[expr.ty.0].cases()[1].payload[0];
                let full_value = self.emit_construct_values(error_ty, 0, Vec::new());
                let failed = self.emit_construct_values(expr.ty, 1, vec![(error_ty, full_value)]);
                let full_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&insert);
                if capacity > 0 {
                    self.emit_map_insert_entry(
                        set_ty, &pointer, key_ty, &key, &hash, &bucket, None, None, None, capacity,
                    );
                }
                let inserted =
                    self.emit_construct_values(expr.ty, 0, vec![(Ty::Unit, String::new())]);
                let insert_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&merge);
                let result = self.temp();
                self.instruction(format!("{result} = phi {} [ {ok_present}, %{present_pred} ], [ {failed}, %{full_pred} ], [ {inserted}, %{insert_pred} ]", self.lltype(expr.ty)));
                result
            }
            SetOp::Count => unreachable!(),
        }
    }

    fn emit_pool_init(&mut self, pool_ty: Ty) -> String {
        match self.program.types[pool_ty.0].kind {
            TTypeKind::Pool { .. } => {}
            _ => unreachable!("pool literal has a pool type"),
        }
        "zeroinitializer".to_owned()
    }

    fn emit_pool_op(
        &mut self,
        expr: &TExpr,
        op: PoolOp,
        receiver: &TExpr,
        args: &[TExpr],
        capacity: usize,
        proven_success: bool,
        result_destination: Option<&str>,
    ) -> String {
        let pool_ty = receiver.ty;
        let element = match self.program.types[pool_ty.0].kind {
            TTypeKind::Pool { element, .. } => element,
            _ => unreachable!("typed pool operation"),
        };
        let pointer = if Self::expr_place(receiver).is_some() {
            self.emit_place_pointer_expr(receiver)
        } else {
            self.emit_expr_storage(receiver)
        };
        if self.terminated {
            return String::new();
        }
        if op == PoolOp::Count {
            return self.emit_collection_count(pool_ty, &pointer);
        }
        let mut values = Vec::with_capacity(args.len());
        let mut value_storages = Vec::with_capacity(args.len());
        for arg in args {
            if is_large_type(arg.ty, &self.program.types) {
                let storage = self.emit_expr_storage(arg);
                values.push(String::new());
                value_storages.push(Some(storage));
            } else {
                values.push(self.emit_expr(arg));
                value_storages.push(None);
            }
            if self.terminated {
                return String::new();
            }
        }
        if op == PoolOp::Add {
            let free_count_ptr = self.emit_pool_meta_ptr(pool_ty, &pointer, 1);
            let free_count = self.temp();
            self.instruction(format!(
                "{free_count} = load i64, ptr {free_count_ptr}, align 1"
            ));
            let has_reusable = self.temp();
            self.instruction(format!("{has_reusable} = icmp ugt i64 {free_count}, 0"));
            let reuse_label = self.new_label("pool.add.reuse");
            let virgin_check = self.new_label("pool.add.virgin.check");
            let virgin_label = self.new_label("pool.add.virgin");
            let fail_label = self.new_label("pool.add.full");
            let merge = self.new_label("pool.add.end");
            self.terminate(format!(
                "br i1 {has_reusable}, label %{reuse_label}, label %{virgin_check}"
            ));
            let result_ty = expr.ty;
            let error_ty = self.program.types[result_ty.0].cases()[1].payload[0];
            let id_ty = self.program.types[result_ty.0].cases()[0].payload[0];

            self.start_block(&reuse_label);
            let free_index = self.temp();
            self.instruction(format!("{free_index} = sub i64 {free_count}, 1"));
            let free_ptr = self.emit_pool_slot_ptr(pool_ty, &pointer, 4, &free_index);
            let reusable_slot32 = self.temp();
            self.instruction(format!(
                "{reusable_slot32} = load i32, ptr {free_ptr}, align 1"
            ));
            let reusable_slot = self.temp();
            self.instruction(format!(
                "{reusable_slot} = zext i32 {reusable_slot32} to i64"
            ));
            self.emit_pool_add_store(
                pool_ty,
                &pointer,
                element,
                &values[0],
                value_storages[0].as_deref(),
                &free_count_ptr,
                &free_count,
                &reusable_slot,
                false,
            );
            let reusable_generation_ptr =
                self.emit_pool_slot_ptr(pool_ty, &pointer, 3, &reusable_slot);
            let reusable_generation = self.temp();
            self.instruction(format!(
                "{reusable_generation} = load i32, ptr {reusable_generation_ptr}, align 1"
            ));
            let reusable_id = self.emit_make_id(&reusable_slot32, &reusable_generation);
            let reusable_success =
                self.emit_construct_values(result_ty, 0, vec![(id_ty, reusable_id)]);
            let reusable_pred = self.current_label.clone();
            self.terminate(format!("br label %{merge}"));

            self.start_block(&virgin_check);
            let high_water_ptr = self.emit_pool_meta_ptr(pool_ty, &pointer, 5);
            let high_water = self.temp();
            self.instruction(format!(
                "{high_water} = load i64, ptr {high_water_ptr}, align 1"
            ));
            if !proven_success {
                let room = self.temp();
                self.instruction(format!("{room} = icmp ult i64 {high_water}, {capacity}"));
                self.terminate(format!(
                    "br i1 {room}, label %{virgin_label}, label %{fail_label}"
                ));
            } else {
                self.terminate(format!("br label %{virgin_label}"));
            }

            self.start_block(&virgin_label);
            let virgin_slot32 = self.temp();
            self.instruction(format!("{virgin_slot32} = trunc i64 {high_water} to i32"));
            self.emit_pool_add_store(
                pool_ty,
                &pointer,
                element,
                &values[0],
                value_storages[0].as_deref(),
                &free_count_ptr,
                &free_count,
                &high_water,
                true,
            );
            let virgin_id = self.emit_make_id(&virgin_slot32, "1");
            let virgin_success = self.emit_construct_values(result_ty, 0, vec![(id_ty, virgin_id)]);
            let virgin_pred = self.current_label.clone();
            self.terminate(format!("br label %{merge}"));

            let mut incoming = vec![
                (reusable_success, reusable_pred),
                (virgin_success, virgin_pred),
            ];
            if !proven_success {
                self.start_block(&fail_label);
                let error = self.emit_construct_values(error_ty, 0, Vec::new());
                let failed = self.emit_construct_values(result_ty, 1, vec![(error_ty, error)]);
                let fail_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                incoming.push((failed, fail_pred));
            }
            self.start_block(&merge);
            let result = self.temp();
            let values = incoming
                .iter()
                .map(|(value, pred)| format!("[ {value}, %{pred} ]"))
                .collect::<Vec<_>>()
                .join(", ");
            self.instruction(format!(
                "{result} = phi {} {values}",
                self.lltype(result_ty)
            ));
            return result;
        }

        let id = values[0].clone();
        let slot = self.temp();
        self.instruction(format!("{slot} = and i64 {id}, 4294967295"));
        let generation64 = self.temp();
        self.instruction(format!("{generation64} = lshr i64 {id}, 32"));
        let generation = self.temp();
        self.instruction(format!("{generation} = trunc i64 {generation64} to i32"));
        let high_water_ptr = self.emit_pool_meta_ptr(pool_ty, &pointer, 5);
        let high_water = self.temp();
        self.instruction(format!(
            "{high_water} = load i64, ptr {high_water_ptr}, align 1"
        ));
        let in_capacity = self.temp();
        self.instruction(format!("{in_capacity} = icmp ult i64 {slot}, {capacity}"));
        let below_high_water = self.temp();
        self.instruction(format!(
            "{below_high_water} = icmp ult i64 {slot}, {high_water}"
        ));
        let in_range = self.temp();
        self.instruction(format!(
            "{in_range} = and i1 {in_capacity}, {below_high_water}"
        ));
        let inspect = self.new_label("pool.id.inspect");
        let invalid = self.new_label("pool.id.invalid");
        let valid = self.new_label("pool.id.valid");
        let merge = self.new_label("pool.id.end");
        self.terminate(format!(
            "br i1 {in_range}, label %{inspect}, label %{invalid}"
        ));
        self.start_block(&inspect);
        let occupied_ptr = self.emit_pool_slot_ptr(pool_ty, &pointer, 2, &slot);
        let occupied = self.temp();
        self.instruction(format!("{occupied} = load i1, ptr {occupied_ptr}, align 1"));
        let actual_generation_ptr = self.emit_pool_slot_ptr(pool_ty, &pointer, 3, &slot);
        let actual_generation = self.temp();
        self.instruction(format!(
            "{actual_generation} = load i32, ptr {actual_generation_ptr}, align 1"
        ));
        let same_generation = self.temp();
        self.instruction(format!(
            "{same_generation} = icmp eq i32 {actual_generation}, {generation}"
        ));
        let matches = self.temp();
        self.instruction(format!("{matches} = and i1 {occupied}, {same_generation}"));
        self.terminate(format!("br i1 {matches}, label %{valid}, label %{invalid}"));
        self.start_block(&invalid);
        if let Some(destination) = result_destination {
            self.emit_sum_empty_case_to(expr.ty, destination, 1);
            let invalid_pred = self.current_label.clone();
            self.terminate(format!("br label %{merge}"));
            self.start_block(&valid);
            let payload = self.emit_sum_payload_pointer(expr.ty, destination, 0, 0);
            self.emit_collection_element_storage(pool_ty, &pointer, &slot, &payload);
            if op == PoolOp::Remove {
                self.emit_clear_collection_element(pool_ty, &pointer, &slot);
                self.instruction(format!("store i1 false, ptr {occupied_ptr}, align 1"));
                let active_ptr = self.emit_pool_meta_ptr(pool_ty, &pointer, 0);
                let active = self.temp();
                self.instruction(format!("{active} = load i64, ptr {active_ptr}, align 1"));
                let active_next = self.temp();
                self.instruction(format!("{active_next} = sub i64 {active}, 1"));
                self.instruction(format!(
                    "store i64 {active_next}, ptr {active_ptr}, align 1"
                ));
                let max_minus_one = self.temp();
                self.instruction(format!(
                    "{max_minus_one} = icmp uge i32 {actual_generation}, -2"
                ));
                let retire = self.new_label("pool.remove.retire");
                let reuse = self.new_label("pool.remove.reuse");
                let remove_done = self.new_label("pool.remove.done");
                self.terminate(format!(
                    "br i1 {max_minus_one}, label %{retire}, label %{reuse}"
                ));
                self.start_block(&retire);
                self.instruction(format!(
                    "store i32 -1, ptr {actual_generation_ptr}, align 1"
                ));
                self.terminate(format!("br label %{remove_done}"));
                self.start_block(&reuse);
                let next_generation = self.temp();
                self.instruction(format!(
                    "{next_generation} = add i32 {actual_generation}, 1"
                ));
                self.instruction(format!(
                    "store i32 {next_generation}, ptr {actual_generation_ptr}, align 1"
                ));
                let free_count_ptr = self.emit_pool_meta_ptr(pool_ty, &pointer, 1);
                let free_count = self.temp();
                self.instruction(format!(
                    "{free_count} = load i64, ptr {free_count_ptr}, align 1"
                ));
                let free_ptr = self.emit_pool_slot_ptr(pool_ty, &pointer, 4, &free_count);
                let slot32 = self.temp();
                self.instruction(format!("{slot32} = trunc i64 {slot} to i32"));
                self.instruction(format!("store i32 {slot32}, ptr {free_ptr}, align 1"));
                let free_next = self.temp();
                self.instruction(format!("{free_next} = add i64 {free_count}, 1"));
                self.instruction(format!(
                    "store i64 {free_next}, ptr {free_count_ptr}, align 1"
                ));
                self.terminate(format!("br label %{remove_done}"));
                self.start_block(&remove_done);
            }
            self.emit_sum_tag_to(expr.ty, destination, 0);
            let valid_pred = self.current_label.clone();
            self.terminate(format!("br label %{merge}"));
            self.start_block(&merge);
            let _ = (invalid_pred, valid_pred);
            return String::new();
        }
        let invalid_value = match op {
            PoolOp::Contains => "false".to_owned(),
            PoolOp::Get | PoolOp::Remove => self.emit_construct_values(expr.ty, 1, Vec::new()),
            _ => unreachable!(),
        };
        let invalid_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&valid);
        let valid_value = match op {
            PoolOp::Contains => "true".to_owned(),
            PoolOp::Get => {
                let value = self.emit_collection_element(pool_ty, &pointer, &slot);
                self.emit_construct_values(expr.ty, 0, vec![(element, value)])
            }
            PoolOp::Remove => {
                let value = self.emit_collection_element(pool_ty, &pointer, &slot);
                self.emit_clear_collection_element(pool_ty, &pointer, &slot);
                self.instruction(format!("store i1 false, ptr {occupied_ptr}, align 1"));
                let active_ptr = self.emit_pool_meta_ptr(pool_ty, &pointer, 0);
                let active = self.temp();
                self.instruction(format!("{active} = load i64, ptr {active_ptr}, align 1"));
                let active_next = self.temp();
                self.instruction(format!("{active_next} = sub i64 {active}, 1"));
                self.instruction(format!(
                    "store i64 {active_next}, ptr {active_ptr}, align 1"
                ));
                let max_minus_one = self.temp();
                self.instruction(format!(
                    "{max_minus_one} = icmp uge i32 {actual_generation}, -2"
                ));
                let retire = self.new_label("pool.remove.retire");
                let reuse = self.new_label("pool.remove.reuse");
                let remove_done = self.new_label("pool.remove.done");
                self.terminate(format!(
                    "br i1 {max_minus_one}, label %{retire}, label %{reuse}"
                ));
                self.start_block(&retire);
                self.instruction(format!(
                    "store i32 -1, ptr {actual_generation_ptr}, align 1"
                ));
                self.terminate(format!("br label %{remove_done}"));
                self.start_block(&reuse);
                let next_generation = self.temp();
                self.instruction(format!(
                    "{next_generation} = add i32 {actual_generation}, 1"
                ));
                self.instruction(format!(
                    "store i32 {next_generation}, ptr {actual_generation_ptr}, align 1"
                ));
                let free_count_ptr = self.emit_pool_meta_ptr(pool_ty, &pointer, 1);
                let free_count = self.temp();
                self.instruction(format!(
                    "{free_count} = load i64, ptr {free_count_ptr}, align 1"
                ));
                let free_ptr = self.emit_pool_slot_ptr(pool_ty, &pointer, 4, &free_count);
                let slot32 = self.temp();
                self.instruction(format!("{slot32} = trunc i64 {slot} to i32"));
                self.instruction(format!("store i32 {slot32}, ptr {free_ptr}, align 1"));
                let free_next = self.temp();
                self.instruction(format!("{free_next} = add i64 {free_count}, 1"));
                self.instruction(format!(
                    "store i64 {free_next}, ptr {free_count_ptr}, align 1"
                ));
                self.terminate(format!("br label %{remove_done}"));
                self.start_block(&remove_done);
                self.emit_construct_values(expr.ty, 0, vec![(element, value)])
            }
            _ => unreachable!(),
        };
        let valid_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi {} [ {invalid_value}, %{invalid_pred} ], [ {valid_value}, %{valid_pred} ]",
            self.lltype(expr.ty)
        ));
        result
    }

    fn emit_pool_add_store(
        &mut self,
        pool_ty: Ty,
        pointer: &str,
        element: Ty,
        value: &str,
        value_storage: Option<&str>,
        free_count_ptr: &str,
        free_count: &str,
        slot_index: &str,
        virgin: bool,
    ) {
        if virgin {
            self.emit_init_var_collection_element(pool_ty, pointer, slot_index);
        }
        if let Some(source) = value_storage {
            self.emit_scatter_collection_element(pool_ty, pointer, slot_index, source);
        } else {
            self.emit_store_collection_element(pool_ty, pointer, slot_index, value);
        }
        if virgin {
            let generation = self.emit_pool_slot_ptr(pool_ty, pointer, 3, slot_index);
            self.instruction(format!("store i32 1, ptr {generation}, align 1"));
        }
        let occupied = self.emit_pool_slot_ptr(pool_ty, pointer, 2, slot_index);
        self.instruction(format!("store i1 true, ptr {occupied}, align 1"));
        if !virgin {
            let free_next = self.temp();
            self.instruction(format!("{free_next} = sub i64 {free_count}, 1"));
            self.instruction(format!(
                "store i64 {free_next}, ptr {free_count_ptr}, align 1"
            ));
        }
        let active_ptr = self.emit_pool_meta_ptr(pool_ty, pointer, 0);
        let active = self.temp();
        self.instruction(format!("{active} = load i64, ptr {active_ptr}, align 1"));
        let active_next = self.temp();
        self.instruction(format!("{active_next} = add i64 {active}, 1"));
        self.instruction(format!(
            "store i64 {active_next}, ptr {active_ptr}, align 1"
        ));
        if virgin {
            let high_water_ptr = self.emit_pool_meta_ptr(pool_ty, pointer, 5);
            let next = self.temp();
            self.instruction(format!("{next} = add i64 {slot_index}, 1"));
            self.instruction(format!("store i64 {next}, ptr {high_water_ptr}, align 1"));
        }
        let _ = element;
    }

    fn emit_make_id(&mut self, slot32: &str, generation32: &str) -> String {
        let slot64 = self.temp();
        self.instruction(format!("{slot64} = zext i32 {slot32} to i64"));
        let generation64 = self.temp();
        self.instruction(format!("{generation64} = zext i32 {generation32} to i64"));
        let shifted = self.temp();
        self.instruction(format!("{shifted} = shl i64 {generation64}, 32"));
        let result = self.temp();
        self.instruction(format!("{result} = or i64 {shifted}, {slot64}"));
        result
    }

    fn emit_byte_string_to(&mut self, destination: &str, ty: Ty, bytes: &[u8]) {
        let TTypeKind::List { capacity, .. } = self.program.types[ty.0].kind else {
            unreachable!("byte strings are lowered to byte lists")
        };
        let count = self.temp();
        self.instruction(format!(
            "{count} = getelementptr {}, ptr {destination}, i32 0, i32 0",
            self.lltype(ty)
        ));
        self.instruction(format!("store i64 0, ptr {count}, align 1"));
        for (index, byte) in bytes.iter().enumerate() {
            debug_assert!(index < capacity);
            let slot = self.temp();
            self.instruction(format!(
                "{slot} = getelementptr {}, ptr {destination}, i32 0, i32 1, i64 {index}",
                self.lltype(ty)
            ));
            self.instruction(format!("store i32 {byte}, ptr {slot}, align 1"));
        }
        self.instruction(format!("store i64 {}, ptr {count}, align 1", bytes.len()));
    }

    fn emit_fill(&mut self, collection_ty: Ty, value: &TExpr, capacity: usize) -> String {
        debug_assert!(matches!(
            self.program.types[collection_ty.0].kind,
            TTypeKind::Array { .. } | TTypeKind::Grid { .. }
        ));
        let value = self.emit_expr(value);
        if self.terminated {
            return String::new();
        }
        let place = self.entry_alloca(collection_ty);
        self.instruction(format!(
            "store {} zeroinitializer, ptr {place}, align 1",
            self.lltype(collection_ty)
        ));
        if capacity != 0 {
            let counter_ty = Ty::Long;
            let counter = self.entry_alloca(counter_ty);
            self.instruction(format!("store i64 0, ptr {counter}, align 1"));
            let cond = self.new_label("fill.cond");
            let body = self.new_label("fill.body");
            let done = self.new_label("fill.done");
            self.terminate(format!("br label %{cond}"));
            self.start_block(&cond);
            let index = self.temp();
            self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
            let more = self.temp();
            self.instruction(format!("{more} = icmp ult i64 {index}, {capacity}"));
            self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
            self.start_block(&body);
            self.emit_store_collection_element(collection_ty, &place, &index, &value);
            let next = self.temp();
            self.instruction(format!("{next} = add i64 {index}, 1"));
            self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
            self.terminate(format!("br label %{cond}"));
            self.start_block(&done);
        }
        let result = self.temp();
        self.instruction(format!(
            "{result} = load {}, ptr {place}, align 1",
            self.lltype(collection_ty)
        ));
        result
    }

    fn emit_collection_op(
        &mut self,
        expr: &TExpr,
        op: CollectionOp,
        receiver: &TExpr,
        args: &[TExpr],
        capacity: usize,
        proven_success: bool,
        result_destination: Option<&str>,
    ) -> String {
        let collection_ty = receiver.ty;
        let element = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { element, .. }
            | TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. }
            | TTypeKind::Grid { element, .. } => element,
            _ => unreachable!("typed collection operation"),
        };
        if matches!(op, CollectionOp::Width | CollectionOp::Height) {
            let _ = self.emit_expr_storage(receiver);
            if self.terminated {
                return String::new();
            }
            return capacity.to_string();
        }
        if op == CollectionOp::Len {
            let _ = self.emit_expr_storage(receiver);
            if self.terminated {
                return String::new();
            }
            return capacity.to_string();
        }
        if op == CollectionOp::Count {
            let pointer = self.emit_expr_storage(receiver);
            return self.emit_collection_count(collection_ty, &pointer);
        }
        let pointer = if Self::expr_place(receiver).is_some() {
            self.emit_place_pointer_expr(receiver)
        } else {
            self.emit_expr_storage(receiver)
        };
        if op == CollectionOp::Clear {
            let count = self.emit_collection_count(collection_ty, &pointer);
            let cursor = self.entry_alloca(Ty::Long);
            self.instruction(format!("store i64 0, ptr {cursor}, align 1"));
            let condition = self.new_label("collection.clear.cond");
            let body = self.new_label("collection.clear.body");
            let done = self.new_label("collection.clear.done");
            self.terminate(format!("br label %{condition}"));
            self.start_block(&condition);
            let index = self.temp();
            self.instruction(format!("{index} = load i64, ptr {cursor}, align 1"));
            let more = self.temp();
            self.instruction(format!("{more} = icmp ult i64 {index}, {count}"));
            self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
            self.start_block(&body);
            let physical = if matches!(
                self.program.types[collection_ty.0].kind,
                TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
            ) {
                self.emit_queue_ring_physical_index(collection_ty, &pointer, &index)
            } else {
                index.clone()
            };
            self.emit_clear_collection_element(collection_ty, &pointer, &physical);
            let next = self.temp();
            self.instruction(format!("{next} = add i64 {index}, 1"));
            self.instruction(format!("store i64 {next}, ptr {cursor}, align 1"));
            self.terminate(format!("br label %{condition}"));
            self.start_block(&done);
            let count_ptr = self.temp();
            self.instruction(format!(
                "{count_ptr} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 0",
                self.lltype(collection_ty)
            ));
            self.instruction(format!("store i64 0, ptr {count_ptr}, align 1"));
            return String::new();
        }
        let mut values = Vec::with_capacity(args.len());
        let mut value_storages = Vec::with_capacity(args.len());
        for arg in args {
            if is_large_type(arg.ty, &self.program.types) {
                let storage = self.emit_expr_storage(arg);
                values.push("zeroinitializer".to_owned());
                value_storages.push(Some(storage));
            } else {
                values.push(self.emit_expr(arg));
                value_storages.push(None);
            }
            if self.terminated {
                return String::new();
            }
        }
        if matches!(
            self.program.types[collection_ty.0].kind,
            TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
        ) {
            let is_ring = matches!(
                self.program.types[collection_ty.0].kind,
                TTypeKind::Ring { .. }
            );
            match op {
                CollectionOp::Push | CollectionOp::RingPush => {
                    if is_ring && capacity == 0 {
                        return String::new();
                    }
                    let count = self.emit_collection_count(collection_ty, &pointer);
                    if op == CollectionOp::Push && proven_success {
                        let physical =
                            self.emit_queue_ring_physical_index(collection_ty, &pointer, &count);
                        self.emit_init_var_collection_element(collection_ty, &pointer, &physical);
                        self.emit_store_collection_element_value(
                            collection_ty,
                            &pointer,
                            &physical,
                            &values[0],
                            value_storages[0].as_deref(),
                        );
                        let next = self.temp();
                        self.instruction(format!("{next} = add i64 {count}, 1"));
                        let count_ptr = self.emit_queue_ring_meta_ptr(collection_ty, &pointer, 1);
                        self.instruction(format!("store i64 {next}, ptr {count_ptr}, align 1"));
                        return self.emit_construct_values(
                            expr.ty,
                            0,
                            vec![(Ty::Unit, String::new())],
                        );
                    }
                    let full = self.temp();
                    self.instruction(format!("{full} = icmp uge i64 {count}, {capacity}"));
                    let full_label = self.new_label("queue.full");
                    let room_label = self.new_label("queue.room");
                    let merge = self.new_label("queue.push.end");
                    self.terminate(format!(
                        "br i1 {full}, label %{full_label}, label %{room_label}"
                    ));
                    self.start_block(&full_label);
                    if op == CollectionOp::RingPush {
                        let head_ptr = self.emit_queue_ring_meta_ptr(collection_ty, &pointer, 0);
                        let head = self.temp();
                        self.instruction(format!("{head} = load i64, ptr {head_ptr}, align 1"));
                        self.emit_store_collection_element_value(
                            collection_ty,
                            &pointer,
                            &head,
                            &values[0],
                            value_storages[0].as_deref(),
                        );
                        let incremented = self.temp();
                        self.instruction(format!("{incremented} = add i64 {head}, 1"));
                        let next_head = self.temp();
                        self.instruction(format!(
                            "{next_head} = urem i64 {incremented}, {capacity}"
                        ));
                        self.instruction(format!("store i64 {next_head}, ptr {head_ptr}, align 1"));
                    }
                    let full_result = if op == CollectionOp::RingPush {
                        "".to_owned()
                    } else {
                        let full_ty = self.program.types[expr.ty.0].cases()[1].payload[0];
                        let full_value = self.emit_construct_values(full_ty, 0, Vec::new());
                        self.emit_construct_values(expr.ty, 1, vec![(full_ty, full_value)])
                    };
                    let full_pred = self.current_label.clone();
                    self.terminate(format!("br label %{merge}"));
                    self.start_block(&room_label);
                    let physical =
                        self.emit_queue_ring_physical_index(collection_ty, &pointer, &count);
                    self.emit_init_var_collection_element(collection_ty, &pointer, &physical);
                    self.emit_store_collection_element_value(
                        collection_ty,
                        &pointer,
                        &physical,
                        &values[0],
                        value_storages[0].as_deref(),
                    );
                    let next = self.temp();
                    self.instruction(format!("{next} = add i64 {count}, 1"));
                    let count_ptr = self.emit_queue_ring_meta_ptr(collection_ty, &pointer, 1);
                    self.instruction(format!("store i64 {next}, ptr {count_ptr}, align 1"));
                    let room_result = if op == CollectionOp::RingPush {
                        String::new()
                    } else {
                        self.emit_construct_values(expr.ty, 0, vec![(Ty::Unit, String::new())])
                    };
                    let room_pred = self.current_label.clone();
                    self.terminate(format!("br label %{merge}"));
                    self.start_block(&merge);
                    if op == CollectionOp::RingPush {
                        return String::new();
                    }
                    let result = self.temp();
                    self.instruction(format!(
                        "{result} = phi {} [ {full_result}, %{full_pred} ], [ {room_result}, %{room_pred} ]",
                        self.lltype(expr.ty)
                    ));
                    return result;
                }
                CollectionOp::Pop => {
                    let count = self.emit_collection_count(collection_ty, &pointer);
                    let empty = self.temp();
                    self.instruction(format!("{empty} = icmp eq i64 {count}, 0"));
                    let none_label = self.new_label("fifo.pop.none");
                    let some_label = self.new_label("fifo.pop.some");
                    let merge = self.new_label("fifo.pop.end");
                    self.terminate(format!(
                        "br i1 {empty}, label %{none_label}, label %{some_label}"
                    ));
                    self.start_block(&none_label);
                    if let Some(destination) = result_destination {
                        self.emit_sum_empty_case_to(expr.ty, destination, 1);
                        let none_pred = self.current_label.clone();
                        self.terminate(format!("br label %{merge}"));
                        self.start_block(&some_label);
                        self.emit_sum_collection_case_to(
                            expr.ty,
                            destination,
                            0,
                            collection_ty,
                            &pointer,
                            "0",
                        );
                        let head_ptr = self.emit_queue_ring_meta_ptr(collection_ty, &pointer, 0);
                        let head = self.temp();
                        self.instruction(format!("{head} = load i64, ptr {head_ptr}, align 1"));
                        self.emit_clear_collection_element(collection_ty, &pointer, &head);
                        let next_count = self.temp();
                        self.instruction(format!("{next_count} = sub i64 {count}, 1"));
                        let count_ptr = self.emit_queue_ring_meta_ptr(collection_ty, &pointer, 1);
                        self.instruction(format!(
                            "store i64 {next_count}, ptr {count_ptr}, align 1"
                        ));
                        if capacity > 0 {
                            let head_ptr =
                                self.emit_queue_ring_meta_ptr(collection_ty, &pointer, 0);
                            let head = self.temp();
                            self.instruction(format!("{head} = load i64, ptr {head_ptr}, align 1"));
                            let incremented = self.temp();
                            self.instruction(format!("{incremented} = add i64 {head}, 1"));
                            let next_head = self.temp();
                            self.instruction(format!(
                                "{next_head} = urem i64 {incremented}, {capacity}"
                            ));
                            self.instruction(format!(
                                "store i64 {next_head}, ptr {head_ptr}, align 1"
                            ));
                        }
                        self.emit_sum_tag_to(expr.ty, destination, 0);
                        let some_pred = self.current_label.clone();
                        self.terminate(format!("br label %{merge}"));
                        self.start_block(&merge);
                        let _ = (none_pred, some_pred);
                        return String::new();
                    }
                    let none = self.emit_construct_values(expr.ty, 1, Vec::new());
                    let none_pred = self.current_label.clone();
                    self.terminate(format!("br label %{merge}"));
                    self.start_block(&some_label);
                    let value = self.emit_collection_element(collection_ty, &pointer, "0");
                    let head_ptr = self.emit_queue_ring_meta_ptr(collection_ty, &pointer, 0);
                    let head = self.temp();
                    self.instruction(format!("{head} = load i64, ptr {head_ptr}, align 1"));
                    self.emit_clear_collection_element(collection_ty, &pointer, &head);
                    let next_count = self.temp();
                    self.instruction(format!("{next_count} = sub i64 {count}, 1"));
                    let count_ptr = self.emit_queue_ring_meta_ptr(collection_ty, &pointer, 1);
                    self.instruction(format!("store i64 {next_count}, ptr {count_ptr}, align 1"));
                    if capacity > 0 {
                        let head_ptr = self.emit_queue_ring_meta_ptr(collection_ty, &pointer, 0);
                        let head = self.temp();
                        self.instruction(format!("{head} = load i64, ptr {head_ptr}, align 1"));
                        let incremented = self.temp();
                        self.instruction(format!("{incremented} = add i64 {head}, 1"));
                        let next_head = self.temp();
                        self.instruction(format!(
                            "{next_head} = urem i64 {incremented}, {capacity}"
                        ));
                        self.instruction(format!("store i64 {next_head}, ptr {head_ptr}, align 1"));
                    }
                    let some = self.emit_construct_values(expr.ty, 0, vec![(element, value)]);
                    let some_pred = self.current_label.clone();
                    self.terminate(format!("br label %{merge}"));
                    self.start_block(&merge);
                    let result = self.temp();
                    self.instruction(format!(
                        "{result} = phi {} [ {none}, %{none_pred} ], [ {some}, %{some_pred} ]",
                        self.lltype(expr.ty)
                    ));
                    return result;
                }
                CollectionOp::Peek => {
                    let count = self.emit_collection_count(collection_ty, &pointer);
                    let empty = self.temp();
                    self.instruction(format!("{empty} = icmp eq i64 {count}, 0"));
                    let none_label = self.new_label("fifo.peek.none");
                    let some_label = self.new_label("fifo.peek.some");
                    let merge = self.new_label("fifo.peek.end");
                    self.terminate(format!(
                        "br i1 {empty}, label %{none_label}, label %{some_label}"
                    ));
                    self.start_block(&none_label);
                    if let Some(destination) = result_destination {
                        self.emit_sum_empty_case_to(expr.ty, destination, 1);
                        self.terminate(format!("br label %{merge}"));
                        self.start_block(&some_label);
                        self.emit_sum_collection_case_to(
                            expr.ty,
                            destination,
                            0,
                            collection_ty,
                            &pointer,
                            "0",
                        );
                        self.terminate(format!("br label %{merge}"));
                        self.start_block(&merge);
                        return String::new();
                    }
                    let none = self.emit_construct_values(expr.ty, 1, Vec::new());
                    let none_pred = self.current_label.clone();
                    self.terminate(format!("br label %{merge}"));
                    self.start_block(&some_label);
                    let value = self.emit_collection_element(collection_ty, &pointer, "0");
                    let some = self.emit_construct_values(expr.ty, 0, vec![(element, value)]);
                    let some_pred = self.current_label.clone();
                    self.terminate(format!("br label %{merge}"));
                    self.start_block(&merge);
                    let result = self.temp();
                    self.instruction(format!(
                        "{result} = phi {} [ {none}, %{none_pred} ], [ {some}, %{some_pred} ]",
                        self.lltype(expr.ty)
                    ));
                    return result;
                }
                _ => unreachable!("type checker restricts queue/ring operations"),
            }
        }
        match op {
            CollectionOp::Push => {
                let count = self.emit_collection_count(collection_ty, &pointer);
                let result_ty = expr.ty;
                if proven_success {
                    self.emit_init_var_collection_element(collection_ty, &pointer, &count);
                    self.emit_store_collection_element_value(
                        collection_ty,
                        &pointer,
                        &count,
                        &values[0],
                        value_storages[0].as_deref(),
                    );
                    let next = self.temp();
                    self.instruction(format!("{next} = add i64 {count}, 1"));
                    let count_ptr = self.temp();
                    self.instruction(format!(
                        "{count_ptr} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 0",
                        self.lltype(collection_ty)
                    ));
                    self.instruction(format!("store i64 {next}, ptr {count_ptr}, align 1"));
                    return self.emit_construct_values(
                        result_ty,
                        0,
                        vec![(Ty::Unit, String::new())],
                    );
                }
                let full = self.temp();
                self.instruction(format!("{full} = icmp uge i64 {count}, {capacity}"));
                let fail_label = self.new_label("push.full");
                let success_label = self.new_label("push.ok");
                let merge = self.new_label("push.end");
                self.terminate(format!(
                    "br i1 {full}, label %{fail_label}, label %{success_label}"
                ));
                self.start_block(&fail_label);
                let full_ty = self.program.types[result_ty.0].cases()[1].payload[0];
                let full = self.emit_construct_values(full_ty, 0, Vec::new());
                let failure = self.emit_construct_values(result_ty, 1, vec![(full_ty, full)]);
                let fail_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&success_label);
                self.emit_init_var_collection_element(collection_ty, &pointer, &count);
                self.emit_store_collection_element_value(
                    collection_ty,
                    &pointer,
                    &count,
                    &values[0],
                    value_storages[0].as_deref(),
                );
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {count}, 1"));
                let count_ptr = self.temp();
                self.instruction(format!(
                    "{count_ptr} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 0",
                    self.lltype(collection_ty)
                ));
                self.instruction(format!("store i64 {next}, ptr {count_ptr}, align 1"));
                let success =
                    self.emit_construct_values(result_ty, 0, vec![(Ty::Unit, String::new())]);
                let success_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&merge);
                let result = self.temp();
                self.instruction(format!(
                    "{result} = phi {} [ {failure}, %{fail_pred} ], [ {success}, %{success_pred} ]",
                    self.lltype(result_ty)
                ));
                result
            }
            CollectionOp::Insert => {
                let index = values[0].clone();
                self.emit_index_guard(collection_ty, &pointer, &index, true, args[0].span);
                let count = self.emit_collection_count(collection_ty, &pointer);
                let full = self.temp();
                self.instruction(format!("{full} = icmp uge i64 {count}, {capacity}"));
                let fail_label = self.new_label("insert.full");
                let success_label = self.new_label("insert.ok");
                let merge = self.new_label("insert.end");
                self.terminate(format!(
                    "br i1 {full}, label %{fail_label}, label %{success_label}"
                ));
                self.start_block(&fail_label);
                let err_ty = self.program.types[expr.ty.0].cases()[1].payload[0];
                let full = self.emit_construct_values(err_ty, 0, Vec::new());
                let failure = self.emit_construct_values(expr.ty, 1, vec![(err_ty, full)]);
                let fail_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&success_label);
                self.emit_init_var_collection_element(collection_ty, &pointer, &count);
                let cursor = self.entry_alloca(Ty::Long);
                self.instruction(format!("store i64 {count}, ptr {cursor}, align 1"));
                let cond = self.new_label("insert.shift.cond");
                let body = self.new_label("insert.shift.body");
                let shifted = self.new_label("insert.shift.done");
                self.terminate(format!("br label %{cond}"));
                self.start_block(&cond);
                let current = self.temp();
                self.instruction(format!("{current} = load i64, ptr {cursor}, align 1"));
                let more = self.temp();
                self.instruction(format!("{more} = icmp ugt i64 {current}, {index}"));
                self.terminate(format!("br i1 {more}, label %{body}, label %{shifted}"));
                self.start_block(&body);
                let previous = self.temp();
                self.instruction(format!("{previous} = sub i64 {current}, 1"));
                self.emit_copy_collection_element(
                    &pointer,
                    &pointer,
                    collection_ty,
                    &current,
                    &previous,
                );
                self.instruction(format!("store i64 {previous}, ptr {cursor}, align 1"));
                self.terminate(format!("br label %{cond}"));
                self.start_block(&shifted);
                self.emit_store_collection_element_value(
                    collection_ty,
                    &pointer,
                    &index,
                    &values[1],
                    value_storages[1].as_deref(),
                );
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {count}, 1"));
                let count_ptr = self.temp();
                self.instruction(format!(
                    "{count_ptr} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 0",
                    self.lltype(collection_ty)
                ));
                self.instruction(format!("store i64 {next}, ptr {count_ptr}, align 1"));
                let success =
                    self.emit_construct_values(expr.ty, 0, vec![(Ty::Unit, String::new())]);
                let success_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&merge);
                let result = self.temp();
                self.instruction(format!(
                    "{result} = phi {} [ {failure}, %{fail_pred} ], [ {success}, %{success_pred} ]",
                    self.lltype(expr.ty)
                ));
                result
            }
            CollectionOp::Pop => {
                let count = self.emit_collection_count(collection_ty, &pointer);
                let empty = self.temp();
                self.instruction(format!("{empty} = icmp eq i64 {count}, 0"));
                let none_label = self.new_label("pop.none");
                let some_label = self.new_label("pop.some");
                let merge = self.new_label("pop.end");
                self.terminate(format!(
                    "br i1 {empty}, label %{none_label}, label %{some_label}"
                ));
                self.start_block(&none_label);
                if let Some(destination) = result_destination {
                    self.emit_sum_empty_case_to(expr.ty, destination, 1);
                    self.terminate(format!("br label %{merge}"));
                    self.start_block(&some_label);
                    let index = self.temp();
                    self.instruction(format!("{index} = sub i64 {count}, 1"));
                    self.emit_sum_collection_case_to(
                        expr.ty,
                        destination,
                        0,
                        collection_ty,
                        &pointer,
                        &index,
                    );
                    self.emit_clear_collection_element(collection_ty, &pointer, &index);
                    let count_ptr = self.emit_collection_count_ptr(collection_ty, &pointer);
                    self.instruction(format!("store i64 {index}, ptr {count_ptr}, align 1"));
                    self.terminate(format!("br label %{merge}"));
                    self.start_block(&merge);
                    return String::new();
                }
                let none = self.emit_construct_values(expr.ty, 1, Vec::new());
                let none_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&some_label);
                let index = self.temp();
                self.instruction(format!("{index} = sub i64 {count}, 1"));
                let value = self.emit_collection_element(collection_ty, &pointer, &index);
                self.emit_clear_collection_element(collection_ty, &pointer, &index);
                let count_ptr = self.temp();
                self.instruction(format!(
                    "{count_ptr} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 0",
                    self.lltype(collection_ty)
                ));
                self.instruction(format!("store i64 {index}, ptr {count_ptr}, align 1"));
                let some = self.emit_construct_values(expr.ty, 0, vec![(element, value)]);
                let some_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&merge);
                let result = self.temp();
                self.instruction(format!(
                    "{result} = phi {} [ {none}, %{none_pred} ], [ {some}, %{some_pred} ]",
                    self.lltype(expr.ty)
                ));
                result
            }
            CollectionOp::Remove => {
                let index = values[0].clone();
                self.emit_index_guard(collection_ty, &pointer, &index, false, args[0].span);
                let count = self.emit_collection_count(collection_ty, &pointer);
                let removed = if let Some(destination) = result_destination {
                    self.emit_collection_element_storage(
                        collection_ty,
                        &pointer,
                        &index,
                        destination,
                    );
                    String::new()
                } else {
                    self.emit_collection_element(collection_ty, &pointer, &index)
                };
                let cursor = self.entry_alloca(Ty::Long);
                self.instruction(format!("store i64 {index}, ptr {cursor}, align 1"));
                let cond = self.new_label("remove.shift.cond");
                let body = self.new_label("remove.shift.body");
                let done = self.new_label("remove.shift.done");
                self.terminate(format!("br label %{cond}"));
                self.start_block(&cond);
                let current = self.temp();
                self.instruction(format!("{current} = load i64, ptr {cursor}, align 1"));
                let last = self.temp();
                self.instruction(format!("{last} = sub i64 {count}, 1"));
                let more = self.temp();
                self.instruction(format!("{more} = icmp ult i64 {current}, {last}"));
                self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
                self.start_block(&body);
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {current}, 1"));
                self.emit_copy_collection_element(
                    &pointer,
                    &pointer,
                    collection_ty,
                    &current,
                    &next,
                );
                self.instruction(format!("store i64 {next}, ptr {cursor}, align 1"));
                self.terminate(format!("br label %{cond}"));
                self.start_block(&done);
                let new_count = self.temp();
                self.instruction(format!("{new_count} = sub i64 {count}, 1"));
                let last = new_count.clone();
                self.emit_clear_collection_element(collection_ty, &pointer, &last);
                let count_ptr = self.temp();
                self.instruction(format!(
                    "{count_ptr} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 0",
                    self.lltype(collection_ty)
                ));
                self.instruction(format!("store i64 {new_count}, ptr {count_ptr}, align 1"));
                if result_destination.is_some() {
                    String::new()
                } else {
                    removed
                }
            }
            CollectionOp::Count
            | CollectionOp::Len
            | CollectionOp::Width
            | CollectionOp::Height
            | CollectionOp::Peek
            | CollectionOp::RingPush
            | CollectionOp::Clear => unreachable!(),
        }
    }

    fn emit_index_guard(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        index: &str,
        allow_end: bool,
        span: Span,
    ) {
        let is_list = matches!(
            self.program.types[collection_ty.0].kind,
            TTypeKind::List { .. }
        );
        let capacity = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { capacity, .. } | TTypeKind::List { capacity, .. } => capacity,
            _ => unreachable!(),
        };
        let limit = if is_list {
            self.emit_collection_count(collection_ty, pointer)
        } else {
            capacity.to_string()
        };
        let negative = self.temp();
        self.instruction(format!("{negative} = icmp slt i64 {index}, 0"));
        let upper = self.temp();
        self.instruction(format!(
            "{upper} = icmp {} i64 {index}, {limit}",
            if allow_end { "sgt" } else { "sge" }
        ));
        let bad = self.temp();
        self.instruction(format!("{bad} = or i1 {negative}, {upper}"));
        self.guard(bad, Failure::IndexOutOfRange, span);
    }

    fn emit_place_pointer(&mut self, place: &TPlace) -> String {
        let mut pointer = if let Some(global) = global_from_root(place.root) {
            self.global_pointer(global)
        } else {
            self.local_pointer(place.root)
        };
        let mut current_ty = self.root_type(place.root);
        let mut soa: Option<(Ty, String, String)> = None;
        if let Some(view) = self.views.get(&place.root).cloned() {
            let idx = self.temp();
            self.instruction(format!(
                "{idx} = load i64, ptr %local.{}, align 1",
                view.counter_id
            ));
            let idx = if matches!(
                self.program.types[view.collection_ty.0].kind,
                TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
            ) {
                self.emit_queue_ring_physical_index(view.collection_ty, &view.collection_ptr, &idx)
            } else {
                idx
            };
            let element = match self.program.types[view.collection_ty.0].kind {
                TTypeKind::Array { element, .. }
                | TTypeKind::List { element, .. }
                | TTypeKind::Queue { element, .. }
                | TTypeKind::Ring { element, .. }
                | TTypeKind::Grid { element, .. }
                | TTypeKind::Pool { element, .. } => element,
                TTypeKind::Map { value, .. } => value,
                _ => unreachable!(),
            };
            current_ty = element;
            if matches!(self.program.types[element.0].kind, TTypeKind::Struct(_)) {
                soa = Some((view.collection_ty, view.collection_ptr, idx));
            } else {
                pointer = self.emit_collection_lane_pointer(
                    view.collection_ty,
                    &view.collection_ptr,
                    &idx,
                    0,
                );
            }
        }
        for projection in &place.path {
            match projection {
                TProjection::Field(index) => {
                    let field_ty = match &self.program.types[current_ty.0].kind {
                        TTypeKind::Struct(fields) => fields[*index].ty,
                        _ => unreachable!("typed place field crosses only struct storage"),
                    };
                    if let Some((collection_ty, base, idx)) = soa.take() {
                        pointer =
                            self.emit_collection_lane_pointer(collection_ty, &base, &idx, *index);
                    } else {
                        let next = self.temp();
                        self.instruction(format!(
                            "{next} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 {index}",
                            self.lltype(current_ty)
                        ));
                        pointer = next;
                    }
                    current_ty = field_ty;
                }
                TProjection::Index {
                    index,
                    is_map,
                    proven,
                    grid,
                    ..
                } => {
                    let index_value = self.emit_projection_index(
                        current_ty,
                        &pointer,
                        index,
                        grid.as_ref(),
                        *proven,
                        *is_map,
                    );
                    let element = match self.program.types[current_ty.0].kind {
                        TTypeKind::Array { element, .. }
                        | TTypeKind::List { element, .. }
                        | TTypeKind::Queue { element, .. }
                        | TTypeKind::Ring { element, .. }
                        | TTypeKind::Grid { element, .. }
                        | TTypeKind::Pool { element, .. } => element,
                        TTypeKind::Map { value, .. } if *is_map => value,
                        _ => unreachable!("typed place index crosses only collection storage"),
                    };
                    if *is_map && matches!(self.program.types[element.0].kind, TTypeKind::Struct(_))
                    {
                        soa = Some((current_ty, pointer.clone(), index_value));
                    } else if *is_map {
                        pointer = self.emit_map_entry_ptr(current_ty, &pointer, &index_value, true);
                    } else if matches!(self.program.types[element.0].kind, TTypeKind::Struct(_)) {
                        soa = Some((current_ty, pointer.clone(), index_value));
                    } else {
                        pointer = self.emit_collection_lane_pointer(
                            current_ty,
                            &pointer,
                            &index_value,
                            0,
                        );
                    }
                    current_ty = element;
                }
            }
        }
        if let Some((collection_ty, base, index)) = soa {
            let gathered = self.entry_alloca(current_ty);
            self.emit_gather_collection_element(collection_ty, &base, &index, &gathered);
            return gathered;
        }
        pointer
    }

    fn global_pointer(&mut self, id: usize) -> String {
        let offset = self.program.globals[id].offset;
        let pointer = self.temp();
        self.instruction(format!(
            "{pointer} = getelementptr inbounds i8, ptr @nl.globals, i64 {offset}"
        ));
        pointer
    }

    fn expr_place(expr: &TExpr) -> Option<TPlace> {
        match &expr.kind {
            TExprKind::Local(id) => Some(TPlace {
                root: *id,
                fields: Vec::new(),
                path: Vec::new(),
                ty: expr.ty,
            }),
            TExprKind::Global(id) => Some(TPlace {
                root: global_root(*id),
                fields: Vec::new(),
                path: Vec::new(),
                ty: expr.ty,
            }),
            TExprKind::Field {
                receiver,
                field_index,
            } => {
                let mut place = Self::expr_place(receiver)?;
                place.fields.push(*field_index);
                place.path.push(TProjection::Field(*field_index));
                place.ty = expr.ty;
                Some(place)
            }
            TExprKind::Index {
                receiver,
                index,
                capacity,
                is_list,
                proven,
                grid,
            } => {
                let mut place = Self::expr_place(receiver)?;
                let constant = if let TExprKind::Integer(value) = index.kind {
                    Some(value)
                } else {
                    None
                };
                place.path.push(TProjection::Index {
                    index: (**index).clone(),
                    constant,
                    capacity: *capacity,
                    is_list: *is_list,
                    is_pool: false,
                    is_map: false,
                    proven: *proven,
                    grid: grid.as_deref().cloned(),
                });
                place.ty = expr.ty;
                Some(place)
            }
            _ => None,
        }
    }

    fn emit_place_pointer_expr(&mut self, expr: &TExpr) -> String {
        let place = Self::expr_place(expr).expect("checker validated writable place");
        self.emit_place_pointer(&place)
    }

    fn emit_expr_storage(&mut self, expr: &TExpr) -> String {
        if let Some(place) = Self::expr_place(expr) {
            return self.emit_place_pointer(&place);
        }
        let pointer = self.entry_alloca(expr.ty);
        if is_large_type(expr.ty, &self.program.types) {
            self.emit_expr_to(&pointer, expr);
        } else {
            let value = self.emit_expr(expr);
            if !self.terminated && expr.ty != Ty::Unit {
                self.instruction(format!(
                    "store {} {value}, ptr {pointer}, align 1",
                    self.lltype(expr.ty)
                ));
            }
        }
        pointer
    }

    fn place_struct_element(&self, place: &TPlace) -> Option<(Ty, TProjection, String)> {
        if place
            .path
            .last()
            .is_some_and(|p| matches!(p, TProjection::Index { .. }))
        {
            let mut current_ty = self.root_type(place.root);
            for projection in &place.path[..place.path.len() - 1] {
                current_ty = match projection {
                    TProjection::Field(index) => match &self.program.types[current_ty.0].kind {
                        TTypeKind::Struct(fields) => fields[*index].ty,
                        _ => return None,
                    },
                    TProjection::Index { is_map, .. } => {
                        match self.program.types[current_ty.0].kind {
                            TTypeKind::Array { element, .. }
                            | TTypeKind::List { element, .. }
                            | TTypeKind::Queue { element, .. }
                            | TTypeKind::Ring { element, .. }
                            | TTypeKind::Grid { element, .. }
                            | TTypeKind::Pool { element, .. } => element,
                            TTypeKind::Map { value, .. } if *is_map => value,
                            _ => return None,
                        }
                    }
                };
            }
            let projection @ TProjection::Index { .. } = place.path.last()? else {
                unreachable!()
            };
            let element = match self.program.types[current_ty.0].kind {
                TTypeKind::Array { element, .. }
                | TTypeKind::List { element, .. }
                | TTypeKind::Queue { element, .. }
                | TTypeKind::Ring { element, .. }
                | TTypeKind::Grid { element, .. }
                | TTypeKind::Pool { element, .. } => element,
                TTypeKind::Map { value, .. } => value,
                _ => return None,
            };
            if matches!(self.program.types[element.0].kind, TTypeKind::Struct(_)) {
                return Some((current_ty, projection.clone(), String::new()));
            }
        }
        if let Some(view) = self.views.get(&place.root) {
            if place.path.is_empty()
                && matches!(self.program.types[place.ty.0].kind, TTypeKind::Struct(_))
            {
                let (capacity, is_list, is_pool, is_map) =
                    match self.program.types[view.collection_ty.0].kind {
                        TTypeKind::Array { capacity, .. } | TTypeKind::Grid { capacity, .. } => {
                            (capacity, false, false, false)
                        }
                        TTypeKind::List { capacity, .. }
                        | TTypeKind::Queue { capacity, .. }
                        | TTypeKind::Ring { capacity, .. } => (capacity, true, false, false),
                        TTypeKind::Pool { capacity, .. } => (capacity, false, true, false),
                        TTypeKind::Map { capacity, .. } => (capacity, false, false, true),
                        _ => return None,
                    };
                let index = TExpr {
                    kind: TExprKind::Local(view.counter_id),
                    ty: Ty::Long,
                    span: Span::default(),
                };
                return Some((
                    view.collection_ty,
                    TProjection::Index {
                        index,
                        constant: None,
                        capacity,
                        is_list,
                        is_pool,
                        is_map,
                        proven: true,
                        grid: None,
                    },
                    view.collection_ptr.clone(),
                ));
            }
        }
        None
    }

    fn emit_growing_field_address(
        &mut self,
        place: &TPlace,
    ) -> Option<(Ty, String, String, usize)> {
        let view = self.views.get(&place.root).cloned();
        let view_lane = if place.path.len() == 1 {
            match place.path[0] {
                TProjection::Field(lane) => Some(lane),
                _ => None,
            }
        } else if place.path.is_empty() {
            Some(0)
        } else {
            None
        };
        if let (Some(view), Some(lane)) = (view.clone(), view_lane) {
            if collection_var_lane(view.collection_ty, &self.program.types, lane)
                .is_some_and(|layout| layout.ty == place.ty)
            {
                let counter = self.temp();
                self.instruction(format!(
                    "{counter} = load i64, ptr %local.{}, align 1",
                    view.counter_id
                ));
                let index = if matches!(
                    self.program.types[view.collection_ty.0].kind,
                    TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
                ) {
                    self.emit_queue_ring_physical_index(
                        view.collection_ty,
                        &view.collection_ptr,
                        &counter,
                    )
                } else {
                    counter
                };
                return Some((view.collection_ty, view.collection_ptr, index, lane));
            }
        }

        let (index_position, lane) = match place.path.as_slice() {
            [.., TProjection::Index { .. }] => (place.path.len() - 1, 0),
            [.., TProjection::Index { .. }, TProjection::Field(lane)] => {
                (place.path.len() - 2, *lane)
            }
            _ => return None,
        };
        let mut collection_ty = self.root_type(place.root);
        for projection in &place.path[..index_position] {
            collection_ty = match projection {
                TProjection::Field(field) => match &self.program.types[collection_ty.0].kind {
                    TTypeKind::Struct(fields) => fields.get(*field)?.ty,
                    _ => return None,
                },
                TProjection::Index {
                    is_map, is_pool, ..
                } => match self.program.types[collection_ty.0].kind {
                    TTypeKind::Array { element, .. }
                    | TTypeKind::List { element, .. }
                    | TTypeKind::Queue { element, .. }
                    | TTypeKind::Ring { element, .. }
                    | TTypeKind::Grid { element, .. }
                    | TTypeKind::Pool { element, .. }
                        if !*is_map && !*is_pool =>
                    {
                        element
                    }
                    TTypeKind::Map { value, .. } if *is_map => value,
                    _ => return None,
                },
            };
        }
        let TProjection::Index {
            index,
            grid,
            proven,
            is_map,
            ..
        } = &place.path[index_position]
        else {
            return None;
        };
        collection_var_lane(collection_ty, &self.program.types, lane)
            .filter(|layout| layout.ty == place.ty)?;
        let mut collection_place = place.clone();
        collection_place.path.truncate(index_position);
        collection_place.ty = collection_ty;
        let collection_pointer = self.emit_place_pointer(&collection_place);
        let index = self.emit_projection_index(
            collection_ty,
            &collection_pointer,
            index,
            grid.as_ref(),
            *proven,
            *is_map,
        );
        Some((collection_ty, collection_pointer, index, lane))
    }

    fn emit_struct_element_address(&mut self, place: &TPlace) -> Option<(Ty, String, String)> {
        let (collection_ty, projection, explicit_ptr) = self.place_struct_element(place)?;
        let has_explicit_pointer = !explicit_ptr.is_empty();
        let pointer = if has_explicit_pointer {
            explicit_ptr
        } else {
            let mut collection_place = place.clone();
            collection_place.path.pop();
            collection_place.ty = collection_ty;
            self.emit_place_pointer(&collection_place)
        };
        let TProjection::Index {
            index,
            grid,
            proven,
            is_map,
            ..
        } = &projection
        else {
            unreachable!()
        };
        let index_value = self.emit_projection_index(
            collection_ty,
            &pointer,
            index,
            grid.as_ref(),
            *proven || has_explicit_pointer,
            *is_map,
        );
        Some((collection_ty, pointer, index_value))
    }

    fn emit_load_place(&mut self, place: &TPlace) -> String {
        if let Some((collection_ty, pointer, index)) = self.emit_struct_element_address(place) {
            return self.emit_collection_element(collection_ty, &pointer, &index);
        }
        let pointer = self.emit_place_pointer(place);
        let result = self.temp();
        self.instruction(format!(
            "{result} = load {}, ptr {pointer}, align 1",
            self.lltype(place.ty)
        ));
        result
    }

    fn emit_store_place(&mut self, place: &TPlace, value: &str) {
        if let Some((collection_ty, pointer, index)) = self.emit_struct_element_address(place) {
            self.emit_store_collection_element(collection_ty, &pointer, &index, value);
            return;
        }
        let pointer = self.emit_place_pointer(place);
        self.instruction(format!(
            "store {} {value}, ptr {pointer}, align 1",
            self.lltype(place.ty)
        ));
    }

    fn emit_call_argument(
        &mut self,
        arg: &TExpr,
        param_ty: Ty,
        mode: ParamMode,
        regions: &mut Vec<CallArgumentRegion>,
    ) -> Option<String> {
        if mode != ParamMode::Read || self.is_pool_type(param_ty) {
            let place = Self::expr_place(arg).expect("checker validated writable place");
            if let Some((collection_ty, collection_ptr, index)) =
                self.emit_struct_element_address(&place)
            {
                let temporary = if is_large_type(param_ty, &self.program.types) {
                    self.emit_runtime_region_alloc(param_ty, arg.span, None)
                } else {
                    self.entry_alloca(param_ty)
                };
                self.emit_gather_collection_element(
                    collection_ty,
                    &collection_ptr,
                    &index,
                    &temporary,
                );
                regions.push(CallArgumentRegion {
                    collection_ty,
                    collection_ptr,
                    index,
                    temporary: temporary.clone(),
                    copy_back: mode != ParamMode::Read,
                });
                return Some(format!("ptr {temporary}"));
            }
            return Some(format!("ptr {}", self.emit_place_pointer(&place)));
        }
        if is_large_type(param_ty, &self.program.types) {
            let pointer = if let Some(place) = Self::expr_place(arg) {
                if let Some((collection_ty, collection_ptr, index)) =
                    self.emit_struct_element_address(&place)
                {
                    let temporary = self.emit_runtime_region_alloc(param_ty, arg.span, None);
                    self.emit_gather_collection_element(
                        collection_ty,
                        &collection_ptr,
                        &index,
                        &temporary,
                    );
                    regions.push(CallArgumentRegion {
                        collection_ty,
                        collection_ptr,
                        index,
                        temporary: temporary.clone(),
                        copy_back: false,
                    });
                    temporary
                } else {
                    self.emit_place_pointer(&place)
                }
            } else {
                let pointer = self.entry_alloca(param_ty);
                self.emit_expr_to(&pointer, arg);
                if self.terminated {
                    return None;
                }
                pointer
            };
            return Some(format!("ptr {pointer}"));
        }
        let value = self.emit_expr(arg);
        (!self.terminated).then(|| format!("{} {value}", self.lltype(param_ty)))
    }

    fn finish_call_argument_regions(&mut self, regions: &[CallArgumentRegion], saved_top: &str) {
        for region in regions.iter().filter(|region| region.copy_back) {
            self.emit_scatter_collection_element(
                region.collection_ty,
                &region.collection_ptr,
                &region.index,
                &region.temporary,
            );
        }
        self.restore_stack_top(saved_top);
    }

    fn ascii_max(&self, ty: Ty) -> Option<usize> {
        match self
            .program
            .types
            .get(ty.0)
            .map(|definition| &definition.kind)
        {
            Some(TTypeKind::Ascii { max_bytes }) => Some(*max_bytes),
            Some(TTypeKind::Text { max_bytes, .. } | TTypeKind::Bytes { max_bytes }) => {
                Some(*max_bytes)
            }
            _ => None,
        }
    }

    fn is_text_type(&self, ty: Ty) -> bool {
        matches!(self.program.types[ty.0].kind, TTypeKind::Text { .. })
    }

    fn is_ascii_type(&self, ty: Ty) -> bool {
        matches!(self.program.types[ty.0].kind, TTypeKind::Ascii { .. })
    }

    fn ascii_static_length(&self, expr: &TExpr) -> Option<usize> {
        static_ascii_length(expr, &self.program.types)
    }

    fn emit_ascii_descriptor_to_local(
        &mut self,
        id: usize,
        descriptor: &str,
        source_ty: Ty,
        destination_ty: Ty,
        span: Span,
    ) {
        let source = self.ascii_field(descriptor, source_ty, 0);
        let length = self.ascii_field(descriptor, source_ty, 1);
        let bytes = self.temp();
        self.instruction(format!("{bytes} = add i64 {length}, 16"));
        let destination = self.emit_runtime_region_alloc_dynamic(
            bytes.as_str(),
            span,
            Some(format!("%local.{id}")),
        );
        let destination_data = self.temp();
        self.instruction(format!(
            "{destination_data} = getelementptr i8, ptr {destination}, i64 16"
        ));
        let data_field = self.temp();
        self.instruction(format!(
            "{data_field} = getelementptr {}, ptr {destination}, i32 0, i32 0",
            self.lltype(destination_ty)
        ));
        self.instruction(format!(
            "store ptr {destination_data}, ptr {data_field}, align 1"
        ));
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {destination_data}, ptr {source}, i64 {length}, i1 false)"
        ));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(destination_ty)
        ));
        self.instruction(format!("store i64 {length}, ptr {length_field}, align 1"));
    }

    fn ascii_field(&mut self, descriptor: &str, ty: Ty, index: usize) -> String {
        let value = self.temp();
        self.instruction(format!(
            "{value} = extractvalue {} {descriptor}, {index}",
            self.lltype(ty)
        ));
        value
    }

    fn emit_ascii_descriptor(&mut self, expr: &TExpr) -> String {
        if matches!(
            expr.kind,
            TExprKind::Binary {
                op: BinaryOp::Add,
                ..
            }
        ) {
            let pointer = self.emit_runtime_region_alloc(expr.ty, expr.span, None);
            self.emit_expr_to(&pointer, expr);
            if self.terminated {
                return String::new();
            }
            let descriptor = self.temp();
            self.instruction(format!(
                "{descriptor} = load {}, ptr {pointer}, align 1",
                self.lltype(expr.ty)
            ));
            descriptor
        } else {
            self.emit_expr(expr)
        }
    }

    fn emit_ascii_stream(&mut self, expr: &TExpr, destination: &str, offset_slot: &str) {
        if self.terminated {
            return;
        }
        match &expr.kind {
            TExprKind::AsciiEmpty => {}
            TExprKind::ByteString(bytes) if self.ascii_max(expr.ty).is_some() => {
                let current = self.temp();
                self.instruction(format!("{current} = load i64, ptr {offset_slot}, align 1"));
                let start = self.temp();
                self.instruction(format!(
                    "{start} = getelementptr i8, ptr {destination}, i64 {current}"
                ));
                for (index, byte) in bytes.iter().enumerate() {
                    let ptr = self.temp();
                    self.instruction(format!(
                        "{ptr} = getelementptr i8, ptr {start}, i64 {index}"
                    ));
                    self.instruction(format!("store i8 {byte}, ptr {ptr}, align 1"));
                }
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {current}, {}", bytes.len()));
                self.instruction(format!("store i64 {next}, ptr {offset_slot}, align 1"));
            }
            TExprKind::Binary {
                op: BinaryOp::Add,
                left,
                right,
                ..
            } if self.ascii_max(expr.ty).is_some() => {
                self.emit_ascii_stream(left, destination, offset_slot);
                self.emit_ascii_stream(right, destination, offset_slot);
            }
            TExprKind::AsciiUpper(value) => {
                let descriptor = self.emit_ascii_descriptor(value);
                if self.terminated {
                    return;
                }
                let source = self.ascii_field(&descriptor, value.ty, 0);
                let length = self.ascii_field(&descriptor, value.ty, 1);
                let current = self.temp();
                self.instruction(format!("{current} = load i64, ptr {offset_slot}, align 1"));
                let target = self.temp();
                self.instruction(format!(
                    "{target} = getelementptr i8, ptr {destination}, i64 {current}"
                ));
                self.instruction(format!(
                    "call void @nl_ascii_upper_copy(ptr {source}, ptr {target}, i64 {length})"
                ));
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {current}, {length}"));
                self.instruction(format!("store i64 {next}, ptr {offset_slot}, align 1"));
            }
            TExprKind::TextUpper(value) => {
                let descriptor = self.emit_ascii_descriptor(value);
                if self.terminated {
                    return;
                }
                let source = self.ascii_field(&descriptor, value.ty, 0);
                let length = self.ascii_field(&descriptor, value.ty, 1);
                let current = self.temp();
                self.instruction(format!("{current} = load i64, ptr {offset_slot}, align 1"));
                let target = self.temp();
                self.instruction(format!(
                    "{target} = getelementptr i8, ptr {destination}, i64 {current}"
                ));
                let written = self.temp();
                self.instruction(format!(
                    "{written} = call i64 @nl_text_upper_copy(ptr {source}, i64 {length}, ptr {target}, ptr null)"
                ));
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {current}, {written}"));
                self.instruction(format!("store i64 {next}, ptr {offset_slot}, align 1"));
            }
            TExprKind::AsciiFormat(value) => {
                let raw = self.emit_expr(value);
                if self.terminated {
                    return;
                }
                let numeric = if base_type(value.ty, &self.program.types) == Ty::Int {
                    let extended = self.temp();
                    self.instruction(format!("{extended} = sext i32 {raw} to i64"));
                    extended
                } else {
                    raw
                };
                let current = self.temp();
                self.instruction(format!("{current} = load i64, ptr {offset_slot}, align 1"));
                let target = self.temp();
                self.instruction(format!(
                    "{target} = getelementptr i8, ptr {destination}, i64 {current}"
                ));
                let length = self.temp();
                self.instruction(format!(
                    "{length} = call i64 @nl_ascii_format_i64(i64 {numeric}, ptr {target})"
                ));
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {current}, {length}"));
                self.instruction(format!("store i64 {next}, ptr {offset_slot}, align 1"));
            }
            TExprKind::Try {
                value,
                success_ty,
                error_ty,
                propagated_ty,
            } if self.ascii_max(*success_ty).is_some() => {
                let original_length = self.temp();
                self.instruction(format!(
                    "{original_length} = load i64, ptr {offset_slot}, align 1"
                ));
                let result_storage = match &value.kind {
                    TExprKind::Call {
                        target: CallTarget::Function(function_id),
                        args,
                        ..
                    } if result_ascii_payload(value.ty, &self.program.types).is_some() => self
                        .emit_ascii_append_result_call(
                            *function_id,
                            args,
                            destination,
                            &original_length,
                            expr.span,
                        ),
                    TExprKind::IndirectCall {
                        callee,
                        args,
                        params,
                        ..
                    } if result_ascii_payload(value.ty, &self.program.types).is_some()
                        && self.function_type_supports_append(callee.ty) =>
                    {
                        self.emit_ascii_append_indirect_result_call(
                            callee,
                            args,
                            params,
                            value.ty,
                            destination,
                            &original_length,
                            expr.span,
                        )
                    }
                    _ => None,
                };
                if let Some(result_storage) = result_storage {
                    let ascii = self.emit_try_from_storage(
                        value.ty,
                        *success_ty,
                        *error_ty,
                        *propagated_ty,
                        &result_storage,
                    );
                    if self.terminated {
                        return;
                    }
                    let amount = self.ascii_field(&ascii, *success_ty, 1);
                    let new_length = self.temp();
                    self.instruction(format!(
                        "{new_length} = add i64 {original_length}, {amount}"
                    ));
                    self.instruction(format!(
                        "store i64 {new_length}, ptr {offset_slot}, align 1"
                    ));
                } else {
                    let descriptor = self.emit_ascii_descriptor(expr);
                    if self.terminated {
                        return;
                    }
                    let source = self.ascii_field(&descriptor, expr.ty, 0);
                    let length = self.ascii_field(&descriptor, expr.ty, 1);
                    let target = self.temp();
                    self.instruction(format!(
                        "{target} = getelementptr i8, ptr {destination}, i64 {original_length}"
                    ));
                    self.instruction(format!(
                        "call void @llvm.memmove.p0.p0.i64(ptr {target}, ptr {source}, i64 {length}, i1 false)"
                    ));
                    let next = self.temp();
                    self.instruction(format!("{next} = add i64 {original_length}, {length}"));
                    self.instruction(format!("store i64 {next}, ptr {offset_slot}, align 1"));
                }
            }
            TExprKind::Call {
                target: CallTarget::Function(function_id),
                args,
                ..
            } if self.is_ascii_type(expr.ty) => {
                self.emit_ascii_append_call(
                    *function_id,
                    args,
                    destination,
                    offset_slot,
                    expr.span,
                );
            }
            TExprKind::IndirectCall {
                callee,
                args,
                params,
                ..
            } if self.is_ascii_type(expr.ty) && self.function_type_supports_append(callee.ty) => {
                if !self.emit_ascii_append_indirect_call(
                    callee,
                    args,
                    params,
                    destination,
                    offset_slot,
                    expr.span,
                ) {
                    let descriptor = self.emit_ascii_descriptor(expr);
                    if self.terminated {
                        return;
                    }
                    let source = self.ascii_field(&descriptor, expr.ty, 0);
                    let length = self.ascii_field(&descriptor, expr.ty, 1);
                    let current = self.temp();
                    self.instruction(format!("{current} = load i64, ptr {offset_slot}, align 1"));
                    let target = self.temp();
                    self.instruction(format!(
                        "{target} = getelementptr i8, ptr {destination}, i64 {current}"
                    ));
                    self.instruction(format!(
                        "call void @llvm.memmove.p0.p0.i64(ptr {target}, ptr {source}, i64 {length}, i1 false)"
                    ));
                    let next = self.temp();
                    self.instruction(format!("{next} = add i64 {current}, {length}"));
                    self.instruction(format!("store i64 {next}, ptr {offset_slot}, align 1"));
                }
            }
            TExprKind::AsciiCast(value) | TExprKind::Take(value) => {
                let descriptor = self.emit_ascii_descriptor(value);
                if self.terminated {
                    return;
                }
                let source = self.ascii_field(&descriptor, value.ty, 0);
                let length = self.ascii_field(&descriptor, value.ty, 1);
                if matches!(expr.kind, TExprKind::AsciiCast(_)) {
                    let fits = self.temp();
                    self.instruction(format!(
                        "{fits} = icmp ule i64 {length}, {}",
                        self.ascii_max(expr.ty).unwrap_or(0)
                    ));
                    let bad = self.temp();
                    self.instruction(format!("{bad} = xor i1 {fits}, true"));
                    self.guard(bad, Failure::BadCast, expr.span);
                    if self.terminated {
                        return;
                    }
                }
                let current = self.temp();
                self.instruction(format!("{current} = load i64, ptr {offset_slot}, align 1"));
                let target = self.temp();
                self.instruction(format!(
                    "{target} = getelementptr i8, ptr {destination}, i64 {current}"
                ));
                self.instruction(format!(
                    "call void @llvm.memmove.p0.p0.i64(ptr {target}, ptr {source}, i64 {length}, i1 false)"
                ));
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {current}, {length}"));
                self.instruction(format!("store i64 {next}, ptr {offset_slot}, align 1"));
            }
            _ => {
                let descriptor = self.emit_ascii_descriptor(expr);
                if self.terminated {
                    return;
                }
                let source = self.ascii_field(&descriptor, expr.ty, 0);
                let length = self.ascii_field(&descriptor, expr.ty, 1);
                let current = self.temp();
                self.instruction(format!("{current} = load i64, ptr {offset_slot}, align 1"));
                let target = self.temp();
                self.instruction(format!(
                    "{target} = getelementptr i8, ptr {destination}, i64 {current}"
                ));
                self.instruction(format!(
                    "call void @llvm.memmove.p0.p0.i64(ptr {target}, ptr {source}, i64 {length}, i1 false)"
                ));
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {current}, {length}"));
                self.instruction(format!("store i64 {next}, ptr {offset_slot}, align 1"));
            }
        }
    }

    fn emit_result_ascii_append_return(&mut self, expr: &TExpr) {
        let Some(payload_ty) = result_ascii_payload(self.function.result, &self.program.types)
        else {
            self.emit_expr_to("%nl.result", expr);
            return;
        };
        if let TExprKind::If {
            condition,
            then_block,
            else_block,
        } = &expr.kind
        {
            let condition = self.emit_expr(condition);
            if self.terminated {
                return;
            }
            let then_label = self.new_label("result.append.if.ok");
            let else_label = self.new_label("result.append.if.err");
            self.terminate(format!(
                "br i1 {condition}, label %{then_label}, label %{else_label}"
            ));
            self.start_block(&then_label);
            self.emit_result_ascii_append_block(then_block);
            self.start_block(&else_label);
            if let Some(other) = else_block {
                self.emit_result_ascii_append_block(other);
            } else {
                self.emit_all_iteration_cleanups();
                self.terminate("ret void");
            }
            return;
        }
        let result_type = expr.ty;
        let (case_index, value) = match &expr.kind {
            TExprKind::Construct { case_index, args } if args.len() == 1 => {
                (*case_index, args.first())
            }
            _ => {
                self.emit_result_ascii_append_fresh(expr);
                return;
            }
        };
        if case_index != 0 {
            self.emit_result_ascii_append_fresh(expr);
            return;
        }
        let Some(value) = value else {
            self.emit_result_ascii_append_fresh(expr);
            return;
        };
        if self.ascii_max(value.ty).is_none() || self.terminated {
            self.emit_result_ascii_append_fresh(expr);
            return;
        }
        let start = self.temp();
        self.instruction(format!(
            "{start} = load i64, ptr %nl.append.offset, align 1"
        ));
        let (data, amount, final_length) =
            if local_root(value).is_some_and(|id| self.append_builder_local == Some(id)) {
                let descriptor = self.emit_expr(value);
                if self.terminated {
                    return;
                }
                let data = self.ascii_field(&descriptor, value.ty, 0);
                let amount = self.ascii_field(&descriptor, value.ty, 1);
                let final_length = self.temp();
                self.instruction(format!("{final_length} = add i64 {start}, {amount}"));
                (data, amount, final_length)
            } else {
                self.emit_ascii_stream(value, "%nl.append.data", "%nl.append.offset");
                if self.terminated {
                    return;
                }
                let final_length = self.temp();
                self.instruction(format!(
                    "{final_length} = load i64, ptr %nl.append.offset, align 1"
                ));
                let amount = self.temp();
                self.instruction(format!("{amount} = sub i64 {final_length}, {start}"));
                let data = self.temp();
                self.instruction(format!(
                    "{data} = getelementptr i8, ptr %nl.append.data, i64 {start}"
                ));
                (data, amount, final_length)
            };
        self.instruction(format!(
            "store i64 {final_length}, ptr %nl.append.offset, align 1"
        ));
        let bytes = type_size(
            result_type,
            &self.program.types,
            &mut vec![None; self.program.types.len()],
        );
        self.instruction(format!(
            "call void @llvm.memset.p0.i64(ptr %nl.result, i8 0, i64 {bytes}, i1 false)"
        ));
        let tag = self.temp();
        self.instruction(format!(
            "{tag} = getelementptr {}, ptr %nl.result, i32 0, i32 0",
            self.lltype(result_type)
        ));
        self.instruction(format!("store i32 0, ptr {tag}, align 1"));
        let payload = self.temp();
        self.instruction(format!(
            "{payload} = getelementptr {}, ptr %nl.result, i32 0, i32 1",
            self.lltype(result_type)
        ));
        let data_field = self.temp();
        self.instruction(format!(
            "{data_field} = getelementptr i8, ptr {payload}, i64 0"
        ));
        self.instruction(format!("store ptr {data}, ptr {data_field}, align 1"));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr i8, ptr {payload}, i64 8"
        ));
        self.instruction(format!("store i64 {amount}, ptr {length_field}, align 1"));
        debug_assert!(self.ascii_max(payload_ty).is_some());
    }

    fn emit_result_ascii_append_fresh(&mut self, expr: &TExpr) {
        self.emit_expr_to("%nl.result", expr);
        if self.terminated {
            return;
        }
        let result_ty = self.function.result;
        let entry_offset = self
            .append_entry_offset
            .clone()
            .expect("Result<Ascii> append variant records its entry offset");
        let tag_pointer = self.temp();
        self.instruction(format!(
            "{tag_pointer} = getelementptr {}, ptr %nl.result, i32 0, i32 0",
            self.lltype(result_ty)
        ));
        let tag = self.temp();
        self.instruction(format!("{tag} = load i32, ptr {tag_pointer}, align 4"));
        let succeeded = self.temp();
        self.instruction(format!("{succeeded} = icmp eq i32 {tag}, 0"));
        let success_label = self.new_label("result.append.fresh.ok");
        let error_label = self.new_label("result.append.fresh.err");
        let merge = self.new_label("result.append.fresh.end");
        self.terminate(format!(
            "br i1 {succeeded}, label %{success_label}, label %{error_label}"
        ));
        self.start_block(&success_label);
        let payload = self.temp();
        self.instruction(format!(
            "{payload} = getelementptr {}, ptr %nl.result, i32 0, i32 1",
            self.lltype(result_ty)
        ));
        let source_data_field = self.temp();
        self.instruction(format!(
            "{source_data_field} = getelementptr i8, ptr {payload}, i64 0"
        ));
        let source_data = self.temp();
        self.instruction(format!(
            "{source_data} = load ptr, ptr {source_data_field}, align 1"
        ));
        let amount_field = self.temp();
        self.instruction(format!(
            "{amount_field} = getelementptr i8, ptr {payload}, i64 8"
        ));
        let amount = self.temp();
        self.instruction(format!("{amount} = load i64, ptr {amount_field}, align 1"));
        let accepted = self.temp();
        self.instruction(format!(
            "{accepted} = load i64, ptr {entry_offset}, align 1"
        ));
        let target = self.temp();
        self.instruction(format!(
            "{target} = getelementptr i8, ptr %nl.append.data, i64 {accepted}"
        ));
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {target}, ptr {source_data}, i64 {amount}, i1 false)"
        ));
        self.instruction(format!(
            "store ptr {target}, ptr {source_data_field}, align 1"
        ));
        self.instruction(format!("store i64 {amount}, ptr {amount_field}, align 1"));
        let new_length = self.temp();
        self.instruction(format!("{new_length} = add i64 {accepted}, {amount}"));
        self.instruction(format!(
            "store i64 {new_length}, ptr %nl.append.offset, align 1"
        ));
        self.terminate(format!("br label %{merge}"));
        self.start_block(&error_label);
        let accepted = self.temp();
        self.instruction(format!(
            "{accepted} = load i64, ptr {entry_offset}, align 1"
        ));
        self.instruction(format!(
            "store i64 {accepted}, ptr %nl.append.offset, align 1"
        ));
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
    }

    fn emit_result_ascii_append_block(&mut self, block: &TBlock) {
        self.emit_block_contents(block);
        if self.terminated {
            return;
        }
        if let Some(tail) = block.tail.as_deref() {
            self.emit_result_ascii_append_return(tail);
        }
        if !self.terminated {
            self.emit_all_iteration_cleanups();
            self.terminate("ret void");
        }
    }

    fn function_type_supports_append(&self, ty: Ty) -> bool {
        matches!(
            self.program.types.get(ty.0).map(|ty| &ty.kind),
            Some(TTypeKind::Function {
                supports_append: true,
                ..
            })
        )
    }

    fn emit_ascii_append_call(
        &mut self,
        function_id: usize,
        args: &[TExpr],
        destination: &str,
        offset_slot: &str,
        call_span: Span,
    ) {
        let function = self.program.functions[function_id].clone();
        if !self.is_ascii_type(function.result) {
            let mut call = TExpr {
                kind: TExprKind::Call {
                    target: CallTarget::Function(function_id),
                    args: args.to_vec(),
                    effect: Effect::None,
                },
                ty: function.result,
                span: call_span,
            };
            let _ = &mut call;
            return;
        }
        let saved_top = self.stack_top.clone();
        let mut call_args = vec![
            "ptr %nl.ctx".to_owned(),
            format!("ptr {destination}"),
            format!("ptr {offset_slot}"),
        ];
        let mut regions = Vec::new();
        for (arg, param) in args.iter().zip(&function.params) {
            let Some(value) = self.emit_call_argument(arg, param.ty, param.mode, &mut regions)
            else {
                return;
            };
            call_args.push(value);
        }
        call_args.insert(1, format!("ptr {}", self.stack_top));
        if function.recursive {
            self.emit_recursion_check(&[function_id], call_span);
        }
        self.instruction(format!(
            "call void @nl_fn_{function_id}_append({})",
            call_args.join(", ")
        ));
        self.finish_call_argument_regions(&regions, &saved_top);
    }

    fn emit_ascii_append_result_call(
        &mut self,
        function_id: usize,
        args: &[TExpr],
        destination: &str,
        accepted: &str,
        call_span: Span,
    ) -> Option<String> {
        let function = self.program.functions[function_id].clone();
        if result_ascii_payload(function.result, &self.program.types).is_none() {
            return None;
        }
        let result_size = stack_storage_size(function.result, &self.program.types);
        let result_storage = self.entry_alloca_raw(&format!("[{result_size} x i8]"));
        let offset = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 {accepted}, ptr {offset}, align 1"));
        let saved_top = self.stack_top.clone();
        let mut call_args = vec![
            "ptr %nl.ctx".to_owned(),
            format!("ptr {result_storage}"),
            format!("ptr {destination}"),
            format!("ptr {offset}"),
        ];
        let mut regions = Vec::new();
        for (arg, param) in args.iter().zip(&function.params) {
            let value = self.emit_call_argument(arg, param.ty, param.mode, &mut regions)?;
            call_args.push(value);
        }
        call_args.insert(1, format!("ptr {}", self.stack_top));
        if function.recursive {
            self.emit_recursion_check(&[function_id], call_span);
        }
        self.instruction(format!(
            "call void @nl_fn_{function_id}_append({})",
            call_args.join(", ")
        ));
        self.finish_call_argument_regions(&regions, &saved_top);
        Some(result_storage)
    }

    fn emit_ascii_append_indirect_result_call(
        &mut self,
        callee: &TExpr,
        args: &[TExpr],
        params: &[TFunctionTypeParam],
        result_ty: Ty,
        destination: &str,
        accepted: &str,
        call_span: Span,
    ) -> Option<String> {
        let targets = self
            .program
            .function_type_targets
            .get(callee.ty.0)
            .cloned()
            .unwrap_or_default();
        if targets.is_empty()
            || targets.iter().any(|target| {
                result_ascii_payload(self.program.functions[*target].result, &self.program.types)
                    .is_none()
            })
        {
            return None;
        }
        let function_value = self.emit_expr(callee);
        if self.terminated {
            return None;
        }
        let result_size = stack_storage_size(result_ty, &self.program.types);
        let result_storage = self.entry_alloca_raw(&format!("[{result_size} x i8]"));
        let offset = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 {accepted}, ptr {offset}, align 1"));
        let saved_top = self.stack_top.clone();
        let mut lowered_args = Vec::with_capacity(args.len());
        let mut regions = Vec::new();
        for (arg, param) in args.iter().zip(params) {
            let value = self.emit_call_argument(arg, param.ty, param.mode, &mut regions)?;
            lowered_args.push(value);
        }
        let call_top = self.stack_top.clone();
        let recursive = targets
            .iter()
            .filter(|target| self.program.functions[**target].recursive)
            .copied()
            .collect::<Vec<_>>();
        self.emit_recursion_check(&recursive, call_span);
        let merge = self.new_label("ascii.append.result.indirect.merge");
        for (index, target) in targets.iter().enumerate() {
            let append_label = self.new_label("ascii.append.result.indirect.target");
            let next_label = self.new_label("ascii.append.result.indirect.next");
            let matches = self.temp();
            self.instruction(format!(
                "{matches} = icmp eq ptr {function_value}, @nl_fn_{target}"
            ));
            self.terminate(format!(
                "br i1 {matches}, label %{append_label}, label %{next_label}"
            ));
            self.start_block(&append_label);
            let mut call_args = vec![
                "ptr %nl.ctx".to_owned(),
                format!("ptr {call_top}"),
                format!("ptr {result_storage}"),
                format!("ptr {destination}"),
                format!("ptr {offset}"),
            ];
            call_args.extend(lowered_args.iter().cloned());
            self.instruction(format!(
                "call void @nl_fn_{target}_append({})",
                call_args.join(", ")
            ));
            if self.stack_top != saved_top {
                self.instruction(format!(
                    "call void @nl_context_set_top(ptr %nl.ctx, ptr {saved_top})"
                ));
            }
            self.terminate(format!("br label %{merge}"));
            self.start_block(&next_label);
            if index + 1 == targets.len() {
                self.terminate("unreachable");
            }
        }
        self.start_block(&merge);
        self.stack_top = saved_top;
        let _ = regions;
        Some(result_storage)
    }

    fn emit_ascii_append_indirect_call(
        &mut self,
        callee: &TExpr,
        args: &[TExpr],
        params: &[TFunctionTypeParam],
        destination: &str,
        offset_slot: &str,
        call_span: Span,
    ) -> bool {
        let targets = self
            .program
            .function_type_targets
            .get(callee.ty.0)
            .cloned()
            .unwrap_or_default();
        if targets.is_empty()
            || targets.iter().any(|target| {
                self.ascii_max(self.program.functions[*target].result)
                    .is_none()
            })
        {
            return false;
        }
        let function_value = self.emit_expr(callee);
        if self.terminated {
            return true;
        }
        let saved_top = self.stack_top.clone();
        let mut lowered_args = Vec::with_capacity(args.len());
        let mut regions = Vec::new();
        for (arg, param) in args.iter().zip(params) {
            let Some(value) = self.emit_call_argument(arg, param.ty, param.mode, &mut regions)
            else {
                return true;
            };
            lowered_args.push(value);
        }
        let call_top = self.stack_top.clone();
        let recursive = targets
            .iter()
            .filter(|target| self.program.functions[**target].recursive)
            .copied()
            .collect::<Vec<_>>();
        self.emit_recursion_check(&recursive, call_span);
        let merge = self.new_label("ascii.append.indirect.merge");
        for (index, target) in targets.iter().enumerate() {
            let append_label = self.new_label("ascii.append.indirect.target");
            let next_label = self.new_label("ascii.append.indirect.next");
            let matches = self.temp();
            self.instruction(format!(
                "{matches} = icmp eq ptr {function_value}, @nl_fn_{target}"
            ));
            self.terminate(format!(
                "br i1 {matches}, label %{append_label}, label %{next_label}"
            ));
            self.start_block(&append_label);
            let mut call_args = vec![
                "ptr %nl.ctx".to_owned(),
                format!("ptr {call_top}"),
                format!("ptr {destination}"),
                format!("ptr {offset_slot}"),
            ];
            call_args.extend(lowered_args.iter().cloned());
            self.instruction(format!(
                "call void @nl_fn_{target}_append({})",
                call_args.join(", ")
            ));
            if self.stack_top != saved_top {
                self.instruction(format!(
                    "call void @nl_context_set_top(ptr %nl.ctx, ptr {saved_top})"
                ));
            }
            self.terminate(format!("br label %{merge}"));
            self.start_block(&next_label);
            if index + 1 == targets.len() {
                self.terminate("unreachable");
            }
        }
        self.start_block(&merge);
        self.stack_top = saved_top;
        let _ = regions;
        true
    }

    fn emit_ascii_to(&mut self, destination: &str, expr: &TExpr) {
        let data = self.temp();
        self.instruction(format!(
            "{data} = getelementptr i8, ptr {destination}, i64 16"
        ));
        self.emit_ascii_to_data(destination, expr, &data);
    }

    fn emit_ascii_to_data(&mut self, destination: &str, expr: &TExpr, data: &str) {
        let data_field = self.temp();
        self.instruction(format!(
            "{data_field} = getelementptr {}, ptr {destination}, i32 0, i32 0",
            self.lltype(expr.ty)
        ));
        self.instruction(format!("store ptr {data}, ptr {data_field}, align 1"));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(expr.ty)
        ));
        let offset_slot = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {offset_slot}, align 1"));
        self.emit_ascii_stream(expr, &data, &offset_slot);
        if self.terminated {
            return;
        }
        let length = self.temp();
        self.instruction(format!("{length} = load i64, ptr {offset_slot}, align 1"));
        self.instruction(format!("store i64 {length}, ptr {length_field}, align 1"));
    }

    fn emit_text_to(&mut self, destination: &str, expr: &TExpr) {
        if let TExprKind::TextConvert {
            value,
            conversion: StringConversion::AsciiToText,
            ..
        } = &expr.kind
        {
            let descriptor = self.emit_expr(value);
            if self.terminated {
                return;
            }
            let data = self.ascii_field(&descriptor, value.ty, 0);
            let length = self.ascii_field(&descriptor, value.ty, 1);
            let data_field = self.temp();
            self.instruction(format!(
                "{data_field} = getelementptr {}, ptr {destination}, i32 0, i32 0",
                self.lltype(expr.ty)
            ));
            self.instruction(format!("store ptr {data}, ptr {data_field}, align 1"));
            let len_field = self.temp();
            self.instruction(format!(
                "{len_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
                self.lltype(expr.ty)
            ));
            self.instruction(format!("store i64 {length}, ptr {len_field}, align 1"));
            let cp_field = self.temp();
            self.instruction(format!(
                "{cp_field} = getelementptr {}, ptr {destination}, i32 0, i32 2",
                self.lltype(expr.ty)
            ));
            self.instruction(format!("store i64 {length}, ptr {cp_field}, align 1"));
            return;
        }
        let data = self.temp();
        self.instruction(format!(
            "{data} = getelementptr i8, ptr {destination}, i64 24"
        ));
        self.emit_text_to_data(destination, expr, &data);
    }

    fn emit_text_to_data(&mut self, destination: &str, expr: &TExpr, data: &str) {
        if matches!(
            expr.kind,
            TExprKind::TextConvert {
                conversion: StringConversion::AsciiToText,
                ..
            }
        ) {
            self.emit_text_to(destination, expr);
            return;
        }
        let data_field = self.temp();
        self.instruction(format!(
            "{data_field} = getelementptr {}, ptr {destination}, i32 0, i32 0",
            self.lltype(expr.ty)
        ));
        self.instruction(format!("store ptr {data}, ptr {data_field}, align 1"));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(expr.ty)
        ));
        let cp_field = self.temp();
        self.instruction(format!(
            "{cp_field} = getelementptr {}, ptr {destination}, i32 0, i32 2",
            self.lltype(expr.ty)
        ));
        let offset_slot = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {offset_slot}, align 1"));
        self.emit_ascii_stream(expr, &data, &offset_slot);
        if self.terminated {
            return;
        }
        let length = self.temp();
        self.instruction(format!("{length} = load i64, ptr {offset_slot}, align 1"));
        self.instruction(format!("store i64 {length}, ptr {length_field}, align 1"));
        let count = self.entry_alloca(Ty::Long);
        let valid = self.temp();
        self.instruction(format!(
            "{valid} = call i32 @nl_utf8_count(ptr {data}, i64 {length}, ptr {count})"
        ));
        let invalid = self.temp();
        self.instruction(format!("{invalid} = icmp eq i32 {valid}, 0"));
        self.guard(invalid, Failure::BadCast, expr.span);
        if self.terminated {
            return;
        }
        let codepoints = self.temp();
        self.instruction(format!("{codepoints} = load i64, ptr {count}, align 1"));
        self.instruction(format!("store i64 {codepoints}, ptr {cp_field}, align 1"));
    }

    fn emit_bytes_view_to(&mut self, destination: &str, expr: &TExpr, receiver: &TExpr) {
        let descriptor = self.emit_expr(receiver);
        if self.terminated {
            return;
        }
        let data = self.ascii_field(&descriptor, receiver.ty, 0);
        let length = self.ascii_field(&descriptor, receiver.ty, 1);
        let data_field = self.temp();
        self.instruction(format!(
            "{data_field} = getelementptr {}, ptr {destination}, i32 0, i32 0",
            self.lltype(expr.ty)
        ));
        self.instruction(format!("store ptr {data}, ptr {data_field}, align 1"));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(expr.ty)
        ));
        self.instruction(format!("store i64 {length}, ptr {length_field}, align 1"));
    }

    fn emit_string_slice_to(
        &mut self,
        destination: &str,
        expr: &TExpr,
        receiver: &TExpr,
        start_expr: &TExpr,
        end_expr: &TExpr,
        text: bool,
    ) {
        let descriptor = self.emit_expr(receiver);
        if self.terminated {
            return;
        }
        let start = self.emit_expr(start_expr);
        if self.terminated {
            return;
        }
        let end = self.emit_expr(end_expr);
        if self.terminated {
            return;
        }
        let source = self.ascii_field(&descriptor, receiver.ty, 0);
        let source_length = self.ascii_field(&descriptor, receiver.ty, 1);
        let source_count = if text {
            self.ascii_field(&descriptor, receiver.ty, 2)
        } else {
            source_length.clone()
        };
        let start_nonnegative = self.temp();
        self.instruction(format!("{start_nonnegative} = icmp sge i64 {start}, 0"));
        let end_after_start = self.temp();
        self.instruction(format!("{end_after_start} = icmp sge i64 {end}, {start}"));
        let end_in_range = self.temp();
        self.instruction(format!(
            "{end_in_range} = icmp sle i64 {end}, {source_count}"
        ));
        let first_pair = self.temp();
        self.instruction(format!(
            "{first_pair} = and i1 {start_nonnegative}, {end_after_start}"
        ));
        let fits = self.temp();
        self.instruction(format!("{fits} = and i1 {first_pair}, {end_in_range}"));
        let bad = self.temp();
        self.instruction(format!("{bad} = xor i1 {fits}, true"));
        self.guard(bad, Failure::IndexOutOfRange, expr.span);
        if self.terminated {
            return;
        }
        let (start_byte, end_byte) = if text {
            let start_byte = self.temp();
            self.instruction(format!(
                "{start_byte} = call i64 @nl_utf8_offset(ptr {source}, i64 {source_length}, i64 {start})"
            ));
            let end_byte = self.temp();
            self.instruction(format!(
                "{end_byte} = call i64 @nl_utf8_offset(ptr {source}, i64 {source_length}, i64 {end})"
            ));
            (start_byte, end_byte)
        } else {
            (start.clone(), end.clone())
        };
        let result_length = self.temp();
        self.instruction(format!(
            "{result_length} = sub i64 {end_byte}, {start_byte}"
        ));
        let source_start = self.temp();
        self.instruction(format!(
            "{source_start} = getelementptr i8, ptr {source}, i64 {start_byte}"
        ));
        let inline_offset = if text { 24 } else { 16 };
        let result_data = self.temp();
        self.instruction(format!(
            "{result_data} = getelementptr i8, ptr {destination}, i64 {inline_offset}"
        ));
        let data_field = self.temp();
        self.instruction(format!(
            "{data_field} = getelementptr {}, ptr {destination}, i32 0, i32 0",
            self.lltype(expr.ty)
        ));
        self.instruction(format!(
            "store ptr {result_data}, ptr {data_field}, align 1"
        ));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(expr.ty)
        ));
        self.instruction(format!(
            "store i64 {result_length}, ptr {length_field}, align 1"
        ));
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {result_data}, ptr {source_start}, i64 {result_length}, i1 false)"
        ));
        if text {
            let cp_count = self.temp();
            self.instruction(format!("{cp_count} = sub i64 {end}, {start}"));
            let cp_field = self.temp();
            self.instruction(format!(
                "{cp_field} = getelementptr {}, ptr {destination}, i32 0, i32 2",
                self.lltype(expr.ty)
            ));
            self.instruction(format!("store i64 {cp_count}, ptr {cp_field}, align 1"));
        }
    }

    fn emit_text_conversion_to(&mut self, destination: &str, expr: &TExpr) {
        let TExprKind::TextConvert {
            value,
            target,
            conversion,
        } = &expr.kind
        else {
            unreachable!()
        };
        let source_descriptor = self.emit_expr(value);
        if self.terminated {
            return;
        }
        let source = self.ascii_field(&source_descriptor, value.ty, 0);
        let length = self.ascii_field(&source_descriptor, value.ty, 1);
        let codepoints = self.entry_alloca(Ty::Long);
        let valid = match conversion {
            StringConversion::BytesToText => self.temp(),
            StringConversion::BytesToAscii | StringConversion::TextToAscii => self.temp(),
            StringConversion::AsciiToText => unreachable!("borrowed conversion is not a Result"),
        };
        match conversion {
            StringConversion::BytesToText => self.instruction(format!(
                "{valid} = call i32 @nl_utf8_count(ptr {source}, i64 {length}, ptr {codepoints})"
            )),
            StringConversion::BytesToAscii | StringConversion::TextToAscii => self.instruction(
                format!("{valid} = call i32 @nl_bytes_are_ascii(ptr {source}, i64 {length})"),
            ),
            StringConversion::AsciiToText => unreachable!(),
        }
        let okay = self.temp();
        self.instruction(format!("{okay} = icmp ne i32 {valid}, 0"));
        let ok_label = self.new_label("text.convert.ok");
        let error_label = self.new_label("text.convert.error");
        let merge_label = self.new_label("text.convert.merge");
        let incoming_stack_top = self.stack_top.clone();
        self.terminate(format!(
            "br i1 {okay}, label %{ok_label}, label %{error_label}"
        ));
        self.start_block(&ok_label);
        let result_storage = self.emit_runtime_region_alloc(*target, expr.span, None);
        let data_offset = if self.is_text_type(*target) { 24 } else { 16 };
        let data = self.temp();
        self.instruction(format!(
            "{data} = getelementptr i8, ptr {result_storage}, i64 {data_offset}"
        ));
        let data_field = self.temp();
        self.instruction(format!(
            "{data_field} = getelementptr {}, ptr {result_storage}, i32 0, i32 0",
            self.lltype(*target)
        ));
        self.instruction(format!("store ptr {data}, ptr {data_field}, align 1"));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {result_storage}, i32 0, i32 1",
            self.lltype(*target)
        ));
        self.instruction(format!("store i64 {length}, ptr {length_field}, align 1"));
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {data}, ptr {source}, i64 {length}, i1 false)"
        ));
        if self.is_text_type(*target) {
            let cp = self.temp();
            self.instruction(format!("{cp} = load i64, ptr {codepoints}, align 1"));
            let cp_field = self.temp();
            self.instruction(format!(
                "{cp_field} = getelementptr {}, ptr {result_storage}, i32 0, i32 2",
                self.lltype(*target)
            ));
            self.instruction(format!("store i64 {cp}, ptr {cp_field}, align 1"));
        }
        let payload = self.temp();
        self.instruction(format!(
            "{payload} = load {}, ptr {result_storage}, align 1",
            self.lltype(*target)
        ));
        let success_value = self.emit_construct_values(expr.ty, 0, vec![(*target, payload)]);
        let success_pred = self.current_label.clone();
        let success_stack_top = self.stack_top.clone();
        self.terminate(format!("br label %{merge_label}"));

        self.stack_top = incoming_stack_top.clone();
        self.start_block(&error_label);
        let error_ty = match self.program.types[expr.ty.0].kind {
            TTypeKind::Result(_, error) => error,
            _ => unreachable!("checked string conversion returns Result"),
        };
        let error_name = if *conversion == StringConversion::BytesToText {
            "InvalidUtf8"
        } else {
            "NonAscii"
        };
        let error_index = self.program.types[error_ty.0]
            .cases()
            .iter()
            .position(|case| case.name == error_name)
            .expect("TextError contains conversion errors");
        let error_value = self.emit_construct_values(error_ty, error_index, Vec::new());
        let failure_value = self.emit_construct_values(expr.ty, 1, vec![(error_ty, error_value)]);
        let failure_pred = self.current_label.clone();
        let failure_stack_top = self.stack_top.clone();
        self.terminate(format!("br label %{merge_label}"));

        self.start_block(&merge_label);
        let merged_stack_top = self.temp();
        self.instruction(format!(
            "{merged_stack_top} = phi ptr [ {success_stack_top}, %{success_pred} ], [ {failure_stack_top}, %{failure_pred} ]"
        ));
        self.stack_top = merged_stack_top;
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi {} [ {success_value}, %{success_pred} ], [ {failure_value}, %{failure_pred} ]",
            self.lltype(expr.ty)
        ));
        self.instruction(format!(
            "store {} {result}, ptr {destination}, align 1",
            self.lltype(expr.ty)
        ));
    }

    fn emit_ascii_fit_to(&mut self, destination: &str, expr: &TExpr, value: &TExpr, option_ty: Ty) {
        let descriptor = self.emit_ascii_descriptor(value);
        if self.terminated {
            return;
        }
        let source = self.ascii_field(&descriptor, value.ty, 0);
        let length = self.ascii_field(&descriptor, value.ty, 1);
        let payload_ty = match self.program.types[option_ty.0].kind {
            TTypeKind::Option(inner) => inner,
            _ => unreachable!("Ascii fit constructs an Option"),
        };
        let limit = self.ascii_max(payload_ty).unwrap_or(0);
        let fits = self.temp();
        self.instruction(format!("{fits} = icmp ule i64 {length}, {limit}"));
        let some_label = self.new_label("ascii.fit.some");
        let none_label = self.new_label("ascii.fit.none");
        let merge = self.new_label("ascii.fit.end");
        self.terminate(format!(
            "br i1 {fits}, label %{some_label}, label %{none_label}"
        ));
        self.start_block(&some_label);
        let some_tag = self.temp();
        self.instruction(format!(
            "{some_tag} = getelementptr {}, ptr {destination}, i32 0, i32 0",
            self.lltype(option_ty)
        ));
        self.instruction(format!("store i32 0, ptr {some_tag}, align 4"));
        let payload = self.temp();
        self.instruction(format!(
            "{payload} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(option_ty)
        ));
        let result_data = self.temp();
        self.instruction(format!(
            "{result_data} = getelementptr i8, ptr {destination}, i64 {}",
            type_size(
                option_ty,
                &self.program.types,
                &mut vec![None; self.program.types.len()]
            )
        ));
        let data_field = self.temp();
        self.instruction(format!(
            "{data_field} = getelementptr i8, ptr {payload}, i64 0"
        ));
        self.instruction(format!(
            "store ptr {result_data}, ptr {data_field}, align 1"
        ));
        let len_field = self.temp();
        self.instruction(format!(
            "{len_field} = getelementptr i8, ptr {payload}, i64 8"
        ));
        self.instruction(format!("store i64 {length}, ptr {len_field}, align 1"));
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {result_data}, ptr {source}, i64 {length}, i1 false)"
        ));
        self.terminate(format!("br label %{merge}"));
        self.start_block(&none_label);
        let none_tag = self.temp();
        self.instruction(format!(
            "{none_tag} = getelementptr {}, ptr {destination}, i32 0, i32 0",
            self.lltype(option_ty)
        ));
        self.instruction(format!("store i32 1, ptr {none_tag}, align 4"));
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let _ = expr;
    }

    fn emit_ascii_append_place(&mut self, place: &TPlace, value: &TExpr) {
        if expression_uses_local_root(value, place.root) {
            let saved_top = self.stack_top.clone();
            let temporary = self.emit_runtime_region_alloc(value.ty, value.span, None);
            self.emit_expr_to(&temporary, value);
            if self.terminated {
                return;
            }
            let descriptor = self.temp();
            self.instruction(format!(
                "{descriptor} = load {}, ptr {temporary}, align 1",
                self.lltype(value.ty)
            ));
            let source = self.ascii_field(&descriptor, value.ty, 0);
            let amount = self.ascii_field(&descriptor, value.ty, 1);
            let destination = self.emit_place_pointer(place);
            let builder = self.temp();
            self.instruction(format!(
                "{builder} = load {}, ptr {destination}, align 1",
                self.lltype(place.ty)
            ));
            let target = self.ascii_field(&builder, place.ty, 0);
            let old_length = self.ascii_field(&builder, place.ty, 1);
            let append_at = self.temp();
            self.instruction(format!(
                "{append_at} = getelementptr i8, ptr {target}, i64 {old_length}"
            ));
            self.instruction(format!(
                "call void @llvm.memmove.p0.p0.i64(ptr {append_at}, ptr {source}, i64 {amount}, i1 false)"
            ));
            let new_length = self.temp();
            self.instruction(format!("{new_length} = add i64 {old_length}, {amount}"));
            let length_field = self.temp();
            self.instruction(format!(
                "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
                self.lltype(place.ty)
            ));
            self.instruction(format!(
                "store i64 {new_length}, ptr {length_field}, align 1"
            ));
            self.restore_stack_top(&saved_top);
            return;
        }
        let destination = self.emit_place_pointer(place);
        let descriptor = self.temp();
        self.instruction(format!(
            "{descriptor} = load {}, ptr {destination}, align 1",
            self.lltype(place.ty)
        ));
        let data = self.ascii_field(&descriptor, place.ty, 0);
        let length = self.ascii_field(&descriptor, place.ty, 1);
        let offset = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 {length}, ptr {offset}, align 1"));
        self.emit_ascii_stream(value, &data, &offset);
        if self.terminated {
            return;
        }
        let new_length = self.temp();
        self.instruction(format!("{new_length} = load i64, ptr {offset}, align 1"));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(place.ty)
        ));
        self.instruction(format!(
            "store i64 {new_length}, ptr {length_field}, align 1"
        ));
    }

    fn emit_ascii_assign_place(&mut self, place: &TPlace, value: &TExpr) {
        let saved_top = self.stack_top.clone();
        let temporary = self.emit_runtime_region_alloc(value.ty, value.span, None);
        self.emit_expr_to(&temporary, value);
        if self.terminated {
            return;
        }
        let source_desc = self.temp();
        self.instruction(format!(
            "{source_desc} = load {}, ptr {temporary}, align 1",
            self.lltype(value.ty)
        ));
        let source_data = self.ascii_field(&source_desc, value.ty, 0);
        let source_length = self.ascii_field(&source_desc, value.ty, 1);
        let destination = self.emit_place_pointer(place);
        let destination_desc = self.temp();
        self.instruction(format!(
            "{destination_desc} = load {}, ptr {destination}, align 1",
            self.lltype(place.ty)
        ));
        let destination_data = self.ascii_field(&destination_desc, place.ty, 0);
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {destination_data}, ptr {source_data}, i64 {source_length}, i1 false)"
        ));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(place.ty)
        ));
        self.instruction(format!(
            "store i64 {source_length}, ptr {length_field}, align 1"
        ));
        self.restore_stack_top(&saved_top);
    }

    fn emit_ascii_try_append(
        &mut self,
        expr: &TExpr,
        receiver: &TExpr,
        argument: &TExpr,
    ) -> String {
        let place = Self::expr_place(receiver).expect("checker validated Ascii builder place");
        let destination = self.emit_place_pointer(&place);
        let saved_top = self.stack_top.clone();
        let builder_descriptor = self.temp();
        self.instruction(format!(
            "{builder_descriptor} = load {}, ptr {destination}, align 1",
            self.lltype(receiver.ty)
        ));
        let target = self.ascii_field(&builder_descriptor, receiver.ty, 0);
        let old_length = self.ascii_field(&builder_descriptor, receiver.ty, 1);
        let builder_max = self.ascii_max(receiver.ty).unwrap_or(0);
        let argument_max = self.ascii_max(argument.ty).unwrap_or(0);
        let remaining = self.temp();
        self.instruction(format!("{remaining} = sub i64 {builder_max}, {old_length}"));
        let max_fits = self.temp();
        if argument_max <= builder_max {
            self.instruction(format!(
                "{max_fits} = icmp uge i64 {remaining}, {argument_max}"
            ));
        } else {
            self.instruction(format!("{max_fits} = icmp eq i64 0, 1"));
        }
        let fast_label = self.new_label("ascii.append.stream");
        let scratch_label = self.new_label("ascii.append.scratch");
        let merge = self.new_label("ascii.append.end");
        self.terminate(format!(
            "br i1 {max_fits}, label %{fast_label}, label %{scratch_label}"
        ));
        self.start_block(&fast_label);
        let append_offset = self.entry_alloca(Ty::Long);
        self.instruction(format!(
            "store i64 {old_length}, ptr {append_offset}, align 1"
        ));
        self.emit_ascii_stream(argument, &target, &append_offset);
        if self.terminated {
            return String::new();
        }
        let new_length = self.temp();
        self.instruction(format!(
            "{new_length} = load i64, ptr {append_offset}, align 1"
        ));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(receiver.ty)
        ));
        self.instruction(format!(
            "store i64 {new_length}, ptr {length_field}, align 1"
        ));
        let fast_result = self.emit_construct_values(expr.ty, 0, Vec::new());
        let fast_end = self.current_label.clone();
        self.instruction(format!(
            "call void @nl_context_set_top(ptr %nl.ctx, ptr {saved_top})"
        ));
        self.terminate(format!("br label %{merge}"));
        self.stack_top = saved_top.clone();
        self.start_block(&scratch_label);
        let scratch_result =
            self.emit_ascii_try_append_scratch(expr, receiver, argument, &destination, &saved_top);
        let scratch_end = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        self.stack_top = saved_top;
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi {} [ {fast_result}, %{fast_end} ], [ {scratch_result}, %{scratch_end} ]",
            self.lltype(expr.ty)
        ));
        result
    }

    fn emit_ascii_try_append_scratch(
        &mut self,
        expr: &TExpr,
        receiver: &TExpr,
        argument: &TExpr,
        destination: &str,
        saved_top: &str,
    ) -> String {
        let argument_storage = self.emit_runtime_region_alloc(argument.ty, argument.span, None);
        let scratch_data = self.temp();
        self.instruction(format!(
            "{scratch_data} = getelementptr i8, ptr {argument_storage}, i64 16"
        ));
        let argument_data_field = self.temp();
        self.instruction(format!(
            "{argument_data_field} = getelementptr {}, ptr {argument_storage}, i32 0, i32 0",
            self.lltype(argument.ty)
        ));
        self.instruction(format!(
            "store ptr {scratch_data}, ptr {argument_data_field}, align 1"
        ));
        let argument_length_field = self.temp();
        self.instruction(format!(
            "{argument_length_field} = getelementptr {}, ptr {argument_storage}, i32 0, i32 1",
            self.lltype(argument.ty)
        ));
        self.instruction(format!("store i64 0, ptr {argument_length_field}, align 1"));
        let scratch_offset = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {scratch_offset}, align 1"));
        self.emit_ascii_stream(argument, &scratch_data, &scratch_offset);
        if self.terminated {
            return String::new();
        }
        let scratch_length = self.temp();
        self.instruction(format!(
            "{scratch_length} = load i64, ptr {scratch_offset}, align 1"
        ));
        self.instruction(format!(
            "store i64 {scratch_length}, ptr {argument_length_field}, align 1"
        ));
        let argument_descriptor = self.temp();
        self.instruction(format!(
            "{argument_descriptor} = load {}, ptr {argument_storage}, align 1",
            self.lltype(argument.ty)
        ));
        let source = self.ascii_field(&argument_descriptor, argument.ty, 0);
        let amount = self.ascii_field(&argument_descriptor, argument.ty, 1);
        let builder_descriptor = self.temp();
        self.instruction(format!(
            "{builder_descriptor} = load {}, ptr {destination}, align 1",
            self.lltype(receiver.ty)
        ));
        let target = self.ascii_field(&builder_descriptor, receiver.ty, 0);
        let old_length = self.ascii_field(&builder_descriptor, receiver.ty, 1);
        let new_length = self.temp();
        self.instruction(format!("{new_length} = add i64 {old_length}, {amount}"));
        let fits = self.temp();
        self.instruction(format!(
            "{fits} = icmp ule i64 {new_length}, {}",
            self.ascii_max(receiver.ty).unwrap_or(0)
        ));
        let success_label = self.new_label("ascii.append.ok");
        let full_label = self.new_label("ascii.append.full");
        let merge = self.new_label("ascii.append.end");
        self.terminate(format!(
            "br i1 {fits}, label %{success_label}, label %{full_label}"
        ));
        self.start_block(&success_label);
        let append_at = self.temp();
        self.instruction(format!(
            "{append_at} = getelementptr i8, ptr {target}, i64 {old_length}"
        ));
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {append_at}, ptr {source}, i64 {amount}, i1 false)"
        ));
        let length_field = self.temp();
        self.instruction(format!(
            "{length_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(receiver.ty)
        ));
        self.instruction(format!(
            "store i64 {new_length}, ptr {length_field}, align 1"
        ));
        let ok = self.emit_construct_values(expr.ty, 0, Vec::new());
        let ok_block = self.current_label.clone();
        self.instruction(format!(
            "call void @nl_context_set_top(ptr %nl.ctx, ptr {saved_top})"
        ));
        self.terminate(format!("br label %{merge}"));
        self.start_block(&full_label);
        let full = self.emit_construct_values(expr.ty, 1, Vec::new());
        let full_block = self.current_label.clone();
        self.instruction(format!(
            "call void @nl_context_set_top(ptr %nl.ctx, ptr {saved_top})"
        ));
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        self.stack_top = saved_top.to_owned();
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi {} [ {ok}, %{ok_block} ], [ {full}, %{full_block} ]",
            self.lltype(expr.ty)
        ));
        result
    }

    fn is_pool_type(&self, ty: Ty) -> bool {
        matches!(self.program.types[ty.0].kind, TTypeKind::Pool { .. })
    }

    fn emit_pointer_overlap_any(
        &mut self,
        destination: &str,
        destination_ty: Ty,
        sources: &[(String, Ty)],
    ) -> String {
        let destination_size = stack_storage_size(destination_ty, &self.program.types);
        let destination_start = self.temp();
        self.instruction(format!(
            "{destination_start} = ptrtoint ptr {destination} to i64"
        ));
        let destination_end = self.temp();
        self.instruction(format!(
            "{destination_end} = add i64 {destination_start}, {destination_size}"
        ));
        let mut overlaps = "false".to_owned();
        for (source, source_ty) in sources {
            let source_size = stack_storage_size(*source_ty, &self.program.types);
            if source_size == 0 || destination_size == 0 {
                continue;
            }
            let source_start = self.temp();
            self.instruction(format!("{source_start} = ptrtoint ptr {source} to i64"));
            let source_end = self.temp();
            self.instruction(format!(
                "{source_end} = add i64 {source_start}, {source_size}"
            ));
            let destination_before_source_end = self.temp();
            self.instruction(format!(
                "{destination_before_source_end} = icmp ult i64 {destination_start}, {source_end}"
            ));
            let source_before_destination_end = self.temp();
            self.instruction(format!(
                "{source_before_destination_end} = icmp ult i64 {source_start}, {destination_end}"
            ));
            let current_overlap = self.temp();
            self.instruction(format!(
                "{current_overlap} = and i1 {destination_before_source_end}, {source_before_destination_end}"
            ));
            let combined = self.temp();
            self.instruction(format!("{combined} = or i1 {overlaps}, {current_overlap}"));
            overlaps = combined;
        }
        overlaps
    }

    fn emit_direct_call(
        &mut self,
        function_id: usize,
        args: &[TExpr],
        result_destination: Option<&str>,
        call_span: Span,
    ) -> String {
        let function = self.program.functions[function_id].clone();
        let signature = lower_signature(&function, &self.program.types);
        let saved_top = self.stack_top.clone();
        let mut call_args = vec!["ptr %nl.ctx".to_owned()];
        let mut result_storage = None;
        if signature.result_destination {
            let destination = result_destination
                .map(str::to_owned)
                .unwrap_or_else(|| self.entry_alloca(function.result));
            call_args.push(format!("ptr {destination}"));
            result_storage = Some(destination);
        }
        let mut regions = Vec::new();
        let mut pointer_args = Vec::new();
        for (arg, param) in args.iter().zip(&function.params) {
            let Some(value) = self.emit_call_argument(arg, param.ty, param.mode, &mut regions)
            else {
                return String::new();
            };
            if value.starts_with("ptr ") {
                pointer_args.push((value[4..].to_owned(), param.ty));
            }
            call_args.push(value);
        }
        if self.program.functions[function_id].recursive {
            self.emit_recursion_check(&[function_id], call_span);
        }
        if signature.result_destination && result_destination.is_some() && !pointer_args.is_empty()
        {
            let destination = result_storage.as_deref().unwrap();
            let argument_top = self.stack_top.clone();
            let overlaps =
                self.emit_pointer_overlap_any(destination, function.result, &pointer_args);
            let direct_label = self.new_label("call.result.direct");
            let scratch_label = self.new_label("call.result.scratch");
            let merge_label = self.new_label("call.result.end");
            self.terminate(format!(
                "br i1 {overlaps}, label %{scratch_label}, label %{direct_label}"
            ));

            self.start_block(&direct_label);
            let mut direct_args = call_args.clone();
            direct_args.insert(1, format!("ptr {}", self.stack_top));
            let direct_call = direct_args.join(", ");
            self.instruction(format!("call void @nl_fn_{function_id}({direct_call})"));
            self.finish_call_argument_regions(&regions, &saved_top);
            self.terminate(format!("br label %{merge_label}"));

            self.stack_top = argument_top.clone();
            self.start_block(&scratch_label);
            let scratch = self.emit_runtime_region_alloc(function.result, call_span, None);
            let mut scratch_args = call_args;
            scratch_args[1] = format!("ptr {scratch}");
            scratch_args.insert(1, format!("ptr {}", self.stack_top));
            let scratch_call = scratch_args.join(", ");
            self.instruction(format!("call void @nl_fn_{function_id}({scratch_call})"));
            for region in regions.iter().filter(|region| region.copy_back) {
                self.emit_scatter_collection_element(
                    region.collection_ty,
                    &region.collection_ptr,
                    &region.index,
                    &region.temporary,
                );
            }
            self.restore_stack_top(&argument_top);
            self.emit_copy_value_storage(destination, &scratch, function.result);
            self.restore_stack_top(&saved_top);
            self.terminate(format!("br label %{merge_label}"));

            self.stack_top = saved_top;
            self.start_block(&merge_label);
            return String::new();
        }
        call_args.insert(1, format!("ptr {}", self.stack_top));
        let lowered = call_args.join(", ");
        if signature.result == "void" {
            self.instruction(format!("call void @nl_fn_{function_id}({lowered})"));
            self.finish_call_argument_regions(&regions, &saved_top);
            if signature.result_destination && result_destination.is_none() {
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {}, align 1",
                    self.lltype(function.result),
                    result_storage.unwrap()
                ));
                value
            } else {
                String::new()
            }
        } else {
            let value = self.temp();
            self.instruction(format!(
                "{value} = call {} @nl_fn_{function_id}({lowered})",
                signature.result
            ));
            self.finish_call_argument_regions(&regions, &saved_top);
            value
        }
    }

    fn emit_indirect_call(
        &mut self,
        callee: &TExpr,
        args: &[TExpr],
        params: &[TFunctionTypeParam],
        result_ty: Ty,
        result_destination: Option<&str>,
        call_span: Span,
    ) -> String {
        let function_value = self.emit_expr(callee);
        if self.terminated {
            return String::new();
        }
        let saved_top = self.stack_top.clone();
        let large_result = is_large_type(result_ty, &self.program.types);
        let mut call_args = vec!["ptr %nl.ctx".to_owned()];
        let result_storage = if large_result {
            let pointer = result_destination
                .map(str::to_owned)
                .unwrap_or_else(|| self.entry_alloca(result_ty));
            call_args.push(format!("ptr {pointer}"));
            Some(pointer)
        } else {
            None
        };
        let mut regions = Vec::new();
        let mut pointer_args = Vec::new();
        for (arg, param) in args.iter().zip(params) {
            let Some(value) = self.emit_call_argument(arg, param.ty, param.mode, &mut regions)
            else {
                return String::new();
            };
            if value.starts_with("ptr ") {
                pointer_args.push((value[4..].to_owned(), param.ty));
            }
            call_args.push(value);
        }
        let targets = self
            .program
            .call_graph
            .get(self.function.id)
            .into_iter()
            .flatten()
            .filter(|edge| {
                edge.span.file == call_span.file
                    && edge.span.line == call_span.line
                    && edge.span.col == call_span.col
                    && self.program.functions[edge.target].recursive
            })
            .map(|edge| edge.target)
            .collect::<Vec<_>>();
        self.emit_recursion_check(&targets, call_span);
        if large_result && result_destination.is_some() && !pointer_args.is_empty() {
            let destination = result_storage.as_deref().unwrap();
            let argument_top = self.stack_top.clone();
            let overlaps = self.emit_pointer_overlap_any(destination, result_ty, &pointer_args);
            let direct_label = self.new_label("indirect.result.direct");
            let scratch_label = self.new_label("indirect.result.scratch");
            let merge_label = self.new_label("indirect.result.end");
            self.terminate(format!(
                "br i1 {overlaps}, label %{scratch_label}, label %{direct_label}"
            ));

            self.start_block(&direct_label);
            let mut direct_args = call_args.clone();
            direct_args.insert(1, format!("ptr {}", self.stack_top));
            let direct_call = direct_args.join(", ");
            self.instruction(format!("call void {function_value}({direct_call})"));
            self.finish_call_argument_regions(&regions, &saved_top);
            self.terminate(format!("br label %{merge_label}"));

            self.stack_top = argument_top.clone();
            self.start_block(&scratch_label);
            let scratch = self.emit_runtime_region_alloc(result_ty, call_span, None);
            let mut scratch_args = call_args;
            scratch_args[1] = format!("ptr {scratch}");
            scratch_args.insert(1, format!("ptr {}", self.stack_top));
            let scratch_call = scratch_args.join(", ");
            self.instruction(format!("call void {function_value}({scratch_call})"));
            for region in regions.iter().filter(|region| region.copy_back) {
                self.emit_scatter_collection_element(
                    region.collection_ty,
                    &region.collection_ptr,
                    &region.index,
                    &region.temporary,
                );
            }
            self.restore_stack_top(&argument_top);
            self.emit_copy_value_storage(destination, &scratch, result_ty);
            self.restore_stack_top(&saved_top);
            self.terminate(format!("br label %{merge_label}"));

            self.stack_top = saved_top;
            self.start_block(&merge_label);
            return String::new();
        }
        call_args.insert(1, format!("ptr {}", self.stack_top));
        let lowered = call_args.join(", ");
        if large_result {
            self.instruction(format!("call void {function_value}({lowered})"));
            self.finish_call_argument_regions(&regions, &saved_top);
            if result_destination.is_none() {
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {}, align 1",
                    self.lltype(result_ty),
                    result_storage.unwrap()
                ));
                value
            } else {
                String::new()
            }
        } else if result_ty == Ty::Unit {
            self.instruction(format!("call void {function_value}({lowered})"));
            self.finish_call_argument_regions(&regions, &saved_top);
            String::new()
        } else {
            let value = self.temp();
            self.instruction(format!(
                "{value} = call {} {function_value}({lowered})",
                self.lltype(result_ty)
            ));
            self.finish_call_argument_regions(&regions, &saved_top);
            value
        }
    }

    fn emit_recursion_check(&mut self, targets: &[usize], span: Span) {
        if !targets.is_empty() {
            self.lines.push(
                recursion_check_instruction(targets, span)
                    .trim_end()
                    .to_owned(),
            );
        }
    }

    fn emit_copy_growing_value(&mut self, destination: &str, source: &str, ty: Ty) {
        let bytes = type_size(
            ty,
            &self.program.types,
            &mut vec![None; self.program.types.len()],
        );
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {destination}, ptr {source}, i64 {bytes}, i1 false)"
        ));
        self.emit_rebase_growing_payload(destination, source, ty, destination, ty, 0);
    }

    fn emit_copy_value_storage(&mut self, destination: &str, source: &str, ty: Ty) {
        if destination == source {
            return;
        }
        if contains_lazy_collection(
            ty,
            &self.program.types,
            &mut vec![false; self.program.types.len()],
        ) {
            self.emit_copy_lazy_storage(destination, source, ty);
            return;
        }
        if self.ascii_max(ty).is_some() {
            let source_data_field = self.temp();
            self.instruction(format!(
                "{source_data_field} = getelementptr {}, ptr {source}, i32 0, i32 0",
                self.lltype(ty)
            ));
            let source_data = self.temp();
            self.instruction(format!(
                "{source_data} = load ptr, ptr {source_data_field}, align 1"
            ));
            let source_len_field = self.temp();
            self.instruction(format!(
                "{source_len_field} = getelementptr {}, ptr {source}, i32 0, i32 1",
                self.lltype(ty)
            ));
            let source_len = self.temp();
            self.instruction(format!(
                "{source_len} = load i64, ptr {source_len_field}, align 1"
            ));
            let text_value = self.is_text_type(ty);
            let destination_data = self.temp();
            self.instruction(format!(
                "{destination_data} = getelementptr i8, ptr {destination}, i64 {}",
                if text_value { 24 } else { 16 }
            ));
            let destination_data_field = self.temp();
            self.instruction(format!(
                "{destination_data_field} = getelementptr {}, ptr {destination}, i32 0, i32 0",
                self.lltype(ty)
            ));
            self.instruction(format!(
                "store ptr {destination_data}, ptr {destination_data_field}, align 1"
            ));
            self.instruction(format!(
                "call void @llvm.memmove.p0.p0.i64(ptr {destination_data}, ptr {source_data}, i64 {source_len}, i1 false)"
            ));
            let destination_len_field = self.temp();
            self.instruction(format!(
                "{destination_len_field} = getelementptr {}, ptr {destination}, i32 0, i32 1",
                self.lltype(ty)
            ));
            self.instruction(format!(
                "store i64 {source_len}, ptr {destination_len_field}, align 1"
            ));
            if text_value {
                let source_chars_field = self.temp();
                self.instruction(format!(
                    "{source_chars_field} = getelementptr {}, ptr {source}, i32 0, i32 2",
                    self.lltype(ty)
                ));
                let source_chars = self.temp();
                self.instruction(format!(
                    "{source_chars} = load i64, ptr {source_chars_field}, align 1"
                ));
                let destination_chars_field = self.temp();
                self.instruction(format!(
                    "{destination_chars_field} = getelementptr {}, ptr {destination}, i32 0, i32 2",
                    self.lltype(ty)
                ));
                self.instruction(format!(
                    "store i64 {source_chars}, ptr {destination_chars_field}, align 1"
                ));
            }
            return;
        }
        if contains_growing_value(
            ty,
            &self.program.types,
            &mut vec![false; self.program.types.len()],
        ) {
            self.emit_copy_growing_value(destination, source, ty);
            return;
        }
        let bytes = type_size(
            ty,
            &self.program.types,
            &mut vec![None; self.program.types.len()],
        );
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {destination}, ptr {source}, i64 {bytes}, i1 false)"
        ));
    }

    fn emit_empty_storage(&mut self, destination: &str, ty: Ty) {
        if collection_capacity(ty, &self.program.types).is_some() {
            self.emit_empty_var_pools(ty, destination);
        }
        match self.program.types[ty.0].kind.clone() {
            TTypeKind::Refinement { base, .. } => self.emit_empty_storage(destination, base),
            TTypeKind::Struct(fields) => {
                for (index, field) in fields.iter().enumerate() {
                    if field.ty == Ty::Unit {
                        continue;
                    }
                    let field_ptr = self.temp();
                    self.instruction(format!(
                        "{field_ptr} = getelementptr inbounds {}, ptr {destination}, i32 0, i32 {index}",
                        self.lltype(ty)
                    ));
                    self.emit_empty_storage(&field_ptr, field.ty);
                }
            }
            TTypeKind::Array { capacity, .. } | TTypeKind::Grid { capacity, .. } => {
                self.emit_empty_fixed_collection(destination, ty, capacity);
            }
            TTypeKind::List { .. } => {
                let count = self.emit_collection_count_ptr(ty, destination);
                self.instruction(format!("store i64 0, ptr {count}, align 1"));
            }
            TTypeKind::Queue { .. } | TTypeKind::Ring { .. } => {
                let head = self.emit_queue_ring_meta_ptr(ty, destination, 0);
                let length = self.emit_queue_ring_meta_ptr(ty, destination, 1);
                self.instruction(format!("store i64 0, ptr {head}, align 1"));
                self.instruction(format!("store i64 0, ptr {length}, align 1"));
            }
            TTypeKind::Map { capacity, .. } | TTypeKind::Set { capacity, .. } => {
                self.emit_empty_map_storage(destination, ty, capacity);
            }
            TTypeKind::Pool { .. } => {
                let active = self.emit_pool_meta_ptr(ty, destination, 0);
                let free_count = self.emit_pool_meta_ptr(ty, destination, 1);
                let high_water = self.emit_pool_meta_ptr(ty, destination, 5);
                self.instruction(format!("store i64 0, ptr {active}, align 1"));
                self.instruction(format!("store i64 0, ptr {free_count}, align 1"));
                self.instruction(format!("store i64 0, ptr {high_water}, align 1"));
            }
            TTypeKind::Option(_) => self.emit_sum_empty_case_to(ty, destination, 1),
            TTypeKind::Result(..) | TTypeKind::Enum(_) => {
                self.emit_sum_empty_case_to(ty, destination, 0)
            }
            TTypeKind::Unit | TTypeKind::Never => {}
            TTypeKind::Int
            | TTypeKind::Long
            | TTypeKind::Bool
            | TTypeKind::Ascii { .. }
            | TTypeKind::Text { .. }
            | TTypeKind::Bytes { .. }
            | TTypeKind::Id { .. }
            | TTypeKind::Function { .. }
            | TTypeKind::Capability(_) => {
                self.instruction(format!(
                    "store {} zeroinitializer, ptr {destination}, align 1",
                    self.lltype(ty)
                ));
            }
        }
    }

    fn emit_collection_count_ptr(&mut self, collection_ty: Ty, pointer: &str) -> String {
        let ptr = self.temp();
        self.instruction(format!(
            "{ptr} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 0",
            self.lltype(collection_ty)
        ));
        ptr
    }

    fn emit_empty_map_storage(&mut self, destination: &str, map_ty: Ty, capacity: usize) {
        let count = self.emit_map_meta_ptr(map_ty, destination, 0);
        let end = self.emit_map_meta_ptr(map_ty, destination, 1);
        self.instruction(format!("store i64 0, ptr {count}, align 1"));
        self.instruction(format!("store i64 0, ptr {end}, align 1"));
        for (field, element_ty, element_size) in [(2usize, Ty::Bool, 1usize), (4, Ty::Long, 8)] {
            if capacity == 0 {
                continue;
            }
            let array = self.emit_map_meta_ptr(map_ty, destination, field);
            self.instruction(format!(
                "call void @llvm.memset.p0.i64(ptr {array}, i8 0, i64 {}, i1 false)",
                capacity.saturating_mul(element_size)
            ));
            let _ = element_ty;
        }
    }

    fn emit_empty_fixed_collection(
        &mut self,
        destination: &str,
        collection_ty: Ty,
        capacity: usize,
    ) {
        if capacity == 0 {
            return;
        }
        let element = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { element, .. } | TTypeKind::Grid { element, .. } => element,
            _ => unreachable!(),
        };
        let index_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {index_ptr}, align 1"));
        let condition = self.new_label("empty.fixed.cond");
        let body = self.new_label("empty.fixed.body");
        let done = self.new_label("empty.fixed.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {index_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {capacity}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
        self.start_block(&body);
        self.emit_init_collection_element(collection_ty, destination, &index);
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {index}, 1"));
        self.instruction(format!("store i64 {next}, ptr {index_ptr}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
        let _ = element;
    }

    fn emit_init_collection_element(&mut self, collection_ty: Ty, pointer: &str, index: &str) {
        self.emit_init_var_collection_element(collection_ty, pointer, index);
        let element = collection_element_type(collection_ty, &self.program.types);
        if let TTypeKind::Struct(fields) = self.program.types[element.0].kind.clone() {
            for (lane, field) in fields.iter().enumerate() {
                if collection_var_lane(collection_ty, &self.program.types, lane).is_some() {
                    continue;
                }
                let destination =
                    self.emit_collection_lane_pointer(collection_ty, pointer, index, lane);
                self.emit_empty_storage(&destination, field.ty);
            }
        } else {
            if collection_var_lane(collection_ty, &self.program.types, 0).is_some() {
                return;
            }
            let destination = self.emit_collection_lane_pointer(collection_ty, pointer, index, 0);
            self.emit_empty_storage(&destination, element);
        }
    }

    fn emit_copy_struct_storage_rooted(
        &mut self,
        destination: &str,
        source: &str,
        ty: Ty,
        root_destination: &str,
        root_ty: Ty,
        extra_offset: usize,
    ) {
        let TTypeKind::Struct(fields) = self.program.types[ty.0].kind.clone() else {
            unreachable!("rooted struct copy requires a struct")
        };
        let mut offset = extra_offset;
        for (index, field) in fields.iter().enumerate() {
            if field.ty == Ty::Unit {
                continue;
            }
            let destination_field = self.temp();
            let source_field = self.temp();
            self.instruction(format!(
                "{destination_field} = getelementptr inbounds {}, ptr {destination}, i32 0, i32 {index}",
                self.lltype(ty)
            ));
            self.instruction(format!(
                "{source_field} = getelementptr inbounds {}, ptr {source}, i32 0, i32 {index}",
                self.lltype(ty)
            ));
            match self.program.types[field.ty.0].kind.clone() {
                TTypeKind::Struct(_) => self.emit_copy_struct_storage_rooted(
                    &destination_field,
                    &source_field,
                    field.ty,
                    root_destination,
                    root_ty,
                    offset,
                ),
                TTypeKind::Ascii { .. } | TTypeKind::Text { .. } | TTypeKind::Bytes { .. } => {
                    let bytes = type_size(
                        field.ty,
                        &self.program.types,
                        &mut vec![None; self.program.types.len()],
                    );
                    self.instruction(format!(
                        "call void @llvm.memmove.p0.p0.i64(ptr {destination_field}, ptr {source_field}, i64 {bytes}, i1 false)"
                    ));
                    self.emit_rebase_growing_payload(
                        &destination_field,
                        &source_field,
                        field.ty,
                        root_destination,
                        root_ty,
                        offset,
                    );
                }
                _ if contains_lazy_collection(
                    field.ty,
                    &self.program.types,
                    &mut vec![false; self.program.types.len()],
                ) =>
                {
                    self.emit_copy_value_storage(&destination_field, &source_field, field.ty)
                }
                _ if growing_value_extra(
                    field.ty,
                    &self.program.types,
                    &mut vec![false; self.program.types.len()],
                ) > 0 =>
                {
                    let bytes = type_size(
                        field.ty,
                        &self.program.types,
                        &mut vec![None; self.program.types.len()],
                    );
                    self.instruction(format!(
                        "call void @llvm.memmove.p0.p0.i64(ptr {destination_field}, ptr {source_field}, i64 {bytes}, i1 false)"
                    ));
                    self.emit_rebase_growing_payload(
                        &destination_field,
                        &source_field,
                        field.ty,
                        root_destination,
                        root_ty,
                        offset,
                    );
                }
                _ => self.emit_copy_value_storage(&destination_field, &source_field, field.ty),
            }
            offset = offset.saturating_add(growing_value_extra(
                field.ty,
                &self.program.types,
                &mut vec![false; self.program.types.len()],
            ));
        }
    }

    fn emit_copy_value_rooted(
        &mut self,
        destination: &str,
        source: &str,
        ty: Ty,
        root_destination: &str,
        root_ty: Ty,
        extra_offset: usize,
    ) {
        if matches!(self.program.types[ty.0].kind, TTypeKind::Struct(_)) {
            self.emit_copy_struct_storage_rooted(
                destination,
                source,
                ty,
                root_destination,
                root_ty,
                extra_offset,
            );
            return;
        }
        let extra = growing_value_extra(
            ty,
            &self.program.types,
            &mut vec![false; self.program.types.len()],
        );
        if extra == 0
            || contains_lazy_collection(
                ty,
                &self.program.types,
                &mut vec![false; self.program.types.len()],
            )
        {
            self.emit_copy_value_storage(destination, source, ty);
            return;
        }
        let bytes = type_size(
            ty,
            &self.program.types,
            &mut vec![None; self.program.types.len()],
        );
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {destination}, ptr {source}, i64 {bytes}, i1 false)"
        ));
        self.emit_rebase_growing_payload(
            destination,
            source,
            ty,
            root_destination,
            root_ty,
            extra_offset,
        );
    }

    fn emit_copy_lazy_storage(&mut self, destination: &str, source: &str, ty: Ty) {
        if destination == source {
            return;
        }
        let is_collection = collection_capacity(ty, &self.program.types).is_some();
        let collection_done = if is_collection {
            let same = self.temp();
            self.instruction(format!("{same} = icmp eq ptr {destination}, {source}"));
            let copy = self.new_label("copy.lazy.collection");
            let done = self.new_label("copy.lazy.collection.done");
            self.terminate(format!("br i1 {same}, label %{done}, label %{copy}"));
            self.start_block(&copy);
            Some(done)
        } else {
            None
        };
        if is_collection {
            self.emit_empty_var_pools(ty, destination);
        }
        match self.program.types[ty.0].kind.clone() {
            TTypeKind::Refinement { base, .. } => {
                self.emit_copy_value_storage(destination, source, base);
            }
            TTypeKind::Struct(fields) => {
                let _ = fields;
                self.emit_copy_struct_storage_rooted(destination, source, ty, destination, ty, 0);
            }
            TTypeKind::Array { capacity, .. } | TTypeKind::Grid { capacity, .. } => {
                self.emit_copy_fixed_collection(destination, source, ty, capacity);
            }
            TTypeKind::List {
                element,
                capacity: _,
            } => {
                let source_count_ptr = self.emit_collection_count_ptr(ty, source);
                let count = self.temp();
                self.instruction(format!(
                    "{count} = load i64, ptr {source_count_ptr}, align 1"
                ));
                let destination_count_ptr = self.emit_collection_count_ptr(ty, destination);
                self.instruction(format!(
                    "store i64 {count}, ptr {destination_count_ptr}, align 1"
                ));
                self.emit_copy_collection_prefix(destination, source, ty, element, &count);
            }
            TTypeKind::Queue { element, capacity } | TTypeKind::Ring { element, capacity } => {
                let source_head = self.emit_queue_ring_meta_ptr(ty, source, 0);
                let source_len = self.emit_queue_ring_meta_ptr(ty, source, 1);
                let head = self.temp();
                let length = self.temp();
                self.instruction(format!("{head} = load i64, ptr {source_head}, align 1"));
                self.instruction(format!("{length} = load i64, ptr {source_len}, align 1"));
                let destination_head = self.emit_queue_ring_meta_ptr(ty, destination, 0);
                let destination_len = self.emit_queue_ring_meta_ptr(ty, destination, 1);
                self.instruction(format!("store i64 {head}, ptr {destination_head}, align 1"));
                self.instruction(format!(
                    "store i64 {length}, ptr {destination_len}, align 1"
                ));
                self.emit_copy_wrapped_collection(
                    destination,
                    source,
                    ty,
                    element,
                    capacity,
                    &head,
                    &length,
                );
            }
            TTypeKind::Map { capacity, .. } | TTypeKind::Set { capacity, .. } => {
                self.emit_copy_map_storage(destination, source, ty, capacity);
            }
            TTypeKind::Pool { .. } => {
                unreachable!("pool copies are rejected by the checker")
            }
            TTypeKind::Option(_) | TTypeKind::Result(..) | TTypeKind::Enum(_) => {
                self.emit_copy_sum_storage(destination, source, ty);
            }
            _ => {
                let bytes = type_size(
                    ty,
                    &self.program.types,
                    &mut vec![None; self.program.types.len()],
                );
                self.instruction(format!(
                    "call void @llvm.memmove.p0.p0.i64(ptr {destination}, ptr {source}, i64 {bytes}, i1 false)"
                ));
            }
        }
        if let Some(done) = collection_done {
            self.terminate(format!("br label %{done}"));
            self.start_block(&done);
        }
    }

    fn emit_copy_fixed_collection(
        &mut self,
        destination: &str,
        source: &str,
        collection_ty: Ty,
        capacity: usize,
    ) {
        if capacity == 0 {
            return;
        }
        let index_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {index_ptr}, align 1"));
        let condition = self.new_label("copy.fixed.cond");
        let body = self.new_label("copy.fixed.body");
        let done = self.new_label("copy.fixed.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {index_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {capacity}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
        self.start_block(&body);
        self.emit_copy_collection_element(destination, source, collection_ty, &index, &index);
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {index}, 1"));
        self.instruction(format!("store i64 {next}, ptr {index_ptr}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
    }

    fn emit_copy_collection_prefix(
        &mut self,
        destination: &str,
        source: &str,
        collection_ty: Ty,
        _element: Ty,
        count: &str,
    ) {
        let index_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {index_ptr}, align 1"));
        let condition = self.new_label("copy.prefix.cond");
        let body = self.new_label("copy.prefix.body");
        let done = self.new_label("copy.prefix.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {index_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {count}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
        self.start_block(&body);
        self.emit_copy_collection_element(destination, source, collection_ty, &index, &index);
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {index}, 1"));
        self.instruction(format!("store i64 {next}, ptr {index_ptr}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
    }

    fn emit_copy_wrapped_collection(
        &mut self,
        destination: &str,
        source: &str,
        collection_ty: Ty,
        _element: Ty,
        capacity: usize,
        head: &str,
        length: &str,
    ) {
        if capacity == 0 {
            return;
        }
        let index_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {index_ptr}, align 1"));
        let condition = self.new_label("copy.wrapped.cond");
        let body = self.new_label("copy.wrapped.body");
        let done = self.new_label("copy.wrapped.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let logical = self.temp();
        self.instruction(format!("{logical} = load i64, ptr {index_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {logical}, {length}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
        self.start_block(&body);
        let src_sum = self.temp();
        self.instruction(format!("{src_sum} = add i64 {head}, {logical}"));
        let source_index = self.temp();
        self.instruction(format!("{source_index} = urem i64 {src_sum}, {capacity}"));
        let dst_sum = self.temp();
        self.instruction(format!("{dst_sum} = add i64 {head}, {logical}"));
        let destination_index = self.temp();
        self.instruction(format!(
            "{destination_index} = urem i64 {dst_sum}, {capacity}"
        ));
        self.emit_copy_collection_element(
            destination,
            source,
            collection_ty,
            &destination_index,
            &source_index,
        );
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {logical}, 1"));
        self.instruction(format!("store i64 {next}, ptr {index_ptr}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
    }

    fn emit_copy_collection_element(
        &mut self,
        destination: &str,
        source: &str,
        collection_ty: Ty,
        destination_index: &str,
        source_index: &str,
    ) {
        let element = collection_element_type(collection_ty, &self.program.types);
        if destination == source {
            if destination_index == source_index {
                return;
            }
            if !collection_var_lanes(collection_ty, &self.program.types).is_empty() {
                self.instruction("call void @nl_test_var_storage_reset()".to_owned());
            }
            let equal = self.temp();
            self.instruction(format!(
                "{equal} = icmp eq i64 {destination_index}, {source_index}"
            ));
            let same = self.new_label("move.element.same");
            let move_value = self.new_label("move.element.value");
            let moved = self.new_label("move.element.done");
            self.terminate(format!("br i1 {equal}, label %{same}, label %{move_value}"));
            self.start_block(&same);
            self.terminate(format!("br label %{moved}"));
            self.start_block(&move_value);
            let lanes = collection_lane_types(element, &self.program.types);
            for (lane, lane_ty) in lanes.iter().enumerate() {
                let destination_lane = self.emit_collection_lane_pointer(
                    collection_ty,
                    destination,
                    destination_index,
                    lane,
                );
                let source_lane =
                    self.emit_collection_lane_pointer(collection_ty, source, source_index, lane);
                if collection_var_lane(collection_ty, &self.program.types, lane).is_some() {
                    let value = self.temp();
                    self.instruction(format!(
                        "{value} = load {}, ptr {source_lane}, align 1",
                        self.lltype(*lane_ty)
                    ));
                    let source_descriptor = self.emit_collection_lane_pointer(
                        collection_ty,
                        source,
                        source_index,
                        lane,
                    );
                    let source_data_field = self.temp();
                    self.instruction(format!(
                        "{source_data_field} = getelementptr {}, ptr {source_descriptor}, i32 0, i32 0",
                        self.lltype(*lane_ty)
                    ));
                    let source_data = self.temp();
                    self.instruction(format!(
                        "{source_data} = load ptr, ptr {source_data_field}, align 1"
                    ));
                    let source_len_field = self.temp();
                    self.instruction(format!(
                        "{source_len_field} = getelementptr {}, ptr {source_descriptor}, i32 0, i32 1",
                        self.lltype(*lane_ty)
                    ));
                    let source_len = self.temp();
                    self.instruction(format!(
                        "{source_len} = load i64, ptr {source_len_field}, align 1"
                    ));
                    let destination_descriptor = self.emit_collection_lane_pointer(
                        collection_ty,
                        destination,
                        destination_index,
                        lane,
                    );
                    let destination_data_field = self.temp();
                    self.instruction(format!(
                        "{destination_data_field} = getelementptr {}, ptr {destination_descriptor}, i32 0, i32 0",
                        self.lltype(*lane_ty)
                    ));
                    let destination_data = self.temp();
                    self.instruction(format!(
                        "{destination_data} = load ptr, ptr {destination_data_field}, align 1"
                    ));
                    self.emit_free_var_lane_slot(
                        collection_ty,
                        destination,
                        lane,
                        &destination_data,
                    );
                    self.instruction(format!(
                        "store {} {value}, ptr {destination_lane}, align 1",
                        self.lltype(*lane_ty)
                    ));
                    if let Some(inline) =
                        collection_var_lane(collection_ty, &self.program.types, lane).and_then(
                            |layout| layout.classes.into_iter().find(|class| class.bytes <= 64),
                        )
                    {
                        let destination_data = self.emit_collection_var_slot_ptr(
                            collection_ty,
                            destination,
                            &inline,
                            destination_index,
                        );
                        self.instruction(format!("call void @llvm.memmove.p0.p0.i64(ptr {destination_data}, ptr {source_data}, i64 {source_len}, i1 false)"));
                        let destination_data_field = self.temp();
                        self.instruction(format!(
                            "{destination_data_field} = getelementptr {}, ptr {destination_descriptor}, i32 0, i32 0",
                            self.lltype(*lane_ty)
                        ));
                        self.instruction(format!(
                            "store ptr {destination_data}, ptr {destination_data_field}, align 1"
                        ));
                        self.instruction(format!(
                            "store ptr {source_data}, ptr {source_data_field}, align 1"
                        ));
                    } else {
                        self.instruction(format!(
                            "store ptr {source_data}, ptr {destination_data_field}, align 1"
                        ));
                        self.instruction(format!(
                            "store ptr null, ptr {source_data_field}, align 1"
                        ));
                    }
                    let destination_len_field = self.temp();
                    self.instruction(format!(
                        "{destination_len_field} = getelementptr {}, ptr {destination_descriptor}, i32 0, i32 1",
                        self.lltype(*lane_ty)
                    ));
                    self.instruction(format!(
                        "store i64 {source_len}, ptr {destination_len_field}, align 1"
                    ));
                    self.instruction(format!("store i64 0, ptr {source_len_field}, align 1"));
                    if self.is_text_type(*lane_ty) {
                        let source_chars_field = self.temp();
                        self.instruction(format!(
                            "{source_chars_field} = getelementptr {}, ptr {source_descriptor}, i32 0, i32 2",
                            self.lltype(*lane_ty)
                        ));
                        let source_chars = self.temp();
                        self.instruction(format!(
                            "{source_chars} = load i64, ptr {source_chars_field}, align 1"
                        ));
                        let destination_chars_field = self.temp();
                        self.instruction(format!(
                            "{destination_chars_field} = getelementptr {}, ptr {destination_descriptor}, i32 0, i32 2",
                            self.lltype(*lane_ty)
                        ));
                        self.instruction(format!(
                            "store i64 {source_chars}, ptr {destination_chars_field}, align 1"
                        ));
                        self.instruction(format!("store i64 0, ptr {source_chars_field}, align 1"));
                    }
                } else if *lane_ty == Ty::Unit {
                    continue;
                } else {
                    self.emit_copy_value_storage(&destination_lane, &source_lane, *lane_ty);
                    self.emit_empty_storage(&source_lane, *lane_ty);
                }
            }
            self.terminate(format!("br label %{moved}"));
            self.start_block(&moved);
            return;
        }
        let bytes = stack_storage_size(element, &self.program.types);
        let staged = self.entry_alloca_raw(&format!("[{bytes} x i8]"));
        self.emit_gather_collection_element(collection_ty, source, source_index, &staged);
        self.emit_init_var_collection_element(collection_ty, destination, destination_index);
        self.emit_scatter_collection_element(
            collection_ty,
            destination,
            destination_index,
            &staged,
        );
    }

    fn emit_copy_map_value(
        &mut self,
        map_ty: Ty,
        destination: &str,
        source: &str,
        index: &str,
        value_ty: Ty,
    ) {
        let destination_value = self.emit_map_entry_ptr(map_ty, destination, index, true);
        let source_value = self.emit_map_entry_ptr(map_ty, source, index, true);
        if collection_var_lanes(map_ty, &self.program.types).is_empty() {
            self.emit_copy_value_storage(&destination_value, &source_value, value_ty);
        } else {
            self.emit_init_var_collection_element(map_ty, destination, index);
            self.emit_scatter_collection_element(map_ty, destination, index, &source_value);
        }
    }

    fn emit_copy_sum_storage(&mut self, destination: &str, source: &str, ty: Ty) {
        let source_tag_ptr = self.temp();
        self.instruction(format!(
            "{source_tag_ptr} = getelementptr {}, ptr {source}, i32 0, i32 0",
            self.lltype(ty)
        ));
        let tag = self.temp();
        self.instruction(format!("{tag} = load i32, ptr {source_tag_ptr}, align 4"));
        let source_payload = self.temp();
        let destination_payload = self.temp();
        self.instruction(format!(
            "{source_payload} = getelementptr {}, ptr {source}, i32 0, i32 1",
            self.lltype(ty)
        ));
        self.instruction(format!(
            "{destination_payload} = getelementptr {}, ptr {destination}, i32 0, i32 1",
            self.lltype(ty)
        ));
        let cases = self.program.types[ty.0].cases().to_vec();
        let labels = (0..cases.len())
            .map(|_| self.new_label("copy.sum.case"))
            .collect::<Vec<_>>();
        let invalid = self.new_label("copy.sum.invalid");
        let merge = self.new_label("copy.sum.end");
        let switch = labels
            .iter()
            .enumerate()
            .map(|(index, label)| format!("i32 {index}, label %{label}"))
            .collect::<Vec<_>>()
            .join(" ");
        self.terminate(format!("switch i32 {tag}, label %{invalid} [ {switch} ]"));
        self.start_block(&invalid);
        self.terminate("unreachable");
        for (case_index, case) in cases.iter().enumerate() {
            self.start_block(&labels[case_index]);
            let mut offset = 0usize;
            for field_ty in &case.payload {
                if *field_ty != Ty::Unit {
                    let source_field = self.temp();
                    let destination_field = self.temp();
                    self.instruction(format!(
                        "{source_field} = getelementptr i8, ptr {source_payload}, i64 {offset}"
                    ));
                    self.instruction(format!(
                        "{destination_field} = getelementptr i8, ptr {destination_payload}, i64 {offset}"
                    ));
                    self.emit_copy_value_storage(&destination_field, &source_field, *field_ty);
                }
                offset = offset.saturating_add(type_size(
                    *field_ty,
                    &self.program.types,
                    &mut vec![None; self.program.types.len()],
                ));
            }
            let destination_tag_ptr = self.temp();
            self.instruction(format!(
                "{destination_tag_ptr} = getelementptr {}, ptr {destination}, i32 0, i32 0",
                self.lltype(ty)
            ));
            self.instruction(format!(
                "store i32 {case_index}, ptr {destination_tag_ptr}, align 4"
            ));
            self.terminate(format!("br label %{merge}"));
        }
        self.start_block(&merge);
    }

    fn emit_copy_map_storage(&mut self, destination: &str, source: &str, ty: Ty, capacity: usize) {
        let key_ty = match self.program.types[ty.0].kind {
            TTypeKind::Map { key, .. } | TTypeKind::Set { key, .. } => key,
            _ => unreachable!(),
        };
        let same = self.temp();
        self.instruction(format!("{same} = icmp eq ptr {destination}, {source}"));
        let copy = self.new_label("copy.map.storage");
        let done = self.new_label("copy.map.storage.done");
        self.terminate(format!("br i1 {same}, label %{done}, label %{copy}"));
        self.start_block(&copy);
        let source_count_ptr = self.emit_map_meta_ptr(ty, source, 0);
        let source_end_ptr = self.emit_map_meta_ptr(ty, source, 1);
        let count = self.temp();
        let end = self.temp();
        self.instruction(format!(
            "{count} = load i64, ptr {source_count_ptr}, align 1"
        ));
        self.instruction(format!("{end} = load i64, ptr {source_end_ptr}, align 1"));
        let destination_count_ptr = self.emit_map_meta_ptr(ty, destination, 0);
        let destination_end_ptr = self.emit_map_meta_ptr(ty, destination, 1);
        self.instruction(format!(
            "store i64 {count}, ptr {destination_count_ptr}, align 1"
        ));
        self.instruction(format!(
            "store i64 {end}, ptr {destination_end_ptr}, align 1"
        ));
        let source_buckets = self.emit_map_meta_ptr(ty, source, 4);
        let destination_buckets = self.emit_map_meta_ptr(ty, destination, 4);
        self.instruction(format!(
            "call void @llvm.memmove.p0.p0.i64(ptr {destination_buckets}, ptr {source_buckets}, i64 {}, i1 false)",
            capacity.saturating_mul(8)
        ));
        if capacity != 0 {
            let destination_flags = self.emit_map_meta_ptr(ty, destination, 2);
            self.instruction(format!(
                "call void @llvm.memset.p0.i64(ptr {destination_flags}, i8 0, i64 {capacity}, i1 false)"
            ));
        }
        let index_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {index_ptr}, align 1"));
        let condition = self.new_label("copy.map.records.cond");
        let inspect = self.new_label("copy.map.records.inspect");
        let active_label = self.new_label("copy.map.records.active");
        let step = self.new_label("copy.map.records.step");
        let records_done = self.new_label("copy.map.records.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {index_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {end}"));
        self.terminate(format!(
            "br i1 {more}, label %{inspect}, label %{records_done}"
        ));
        self.start_block(&inspect);
        let source_active_ptr = self.emit_map_array_ptr(ty, source, 2, capacity, Ty::Bool, &index);
        let source_active = self.temp();
        self.instruction(format!(
            "{source_active} = load i1, ptr {source_active_ptr}, align 1"
        ));
        self.terminate(format!(
            "br i1 {source_active}, label %{active_label}, label %{step}"
        ));
        self.start_block(&active_label);
        let destination_active_ptr =
            self.emit_map_array_ptr(ty, destination, 2, capacity, Ty::Bool, &index);
        let source_hash = self.emit_map_array_ptr(ty, source, 3, capacity, Ty::Long, &index);
        let destination_hash =
            self.emit_map_array_ptr(ty, destination, 3, capacity, Ty::Long, &index);
        let hash = self.temp();
        self.instruction(format!("{hash} = load i64, ptr {source_hash}, align 1"));
        let source_key = self.emit_map_entry_ptr(ty, source, &index, false);
        if self.ascii_max(key_ty).is_some() {
            let key = self.temp();
            self.instruction(format!(
                "{key} = load {}, ptr {source_key}, align 1",
                self.lltype(key_ty)
            ));
            self.emit_map_store_key(ty, destination, key_ty, &index, &key);
        } else {
            let destination_key = self.emit_map_entry_ptr(ty, destination, &index, false);
            self.emit_copy_value_storage(&destination_key, &source_key, key_ty);
        }
        self.instruction(format!("store i64 {hash}, ptr {destination_hash}, align 1"));
        self.instruction(format!(
            "store i1 true, ptr {destination_active_ptr}, align 1"
        ));
        if let TTypeKind::Map { value, .. } = &self.program.types[ty.0].kind {
            self.emit_copy_map_value(ty, destination, source, &index, *value);
        }
        self.terminate(format!("br label %{step}"));
        self.start_block(&step);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {index_ptr}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {index_ptr}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&records_done);
        self.terminate(format!("br label %{done}"));
        self.start_block(&done);
    }

    fn emit_rebase_growing_payload(
        &mut self,
        destination: &str,
        source: &str,
        ty: Ty,
        root_destination: &str,
        root_ty: Ty,
        extra_offset: usize,
    ) {
        match self.program.types[ty.0].kind.clone() {
            TTypeKind::Ascii { .. } | TTypeKind::Text { .. } | TTypeKind::Bytes { .. } => {
                let source_data_field = self.temp();
                self.instruction(format!(
                    "{source_data_field} = getelementptr {}, ptr {source}, i32 0, i32 0",
                    self.lltype(ty)
                ));
                let source_data = self.temp();
                self.instruction(format!(
                    "{source_data} = load ptr, ptr {source_data_field}, align 1"
                ));
                let source_len_field = self.temp();
                self.instruction(format!(
                    "{source_len_field} = getelementptr {}, ptr {source}, i32 0, i32 1",
                    self.lltype(ty)
                ));
                let source_len = self.temp();
                self.instruction(format!(
                    "{source_len} = load i64, ptr {source_len_field}, align 1"
                ));
                let fixed_bytes = type_size(
                    root_ty,
                    &self.program.types,
                    &mut vec![None; self.program.types.len()],
                );
                let destination_data = self.temp();
                self.instruction(format!(
                    "{destination_data} = getelementptr i8, ptr {root_destination}, i64 {}",
                    fixed_bytes.saturating_add(extra_offset)
                ));
                self.instruction(format!(
                    "call void @llvm.memmove.p0.p0.i64(ptr {destination_data}, ptr {source_data}, i64 {source_len}, i1 false)"
                ));
                let destination_data_field = self.temp();
                self.instruction(format!(
                    "{destination_data_field} = getelementptr {}, ptr {destination}, i32 0, i32 0",
                    self.lltype(ty)
                ));
                self.instruction(format!(
                    "store ptr {destination_data}, ptr {destination_data_field}, align 1"
                ));
            }
            TTypeKind::Struct(fields) => {
                let mut offset = extra_offset;
                for (index, field) in fields.iter().enumerate() {
                    if field.ty == Ty::Unit {
                        continue;
                    }
                    let source_field = self.temp();
                    let destination_field = self.temp();
                    self.instruction(format!(
                        "{source_field} = getelementptr inbounds {}, ptr {source}, i32 0, i32 {index}",
                        self.lltype(ty)
                    ));
                    self.instruction(format!(
                        "{destination_field} = getelementptr inbounds {}, ptr {destination}, i32 0, i32 {index}",
                        self.lltype(ty)
                    ));
                    self.emit_rebase_growing_payload(
                        &destination_field,
                        &source_field,
                        field.ty,
                        root_destination,
                        root_ty,
                        offset,
                    );
                    offset = offset.saturating_add(growing_value_extra(
                        field.ty,
                        &self.program.types,
                        &mut vec![false; self.program.types.len()],
                    ));
                }
            }
            TTypeKind::Option(inner) => {
                let tag_field = self.temp();
                self.instruction(format!(
                    "{tag_field} = getelementptr {}, ptr {source}, i32 0, i32 0",
                    self.lltype(ty)
                ));
                let tag = self.temp();
                self.instruction(format!("{tag} = load i32, ptr {tag_field}, align 4"));
                let is_some = self.temp();
                self.instruction(format!("{is_some} = icmp eq i32 {tag}, 0"));
                let some_label = self.new_label("growing.copy.some");
                let done_label = self.new_label("growing.copy.none");
                let merge_label = self.new_label("growing.copy.option.end");
                self.terminate(format!(
                    "br i1 {is_some}, label %{some_label}, label %{done_label}"
                ));
                self.start_block(&some_label);
                let source_payload = self.temp();
                self.instruction(format!(
                    "{source_payload} = getelementptr {}, ptr {source}, i32 0, i32 1",
                    self.lltype(ty)
                ));
                let destination_payload = self.temp();
                self.instruction(format!(
                    "{destination_payload} = getelementptr {}, ptr {destination}, i32 0, i32 1",
                    self.lltype(ty)
                ));
                self.emit_rebase_growing_payload(
                    &destination_payload,
                    &source_payload,
                    inner,
                    root_destination,
                    root_ty,
                    extra_offset,
                );
                self.terminate(format!("br label %{merge_label}"));
                self.start_block(&done_label);
                self.terminate(format!("br label %{merge_label}"));
                self.start_block(&merge_label);
            }
            TTypeKind::Result(ok, err) => {
                let tag_field = self.temp();
                self.instruction(format!(
                    "{tag_field} = getelementptr {}, ptr {source}, i32 0, i32 0",
                    self.lltype(ty)
                ));
                let tag = self.temp();
                self.instruction(format!("{tag} = load i32, ptr {tag_field}, align 4"));
                let is_ok = self.temp();
                self.instruction(format!("{is_ok} = icmp eq i32 {tag}, 0"));
                let ok_label = self.new_label("growing.copy.ok");
                let err_label = self.new_label("growing.copy.err");
                let merge_label = self.new_label("growing.copy.result.end");
                self.terminate(format!(
                    "br i1 {is_ok}, label %{ok_label}, label %{err_label}"
                ));
                self.start_block(&ok_label);
                let source_payload = self.temp();
                self.instruction(format!(
                    "{source_payload} = getelementptr {}, ptr {source}, i32 0, i32 1",
                    self.lltype(ty)
                ));
                let destination_payload = self.temp();
                self.instruction(format!(
                    "{destination_payload} = getelementptr {}, ptr {destination}, i32 0, i32 1",
                    self.lltype(ty)
                ));
                self.emit_rebase_growing_payload(
                    &destination_payload,
                    &source_payload,
                    ok,
                    root_destination,
                    root_ty,
                    extra_offset,
                );
                self.terminate(format!("br label %{merge_label}"));
                self.start_block(&err_label);
                let source_payload = self.temp();
                self.instruction(format!(
                    "{source_payload} = getelementptr {}, ptr {source}, i32 0, i32 1",
                    self.lltype(ty)
                ));
                let destination_payload = self.temp();
                self.instruction(format!(
                    "{destination_payload} = getelementptr {}, ptr {destination}, i32 0, i32 1",
                    self.lltype(ty)
                ));
                self.emit_rebase_growing_payload(
                    &destination_payload,
                    &source_payload,
                    err,
                    root_destination,
                    root_ty,
                    extra_offset,
                );
                self.terminate(format!("br label %{merge_label}"));
                self.start_block(&merge_label);
            }
            TTypeKind::Map { key, capacity, .. } | TTypeKind::Set { key, capacity }
                if self.ascii_max(key).is_some() =>
            {
                let end_pointer = self.emit_map_meta_ptr(ty, source, 1);
                let end = self.temp();
                self.instruction(format!("{end} = load i64, ptr {end_pointer}, align 1"));
                let counter = self.entry_alloca(Ty::Long);
                self.instruction(format!("store i64 0, ptr {counter}, align 1"));
                let condition = self.new_label("growing.copy.map.cond");
                let inspect = self.new_label("growing.copy.map.inspect");
                let active_label = self.new_label("growing.copy.map.active");
                let step = self.new_label("growing.copy.map.step");
                let done = self.new_label("growing.copy.map.done");
                self.terminate(format!("br label %{condition}"));
                self.start_block(&condition);
                let index = self.temp();
                self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
                let more = self.temp();
                self.instruction(format!("{more} = icmp ult i64 {index}, {end}"));
                self.terminate(format!("br i1 {more}, label %{inspect}, label %{done}"));
                self.start_block(&inspect);
                let active_ptr = self.emit_map_array_ptr(ty, source, 2, capacity, Ty::Bool, &index);
                let active = self.temp();
                self.instruction(format!("{active} = load i1, ptr {active_ptr}, align 1"));
                self.terminate(format!(
                    "br i1 {active}, label %{active_label}, label %{step}"
                ));
                self.start_block(&active_label);
                let source_key = self.emit_map_entry_ptr(ty, source, &index, false);
                let key_value = self.temp();
                self.instruction(format!(
                    "{key_value} = load {}, ptr {source_key}, align 1",
                    self.lltype(key)
                ));
                self.emit_map_store_key(ty, destination, key, &index, &key_value);
                self.terminate(format!("br label %{step}"));
                self.start_block(&step);
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {index}, 1"));
                self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
                self.terminate(format!("br label %{condition}"));
                self.start_block(&done);
            }
            _ => {}
        }
    }

    fn emit_expr_to_growing_root(
        &mut self,
        destination: &str,
        expr: &TExpr,
        root_destination: &str,
        root_ty: Ty,
        extra_offset: usize,
    ) {
        if let TExprKind::StructConstruct { fields } = &expr.kind {
            self.emit_empty_storage(destination, expr.ty);
            let field_types = match self.program.types[expr.ty.0].kind.clone() {
                TTypeKind::Struct(fields) => fields,
                _ => unreachable!("struct construction has a struct type"),
            };
            let mut field_offsets = Vec::with_capacity(field_types.len());
            let mut next_offset = extra_offset;
            for field in &field_types {
                field_offsets.push(next_offset);
                next_offset = next_offset.saturating_add(growing_value_extra(
                    field.ty,
                    &self.program.types,
                    &mut vec![false; self.program.types.len()],
                ));
            }
            for (index, value) in fields {
                let offset = field_offsets[*index];
                let field_destination = self.temp();
                self.instruction(format!(
                    "{field_destination} = getelementptr inbounds {}, ptr {destination}, i32 0, i32 {index}",
                    self.lltype(expr.ty)
                ));
                self.emit_expr_to_growing_root(
                    &field_destination,
                    value,
                    root_destination,
                    root_ty,
                    offset,
                );
                if self.terminated {
                    return;
                }
            }
            return;
        }

        let extra = growing_value_extra(
            expr.ty,
            &self.program.types,
            &mut vec![false; self.program.types.len()],
        );
        if extra == 0 {
            self.emit_expr_to(destination, expr);
            return;
        }

        let fixed_size = type_size(
            root_ty,
            &self.program.types,
            &mut vec![None; self.program.types.len()],
        );
        let inline_offset = fixed_size.saturating_add(extra_offset);
        let data = self.temp();
        self.instruction(format!(
            "{data} = getelementptr i8, ptr {root_destination}, i64 {inline_offset}"
        ));
        if self.is_text_type(expr.ty) {
            self.emit_text_to_data(destination, expr, &data);
            return;
        }
        if self.ascii_max(expr.ty).is_some() {
            self.emit_ascii_to_data(destination, expr, &data);
            return;
        }

        let source = self.emit_expr_storage(expr);
        if self.terminated {
            return;
        }
        if source != destination {
            let bytes = type_size(
                expr.ty,
                &self.program.types,
                &mut vec![None; self.program.types.len()],
            );
            self.instruction(format!(
                "call void @llvm.memmove.p0.p0.i64(ptr {destination}, ptr {source}, i64 {bytes}, i1 false)"
            ));
            self.emit_rebase_growing_payload(
                destination,
                &source,
                expr.ty,
                root_destination,
                root_ty,
                extra_offset,
            );
        }
    }

    fn emit_expr_to(&mut self, destination: &str, expr: &TExpr) {
        match &expr.kind {
            TExprKind::TextSlice {
                receiver,
                start,
                end,
            } => {
                self.emit_string_slice_to(destination, expr, receiver, start, end, true);
                return;
            }
            TExprKind::BytesSlice {
                receiver,
                start,
                end,
            } => {
                self.emit_string_slice_to(destination, expr, receiver, start, end, false);
                return;
            }
            TExprKind::BytesView(receiver) => {
                self.emit_bytes_view_to(destination, expr, receiver);
                return;
            }
            TExprKind::TextConvert {
                conversion: StringConversion::AsciiToText,
                ..
            } => {
                self.emit_text_to(destination, expr);
                return;
            }
            TExprKind::TextConvert { .. } => {
                self.emit_text_conversion_to(destination, expr);
                return;
            }
            _ => {}
        }
        if self.is_text_type(expr.ty) {
            self.emit_text_to(destination, expr);
            return;
        }
        if self.ascii_max(expr.ty).is_some() {
            self.emit_ascii_to(destination, expr);
            return;
        }
        if let TExprKind::AsciiFit { value, option_ty } = &expr.kind {
            self.emit_ascii_fit_to(destination, expr, value, *option_ty);
            return;
        }
        if !is_large_type(expr.ty, &self.program.types) {
            let value = self.emit_expr(expr);
            if !self.terminated && expr.ty != Ty::Unit {
                self.instruction(format!(
                    "store {} {value}, ptr {destination}, align 1",
                    self.lltype(expr.ty)
                ));
            }
            return;
        }

        if let Some(place) = Self::expr_place(expr) {
            if let Some((collection_ty, pointer, index)) = self.emit_struct_element_address(&place)
            {
                self.emit_gather_collection_element(collection_ty, &pointer, &index, destination);
                return;
            }
            let source = self.emit_place_pointer(&place);
            if source != destination {
                self.emit_copy_value_storage(destination, &source, expr.ty);
            }
            return;
        }
        if let TExprKind::Constant(id) = &expr.kind {
            self.emit_copy_value_storage(destination, &format!("@nl.const.{id}"), expr.ty);
            return;
        }

        match &expr.kind {
            TExprKind::EmptyArray
            | TExprKind::EmptyGrid
            | TExprKind::EmptyList
            | TExprKind::EmptyMap
            | TExprKind::EmptySet
            | TExprKind::EmptyQueue
            | TExprKind::EmptyRing => {
                self.emit_empty_storage(destination, expr.ty);
            }
            TExprKind::EmptyPool => {
                self.emit_empty_storage(destination, expr.ty);
            }
            TExprKind::ByteString(value) => self.emit_byte_string_to(destination, expr.ty, value),
            TExprKind::Call {
                target: CallTarget::Function(function_id),
                args,
                ..
            } => {
                self.emit_direct_call(*function_id, args, Some(destination), expr.span);
            }
            TExprKind::Call {
                target: CallTarget::FsJoin,
                args,
                ..
            } => {
                self.emit_capability_call_to(destination, expr, &CallTarget::FsJoin, args);
            }
            TExprKind::IndirectCall {
                callee,
                args,
                params,
                ..
            } => {
                self.emit_indirect_call(
                    callee,
                    args,
                    params,
                    expr.ty,
                    Some(destination),
                    expr.span,
                );
            }
            TExprKind::StructConstruct { fields } => {
                let _ = fields;
                self.emit_expr_to_growing_root(destination, expr, destination, expr.ty, 0);
            }
            TExprKind::Field {
                receiver,
                field_index,
            } => {
                let receiver_pointer = self.emit_expr_storage(receiver);
                let field_pointer = self.temp();
                self.instruction(format!(
                    "{field_pointer} = getelementptr inbounds {}, ptr {receiver_pointer}, i32 0, i32 {field_index}",
                    self.lltype(receiver.ty)
                ));
                self.emit_copy_value_storage(destination, &field_pointer, expr.ty);
            }
            TExprKind::Index {
                receiver,
                index,
                proven,
                grid,
                ..
            } => {
                let collection_pointer = self.emit_expr_storage(receiver);
                if self.terminated {
                    return;
                }
                let index_value = if let Some(grid) = grid {
                    self.emit_grid_index_value(grid)
                } else {
                    self.emit_expr(index)
                };
                if self.terminated {
                    return;
                }
                if grid.is_none() && !*proven {
                    self.emit_index_guard(
                        receiver.ty,
                        &collection_pointer,
                        &index_value,
                        false,
                        index.span,
                    );
                }
                self.emit_collection_element_storage(
                    receiver.ty,
                    &collection_pointer,
                    &index_value,
                    destination,
                );
            }
            TExprKind::CollectionOp {
                op,
                receiver,
                args,
                capacity,
                proven_success,
            } => {
                self.emit_collection_op(
                    expr,
                    *op,
                    receiver,
                    args,
                    *capacity,
                    *proven_success,
                    Some(destination),
                );
            }
            TExprKind::MapOp {
                op,
                receiver,
                args,
                capacity,
                proven_success,
            } => {
                self.emit_map_op(
                    expr,
                    *op,
                    receiver,
                    args,
                    *capacity,
                    *proven_success,
                    Some(destination),
                );
            }
            TExprKind::PoolOp {
                op,
                receiver,
                args,
                capacity,
                proven_success,
            } => {
                self.emit_pool_op(
                    expr,
                    *op,
                    receiver,
                    args,
                    *capacity,
                    *proven_success,
                    Some(destination),
                );
            }
            TExprKind::Method { kind, receiver } => {
                self.emit_method_to(destination, expr, *kind, receiver);
            }
            TExprKind::Fill { value, capacity } => {
                let element = match &self.program.types[expr.ty.0].kind {
                    TTypeKind::Array { element, .. } | TTypeKind::Grid { element, .. } => *element,
                    _ => unreachable!("fill expressions have fixed collection types"),
                };
                let value_pointer = if is_large_type(element, &self.program.types) {
                    let pointer = self.emit_runtime_region_alloc(element, value.span, None);
                    self.emit_expr_to(&pointer, value);
                    Some(pointer)
                } else {
                    None
                };
                let value = if value_pointer.is_none() {
                    Some(self.emit_expr(value))
                } else {
                    None
                };
                if self.terminated || *capacity == 0 {
                    return;
                }
                self.emit_empty_storage(destination, expr.ty);
                let counter = self.entry_alloca(Ty::Long);
                self.instruction(format!("store i64 0, ptr {counter}, align 1"));
                let condition = self.new_label("fill.to.cond");
                let body = self.new_label("fill.to.body");
                let done = self.new_label("fill.to.done");
                self.terminate(format!("br label %{condition}"));
                self.start_block(&condition);
                let index = self.temp();
                self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
                let more = self.temp();
                self.instruction(format!("{more} = icmp ult i64 {index}, {capacity}"));
                self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
                self.start_block(&body);
                if let Some(source) = &value_pointer {
                    self.emit_scatter_collection_element(expr.ty, destination, &index, source);
                } else {
                    self.emit_store_collection_element(
                        expr.ty,
                        destination,
                        &index,
                        value.as_deref().unwrap(),
                    );
                }
                let next = self.temp();
                self.instruction(format!("{next} = add i64 {index}, 1"));
                self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
                self.terminate(format!("br label %{condition}"));
                self.start_block(&done);
            }
            TExprKind::Construct { case_index, args } => {
                let payload_ptr = self.temp();
                self.instruction(format!(
                    "{payload_ptr} = getelementptr {}, ptr {destination}, i32 0, i32 1",
                    self.lltype(expr.ty)
                ));
                let case = self.program.types[expr.ty.0].cases()[*case_index].clone();
                let mut offset = 0usize;
                for (arg, payload_ty) in args.iter().zip(case.payload) {
                    let field_ptr = self.temp();
                    self.instruction(format!(
                        "{field_ptr} = getelementptr i8, ptr {payload_ptr}, i64 {offset}"
                    ));
                    self.emit_expr_to(&field_ptr, arg);
                    if self.terminated {
                        return;
                    }
                    offset += type_size(
                        payload_ty,
                        &self.program.types,
                        &mut vec![None; self.program.types.len()],
                    );
                }
                self.emit_sum_tag_to(expr.ty, destination, *case_index);
            }
            TExprKind::If {
                condition,
                then_block,
                else_block,
            } => {
                let cond = self.emit_expr(condition);
                if self.terminated {
                    return;
                }
                let saved_top = self.stack_top.clone();
                let then_label = self.new_label("if.to.then");
                let else_label = self.new_label("if.to.else");
                let merge_label = self.new_label("if.to.end");
                self.terminate(format!(
                    "br i1 {cond}, label %{then_label}, label %{else_label}"
                ));
                self.start_block(&then_label);
                self.emit_block_contents(then_block);
                if !self.terminated {
                    if let Some(tail) = then_block.tail.as_deref() {
                        self.emit_expr_to(destination, tail);
                    }
                }
                if !self.terminated {
                    self.restore_stack_top(&saved_top);
                    self.terminate(format!("br label %{merge_label}"));
                }
                self.stack_top = saved_top.clone();
                self.start_block(&else_label);
                if let Some(block) = else_block {
                    self.emit_block_contents(block);
                    if !self.terminated {
                        if let Some(tail) = block.tail.as_deref() {
                            self.emit_expr_to(destination, tail);
                        }
                    }
                }
                if !self.terminated {
                    self.restore_stack_top(&saved_top);
                    self.terminate(format!("br label %{merge_label}"));
                }
                self.stack_top = saved_top;
                self.start_block(&merge_label);
            }
            TExprKind::Match { scrutinee, arms } => {
                self.emit_match(expr, scrutinee, arms, Some(destination));
            }
            TExprKind::Try {
                value,
                success_ty,
                error_ty,
                propagated_ty,
            } => {
                self.emit_try_to(destination, value, *success_ty, *error_ty, *propagated_ty);
            }
            TExprKind::Coalesce { option, fallback } => {
                self.emit_coalesce_to(destination, expr, option, fallback);
            }
            TExprKind::OptionalCall {
                receiver,
                function_id,
                args,
                wraps_result,
            } => {
                self.emit_optional_call_to(
                    destination,
                    expr,
                    receiver,
                    *function_id,
                    args,
                    *wraps_result,
                );
            }
            _ => {
                let value = self.emit_expr(expr);
                if !self.terminated {
                    self.instruction(format!(
                        "store {} {value}, ptr {destination}, align 1",
                        self.lltype(expr.ty)
                    ));
                }
            }
        }
    }

    fn emit_block_contents(&mut self, block: &TBlock) {
        for stmt in &block.statements {
            if self.terminated {
                break;
            }
            self.emit_stmt(stmt);
        }
    }

    fn emit_stmt(&mut self, stmt: &TStmt) {
        match &stmt.kind {
            TStmtKind::Let { id, ty, value, .. } => {
                if self.append_variant && self.append_builder_local == Some(*id) {
                    let descriptor = self.entry_alloca_raw("[16 x i8]");
                    let accepted = self.temp();
                    self.instruction(format!(
                        "{accepted} = load i64, ptr %nl.append.offset, align 1"
                    ));
                    let data = self.temp();
                    self.instruction(format!(
                        "{data} = getelementptr i8, ptr %nl.append.data, i64 {accepted}"
                    ));
                    self.instruction(format!("store ptr {data}, ptr {descriptor}, align 1"));
                    let length = self.temp();
                    self.instruction(format!(
                        "{length} = getelementptr i8, ptr {descriptor}, i64 8"
                    ));
                    self.instruction(format!("store i64 0, ptr {length}, align 1"));
                    self.instruction(format!(
                        "%local.{id} = getelementptr i8, ptr {descriptor}, i64 0"
                    ));
                    return;
                }
                if is_large_type(*ty, &self.program.types) {
                    if returned_lazy_local(self.function, &self.program.types) == Some(*id) {
                        let pointer = format!("%local.{id}");
                        self.instruction(format!(
                            "{pointer} = getelementptr i8, ptr %nl.result, i64 0"
                        ));
                        self.emit_expr_to(&pointer, value);
                        return;
                    }
                    if !self.append_variant && self.returned_ascii_builder_local == Some(*id) {
                        let pointer = format!("%local.{id}");
                        self.instruction(format!(
                            "{pointer} = getelementptr i8, ptr %nl.result, i64 0"
                        ));
                        self.emit_expr_to(&pointer, value);
                        return;
                    }
                    if let TExprKind::Take(source) = &value.kind {
                        if let TExprKind::Local(source_id) = source.kind {
                            let source_pointer = self.local_pointer(source_id);
                            self.instruction(format!(
                                "%local.{id} = getelementptr i8, ptr {source_pointer}, i64 0"
                            ));
                            return;
                        }
                    }
                    if self.is_ascii_type(*ty) && !self.reserved_ascii_locals.contains(id) {
                        if let Some(length) = self.ascii_static_length(value) {
                            let bytes = (16usize.saturating_add(length)).to_string();
                            let pointer = self.emit_runtime_region_alloc_dynamic(
                                &bytes,
                                stmt.span,
                                Some(format!("%local.{id}")),
                            );
                            self.emit_expr_to(&pointer, value);
                            return;
                        }
                        if matches!(value.kind, TExprKind::Local(_)) {
                            let descriptor = self.emit_expr(value);
                            if self.terminated {
                                return;
                            }
                            self.emit_ascii_descriptor_to_local(
                                *id,
                                &descriptor,
                                value.ty,
                                *ty,
                                stmt.span,
                            );
                            return;
                        }
                    }
                    let pointer = self.emit_runtime_region_alloc(
                        *ty,
                        stmt.span,
                        Some(format!("%local.{id}")),
                    );
                    self.emit_expr_to(&pointer, value);
                    if !self.terminated
                        && self.is_ascii_type(*ty)
                        && !self.reserved_ascii_locals.contains(id)
                    {
                        let descriptor = self.temp();
                        self.instruction(format!(
                            "{descriptor} = load {}, ptr {pointer}, align 1",
                            self.lltype(*ty)
                        ));
                        let length = self.ascii_field(&descriptor, *ty, 1);
                        let bytes = self.temp();
                        self.instruction(format!("{bytes} = add i64 {length}, 16"));
                        let packed_top = self.temp();
                        self.instruction(format!(
                            "{packed_top} = getelementptr i8, ptr {pointer}, i64 {bytes}"
                        ));
                        self.restore_stack_top(&packed_top);
                    }
                } else {
                    let val = self.emit_expr(value);
                    if !self.terminated {
                        self.instruction(format!(
                            "store {} {val}, ptr %local.{id}, align 1",
                            self.lltype(*ty)
                        ));
                    }
                }
            }
            TStmtKind::Assign {
                place,
                ty,
                op,
                operator_span,
                value,
            } => {
                if *op == AssignOp::Set {
                    if let Some((collection_ty, collection_pointer, index, lane)) =
                        self.emit_growing_field_address(place)
                    {
                        let saved_top = self.stack_top.clone();
                        let scratch = self.emit_runtime_region_alloc(*ty, value.span, None);
                        self.emit_expr_to(&scratch, value);
                        if !self.terminated {
                            self.emit_store_var_lane(
                                collection_ty,
                                &collection_pointer,
                                &index,
                                lane,
                                &scratch,
                            );
                            self.restore_stack_top(&saved_top);
                        }
                        return;
                    }
                }
                if self.is_ascii_type(*ty) {
                    if *op == AssignOp::Add {
                        self.emit_ascii_append_place(place, value);
                    } else if *op == AssignOp::Set {
                        self.emit_ascii_assign_place(place, value);
                    } else {
                        unreachable!("checker rejects non-add Ascii assignment operators")
                    }
                    return;
                }
                let struct_address = self.emit_struct_element_address(place);
                let pointer = if struct_address.is_some() {
                    None
                } else {
                    Some(self.emit_place_pointer(place))
                };
                if *op == AssignOp::Set && is_large_type(*ty, &self.program.types) {
                    if let Some(pointer) = pointer {
                        self.emit_expr_to(&pointer, value);
                    } else {
                        if let Some((collection_ty, collection_pointer, index)) = struct_address {
                            let saved_top = self.stack_top.clone();
                            let scratch = self.emit_runtime_region_alloc(*ty, value.span, None);
                            self.emit_expr_to(&scratch, value);
                            if !self.terminated {
                                self.emit_scatter_collection_element(
                                    collection_ty,
                                    &collection_pointer,
                                    &index,
                                    &scratch,
                                );
                                self.restore_stack_top(&saved_top);
                            }
                        }
                    }
                    return;
                }
                let lhs = if *op != AssignOp::Set {
                    Some(if let Some(pointer) = &pointer {
                        let lhs = self.temp();
                        self.instruction(format!(
                            "{lhs} = load {}, ptr {pointer}, align 1",
                            self.lltype(*ty)
                        ));
                        lhs
                    } else {
                        self.emit_load_place(place)
                    })
                } else {
                    None
                };
                let rhs = self.emit_expr(value);
                if self.terminated {
                    return;
                }
                if *op == AssignOp::Set {
                    if let Some(pointer) = pointer {
                        self.instruction(format!(
                            "store {} {rhs}, ptr {pointer}, align 1",
                            self.lltype(*ty)
                        ));
                    } else if let Some((collection_ty, pointer, index)) = struct_address {
                        self.emit_store_collection_element(collection_ty, &pointer, &index, &rhs);
                    } else {
                        self.emit_store_place(place, &rhs);
                    }
                } else {
                    let lhs = lhs.unwrap();
                    let bop = assign_binary(*op);
                    let result = self.emit_binary(
                        bop,
                        base_type(*ty, &self.program.types),
                        &lhs,
                        &rhs,
                        *operator_span,
                    );
                    if !self.terminated {
                        let result = self.emit_policy_conversion(result, *ty, *operator_span);
                        if let Some(pointer) = pointer {
                            self.instruction(format!(
                                "store {} {result}, ptr {pointer}, align 1",
                                self.lltype(*ty)
                            ));
                        } else if let Some((collection_ty, pointer, index)) = struct_address {
                            self.emit_store_collection_element(
                                collection_ty,
                                &pointer,
                                &index,
                                &result,
                            );
                        } else {
                            self.emit_store_place(place, &result);
                        }
                    }
                }
            }
            TStmtKind::Return(value) => {
                if let Some(value) = value {
                    if self.append_variant {
                        if result_ascii_payload(self.function.result, &self.program.types).is_some()
                        {
                            self.emit_result_ascii_append_return(value);
                        } else {
                            self.emit_ascii_stream(value, "%nl.append.data", "%nl.append.offset");
                        }
                        if !self.terminated {
                            self.emit_all_iteration_cleanups();
                            self.terminate("ret void");
                        }
                        return;
                    }
                    if is_large_type(self.function.result, &self.program.types) {
                        self.emit_expr_to("%nl.result", value);
                        if !self.terminated {
                            self.emit_all_iteration_cleanups();
                            self.terminate("ret void");
                        }
                        return;
                    }
                    let val = self.emit_expr(value);
                    if !self.terminated {
                        self.emit_all_iteration_cleanups();
                        self.terminate(format!("ret {} {val}", self.lltype(value.ty)));
                    }
                } else {
                    self.emit_all_iteration_cleanups();
                    self.terminate("ret void");
                }
            }
            TStmtKind::Expr(expr) => {
                self.emit_expr(expr);
            }
            TStmtKind::If {
                condition,
                then_block,
                else_block,
            } => {
                self.emit_if(
                    condition,
                    then_block,
                    else_block.as_ref(),
                    Ty::Unit,
                    false,
                    stmt.span,
                );
            }
            TStmtKind::For {
                id,
                ty,
                start,
                end,
                inclusive,
                body,
            } => self.emit_for(*id, *ty, start, end, *inclusive, body),
            TStmtKind::ForEach {
                id,
                index_id,
                second_index_id,
                counter_id,
                collection,
                source,
                is_list,
                is_pool,
                is_map,
                is_set,
                is_grid,
                body,
            } => self.emit_for_each(
                *id,
                *index_id,
                *second_index_id,
                *counter_id,
                collection,
                source,
                *is_list,
                *is_pool,
                *is_map,
                *is_set,
                *is_grid,
                body,
            ),
            TStmtKind::Discard(value) => {
                self.emit_expr(value);
            }
            TStmtKind::Break => {
                self.emit_iteration_cleanup();
                let exit = self
                    .loops
                    .last()
                    .expect("checker validated break")
                    .exit
                    .clone();
                self.terminate(format!("br label %{exit}"));
            }
            TStmtKind::Continue => {
                self.emit_iteration_cleanup();
                let latch = self
                    .loops
                    .last()
                    .expect("checker validated continue")
                    .latch
                    .clone();
                self.terminate(format!("br label %{latch}"));
            }
            TStmtKind::Expect { source, kind } => self.emit_expect(source, kind, stmt.span),
            TStmtKind::Block(block) => self.emit_block(block),
        }
    }

    fn emit_block(&mut self, block: &TBlock) {
        let saved_top = self.stack_top.clone();
        self.emit_block_contents(block);
        if !self.terminated {
            if let Some(tail) = &block.tail {
                self.emit_expr(tail);
            }
            if !self.terminated {
                self.restore_stack_top(&saved_top);
            }
        }
    }

    fn emit_for(
        &mut self,
        id: usize,
        ty: Ty,
        start: &TExpr,
        end: &TExpr,
        inclusive: bool,
        body: &TBlock,
    ) {
        let start_value = self.emit_expr(start);
        let end_value = self.emit_expr(end);
        if self.terminated {
            return;
        }
        self.instruction(format!(
            "store {} {start_value}, ptr %local.{id}",
            self.lltype(ty)
        ));
        let condition = self.new_label("for.cond");
        let body_label = self.new_label("for.body");
        let latch = self.new_label("for.latch");
        let exit = self.new_label("for.exit");
        self.terminate(format!("br label %{condition}"));

        self.start_block(&condition);
        let current = self.temp();
        self.instruction(format!(
            "{current} = load {}, ptr %local.{id}",
            self.lltype(ty)
        ));
        let in_range = self.temp();
        self.instruction(format!(
            "{in_range} = icmp {} {} {current}, {end_value}",
            if inclusive { "sle" } else { "slt" },
            self.lltype(ty)
        ));
        self.terminate(format!(
            "br i1 {in_range}, label %{body_label}, label %{exit}"
        ));

        self.start_block(&body_label);
        let iteration_top = self.stack_top.clone();
        self.loops.push(LoopTargets {
            latch: latch.clone(),
            exit: exit.clone(),
            stack_top: iteration_top,
        });
        self.emit_block(body);
        if !self.terminated {
            self.emit_iteration_cleanup();
            self.terminate(format!("br label %{latch}"));
        }
        self.loops.pop();

        self.start_block(&latch);
        let current = self.temp();
        self.instruction(format!(
            "{current} = load {}, ptr %local.{id}",
            self.lltype(ty)
        ));
        if inclusive {
            let at_end = self.temp();
            self.instruction(format!(
                "{at_end} = icmp eq {} {current}, {end_value}",
                self.lltype(ty)
            ));
            let increment = self.new_label("for.increment");
            self.terminate(format!("br i1 {at_end}, label %{exit}, label %{increment}"));
            self.start_block(&increment);
        }
        let next = self.temp();
        self.instruction(format!("{next} = add {} {current}, 1", self.lltype(ty)));
        self.instruction(format!("store {} {next}, ptr %local.{id}", self.lltype(ty)));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&exit);
    }

    fn emit_for_each(
        &mut self,
        id: usize,
        index_id: Option<usize>,
        second_index_id: Option<usize>,
        counter_id: usize,
        collection: &TExpr,
        source: &TPlace,
        is_list: bool,
        is_pool: bool,
        is_map: bool,
        is_set: bool,
        is_grid: bool,
        body: &TBlock,
    ) {
        let collection_ptr = self.emit_place_pointer(source);
        let collection_ty = collection.ty;
        let capacity = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { capacity, .. }
            | TTypeKind::List { capacity, .. }
            | TTypeKind::Queue { capacity, .. }
            | TTypeKind::Ring { capacity, .. }
            | TTypeKind::Grid { capacity, .. }
            | TTypeKind::Pool { capacity, .. }
            | TTypeKind::Map { capacity, .. }
            | TTypeKind::Set { capacity, .. } => capacity,
            _ => unreachable!("typed foreach collection"),
        };
        if is_pool {
            let high_water_ptr = self.emit_pool_meta_ptr(collection_ty, &collection_ptr, 5);
            let high_water = self.temp();
            self.instruction(format!(
                "{high_water} = load i64, ptr {high_water_ptr}, align 1"
            ));
            let snapshot = self.entry_alloca_raw(&format!("[{} x i1]", capacity));
            let snapshot_index = self.entry_alloca(Ty::Long);
            self.instruction(format!("store i64 0, ptr {snapshot_index}, align 1"));
            let copy_cond = self.new_label("foreach.pool.snapshot.cond");
            let copy_body = self.new_label("foreach.pool.snapshot.body");
            let copy_done = self.new_label("foreach.pool.snapshot.done");
            self.terminate(format!("br label %{copy_cond}"));
            self.start_block(&copy_cond);
            let index = self.temp();
            self.instruction(format!("{index} = load i64, ptr {snapshot_index}, align 1"));
            let more = self.temp();
            self.instruction(format!("{more} = icmp ult i64 {index}, {high_water}"));
            self.terminate(format!(
                "br i1 {more}, label %{copy_body}, label %{copy_done}"
            ));
            self.start_block(&copy_body);
            let occupied_ptr = self.emit_pool_slot_ptr(collection_ty, &collection_ptr, 2, &index);
            let occupied = self.temp();
            self.instruction(format!("{occupied} = load i1, ptr {occupied_ptr}, align 1"));
            let snapshot_ptr = self.temp();
            self.instruction(format!("{snapshot_ptr} = getelementptr inbounds [{} x i1], ptr {snapshot}, i32 0, i64 {index}", capacity));
            self.instruction(format!("store i1 {occupied}, ptr {snapshot_ptr}, align 1"));
            let next = self.temp();
            self.instruction(format!("{next} = add i64 {index}, 1"));
            self.instruction(format!("store i64 {next}, ptr {snapshot_index}, align 1"));
            self.terminate(format!("br label %{copy_cond}"));
            self.start_block(&copy_done);
            self.instruction(format!("store i64 0, ptr %local.{counter_id}, align 1"));
            let condition = self.new_label("foreach.pool.cond");
            let check = self.new_label("foreach.pool.check");
            let body_label = self.new_label("foreach.pool.body");
            let latch = self.new_label("foreach.pool.latch");
            let exit = self.new_label("foreach.pool.exit");
            self.terminate(format!("br label %{condition}"));
            self.start_block(&condition);
            let current = self.temp();
            self.instruction(format!(
                "{current} = load i64, ptr %local.{counter_id}, align 1"
            ));
            let within = self.temp();
            self.instruction(format!("{within} = icmp ult i64 {current}, {high_water}"));
            self.terminate(format!("br i1 {within}, label %{check}, label %{exit}"));
            self.start_block(&check);
            let snapshot_ptr = self.temp();
            self.instruction(format!("{snapshot_ptr} = getelementptr inbounds [{} x i1], ptr {snapshot}, i32 0, i64 {current}", capacity));
            let present = self.temp();
            self.instruction(format!("{present} = load i1, ptr {snapshot_ptr}, align 1"));
            self.terminate(format!(
                "br i1 {present}, label %{body_label}, label %{latch}"
            ));
            self.start_block(&body_label);
            if let Some(index_id) = index_id {
                let generation_ptr =
                    self.emit_pool_slot_ptr(collection_ty, &collection_ptr, 3, &current);
                let generation = self.temp();
                self.instruction(format!(
                    "{generation} = load i32, ptr {generation_ptr}, align 1"
                ));
                let slot32 = self.temp();
                self.instruction(format!("{slot32} = trunc i64 {current} to i32"));
                let id = self.emit_make_id(&slot32, &generation);
                self.instruction(format!("store i64 {id}, ptr %local.{index_id}, align 1"));
            }
            self.views.insert(
                id,
                ViewInfo {
                    collection_ty,
                    collection_ptr: collection_ptr.clone(),
                    counter_id,
                },
            );
            let iteration_top = self.stack_top.clone();
            self.loops.push(LoopTargets {
                latch: latch.clone(),
                exit: exit.clone(),
                stack_top: iteration_top,
            });
            self.emit_block(body);
            if !self.terminated {
                self.emit_iteration_cleanup();
                self.terminate(format!("br label %{latch}"));
            }
            self.loops.pop();
            self.views.remove(&id);
            self.start_block(&latch);
            let current = self.temp();
            self.instruction(format!(
                "{current} = load i64, ptr %local.{counter_id}, align 1"
            ));
            let next = self.temp();
            self.instruction(format!("{next} = add i64 {current}, 1"));
            self.instruction(format!(
                "store i64 {next}, ptr %local.{counter_id}, align 1"
            ));
            self.terminate(format!("br label %{condition}"));
            self.start_block(&exit);
            let _ = collection;
            return;
        }
        let snapshot = if is_list {
            self.emit_collection_count(collection_ty, &collection_ptr)
        } else if is_map || is_set {
            let end_ptr = self.emit_map_meta_ptr(collection_ty, &collection_ptr, 1);
            let end = self.temp();
            self.instruction(format!("{end} = load i64, ptr {end_ptr}, align 1"));
            end
        } else {
            capacity.to_string()
        };
        self.instruction(format!("store i64 0, ptr %local.{counter_id}, align 1"));
        let condition = self.new_label("foreach.cond");
        let check = self.new_label("foreach.check");
        let body_label = self.new_label("foreach.body");
        let latch = self.new_label("foreach.latch");
        let exit = self.new_label("foreach.exit");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let current = self.temp();
        self.instruction(format!(
            "{current} = load i64, ptr %local.{counter_id}, align 1"
        ));
        let within = self.temp();
        self.instruction(format!("{within} = icmp ult i64 {current}, {snapshot}"));
        self.terminate(format!(
            "br i1 {within}, label %{}, label %{exit}",
            if is_map || is_set {
                &check
            } else {
                &body_label
            }
        ));
        if is_map || is_set {
            self.start_block(&check);
            let active_ptr = self.emit_map_array_ptr(
                collection_ty,
                &collection_ptr,
                2,
                capacity,
                Ty::Bool,
                &current,
            );
            let active = self.temp();
            self.instruction(format!("{active} = load i1, ptr {active_ptr}, align 1"));
            self.terminate(format!(
                "br i1 {active}, label %{body_label}, label %{latch}"
            ));
        }
        self.start_block(&body_label);
        if is_map {
            let (_, key_ty, _) = match self.program.types[collection_ty.0].kind {
                TTypeKind::Map { key, value, .. } => (collection_ty, key, value),
                _ => unreachable!(),
            };
            let key_ptr = self.emit_map_entry_ptr(collection_ty, &collection_ptr, &current, false);
            let key = self.temp();
            self.instruction(format!(
                "{key} = load {}, ptr {key_ptr}, align 1",
                self.lltype(key_ty)
            ));
            if let Some(index_id) = index_id {
                self.instruction(format!(
                    "store {} {key}, ptr %local.{index_id}, align 1",
                    self.lltype(key_ty)
                ));
            }
        } else if is_set {
            let key_ty = match self.program.types[collection_ty.0].kind {
                TTypeKind::Set { key, .. } => key,
                _ => unreachable!(),
            };
            let key_ptr = self.emit_map_entry_ptr(collection_ty, &collection_ptr, &current, false);
            let key = self.temp();
            self.instruction(format!(
                "{key} = load {}, ptr {key_ptr}, align 1",
                self.lltype(key_ty)
            ));
            self.instruction(format!(
                "store {} {key}, ptr %local.{id}, align 1",
                self.lltype(key_ty)
            ));
        } else if is_grid {
            let current = self.temp();
            self.instruction(format!(
                "{current} = load i64, ptr %local.{counter_id}, align 1"
            ));
            let width = match self.program.types[collection_ty.0].kind {
                TTypeKind::Grid { width, .. } => width,
                _ => unreachable!("grid iteration has a grid source"),
            };
            let (x, y) = if width == 0 {
                ("0".to_owned(), "0".to_owned())
            } else {
                let x = self.temp();
                self.instruction(format!("{x} = urem i64 {current}, {width}"));
                let y = self.temp();
                self.instruction(format!("{y} = udiv i64 {current}, {width}"));
                (x, y)
            };
            if let Some(index_id) = index_id {
                self.instruction(format!("store i64 {x}, ptr %local.{index_id}, align 1"));
            }
            if let Some(second_index_id) = second_index_id {
                self.instruction(format!(
                    "store i64 {y}, ptr %local.{second_index_id}, align 1"
                ));
            }
        } else if let Some(index_id) = index_id {
            let index = self.temp();
            self.instruction(format!(
                "{index} = load i64, ptr %local.{counter_id}, align 1"
            ));
            self.instruction(format!("store i64 {index}, ptr %local.{index_id}, align 1"));
        }
        if !is_set {
            self.views.insert(
                id,
                ViewInfo {
                    collection_ty,
                    collection_ptr,
                    counter_id,
                },
            );
        }
        let iteration_top = self.stack_top.clone();
        self.loops.push(LoopTargets {
            latch: latch.clone(),
            exit: exit.clone(),
            stack_top: iteration_top,
        });
        self.emit_block(body);
        if !self.terminated {
            self.emit_iteration_cleanup();
            self.terminate(format!("br label %{latch}"));
        }
        self.loops.pop();
        self.views.remove(&id);
        self.start_block(&latch);
        let current = self.temp();
        self.instruction(format!(
            "{current} = load i64, ptr %local.{counter_id}, align 1"
        ));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!(
            "store i64 {next}, ptr %local.{counter_id}, align 1"
        ));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&exit);
        let _ = collection;
    }

    fn emit_iteration_cleanup(&mut self) {
        if let Some(saved) = self.loops.last().map(|target| target.stack_top.clone()) {
            self.restore_stack_top(&saved);
        }
    }

    fn emit_all_iteration_cleanups(&mut self) {
        let saved = self
            .loops
            .iter()
            .rev()
            .map(|target| target.stack_top.clone())
            .collect::<Vec<_>>();
        for top in saved {
            self.restore_stack_top(&top);
        }
    }

    fn emit_expect(&mut self, source: &str, kind: &TExpectKind, span: Span) {
        if matches!(kind, TExpectKind::StackPeak { .. }) {
            return;
        }
        let (condition, comparison_values) = match kind {
            TExpectKind::Bool(value) => (self.emit_expr(value), None),
            TExpectKind::Compare { op, left, right } => {
                let storage = matches!(op, BinaryOp::Eq | BinaryOp::Ne)
                    && contains_lazy_collection(
                        left.ty,
                        &self.program.types,
                        &mut vec![false; self.program.types.len()],
                    );
                let lhs = if storage {
                    self.emit_expr_storage(left)
                } else {
                    self.emit_expr(left)
                };
                if self.terminated {
                    return;
                }
                let rhs = if storage {
                    self.emit_expr_storage(right)
                } else {
                    self.emit_expr(right)
                };
                if self.terminated {
                    return;
                }
                let condition = if storage {
                    let equal = self.emit_equal_storage(left.ty, &lhs, &rhs);
                    if *op == BinaryOp::Eq {
                        equal
                    } else {
                        let result = self.temp();
                        self.instruction(format!("{result} = xor i1 {equal}, true"));
                        result
                    }
                } else {
                    self.emit_binary(*op, left.ty, &lhs, &rhs, span)
                };
                (condition, Some((left.ty, lhs, rhs, storage)))
            }
            TExpectKind::StackPeak { .. } => unreachable!("handled above"),
        };
        if self.terminated {
            return;
        }
        let failed = self.temp();
        self.instruction(format!("{failed} = xor i1 {condition}, true"));
        let fail_label = self.new_label("expect.fail");
        let pass_label = self.new_label("expect.pass");
        let pass_top = self.stack_top.clone();
        self.terminate(format!(
            "br i1 {failed}, label %{fail_label}, label %{pass_label}, !prof !0"
        ));
        self.start_block(&fail_label);
        let source_id = self.expect_ids[source];
        let source_len = source.len() + 1;
        let source_ptr = format!(
            "getelementptr inbounds ([{source_len} x i8], ptr @.nl.expect.{source_id}, i64 0, i64 0)"
        );
        if let Some((ty, lhs, rhs, storage)) = comparison_values {
            if !matches!(
                base_type(ty, &self.program.types),
                Ty::Int | Ty::Long | Ty::Bool
            ) {
                self.instruction(format!(
                    "call void @nl_expect_fail_header(i32 {}, i32 {}, i32 {}, ptr {source_ptr})",
                    span.file, span.line, span.col
                ));
                self.instruction("call void @nl_expect_fail_left()");
                if storage {
                    self.emit_print_value_storage(ty, &lhs);
                } else {
                    self.emit_print_value(ty, &lhs);
                }
                self.instruction("call void @nl_print_newline()");
                self.instruction("call void @nl_expect_fail_right()");
                if storage {
                    self.emit_print_value_storage(ty, &rhs);
                } else {
                    self.emit_print_value(ty, &rhs);
                }
                self.instruction("call void @nl_print_newline()");
            } else {
                let (left, right, is_bool) = match base_type(ty, &self.program.types) {
                    Ty::Int => {
                        let l = self.temp();
                        let r = self.temp();
                        self.instruction(format!("{l} = sext i32 {lhs} to i64"));
                        self.instruction(format!("{r} = sext i32 {rhs} to i64"));
                        (l, r, 0)
                    }
                    Ty::Long => (lhs, rhs, 0),
                    Ty::Bool => {
                        let l = self.temp();
                        let r = self.temp();
                        self.instruction(format!("{l} = zext i1 {lhs} to i64"));
                        self.instruction(format!("{r} = zext i1 {rhs} to i64"));
                        (l, r, 1)
                    }
                    _ => unreachable!("expect comparisons only admit scalar values"),
                };
                self.instruction(format!("call void @nl_expect_fail_compare(i32 {}, i32 {}, i32 {}, ptr {source_ptr}, i64 {left}, i64 {right}, i32 {is_bool})", span.file, span.line, span.col));
            }
        } else {
            self.instruction(format!(
                "call void @nl_expect_fail_bool(i32 {}, i32 {}, i32 {}, ptr {source_ptr})",
                span.file, span.line, span.col
            ));
        }
        self.emit_all_iteration_cleanups();
        self.terminate("ret i32 1");
        self.stack_top = pass_top;
        self.start_block(&pass_label);
    }

    fn print_text(&mut self, value: &str) {
        let id = self.print_ids[value];
        let len = value.len() + 1;
        let ptr =
            format!("getelementptr inbounds ([{len} x i8], ptr @.nl.print.{id}, i64 0, i64 0)");
        self.instruction(format!("call void @nl_print_text(ptr {ptr})"));
    }

    fn emit_tag(&mut self, ty: Ty, value: &str) -> String {
        let result = self.temp();
        self.instruction(format!(
            "{result} = extractvalue {} {value}, 0",
            self.lltype(ty)
        ));
        result
    }

    fn emit_construct(&mut self, ty: Ty, case_index: usize, args: &[TExpr]) -> String {
        let mut values = Vec::new();
        for arg in args {
            let value = self.emit_expr(arg);
            if self.terminated {
                return String::new();
            }
            values.push((arg.ty, value));
        }
        self.emit_construct_values(ty, case_index, values)
    }

    fn emit_struct_construct(&mut self, ty: Ty, fields: &[(usize, TExpr)]) -> String {
        let llvm_ty = self.lltype(ty);
        let mut aggregate = "zeroinitializer".to_owned();
        for (index, value_expr) in fields {
            let value = self.emit_expr(value_expr);
            if self.terminated {
                return String::new();
            }
            let next = self.temp();
            self.instruction(format!(
                "{next} = insertvalue {llvm_ty} {aggregate}, {} {value}, {index}",
                self.lltype(value_expr.ty)
            ));
            aggregate = next;
        }
        aggregate
    }

    fn emit_policy_conversion(&mut self, value: String, target: Ty, span: Span) -> String {
        let Some((base, min, max, policy)) = refinement(target, &self.program.types) else {
            return value;
        };
        self.emit_policy_conversion_values(value, base, min, max, policy, span)
    }

    fn emit_policy_conversion_values(
        &mut self,
        value: String,
        base: Ty,
        min: i128,
        max: i128,
        policy: RefinePolicy,
        span: Span,
    ) -> String {
        match policy {
            RefinePolicy::Checked => value,
            RefinePolicy::Clamp => {
                let llvm_ty = self.lltype(base);
                let below = self.temp();
                self.instruction(format!("{below} = icmp slt {llvm_ty} {value}, {min}"));
                let at_least_min = self.temp();
                self.instruction(format!(
                    "{at_least_min} = select i1 {below}, {llvm_ty} {min}, {llvm_ty} {value}"
                ));
                let above = self.temp();
                self.instruction(format!(
                    "{above} = icmp sgt {llvm_ty} {at_least_min}, {max}"
                ));
                let result = self.temp();
                self.instruction(format!(
                    "{result} = select i1 {above}, {llvm_ty} {max}, {llvm_ty} {at_least_min}"
                ));
                let _ = span;
                result
            }
            RefinePolicy::Wrap => {
                let llvm_ty = self.lltype(base);
                let width = max - min + 1;
                let wide = self.temp();
                self.instruction(format!("{wide} = sext {llvm_ty} {value} to i128"));
                let delta = self.temp();
                self.instruction(format!("{delta} = sub i128 {wide}, {min}"));
                let remainder = self.temp();
                self.instruction(format!("{remainder} = srem i128 {delta}, {width}"));
                let negative = self.temp();
                self.instruction(format!("{negative} = icmp slt i128 {remainder}, 0"));
                let positive = self.temp();
                self.instruction(format!("{positive} = add i128 {remainder}, {width}"));
                let adjusted = self.temp();
                self.instruction(format!(
                    "{adjusted} = select i1 {negative}, i128 {positive}, i128 {remainder}"
                ));
                let wrapped = self.temp();
                self.instruction(format!("{wrapped} = add i128 {adjusted}, {min}"));
                let result = self.temp();
                self.instruction(format!("{result} = trunc i128 {wrapped} to {llvm_ty}"));
                let _ = span;
                result
            }
        }
    }

    fn emit_fit(
        &mut self,
        expr: &TExpr,
        value: &TExpr,
        min: i128,
        max: i128,
        option_ty: Ty,
    ) -> String {
        let value = self.emit_expr(value);
        let payload_ty = match &self.program.types[option_ty.0].kind {
            TTypeKind::Option(inner) => *inner,
            _ => unreachable!(),
        };
        let llvm_ty = self.lltype(payload_ty);
        let above_min = self.temp();
        self.instruction(format!("{above_min} = icmp sge {llvm_ty} {value}, {min}"));
        let below_max = self.temp();
        self.instruction(format!("{below_max} = icmp sle {llvm_ty} {value}, {max}"));
        let fits = self.temp();
        self.instruction(format!("{fits} = and i1 {above_min}, {below_max}"));
        let some_label = self.new_label("fit.some");
        let none_label = self.new_label("fit.none");
        let merge = self.new_label("fit.end");
        self.terminate(format!(
            "br i1 {fits}, label %{some_label}, label %{none_label}"
        ));
        self.start_block(&some_label);
        let some = self.emit_construct_values(option_ty, 0, vec![(payload_ty, value)]);
        let some_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&none_label);
        let none = self.emit_construct_values(option_ty, 1, Vec::new());
        let none_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi {} [ {some}, %{some_pred} ], [ {none}, %{none_pred} ]",
            self.lltype(expr.ty)
        ));
        result
    }

    fn emit_optional_to_long(&mut self, expr: &TExpr, receiver: &TExpr) -> String {
        let value = self.emit_expr(receiver);
        let tag = self.emit_tag(receiver.ty, &value);
        let is_some = self.temp();
        self.instruction(format!("{is_some} = icmp eq i32 {tag}, 0"));
        let some_label = self.new_label("optional.long.some");
        let none_label = self.new_label("optional.long.none");
        let merge = self.new_label("optional.long.end");
        self.terminate(format!(
            "br i1 {is_some}, label %{some_label}, label %{none_label}"
        ));
        self.start_block(&none_label);
        let none = self.emit_construct_values(expr.ty, 1, Vec::new());
        let none_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&some_label);
        let (_, inner) = self.emit_payload(receiver.ty, &value, 0, 0);
        let widened = self.temp();
        self.instruction(format!("{widened} = sext i32 {inner} to i64"));
        let payload_ty = match &self.program.types[expr.ty.0].kind {
            TTypeKind::Option(inner) => *inner,
            _ => unreachable!(),
        };
        let some = self.emit_construct_values(expr.ty, 0, vec![(payload_ty, widened)]);
        let some_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi {} [ {none}, %{none_pred} ], [ {some}, %{some_pred} ]",
            self.lltype(expr.ty)
        ));
        result
    }

    fn emit_construct_values(
        &mut self,
        ty: Ty,
        case_index: usize,
        values: Vec<(Ty, String)>,
    ) -> String {
        let llvm_ty = self.lltype(ty);
        let place = self.entry_alloca(ty);
        self.instruction(format!(
            "store {llvm_ty} zeroinitializer, ptr {place}, align 1"
        ));
        let tag_ptr = self.temp();
        self.instruction(format!(
            "{tag_ptr} = getelementptr {llvm_ty}, ptr {place}, i32 0, i32 0"
        ));
        self.instruction(format!("store i32 {case_index}, ptr {tag_ptr}, align 4"));
        let payload = self.temp();
        self.instruction(format!(
            "{payload} = getelementptr {llvm_ty}, ptr {place}, i32 0, i32 1"
        ));
        let case = self.program.types[ty.0].cases()[case_index].clone();
        let mut sizes = vec![None; self.program.types.len()];
        let mut offset = 0usize;
        for ((field_ty, value), expected_ty) in values.into_iter().zip(case.payload) {
            debug_assert_eq!(
                base_type(field_ty, &self.program.types),
                base_type(expected_ty, &self.program.types),
                "construction of {} case {} has incompatible payload type {} but expects {}",
                self.program.types[ty.0].name,
                case_index,
                self.program.types[field_ty.0].name,
                self.program.types[expected_ty.0].name
            );
            let size = type_size(field_ty, &self.program.types, &mut sizes);
            if field_ty != Ty::Unit {
                let field_ptr = self.temp();
                self.instruction(format!(
                    "{field_ptr} = getelementptr i8, ptr {payload}, i64 {offset}"
                ));
                self.instruction(format!(
                    "store {} {value}, ptr {field_ptr}, align 1",
                    self.lltype(field_ty)
                ));
            }
            offset += size;
        }
        let result = self.temp();
        self.instruction(format!("{result} = load {llvm_ty}, ptr {place}, align 1"));
        result
    }

    fn emit_payload(
        &mut self,
        ty: Ty,
        value: &str,
        case_index: usize,
        payload_index: usize,
    ) -> (Ty, String) {
        let payload_ty = self.program.types[ty.0].cases()[case_index].payload[payload_index];
        if payload_ty == Ty::Unit {
            return (payload_ty, String::new());
        }
        let llvm_ty = self.lltype(ty);
        let place = self.entry_alloca(ty);
        self.instruction(format!("store {llvm_ty} {value}, ptr {place}, align 1"));
        let payload = self.temp();
        self.instruction(format!(
            "{payload} = getelementptr {llvm_ty}, ptr {place}, i32 0, i32 1"
        ));
        let mut sizes = vec![None; self.program.types.len()];
        let case = self.program.types[ty.0].cases()[case_index].clone();
        let offset = case
            .payload
            .iter()
            .take(payload_index)
            .map(|field| type_size(*field, &self.program.types, &mut sizes))
            .sum::<usize>();
        let field_ptr = self.temp();
        self.instruction(format!(
            "{field_ptr} = getelementptr i8, ptr {payload}, i64 {offset}"
        ));
        let result = self.temp();
        self.instruction(format!(
            "{result} = load {}, ptr {field_ptr}, align 1",
            self.lltype(payload_ty)
        ));
        (payload_ty, result)
    }

    fn emit_print_value(&mut self, ty: Ty, value: &str) {
        let ty = base_type(ty, &self.program.types);
        if self.ascii_max(ty).is_some() {
            let data = self.ascii_field(value, ty, 0);
            let length = self.ascii_field(value, ty, 1);
            self.instruction(format!(
                "call void @nl_print_ascii(ptr {data}, i64 {length})"
            ));
            return;
        }
        if matches!(self.program.types[ty.0].kind, TTypeKind::Function { .. }) {
            self.emit_print_function(value);
            return;
        }
        if matches!(self.program.types[ty.0].kind, TTypeKind::Pool { .. }) {
            self.emit_print_pool(ty, value);
            return;
        }
        if matches!(self.program.types[ty.0].kind, TTypeKind::Grid { .. }) {
            self.emit_print_grid(ty, value);
            return;
        }
        if matches!(
            self.program.types[ty.0].kind,
            TTypeKind::Array { .. }
                | TTypeKind::List { .. }
                | TTypeKind::Queue { .. }
                | TTypeKind::Ring { .. }
        ) {
            self.emit_print_collection(ty, value);
            return;
        }
        if matches!(
            self.program.types[ty.0].kind,
            TTypeKind::Map { .. } | TTypeKind::Set { .. }
        ) {
            self.emit_print_map_set(ty, value);
            return;
        }
        match ty {
            Ty::Int => self.instruction(format!("call void @nl_print_int_raw(i32 {value})")),
            Ty::Long => self.instruction(format!("call void @nl_print_long_raw(i64 {value})")),
            Ty::Bool => {
                self.instruction(format!("call void @nl_print_bool_raw(i1 zeroext {value})"))
            }
            Ty::Unit => self.print_text("()"),
            _ => {
                if matches!(self.program.types[ty.0].kind, TTypeKind::Id { .. }) {
                    let slot = self.temp();
                    self.instruction(format!("{slot} = and i64 {value}, 4294967295"));
                    let generation = self.temp();
                    self.instruction(format!("{generation} = lshr i64 {value}, 32"));
                    self.instruction(format!("call void @nl_print_long_raw(i64 {slot})"));
                    self.print_text(":");
                    self.instruction(format!("call void @nl_print_long_raw(i64 {generation})"));
                    return;
                }
                if let TTypeKind::Struct(fields) = &self.program.types[ty.0].kind {
                    let name = self.program.types[ty.0].name.clone();
                    self.print_text(&name);
                    self.print_text(" { ");
                    for (index, field) in fields.iter().enumerate() {
                        if index != 0 {
                            self.print_text(", ");
                        }
                        self.print_text(&field.name);
                        self.print_text(": ");
                        let field_value = self.temp();
                        self.instruction(format!(
                            "{field_value} = extractvalue {} {value}, {index}",
                            self.lltype(ty)
                        ));
                        self.emit_print_value(field.ty, &field_value);
                    }
                    self.print_text(" }");
                    return;
                }
                let tag = self.emit_tag(ty, value);
                let cases = self.program.types[ty.0].cases();
                let merge = self.new_label("print.end");
                let mut case_labels = Vec::new();
                let invalid = self.new_label("print.invalid");
                for _ in cases.iter() {
                    case_labels.push(self.new_label("print.case"));
                }
                let switch = cases
                    .iter()
                    .enumerate()
                    .map(|(index, _)| format!("i32 {index}, label %{}", case_labels[index]))
                    .collect::<Vec<_>>()
                    .join(" ");
                self.terminate(format!("switch i32 {tag}, label %{invalid} [ {switch} ]"));
                self.start_block(&invalid);
                self.terminate("unreachable");
                for (index, case) in cases.iter().enumerate() {
                    self.start_block(&case_labels[index]);
                    self.print_text(&case.name);
                    if !case.payload.is_empty() {
                        self.print_text("(");
                        for payload_index in 0..case.payload.len() {
                            if payload_index != 0 {
                                self.print_text(", ");
                            }
                            let (field_ty, field) =
                                self.emit_payload(ty, value, index, payload_index);
                            self.emit_print_value(field_ty, &field);
                        }
                        self.print_text(")");
                    }
                    self.terminate(format!("br label %{merge}"));
                }
                self.start_block(&merge);
            }
        }
    }

    fn emit_print_value_storage(&mut self, ty: Ty, pointer: &str) {
        let ty = base_type(ty, &self.program.types);
        if self.ascii_max(ty).is_some() {
            let data_field = self.temp();
            let length_field = self.temp();
            self.instruction(format!(
                "{data_field} = getelementptr {}, ptr {pointer}, i32 0, i32 0",
                self.lltype(ty)
            ));
            self.instruction(format!(
                "{length_field} = getelementptr {}, ptr {pointer}, i32 0, i32 1",
                self.lltype(ty)
            ));
            let data = self.temp();
            let length = self.temp();
            self.instruction(format!("{data} = load ptr, ptr {data_field}, align 1"));
            self.instruction(format!("{length} = load i64, ptr {length_field}, align 1"));
            self.instruction(format!(
                "call void @nl_print_ascii(ptr {data}, i64 {length})"
            ));
            return;
        }
        match self.program.types[ty.0].kind.clone() {
            TTypeKind::Refinement { base, .. } => self.emit_print_value_storage(base, pointer),
            TTypeKind::Struct(fields) => {
                self.print_text(&self.program.types[ty.0].name.clone());
                self.print_text(" { ");
                for (index, field) in fields.iter().enumerate() {
                    if index != 0 {
                        self.print_text(", ");
                    }
                    self.print_text(&field.name);
                    self.print_text(": ");
                    let field_pointer = self.temp();
                    self.instruction(format!(
                        "{field_pointer} = getelementptr inbounds {}, ptr {pointer}, i32 0, i32 {index}",
                        self.lltype(ty)
                    ));
                    self.emit_print_value_storage(field.ty, &field_pointer);
                }
                self.print_text(" }");
            }
            TTypeKind::Pool { .. } => self.emit_print_pool_storage(ty, pointer),
            TTypeKind::Grid { .. } => self.emit_print_grid_storage(ty, pointer),
            TTypeKind::Array { .. }
            | TTypeKind::List { .. }
            | TTypeKind::Queue { .. }
            | TTypeKind::Ring { .. } => self.emit_print_collection_storage(ty, pointer),
            TTypeKind::Map { .. } | TTypeKind::Set { .. } => {
                self.emit_print_map_set_storage(ty, pointer)
            }
            TTypeKind::Option(_) | TTypeKind::Result(..) | TTypeKind::Enum(_) => {
                self.emit_print_sum_storage(ty, pointer)
            }
            _ => {
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {pointer}, align 1",
                    self.lltype(ty)
                ));
                self.emit_print_value(ty, &value);
            }
        }
    }

    fn emit_print_collection_element_storage(
        &mut self,
        collection_ty: Ty,
        pointer: &str,
        logical_index: &str,
    ) {
        let element = collection_element_type(collection_ty, &self.program.types);
        let index = if matches!(
            self.program.types[collection_ty.0].kind,
            TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
        ) {
            self.emit_queue_ring_physical_index(collection_ty, pointer, logical_index)
        } else {
            logical_index.to_owned()
        };
        if let TTypeKind::Struct(fields) = self.program.types[element.0].kind.clone() {
            self.print_text(&self.program.types[element.0].name.clone());
            self.print_text(" { ");
            for (lane, field) in fields.iter().enumerate() {
                if lane != 0 {
                    self.print_text(", ");
                }
                self.print_text(&field.name);
                self.print_text(": ");
                let field_pointer =
                    self.emit_collection_lane_pointer(collection_ty, pointer, &index, lane);
                self.emit_print_value_storage(field.ty, &field_pointer);
            }
            self.print_text(" }");
        } else {
            let item = self.emit_collection_lane_pointer(collection_ty, pointer, &index, 0);
            self.emit_print_value_storage(element, &item);
        }
    }

    fn emit_print_collection_storage(&mut self, ty: Ty, pointer: &str) {
        let length = match self.program.types[ty.0].kind {
            TTypeKind::Array { capacity, .. } => capacity.to_string(),
            TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. } => {
                let _ = element;
                self.emit_collection_count(ty, pointer)
            }
            _ => unreachable!(),
        };
        match self.program.types[ty.0].kind {
            TTypeKind::Queue { .. } => self.print_text("queue["),
            TTypeKind::Ring { .. } => self.print_text("ring["),
            _ => self.print_text("["),
        }
        let counter = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {counter}, align 1"));
        let condition = self.new_label("print.storage.collection.cond");
        let body = self.new_label("print.storage.collection.body");
        let advance = self.new_label("print.storage.collection.advance");
        let done = self.new_label("print.storage.collection.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {length}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
        self.start_block(&body);
        let first = self.temp();
        self.instruction(format!("{first} = icmp eq i64 {index}, 0"));
        let value_label = self.new_label("print.storage.collection.first");
        let separator = self.new_label("print.storage.collection.separator");
        self.terminate(format!(
            "br i1 {first}, label %{value_label}, label %{separator}"
        ));
        self.start_block(&separator);
        self.print_text(", ");
        self.terminate(format!("br label %{value_label}"));
        self.start_block(&value_label);
        self.emit_print_collection_element_storage(ty, pointer, &index);
        self.terminate(format!("br label %{advance}"));
        self.start_block(&advance);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {counter}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
        self.print_text("]");
    }

    fn emit_print_grid_storage(&mut self, ty: Ty, pointer: &str) {
        let (width, height) = match self.program.types[ty.0].kind {
            TTypeKind::Grid { width, height, .. } => (width, height),
            _ => unreachable!(),
        };
        let y_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {y_ptr}, align 1"));
        let outer_cond = self.new_label("print.storage.grid.outer.cond");
        let outer_body = self.new_label("print.storage.grid.outer.body");
        let outer_done = self.new_label("print.storage.grid.outer.done");
        self.print_text("[");
        self.terminate(format!("br label %{outer_cond}"));
        self.start_block(&outer_cond);
        let y = self.temp();
        self.instruction(format!("{y} = load i64, ptr {y_ptr}, align 1"));
        let more_rows = self.temp();
        self.instruction(format!("{more_rows} = icmp ult i64 {y}, {height}"));
        self.terminate(format!(
            "br i1 {more_rows}, label %{outer_body}, label %{outer_done}"
        ));
        self.start_block(&outer_body);
        let first_row = self.temp();
        self.instruction(format!("{first_row} = icmp eq i64 {y}, 0"));
        let row_label = self.new_label("print.storage.grid.row");
        let separator = self.new_label("print.storage.grid.separator");
        self.terminate(format!(
            "br i1 {first_row}, label %{row_label}, label %{separator}"
        ));
        self.start_block(&separator);
        self.print_text(", ");
        self.terminate(format!("br label %{row_label}"));
        self.start_block(&row_label);
        self.print_text("[");
        let x_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {x_ptr}, align 1"));
        let inner_cond = self.new_label("print.storage.grid.inner.cond");
        let inner_body = self.new_label("print.storage.grid.inner.body");
        let inner_item = self.new_label("print.storage.grid.inner.item");
        let inner_separator = self.new_label("print.storage.grid.inner.separator");
        let inner_advance = self.new_label("print.storage.grid.inner.advance");
        let inner_done = self.new_label("print.storage.grid.inner.done");
        self.terminate(format!("br label %{inner_cond}"));
        self.start_block(&inner_cond);
        let x = self.temp();
        self.instruction(format!("{x} = load i64, ptr {x_ptr}, align 1"));
        let more_cols = self.temp();
        self.instruction(format!("{more_cols} = icmp ult i64 {x}, {width}"));
        self.terminate(format!(
            "br i1 {more_cols}, label %{inner_body}, label %{inner_done}"
        ));
        self.start_block(&inner_body);
        let first = self.temp();
        self.instruction(format!("{first} = icmp eq i64 {x}, 0"));
        self.terminate(format!(
            "br i1 {first}, label %{inner_item}, label %{inner_separator}"
        ));
        self.start_block(&inner_separator);
        self.print_text(", ");
        self.terminate(format!("br label %{inner_item}"));
        self.start_block(&inner_item);
        let row = self.temp();
        self.instruction(format!("{row} = mul i64 {y}, {width}"));
        let flat = self.temp();
        self.instruction(format!("{flat} = add i64 {row}, {x}"));
        self.emit_print_collection_element_storage(ty, pointer, &flat);
        self.terminate(format!("br label %{inner_advance}"));
        self.start_block(&inner_advance);
        let next_x = self.temp();
        self.instruction(format!("{next_x} = add i64 {x}, 1"));
        self.instruction(format!("store i64 {next_x}, ptr {x_ptr}, align 1"));
        self.terminate(format!("br label %{inner_cond}"));
        self.start_block(&inner_done);
        self.print_text("]");
        let next_y = self.temp();
        self.instruction(format!("{next_y} = add i64 {y}, 1"));
        self.instruction(format!("store i64 {next_y}, ptr {y_ptr}, align 1"));
        self.terminate(format!("br label %{outer_cond}"));
        self.start_block(&outer_done);
        self.print_text("]");
    }

    fn emit_print_sum_storage(&mut self, ty: Ty, pointer: &str) {
        let tag_ptr = self.temp();
        self.instruction(format!(
            "{tag_ptr} = getelementptr {}, ptr {pointer}, i32 0, i32 0",
            self.lltype(ty)
        ));
        let tag = self.temp();
        self.instruction(format!("{tag} = load i32, ptr {tag_ptr}, align 4"));
        let cases = self.program.types[ty.0].cases().to_vec();
        let merge = self.new_label("print.storage.sum.end");
        let invalid = self.new_label("print.storage.sum.invalid");
        let labels = (0..cases.len())
            .map(|_| self.new_label("print.storage.sum.case"))
            .collect::<Vec<_>>();
        let switch = labels
            .iter()
            .enumerate()
            .map(|(index, label)| format!("i32 {index}, label %{label}"))
            .collect::<Vec<_>>()
            .join(" ");
        self.terminate(format!("switch i32 {tag}, label %{invalid} [ {switch} ]"));
        self.start_block(&invalid);
        self.terminate("unreachable");
        for (index, case) in cases.iter().enumerate() {
            self.start_block(&labels[index]);
            self.print_text(&case.name);
            if !case.payload.is_empty() {
                self.print_text("(");
                for (field_index, field_ty) in case.payload.iter().enumerate() {
                    if field_index != 0 {
                        self.print_text(", ");
                    }
                    let field = self.emit_sum_payload_pointer(ty, pointer, index, field_index);
                    self.emit_print_value_storage(*field_ty, &field);
                }
                self.print_text(")");
            }
            self.terminate(format!("br label %{merge}"));
        }
        self.start_block(&merge);
    }

    fn emit_print_map_set_storage(&mut self, ty: Ty, pointer: &str) {
        let (capacity, key_ty, value_ty) = match self.program.types[ty.0].kind {
            TTypeKind::Map {
                key,
                value,
                capacity,
            } => (capacity, key, Some(value)),
            TTypeKind::Set { key, capacity } => (capacity, key, None),
            _ => unreachable!(),
        };
        let end_ptr = self.emit_map_meta_ptr(ty, pointer, 1);
        let end = self.temp();
        self.instruction(format!("{end} = load i64, ptr {end_ptr}, align 1"));
        let counter = self.entry_alloca(Ty::Long);
        let first = self.entry_alloca(Ty::Bool);
        self.instruction(format!("store i64 0, ptr {counter}, align 1"));
        self.instruction(format!("store i1 true, ptr {first}, align 1"));
        let condition = self.new_label("print.storage.map.cond");
        let inspect = self.new_label("print.storage.map.inspect");
        let print = self.new_label("print.storage.map.item");
        let advance = self.new_label("print.storage.map.advance");
        let done = self.new_label("print.storage.map.done");
        self.print_text("{");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {end}"));
        self.terminate(format!("br i1 {more}, label %{inspect}, label %{done}"));
        self.start_block(&inspect);
        let active_ptr = self.emit_map_array_ptr(ty, pointer, 2, capacity, Ty::Bool, &index);
        let active = self.temp();
        self.instruction(format!("{active} = load i1, ptr {active_ptr}, align 1"));
        self.terminate(format!("br i1 {active}, label %{print}, label %{advance}"));
        self.start_block(&print);
        let is_first = self.temp();
        self.instruction(format!("{is_first} = load i1, ptr {first}, align 1"));
        let item = self.new_label("print.storage.map.first");
        let separator = self.new_label("print.storage.map.separator");
        self.terminate(format!(
            "br i1 {is_first}, label %{item}, label %{separator}"
        ));
        self.start_block(&separator);
        self.print_text(", ");
        self.terminate(format!("br label %{item}"));
        self.start_block(&item);
        self.instruction(format!("store i1 false, ptr {first}, align 1"));
        let key = self.emit_map_entry_ptr(ty, pointer, &index, false);
        self.emit_print_value_storage(key_ty, &key);
        if let Some(value_ty) = value_ty {
            self.print_text(": ");
            let value = self.emit_map_entry_ptr(ty, pointer, &index, true);
            self.emit_print_value_storage(value_ty, &value);
        }
        self.terminate(format!("br label %{advance}"));
        self.start_block(&advance);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {counter}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
        self.print_text("}");
    }

    fn emit_print_pool_element_storage(&mut self, ty: Ty, pointer: &str, index: &str) {
        let element = collection_element_type(ty, &self.program.types);
        if let TTypeKind::Struct(fields) = self.program.types[element.0].kind.clone() {
            self.print_text(&self.program.types[element.0].name.clone());
            self.print_text(" { ");
            for (lane, field) in fields.iter().enumerate() {
                if lane != 0 {
                    self.print_text(", ");
                }
                self.print_text(&field.name);
                self.print_text(": ");
                let value = self.emit_collection_lane_pointer(ty, pointer, index, lane);
                self.emit_print_value_storage(field.ty, &value);
            }
            self.print_text(" }");
        } else {
            let value = self.emit_collection_lane_pointer(ty, pointer, index, 0);
            self.emit_print_value_storage(element, &value);
        }
    }

    fn emit_print_pool_storage(&mut self, ty: Ty, pointer: &str) {
        let high_water_ptr = self.emit_pool_meta_ptr(ty, pointer, 5);
        let high_water = self.temp();
        self.instruction(format!(
            "{high_water} = load i64, ptr {high_water_ptr}, align 1"
        ));
        self.print_text("pool{");
        let counter = self.entry_alloca(Ty::Long);
        let first = self.entry_alloca(Ty::Bool);
        self.instruction(format!("store i64 0, ptr {counter}, align 1"));
        self.instruction(format!("store i1 true, ptr {first}, align 1"));
        let condition = self.new_label("print.storage.pool.cond");
        let body = self.new_label("print.storage.pool.body");
        let print = self.new_label("print.storage.pool.item");
        let advance = self.new_label("print.storage.pool.advance");
        let done = self.new_label("print.storage.pool.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {high_water}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
        self.start_block(&body);
        let occupied_ptr = self.emit_pool_slot_ptr(ty, pointer, 2, &index);
        let occupied = self.temp();
        self.instruction(format!("{occupied} = load i1, ptr {occupied_ptr}, align 1"));
        self.terminate(format!(
            "br i1 {occupied}, label %{print}, label %{advance}"
        ));
        self.start_block(&print);
        let is_first = self.temp();
        self.instruction(format!("{is_first} = load i1, ptr {first}, align 1"));
        let item = self.new_label("print.storage.pool.first");
        let separator = self.new_label("print.storage.pool.separator");
        self.terminate(format!(
            "br i1 {is_first}, label %{item}, label %{separator}"
        ));
        self.start_block(&separator);
        self.print_text(", ");
        self.terminate(format!("br label %{item}"));
        self.start_block(&item);
        self.instruction(format!("store i1 false, ptr {first}, align 1"));
        self.instruction(format!("call void @nl_print_long_raw(i64 {index})"));
        self.print_text(":");
        let generation_ptr = self.emit_pool_slot_ptr(ty, pointer, 3, &index);
        let generation32 = self.temp();
        self.instruction(format!(
            "{generation32} = load i32, ptr {generation_ptr}, align 1"
        ));
        let generation = self.temp();
        self.instruction(format!("{generation} = zext i32 {generation32} to i64"));
        self.instruction(format!("call void @nl_print_long_raw(i64 {generation})"));
        self.print_text(" => ");
        self.emit_print_pool_element_storage(ty, pointer, &index);
        self.terminate(format!("br label %{advance}"));
        self.start_block(&advance);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {counter}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
        self.print_text("}");
    }

    fn emit_print_function(&mut self, value: &str) {
        let unknown_id = self.print_ids["<unknown function>"];
        let mut name_pointer = format!(
            "getelementptr inbounds ([{} x i8], ptr @.nl.print.{unknown_id}, i64 0, i64 0)",
            "<unknown function>".len() + 1
        );
        for function in &self.program.functions {
            let Some(name_id) = self.print_ids.get(&function.name).copied() else {
                continue;
            };
            let name_pointer_for_function = format!(
                "getelementptr inbounds ([{} x i8], ptr @.nl.print.{name_id}, i64 0, i64 0)",
                function.name.len() + 1
            );
            let equal = self.temp();
            self.instruction(format!(
                "{equal} = icmp eq ptr {value}, @nl_fn_{}",
                function.id
            ));
            let selected = self.temp();
            self.instruction(format!(
                "{selected} = select i1 {equal}, ptr {name_pointer_for_function}, ptr {name_pointer}"
            ));
            name_pointer = selected;
        }
        self.instruction(format!("call void @nl_print_text(ptr {name_pointer})"));
    }

    fn emit_print_collection(&mut self, ty: Ty, value: &str) {
        let pointer = self.entry_alloca(ty);
        self.instruction(format!(
            "store {} {value}, ptr {pointer}, align 1",
            self.lltype(ty)
        ));
        let length = match self.program.types[ty.0].kind {
            TTypeKind::Array { capacity, .. } => capacity.to_string(),
            TTypeKind::List { .. } | TTypeKind::Queue { .. } | TTypeKind::Ring { .. } => {
                self.emit_collection_count(ty, &pointer)
            }
            _ => unreachable!(),
        };
        let element = match self.program.types[ty.0].kind {
            TTypeKind::Array { element, .. }
            | TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. } => element,
            _ => unreachable!(),
        };
        match self.program.types[ty.0].kind {
            TTypeKind::Queue { .. } => self.print_text("queue["),
            TTypeKind::Ring { .. } => self.print_text("ring["),
            _ => self.print_text("["),
        }
        let counter = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {counter}, align 1"));
        let cond = self.new_label("print.collection.cond");
        let body = self.new_label("print.collection.body");
        let done = self.new_label("print.collection.done");
        self.terminate(format!("br label %{cond}"));
        self.start_block(&cond);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {length}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
        self.start_block(&body);
        let first = self.temp();
        self.instruction(format!("{first} = icmp eq i64 {index}, 0"));
        let separator = self.new_label("print.collection.separator");
        let value_label = self.new_label("print.collection.value");
        self.terminate(format!(
            "br i1 {first}, label %{value_label}, label %{separator}"
        ));
        self.start_block(&separator);
        self.print_text(", ");
        self.terminate(format!("br label %{value_label}"));
        self.start_block(&value_label);
        let item = self.emit_collection_element(ty, &pointer, &index);
        self.emit_print_value(element, &item);
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {index}, 1"));
        self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
        self.terminate(format!("br label %{cond}"));
        self.start_block(&done);
        self.print_text("]");
    }

    fn emit_print_grid(&mut self, ty: Ty, value: &str) {
        let pointer = self.entry_alloca(ty);
        self.instruction(format!(
            "store {} {value}, ptr {pointer}, align 1",
            self.lltype(ty)
        ));
        let (element, width, height) = match self.program.types[ty.0].kind {
            TTypeKind::Grid {
                element,
                width,
                height,
                ..
            } => (element, width, height),
            _ => unreachable!(),
        };
        let y_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {y_ptr}, align 1"));
        let outer_cond = self.new_label("print.grid.outer.cond");
        let outer_body = self.new_label("print.grid.outer.body");
        let outer_done = self.new_label("print.grid.outer.done");
        self.print_text("[");
        self.terminate(format!("br label %{outer_cond}"));
        self.start_block(&outer_cond);
        let y = self.temp();
        self.instruction(format!("{y} = load i64, ptr {y_ptr}, align 1"));
        let more_rows = self.temp();
        self.instruction(format!("{more_rows} = icmp ult i64 {y}, {height}"));
        self.terminate(format!(
            "br i1 {more_rows}, label %{outer_body}, label %{outer_done}"
        ));
        self.start_block(&outer_body);
        let first_row = self.temp();
        self.instruction(format!("{first_row} = icmp eq i64 {y}, 0"));
        let row_separator = self.new_label("print.grid.row.separator");
        let row_start = self.new_label("print.grid.row.start");
        self.terminate(format!(
            "br i1 {first_row}, label %{row_start}, label %{row_separator}"
        ));
        self.start_block(&row_separator);
        self.print_text(", ");
        self.terminate(format!("br label %{row_start}"));
        self.start_block(&row_start);
        self.print_text("[");
        let x_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {x_ptr}, align 1"));
        let inner_cond = self.new_label("print.grid.inner.cond");
        let inner_body = self.new_label("print.grid.inner.body");
        let inner_done = self.new_label("print.grid.inner.done");
        self.terminate(format!("br label %{inner_cond}"));
        self.start_block(&inner_cond);
        let x = self.temp();
        self.instruction(format!("{x} = load i64, ptr {x_ptr}, align 1"));
        let more_cols = self.temp();
        self.instruction(format!("{more_cols} = icmp ult i64 {x}, {width}"));
        self.terminate(format!(
            "br i1 {more_cols}, label %{inner_body}, label %{inner_done}"
        ));
        self.start_block(&inner_body);
        let first_col = self.temp();
        self.instruction(format!("{first_col} = icmp eq i64 {x}, 0"));
        let item_separator = self.new_label("print.grid.item.separator");
        let item_start = self.new_label("print.grid.item.start");
        self.terminate(format!(
            "br i1 {first_col}, label %{item_start}, label %{item_separator}"
        ));
        self.start_block(&item_separator);
        self.print_text(", ");
        self.terminate(format!("br label %{item_start}"));
        self.start_block(&item_start);
        let row = self.temp();
        self.instruction(format!("{row} = mul i64 {y}, {width}"));
        let flat = self.temp();
        self.instruction(format!("{flat} = add i64 {row}, {x}"));
        let item = self.emit_collection_element(ty, &pointer, &flat);
        self.emit_print_value(element, &item);
        let next_x = self.temp();
        self.instruction(format!("{next_x} = add i64 {x}, 1"));
        self.instruction(format!("store i64 {next_x}, ptr {x_ptr}, align 1"));
        self.terminate(format!("br label %{inner_cond}"));
        self.start_block(&inner_done);
        self.print_text("]");
        let next_y = self.temp();
        self.instruction(format!("{next_y} = add i64 {y}, 1"));
        self.instruction(format!("store i64 {next_y}, ptr {y_ptr}, align 1"));
        self.terminate(format!("br label %{outer_cond}"));
        self.start_block(&outer_done);
        self.print_text("]");
    }

    fn emit_print_map_set(&mut self, ty: Ty, value: &str) {
        let pointer = self.entry_alloca(ty);
        self.instruction(format!(
            "store {} {value}, ptr {pointer}, align 1",
            self.lltype(ty)
        ));
        let capacity = match self.program.types[ty.0].kind {
            TTypeKind::Map { capacity, .. } | TTypeKind::Set { capacity, .. } => capacity,
            _ => unreachable!(),
        };
        let end_ptr = self.emit_map_meta_ptr(ty, &pointer, 1);
        let end = self.temp();
        self.instruction(format!("{end} = load i64, ptr {end_ptr}, align 1"));
        let counter = self.entry_alloca(Ty::Long);
        let first = self.entry_alloca(Ty::Bool);
        self.instruction(format!("store i64 0, ptr {counter}, align 1"));
        self.instruction(format!("store i1 true, ptr {first}, align 1"));
        let condition = self.new_label("print.map.cond");
        let inspect = self.new_label("print.map.inspect");
        let print = self.new_label("print.map.item");
        let advance = self.new_label("print.map.advance");
        let done = self.new_label("print.map.done");
        self.print_text("{");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {end}"));
        self.terminate(format!("br i1 {more}, label %{inspect}, label %{done}"));
        self.start_block(&inspect);
        let active_ptr = self.emit_map_array_ptr(ty, &pointer, 2, capacity, Ty::Bool, &index);
        let active = self.temp();
        self.instruction(format!("{active} = load i1, ptr {active_ptr}, align 1"));
        self.terminate(format!("br i1 {active}, label %{print}, label %{advance}"));
        self.start_block(&print);
        let is_first = self.temp();
        self.instruction(format!("{is_first} = load i1, ptr {first}, align 1"));
        let separator = self.new_label("print.map.separator");
        let item = self.new_label("print.map.item.value");
        self.terminate(format!(
            "br i1 {is_first}, label %{item}, label %{separator}"
        ));
        self.start_block(&separator);
        self.print_text(", ");
        self.terminate(format!("br label %{item}"));
        self.start_block(&item);
        self.instruction(format!("store i1 false, ptr {first}, align 1"));
        match self.program.types[ty.0].kind {
            TTypeKind::Map { key, value, .. } => {
                let key_ptr = self.emit_map_entry_ptr(ty, &pointer, &index, false);
                let key_value = self.temp();
                self.instruction(format!(
                    "{key_value} = load {}, ptr {key_ptr}, align 1",
                    self.lltype(key)
                ));
                self.emit_print_value(key, &key_value);
                self.print_text(": ");
                let item_value = self.emit_collection_element(ty, &pointer, &index);
                self.emit_print_value(value, &item_value);
            }
            TTypeKind::Set { key, .. } => {
                let key_ptr = self.emit_map_entry_ptr(ty, &pointer, &index, false);
                let key_value = self.temp();
                self.instruction(format!(
                    "{key_value} = load {}, ptr {key_ptr}, align 1",
                    self.lltype(key)
                ));
                self.emit_print_value(key, &key_value);
            }
            _ => unreachable!(),
        }
        self.terminate(format!("br label %{advance}"));
        self.start_block(&advance);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {counter}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
        self.print_text("}");
    }

    fn emit_print_pool(&mut self, ty: Ty, value: &str) {
        let pointer = self.entry_alloca(ty);
        self.instruction(format!(
            "store {} {value}, ptr {pointer}, align 1",
            self.lltype(ty)
        ));
        debug_assert!(matches!(
            self.program.types[ty.0].kind,
            TTypeKind::Pool { .. }
        ));
        let high_water_ptr = self.emit_pool_meta_ptr(ty, &pointer, 5);
        let high_water = self.temp();
        self.instruction(format!(
            "{high_water} = load i64, ptr {high_water_ptr}, align 1"
        ));
        self.print_text("pool{");
        let counter = self.entry_alloca(Ty::Long);
        let first = self.entry_alloca_raw("i1");
        self.instruction(format!("store i64 0, ptr {counter}, align 1"));
        self.instruction(format!("store i1 true, ptr {first}, align 1"));
        let cond = self.new_label("print.pool.cond");
        let body = self.new_label("print.pool.body");
        let print = self.new_label("print.pool.item");
        let advance = self.new_label("print.pool.advance");
        let done = self.new_label("print.pool.done");
        self.terminate(format!("br label %{cond}"));
        self.start_block(&cond);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {high_water}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
        self.start_block(&body);
        let occupied_ptr = self.emit_pool_slot_ptr(ty, &pointer, 2, &index);
        let occupied = self.temp();
        self.instruction(format!("{occupied} = load i1, ptr {occupied_ptr}, align 1"));
        self.terminate(format!(
            "br i1 {occupied}, label %{print}, label %{advance}"
        ));
        self.start_block(&print);
        let is_first = self.temp();
        self.instruction(format!("{is_first} = load i1, ptr {first}, align 1"));
        let separator = self.new_label("print.pool.separator");
        let item_label = self.new_label("print.pool.item.value");
        self.terminate(format!(
            "br i1 {is_first}, label %{item_label}, label %{separator}"
        ));
        self.start_block(&separator);
        self.print_text(", ");
        self.terminate(format!("br label %{item_label}"));
        self.start_block(&item_label);
        self.instruction(format!("store i1 false, ptr {first}, align 1"));
        self.instruction(format!("call void @nl_print_long_raw(i64 {index})"));
        self.print_text(":");
        let generation_ptr = self.emit_pool_slot_ptr(ty, &pointer, 3, &index);
        let generation = self.temp();
        self.instruction(format!(
            "{generation} = load i32, ptr {generation_ptr}, align 1"
        ));
        let generation64 = self.temp();
        self.instruction(format!("{generation64} = zext i32 {generation} to i64"));
        self.instruction(format!("call void @nl_print_long_raw(i64 {generation64})"));
        self.print_text(" => ");
        let item = self.emit_collection_element(ty, &pointer, &index);
        let element = match self.program.types[ty.0].kind {
            TTypeKind::Pool { element, .. } => element,
            _ => unreachable!(),
        };
        self.emit_print_value(element, &item);
        self.terminate(format!("br label %{advance}"));
        self.start_block(&advance);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {counter}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
        self.terminate(format!("br label %{cond}"));
        self.start_block(&done);
        self.print_text("}");
    }

    fn emit_method(&mut self, expr: &TExpr, kind: MethodKind, receiver: &TExpr) -> String {
        let value = self.emit_expr(receiver);
        if kind == MethodKind::AsciiLen {
            return self.ascii_field(&value, receiver.ty, 1);
        }
        if kind == MethodKind::TextLen {
            return self.ascii_field(&value, receiver.ty, 2);
        }
        if matches!(kind, MethodKind::TextByteLen | MethodKind::BytesLen) {
            return self.ascii_field(&value, receiver.ty, 1);
        }
        let tag = self.emit_tag(receiver.ty, &value);
        match kind {
            MethodKind::AsciiLen => unreachable!("Ascii length was handled above"),
            MethodKind::TextLen | MethodKind::TextByteLen | MethodKind::BytesLen => {
                unreachable!("string length was handled above")
            }
            MethodKind::IsNone | MethodKind::IsErr => {
                let result = self.temp();
                self.instruction(format!("{result} = icmp eq i32 {tag}, 1"));
                result
            }
            MethodKind::IsSome | MethodKind::IsOk => {
                let result = self.temp();
                self.instruction(format!("{result} = icmp eq i32 {tag}, 0"));
                result
            }
            MethodKind::UnwrapOption | MethodKind::UnwrapResult => {
                let success = self.temp();
                self.instruction(format!("{success} = icmp eq i32 {tag}, 0"));
                let bad = self.temp();
                self.instruction(format!("{bad} = xor i1 {success}, true"));
                self.guard(
                    bad,
                    if kind == MethodKind::UnwrapOption {
                        Failure::UnwrapNone
                    } else {
                        Failure::UnwrapErr
                    },
                    expr.span,
                );
                self.emit_payload(receiver.ty, &value, 0, 0).1
            }
            MethodKind::ResultOk => {
                let is_ok = self.temp();
                self.instruction(format!("{is_ok} = icmp eq i32 {tag}, 0"));
                let ok_label = self.new_label("result.ok");
                let err_label = self.new_label("result.err");
                let merge = self.new_label("result.ok.end");
                self.terminate(format!(
                    "br i1 {is_ok}, label %{ok_label}, label %{err_label}"
                ));
                self.start_block(&ok_label);
                let (payload_ty, payload) = self.emit_payload(receiver.ty, &value, 0, 0);
                let some = self.emit_construct_values(expr.ty, 0, vec![(payload_ty, payload)]);
                let ok_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&err_label);
                let none = self.emit_construct_values(expr.ty, 1, Vec::new());
                let err_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&merge);
                let result = self.temp();
                self.instruction(format!(
                    "{result} = phi {} [ {some}, %{ok_pred} ], [ {none}, %{err_pred} ]",
                    self.lltype(expr.ty)
                ));
                result
            }
        }
    }

    fn emit_method_to(
        &mut self,
        destination: &str,
        expr: &TExpr,
        kind: MethodKind,
        receiver: &TExpr,
    ) {
        let receiver_pointer = self.emit_expr_storage(receiver);
        if self.terminated {
            return;
        }
        let tag_pointer = self.temp();
        self.instruction(format!(
            "{tag_pointer} = getelementptr {}, ptr {receiver_pointer}, i32 0, i32 0",
            self.lltype(receiver.ty)
        ));
        let tag = self.temp();
        self.instruction(format!("{tag} = load i32, ptr {tag_pointer}, align 4"));
        match kind {
            MethodKind::UnwrapOption | MethodKind::UnwrapResult => {
                let success = self.temp();
                self.instruction(format!("{success} = icmp eq i32 {tag}, 0"));
                let bad = self.temp();
                self.instruction(format!("{bad} = xor i1 {success}, true"));
                self.guard(
                    bad,
                    if kind == MethodKind::UnwrapOption {
                        Failure::UnwrapNone
                    } else {
                        Failure::UnwrapErr
                    },
                    expr.span,
                );
                let payload = self.emit_sum_payload_pointer(receiver.ty, &receiver_pointer, 0, 0);
                self.emit_copy_value_storage(destination, &payload, expr.ty);
            }
            MethodKind::ResultOk => {
                let is_ok = self.temp();
                self.instruction(format!("{is_ok} = icmp eq i32 {tag}, 0"));
                let ok_label = self.new_label("result.ok.to");
                let err_label = self.new_label("result.err.to");
                let merge = self.new_label("result.ok.to.end");
                self.terminate(format!(
                    "br i1 {is_ok}, label %{ok_label}, label %{err_label}"
                ));
                self.start_block(&ok_label);
                let source = self.emit_sum_payload_pointer(receiver.ty, &receiver_pointer, 0, 0);
                let destination_payload = self.emit_sum_payload_pointer(expr.ty, destination, 0, 0);
                let ok_ty = self.program.types[receiver.ty.0].cases()[0].payload[0];
                self.emit_copy_value_storage(&destination_payload, &source, ok_ty);
                self.emit_sum_tag_to(expr.ty, destination, 0);
                self.terminate(format!("br label %{merge}"));
                self.start_block(&err_label);
                self.emit_sum_empty_case_to(expr.ty, destination, 1);
                self.terminate(format!("br label %{merge}"));
                self.start_block(&merge);
            }
            _ => unreachable!("only large-result methods require destination emission"),
        }
    }

    fn emit_optional_call(
        &mut self,
        expr: &TExpr,
        receiver: &TExpr,
        function_id: usize,
        args: &[TExpr],
        wraps_result: bool,
    ) -> String {
        let receiver_value = self.emit_expr(receiver);
        if self.terminated {
            return String::new();
        }
        let tag = self.emit_tag(receiver.ty, &receiver_value);
        let is_some = self.temp();
        self.instruction(format!("{is_some} = icmp eq i32 {tag}, 0"));
        let some_label = self.new_label("optional.some");
        let none_label = self.new_label("optional.none");
        let merge = self.new_label("optional.end");
        let saved_top = self.stack_top.clone();
        self.terminate(format!(
            "br i1 {is_some}, label %{some_label}, label %{none_label}"
        ));
        self.start_block(&none_label);
        let none = self.emit_construct_values(expr.ty, 1, Vec::new());
        let none_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&some_label);
        let (receiver_ty, receiver_arg) = self.emit_payload(receiver.ty, &receiver_value, 0, 0);
        let target = self.program.functions[function_id].clone();
        let signature = lower_signature(&target, &self.program.types);
        let mut lowered_args = vec!["ptr %nl.ctx".to_owned()];
        let result_storage = if signature.result_destination {
            let pointer = self.entry_alloca(target.result);
            lowered_args.push(format!("ptr {pointer}"));
            Some(pointer)
        } else {
            None
        };
        if signature.params[0].starts_with("ptr") {
            let pointer = self.entry_alloca(receiver_ty);
            self.instruction(format!(
                "store {} {receiver_arg}, ptr {pointer}, align 1",
                self.lltype(receiver_ty)
            ));
            lowered_args.push(format!("ptr {pointer}"));
        } else {
            lowered_args.push(format!("{} {receiver_arg}", signature.params[0]));
        }
        let mut regions = Vec::new();
        for (arg, param) in args.iter().zip(target.params.iter().skip(1)) {
            let Some(value) = self.emit_call_argument(arg, param.ty, param.mode, &mut regions)
            else {
                self.start_block(&merge);
                return none;
            };
            lowered_args.push(value);
        }
        lowered_args.insert(1, format!("ptr {}", self.stack_top));
        let call_args = lowered_args.join(", ");
        if target.recursive {
            self.emit_recursion_check(&[function_id], expr.span);
        }
        let function_result = if signature.result == "void" {
            self.instruction(format!("call void @nl_fn_{function_id}({call_args})"));
            if let Some(pointer) = result_storage {
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {pointer}, align 1",
                    self.lltype(target.result)
                ));
                value
            } else {
                String::new()
            }
        } else {
            let result = self.temp();
            self.instruction(format!(
                "{result} = call {} @nl_fn_{function_id}({call_args})",
                signature.result
            ));
            result
        };
        self.finish_call_argument_regions(&regions, &saved_top);
        let some = if wraps_result {
            self.emit_construct_values(expr.ty, 0, vec![(target.result, function_result)])
        } else {
            function_result
        };
        let some_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi {} [ {none}, %{none_pred} ], [ {some}, %{some_pred} ]",
            self.lltype(expr.ty)
        ));
        result
    }

    fn emit_optional_call_to(
        &mut self,
        destination: &str,
        expr: &TExpr,
        receiver: &TExpr,
        function_id: usize,
        args: &[TExpr],
        wraps_result: bool,
    ) {
        let receiver_pointer = self.emit_expr_storage(receiver);
        if self.terminated {
            return;
        }

        let receiver_tag = self.temp();
        self.instruction(format!(
            "{receiver_tag} = getelementptr {}, ptr {receiver_pointer}, i32 0, i32 0",
            self.lltype(receiver.ty)
        ));
        let tag = self.temp();
        self.instruction(format!("{tag} = load i32, ptr {receiver_tag}, align 4"));
        let is_some = self.temp();
        self.instruction(format!("{is_some} = icmp eq i32 {tag}, 0"));
        let some_label = self.new_label("optional.to.some");
        let none_label = self.new_label("optional.to.none");
        let merge = self.new_label("optional.to.end");
        let saved_top = self.stack_top.clone();
        self.terminate(format!(
            "br i1 {is_some}, label %{some_label}, label %{none_label}"
        ));

        self.start_block(&none_label);
        self.emit_sum_empty_case_to(expr.ty, destination, 1);
        self.restore_stack_top(&saved_top);
        self.terminate(format!("br label %{merge}"));

        self.stack_top = saved_top.clone();
        self.start_block(&some_label);

        let target = self.program.functions[function_id].clone();
        let signature = lower_signature(&target, &self.program.types);
        let mut lowered_args = vec!["ptr %nl.ctx".to_owned()];
        let result_destination = if signature.result_destination {
            if wraps_result {
                let payload = self.temp();
                self.instruction(format!(
                    "{payload} = getelementptr {}, ptr {destination}, i32 0, i32 1",
                    self.lltype(expr.ty)
                ));
                Some(payload)
            } else {
                Some(destination.to_owned())
            }
        } else {
            None
        };
        if let Some(pointer) = &result_destination {
            lowered_args.push(format!("ptr {pointer}"));
        }
        let (_, receiver_ty) = match &self.program.types[receiver.ty.0].kind {
            TTypeKind::Option(inner) => (receiver.ty, *inner),
            _ => unreachable!("typed optional calls have an Option receiver"),
        };
        let receiver_payload = self.temp();
        self.instruction(format!(
            "{receiver_payload} = getelementptr {}, ptr {receiver_pointer}, i32 0, i32 1",
            self.lltype(receiver.ty)
        ));
        if is_large_type(receiver_ty, &self.program.types) || self.is_pool_type(receiver_ty) {
            lowered_args.push(format!("ptr {receiver_payload}"));
        } else {
            let value = self.temp();
            self.instruction(format!(
                "{value} = load {}, ptr {receiver_payload}, align 1",
                self.lltype(receiver_ty)
            ));
            lowered_args.push(format!("{} {value}", signature.params[0]));
        }

        let mut regions = Vec::new();
        for (arg, param) in args.iter().zip(target.params.iter().skip(1)) {
            let Some(value) = self.emit_call_argument(arg, param.ty, param.mode, &mut regions)
            else {
                return;
            };
            lowered_args.push(value);
        }
        if self.terminated {
            return;
        }

        lowered_args.insert(1, format!("ptr {}", self.stack_top));
        let call_args = lowered_args.join(", ");
        if self.program.functions[function_id].recursive {
            self.emit_recursion_check(&[function_id], expr.span);
        }
        if signature.result_destination {
            self.instruction(format!("call void @nl_fn_{function_id}({call_args})"));
            if wraps_result {
                self.emit_sum_tag_to(expr.ty, destination, 0);
            }
        } else if signature.result != "void" {
            let value = self.temp();
            self.instruction(format!(
                "{value} = call {} @nl_fn_{function_id}({call_args})",
                signature.result
            ));
            if wraps_result {
                let payload = self.temp();
                self.instruction(format!(
                    "{payload} = getelementptr {}, ptr {destination}, i32 0, i32 1",
                    self.lltype(expr.ty)
                ));
                self.instruction(format!(
                    "store {} {value}, ptr {payload}, align 1",
                    self.lltype(target.result)
                ));
            } else {
                self.instruction(format!(
                    "store {} {value}, ptr {destination}, align 1",
                    self.lltype(target.result)
                ));
            }
            if wraps_result {
                self.emit_sum_tag_to(expr.ty, destination, 0);
            }
        }
        self.finish_call_argument_regions(&regions, &saved_top);
        self.restore_stack_top(&saved_top);
        self.terminate(format!("br label %{merge}"));

        self.stack_top = saved_top;
        self.start_block(&merge);
    }

    fn emit_try(
        &mut self,
        _expr: &TExpr,
        value: &TExpr,
        success_ty: Ty,
        error_ty: Option<Ty>,
        propagated_ty: Ty,
    ) -> String {
        let source_pointer = self.emit_expr_storage(value);
        if self.terminated {
            return String::new();
        }
        self.emit_try_from_storage(
            value.ty,
            success_ty,
            error_ty,
            propagated_ty,
            &source_pointer,
        )
    }

    fn emit_try_from_storage(
        &mut self,
        value_ty: Ty,
        success_ty: Ty,
        error_ty: Option<Ty>,
        propagated_ty: Ty,
        source_pointer: &str,
    ) -> String {
        let tag_pointer = self.temp();
        self.instruction(format!(
            "{tag_pointer} = getelementptr {}, ptr {source_pointer}, i32 0, i32 0",
            self.lltype(value_ty)
        ));
        let tag = self.temp();
        self.instruction(format!("{tag} = load i32, ptr {tag_pointer}, align 4"));
        let success = self.temp();
        self.instruction(format!("{success} = icmp eq i32 {tag}, 0"));
        let success_label = self.new_label("try.success");
        let failure_label = self.new_label("try.failure");
        let success_top = self.stack_top.clone();
        self.terminate(format!(
            "br i1 {success}, label %{success_label}, label %{failure_label}"
        ));
        self.start_block(&failure_label);
        if is_large_type(self.function.result, &self.program.types) {
            if let Some(err_ty) = error_ty {
                let source_payload = self.temp();
                self.instruction(format!(
                    "{source_payload} = getelementptr {}, ptr {source_pointer}, i32 0, i32 1",
                    self.lltype(value_ty)
                ));
                let result_payload = self.temp();
                self.instruction(format!(
                    "{result_payload} = getelementptr {}, ptr %nl.result, i32 0, i32 1",
                    self.lltype(self.function.result)
                ));
                if is_large_type(err_ty, &self.program.types) {
                    self.emit_copy_value_storage(&result_payload, &source_payload, err_ty);
                } else if err_ty != Ty::Unit {
                    let err = self.temp();
                    self.instruction(format!(
                        "{err} = load {}, ptr {source_payload}, align 1",
                        self.lltype(err_ty)
                    ));
                    self.instruction(format!(
                        "store {} {err}, ptr {result_payload}, align 1",
                        self.lltype(err_ty)
                    ));
                }
            }
            let result_tag = self.temp();
            self.instruction(format!(
                "{result_tag} = getelementptr {}, ptr %nl.result, i32 0, i32 0",
                self.lltype(self.function.result)
            ));
            self.instruction(format!("store i32 1, ptr {result_tag}, align 4"));
            self.emit_all_iteration_cleanups();
            self.terminate("ret void");
        } else {
            let propagated = if let Some(err_ty) = error_ty {
                let source_payload = self.temp();
                self.instruction(format!(
                    "{source_payload} = getelementptr {}, ptr {source_pointer}, i32 0, i32 1",
                    self.lltype(value_ty)
                ));
                let err = if err_ty == Ty::Unit {
                    String::new()
                } else {
                    let err = self.temp();
                    self.instruction(format!(
                        "{err} = load {}, ptr {source_payload}, align 1",
                        self.lltype(err_ty)
                    ));
                    err
                };
                self.emit_construct_values(propagated_ty, 1, vec![(err_ty, err)])
            } else {
                self.emit_construct_values(propagated_ty, 1, Vec::new())
            };
            self.emit_all_iteration_cleanups();
            self.terminate(format!("ret {} {propagated}", self.lltype(propagated_ty)));
        }
        self.stack_top = success_top;
        self.start_block(&success_label);
        if success_ty == Ty::Unit {
            String::new()
        } else {
            let source_payload = self.temp();
            self.instruction(format!(
                "{source_payload} = getelementptr {}, ptr {source_pointer}, i32 0, i32 1",
                self.lltype(value_ty)
            ));
            let result = self.temp();
            self.instruction(format!(
                "{result} = load {}, ptr {source_payload}, align 1",
                self.lltype(success_ty)
            ));
            result
        }
    }

    fn emit_try_to(
        &mut self,
        destination: &str,
        value: &TExpr,
        _success_ty: Ty,
        error_ty: Option<Ty>,
        propagated_ty: Ty,
    ) {
        let source_pointer = self.emit_expr_storage(value);
        if self.terminated {
            return;
        }
        let tag_pointer = self.temp();
        self.instruction(format!(
            "{tag_pointer} = getelementptr {}, ptr {source_pointer}, i32 0, i32 0",
            self.lltype(value.ty)
        ));
        let tag = self.temp();
        self.instruction(format!("{tag} = load i32, ptr {tag_pointer}, align 4"));
        let success = self.temp();
        self.instruction(format!("{success} = icmp eq i32 {tag}, 0"));
        let success_label = self.new_label("try.to.success");
        let failure_label = self.new_label("try.to.failure");
        let success_top = self.stack_top.clone();
        self.terminate(format!(
            "br i1 {success}, label %{success_label}, label %{failure_label}"
        ));
        self.start_block(&failure_label);
        if is_large_type(self.function.result, &self.program.types) {
            if let Some(err_ty) = error_ty {
                let source_payload = self.temp();
                self.instruction(format!(
                    "{source_payload} = getelementptr {}, ptr {source_pointer}, i32 0, i32 1",
                    self.lltype(value.ty)
                ));
                let result_payload = self.temp();
                self.instruction(format!(
                    "{result_payload} = getelementptr {}, ptr %nl.result, i32 0, i32 1",
                    self.lltype(self.function.result)
                ));
                if is_large_type(err_ty, &self.program.types) {
                    self.emit_copy_value_storage(&result_payload, &source_payload, err_ty);
                } else if err_ty != Ty::Unit {
                    let err = self.temp();
                    self.instruction(format!(
                        "{err} = load {}, ptr {source_payload}, align 1",
                        self.lltype(err_ty)
                    ));
                    self.instruction(format!(
                        "store {} {err}, ptr {result_payload}, align 1",
                        self.lltype(err_ty)
                    ));
                }
            }
            self.emit_sum_tag_to(self.function.result, "%nl.result", 1);
            self.emit_all_iteration_cleanups();
            self.terminate("ret void");
        } else {
            let propagated = if let Some(err_ty) = error_ty {
                let source_payload = self.temp();
                self.instruction(format!(
                    "{source_payload} = getelementptr {}, ptr {source_pointer}, i32 0, i32 1",
                    self.lltype(value.ty)
                ));
                let err = if err_ty == Ty::Unit {
                    String::new()
                } else {
                    let err = self.temp();
                    self.instruction(format!(
                        "{err} = load {}, ptr {source_payload}, align 1",
                        self.lltype(err_ty)
                    ));
                    err
                };
                self.emit_construct_values(propagated_ty, 1, vec![(err_ty, err)])
            } else {
                self.emit_construct_values(propagated_ty, 1, Vec::new())
            };
            self.emit_all_iteration_cleanups();
            self.terminate(format!("ret {} {propagated}", self.lltype(propagated_ty)));
        }
        self.stack_top = success_top;
        self.start_block(&success_label);
        let source_payload = self.temp();
        self.instruction(format!(
            "{source_payload} = getelementptr {}, ptr {source_pointer}, i32 0, i32 1",
            self.lltype(value.ty)
        ));
        if is_large_type(_success_ty, &self.program.types) {
            self.emit_copy_value_storage(destination, &source_payload, _success_ty);
        } else if _success_ty != Ty::Unit {
            let result = self.temp();
            self.instruction(format!(
                "{result} = load {}, ptr {source_payload}, align 1",
                self.lltype(_success_ty)
            ));
            self.instruction(format!(
                "store {} {result}, ptr {destination}, align 1",
                self.lltype(_success_ty)
            ));
        }
    }

    fn emit_coalesce(&mut self, expr: &TExpr, option: &TExpr, fallback: &TExpr) -> String {
        let option_value = self.emit_expr(option);
        let tag = self.emit_tag(option.ty, &option_value);
        let is_some = self.temp();
        self.instruction(format!("{is_some} = icmp eq i32 {tag}, 0"));
        let some_label = self.new_label("coalesce.some");
        let fallback_label = self.new_label("coalesce.fallback");
        let merge = self.new_label("coalesce.end");
        self.terminate(format!(
            "br i1 {is_some}, label %{some_label}, label %{fallback_label}"
        ));
        self.start_block(&some_label);
        let some = self.emit_payload(option.ty, &option_value, 0, 0).1;
        let some_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&fallback_label);
        let fallback_value = self.emit_expr(fallback);
        let fallback_live = !self.terminated;
        let fallback_pred = self.current_label.clone();
        if fallback_live {
            self.terminate(format!("br label %{merge}"));
        }
        self.start_block(&merge);
        if expr.ty == Ty::Unit {
            return String::new();
        }
        if fallback_live {
            let result = self.temp();
            self.instruction(format!("{result} = phi {} [ {some}, %{some_pred} ], [ {fallback_value}, %{fallback_pred} ]", self.lltype(expr.ty)));
            result
        } else {
            some
        }
    }

    fn emit_coalesce_to(
        &mut self,
        destination: &str,
        expr: &TExpr,
        option: &TExpr,
        fallback: &TExpr,
    ) {
        let option_pointer = self.emit_expr_storage(option);
        if self.terminated {
            return;
        }
        let tag_pointer = self.temp();
        self.instruction(format!(
            "{tag_pointer} = getelementptr {}, ptr {option_pointer}, i32 0, i32 0",
            self.lltype(option.ty)
        ));
        let tag = self.temp();
        self.instruction(format!("{tag} = load i32, ptr {tag_pointer}, align 4"));
        let is_some = self.temp();
        self.instruction(format!("{is_some} = icmp eq i32 {tag}, 0"));
        let some_label = self.new_label("coalesce.to.some");
        let fallback_label = self.new_label("coalesce.to.fallback");
        let merge = self.new_label("coalesce.to.end");
        let saved_top = self.stack_top.clone();
        self.terminate(format!(
            "br i1 {is_some}, label %{some_label}, label %{fallback_label}"
        ));
        self.start_block(&some_label);
        let payload = self.temp();
        self.instruction(format!(
            "{payload} = getelementptr {}, ptr {option_pointer}, i32 0, i32 1",
            self.lltype(option.ty)
        ));
        self.emit_copy_value_storage(destination, &payload, expr.ty);
        self.restore_stack_top(&saved_top);
        self.terminate(format!("br label %{merge}"));
        self.stack_top = saved_top.clone();
        self.start_block(&fallback_label);
        self.emit_expr_to(destination, fallback);
        if !self.terminated {
            self.restore_stack_top(&saved_top);
            self.terminate(format!("br label %{merge}"));
        }
        self.stack_top = saved_top;
        self.start_block(&merge);
    }

    fn emit_match(
        &mut self,
        expr: &TExpr,
        scrutinee: &TExpr,
        arms: &[TMatchArm],
        destination: Option<&str>,
    ) -> String {
        let scrutinee_pointer = if is_large_type(scrutinee.ty, &self.program.types) {
            Some(self.emit_expr_storage(scrutinee))
        } else {
            None
        };
        if self.terminated {
            return String::new();
        }
        let value = if scrutinee_pointer.is_none() {
            self.emit_expr(scrutinee)
        } else {
            String::new()
        };
        if self.terminated {
            return String::new();
        }
        let tag = if self.program.types[scrutinee.ty.0].is_sum() {
            if let Some(pointer) = &scrutinee_pointer {
                let tag_pointer = self.temp();
                self.instruction(format!(
                    "{tag_pointer} = getelementptr {}, ptr {pointer}, i32 0, i32 0",
                    self.lltype(scrutinee.ty)
                ));
                let tag = self.temp();
                self.instruction(format!("{tag} = load i32, ptr {tag_pointer}, align 4"));
                Some(tag)
            } else {
                Some(self.emit_tag(scrutinee.ty, &value))
            }
        } else {
            None
        };
        let merge = self.new_label("match.end");
        let mut arm_labels = Vec::new();
        for arm in arms {
            let arm_label = self.new_label("match.arm");
            arm_labels.push(arm_label.clone());
            match &arm.pattern {
                TPattern::Wildcard => self.terminate(format!("br label %{arm_label}")),
                TPattern::Integer(literal) => {
                    let condition = self.temp();
                    self.instruction(format!(
                        "{condition} = icmp eq {} {value}, {literal}",
                        self.lltype(scrutinee.ty)
                    ));
                    let next = self.new_label("match.next");
                    self.terminate(format!(
                        "br i1 {condition}, label %{arm_label}, label %{next}"
                    ));
                    self.start_block(&next);
                }
                TPattern::Bool(literal) => {
                    let condition = self.temp();
                    self.instruction(format!("{condition} = icmp eq i1 {value}, {literal}"));
                    let next = self.new_label("match.next");
                    self.terminate(format!(
                        "br i1 {condition}, label %{arm_label}, label %{next}"
                    ));
                    self.start_block(&next);
                }
                TPattern::Case { case_index, .. } => {
                    let condition = self.temp();
                    self.instruction(format!(
                        "{condition} = icmp eq i32 {}, {case_index}",
                        tag.as_ref().unwrap()
                    ));
                    let next = self.new_label("match.next");
                    self.terminate(format!(
                        "br i1 {condition}, label %{arm_label}, label %{next}"
                    ));
                    self.start_block(&next);
                }
            }
        }
        if !self.terminated {
            self.terminate("unreachable");
        }

        let mut incoming = Vec::<(String, String)>::new();
        for (arm, label) in arms.iter().zip(arm_labels.iter()) {
            self.start_block(label);
            let arm_saved_top = self.stack_top.clone();
            if let TPattern::Case {
                ty,
                case_index,
                bindings,
            } = &arm.pattern
            {
                let mut payload_pointer = None;
                if let Some(pointer) = &scrutinee_pointer {
                    let payload = self.temp();
                    self.instruction(format!(
                        "{payload} = getelementptr {}, ptr {pointer}, i32 0, i32 1",
                        self.lltype(*ty)
                    ));
                    payload_pointer = Some(payload);
                }
                let case_payload = self.program.types[ty.0].cases()[*case_index]
                    .payload
                    .clone();
                let mut offset = 0usize;
                for (index, id) in bindings.iter().enumerate() {
                    if let Some(id) = id {
                        let field_ty = case_payload[index];
                        if let Some(payload) = &payload_pointer {
                            let field_pointer = self.temp();
                            self.instruction(format!(
                                "{field_pointer} = getelementptr i8, ptr {payload}, i64 {offset}"
                            ));
                            if is_large_type(field_ty, &self.program.types) {
                                let pointer = self.emit_runtime_region_alloc(
                                    field_ty,
                                    arm.body.span,
                                    Some(format!("%local.{id}")),
                                );
                                self.emit_copy_value_storage(&pointer, &field_pointer, field_ty);
                            } else if field_ty != Ty::Unit {
                                let field = self.temp();
                                self.instruction(format!(
                                    "{field} = load {}, ptr {field_pointer}, align 1",
                                    self.lltype(field_ty)
                                ));
                                self.instruction(format!(
                                    "store {} {field}, ptr %local.{id}, align 1",
                                    self.lltype(field_ty)
                                ));
                            }
                        } else {
                            let (field_ty, field) =
                                self.emit_payload(*ty, &value, *case_index, index);
                            if is_large_type(field_ty, &self.program.types) {
                                let pointer = self.emit_runtime_region_alloc(
                                    field_ty,
                                    arm.body.span,
                                    Some(format!("%local.{id}")),
                                );
                                self.instruction(format!(
                                    "store {} {field}, ptr {pointer}, align 1",
                                    self.lltype(field_ty)
                                ));
                            } else if field_ty != Ty::Unit {
                                self.instruction(format!(
                                    "store {} {field}, ptr %local.{id}",
                                    self.lltype(field_ty)
                                ));
                            }
                        }
                    }
                    offset += type_size(
                        case_payload[index],
                        &self.program.types,
                        &mut vec![None; self.program.types.len()],
                    );
                }
            }
            let arm_value = if let Some(destination) = destination {
                self.emit_block_contents(&arm.body);
                if !self.terminated {
                    if let Some(tail) = arm.body.tail.as_deref() {
                        self.emit_expr_to(destination, tail);
                    }
                }
                if self.terminated {
                    None
                } else {
                    self.restore_stack_top(&arm_saved_top);
                    Some(String::new())
                }
            } else {
                self.emit_branch_block(&arm.body, &merge)
            };
            if !self.terminated {
                self.restore_stack_top(&arm_saved_top);
                let predecessor = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                incoming.push((arm_value.unwrap_or_default(), predecessor));
            }
            self.stack_top = arm_saved_top;
        }
        if incoming.is_empty() {
            self.terminated = true;
            String::new()
        } else {
            self.start_block(&merge);
            if destination.is_some() {
                return String::new();
            }
            if expr.ty == Ty::Unit {
                return String::new();
            }
            if incoming.len() == 1 {
                return incoming.pop().unwrap().0;
            }
            let result = self.temp();
            let values = incoming
                .iter()
                .map(|(value, pred)| format!("[ {value}, %{pred} ]"))
                .collect::<Vec<_>>()
                .join(", ");
            self.instruction(format!("{result} = phi {} {values}", self.lltype(expr.ty)));
            result
        }
    }

    fn emit_structural_equal(&mut self, ty: Ty, left: &str, right: &str) -> String {
        if matches!(
            self.program.types[ty.0].kind,
            TTypeKind::Map { .. } | TTypeKind::Set { .. }
        ) {
            return self.emit_map_set_equal(ty, left, right);
        }
        if matches!(
            self.program.types[ty.0].kind,
            TTypeKind::Array { .. }
                | TTypeKind::List { .. }
                | TTypeKind::Queue { .. }
                | TTypeKind::Ring { .. }
                | TTypeKind::Grid { .. }
                | TTypeKind::Pool { .. }
        ) {
            if matches!(self.program.types[ty.0].kind, TTypeKind::Pool { .. }) {
                return self.emit_pool_equal(ty, left, right);
            }
            return self.emit_collection_equal(ty, left, right);
        }
        if let TTypeKind::Struct(fields) = &self.program.types[ty.0].kind {
            let fields = fields.clone();
            let mut equal = "true".to_owned();
            for (index, field) in fields.iter().enumerate() {
                if field.ty == Ty::Unit {
                    continue;
                }
                let lhs = self.temp();
                let rhs = self.temp();
                self.instruction(format!(
                    "{lhs} = extractvalue {} {left}, {index}",
                    self.lltype(ty)
                ));
                self.instruction(format!(
                    "{rhs} = extractvalue {} {right}, {index}",
                    self.lltype(ty)
                ));
                let field_equal =
                    self.emit_binary(BinaryOp::Eq, field.ty, &lhs, &rhs, Span::default());
                let next = self.temp();
                self.instruction(format!("{next} = and i1 {equal}, {field_equal}"));
                equal = next;
            }
            return equal;
        }
        let left_tag = self.emit_tag(ty, left);
        let right_tag = self.emit_tag(ty, right);
        let same_tag = self.temp();
        self.instruction(format!("{same_tag} = icmp eq i32 {left_tag}, {right_tag}"));
        let dispatch = self.new_label("eq.dispatch");
        let unequal = self.new_label("eq.unequal");
        let merge = self.new_label("eq.end");
        self.terminate(format!(
            "br i1 {same_tag}, label %{dispatch}, label %{unequal}"
        ));
        self.start_block(&unequal);
        let unequal_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));

        let cases = self.program.types[ty.0].cases();
        let labels = (0..cases.len())
            .map(|_| self.new_label("eq.case"))
            .collect::<Vec<_>>();
        let invalid = self.new_label("eq.invalid");
        self.start_block(&dispatch);
        let switch_cases = labels
            .iter()
            .enumerate()
            .map(|(index, label)| format!("i32 {index}, label %{label}"))
            .collect::<Vec<_>>()
            .join(" ");
        self.terminate(format!(
            "switch i32 {left_tag}, label %{invalid} [ {switch_cases} ]"
        ));
        self.start_block(&invalid);
        self.terminate("unreachable");

        let mut incoming = vec![("false".to_owned(), unequal_pred)];
        for (case_index, case) in cases.iter().enumerate() {
            self.start_block(&labels[case_index]);
            let mut equal = "true".to_owned();
            for field_index in 0..case.payload.len() {
                let field_ty = case.payload[field_index];
                if field_ty == Ty::Unit {
                    continue;
                }
                let left_field = self.emit_payload(ty, left, case_index, field_index).1;
                let right_field = self.emit_payload(ty, right, case_index, field_index).1;
                let field_equal = self.emit_binary(
                    BinaryOp::Eq,
                    field_ty,
                    &left_field,
                    &right_field,
                    Span::default(),
                );
                let next_equal = self.temp();
                self.instruction(format!("{next_equal} = and i1 {equal}, {field_equal}"));
                equal = next_equal;
            }
            let predecessor = self.current_label.clone();
            self.terminate(format!("br label %{merge}"));
            incoming.push((equal, predecessor));
        }
        self.start_block(&merge);
        let result = self.temp();
        let values = incoming
            .iter()
            .map(|(value, pred)| format!("[ {value}, %{pred} ]"))
            .collect::<Vec<_>>()
            .join(", ");
        self.instruction(format!("{result} = phi i1 {values}"));
        result
    }

    fn emit_equal_storage(&mut self, ty: Ty, left: &str, right: &str) -> String {
        match self.program.types[ty.0].kind.clone() {
            TTypeKind::Refinement { base, .. } => self.emit_equal_storage(base, left, right),
            TTypeKind::Struct(fields) => {
                let mut equal = "true".to_owned();
                for (index, field) in fields.iter().enumerate() {
                    if field.ty == Ty::Unit {
                        continue;
                    }
                    let left_field = self.temp();
                    let right_field = self.temp();
                    self.instruction(format!(
                        "{left_field} = getelementptr inbounds {}, ptr {left}, i32 0, i32 {index}",
                        self.lltype(ty)
                    ));
                    self.instruction(format!(
                        "{right_field} = getelementptr inbounds {}, ptr {right}, i32 0, i32 {index}",
                        self.lltype(ty)
                    ));
                    let field_equal = self.emit_equal_storage(field.ty, &left_field, &right_field);
                    let next = self.temp();
                    self.instruction(format!("{next} = and i1 {equal}, {field_equal}"));
                    equal = next;
                }
                equal
            }
            TTypeKind::Array { capacity, .. } | TTypeKind::Grid { capacity, .. } => {
                self.emit_equal_sequence_storage(ty, left, right, capacity.to_string(), false)
            }
            TTypeKind::List { .. } | TTypeKind::Queue { .. } | TTypeKind::Ring { .. } => {
                let left_length = self.emit_collection_count(ty, left);
                self.emit_equal_sequence_storage(ty, left, right, left_length, true)
            }
            TTypeKind::Map { .. } | TTypeKind::Set { .. } => {
                self.emit_map_set_equal_storage(ty, left, right)
            }
            TTypeKind::Pool { .. } => self.emit_pool_equal_storage(ty, left, right),
            TTypeKind::Option(_) | TTypeKind::Result(..) | TTypeKind::Enum(_) => {
                self.emit_sum_equal_storage(ty, left, right)
            }
            TTypeKind::Ascii { .. } => {
                let left_value = self.temp();
                let right_value = self.temp();
                self.instruction(format!(
                    "{left_value} = load {}, ptr {left}, align 1",
                    self.lltype(ty)
                ));
                self.instruction(format!(
                    "{right_value} = load {}, ptr {right}, align 1",
                    self.lltype(ty)
                ));
                self.emit_binary(BinaryOp::Eq, ty, &left_value, &right_value, Span::default())
            }
            TTypeKind::Unit | TTypeKind::Never => "true".to_owned(),
            _ => {
                let left_value = self.temp();
                let right_value = self.temp();
                self.instruction(format!(
                    "{left_value} = load {}, ptr {left}, align 1",
                    self.lltype(ty)
                ));
                self.instruction(format!(
                    "{right_value} = load {}, ptr {right}, align 1",
                    self.lltype(ty)
                ));
                self.emit_binary(BinaryOp::Eq, ty, &left_value, &right_value, Span::default())
            }
        }
    }

    fn emit_equal_collection_elements(
        &mut self,
        collection_ty: Ty,
        left: &str,
        left_index: &str,
        right: &str,
        right_index: &str,
    ) -> String {
        let element = collection_element_type(collection_ty, &self.program.types);
        let left_index = if matches!(
            self.program.types[collection_ty.0].kind,
            TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
        ) {
            self.emit_queue_ring_physical_index(collection_ty, left, left_index)
        } else {
            left_index.to_owned()
        };
        let right_index = if matches!(
            self.program.types[collection_ty.0].kind,
            TTypeKind::Queue { .. } | TTypeKind::Ring { .. }
        ) {
            self.emit_queue_ring_physical_index(collection_ty, right, right_index)
        } else {
            right_index.to_owned()
        };
        if let TTypeKind::Struct(fields) = self.program.types[element.0].kind.clone() {
            let mut equal = "true".to_owned();
            for (lane, field) in fields.iter().enumerate() {
                if field.ty == Ty::Unit {
                    continue;
                }
                let left_field =
                    self.emit_collection_lane_pointer(collection_ty, left, &left_index, lane);
                let right_field =
                    self.emit_collection_lane_pointer(collection_ty, right, &right_index, lane);
                let field_equal = self.emit_equal_storage(field.ty, &left_field, &right_field);
                let next = self.temp();
                self.instruction(format!("{next} = and i1 {equal}, {field_equal}"));
                equal = next;
            }
            equal
        } else {
            let left_element =
                self.emit_collection_lane_pointer(collection_ty, left, &left_index, 0);
            let right_element =
                self.emit_collection_lane_pointer(collection_ty, right, &right_index, 0);
            self.emit_equal_storage(element, &left_element, &right_element)
        }
    }

    fn emit_equal_sequence_storage(
        &mut self,
        collection_ty: Ty,
        left: &str,
        right: &str,
        length: String,
        _dynamic: bool,
    ) -> String {
        let counter = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {counter}, align 1"));
        let condition = self.new_label("equal.sequence.cond");
        let body = self.new_label("equal.sequence.body");
        let next_label = self.new_label("equal.sequence.next");
        let yes = self.new_label("equal.sequence.true");
        let no = self.new_label("equal.sequence.false");
        let merge = self.new_label("equal.sequence.end");
        if _dynamic {
            let left_length = self.emit_collection_count(collection_ty, left);
            let right_length = self.emit_collection_count(collection_ty, right);
            let same_length = self.temp();
            self.instruction(format!(
                "{same_length} = icmp eq i64 {left_length}, {right_length}"
            ));
            self.terminate(format!(
                "br i1 {same_length}, label %{condition}, label %{no}"
            ));
        } else {
            self.terminate(format!("br label %{condition}"));
        }
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {length}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{yes}"));
        self.start_block(&body);
        let equal = self.emit_equal_collection_elements(collection_ty, left, &index, right, &index);
        self.terminate(format!("br i1 {equal}, label %{next_label}, label %{no}"));
        self.start_block(&next_label);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {counter}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&yes);
        let yes_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&no);
        let no_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi i1 [ true, %{yes_pred} ], [ false, %{no_pred} ]"
        ));
        result
    }

    fn emit_sum_equal_storage(&mut self, ty: Ty, left: &str, right: &str) -> String {
        let left_tag_ptr = self.temp();
        let right_tag_ptr = self.temp();
        self.instruction(format!(
            "{left_tag_ptr} = getelementptr {}, ptr {left}, i32 0, i32 0",
            self.lltype(ty)
        ));
        self.instruction(format!(
            "{right_tag_ptr} = getelementptr {}, ptr {right}, i32 0, i32 0",
            self.lltype(ty)
        ));
        let left_tag = self.temp();
        let right_tag = self.temp();
        self.instruction(format!(
            "{left_tag} = load i32, ptr {left_tag_ptr}, align 4"
        ));
        self.instruction(format!(
            "{right_tag} = load i32, ptr {right_tag_ptr}, align 4"
        ));
        let same_tag = self.temp();
        self.instruction(format!("{same_tag} = icmp eq i32 {left_tag}, {right_tag}"));
        let dispatch = self.new_label("equal.sum.dispatch");
        let mismatch = self.new_label("equal.sum.mismatch");
        let merge = self.new_label("equal.sum.end");
        self.terminate(format!(
            "br i1 {same_tag}, label %{dispatch}, label %{mismatch}"
        ));
        self.start_block(&mismatch);
        let mismatch_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        let cases = self.program.types[ty.0].cases().to_vec();
        let labels = (0..cases.len())
            .map(|_| self.new_label("equal.sum.case"))
            .collect::<Vec<_>>();
        let invalid = self.new_label("equal.sum.invalid");
        self.start_block(&dispatch);
        let switch = labels
            .iter()
            .enumerate()
            .map(|(index, label)| format!("i32 {index}, label %{label}"))
            .collect::<Vec<_>>()
            .join(" ");
        self.terminate(format!(
            "switch i32 {left_tag}, label %{invalid} [ {switch} ]"
        ));
        self.start_block(&invalid);
        self.terminate("unreachable");
        let mut incoming = vec![("false".to_owned(), mismatch_pred)];
        for (case_index, case) in cases.iter().enumerate() {
            self.start_block(&labels[case_index]);
            let mut equal = "true".to_owned();
            for (field_index, field_ty) in case.payload.iter().enumerate() {
                if *field_ty == Ty::Unit {
                    continue;
                }
                let left_field = self.emit_sum_payload_pointer(ty, left, case_index, field_index);
                let right_field = self.emit_sum_payload_pointer(ty, right, case_index, field_index);
                let field_equal = self.emit_equal_storage(*field_ty, &left_field, &right_field);
                let next = self.temp();
                self.instruction(format!("{next} = and i1 {equal}, {field_equal}"));
                equal = next;
            }
            let predecessor = self.current_label.clone();
            self.terminate(format!("br label %{merge}"));
            incoming.push((equal, predecessor));
        }
        self.start_block(&merge);
        let result = self.temp();
        let incoming = incoming
            .iter()
            .map(|(value, predecessor)| format!("[ {value}, %{predecessor} ]"))
            .collect::<Vec<_>>()
            .join(", ");
        self.instruction(format!("{result} = phi i1 {incoming}"));
        result
    }

    fn emit_map_set_equal_storage(&mut self, ty: Ty, left: &str, right: &str) -> String {
        let (capacity, key_ty, value_ty) = match self.program.types[ty.0].kind {
            TTypeKind::Map {
                key,
                value,
                capacity,
            } => (capacity, key, Some(value)),
            TTypeKind::Set { key, capacity } => (capacity, key, None),
            _ => unreachable!(),
        };
        let left_count = self.temp();
        let right_count = self.temp();
        let left_count_ptr = self.emit_map_meta_ptr(ty, left, 0);
        let right_count_ptr = self.emit_map_meta_ptr(ty, right, 0);
        self.instruction(format!(
            "{left_count} = load i64, ptr {left_count_ptr}, align 1"
        ));
        self.instruction(format!(
            "{right_count} = load i64, ptr {right_count_ptr}, align 1"
        ));
        let counts_equal = self.temp();
        self.instruction(format!(
            "{counts_equal} = icmp eq i64 {left_count}, {right_count}"
        ));
        let result_ptr = self.entry_alloca(Ty::Bool);
        self.instruction(format!(
            "store i1 {counts_equal}, ptr {result_ptr}, align 1"
        ));
        let left_end_ptr = self.emit_map_meta_ptr(ty, left, 1);
        let left_end = self.temp();
        self.instruction(format!(
            "{left_end} = load i64, ptr {left_end_ptr}, align 1"
        ));
        let index_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {index_ptr}, align 1"));
        let condition = self.new_label("equal.map.cond");
        let inspect = self.new_label("equal.map.inspect");
        let compare = self.new_label("equal.map.compare");
        let skip = self.new_label("equal.map.skip");
        let done = self.new_label("equal.map.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {index_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {left_end}"));
        self.terminate(format!("br i1 {more}, label %{inspect}, label %{done}"));
        self.start_block(&inspect);
        let active_ptr = self.emit_map_array_ptr(ty, left, 2, capacity, Ty::Bool, &index);
        let active = self.temp();
        self.instruction(format!("{active} = load i1, ptr {active_ptr}, align 1"));
        self.terminate(format!("br i1 {active}, label %{compare}, label %{skip}"));
        self.start_block(&compare);
        let key_ptr = self.emit_map_entry_ptr(ty, left, &index, false);
        let key = self.temp();
        self.instruction(format!(
            "{key} = load {}, ptr {key_ptr}, align 1",
            self.lltype(key_ty)
        ));
        let (found_entry, _, _) = self.emit_map_lookup(ty, right, key_ty, &key, capacity);
        let found = self.temp();
        self.instruction(format!("{found} = icmp sge i64 {found_entry}, 0"));
        let matched = if let Some(value_ty) = value_ty {
            let value_label = self.new_label("equal.map.value");
            let missing_label = self.new_label("equal.map.missing");
            let value_merge = self.new_label("equal.map.value.end");
            self.terminate(format!(
                "br i1 {found}, label %{value_label}, label %{missing_label}"
            ));
            self.start_block(&missing_label);
            let missing_pred = self.current_label.clone();
            self.terminate(format!("br label %{value_merge}"));
            self.start_block(&value_label);
            let left_value = self.emit_map_entry_ptr(ty, left, &index, true);
            let right_value = self.emit_map_entry_ptr(ty, right, &found_entry, true);
            let equal = self.emit_equal_storage(value_ty, &left_value, &right_value);
            let equal_pred = self.current_label.clone();
            self.terminate(format!("br label %{value_merge}"));
            self.start_block(&value_merge);
            let result = self.temp();
            self.instruction(format!(
                "{result} = phi i1 [ false, %{missing_pred} ], [ {equal}, %{equal_pred} ]"
            ));
            result
        } else {
            found
        };
        let previous = self.temp();
        self.instruction(format!("{previous} = load i1, ptr {result_ptr}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = and i1 {previous}, {matched}"));
        self.instruction(format!("store i1 {next}, ptr {result_ptr}, align 1"));
        self.terminate(format!("br label %{skip}"));
        self.start_block(&skip);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {index_ptr}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {index_ptr}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
        let result = self.temp();
        self.instruction(format!("{result} = load i1, ptr {result_ptr}, align 1"));
        result
    }

    fn emit_pool_occupied_if_initialized(
        &mut self,
        ty: Ty,
        pointer: &str,
        index: &str,
        high_water: &str,
    ) -> String {
        let within = self.temp();
        self.instruction(format!("{within} = icmp ult i64 {index}, {high_water}"));
        let load_label = self.new_label("equal.pool.occupied.load");
        let empty_label = self.new_label("equal.pool.occupied.empty");
        let merge = self.new_label("equal.pool.occupied.end");
        self.terminate(format!(
            "br i1 {within}, label %{load_label}, label %{empty_label}"
        ));
        self.start_block(&load_label);
        let occupied_ptr = self.emit_pool_slot_ptr(ty, pointer, 2, index);
        let occupied = self.temp();
        self.instruction(format!("{occupied} = load i1, ptr {occupied_ptr}, align 1"));
        let occupied_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&empty_label);
        let empty_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi i1 [ {occupied}, %{occupied_pred} ], [ false, %{empty_pred} ]"
        ));
        result
    }

    fn emit_equal_pool_elements(&mut self, ty: Ty, left: &str, right: &str, index: &str) -> String {
        let element = match self.program.types[ty.0].kind {
            TTypeKind::Pool { element, .. } => element,
            _ => unreachable!(),
        };
        if let TTypeKind::Struct(fields) = self.program.types[element.0].kind.clone() {
            let mut equal = "true".to_owned();
            for (lane, field) in fields.iter().enumerate() {
                if field.ty == Ty::Unit {
                    continue;
                }
                let left_field = self.emit_collection_lane_pointer(ty, left, index, lane);
                let right_field = self.emit_collection_lane_pointer(ty, right, index, lane);
                let field_equal = self.emit_equal_storage(field.ty, &left_field, &right_field);
                let next = self.temp();
                self.instruction(format!("{next} = and i1 {equal}, {field_equal}"));
                equal = next;
            }
            equal
        } else {
            let left_element = self.emit_collection_lane_pointer(ty, left, index, 0);
            let right_element = self.emit_collection_lane_pointer(ty, right, index, 0);
            self.emit_equal_storage(element, &left_element, &right_element)
        }
    }

    fn emit_pool_equal_storage(&mut self, ty: Ty, left: &str, right: &str) -> String {
        let capacity = match self.program.types[ty.0].kind {
            TTypeKind::Pool { capacity, .. } => capacity,
            _ => unreachable!(),
        };
        let left_active_ptr = self.emit_pool_meta_ptr(ty, left, 0);
        let right_active_ptr = self.emit_pool_meta_ptr(ty, right, 0);
        let left_active = self.temp();
        let right_active = self.temp();
        self.instruction(format!(
            "{left_active} = load i64, ptr {left_active_ptr}, align 1"
        ));
        self.instruction(format!(
            "{right_active} = load i64, ptr {right_active_ptr}, align 1"
        ));
        let counts_equal = self.temp();
        self.instruction(format!(
            "{counts_equal} = icmp eq i64 {left_active}, {right_active}"
        ));
        let left_hw_ptr = self.emit_pool_meta_ptr(ty, left, 5);
        let right_hw_ptr = self.emit_pool_meta_ptr(ty, right, 5);
        let left_hw = self.temp();
        let right_hw = self.temp();
        self.instruction(format!("{left_hw} = load i64, ptr {left_hw_ptr}, align 1"));
        self.instruction(format!(
            "{right_hw} = load i64, ptr {right_hw_ptr}, align 1"
        ));
        let index_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {index_ptr}, align 1"));
        let condition = self.new_label("equal.pool.cond");
        let body = self.new_label("equal.pool.body");
        let occupancy_equal = self.new_label("equal.pool.occupancy.equal");
        let live = self.new_label("equal.pool.live");
        let generation_equal = self.new_label("equal.pool.generation.equal");
        let next_label = self.new_label("equal.pool.next");
        let yes = self.new_label("equal.pool.true");
        let no = self.new_label("equal.pool.false");
        let merge = self.new_label("equal.pool.end");
        self.terminate(format!(
            "br i1 {counts_equal}, label %{condition}, label %{no}"
        ));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {index_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {capacity}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{yes}"));
        self.start_block(&body);
        let left_occupied = self.emit_pool_occupied_if_initialized(ty, left, &index, &left_hw);
        let right_occupied = self.emit_pool_occupied_if_initialized(ty, right, &index, &right_hw);
        let same_occupancy = self.temp();
        self.instruction(format!(
            "{same_occupancy} = icmp eq i1 {left_occupied}, {right_occupied}"
        ));
        self.terminate(format!(
            "br i1 {same_occupancy}, label %{occupancy_equal}, label %{no}"
        ));
        self.start_block(&occupancy_equal);
        self.terminate(format!(
            "br i1 {left_occupied}, label %{live}, label %{next_label}"
        ));
        self.start_block(&live);
        let left_generation_ptr = self.emit_pool_slot_ptr(ty, left, 3, &index);
        let right_generation_ptr = self.emit_pool_slot_ptr(ty, right, 3, &index);
        let left_generation = self.temp();
        let right_generation = self.temp();
        self.instruction(format!(
            "{left_generation} = load i32, ptr {left_generation_ptr}, align 1"
        ));
        self.instruction(format!(
            "{right_generation} = load i32, ptr {right_generation_ptr}, align 1"
        ));
        let same_generation = self.temp();
        self.instruction(format!(
            "{same_generation} = icmp eq i32 {left_generation}, {right_generation}"
        ));
        self.terminate(format!(
            "br i1 {same_generation}, label %{generation_equal}, label %{no}"
        ));
        self.start_block(&generation_equal);
        let values_equal = self.emit_equal_pool_elements(ty, left, right, &index);
        self.terminate(format!(
            "br i1 {values_equal}, label %{next_label}, label %{no}"
        ));
        self.start_block(&next_label);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {index_ptr}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {index_ptr}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&yes);
        let yes_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&no);
        let no_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi i1 [ true, %{yes_pred} ], [ false, %{no_pred} ]"
        ));
        result
    }

    fn emit_map_set_equal(&mut self, ty: Ty, left: &str, right: &str) -> String {
        let left_ptr = self.entry_alloca(ty);
        let right_ptr = self.entry_alloca(ty);
        self.instruction(format!(
            "store {} {left}, ptr {left_ptr}, align 1",
            self.lltype(ty)
        ));
        self.instruction(format!(
            "store {} {right}, ptr {right_ptr}, align 1",
            self.lltype(ty)
        ));
        let (capacity, key_ty, value_ty) = match self.program.types[ty.0].kind {
            TTypeKind::Map {
                key,
                value,
                capacity,
            } => (capacity, key, Some(value)),
            TTypeKind::Set { key, capacity } => (capacity, key, None),
            _ => unreachable!(),
        };
        let left_count_ptr = self.emit_map_meta_ptr(ty, &left_ptr, 0);
        let right_count_ptr = self.emit_map_meta_ptr(ty, &right_ptr, 0);
        let left_count = self.temp();
        let right_count = self.temp();
        self.instruction(format!(
            "{left_count} = load i64, ptr {left_count_ptr}, align 1"
        ));
        self.instruction(format!(
            "{right_count} = load i64, ptr {right_count_ptr}, align 1"
        ));
        let counts_equal = self.temp();
        self.instruction(format!(
            "{counts_equal} = icmp eq i64 {left_count}, {right_count}"
        ));
        let equal_ptr = self.entry_alloca(Ty::Bool);
        self.instruction(format!("store i1 {counts_equal}, ptr {equal_ptr}, align 1"));
        let index_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {index_ptr}, align 1"));
        let left_end_ptr = self.emit_map_meta_ptr(ty, &left_ptr, 1);
        let left_end = self.temp();
        self.instruction(format!(
            "{left_end} = load i64, ptr {left_end_ptr}, align 1"
        ));
        let condition = self.new_label("map.eq.cond");
        let inspect = self.new_label("map.eq.inspect");
        let compare = self.new_label("map.eq.compare");
        let skip = self.new_label("map.eq.skip");
        let done = self.new_label("map.eq.done");
        self.terminate(format!("br label %{condition}"));
        self.start_block(&condition);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {index_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {left_end}"));
        self.terminate(format!("br i1 {more}, label %{inspect}, label %{done}"));
        self.start_block(&inspect);
        let active_ptr = self.emit_map_array_ptr(ty, &left_ptr, 2, capacity, Ty::Bool, &index);
        let active = self.temp();
        self.instruction(format!("{active} = load i1, ptr {active_ptr}, align 1"));
        self.terminate(format!("br i1 {active}, label %{compare}, label %{skip}"));
        self.start_block(&compare);
        let key_ptr = self.emit_map_entry_ptr(ty, &left_ptr, &index, false);
        let key = self.temp();
        self.instruction(format!(
            "{key} = load {}, ptr {key_ptr}, align 1",
            self.lltype(key_ty)
        ));
        let (found_entry, _, _) = self.emit_map_lookup(ty, &right_ptr, key_ty, &key, capacity);
        let found = self.temp();
        self.instruction(format!("{found} = icmp sge i64 {found_entry}, 0"));
        let matched = if let Some(value_ty) = value_ty {
            let compare_value = self.new_label("map.eq.value");
            let missing = self.new_label("map.eq.missing");
            let value_merge = self.new_label("map.eq.value.end");
            self.terminate(format!(
                "br i1 {found}, label %{compare_value}, label %{missing}"
            ));
            self.start_block(&missing);
            let missing_pred = self.current_label.clone();
            self.terminate(format!("br label %{value_merge}"));
            self.start_block(&compare_value);
            let left_value = self.emit_collection_element(ty, &left_ptr, &index);
            let right_value = self.emit_collection_element(ty, &right_ptr, &found_entry);
            let equal = self.emit_binary(
                BinaryOp::Eq,
                value_ty,
                &left_value,
                &right_value,
                Span::default(),
            );
            let value_pred = self.current_label.clone();
            self.terminate(format!("br label %{value_merge}"));
            self.start_block(&value_merge);
            let result = self.temp();
            self.instruction(format!(
                "{result} = phi i1 [ false, %{missing_pred} ], [ {equal}, %{value_pred} ]"
            ));
            result
        } else {
            found
        };
        let previous = self.temp();
        self.instruction(format!("{previous} = load i1, ptr {equal_ptr}, align 1"));
        let next_equal = self.temp();
        self.instruction(format!("{next_equal} = and i1 {previous}, {matched}"));
        self.instruction(format!("store i1 {next_equal}, ptr {equal_ptr}, align 1"));
        self.terminate(format!("br label %{skip}"));
        self.start_block(&skip);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {index_ptr}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {index_ptr}, align 1"));
        self.terminate(format!("br label %{condition}"));
        self.start_block(&done);
        let equal = self.temp();
        self.instruction(format!("{equal} = load i1, ptr {equal_ptr}, align 1"));
        equal
    }

    fn emit_collection_equal(&mut self, ty: Ty, left: &str, right: &str) -> String {
        let left_ptr = self.entry_alloca(ty);
        let right_ptr = self.entry_alloca(ty);
        self.instruction(format!(
            "store {} {left}, ptr {left_ptr}, align 1",
            self.lltype(ty)
        ));
        self.instruction(format!(
            "store {} {right}, ptr {right_ptr}, align 1",
            self.lltype(ty)
        ));
        let (length, is_dynamic) = match self.program.types[ty.0].kind {
            TTypeKind::Array { capacity, .. } | TTypeKind::Grid { capacity, .. } => {
                (capacity.to_string(), false)
            }
            TTypeKind::List { .. } | TTypeKind::Queue { .. } | TTypeKind::Ring { .. } => {
                (self.emit_collection_count(ty, &left_ptr), true)
            }
            _ => unreachable!(),
        };
        let element = match self.program.types[ty.0].kind {
            TTypeKind::Array { element, .. }
            | TTypeKind::List { element, .. }
            | TTypeKind::Queue { element, .. }
            | TTypeKind::Ring { element, .. }
            | TTypeKind::Grid { element, .. } => element,
            _ => unreachable!(),
        };
        let counter = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {counter}, align 1"));
        let cond = self.new_label("eq.collection.cond");
        let body = self.new_label("eq.collection.body");
        let increment = self.new_label("eq.collection.increment");
        let true_label = self.new_label("eq.collection.true");
        let false_label = self.new_label("eq.collection.false");
        let merge = self.new_label("eq.collection.end");
        if is_dynamic {
            let left_count = self.emit_collection_count(ty, &left_ptr);
            let right_count = self.emit_collection_count(ty, &right_ptr);
            let same = self.temp();
            self.instruction(format!("{same} = icmp eq i64 {left_count}, {right_count}"));
            self.terminate(format!("br i1 {same}, label %{cond}, label %{false_label}"));
        } else {
            self.terminate(format!("br label %{cond}"));
        }
        self.start_block(&cond);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {length}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{true_label}"));
        self.start_block(&body);
        let lhs = self.emit_collection_element(ty, &left_ptr, &index);
        let rhs = self.emit_collection_element(ty, &right_ptr, &index);
        let equal = self.emit_binary(BinaryOp::Eq, element, &lhs, &rhs, Span::default());
        self.terminate(format!(
            "br i1 {equal}, label %{increment}, label %{false_label}"
        ));
        self.start_block(&increment);
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {index}, 1"));
        self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
        self.terminate(format!("br label %{cond}"));
        self.start_block(&true_label);
        let true_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&false_label);
        let false_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi i1 [ true, %{true_pred} ], [ false, %{false_pred} ]"
        ));
        result
    }

    fn emit_pool_equal(&mut self, ty: Ty, left: &str, right: &str) -> String {
        let left_ptr = self.entry_alloca(ty);
        let right_ptr = self.entry_alloca(ty);
        self.instruction(format!(
            "store {} {left}, ptr {left_ptr}, align 1",
            self.lltype(ty)
        ));
        self.instruction(format!(
            "store {} {right}, ptr {right_ptr}, align 1",
            self.lltype(ty)
        ));
        let (element, capacity) = match self.program.types[ty.0].kind {
            TTypeKind::Pool {
                element, capacity, ..
            } => (element, capacity),
            _ => unreachable!(),
        };
        let counter = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {counter}, align 1"));
        let cond = self.new_label("eq.pool.cond");
        let body = self.new_label("eq.pool.body");
        let occupied_equal = self.new_label("eq.pool.occupied.equal");
        let live = self.new_label("eq.pool.live");
        let compare_value = self.new_label("eq.pool.value");
        let increment = self.new_label("eq.pool.increment");
        let yes = self.new_label("eq.pool.true");
        let no = self.new_label("eq.pool.false");
        let merge = self.new_label("eq.pool.end");
        self.terminate(format!("br label %{cond}"));
        self.start_block(&cond);
        let index = self.temp();
        self.instruction(format!("{index} = load i64, ptr {counter}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {index}, {capacity}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{yes}"));
        self.start_block(&body);
        let left_occupied_ptr = self.emit_pool_slot_ptr(ty, &left_ptr, 2, &index);
        let right_occupied_ptr = self.emit_pool_slot_ptr(ty, &right_ptr, 2, &index);
        let left_occupied = self.temp();
        let right_occupied = self.temp();
        self.instruction(format!(
            "{left_occupied} = load i1, ptr {left_occupied_ptr}, align 1"
        ));
        self.instruction(format!(
            "{right_occupied} = load i1, ptr {right_occupied_ptr}, align 1"
        ));
        let same_occupancy = self.temp();
        self.instruction(format!(
            "{same_occupancy} = icmp eq i1 {left_occupied}, {right_occupied}"
        ));
        self.terminate(format!(
            "br i1 {same_occupancy}, label %{occupied_equal}, label %{no}"
        ));
        self.start_block(&occupied_equal);
        self.terminate(format!(
            "br i1 {left_occupied}, label %{live}, label %{increment}"
        ));
        self.start_block(&live);
        let left_gen_ptr = self.emit_pool_slot_ptr(ty, &left_ptr, 3, &index);
        let right_gen_ptr = self.emit_pool_slot_ptr(ty, &right_ptr, 3, &index);
        let left_gen = self.temp();
        let right_gen = self.temp();
        self.instruction(format!(
            "{left_gen} = load i32, ptr {left_gen_ptr}, align 1"
        ));
        self.instruction(format!(
            "{right_gen} = load i32, ptr {right_gen_ptr}, align 1"
        ));
        let same_generation = self.temp();
        self.instruction(format!(
            "{same_generation} = icmp eq i32 {left_gen}, {right_gen}"
        ));
        self.terminate(format!(
            "br i1 {same_generation}, label %{compare_value}, label %{no}"
        ));
        self.start_block(&compare_value);
        let left_value = self.emit_collection_element(ty, &left_ptr, &index);
        let right_value = self.emit_collection_element(ty, &right_ptr, &index);
        let values_equal = self.emit_binary(
            BinaryOp::Eq,
            element,
            &left_value,
            &right_value,
            Span::default(),
        );
        self.terminate(format!(
            "br i1 {values_equal}, label %{increment}, label %{no}"
        ));
        self.start_block(&increment);
        let current = self.temp();
        self.instruction(format!("{current} = load i64, ptr {counter}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {current}, 1"));
        self.instruction(format!("store i64 {next}, ptr {counter}, align 1"));
        self.terminate(format!("br label %{cond}"));
        self.start_block(&yes);
        let yes_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&no);
        let no_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi i1 [ true, %{yes_pred} ], [ false, %{no_pred} ]"
        ));
        result
    }

    fn emit_sort_less(
        &mut self,
        element_ty: Ty,
        callback: Option<(Ty, Ty, &str, &str)>,
        collection_ty: Ty,
        left_collection: &str,
        left_index: &str,
        right_collection: &str,
        right_index: &str,
        call_span: Span,
    ) -> String {
        let saved_top = self.stack_top.clone();
        let large_element = is_large_type(element_ty, &self.program.types);
        let (left, right) = if large_element {
            let left_storage = self.emit_runtime_region_alloc(element_ty, call_span, None);
            self.emit_gather_collection_element(
                collection_ty,
                left_collection,
                left_index,
                &left_storage,
            );
            let right_storage = self.emit_runtime_region_alloc(element_ty, call_span, None);
            self.emit_gather_collection_element(
                collection_ty,
                right_collection,
                right_index,
                &right_storage,
            );
            (left_storage, right_storage)
        } else {
            (
                self.emit_collection_element(collection_ty, left_collection, left_index),
                self.emit_collection_element(collection_ty, right_collection, right_index),
            )
        };
        if let Some((callback_ty, context_ty, function_value, context_value)) = callback {
            let TTypeKind::Function { params, .. } = &self.program.types[callback_ty.0].kind else {
                unreachable!("sort_by comparator has a function type")
            };
            let context_arg = if matches!(
                self.program.types[context_ty.0].kind,
                TTypeKind::Pool { .. }
            ) {
                format!("ptr {context_value}")
            } else {
                format!("{} {context_value}", self.lltype(context_ty))
            };
            debug_assert_eq!(params.len(), 3);
            let args = if large_element {
                format!("{context_arg}, ptr {left}, ptr {right}")
            } else {
                format!(
                    "{context_arg}, {} {left}, {} {right}",
                    self.lltype(element_ty),
                    self.lltype(element_ty)
                )
            };
            let targets = self
                .program
                .function_type_targets
                .get(callback_ty.0)
                .into_iter()
                .flatten()
                .filter(|target| self.program.functions[**target].recursive)
                .copied()
                .collect::<Vec<_>>();
            self.emit_recursion_check(&targets, call_span);
            let result = self.temp();
            self.instruction(format!(
                "{result} = call i1 {function_value}(ptr %nl.ctx, ptr {}, {args})",
                self.stack_top
            ));
            if large_element {
                self.restore_stack_top(&saved_top);
            }
            return result;
        }

        if self.is_ascii_type(element_ty) {
            let left_value = if large_element {
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {left}, align 1",
                    self.lltype(element_ty)
                ));
                value
            } else {
                left
            };
            let right_value = if large_element {
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {right}, align 1",
                    self.lltype(element_ty)
                ));
                value
            } else {
                right
            };
            let result = self.emit_binary(
                BinaryOp::Lt,
                element_ty,
                &left_value,
                &right_value,
                call_span,
            );
            if large_element {
                self.restore_stack_top(&saved_top);
            }
            return result;
        }

        let ordered_ty = base_type(element_ty, &self.program.types);
        match &self.program.types[ordered_ty.0].kind {
            TTypeKind::Int | TTypeKind::Long | TTypeKind::Bool => {
                let result = self.temp();
                self.instruction(format!(
                    "{result} = icmp {} {} {left}, {right}",
                    if ordered_ty == Ty::Bool { "ult" } else { "slt" },
                    self.lltype(ordered_ty)
                ));
                result
            }
            TTypeKind::Enum(_) => {
                let left_tag = self.temp();
                self.instruction(format!(
                    "{left_tag} = extractvalue {} {left}, 0",
                    self.lltype(element_ty)
                ));
                let right_tag = self.temp();
                self.instruction(format!(
                    "{right_tag} = extractvalue {} {right}, 0",
                    self.lltype(element_ty)
                ));
                let result = self.temp();
                self.instruction(format!("{result} = icmp ult i32 {left_tag}, {right_tag}"));
                result
            }
            _ => unreachable!("checker restricts natural sort element types"),
        }
    }

    fn emit_sort_copy_element(
        &mut self,
        collection_ty: Ty,
        source: &str,
        source_index: &str,
        destination: &str,
        destination_index: &str,
        element_ty: Ty,
    ) {
        if is_large_type(element_ty, &self.program.types) {
            self.emit_copy_collection_element(
                destination,
                source,
                collection_ty,
                destination_index,
                source_index,
            );
        } else {
            let value = self.emit_collection_element(collection_ty, source, source_index);
            self.emit_store_collection_element(
                collection_ty,
                destination,
                destination_index,
                &value,
            );
        }
    }

    fn emit_sort(&mut self, expr: &TExpr, args: &[TExpr], capacity: usize, is_list: bool) {
        let collection = &args[0];
        let collection_ty = collection.ty;
        let collection_ptr = self.emit_place_pointer_expr(collection);
        if self.terminated {
            return;
        }
        let mut callback = None;
        if args.len() == 3 {
            let context = &args[1];
            let context_value = if matches!(
                self.program.types[context.ty.0].kind,
                TTypeKind::Pool { .. }
            ) {
                self.emit_place_pointer_expr(context)
            } else {
                self.emit_expr(context)
            };
            if self.terminated {
                return;
            }
            let function_value = self.emit_expr(&args[2]);
            if self.terminated {
                return;
            }
            let TTypeKind::Function { params, .. } = &self.program.types[args[2].ty.0].kind else {
                unreachable!("type checker validates sort_by comparator")
            };
            callback = Some((args[2].ty, params[0].ty, function_value, context_value));
        }
        let count = if is_list {
            self.emit_collection_count(collection_ty, &collection_ptr)
        } else {
            capacity.to_string()
        };
        let element_ty = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { element, .. } | TTypeKind::List { element, .. } => element,
            _ => unreachable!("sort input was checked as a list or array"),
        };
        let scratch_ptr = if let Some(pointer) = self.sort_scratch.get(&collection_ty) {
            pointer.clone()
        } else {
            let pointer = self.entry_alloca(collection_ty);
            self.sort_scratch.insert(collection_ty, pointer.clone());
            self.emit_empty_storage(&pointer, collection_ty);
            pointer
        };
        if is_list {
            let scratch_count = self.emit_collection_count_ptr(collection_ty, &scratch_ptr);
            self.instruction(format!("store i64 {count}, ptr {scratch_count}, align 1"));
        }
        let i_ptr = self.entry_alloca(Ty::Long);
        let j_ptr = self.entry_alloca(Ty::Long);

        let small = self.temp();
        self.instruction(format!("{small} = icmp ult i64 {count}, 16"));
        let insertion = self.new_label("sort.insertion");
        let merge = self.new_label("sort.merge.init");
        let finished = self.new_label("sort.done");
        self.terminate(format!("br i1 {small}, label %{insertion}, label %{merge}"));

        self.start_block(&insertion);
        self.instruction(format!("store i64 1, ptr {i_ptr}, align 1"));
        let insertion_cond = self.new_label("sort.insertion.cond");
        let insertion_body = self.new_label("sort.insertion.body");
        let insertion_inner = self.new_label("sort.insertion.inner");
        let insertion_compare = self.new_label("sort.insertion.compare");
        let insertion_shift = self.new_label("sort.insertion.shift");
        let insertion_store = self.new_label("sort.insertion.store");
        let insertion_exit = self.new_label("sort.insertion.exit");
        self.terminate(format!("br label %{insertion_cond}"));
        self.start_block(&insertion_cond);
        let i = self.temp();
        self.instruction(format!("{i} = load i64, ptr {i_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {i}, {count}"));
        self.terminate(format!(
            "br i1 {more}, label %{insertion_body}, label %{insertion_exit}"
        ));
        self.start_block(&insertion_body);
        self.emit_sort_copy_element(
            collection_ty,
            &collection_ptr,
            &i,
            &scratch_ptr,
            &i,
            element_ty,
        );
        self.instruction(format!("store i64 {i}, ptr {j_ptr}, align 1"));
        self.terminate(format!("br label %{insertion_inner}"));
        self.start_block(&insertion_inner);
        let j = self.temp();
        self.instruction(format!("{j} = load i64, ptr {j_ptr}, align 1"));
        let has_previous = self.temp();
        self.instruction(format!("{has_previous} = icmp ugt i64 {j}, 0"));
        self.terminate(format!(
            "br i1 {has_previous}, label %{insertion_compare}, label %{insertion_store}"
        ));
        self.start_block(&insertion_compare);
        let previous = self.temp();
        self.instruction(format!("{previous} = sub i64 {j}, 1"));
        let key_index = self.temp();
        self.instruction(format!("{key_index} = load i64, ptr {i_ptr}, align 1"));
        let should_shift = self.emit_sort_less(
            element_ty,
            callback
                .as_ref()
                .map(|(callback_ty, context_ty, function_value, context_value)| {
                    (
                        *callback_ty,
                        *context_ty,
                        function_value.as_str(),
                        context_value.as_str(),
                    )
                }),
            collection_ty,
            &scratch_ptr,
            &key_index,
            &collection_ptr,
            &previous,
            expr.span,
        );
        self.terminate(format!(
            "br i1 {should_shift}, label %{insertion_shift}, label %{insertion_store}"
        ));
        self.start_block(&insertion_shift);
        self.emit_sort_copy_element(
            collection_ty,
            &collection_ptr,
            &previous,
            &collection_ptr,
            &j,
            element_ty,
        );
        self.instruction(format!("store i64 {previous}, ptr {j_ptr}, align 1"));
        self.terminate(format!("br label %{insertion_inner}"));
        self.start_block(&insertion_store);
        let j = self.temp();
        self.instruction(format!("{j} = load i64, ptr {j_ptr}, align 1"));
        let key_index = self.temp();
        self.instruction(format!("{key_index} = load i64, ptr {i_ptr}, align 1"));
        self.emit_clear_collection_element(collection_ty, &collection_ptr, &j);
        self.emit_sort_copy_element(
            collection_ty,
            &scratch_ptr,
            &key_index,
            &collection_ptr,
            &j,
            element_ty,
        );
        self.emit_clear_collection_element(collection_ty, &scratch_ptr, &key_index);
        let i = self.temp();
        self.instruction(format!("{i} = load i64, ptr {i_ptr}, align 1"));
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {i}, 1"));
        self.instruction(format!("store i64 {next}, ptr {i_ptr}, align 1"));
        self.terminate(format!("br label %{insertion_cond}"));
        self.start_block(&insertion_exit);
        self.terminate(format!("br label %{finished}"));

        self.start_block(&merge);
        let width_ptr = self.entry_alloca(Ty::Long);
        let left_ptr = self.entry_alloca(Ty::Long);
        let mid_ptr = self.entry_alloca(Ty::Long);
        let right_ptr = self.entry_alloca(Ty::Long);
        let out_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 1, ptr {width_ptr}, align 1"));
        let merge_cond = self.new_label("sort.merge.cond");
        let merge_pass = self.new_label("sort.merge.pass");
        let group_cond = self.new_label("sort.merge.group.cond");
        let group_setup = self.new_label("sort.merge.group.setup");
        let values_cond = self.new_label("sort.merge.values.cond");
        let compare = self.new_label("sort.merge.compare");
        let choose_left = self.new_label("sort.merge.left");
        let choose_right = self.new_label("sort.merge.right");
        let group_done = self.new_label("sort.merge.group.done");
        let copy_cond = self.new_label("sort.merge.copy.cond");
        let copy_body = self.new_label("sort.merge.copy.body");
        let copy_done = self.new_label("sort.merge.copy.done");
        let merge_done = self.new_label("sort.merge.done");
        self.terminate(format!("br label %{merge_cond}"));
        self.start_block(&merge_cond);
        let width = self.temp();
        self.instruction(format!("{width} = load i64, ptr {width_ptr}, align 1"));
        let finished_passes = self.temp();
        self.instruction(format!("{finished_passes} = icmp uge i64 {width}, {count}"));
        self.terminate(format!(
            "br i1 {finished_passes}, label %{merge_done}, label %{merge_pass}"
        ));
        self.start_block(&merge_pass);
        self.instruction(format!("store i64 0, ptr {left_ptr}, align 1"));
        self.terminate(format!("br label %{group_cond}"));
        self.start_block(&group_cond);
        let left = self.temp();
        self.instruction(format!("{left} = load i64, ptr {left_ptr}, align 1"));
        let more_groups = self.temp();
        self.instruction(format!("{more_groups} = icmp ult i64 {left}, {count}"));
        self.terminate(format!(
            "br i1 {more_groups}, label %{group_setup}, label %{copy_cond}"
        ));
        self.start_block(&group_setup);
        let width = self.temp();
        self.instruction(format!("{width} = load i64, ptr {width_ptr}, align 1"));
        let left = self.temp();
        self.instruction(format!("{left} = load i64, ptr {left_ptr}, align 1"));
        let mid_candidate = self.temp();
        self.instruction(format!("{mid_candidate} = add i64 {left}, {width}"));
        let mid_past = self.temp();
        self.instruction(format!(
            "{mid_past} = icmp ugt i64 {mid_candidate}, {count}"
        ));
        let mid = self.temp();
        self.instruction(format!(
            "{mid} = select i1 {mid_past}, i64 {count}, i64 {mid_candidate}"
        ));
        self.instruction(format!("store i64 {mid}, ptr {mid_ptr}, align 1"));
        let right_candidate = self.temp();
        self.instruction(format!("{right_candidate} = add i64 {mid}, {width}"));
        let right_past = self.temp();
        self.instruction(format!(
            "{right_past} = icmp ugt i64 {right_candidate}, {count}"
        ));
        let right = self.temp();
        self.instruction(format!(
            "{right} = select i1 {right_past}, i64 {count}, i64 {right_candidate}"
        ));
        self.instruction(format!("store i64 {right}, ptr {right_ptr}, align 1"));
        self.instruction(format!("store i64 {left}, ptr {i_ptr}, align 1"));
        self.instruction(format!("store i64 {mid}, ptr {j_ptr}, align 1"));
        self.instruction(format!("store i64 {left}, ptr {out_ptr}, align 1"));
        self.terminate(format!("br label %{values_cond}"));
        self.start_block(&values_cond);
        let i = self.temp();
        self.instruction(format!("{i} = load i64, ptr {i_ptr}, align 1"));
        let j = self.temp();
        self.instruction(format!("{j} = load i64, ptr {j_ptr}, align 1"));
        let mid = self.temp();
        self.instruction(format!("{mid} = load i64, ptr {mid_ptr}, align 1"));
        let right = self.temp();
        self.instruction(format!("{right} = load i64, ptr {right_ptr}, align 1"));
        let i_more = self.temp();
        self.instruction(format!("{i_more} = icmp ult i64 {i}, {mid}"));
        let j_more = self.temp();
        self.instruction(format!("{j_more} = icmp ult i64 {j}, {right}"));
        let both = self.temp();
        self.instruction(format!("{both} = and i1 {i_more}, {j_more}"));
        let values_done = self.new_label("sort.merge.values.done");
        let one_side = self.new_label("sort.merge.one.side");
        self.terminate(format!("br i1 {both}, label %{compare}, label %{one_side}"));
        self.start_block(&one_side);
        let any = self.temp();
        self.instruction(format!("{any} = or i1 {i_more}, {j_more}"));
        self.terminate(format!(
            "br i1 {any}, label %{choose_left}, label %{values_done}"
        ));
        self.start_block(&compare);
        let i = self.temp();
        self.instruction(format!("{i} = load i64, ptr {i_ptr}, align 1"));
        let j = self.temp();
        self.instruction(format!("{j} = load i64, ptr {j_ptr}, align 1"));
        let right_before_left = self.emit_sort_less(
            element_ty,
            callback
                .as_ref()
                .map(|(callback_ty, context_ty, function_value, context_value)| {
                    (
                        *callback_ty,
                        *context_ty,
                        function_value.as_str(),
                        context_value.as_str(),
                    )
                }),
            collection_ty,
            &collection_ptr,
            &j,
            &collection_ptr,
            &i,
            expr.span,
        );
        self.terminate(format!(
            "br i1 {right_before_left}, label %{choose_right}, label %{choose_left}"
        ));

        self.start_block(&choose_left);
        let i_more = self.temp();
        let i = self.temp();
        let mid = self.temp();
        self.instruction(format!("{i} = load i64, ptr {i_ptr}, align 1"));
        self.instruction(format!("{mid} = load i64, ptr {mid_ptr}, align 1"));
        self.instruction(format!("{i_more} = icmp ult i64 {i}, {mid}"));
        let left_value = self.new_label("sort.merge.take.left");
        let right_value = self.new_label("sort.merge.take.right");
        self.terminate(format!(
            "br i1 {i_more}, label %{left_value}, label %{right_value}"
        ));
        self.start_block(&left_value);
        let i = self.temp();
        let out = self.temp();
        self.instruction(format!("{i} = load i64, ptr {i_ptr}, align 1"));
        self.instruction(format!("{out} = load i64, ptr {out_ptr}, align 1"));
        self.emit_sort_copy_element(
            collection_ty,
            &collection_ptr,
            &i,
            &scratch_ptr,
            &out,
            element_ty,
        );
        let i_next = self.temp();
        self.instruction(format!("{i_next} = add i64 {i}, 1"));
        self.instruction(format!("store i64 {i_next}, ptr {i_ptr}, align 1"));
        let out_next = self.temp();
        self.instruction(format!("{out_next} = add i64 {out}, 1"));
        self.instruction(format!("store i64 {out_next}, ptr {out_ptr}, align 1"));
        self.terminate(format!("br label %{values_cond}"));
        self.start_block(&right_value);
        let j = self.temp();
        let out = self.temp();
        self.instruction(format!("{j} = load i64, ptr {j_ptr}, align 1"));
        self.instruction(format!("{out} = load i64, ptr {out_ptr}, align 1"));
        self.emit_sort_copy_element(
            collection_ty,
            &collection_ptr,
            &j,
            &scratch_ptr,
            &out,
            element_ty,
        );
        let j_next = self.temp();
        self.instruction(format!("{j_next} = add i64 {j}, 1"));
        self.instruction(format!("store i64 {j_next}, ptr {j_ptr}, align 1"));
        let out_next = self.temp();
        self.instruction(format!("{out_next} = add i64 {out}, 1"));
        self.instruction(format!("store i64 {out_next}, ptr {out_ptr}, align 1"));
        self.terminate(format!("br label %{values_cond}"));

        self.start_block(&choose_right);
        let j = self.temp();
        let out = self.temp();
        self.instruction(format!("{j} = load i64, ptr {j_ptr}, align 1"));
        self.instruction(format!("{out} = load i64, ptr {out_ptr}, align 1"));
        self.emit_sort_copy_element(
            collection_ty,
            &collection_ptr,
            &j,
            &scratch_ptr,
            &out,
            element_ty,
        );
        let j_next = self.temp();
        self.instruction(format!("{j_next} = add i64 {j}, 1"));
        self.instruction(format!("store i64 {j_next}, ptr {j_ptr}, align 1"));
        let out_next = self.temp();
        self.instruction(format!("{out_next} = add i64 {out}, 1"));
        self.instruction(format!("store i64 {out_next}, ptr {out_ptr}, align 1"));
        self.terminate(format!("br label %{values_cond}"));

        self.start_block(&values_done);
        let left = self.temp();
        let right = self.temp();
        self.instruction(format!("{left} = load i64, ptr {left_ptr}, align 1"));
        self.instruction(format!("{right} = load i64, ptr {right_ptr}, align 1"));
        let _ = (left, right);
        self.terminate(format!("br label %{group_done}"));
        self.start_block(&group_done);
        let next_left = self.temp();
        self.instruction(format!("{next_left} = load i64, ptr {right_ptr}, align 1"));
        self.instruction(format!("store i64 {next_left}, ptr {left_ptr}, align 1"));
        self.terminate(format!("br label %{group_cond}"));

        self.start_block(&copy_cond);
        self.instruction(format!("store i64 0, ptr {i_ptr}, align 1"));
        let copy_loop = self.new_label("sort.merge.copy.loop");
        self.terminate(format!("br label %{copy_loop}"));
        self.start_block(&copy_loop);
        let i = self.temp();
        self.instruction(format!("{i} = load i64, ptr {i_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {i}, {count}"));
        self.terminate(format!(
            "br i1 {more}, label %{copy_body}, label %{copy_done}"
        ));
        self.start_block(&copy_body);
        let i = self.temp();
        self.instruction(format!("{i} = load i64, ptr {i_ptr}, align 1"));
        self.emit_clear_collection_element(collection_ty, &collection_ptr, &i);
        self.emit_sort_copy_element(
            collection_ty,
            &scratch_ptr,
            &i,
            &collection_ptr,
            &i,
            element_ty,
        );
        self.emit_clear_collection_element(collection_ty, &scratch_ptr, &i);
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {i}, 1"));
        self.instruction(format!("store i64 {next}, ptr {i_ptr}, align 1"));
        self.terminate(format!("br label %{copy_loop}"));
        self.start_block(&copy_done);
        let width = self.temp();
        self.instruction(format!("{width} = load i64, ptr {width_ptr}, align 1"));
        let doubled = self.temp();
        self.instruction(format!("{doubled} = shl i64 {width}, 1"));
        self.instruction(format!("store i64 {doubled}, ptr {width_ptr}, align 1"));
        self.terminate(format!("br label %{merge_cond}"));
        self.start_block(&merge_done);
        self.terminate(format!("br label %{finished}"));
        self.start_block(&finished);
        let _ = expr;
    }

    fn emit_binary_search(
        &mut self,
        expr: &TExpr,
        args: &[TExpr],
        capacity: usize,
        is_list: bool,
    ) -> String {
        let collection = &args[0];
        let collection_ty = collection.ty;
        let collection_ptr = if let Some(place) = Self::expr_place(collection) {
            self.emit_place_pointer(&place)
        } else {
            let value = self.emit_expr(collection);
            if self.terminated {
                return String::new();
            }
            let pointer = self.entry_alloca(collection_ty);
            self.instruction(format!(
                "store {} {value}, ptr {pointer}, align 1",
                self.lltype(collection_ty)
            ));
            pointer
        };
        let key = self.emit_expr(&args[1]);
        if self.terminated {
            return String::new();
        }
        let element_ty = match self.program.types[collection_ty.0].kind {
            TTypeKind::Array { element, .. } | TTypeKind::List { element, .. } => element,
            _ => unreachable!("binary_search input was checked as a list or array"),
        };
        let base = base_type(element_ty, &self.program.types);
        let count = if is_list {
            self.emit_collection_count(collection_ty, &collection_ptr)
        } else {
            capacity.to_string()
        };
        let key_ptr = self.entry_alloca(element_ty);
        self.instruction(format!(
            "store {} {key}, ptr {key_ptr}, align 1",
            self.lltype(element_ty)
        ));

        if cfg!(debug_assertions) {
            let index_ptr = self.entry_alloca(Ty::Long);
            self.instruction(format!("store i64 1, ptr {index_ptr}, align 1"));
            let cond = self.new_label("binary.search.sorted.cond");
            let body = self.new_label("binary.search.sorted.body");
            let compare = self.new_label("binary.search.sorted.compare");
            let next = self.new_label("binary.search.sorted.next");
            let done = self.new_label("binary.search.sorted.done");
            self.terminate(format!("br label %{cond}"));
            self.start_block(&cond);
            let index = self.temp();
            self.instruction(format!("{index} = load i64, ptr {index_ptr}, align 1"));
            let valid = self.temp();
            self.instruction(format!("{valid} = icmp ult i64 {index}, {count}"));
            self.terminate(format!("br i1 {valid}, label %{body}, label %{done}"));
            self.start_block(&body);
            self.terminate(format!("br label %{compare}"));
            self.start_block(&compare);
            let index = self.temp();
            self.instruction(format!("{index} = load i64, ptr {index_ptr}, align 1"));
            let previous = self.temp();
            self.instruction(format!("{previous} = sub i64 {index}, 1"));
            let previous_value =
                self.emit_collection_element(collection_ty, &collection_ptr, &previous);
            let current_value =
                self.emit_collection_element(collection_ty, &collection_ptr, &index);
            let inverted = self.temp();
            self.instruction(format!(
                "{inverted} = icmp slt {} {current_value}, {previous_value}",
                self.lltype(base)
            ));
            self.guard(inverted, Failure::UnsortedInput, expr.span);
            self.terminate(format!("br label %{next}"));
            self.start_block(&next);
            let index = self.temp();
            self.instruction(format!("{index} = load i64, ptr {index_ptr}, align 1"));
            let incremented = self.temp();
            self.instruction(format!("{incremented} = add i64 {index}, 1"));
            self.instruction(format!("store i64 {incremented}, ptr {index_ptr}, align 1"));
            self.terminate(format!("br label %{cond}"));
            self.start_block(&done);
        }

        let low_ptr = self.entry_alloca(Ty::Long);
        let high_ptr = self.entry_alloca(Ty::Long);
        self.instruction(format!("store i64 0, ptr {low_ptr}, align 1"));
        self.instruction(format!("store i64 {count}, ptr {high_ptr}, align 1"));
        let cond = self.new_label("binary.search.cond");
        let body = self.new_label("binary.search.body");
        let done = self.new_label("binary.search.done");
        self.terminate(format!("br label %{cond}"));
        self.start_block(&cond);
        let low = self.temp();
        let high = self.temp();
        self.instruction(format!("{low} = load i64, ptr {low_ptr}, align 1"));
        self.instruction(format!("{high} = load i64, ptr {high_ptr}, align 1"));
        let more = self.temp();
        self.instruction(format!("{more} = icmp ult i64 {low}, {high}"));
        self.terminate(format!("br i1 {more}, label %{body}, label %{done}"));
        self.start_block(&body);
        let low = self.temp();
        let high = self.temp();
        self.instruction(format!("{low} = load i64, ptr {low_ptr}, align 1"));
        self.instruction(format!("{high} = load i64, ptr {high_ptr}, align 1"));
        let delta = self.temp();
        self.instruction(format!("{delta} = sub i64 {high}, {low}"));
        let half = self.temp();
        self.instruction(format!("{half} = udiv i64 {delta}, 2"));
        let middle = self.temp();
        self.instruction(format!("{middle} = add i64 {low}, {half}"));
        let value = self.emit_collection_element(collection_ty, &collection_ptr, &middle);
        let key = self.temp();
        self.instruction(format!(
            "{key} = load {}, ptr {key_ptr}, align 1",
            self.lltype(element_ty)
        ));
        let before = self.temp();
        self.instruction(format!(
            "{before} = icmp slt {} {value}, {key}",
            self.lltype(base)
        ));
        let advance = self.new_label("binary.search.advance");
        let shorten = self.new_label("binary.search.shorten");
        self.terminate(format!(
            "br i1 {before}, label %{advance}, label %{shorten}"
        ));
        self.start_block(&advance);
        let next = self.temp();
        self.instruction(format!("{next} = add i64 {middle}, 1"));
        self.instruction(format!("store i64 {next}, ptr {low_ptr}, align 1"));
        self.terminate(format!("br label %{cond}"));
        self.start_block(&shorten);
        self.instruction(format!("store i64 {middle}, ptr {high_ptr}, align 1"));
        self.terminate(format!("br label %{cond}"));
        self.start_block(&done);
        let low = self.temp();
        self.instruction(format!("{low} = load i64, ptr {low_ptr}, align 1"));
        let within = self.temp();
        self.instruction(format!("{within} = icmp ult i64 {low}, {count}"));
        let found = self.new_label("binary.search.found.check");
        let missing = self.new_label("binary.search.missing");
        let found_value = self.new_label("binary.search.found");
        self.terminate(format!("br i1 {within}, label %{found}, label %{missing}"));
        self.start_block(&found);
        let value = self.emit_collection_element(collection_ty, &collection_ptr, &low);
        let key = self.temp();
        self.instruction(format!(
            "{key} = load {}, ptr {key_ptr}, align 1",
            self.lltype(element_ty)
        ));
        let equal = self.temp();
        self.instruction(format!(
            "{equal} = icmp eq {} {value}, {key}",
            self.lltype(base)
        ));
        self.terminate(format!(
            "br i1 {equal}, label %{found_value}, label %{missing}"
        ));
        self.start_block(&found_value);
        let found_value = low.clone();
        let found_pred = self.current_label.clone();
        let result_block = self.new_label("binary.search.result");
        self.terminate(format!("br label %{result_block}"));
        self.start_block(&missing);
        let missing_pred = self.current_label.clone();
        self.terminate(format!("br label %{result_block}"));
        self.start_block(&result_block);
        let is_found = self.temp();
        self.instruction(format!(
            "{is_found} = phi i1 [ true, %{found_pred} ], [ false, %{missing_pred} ]"
        ));
        let index = self.temp();
        self.instruction(format!(
            "{index} = phi i64 [ {found_value}, %{found_pred} ], [ 0, %{missing_pred} ]"
        ));
        let some_label = self.new_label("binary.search.some");
        let none_label = self.new_label("binary.search.none");
        let result_label = self.new_label("binary.search.result.end");
        self.terminate(format!(
            "br i1 {is_found}, label %{some_label}, label %{none_label}"
        ));
        self.start_block(&some_label);
        let some = self.emit_construct_values(expr.ty, 0, vec![(Ty::Long, index.clone())]);
        let some_pred = self.current_label.clone();
        self.terminate(format!("br label %{result_label}"));
        self.start_block(&none_label);
        let none = self.emit_construct_values(expr.ty, 1, Vec::new());
        let none_pred = self.current_label.clone();
        self.terminate(format!("br label %{result_label}"));
        self.start_block(&result_label);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi {} [ {some}, %{some_pred} ], [ {none}, %{none_pred} ]",
            self.lltype(expr.ty)
        ));
        result
    }

    fn emit_expr(&mut self, expr: &TExpr) -> String {
        if self.terminated {
            return String::new();
        }
        match &expr.kind {
            TExprKind::Call {
                target: CallTarget::Function(function_id),
                args,
                ..
            } => self.emit_direct_call(*function_id, args, None, expr.span),
            TExprKind::Call {
                target,
                args,
                effect,
            } => self.emit_call_expr(expr, target, args, effect),
            TExprKind::Binary {
                op,
                operator_span,
                left,
                right,
            } => {
                if matches!(op, BinaryOp::And | BinaryOp::Or) {
                    return self.emit_short_circuit(*op, left, right);
                }
                if matches!(op, BinaryOp::Eq | BinaryOp::Ne)
                    && contains_lazy_collection(
                        left.ty,
                        &self.program.types,
                        &mut vec![false; self.program.types.len()],
                    )
                {
                    let lhs = self.emit_expr_storage(left);
                    if self.terminated {
                        return String::new();
                    }
                    let rhs = self.emit_expr_storage(right);
                    if self.terminated {
                        return String::new();
                    }
                    let equal = self.emit_equal_storage(left.ty, &lhs, &rhs);
                    if *op == BinaryOp::Eq {
                        return equal;
                    }
                    let result = self.temp();
                    self.instruction(format!("{result} = xor i1 {equal}, true"));
                    return result;
                }
                if *op == BinaryOp::Add && self.ascii_max(left.ty).is_some() {
                    let pointer = self.entry_alloca(expr.ty);
                    self.emit_expr_to(&pointer, expr);
                    if self.terminated {
                        return String::new();
                    }
                    let value = self.temp();
                    self.instruction(format!(
                        "{value} = load {}, ptr {pointer}, align 1",
                        self.lltype(expr.ty)
                    ));
                    return value;
                }
                let lhs = self.emit_expr(left);
                if self.terminated {
                    return String::new();
                }
                let rhs = self.emit_expr(right);
                if self.terminated {
                    return String::new();
                }
                self.emit_binary(*op, left.ty, &lhs, &rhs, *operator_span)
            }
            TExprKind::If {
                condition,
                then_block,
                else_block,
            } => self.emit_if(
                condition,
                then_block,
                else_block.as_ref(),
                expr.ty,
                true,
                expr.span,
            ),
            _ => self.emit_expr_inner(expr),
        }
    }

    #[inline(never)]
    fn emit_call_expr(
        &mut self,
        expr: &TExpr,
        target: &CallTarget,
        args: &[TExpr],
        effect: &Effect,
    ) -> String {
        match target {
            CallTarget::Function(_) => {
                unreachable!("direct calls use the small emitter path")
            }
            CallTarget::Print => {
                debug_assert_eq!(*effect, Effect::Observable);
                let arg = &args[0];
                let ty = base_type(arg.ty, &self.program.types);
                if matches!(
                    self.program.types[ty.0].kind,
                    TTypeKind::Capability(CapabilityKind::Arg)
                ) {
                    let value = self.emit_expr(arg);
                    if self.terminated {
                        return String::new();
                    }
                    self.instruction(format!("call void @nl_print_arg(ptr {value})"));
                } else if matches!(ty, Ty::Int | Ty::Long | Ty::Bool) {
                    let value = self.emit_expr(arg);
                    if self.terminated {
                        return String::new();
                    }
                    let name = match ty {
                        Ty::Int => "nl_print_int",
                        Ty::Long => "nl_print_long",
                        Ty::Bool => "nl_print_bool",
                        _ => unreachable!(),
                    };
                    let bool_abi = if ty == Ty::Bool { " zeroext" } else { "" };
                    self.instruction(format!(
                        "call void @{name}({}{bool_abi} {value})",
                        self.lltype(ty)
                    ));
                } else if is_large_type(arg.ty, &self.program.types) {
                    let pointer = self.emit_expr_storage(arg);
                    if self.terminated {
                        return String::new();
                    }
                    self.emit_print_value_storage(arg.ty, &pointer);
                    self.instruction("call void @nl_print_newline()");
                } else {
                    let value = self.emit_expr(arg);
                    if self.terminated {
                        return String::new();
                    }
                    self.emit_print_value(arg.ty, &value);
                    self.instruction("call void @nl_print_newline()");
                }
                String::new()
            }
            CallTarget::Min | CallTarget::Max => {
                let left = self.emit_expr(&args[0]);
                if self.terminated {
                    return String::new();
                }
                let right = self.emit_expr(&args[1]);
                if self.terminated {
                    return String::new();
                }
                let ty = base_type(args[0].ty, &self.program.types);
                let test = self.temp();
                self.instruction(format!(
                    "{test} = icmp {} {} {left}, {right}",
                    if matches!(target, CallTarget::Min) {
                        "slt"
                    } else {
                        "sgt"
                    },
                    self.lltype(ty)
                ));
                let result = self.temp();
                self.instruction(format!(
                    "{result} = select i1 {test}, {} {left}, {} {right}",
                    self.lltype(ty),
                    self.lltype(ty)
                ));
                result
            }
            CallTarget::Sort { capacity, is_list } => {
                debug_assert_eq!(*effect, Effect::None);
                self.emit_sort(expr, args, *capacity, *is_list);
                String::new()
            }
            CallTarget::SortBy {
                capacity, is_list, ..
            } => {
                debug_assert_eq!(*effect, Effect::None);
                self.emit_sort(expr, args, *capacity, *is_list);
                String::new()
            }
            CallTarget::BinarySearch { capacity, is_list } => {
                debug_assert_eq!(*effect, Effect::None);
                self.emit_binary_search(expr, args, *capacity, *is_list)
            }
            CallTarget::EnvArgs
            | CallTarget::EnvFs
            | CallTarget::EnvOut
            | CallTarget::EnvErr
            | CallTarget::ArgsCount
            | CallTarget::ArgsGet
            | CallTarget::ArgLength
            | CallTarget::ArgByte
            | CallTarget::FsRead
            | CallTarget::FsList
            | CallTarget::FsWrite
            | CallTarget::FsJoin
            | CallTarget::OutWrite
            | CallTarget::OutLine
            | CallTarget::OutInt
            | CallTarget::OutLong => self.emit_capability_call(expr, target, args),
        }
    }

    fn emit_io_bytes_argument(&mut self, expr: &TExpr) -> (String, i32, usize) {
        if matches!(
            self.program.types[expr.ty.0].kind,
            TTypeKind::Capability(CapabilityKind::Arg)
        ) {
            let value = self.emit_expr(expr);
            (value, 1, 0)
        } else if self.ascii_max(expr.ty).is_some() {
            let pointer = if Self::expr_place(expr).is_some() {
                self.emit_expr_storage(expr)
            } else {
                let pointer = self.entry_alloca(expr.ty);
                self.emit_expr_to(&pointer, expr);
                pointer
            };
            (pointer, 2, self.ascii_max(expr.ty).unwrap_or(0))
        } else {
            let TTypeKind::List { capacity, .. } = self.program.types[expr.ty.0].kind else {
                unreachable!("checker validates I/O byte arguments")
            };
            (self.emit_expr_storage(expr), 0, capacity)
        }
    }

    fn emit_capability_call(
        &mut self,
        expr: &TExpr,
        target: &CallTarget,
        args: &[TExpr],
    ) -> String {
        match target {
            CallTarget::EnvArgs | CallTarget::EnvFs => {
                let env = self.emit_expr(&args[0]);
                if self.terminated {
                    return String::new();
                }
                let function = if matches!(target, CallTarget::EnvArgs) {
                    "nl_env_args"
                } else {
                    "nl_env_fs"
                };
                let value = self.temp();
                self.instruction(format!("{value} = call ptr @{function}(ptr {env})"));
                value
            }
            CallTarget::EnvOut | CallTarget::EnvErr => {
                let env = self.emit_expr(&args[0]);
                if self.terminated {
                    return String::new();
                }
                let fd = if matches!(target, CallTarget::EnvErr) {
                    2
                } else {
                    1
                };
                let value = self.temp();
                self.instruction(format!(
                    "{value} = call ptr @nl_env_out(ptr {env}, i32 {fd})"
                ));
                value
            }
            CallTarget::ArgsCount | CallTarget::ArgLength => {
                let receiver = self.emit_expr(&args[0]);
                if self.terminated {
                    return String::new();
                }
                let function = if matches!(target, CallTarget::ArgsCount) {
                    "nl_args_count"
                } else {
                    "nl_arg_length"
                };
                let value = self.temp();
                self.instruction(format!("{value} = call i64 @{function}(ptr {receiver})"));
                value
            }
            CallTarget::ArgsGet => {
                let receiver = self.emit_expr(&args[0]);
                if self.terminated {
                    return String::new();
                }
                let index = self.emit_expr(&args[1]);
                if self.terminated {
                    return String::new();
                }
                let pointer = self.temp();
                self.instruction(format!(
                    "{pointer} = call ptr @nl_args_get(ptr {receiver}, i64 {index})"
                ));
                let present = self.temp();
                self.instruction(format!("{present} = icmp ne ptr {pointer}, null"));
                self.emit_option_pointer(
                    expr.ty,
                    &pointer,
                    &present,
                    self.program.types[expr.ty.0].cases()[0].payload[0],
                )
            }
            CallTarget::ArgByte => {
                let receiver = self.emit_expr(&args[0]);
                if self.terminated {
                    return String::new();
                }
                let index = self.emit_expr(&args[1]);
                if self.terminated {
                    return String::new();
                }
                let byte = self.temp();
                self.instruction(format!(
                    "{byte} = call i32 @nl_arg_byte(ptr {receiver}, i64 {index})"
                ));
                let present = self.temp();
                self.instruction(format!("{present} = icmp sge i32 {byte}, 0"));
                let some = self.new_label("arg.byte.some");
                let none = self.new_label("arg.byte.none");
                let merge = self.new_label("arg.byte.end");
                self.terminate(format!("br i1 {present}, label %{some}, label %{none}"));
                self.start_block(&some);
                let some_value = self.emit_construct_values(expr.ty, 0, vec![(Ty::Int, byte)]);
                let some_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&none);
                let none_value = self.emit_construct_values(expr.ty, 1, Vec::new());
                let none_pred = self.current_label.clone();
                self.terminate(format!("br label %{merge}"));
                self.start_block(&merge);
                let result = self.temp();
                self.instruction(format!("{result} = phi {} [ {some_value}, %{some_pred} ], [ {none_value}, %{none_pred} ]", self.lltype(expr.ty)));
                result
            }
            CallTarget::FsRead | CallTarget::FsList | CallTarget::FsWrite => {
                let fs = self.emit_expr(&args[0]);
                if self.terminated {
                    return String::new();
                }
                let (path, path_is_arg, path_capacity) = self.emit_io_bytes_argument(&args[1]);
                if self.terminated {
                    return String::new();
                }
                let result_storage = self.entry_alloca(expr.ty);
                match target {
                    CallTarget::FsRead => {
                        let buffer = self.emit_expr_storage(&args[2]);
                        if self.terminated {
                            return String::new();
                        }
                        if let TTypeKind::List { capacity, .. } =
                            self.program.types[args[2].ty.0].kind
                        {
                            self.instruction(format!("call void @nl_fs_read(ptr {fs}, ptr {path}, i32 {path_is_arg}, i64 {path_capacity}, ptr {buffer}, i64 {capacity}, ptr {result_storage})"));
                        } else {
                            let is_text = self.is_text_type(args[2].ty);
                            let byte_offset = if is_text { 24 } else { 16 };
                            let output_data = self.temp();
                            self.instruction(format!(
                                "{output_data} = getelementptr i8, ptr {buffer}, i64 {byte_offset}"
                            ));
                            let data_field = self.temp();
                            self.instruction(format!(
                                "{data_field} = getelementptr {}, ptr {buffer}, i32 0, i32 0",
                                self.lltype(args[2].ty)
                            ));
                            self.instruction(format!(
                                "store ptr {output_data}, ptr {data_field}, align 1"
                            ));
                            let length_field = self.temp();
                            self.instruction(format!(
                                "{length_field} = getelementptr {}, ptr {buffer}, i32 0, i32 1",
                                self.lltype(args[2].ty)
                            ));
                            if is_text {
                                let cp_field = self.temp();
                                self.instruction(format!(
                                    "{cp_field} = getelementptr {}, ptr {buffer}, i32 0, i32 2",
                                    self.lltype(args[2].ty)
                                ));
                                let (codepoints, _) = match self.program.types[args[2].ty.0].kind {
                                    TTypeKind::Text {
                                        max_codepoints,
                                        max_bytes,
                                    } => (max_codepoints, max_bytes),
                                    _ => unreachable!(),
                                };
                                self.instruction(format!("call void @nl_fs_read_string(ptr {fs}, ptr {path}, i32 {path_is_arg}, i64 {path_capacity}, ptr {output_data}, i64 {}, i32 1, i64 {codepoints}, ptr {length_field}, ptr {cp_field}, ptr {result_storage})", self.ascii_max(args[2].ty).unwrap_or(0)));
                            } else {
                                self.instruction(format!("call void @nl_fs_read_string(ptr {fs}, ptr {path}, i32 {path_is_arg}, i64 {path_capacity}, ptr {output_data}, i64 {}, i32 0, i64 0, ptr {length_field}, ptr null, ptr {result_storage})", self.ascii_max(args[2].ty).unwrap_or(0)));
                            }
                        }
                    }
                    CallTarget::FsList => {
                        let output = self.emit_expr_storage(&args[2]);
                        if self.terminated {
                            return String::new();
                        }
                        let TTypeKind::List { capacity, .. } =
                            self.program.types[args[2].ty.0].kind
                        else {
                            unreachable!()
                        };
                        self.instruction(format!("call void @nl_fs_list(ptr {fs}, ptr {path}, i32 {path_is_arg}, i64 {path_capacity}, ptr {output}, i64 {capacity}, ptr {result_storage})"));
                    }
                    CallTarget::FsWrite => {
                        let (data, data_is_arg, data_capacity) =
                            self.emit_io_bytes_argument(&args[2]);
                        if self.terminated {
                            return String::new();
                        }
                        self.instruction(format!("call void @nl_fs_write(ptr {fs}, ptr {path}, i32 {path_is_arg}, i64 {path_capacity}, ptr {data}, i32 {data_is_arg}, i64 {data_capacity}, ptr {result_storage})"));
                    }
                    _ => unreachable!(),
                }
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {result_storage}, align 1",
                    self.lltype(expr.ty)
                ));
                value
            }
            CallTarget::FsJoin => {
                let result_storage = self.entry_alloca(expr.ty);
                self.emit_capability_call_to(&result_storage, expr, target, args);
                if self.terminated {
                    return String::new();
                }
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {result_storage}, align 1",
                    self.lltype(expr.ty)
                ));
                value
            }
            CallTarget::OutWrite
            | CallTarget::OutLine
            | CallTarget::OutInt
            | CallTarget::OutLong => {
                let output = self.emit_expr(&args[0]);
                if self.terminated {
                    return String::new();
                }
                let result_storage = self.entry_alloca(expr.ty);
                match target {
                    CallTarget::OutWrite | CallTarget::OutLine => {
                        if matches!(
                            self.program.types[args[1].ty.0].kind,
                            TTypeKind::Capability(CapabilityKind::Arg)
                        ) {
                            let data = self.emit_expr(&args[1]);
                            if self.terminated {
                                return String::new();
                            }
                            self.instruction(format!("call void @nl_out_arg(ptr {output}, ptr {data}, i32 {}, ptr {result_storage})", i32::from(matches!(target, CallTarget::OutLine))));
                        } else {
                            let (data, data_is_arg, capacity) =
                                self.emit_io_bytes_argument(&args[1]);
                            if self.terminated {
                                return String::new();
                            }
                            self.instruction(format!("call void @nl_out_write(ptr {output}, ptr {data}, i32 {data_is_arg}, i64 {capacity}, i32 {}, ptr {result_storage})", i32::from(matches!(target, CallTarget::OutLine))));
                        }
                    }
                    CallTarget::OutInt => {
                        let value = self.emit_expr(&args[1]);
                        if self.terminated {
                            return String::new();
                        }
                        self.instruction(format!(
                            "call void @nl_out_int(ptr {output}, i32 {value}, ptr {result_storage})"
                        ));
                    }
                    CallTarget::OutLong => {
                        let value = self.emit_expr(&args[1]);
                        if self.terminated {
                            return String::new();
                        }
                        self.instruction(format!("call void @nl_out_long(ptr {output}, i64 {value}, ptr {result_storage})"));
                    }
                    _ => unreachable!(),
                }
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {result_storage}, align 1",
                    self.lltype(expr.ty)
                ));
                value
            }
            CallTarget::Function(_)
            | CallTarget::Print
            | CallTarget::Min
            | CallTarget::Max
            | CallTarget::Sort { .. }
            | CallTarget::SortBy { .. }
            | CallTarget::BinarySearch { .. } => unreachable!(),
        }
    }

    fn emit_option_pointer(
        &mut self,
        option_ty: Ty,
        pointer: &str,
        present: &str,
        payload_ty: Ty,
    ) -> String {
        let some_label = self.new_label("option.ptr.some");
        let none_label = self.new_label("option.ptr.none");
        let merge = self.new_label("option.ptr.end");
        self.terminate(format!(
            "br i1 {present}, label %{some_label}, label %{none_label}"
        ));
        self.start_block(&some_label);
        let some_value =
            self.emit_construct_values(option_ty, 0, vec![(payload_ty, pointer.to_owned())]);
        let some_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&none_label);
        let none_value = self.emit_construct_values(option_ty, 1, Vec::new());
        let none_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge}"));
        self.start_block(&merge);
        let result = self.temp();
        self.instruction(format!(
            "{result} = phi {} [ {some_value}, %{some_pred} ], [ {none_value}, %{none_pred} ]",
            self.lltype(option_ty)
        ));
        result
    }

    fn emit_capability_call_to(
        &mut self,
        destination: &str,
        _expr: &TExpr,
        target: &CallTarget,
        args: &[TExpr],
    ) {
        if matches!(target, CallTarget::FsJoin) {
            let fs = self.emit_expr(&args[0]);
            let (dir, dir_is_arg, dir_capacity) = self.emit_io_bytes_argument(&args[1]);
            let (name, name_is_arg, name_capacity) = self.emit_io_bytes_argument(&args[2]);
            self.instruction(format!("call void @nl_fs_join(ptr {fs}, ptr {dir}, i32 {dir_is_arg}, i64 {dir_capacity}, ptr {name}, i32 {name_is_arg}, i64 {name_capacity}, ptr {destination})"));
        }
    }

    fn emit_expr_inner(&mut self, expr: &TExpr) -> String {
        if self.terminated {
            return String::new();
        }
        match &expr.kind {
            TExprKind::Unit => String::new(),
            TExprKind::Integer(value) => value.to_string(),
            TExprKind::Bool(value) => if *value { "true" } else { "false" }.to_owned(),
            TExprKind::ByteString(bytes) if self.ascii_max(expr.ty).is_some() => {
                let pointer = self.entry_alloca(expr.ty);
                self.emit_expr_to(&pointer, expr);
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {pointer}, align 1",
                    self.lltype(expr.ty)
                ));
                value
            }
            TExprKind::ByteString(bytes) => {
                let pointer = self.entry_alloca(expr.ty);
                self.emit_byte_string_to(&pointer, expr.ty, bytes);
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {pointer}, align 1",
                    self.lltype(expr.ty)
                ));
                value
            }
            TExprKind::Local(id) => {
                if let Some(view) = self.views.get(id).cloned() {
                    let index = self.temp();
                    self.instruction(format!(
                        "{index} = load i64, ptr %local.{}, align 1",
                        view.counter_id
                    ));
                    return self.emit_collection_element(
                        view.collection_ty,
                        &view.collection_ptr,
                        &index,
                    );
                }
                let tmp = self.temp();
                self.instruction(format!(
                    "{tmp} = load {}, ptr {}, align 1",
                    self.lltype(expr.ty),
                    self.local_pointer(*id)
                ));
                tmp
            }
            TExprKind::Global(id) => {
                if base_type(expr.ty, &self.program.types) == Ty::Unit {
                    String::new()
                } else {
                    let pointer = self.global_pointer(*id);
                    let tmp = self.temp();
                    self.instruction(format!(
                        "{tmp} = load {}, ptr {pointer}, align 1",
                        self.lltype(expr.ty)
                    ));
                    tmp
                }
            }
            TExprKind::Constant(id) => {
                if base_type(expr.ty, &self.program.types) == Ty::Unit {
                    String::new()
                } else {
                    let tmp = self.temp();
                    self.instruction(format!(
                        "{tmp} = load {}, ptr @nl.const.{id}, align 1",
                        self.lltype(expr.ty)
                    ));
                    tmp
                }
            }
            TExprKind::FunctionValue(id) => format!("@nl_fn_{id}"),
            TExprKind::Call { .. } => unreachable!("calls use the split emitter path"),
            TExprKind::IndirectCall {
                callee,
                args,
                params,
                ..
            } => self.emit_indirect_call(callee, args, params, expr.ty, None, expr.span),
            TExprKind::Construct { case_index, args } => {
                self.emit_construct(expr.ty, *case_index, args)
            }
            TExprKind::Method { kind, receiver } => self.emit_method(expr, *kind, receiver),
            TExprKind::AsciiEmpty | TExprKind::TextEmpty | TExprKind::BytesEmpty => {
                "zeroinitializer".to_owned()
            }
            TExprKind::AsciiUpper(_)
            | TExprKind::TextUpper(_)
            | TExprKind::AsciiFormat(_)
            | TExprKind::AsciiCast(_)
            | TExprKind::AsciiFit { .. } => {
                let pointer = self.entry_alloca(expr.ty);
                self.emit_expr_to(&pointer, expr);
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {pointer}, align 1",
                    self.lltype(expr.ty)
                ));
                value
            }
            TExprKind::TextSlice { .. }
            | TExprKind::BytesSlice { .. }
            | TExprKind::BytesView(_)
            | TExprKind::TextConvert { .. } => {
                let pointer = self.entry_alloca(expr.ty);
                self.emit_expr_to(&pointer, expr);
                let value = self.temp();
                self.instruction(format!(
                    "{value} = load {}, ptr {pointer}, align 1",
                    self.lltype(expr.ty)
                ));
                value
            }
            TExprKind::AsciiTryAppend { receiver, argument } => {
                self.emit_ascii_try_append(expr, receiver, argument)
            }
            TExprKind::Take(value) => self.emit_expr(value),
            TExprKind::Index {
                receiver,
                index,
                proven,
                grid,
                ..
            } => {
                if let Some(place) = Self::expr_place(expr) {
                    self.emit_load_place(&place)
                } else {
                    // A returned or otherwise temporary collection can be indexed for reading.
                    // Capture it once before evaluating the index, preserving left-to-right order.
                    let pointer = self.emit_expr_storage(receiver);
                    if self.terminated {
                        return String::new();
                    }
                    let index_value = if let Some(grid) = grid {
                        self.emit_grid_index_value(grid)
                    } else {
                        self.emit_expr(index)
                    };
                    if self.terminated {
                        return String::new();
                    }
                    if grid.is_none() && !*proven {
                        self.emit_index_guard(
                            receiver.ty,
                            &pointer,
                            &index_value,
                            false,
                            index.span,
                        );
                    }
                    self.emit_collection_element(receiver.ty, &pointer, &index_value)
                }
            }
            TExprKind::Fill { value, capacity } => self.emit_fill(expr.ty, value, *capacity),
            TExprKind::EmptyArray
            | TExprKind::EmptyGrid
            | TExprKind::EmptyList
            | TExprKind::EmptyMap
            | TExprKind::EmptySet
            | TExprKind::EmptyQueue
            | TExprKind::EmptyRing => "zeroinitializer".to_owned(),
            TExprKind::EmptyPool => self.emit_pool_init(expr.ty),
            TExprKind::CollectionOp {
                op,
                receiver,
                args,
                capacity,
                proven_success,
            } => {
                self.emit_collection_op(expr, *op, receiver, args, *capacity, *proven_success, None)
            }
            TExprKind::PoolOp {
                op,
                receiver,
                args,
                capacity,
                proven_success,
            } => self.emit_pool_op(expr, *op, receiver, args, *capacity, *proven_success, None),
            TExprKind::MapOp {
                op,
                receiver,
                args,
                capacity,
                proven_success,
            } => self.emit_map_op(expr, *op, receiver, args, *capacity, *proven_success, None),
            TExprKind::SetOp {
                op,
                receiver,
                args,
                capacity,
                proven_success,
            } => self.emit_set_op(expr, *op, receiver, args, *capacity, *proven_success),
            TExprKind::OptionalToLong(receiver) => self.emit_optional_to_long(expr, receiver),
            TExprKind::Field {
                receiver,
                field_index,
            } => {
                let receiver_pointer = self.emit_expr_storage(receiver);
                if self.terminated {
                    return String::new();
                }
                let field_pointer = self.temp();
                self.instruction(format!(
                    "{field_pointer} = getelementptr inbounds {}, ptr {receiver_pointer}, i32 0, i32 {field_index}",
                    self.lltype(receiver.ty)
                ));
                let result = self.temp();
                self.instruction(format!(
                    "{result} = load {}, ptr {field_pointer}, align 1",
                    self.lltype(expr.ty)
                ));
                result
            }
            TExprKind::StructConstruct { fields } => self.emit_struct_construct(expr.ty, fields),
            TExprKind::Convert {
                value,
                min,
                max,
                policy,
            } => {
                let source = self.emit_expr(value);
                self.emit_policy_conversion_values(
                    source,
                    base_type(expr.ty, &self.program.types),
                    *min,
                    *max,
                    *policy,
                    expr.span,
                )
            }
            TExprKind::Fit {
                value,
                min,
                max,
                option_ty,
            } => self.emit_fit(expr, value, *min, *max, *option_ty),
            TExprKind::OptionalCall {
                receiver,
                function_id,
                args,
                wraps_result,
            } => self.emit_optional_call(expr, receiver, *function_id, args, *wraps_result),
            TExprKind::Try {
                value,
                success_ty,
                error_ty,
                propagated_ty,
            } => self.emit_try(expr, value, *success_ty, *error_ty, *propagated_ty),
            TExprKind::Coalesce { option, fallback } => self.emit_coalesce(expr, option, fallback),
            TExprKind::Match { scrutinee, arms } => self.emit_match(expr, scrutinee, arms, None),
            TExprKind::Return(value) => {
                if let Some(value) = value {
                    if is_large_type(self.function.result, &self.program.types) {
                        self.emit_expr_to("%nl.result", value);
                        if !self.terminated {
                            self.emit_all_iteration_cleanups();
                            self.terminate("ret void");
                        }
                        return String::new();
                    }
                    let result = self.emit_expr(value);
                    if !self.terminated {
                        self.emit_all_iteration_cleanups();
                        self.terminate(format!(
                            "ret {} {result}",
                            self.lltype(self.function.result)
                        ));
                    }
                } else {
                    self.emit_all_iteration_cleanups();
                    self.terminate("ret void");
                }
                String::new()
            }
            TExprKind::LoopExit(is_break) => {
                self.emit_iteration_cleanup();
                let target = self.loops.last().expect("checker validated loop exit");
                self.terminate(format!(
                    "br label %{}",
                    if *is_break {
                        &target.exit
                    } else {
                        &target.latch
                    }
                ));
                String::new()
            }
            TExprKind::ToLong(value) => {
                let source = self.emit_expr(value);
                let tmp = self.temp();
                self.instruction(format!("{tmp} = sext i32 {source} to i64"));
                tmp
            }
            TExprKind::Cast { cast_span, value } => {
                let source = self.emit_expr(value);
                let from = base_type(value.ty, &self.program.types);
                let to = base_type(expr.ty, &self.program.types);
                let converted = match (from, to) {
                    (Ty::Int, Ty::Long) => {
                        let tmp = self.temp();
                        self.instruction(format!("{tmp} = sext i32 {source} to i64"));
                        tmp
                    }
                    (Ty::Long, Ty::Int) => {
                        let narrowed = self.temp();
                        self.instruction(format!("{narrowed} = trunc i64 {source} to i32"));
                        let restored = self.temp();
                        self.instruction(format!("{restored} = sext i32 {narrowed} to i64"));
                        let ok = self.temp();
                        self.instruction(format!("{ok} = icmp eq i64 {restored}, {source}"));
                        let bad = self.temp();
                        self.instruction(format!("{bad} = xor i1 {ok}, true"));
                        self.guard(bad, Failure::BadCast, *cast_span);
                        narrowed
                    }
                    _ => source,
                };
                if let Some((_, min, max, _)) = refinement(expr.ty, &self.program.types) {
                    let llvm_ty = self.lltype(to);
                    let below = self.temp();
                    self.instruction(format!("{below} = icmp slt {llvm_ty} {converted}, {min}"));
                    let above = self.temp();
                    self.instruction(format!("{above} = icmp sgt {llvm_ty} {converted}, {max}"));
                    let bad = self.temp();
                    self.instruction(format!("{bad} = or i1 {below}, {above}"));
                    self.guard(bad, Failure::BadCast, *cast_span);
                }
                converted
            }
            TExprKind::Unary {
                op,
                operator_span,
                value,
            } => {
                let operand = self.emit_expr(value);
                match op {
                    UnaryOp::Not => {
                        let tmp = self.temp();
                        self.instruction(format!("{tmp} = xor i1 {operand}, true"));
                        tmp
                    }
                    UnaryOp::Neg => {
                        let primitive = base_type(expr.ty, &self.program.types);
                        let result = self.temp();
                        let zero = if primitive == Ty::Int {
                            "i32 0"
                        } else {
                            "i64 0"
                        };
                        let width = width(primitive);
                        let pair = self.temp();
                        self.instruction(format!("{pair} = call {{ i{width}, i1 }} @llvm.ssub.with.overflow.i{width}(i{width} 0, i{width} {operand})"));
                        self.instruction(format!(
                            "{result} = extractvalue {{ i{width}, i1 }} {pair}, 0"
                        ));
                        let overflow = self.temp();
                        self.instruction(format!(
                            "{overflow} = extractvalue {{ i{width}, i1 }} {pair}, 1"
                        ));
                        let _ = zero;
                        self.guard(
                            overflow,
                            failure_for(primitive, BinaryOp::Sub, true),
                            *operator_span,
                        );
                        result
                    }
                }
            }
            TExprKind::Binary { .. } | TExprKind::If { .. } => {
                unreachable!("binary and if expressions use the split emitter path")
            }
        }
    }

    fn emit_binary(&mut self, op: BinaryOp, ty: Ty, lhs: &str, rhs: &str, span: Span) -> String {
        if self.ascii_max(ty).is_some() {
            let left_data = self.ascii_field(lhs, ty, 0);
            let left_length = self.ascii_field(lhs, ty, 1);
            let right_data = self.ascii_field(rhs, ty, 0);
            let right_length = self.ascii_field(rhs, ty, 1);
            let order = self.temp();
            self.instruction(format!(
                "{order} = call i32 @nl_ascii_compare(ptr {left_data}, i64 {left_length}, ptr {right_data}, i64 {right_length})"
            ));
            let comparison = match op {
                BinaryOp::Eq => "eq",
                BinaryOp::Ne => "ne",
                BinaryOp::Lt => "slt",
                BinaryOp::Le => "sle",
                BinaryOp::Gt => "sgt",
                BinaryOp::Ge => "sge",
                _ => unreachable!("checker permits only bytewise Ascii comparisons"),
            };
            let result = self.temp();
            self.instruction(format!("{result} = icmp {comparison} i32 {order}, 0"));
            let _ = span;
            return result;
        }
        let primitive = base_type(ty, &self.program.types);
        if matches!(op, BinaryOp::Eq | BinaryOp::Ne)
            && matches!(self.program.types[ty.0].kind, TTypeKind::Function { .. })
        {
            let equal = self.temp();
            self.instruction(format!("{equal} = icmp eq ptr {lhs}, {rhs}"));
            if op == BinaryOp::Eq {
                return equal;
            }
            let result = self.temp();
            self.instruction(format!("{result} = xor i1 {equal}, true"));
            return result;
        }
        if matches!(op, BinaryOp::Eq | BinaryOp::Ne)
            && matches!(self.program.types[ty.0].kind, TTypeKind::Id { .. })
        {
            let equal = self.temp();
            self.instruction(format!("{equal} = icmp eq i64 {lhs}, {rhs}"));
            if op == BinaryOp::Eq {
                return equal;
            }
            let result = self.temp();
            self.instruction(format!("{result} = xor i1 {equal}, true"));
            return result;
        }
        if matches!(op, BinaryOp::Eq | BinaryOp::Ne)
            && !matches!(primitive, Ty::Int | Ty::Long | Ty::Bool)
        {
            let equal = self.emit_structural_equal(ty, lhs, rhs);
            if op == BinaryOp::Eq {
                return equal;
            }
            let result = self.temp();
            self.instruction(format!("{result} = xor i1 {equal}, true"));
            return result;
        }
        let ty = primitive;
        let llvm_ty = self.lltype(ty);
        if matches!(
            op,
            BinaryOp::Add
                | BinaryOp::Sub
                | BinaryOp::Mul
                | BinaryOp::WrapAdd
                | BinaryOp::WrapSub
                | BinaryOp::WrapMul
        ) {
            let operation = match op {
                BinaryOp::Add | BinaryOp::WrapAdd => "add",
                BinaryOp::Sub | BinaryOp::WrapSub => "sub",
                BinaryOp::Mul | BinaryOp::WrapMul => "mul",
                _ => unreachable!(),
            };
            if matches!(
                op,
                BinaryOp::WrapAdd | BinaryOp::WrapSub | BinaryOp::WrapMul
            ) {
                let result = self.temp();
                self.instruction(format!("{result} = {operation} {llvm_ty} {lhs}, {rhs}"));
                return result;
            }
            let w = width(ty);
            let intrinsic = match op {
                BinaryOp::Add => "sadd",
                BinaryOp::Sub => "ssub",
                BinaryOp::Mul => "smul",
                _ => unreachable!(),
            };
            let pair = self.temp();
            self.instruction(format!("{pair} = call {{ i{w}, i1 }} @llvm.{intrinsic}.with.overflow.i{w}(i{w} {lhs}, i{w} {rhs})"));
            let result = self.temp();
            self.instruction(format!("{result} = extractvalue {{ i{w}, i1 }} {pair}, 0"));
            let overflow = self.temp();
            self.instruction(format!(
                "{overflow} = extractvalue {{ i{w}, i1 }} {pair}, 1"
            ));
            self.guard(overflow, failure_for(ty, op, false), span);
            return result;
        }
        match op {
            BinaryOp::Div | BinaryOp::Rem => self.emit_div_rem(op, ty, lhs, rhs, span),
            BinaryOp::Shl | BinaryOp::Shr => {
                let negative = self.temp();
                self.instruction(format!("{negative} = icmp slt {llvm_ty} {rhs}, 0"));
                let high = self.temp();
                self.instruction(format!("{high} = icmp sge {llvm_ty} {rhs}, {}", width(ty)));
                let bad = self.temp();
                self.instruction(format!("{bad} = or i1 {negative}, {high}"));
                self.guard(bad, Failure::BadShift, span);
                let result = self.temp();
                self.instruction(format!(
                    "{result} = {} {llvm_ty} {lhs}, {rhs}",
                    if op == BinaryOp::Shl { "shl" } else { "ashr" }
                ));
                result
            }
            BinaryOp::BitAnd | BinaryOp::BitOr | BinaryOp::BitXor => {
                let operation = match op {
                    BinaryOp::BitAnd => "and",
                    BinaryOp::BitOr => "or",
                    BinaryOp::BitXor => "xor",
                    _ => unreachable!(),
                };
                let result = self.temp();
                self.instruction(format!("{result} = {operation} {llvm_ty} {lhs}, {rhs}"));
                result
            }
            BinaryOp::Eq
            | BinaryOp::Ne
            | BinaryOp::Lt
            | BinaryOp::Le
            | BinaryOp::Gt
            | BinaryOp::Ge => {
                let predicate = match op {
                    BinaryOp::Eq => "eq",
                    BinaryOp::Ne => "ne",
                    BinaryOp::Lt => "slt",
                    BinaryOp::Le => "sle",
                    BinaryOp::Gt => "sgt",
                    BinaryOp::Ge => "sge",
                    _ => unreachable!(),
                };
                let result = self.temp();
                self.instruction(format!(
                    "{result} = icmp {predicate} {llvm_ty} {lhs}, {rhs}"
                ));
                result
            }
            _ => unreachable!(),
        }
    }

    fn emit_div_rem(&mut self, op: BinaryOp, ty: Ty, lhs: &str, rhs: &str, span: Span) -> String {
        let llvm_ty = self.lltype(ty);
        let zero = self.temp();
        self.instruction(format!("{zero} = icmp eq {llvm_ty} {rhs}, 0"));
        self.guard(zero, Failure::DivideByZero, span);
        let w = width(ty);
        let min = if ty == Ty::Int {
            i32::MIN.to_string()
        } else {
            i64::MIN.to_string()
        };
        let is_min = self.temp();
        self.instruction(format!("{is_min} = icmp eq {llvm_ty} {lhs}, {min}"));
        let is_neg_one = self.temp();
        self.instruction(format!("{is_neg_one} = icmp eq {llvm_ty} {rhs}, -1"));
        let special = self.temp();
        self.instruction(format!("{special} = and i1 {is_min}, {is_neg_one}"));
        if op == BinaryOp::Div {
            self.guard(special, failure_for(ty, BinaryOp::Div, false), span);
            let result = self.temp();
            self.instruction(format!("{result} = sdiv i{w} {lhs}, {rhs}"));
            result
        } else {
            let special_label = self.new_label("rem.zero");
            let normal_label = self.new_label("rem.normal");
            let merge_label = self.new_label("rem.end");
            self.terminate(format!(
                "br i1 {special}, label %{special_label}, label %{normal_label}"
            ));
            self.start_block(&special_label);
            let special_pred = self.current_label.clone();
            self.terminate(format!("br label %{merge_label}"));
            self.start_block(&normal_label);
            let normal = self.temp();
            self.instruction(format!("{normal} = srem i{w} {lhs}, {rhs}"));
            let normal_pred = self.current_label.clone();
            self.terminate(format!("br label %{merge_label}"));
            self.start_block(&merge_label);
            let result = self.temp();
            self.instruction(format!(
                "{result} = phi i{w} [ 0, %{special_pred} ], [ {normal}, %{normal_pred} ]"
            ));
            result
        }
    }

    fn emit_short_circuit(&mut self, op: BinaryOp, left: &TExpr, right: &TExpr) -> String {
        let lhs = self.emit_expr(left);
        let rhs_label = self.new_label("logic.rhs");
        let short_label = self.new_label("logic.short");
        let merge_label = self.new_label("logic.end");
        let (true_target, false_target) = if op == BinaryOp::And {
            (&rhs_label, &short_label)
        } else {
            (&short_label, &rhs_label)
        };
        self.terminate(format!(
            "br i1 {lhs}, label %{true_target}, label %{false_target}"
        ));
        self.start_block(&short_label);
        let short_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge_label}"));
        self.start_block(&rhs_label);
        let rhs_value = self.emit_expr(right);
        if self.terminated {
            self.start_block(&merge_label);
            return if op == BinaryOp::And { "false" } else { "true" }.to_owned();
        }
        let rhs_pred = self.current_label.clone();
        self.terminate(format!("br label %{merge_label}"));
        self.start_block(&merge_label);
        let result = self.temp();
        let short_value = if op == BinaryOp::And { "false" } else { "true" };
        self.instruction(format!(
            "{result} = phi i1 [ {short_value}, %{short_pred} ], [ {rhs_value}, %{rhs_pred} ]"
        ));
        result
    }

    fn emit_if(
        &mut self,
        condition: &TExpr,
        then_block: &TBlock,
        else_block: Option<&TBlock>,
        result_ty: Ty,
        value_context: bool,
        _span: Span,
    ) -> String {
        let cond = self.emit_expr(condition);
        let incoming_top = self.stack_top.clone();
        let condition_pred = self.current_label.clone();
        let then_label = self.new_label("if.then");
        let else_label = else_block.map(|_| self.new_label("if.else"));
        let merge_label = self.new_label("if.end");
        if let Some(other) = &else_label {
            self.terminate(format!("br i1 {cond}, label %{then_label}, label %{other}"));
        } else {
            self.terminate(format!(
                "br i1 {cond}, label %{then_label}, label %{merge_label}"
            ));
        }

        self.start_block(&then_label);
        let then_value = self.emit_branch_block(then_block, &merge_label);
        let then_live = !self.terminated;
        let then_pred = self.current_label.clone();
        if then_live {
            self.terminate(format!("br label %{merge_label}"));
        }
        self.stack_top = incoming_top.clone();

        let (else_value, else_live, else_pred) =
            if let (Some(block), Some(label)) = (else_block, else_label.as_ref()) {
                self.start_block(label);
                let value = self.emit_branch_block(block, &merge_label);
                let live = !self.terminated;
                let pred = self.current_label.clone();
                if live {
                    self.terminate(format!("br label %{merge_label}"));
                }
                self.stack_top = incoming_top.clone();
                (value, live, Some(pred))
            } else {
                // The false condition edge itself reaches the merge block.
                (None, true, Some(condition_pred))
            };

        let any_live = then_live || else_live;
        if !any_live {
            self.terminated = true;
            return String::new();
        }
        self.start_block(&merge_label);
        self.stack_top = incoming_top;
        if !value_context || result_ty == Ty::Unit || result_ty == Ty::Never {
            return String::new();
        }
        match (then_live, else_live, then_value, else_value) {
            (true, true, Some(tv), Some(ev)) => {
                let result = self.temp();
                self.instruction(format!(
                    "{result} = phi {} [ {tv}, %{then_pred} ], [ {ev}, %{} ]",
                    self.lltype(result_ty),
                    else_pred.unwrap()
                ));
                result
            }
            (true, false, Some(tv), _) => tv,
            (false, true, _, Some(ev)) => ev,
            _ => String::new(),
        }
    }

    fn emit_branch_block(&mut self, block: &TBlock, _merge: &str) -> Option<String> {
        let saved_top = self.stack_top.clone();
        self.emit_block_contents(block);
        if self.terminated {
            return None;
        }
        let value = if let Some(tail) = &block.tail {
            let value = self.emit_expr(tail);
            if self.terminated {
                return None;
            }
            if tail.ty == Ty::Unit {
                None
            } else {
                Some(value)
            }
        } else {
            None
        };
        if !self.terminated {
            self.restore_stack_top(&saved_top);
        }
        Some(value.unwrap_or_default())
    }

    fn guard(&mut self, bad: String, failure: Failure, span: Span) {
        let fail_label = self.new_label("fail");
        let okay_label = self.new_label("ok");
        self.terminate(format!(
            "br i1 {bad}, label %{fail_label}, label %{okay_label}, !prof !0"
        ));
        self.start_block(&fail_label);
        self.instruction(format!(
            "call void @nl_fail(i32 {}, i32 {}, i32 {}, i32 {})",
            failure as i32, span.file, span.line, span.col
        ));
        self.terminate("unreachable");
        self.start_block(&okay_label);
    }

    fn instruction(&mut self, text: impl Into<String>) {
        debug_assert!(
            !self.terminated,
            "instruction after terminator in {}",
            self.function.name
        );
        self.lines.push(format!("  {}", text.into()));
    }

    fn terminate(&mut self, text: impl Into<String>) {
        debug_assert!(
            !self.terminated,
            "duplicate terminator in {}",
            self.function.name
        );
        let text = text.into();
        if text.starts_with("ret ") {
            self.lines.push(format!(
                "  call void @nl_context_set_top(ptr %nl.ctx, ptr %nl.entry.top)"
            ));
        }
        self.lines.push(format!("  {text}"));
        self.terminated = true;
    }

    fn start_block(&mut self, label: &str) {
        self.lines.push(format!("{label}:"));
        self.current_label = label.to_owned();
        self.terminated = false;
    }

    fn temp(&mut self) -> String {
        let value = format!("%t{}", self.temp);
        self.temp += 1;
        value
    }

    fn new_label(&mut self, prefix: &str) -> String {
        let value = format!("{prefix}.{}", self.label);
        self.label += 1;
        value
    }
}

#[derive(Clone, Copy)]
enum Failure {
    OverflowIntAdd = 1,
    OverflowIntSub = 2,
    OverflowIntMul = 3,
    OverflowIntNeg = 4,
    OverflowLongAdd = 5,
    OverflowLongSub = 6,
    OverflowLongMul = 7,
    OverflowLongNeg = 8,
    DivideByZero = 9,
    BadCast = 10,
    BadShift = 11,
    OverflowIntDiv = 12,
    OverflowLongDiv = 13,
    UnwrapNone = 14,
    UnwrapErr = 15,
    IndexOutOfRange = 16,
    UnsortedInput = 17,
}

fn failure_for(ty: Ty, op: BinaryOp, unary: bool) -> Failure {
    match (ty, op, unary) {
        (Ty::Int, _, true) => Failure::OverflowIntNeg,
        (Ty::Long, _, true) => Failure::OverflowLongNeg,
        (Ty::Int, BinaryOp::Add, _) => Failure::OverflowIntAdd,
        (Ty::Int, BinaryOp::Sub, _) => Failure::OverflowIntSub,
        (Ty::Int, BinaryOp::Mul, _) => Failure::OverflowIntMul,
        (Ty::Long, BinaryOp::Add, _) => Failure::OverflowLongAdd,
        (Ty::Long, BinaryOp::Sub, _) => Failure::OverflowLongSub,
        (Ty::Long, BinaryOp::Mul, _) => Failure::OverflowLongMul,
        (Ty::Int, BinaryOp::Div, _) => Failure::OverflowIntDiv,
        (Ty::Long, BinaryOp::Div, _) => Failure::OverflowLongDiv,
        _ => unreachable!(),
    }
}

fn width(ty: Ty) -> u32 {
    if ty == Ty::Int { 32 } else { 64 }
}

fn assign_binary(op: AssignOp) -> BinaryOp {
    match op {
        AssignOp::Add => BinaryOp::Add,
        AssignOp::Sub => BinaryOp::Sub,
        AssignOp::Mul => BinaryOp::Mul,
        AssignOp::Div => BinaryOp::Div,
        AssignOp::Rem => BinaryOp::Rem,
        AssignOp::Shr => BinaryOp::Shr,
        AssignOp::Set => unreachable!(),
    }
}

struct LoweredSignature {
    result: String,
    params: Vec<String>,
    result_destination: bool,
}

// All language function ABI decisions live here, including the hidden stack
// context/top arguments and caller-owned destinations for large results.
fn lower_signature(function: &TFunction, types: &[TType]) -> LoweredSignature {
    let result_destination = !function.is_test && is_large_type(function.result, types);
    LoweredSignature {
        result: if function.is_test {
            "i32".to_owned()
        } else if result_destination {
            "void".to_owned()
        } else {
            llvm_type(function.result, types)
        },
        params: function
            .params
            .iter()
            .map(|param| {
                if param.mode != ParamMode::Read
                    || matches!(types[param.ty.0].kind, TTypeKind::Pool { .. })
                    || is_large_type(param.ty, types)
                {
                    if param.mode != ParamMode::Read && !result_destination {
                        "ptr noalias".to_owned()
                    } else {
                        "ptr".to_owned()
                    }
                } else {
                    llvm_type(param.ty, types)
                }
            })
            .collect(),
        result_destination,
    }
}

#[cfg(test)]
mod stack_reservation_tests {
    use super::{STACK_PAGE_BYTES, UNBOUNDED_DATA_STACK_DEFAULT, data_stack_reservation};

    #[test]
    fn unbounded_entry_uses_the_64_mib_default() {
        assert_eq!(data_stack_reservation(None), UNBOUNDED_DATA_STACK_DEFAULT);
    }

    #[test]
    fn bounded_reservations_round_up_without_a_64_mib_cap() {
        assert_eq!(data_stack_reservation(Some(1)), STACK_PAGE_BYTES);
        assert_eq!(
            data_stack_reservation(Some(1024 * 1024 * 1024)),
            1024 * 1024 * 1024 + STACK_PAGE_BYTES
        );
    }
}
