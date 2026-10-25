use std::path::Path;
use std::process::Command;

use next_lang::compile_package;

fn inline_text_fixture() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root")
        .join("tests/run/t29_inline_text_fields")
}

#[test]
fn text_fields_use_inline_pointer_free_storage_and_smaller_contracts() {
    let compiled = compile_package(&inline_text_fixture()).expect("T29 package compiles");
    let declaration = |suffix: &str| {
        compiled
            .llvm_ir
            .lines()
            .find(|line| line.ends_with(suffix))
            .unwrap_or_else(|| panic!("missing LLVM declaration ending in {suffix:?}"))
    };

    let fields = declaration("; Fields");
    assert!(fields.contains("%nl.storage."), "{fields}");
    assert!(
        !fields.contains("ptr"),
        "stored Fields has no pointer: {fields}"
    );
    let nested = declaration("; Nested");
    assert!(
        !nested.contains("ptr"),
        "stored Nested has no pointer: {nested}"
    );
    let payload = declaration("; Payload");
    assert!(
        !payload.contains("ptr"),
        "stored Payload has no pointer: {payload}"
    );
    assert!(
        compiled
            .llvm_ir
            .lines()
            .any(|line| line.contains("i64, i64, [32 x i8]") && line.contains("Text max 8")),
        "Text storage keeps its byte length, code-point count, and maximum bytes"
    );
    assert!(!compiled.llvm_ir.contains("%nl.option.ascii"));
    assert!(!compiled.llvm_ir.contains("%nl.option.text"));
    assert!(!compiled.llvm_ir.contains("%nl.option.bytes"));

    assert_eq!(compiled.memory.startup_claim_bytes, 264);
    assert_eq!(
        compiled
            .memory
            .globals
            .iter()
            .map(|global| global.size_bytes)
            .collect::<Vec<_>>(),
        [88, 88, 88]
    );
    let copy_fields = compiled
        .contracts
        .iter()
        .find(|contract| contract.function == "copy_fields")
        .expect("copy_fields has a stack contract");
    assert!(
        copy_fields
            .parameters
            .iter()
            .any(|parameter| parameter == "value: read pointer (80 bytes)")
    );
    assert_eq!(
        copy_fields.result_placement,
        "caller destination (80 bytes)"
    );
}

#[test]
fn copying_a_shrunk_inline_string_touches_only_its_live_bytes() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let package = root.join("tests/test/t29_dirty_inline_copy");
    let output = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("test")
        .arg(&package)
        .env("NLC_TEST_REPORT_STACK_TOUCHED", "1")
        .output()
        .expect("run the dirty inline string copy probe");
    assert!(
        output.status.success(),
        "dirty copy probe failed: stdout={} stderr={}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    let measured = stderr
        .lines()
        .find(|line| line.contains("reserved=") && line.contains("touched="))
        .expect("runtime test hook reported stack residency");
    let touched = measured
        .split_whitespace()
        .find_map(|part| part.strip_prefix("touched="))
        .and_then(|value| value.parse::<u64>().ok())
        .expect("runtime report contains touched bytes");
    assert!(
        touched > 4 * 1024 * 1024,
        "the probe did not dirty its source region: {measured}"
    );
    assert!(
        touched < 12 * 1024 * 1024,
        "copying the one-byte live value touched its full declared capacity: {measured}"
    );
}
