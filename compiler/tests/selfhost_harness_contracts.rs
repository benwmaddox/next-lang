use std::path::Path;
use std::process::Command;

#[test]
fn classification_schema_accepts_only_supported_package_classes() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let result = Command::new("python3")
        .arg(root.join("scripts/test_harness_contracts.py"))
        .current_dir(root)
        .output()
        .expect("run classification contract tests");
    assert!(
        result.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
}
