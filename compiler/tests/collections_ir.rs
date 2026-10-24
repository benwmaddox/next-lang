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
