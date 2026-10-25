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
    assert!(indirect.parameters[0].contains("function targets need up to 8192 data-stack bytes"));

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
