use std::fs;
use std::path::Path;
use std::process::Command;

use next_lang::compile_package;

fn workspace_root() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root")
        .to_path_buf()
}

#[test]
fn proven_builder_reassignment_is_in_place_and_other_calls_keep_copy_down() {
    let package = workspace_root().join("tests/run/t30_copy_down");
    let compiled = compile_package(&package).expect("T30 copy-down fixture compiles");
    let main = compiled
        .contracts
        .iter()
        .find(|contract| contract.function == "main")
        .expect("main has a stack contract");
    assert_eq!(main.copy_down_sites.len(), 1, "{:?}", main.copy_down_sites);
    assert_eq!(main.copy_down_sites[0].name, "copied");
    assert_eq!(main.copy_down_sites[0].span.line, 16);

    let output_path =
        std::env::temp_dir().join(format!("nlc-t30-copy-down-{}.out", std::process::id()));
    let _ = fs::remove_file(&output_path);
    let build = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("build")
        .arg(&package)
        .arg("-o")
        .arg(&output_path)
        .output()
        .expect("build the T30 copy-down fixture");
    let _ = fs::remove_file(&output_path);
    assert!(
        build.status.success(),
        "build failed: {}",
        String::from_utf8_lossy(&build.stderr)
    );
    let note = String::from_utf8_lossy(&build.stderr);
    assert!(note.contains("main.nl:16:5"), "{note}");
    assert!(note.contains("'copied'"), "{note}");
    assert!(note.contains("40-byte copy-down temporary"), "{note}");
    assert!(note.contains("'grow' or 'write' parameter"), "{note}");
}

#[test]
fn small_regions_are_adjacent_before_the_megabyte_builder() {
    let package = workspace_root().join("tests/run/t30_locality");
    let output = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("inspect")
        .arg("stacks")
        .arg(&package)
        .output()
        .expect("inspect T30 local placement");
    assert!(
        output.status.success(),
        "inspect stacks failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let regions = stdout
        .lines()
        .filter(|line| {
            line.contains("data region: main.nl:")
                || line.contains("reserved region over 64 KB: main.nl:")
        })
        .collect::<Vec<_>>();
    let names = regions
        .iter()
        .map(|line| {
            line.split_once('(')
                .and_then(|(label, _)| label.split_whitespace().last())
                .expect("region line includes its name and size")
        })
        .collect::<Vec<_>>();
    assert_eq!(names, ["before", "fixed", "after", "buffer"], "{stdout}");

    let bytes = |line: &str| -> u64 {
        line.rsplit_once('(')
            .and_then(|(_, value)| value.strip_suffix(" bytes)"))
            .and_then(|value| value.parse().ok())
            .expect("region line includes a byte size")
    };
    let align8 = |value: u64| (value + 7) & !7;
    let distance = align8(bytes(regions[0])) + align8(bytes(regions[1]));
    assert_eq!(
        distance, 64,
        "small-local start distance was {distance}\n{stdout}"
    );
}
