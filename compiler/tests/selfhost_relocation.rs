use std::path::Path;
use std::process::Command;

#[test]
fn forced_selfhost_relocations_match_ordinary_runs() {
    // The harness fixes both the reference frontend and stage-zero frontend;
    // its package results are independent of the full suite's frontend.
    if std::env::var("NLC_FRONTEND").as_deref() == Ok("selfhost") {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let reference = env!("CARGO_BIN_EXE_nlc");
    let result = Command::new("python3")
        .arg(root.join("scripts/check-selfhost-relocation.py"))
        .arg("--reference")
        .arg(reference)
        .current_dir(root)
        .env("NLC_FRONTEND", "rust")
        .output()
        .expect("run the selfhost relocation check");
    assert!(
        result.status.success(),
        "selfhost relocation check failed (status {:?}):\n{}\n{}",
        result.status.code(),
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
}
