use std::path::Path;

use next_lang::compile_package;

#[test]
fn nested_collection_layout_uses_field_lanes_and_proves_array_indexes() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let package = root.join("tests/run/t06_layout");
    let compiled = compile_package(&package).expect("T06 layout fixture should compile");
    let ir = compiled.llvm_ir;

    assert!(
        ir.contains("[64 x i64]"),
        "outer struct fields need 64-element lanes"
    );
    assert!(
        ir.contains("[8 x i64]"),
        "nested Point fields need eight-element lanes"
    );
    let inventory_decl = ir
        .lines()
        .find(|line| line.contains("; list<Point, 8>"))
        .expect("nested inventory should have an inline list storage type");
    assert!(
        inventory_decl.contains("i64, [8 x i64], [8 x i64]"),
        "each nested list needs its own count and per-field item lanes"
    );
    let unit_decl = ir
        .lines()
        .find(|line| line.ends_with("; Unit"))
        .expect("Unit should have a generated storage type");
    let unit_id = unit_decl
        .strip_prefix("%nl.ty.")
        .and_then(|line| line.split_once(" ="))
        .map(|(id, _)| id)
        .expect("Unit storage type should have an id");
    let units_decl = ir
        .lines()
        .find(|line| line.ends_with("; Unit[64]"))
        .expect("Unit[64] should have a generated SoA storage type");
    assert!(
        units_decl.contains("[64 x i64]") && units_decl.contains("[64 x %nl.ty."),
        "the Unit inventory field should have one inline list per Unit: {units_decl}"
    );
    assert!(
        !units_decl.contains(&format!("[64 x %nl.ty.{unit_id}]")),
        "the Unit collection must not be an array of Unit structs"
    );
    assert!(
        !ir.contains("call void @nl_fail(i32 16"),
        "the 0..units.len() index must not emit a bounds guard"
    );

    let first_body = ir
        .find("for.body")
        .expect("fixture should contain a loop body");
    assert!(
        !ir[first_body..]
            .lines()
            .any(|line| line.contains("alloca ")),
        "loop-body locals and fill temporaries must allocate in the function entry"
    );
}

#[test]
fn queue_ring_and_grid_fields_keep_inline_soa_layout() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let package = root.join("tests/run/t10_queue_ring_grid");
    let compiled = compile_package(&package).expect("T10 collection fixture should compile");
    let ir = compiled.llvm_ir;

    assert!(
        ir.lines().any(|line| line.contains("[2 x i64], [2 x i32]") && line.ends_with("; queue<Cell, 2>")),
        "a queue of structs needs head/count metadata followed by one lane per field"
    );
    assert!(
        ir.lines()
            .any(|line| line.contains("[2 x i64], [2 x i32]") && line.ends_with("; ring<Cell, 2>")),
        "a ring of structs needs head/count metadata followed by one lane per field"
    );
    assert!(
        ir.lines()
            .any(|line| line.contains("[4 x i64], [4 x i32]")
                && line.ends_with("; grid<Cell, 2, 2>")),
        "a grid of structs needs row-major field lanes"
    );
    let board_array = ir
        .lines()
        .find(|line| line.ends_with("; Board[2]"))
        .expect("World should contain its bounded Board array");
    assert!(
        board_array.matches("[2 x %nl.ty.").count() == 3,
        "nested queue, ring and grid values must be inline lanes in Board[2]: {board_array}"
    );
}

#[test]
fn empty_large_lists_do_not_clear_their_element_lanes() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let package = root.join("tests/run/t23_rss_list");
    let compiled = compile_package(&package).expect("T23 large-list package should compile");
    let main = compiled
        .llvm_ir
        .split("; function main\n")
        .nth(1)
        .expect("main function is emitted")
        .split("}\n")
        .next()
        .expect("main function has a closing brace");
    assert!(main.contains("[6000000 x i64]"));
    assert!(
        !main.contains("llvm.memset"),
        "an empty list and its first push must not clear unused element lanes"
    );
}

#[test]
fn growing_collection_lanes_have_no_pointer_fields_or_pointer_stores() {
    use std::collections::HashSet;

    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let package = root.join("tests/run/t16_collections");
    let compiled = compile_package(&package).expect("T16 collection fixture should compile");
    let ir = compiled.llvm_ir;

    for declaration in ir.lines().filter(|line| {
        line.contains(" = type ")
            && (line.starts_with("%nl.ty.") || line.starts_with("%nl.collection."))
    }) {
        assert!(
            !declaration.contains("ptr"),
            "collection and value lane declarations must not store addresses: {declaration}"
        );
    }

    let collection_lane_pointers = ir
        .lines()
        .filter_map(|line| {
            let (result, instruction) = line.split_once(" = getelementptr ")?;
            (instruction.contains("%nl.collection.string.")
                || instruction.contains("%nl.collection.key."))
            .then(|| result.to_owned())
        })
        .collect::<HashSet<_>>();
    for instruction in ir.lines().filter(|line| line.contains("store ptr ")) {
        let Some((_, destination)) = instruction.rsplit_once(", ptr ") else {
            continue;
        };
        let destination = destination.trim();
        assert!(
            !collection_lane_pointers.contains(destination),
            "pointer stored to collection lane address {destination}: {instruction}"
        );
    }
}

#[test]
fn huge_collection_class_pools_use_a_flat_byte_region() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let package = root.join("tests/test/t31_large_classes_build");
    let compiled = compile_package(&package).expect("T31 large-class fixture should compile");
    let ir = compiled.llvm_ir;

    let collection_decl = ir
        .lines()
        .find(|line| line.ends_with("; list<Ascii max 8388608, 1>"))
        .expect("the fixture should emit its large collection prefix type");
    let collection_type = collection_decl
        .strip_prefix("%nl.ty.")
        .and_then(|line| line.split_once(" ="))
        .map(|(id, _)| format!("%nl.ty.{id}"))
        .expect("the collection type should have an LLVM identifier");
    assert!(
        !collection_decl.contains("8388608 x i8"),
        "large size-class payloads must not appear in the first-class collection type: {collection_decl}"
    );

    let globals = ir
        .lines()
        .find(|line| line.starts_with("@nl.globals ="))
        .expect("the fixture should emit global collection storage");
    let backing_bytes = globals
        .rsplit(" x i8] zeroinitializer")
        .nth(1)
        .and_then(|prefix| prefix.rsplit_once('[').map(|(_, count)| count))
        .and_then(|count| count.parse::<usize>().ok())
        .expect("the global collection should use a flat byte-array backing region");
    assert!(
        backing_bytes >= 8 * 1024 * 1024,
        "the flat backing should include the largest class and its smaller classes"
    );
    assert!(
        !ir.lines().any(|line| {
            line.contains(&format!("load {collection_type}"))
                || line.contains(&format!("store {collection_type}"))
        }),
        "collection prefixes must not be loaded or stored as whole aggregates"
    );
    assert!(
        !ir.lines()
            .any(|line| { line.contains("load <{ %nl.ty.") || line.contains("store <{ %nl.ty.") }),
        "flat class backing must not be loaded or stored with the collection prefix"
    );
}
