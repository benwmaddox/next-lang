use std::path::Path;

use next_lang::compile_package;

fn package(name: &str) -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root")
        .join("tests/run")
        .join(name)
}

#[test]
fn owners_are_erased_and_pool_lanes_include_metadata() {
    let core = compile_package(&package("t07_core")).expect("T07 core should compile");
    let definitions = core
        .llvm_ir
        .lines()
        .filter(|line| line.starts_with("define i64 @nl_fn_"))
        .count();
    assert_eq!(
        definitions, 3,
        "depth, rock_count, and retain_id each need one capacity specialization, shared across owners"
    );
    assert!(
        core.llvm_ir.contains("icmp uge i32") && core.llvm_ir.contains("store i32 -1"),
        "pool removal must retire a slot instead of wrapping its maximum generation"
    );

    let nested = compile_package(&package("t07_nested_list"))
        .expect("pool elements with nested lists should compile");
    let pool_layout = nested
        .llvm_ir
        .lines()
        .find(|line| line.contains("; pool<Crate, 2"))
        .expect("the crate pool should have a generated layout");
    assert!(
        pool_layout.contains("[2 x i1]")
            && pool_layout.contains("[2 x i32]")
            && pool_layout.contains("[2 x %nl.ty."),
        "pool slots need occupied/generation/free-list metadata and per-field lanes: {pool_layout}"
    );
    assert!(
        pool_layout.contains("[2 x i32], i64, [2 x %nl.ty."),
        "pool storage must include a high-water mark before its live-value lanes: {pool_layout}"
    );
    let list_layout = nested
        .llvm_ir
        .lines()
        .find(|line| line.contains("; list<Item, 2>"))
        .expect("each crate should have its own bounded item list");
    assert!(
        list_layout.contains("i64, [2 x i32]"),
        "nested lists must keep an independent count and an item lane: {list_layout}"
    );
}
