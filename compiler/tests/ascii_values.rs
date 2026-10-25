use std::path::Path;

use next_lang::compile_package;

fn ascii_fixture() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root")
        .join("tests/run/t14_ascii_values")
}

fn packed_fixture() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root")
        .join("tests/run/t14_ascii_packed")
}

#[test]
fn growing_argument_and_hidden_result_do_not_claim_noalias() {
    let compiled = compile_package(&ascii_fixture()).expect("Ascii package compiles");
    let function = compiled
        .llvm_ir
        .split("; function append_result\n")
        .nth(1)
        .expect("append_result is emitted");
    let signature = function
        .lines()
        .find(|line| line.starts_with("define "))
        .expect("append_result has an LLVM definition");
    assert!(signature.contains("ptr %nl.result"));
    assert!(signature.contains("ptr %arg."));
    assert!(
        !signature.contains("ptr noalias %arg."),
        "the hidden result destination prevents proving disjoint pointer ranges"
    );
}

#[test]
fn appending_a_literal_does_not_allocate_a_second_stack_region() {
    let compiled = compile_package(&ascii_fixture()).expect("Ascii package compiles");
    let function = compiled
        .llvm_ir
        .split("; function append_loop\n")
        .nth(1)
        .expect("append_loop is emitted");
    let function = function.split("}\n").next().unwrap();
    let loop_start = function.find("\nfor.body").expect("loop body is emitted");
    let loop_body = function[loop_start..]
        .split("\nfor.latch")
        .next()
        .expect("loop latch follows the body");
    assert_eq!(
        loop_body.matches("@nl_stack_alloc").count(),
        1,
        "the body allocates its builder once, and append adds no temporary region: {loop_body}"
    );
    assert_eq!(
        loop_body.matches("@nl_context_set_top").count(),
        1,
        "the body restores its iteration region once, and append adds no stack-top traffic"
    );
}

#[test]
fn finished_ascii_literals_reserve_only_their_actual_bytes() {
    let compiled = compile_package(&packed_fixture()).expect("large-maximum literals compile");
    let main = compiled
        .contracts
        .iter()
        .find(|contract| contract.function == "main")
        .expect("main has a stack contract");
    assert_eq!(main.byte_requirement, 35);
    assert!(compiled.llvm_ir.contains("i64 17"));
    assert!(compiled.llvm_ir.contains("i64 18"));
}
