use std::fs;
use std::path::Path;
use std::process::Command;

use next_lang::compile_package;

#[test]
fn test_runtime_stack_override_reports_exhaustion() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/test/t13_stack_exhaustion");
    let nlc = env!("CARGO_BIN_EXE_nlc");

    let normal = Command::new(nlc)
        .arg("test")
        .arg(&package)
        .output()
        .expect("run the bounded workload with the normal reservation");
    assert!(
        normal.status.success(),
        "normal reservation failed: {}",
        String::from_utf8_lossy(&normal.stderr)
    );

    let small = Command::new(nlc)
        .arg("test")
        .arg(&package)
        .env("NLC_TEST_DATA_STACK_BYTES", "16384")
        .env("NLC_TEST_ALLOW_STACK_EXHAUSTION", "1")
        .output()
        .expect("run the bounded workload with a shrunken test reservation");
    assert_eq!(small.status.code(), Some(1));
    assert!(
        String::from_utf8_lossy(&small.stderr).contains("data stack exhausted"),
        "expected a data-stack exhaustion diagnostic, got: {}",
        String::from_utf8_lossy(&small.stderr)
    );
    assert!(
        String::from_utf8_lossy(&small.stdout)
            .contains("ok   iteration region is released each time"),
        "iteration cleanup did not keep the bounded loop below the shrunken reservation: {}",
        String::from_utf8_lossy(&small.stdout)
    );
}

#[test]
fn fixed_large_values_use_regions_and_large_results_use_destinations() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/run/t13_stack_contracts");
    let compiled = compile_package(&package).expect("T13 stack-contract package compiles");
    let ir = compiled.llvm_ir;

    assert!(ir.lines().any(|line| {
        line.starts_with("define ") && line.contains("ptr %nl.ctx, ptr %nl.entry.top")
    }));
    assert!(ir.contains("@nl_stack_alloc(ptr %nl.ctx"));
    assert!(ir.contains("ptr %nl.result"));
    let large_result = ir
        .split("; function make_nested\n")
        .nth(1)
        .expect("large-result function is emitted");
    assert!(
        large_result
            .lines()
            .next()
            .unwrap()
            .contains("ptr %nl.ctx, ptr %nl.entry.top, ptr %nl.result")
    );
    assert!(ir.contains("call void @llvm.memmove.p0.p0.i64"));
    assert!(ir.contains("ptr noalias %arg."));
    assert!(ir.contains("ptr %arg."));

    let indirect = compiled
        .contracts
        .iter()
        .find(|contract| contract.function == "call_indirect")
        .expect("indirect caller has a stack contract");
    assert!(indirect.byte_requirement >= 8192);
    assert!(indirect.parameters[0].contains("function targets need up to 16384 data-stack bytes"));

    let no_stack_loop = ir
        .split("; function no_stack_loop\n")
        .nth(1)
        .expect("no_stack_loop function is emitted");
    let no_stack_loop = no_stack_loop.split("}\n").next().unwrap();
    let loop_body = no_stack_loop
        .split("for.body")
        .nth(1)
        .expect("loop body block is emitted")
        .split("for.latch")
        .next()
        .expect("loop latch follows the body");
    assert!(!loop_body.contains("@nl_stack_alloc"));
    assert!(!loop_body.contains("@nl_context_set_top"));

    let possibly_alias = ir
        .split("; function possibly_alias\n")
        .nth(1)
        .expect("possibly_alias function is emitted")
        .split("}\n")
        .next()
        .unwrap();
    assert!(possibly_alias.contains("ptr %arg."));
    assert!(!possibly_alias.contains("noalias"));
}

#[test]
fn returned_collection_local_is_built_in_the_caller_destination() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/run/t23_rss_return");
    let compiled = compile_package(&package).expect("returned-list probe compiles");
    let make = compiled
        .contracts
        .iter()
        .find(|contract| contract.function == "make")
        .expect("make has a stack contract");

    assert_eq!(make.byte_requirement, 0);
    assert!(
        make.result_placement
            .contains("caller destination (16000008 bytes)")
    );

    let make_ir = compiled
        .llvm_ir
        .split("; function make\n")
        .nth(1)
        .expect("make is emitted")
        .split("}\n")
        .next()
        .expect("make has a body");
    assert!(make_ir.contains("ptr %nl.result, i64 0"));
    assert!(!make_ir.contains("@nl_stack_alloc"));
}

#[test]
fn gathered_large_struct_arguments_count_in_the_caller_contract() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/run/t13_soa_gather");
    let compiled = compile_package(&package).expect("SoA gather package compiles");
    let caller = compiled
        .contracts
        .iter()
        .find(|contract| contract.function == "forward_element")
        .expect("forward_element has a stack contract");

    assert!(
        caller.byte_requirement >= 8_004,
        "the caller contract must include the gathered Big argument, got {} bytes",
        caller.byte_requirement
    );
}

