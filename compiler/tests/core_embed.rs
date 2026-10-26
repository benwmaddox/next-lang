use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn embedded_core_source_is_current_and_within_its_budgets() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock is after the epoch")
        .as_nanos();
    let scratch = std::env::temp_dir().join(format!(
        "next-lang-core-embed-{}-{stamp}",
        std::process::id()
    ));
    fs::create_dir_all(&scratch).expect("create scratch directory");
    let generated = scratch.join("core_files.nl");
    let result = Command::new("bash")
        .arg(root.join("scripts/embed-core.sh"))
        .arg("--output")
        .arg(&generated)
        .current_dir(root)
        .output()
        .expect("run core embedding generator");
    assert!(
        result.status.success(),
        "core embed generator failed: {}",
        String::from_utf8_lossy(&result.stderr)
    );
    let generated_bytes = fs::read(generated).expect("read generated core embed");
    let checked_in_bytes = fs::read(root.join("selfhost/core_files.nl"))
        .expect("read checked-in core embed");
    fs::remove_dir_all(scratch).expect("remove scratch directory");
    assert_eq!(generated_bytes, checked_in_bytes, "selfhost/core_files.nl is stale");
}
