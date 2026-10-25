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
        stdout.contains("data stack worst case: 40348 bytes"),
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
fn one_gib_reservation_reports_touched_pages_and_stays_within_its_bound() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/test/t17_large_reservation");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let output = Command::new(nlc)
        .arg("test")
        .arg(&package)
        .env("NLC_TEST_REPORT_STACK_TOUCHED", "1")
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
        .find(|line| line.contains("reserved=") && line.contains("touched="))
        .expect("runtime test hook reported reservation and touched pages");
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
        field("touched") > 0 && field("touched") < 16 * 1024 * 1024,
        "{measured}"
    );
    assert!(
        field("peak_used") <= computed,
        "{measured}; computed={computed}"
    );
}
