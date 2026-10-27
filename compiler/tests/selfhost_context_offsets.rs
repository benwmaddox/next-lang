use std::path::Path;
use std::process::Command;

fn run_frontend_independent_check() -> bool {
    // The C ABI probe and core source checks do not use the suite frontend.
    std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost")
}

#[test]
fn core_context_prefix_matches_the_offset_runtime_layout() {
    if !run_frontend_independent_check() {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let temporary =
        std::env::temp_dir().join(format!("next-lang-context-offsets-{}", std::process::id()));
    std::fs::create_dir_all(&temporary).expect("create temporary context-offset directory");
    let binary = temporary.join("context-offsets");
    let source = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/selfhost_context_offsets.c");
    let build = Command::new("clang")
        .args(["-O0", "-pthread"])
        .arg(&source)
        .arg("-o")
        .arg(&binary)
        .output()
        .expect("start clang for the context-offset probe");
    assert!(
        build.status.success(),
        "context-offset probe failed to compile: {}",
        String::from_utf8_lossy(&build.stderr)
    );
    let run = Command::new(&binary)
        .output()
        .expect("run the context-offset probe");
    assert!(run.status.success());
    let c_offsets: Vec<usize> = String::from_utf8(run.stdout)
        .expect("C probe output is UTF-8")
        .split_whitespace()
        .map(|value| value.parse().expect("C offset is an integer"))
        .collect();

    let declaration = std::fs::read_to_string(root.join("core/context.nl"))
        .expect("read the core context declaration");
    let context = declaration
        .split_once("struct DataStackContext {")
        .expect("core context struct is present")
        .1
        .split_once('}')
        .expect("core context struct is closed")
        .0;
    let fields: Vec<(&str, &str)> = context
        .lines()
        .filter_map(|line| {
            let (name, ty) = line.trim().split_once(':')?;
            Some((name.trim(), ty.trim()))
        })
        .take(15)
        .collect();
    let expected_names = [
        "header_mapping",
        "header_bytes",
        "mapping",
        "mapping_bytes",
        "reservation_bytes",
        "peak_used_bytes",
        "entry_name",
        "base",
        "top",
        "limit",
        "top_offset",
        "growth_count",
        "relocation_count",
        "growth_nanoseconds",
        "poison_records",
    ];
    assert_eq!(fields.len(), expected_names.len());
    for (index, ((name, ty), expected_name)) in fields.iter().zip(expected_names).enumerate() {
        assert_eq!(*name, expected_name, "context prefix field {index}");
        assert!(
            *ty == "sys.Addr" || *ty == "long",
            "unexpected context prefix type for {name}: {ty}"
        );
    }
    let core_offsets: Vec<usize> = (0..fields.len()).map(|index| index * 8).collect();
    assert_eq!(
        c_offsets, core_offsets,
        "DataStackContext offsets differ from the C offset-mode prefix"
    );
    std::fs::remove_dir_all(temporary).expect("remove temporary context-offset directory");
}

#[test]
fn legacy_c_hook_contracts_are_recorded_before_the_context_abi_switch() {
    if !run_frontend_independent_check() {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let temporary =
        std::env::temp_dir().join(format!("next-lang-hook-contracts-{}", std::process::id()));
    std::fs::create_dir_all(&temporary).expect("create temporary hook-contract directory");

    struct Fixture {
        name: &'static str,
        body: String,
        stdout: &'static [u8],
        stderr: &'static [u8],
        status: i32,
        test_index: Option<&'static str>,
    }

    let common_context = r#"
@entry = private unnamed_addr constant [9 x i8] c"contract\00"
declare ptr @nl_context_create(i64, i64, ptr)
declare i64 @nl_context_base_offset(ptr)
declare void @nl_context_destroy(ptr)
"#;
    let create_and_destroy = r#"
  %ctx = call ptr @nl_context_create(i64 262144, i64 0, ptr getelementptr inbounds ([9 x i8], ptr @entry, i64 0, i64 0))
  call void @nl_context_destroy(ptr %ctx)
  ret i32 0
"#;
    let expected_source = r#"
@file = private unnamed_addr constant [17 x i8] c"hook-contract.nl\00"
declare void @nl_register_file(i32, ptr)
"#;

    // Each body calls one entry in the E1c C hook table.  The expected bytes
    // were captured from runtime/nl_runtime.c while `; nlc.runtime c` still
    // linked that ABI.
    let fixtures = [
        Fixture {
            name: "context_create",
            body: format!("{common_context}define i32 @main(i32 %argc, ptr %argv, ptr %envp) {{\nentry:\n  %ctx = call ptr @nl_context_create(i64 262144, i64 0, ptr getelementptr inbounds ([9 x i8], ptr @entry, i64 0, i64 0))\n  %missing = icmp eq ptr %ctx, null\n  %status = select i1 %missing, i32 1, i32 0\n  ret i32 %status\n}}\n"),
            stdout: b"",
            stderr: b"",
            status: 0,
            test_index: None,
        },
        Fixture {
            name: "context_base_offset",
            body: format!("{common_context}define i32 @main(i32 %argc, ptr %argv, ptr %envp) {{\nentry:\n  %ctx = call ptr @nl_context_create(i64 262144, i64 0, ptr getelementptr inbounds ([9 x i8], ptr @entry, i64 0, i64 0))\n  %offset = call i64 @nl_context_base_offset(ptr %ctx)\n  call void @nl_context_destroy(ptr %ctx)\n  %is_zero = icmp eq i64 %offset, 0\n  %status = select i1 %is_zero, i32 0, i32 1\n  ret i32 %status\n}}\n"),
            stdout: b"",
            stderr: b"",
            status: 0,
            test_index: None,
        },
        Fixture {
            name: "context_destroy",
            body: format!("{common_context}define i32 @main(i32 %argc, ptr %argv, ptr %envp) {{\nentry:\n{create_and_destroy}}}\n"),
            stdout: b"",
            stderr: b"",
            status: 0,
            test_index: None,
        },
        Fixture {
            name: "env_create",
            body: "declare ptr @nl_env_create(i32, ptr, i32)\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {\nentry:\n  %env = call ptr @nl_env_create(i32 %argc, ptr %argv, i32 0)\n  %missing = icmp eq ptr %env, null\n  %status = select i1 %missing, i32 1, i32 0\n  ret i32 %status\n}\n".to_owned(),
            stdout: b"",
            stderr: b"",
            status: 0,
            test_index: None,
        },
        Fixture {
            name: "env_destroy",
            body: "declare ptr @nl_env_create(i32, ptr, i32)\ndeclare void @nl_env_destroy(ptr)\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {\nentry:\n  %env = call ptr @nl_env_create(i32 %argc, ptr %argv, i32 0)\n  call void @nl_env_destroy(ptr %env)\n  ret i32 0\n}\n".to_owned(),
            stdout: b"",
            stderr: b"",
            status: 0,
            test_index: None,
        },
        Fixture {
            name: "register_file",
            body: format!("{expected_source}declare void @nl_fail(i32, i32, i32, i32) noreturn\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {{\nentry:\n  call void @nl_register_file(i32 0, ptr getelementptr inbounds ([17 x i8], ptr @file, i64 0, i64 0))\n  call void @nl_fail(i32 1, i32 0, i32 1, i32 2)\n  unreachable\n}}\n"),
            stdout: b"",
            stderr: b"hook-contract.nl:1:2: overflow in int addition\n",
            status: 1,
            test_index: None,
        },
        Fixture {
            name: "test_selected_index",
            body: "declare i32 @nl_test_selected_index()\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {\nentry:\n  %index = call i32 @nl_test_selected_index()\n  ret i32 %index\n}\n".to_owned(),
            stdout: b"",
            stderr: b"",
            status: 7,
            test_index: Some("7"),
        },
        Fixture {
            name: "set_test_mode",
            body: "declare void @nl_set_test_mode()\ndeclare void @nl_fail(i32, i32, i32, i32) noreturn\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {\nentry:\n  call void @nl_set_test_mode()\n  call void @nl_fail(i32 1, i32 -1, i32 4, i32 9)\n  unreachable\n}\n".to_owned(),
            stdout: b"",
            stderr: b"<source>:4:9: overflow in int addition\n",
            status: 70,
            test_index: None,
        },
        Fixture {
            name: "print_int",
            body: format!("{common_context}declare void @nl_print_int(i32)\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {{\nentry:\n  %ctx = call ptr @nl_context_create(i64 262144, i64 0, ptr getelementptr inbounds ([9 x i8], ptr @entry, i64 0, i64 0))\n  call void @nl_print_int(i32 -2147483648)\n  call void @nl_context_destroy(ptr %ctx)\n  ret i32 0\n}}\n"),
            stdout: b"-2147483648\n",
            stderr: b"",
            status: 0,
            test_index: None,
        },
        Fixture {
            name: "print_long",
            body: format!("{common_context}declare void @nl_print_long(i64)\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {{\nentry:\n  %ctx = call ptr @nl_context_create(i64 262144, i64 0, ptr getelementptr inbounds ([9 x i8], ptr @entry, i64 0, i64 0))\n  call void @nl_print_long(i64 -9223372036854775808)\n  call void @nl_context_destroy(ptr %ctx)\n  ret i32 0\n}}\n"),
            stdout: b"-9223372036854775808\n",
            stderr: b"",
            status: 0,
            test_index: None,
        },
        Fixture {
            name: "print_bool",
            body: format!("{common_context}declare void @nl_print_bool(i1 zeroext)\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {{\nentry:\n  %ctx = call ptr @nl_context_create(i64 262144, i64 0, ptr getelementptr inbounds ([9 x i8], ptr @entry, i64 0, i64 0))\n  call void @nl_print_bool(i1 zeroext true)\n  call void @nl_context_destroy(ptr %ctx)\n  ret i32 0\n}}\n"),
            stdout: b"true\n",
            stderr: b"",
            status: 0,
            test_index: None,
        },
        Fixture {
            name: "fail",
            body: "declare void @nl_fail(i32, i32, i32, i32) noreturn\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {\nentry:\n  call void @nl_fail(i32 1, i32 -1, i32 4, i32 9)\n  unreachable\n}\n".to_owned(),
            stdout: b"",
            stderr: b"<source>:4:9: overflow in int addition\n",
            status: 1,
            test_index: None,
        },
        Fixture {
            name: "expect_fail_compare",
            body: format!("{expected_source}@source = private unnamed_addr constant [14 x i8] c\"left == right\\00\"\ndeclare void @nl_expect_fail_compare(i32, i32, i32, ptr, i64, i64, i32)\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {{\nentry:\n  call void @nl_register_file(i32 0, ptr getelementptr inbounds ([17 x i8], ptr @file, i64 0, i64 0))\n  call void @nl_expect_fail_compare(i32 0, i32 3, i32 4, ptr getelementptr inbounds ([14 x i8], ptr @source, i64 0, i64 0), i64 -9223372036854775808, i64 9223372036854775807, i32 0)\n  ret i32 0\n}}\n"),
            stdout: b"  hook-contract.nl:3:4: left == right\n    left:  -9223372036854775808\n    right: 9223372036854775807\n",
            stderr: b"",
            status: 0,
            test_index: None,
        },
        Fixture {
            name: "expect_fail_bool",
            body: format!("{expected_source}@source = private unnamed_addr constant [6 x i8] c\"ready\\00\"\ndeclare void @nl_expect_fail_bool(i32, i32, i32, ptr)\ndefine i32 @main(i32 %argc, ptr %argv, ptr %envp) {{\nentry:\n  call void @nl_register_file(i32 0, ptr getelementptr inbounds ([17 x i8], ptr @file, i64 0, i64 0))\n  call void @nl_expect_fail_bool(i32 0, i32 9, i32 2, ptr getelementptr inbounds ([6 x i8], ptr @source, i64 0, i64 0))\n  ret i32 0\n}}\n"),
            stdout: b"  hook-contract.nl:9:2: ready\n    value: false\n",
            stderr: b"",
            status: 0,
            test_index: None,
        },
    ];

    for fixture in fixtures {
        let ir = temporary.join(format!("{}.ll", fixture.name));
        let executable = temporary.join(fixture.name);
        let source = format!(
            "; nlc-link-ir 1\n; nlc.build test\n; nlc.stack offset\n; nlc.recursion none\nsource_filename = \"hook-contract\"\n{}\n; nlc-link-ir end\n",
            fixture.body
        );
        std::fs::write(&ir, source).expect("write legacy C hook contract IR");
        let linked = Command::new(nlc)
            .arg("link-ir")
            .arg(&ir)
            .arg("-o")
            .arg(&executable)
            .current_dir(root)
            .env("NLC_OPT_LEVEL", "1")
            .output()
            .expect("link legacy C hook contract");
        assert!(
            linked.status.success(),
            "{} did not link: {}",
            fixture.name,
            String::from_utf8_lossy(&linked.stderr)
        );
        let mut command = Command::new(&executable);
        command
            .env_remove("NLC_STACK_STATS")
            .env_remove("NLC_STACK_VERIFY")
            .env_remove("NLC_STACK_PREALLOC")
            .env_remove("NLC_TEST_STACK_FORCE_MOVE");
        if let Some(index) = fixture.test_index {
            command.env("NLC_TEST_INDEX", index);
        } else {
            command.env_remove("NLC_TEST_INDEX");
        }
        let result = command.output().expect("run legacy C hook contract");
        assert_eq!(
            result.status.code(),
            Some(fixture.status),
            "{} status, stdout={:?}, stderr={:?}",
            fixture.name,
            result.stdout,
            result.stderr
        );
        assert_eq!(result.stdout, fixture.stdout, "{} stdout", fixture.name);
        assert_eq!(result.stderr, fixture.stderr, "{} stderr", fixture.name);
    }

    std::fs::remove_dir_all(temporary).expect("remove temporary hook-contract directory");
}