#[test]
fn hidden_global_writes_drive_read_snapshots_and_scratch_contracts() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");

    let writing = compile_package(&root.join("tests/e2/e2i_global_hidden_write_snapshot"))
        .expect("hidden global write fixture compiles");
    let main_contract = writing
        .contracts
        .iter()
        .find(|contract| contract.function == "main")
        .expect("writing caller has a stack contract");
    assert!(
        main_contract.byte_requirement >= 4_404,
        "main must reserve the large read snapshot, got {} bytes",
        main_contract.byte_requirement
    );

    let read_only = compile_package(&root.join("tests/e2/e2i_global_read_only_no_snapshot"))
        .expect("read-only global fixture compiles");
    let main_contract = read_only
        .contracts
        .iter()
        .find(|contract| contract.function == "main")
        .expect("read-only caller has a stack contract");
    assert_eq!(
        main_contract.byte_requirement, 0,
        "a read-only later call must not reserve a snapshot"
    );
    let main_ir = read_only
        .llvm_ir
        .split("; function main\n")
        .nth(1)
        .expect("main is emitted")
        .split("}\n")
        .next()
        .expect("main has a body");
    assert!(
        !main_ir.contains("@nl_stack_alloc"),
        "read-only later call unexpectedly allocates snapshot scratch:\n{main_ir}"
    );
}

#[test]
fn worked_reservation_is_small_and_reports_loop_growth() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/run/t17_worked_reservation");
    let output = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("inspect")
        .arg("stacks")
        .arg(&package)
        .output()
        .expect("inspect the worked reservation example");
    assert!(
        output.status.success(),
        "inspect stacks failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("entry point main"));
    assert!(
        stdout.contains("data stack worst case: 40332 bytes"),
        "{stdout}"
    );
    assert!(
        stdout.contains("data stack reservation: 40960 bytes"),
        "{stdout}"
    );
    assert!(stdout.contains("growth per iteration 80 bytes"), "{stdout}");
    assert!(stdout.contains("data region: main.nl:"), "{stdout}");
}

#[test]
fn selfhost_stack_bound_has_an_exact_attributed_path() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("selfhost");
    let output = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("inspect")
        .arg("stacks")
        .arg(&package)
        .output()
        .expect("inspect the self-hosted parser stack bound");
    assert!(
        output.status.success(),
        "inspect stacks failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let parse_bytes = |prefix: &str| -> u64 {
        stdout
            .lines()
            .find_map(|line| line.strip_prefix(prefix))
            .and_then(|remainder| remainder.split_whitespace().next())
            .and_then(|value| value.parse().ok())
            .unwrap_or_else(|| panic!("missing byte count for {prefix} in:\n{stdout}"))
    };
    let worst_case = parse_bytes("  data stack worst case: ");
    let attributed = parse_bytes("  data stack critical path sum: ");
    assert_eq!(attributed, worst_case, "{stdout}");
    // E2's layout, defaults, helper and aggregate-frame tables live in main
    // alongside the parser's source, token and node buffers. E2b expands the
    // IR table allowance for sum helpers; pin the new total below 7 GB so the
    // selfhost compiler still fits the fixed 8 GB process budget.
    assert_eq!(worst_case, 6_943_732_617, "{stdout}");
    assert!(worst_case < 7_000_000_000, "{stdout}");
    assert_eq!(
        parse_bytes("  data stack reservation: "),
        6_943_735_808,
        "{stdout}"
    );
    assert!(
        stdout.contains("data stack critical path: main ->"),
        "{stdout}"
    );
    assert!(
        stdout.contains("main.nl:96 main.tables (680912049 bytes)"),
        "{stdout}"
    );
    for line in [68, 72, 103, 128, 175] {
        assert!(
            !stdout.contains(&format!("dump.nl:{line} copy-down temporary for buffer")),
            "empty buffer reset at dump.nl:{line} was reported as a copy-down:\n{stdout}"
        );
    }

    let compiled = compile_package(&package).expect("self-hosted parser compiles");
    for function in ["dump_number", "dump_json_byte", "dump_binary_op"] {
        let contract = compiled
            .contracts
            .iter()
            .find(|contract| contract.function == function)
            .unwrap_or_else(|| panic!("missing stack contract for {function}"));
        assert!(
            contract.byte_requirement < 1024,
            "{function} still stages a bounded byte literal as a large collection: {} bytes",
            contract.byte_requirement
        );
    }
    let token_dump = compiled
        .contracts
        .iter()
        .find(|contract| contract.function == "output_token_dump")
        .expect("token dump has a stack contract");
    assert!(
        token_dump.copy_down_sites.is_empty(),
        "empty buffer resets do not need copy-down storage"
    );

    let decoded_dump = compiled
        .llvm_ir
        .split("; function dump_quoted_decoded_token\n")
        .nth(1)
        .expect("decoded token dump helper is emitted")
        .split("}\n")
        .next()
        .expect("decoded token dump helper has a body");
    let hidden_result_allocations = decoded_dump
        .lines()
        .filter(|line| {
            line.contains("call ptr @nl_stack_alloc")
                && line.contains("i64 16777232")
                && line.contains("i32 4, i32 415,")
        })
        .count();
    assert_eq!(
        hidden_result_allocations, 0,
        "the decoder result should be built directly in the local value destination"
    );
}

