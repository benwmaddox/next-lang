use std::path::Path;

use next_lang::compile_package;

#[test]
fn ascii_read_as_text_passes_a_view_without_copying_payload_bytes() {
    let package = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root")
        .join("tests/run/t16_ascii_read_text");
    let compiled = compile_package(&package).expect("Ascii-to-Text read fixture compiles");
    let main = compiled
        .llvm_ir
        .split("; function main\n")
        .nth(1)
        .expect("main is emitted")
        .split("\n}\n")
        .next()
        .expect("main body has a terminator");
    assert!(main.contains("@nl_fn_"), "main calls the Text reader");
    assert!(
        !main.contains("@llvm.memmove"),
        "the Ascii payload is borrowed directly as Text"
    );
    assert!(
        !main.contains("@nl_utf8_count"),
        "Ascii-to-Text does not need UTF-8 validation"
    );
}
