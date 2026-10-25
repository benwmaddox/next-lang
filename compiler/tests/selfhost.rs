use std::fs;
use std::path::Path;
use std::process::Command;

#[test]
fn selfhosted_lexer_matches_the_rust_lexer() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let temp = std::env::temp_dir().join(format!("next-lang-selfhost-{}", std::process::id()));
    fs::create_dir_all(&temp).expect("create temporary selfhost executable directory");
    let selfhost = temp.join(if cfg!(windows) {
        "selfhost.exe"
    } else {
        "selfhost"
    });

    let build = Command::new(nlc)
        .args(["build", "selfhost", "-o"])
        .arg(&selfhost)
        .current_dir(root)
        .output()
        .expect("build the next-lang selfhost package once");
    assert!(
        build.status.success(),
        "selfhost build failed:\n{}",
        String::from_utf8_lossy(&build.stderr)
    );

    let comparison = Command::new(root.join("scripts/compare-selfhost.sh"))
        .arg("--tokens")
        .arg("--reference")
        .arg(nlc)
        .arg("--selfhost")
        .arg(&selfhost)
        .current_dir(root)
        .output()
        .expect("run the selfhost lexer comparison harness");
    let _ = fs::remove_dir_all(&temp);
    assert!(
        comparison.status.success(),
        "selfhost lexer comparison failed (status {:?}):\n{}\n{}",
        comparison.status.code(),
        String::from_utf8_lossy(&comparison.stdout),
        String::from_utf8_lossy(&comparison.stderr)
    );
}