#[test]
fn match_arm_iteration_regions_are_in_the_stack_contract() {
    let package =
        std::env::temp_dir().join(format!("next-lang-stack-match-{}", std::process::id()));
    fs::create_dir_all(&package).expect("create the temporary package");
    fs::write(
        package.join("main.nl"),
        "struct Row { payload: Bytes max 4096 }\n\
         fn main() {\n\
             var rows: list<Row, 1> = list {}\n\
             match true {\n\
                 true => { for row in rows { print(row.payload.count()) } },\n\
                 false => {}\n\
             }\n\
         }\n",
    )
    .expect("write the temporary program");

    let compiled = compile_package(&package).expect("nested match and iteration program compiles");
    let main = compiled
        .contracts
        .iter()
        .find(|contract| contract.function == "main")
        .expect("main has a stack contract");
    let iteration = main
        .local_regions
        .iter()
        .find(|region| region.name == "iteration element")
        .expect("the match arm's large iteration element is attributed");
    assert!(main.local_requirement >= iteration.bytes);

    fs::remove_dir_all(package).expect("remove the temporary package");
}

#[test]
fn undersized_test_reservations_fail_before_the_test_starts() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/test/t17_startup_reservation");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let normal = Command::new(nlc)
        .arg("test")
        .arg(&package)
        .output()
        .expect("run with the computed reservation");
    assert!(
        normal.status.success(),
        "{}",
        String::from_utf8_lossy(&normal.stderr)
    );

    let small = Command::new(nlc)
        .arg("test")
        .arg(&package)
        .env("NLC_TEST_DATA_STACK_BYTES", "1024")
        .output()
        .expect("run with an undersized test reservation");
    assert_eq!(small.status.code(), Some(1));
    let stderr = String::from_utf8_lossy(&small.stderr);
    assert!(stderr.contains("data stack startup failure for entry 'test 'reservation has room for the computed bound'"), "{stderr}");
    assert!(
        stderr.contains("test reservation is below the computed worst case"),
        "{stderr}"
    );
}

#[test]
fn one_gib_reservation_reports_resident_pages_and_stays_within_its_bound() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/test/t17_large_reservation");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let output = Command::new(nlc)
        .arg("test")
        .arg(&package)
        .env("NLC_TEST_REPORT_STACK_RESIDENT", "1")
        .output()
        .expect("run the large-reservation probe");
    assert!(
        output.status.success(),
        "large reservation test failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    let measured = stderr
        .lines()
        .find(|line| line.contains("reserved=") && line.contains("resident="))
        .expect("runtime test hook reported reservation and resident pages");
    let field = |name: &str| -> u64 {
        measured
            .split_whitespace()
            .find_map(|part| part.strip_prefix(&format!("{name}=")))
            .and_then(|part| part.parse().ok())
            .unwrap_or_else(|| panic!("missing {name} in {measured}"))
    };
    let inspect = Command::new(nlc)
        .arg("inspect")
        .arg("stacks")
        .arg(&package)
        .output()
        .expect("inspect the large reservation");
    assert!(
        inspect.status.success(),
        "{}",
        String::from_utf8_lossy(&inspect.stderr)
    );
    let inspect_stdout = String::from_utf8_lossy(&inspect.stdout);
    let stack_line = inspect_stdout
        .lines()
        .find(|line| line.contains("data stack worst case:"))
        .expect("inspect output reports the data stack bound");
    let computed = stack_line
        .split_whitespace()
        .nth(4)
        .and_then(|value| value.parse::<u64>().ok())
        .expect("inspect output contains a byte count");
    assert!(field("reserved") > 64 * 1024 * 1024, "{measured}");
    assert!(
        field("resident") > 0 && field("resident") < 16 * 1024 * 1024,
        "{measured}"
    );
    assert!(
        field("peak_used") <= computed,
        "{measured}; computed={computed}"
    );
}
