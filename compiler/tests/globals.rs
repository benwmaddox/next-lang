use std::fs;
use std::path::Path;
use std::process::{Command, Output};

use next_lang::compile_package;

#[test]
fn global_initializers_are_static_or_run_once_in_dependency_order() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/run/t08_globals");
    let compiled = compile_package(&package).expect("T08 globals package compiles");
    assert!(compiled.llvm_ir.contains("@nl.globals = global"));
    assert!(
        compiled
            .llvm_ir
            .contains("call void @nl_fn_1(ptr %nl.ctx, ptr %nl.top)")
    );
    assert_eq!(compiled.memory.globals.len(), 3);
    assert!(compiled.memory.startup_claim_bytes >= 24);
    assert_eq!(
        compiled
            .llvm_ir
            .matches("call void @nl_fn_1(ptr %nl.ctx, ptr %nl.top)")
            .count(),
        1,
        "the runtime initializer is called once before main"
    );

    let static_only = root.join("tests/run/t08_memory");
    let static_ir = compile_package(&static_only).expect("static global package compiles");
    assert!(
        !static_ir
            .llvm_ir
            .contains("call void @nl_fn_1(ptr %nl.ctx, ptr %nl.top)")
    );
    assert!(static_ir.llvm_ir.contains("i32 7"));
}

#[test]
fn memory_inspection_reports_alignment_headroom_budget_and_waiver() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/run/t08_memory");
    let inspect = |allow: bool| {
        let mut command = Command::new(env!("CARGO_BIN_EXE_nlc"));
        command.args(["inspect", "memory"]).arg(&package);
        if allow {
            command.arg("--allow-overcommit");
        }
        command.output().expect("run memory inspection")
    };
    let normal = inspect(false);
    assert!(normal.status.success());
    let report = String::from_utf8_lossy(&normal.stdout);
    assert!(report.contains("global value: 8 bytes (offset 0, alignment 8)"));
    assert!(report.contains("startup claim: 8 bytes"));
    assert!(report.contains("job headroom: 1048576 bytes"));
    assert!(report.contains("guarantee waived: no"));
    assert!(report.contains("local storage: excluded"));
    assert!(report.contains("above globals_budget of 0 bytes"));

    let waived = inspect(true);
    assert!(waived.status.success());
    assert!(String::from_utf8_lossy(&waived.stdout).contains("guarantee waived: yes"));
}

#[test]
fn linux_startup_memory_policy_checks_each_configured_branch() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/run/t08_memory");
    let compiled = compile_package(&package).expect("T08 memory package compiles");
    let temp = std::env::temp_dir().join(format!("next-lang-t08-memory-{}", std::process::id()));
    fs::create_dir_all(&temp).expect("create temporary test directory");
    let ir = temp.join("program.ll");
    let binary = temp.join("program");
    fs::write(&ir, compiled.llvm_ir).expect("write generated LLVM IR");
    let runtime = root.join("runtime/nl_runtime.c");
    let build = Command::new("clang")
        .args(["-O1", "-DNLC_TEST_BUILD=1"])
        .arg(&ir)
        .arg(&runtime)
        .arg("-o")
        .arg(&binary)
        .output()
        .expect("start clang");
    assert!(
        build.status.success(),
        "clang failed: {}",
        String::from_utf8_lossy(&build.stderr)
    );

    let claim = compiled.memory.startup_claim_bytes;
    let required = claim + compiled.memory.job_headroom_bytes;
    let extra = 4096u64;
    let run = |policy: String, allow: bool| -> Output {
        let mut command = Command::new(&binary);
        if allow {
            command.arg("--allow-overcommit");
        }
        command
            .env("NLC_TEST_MEMORY_POLICY", policy)
            .output()
            .unwrap()
    };

    let strict = run(
        format!(
            "mode=2;memory={};current=0;swap=max;swap_current=0;available=max;commit={};committed=0",
            required + extra,
            required + extra
        ),
        false,
    );
    assert!(strict.status.success(), "strict branch failed: {strict:?}");
    assert_eq!(strict.stdout, b"7\n");

    let default = run(
        format!(
            "mode=1;memory={};current=0;swap=0;swap_current=0;available=max",
            required + extra
        ),
        false,
    );
    assert!(
        default.status.success(),
        "default branch failed: {default:?}"
    );
    assert_eq!(default.stdout, b"7\n");

    let too_small = run(
        format!("mode=1;memory={};current=0;swap=0;available=max", claim - 1),
        false,
    );
    assert!(!too_small.status.success());
    assert!(too_small.stdout.is_empty());
    assert!(String::from_utf8_lossy(&too_small.stderr).contains("memory.max"));

    let swap_limited = run(
        format!(
            "mode=1;memory={claim};current=0;swap={};swap_current=0;available=max",
            required - claim - 1
        ),
        false,
    );
    assert!(!swap_limited.status.success());
    assert!(swap_limited.stdout.is_empty());
    assert!(String::from_utf8_lossy(&swap_limited.stderr).contains("job_headroom"));

    let waived = run(
        "mode=1;memory=0;current=0;swap=0;available=0".to_owned(),
        true,
    );
    assert!(waived.status.success(), "waiver branch failed: {waived:?}");
    assert_eq!(waived.stdout, b"7\n");
    assert!(String::from_utf8_lossy(&waived.stderr).contains("guarantee is off"));

    let _ = fs::remove_dir_all(temp);
}
