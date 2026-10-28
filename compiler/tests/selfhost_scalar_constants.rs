#![cfg(unix)]

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

struct TemporaryPackage(PathBuf);

impl Drop for TemporaryPackage {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn shared_constant_dependencies_are_memoized_and_lower_to_immediates() {
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let build = Command::new("python3")
        .arg(root.join("scripts/build-selfhost-cached.py"))
        .args(["--reference", env!("CARGO_BIN_EXE_nlc")])
        .current_dir(root)
        .output()
        .expect("build the selfhost compiler");
    assert!(
        build.status.success(),
        "selfhost build failed: {}",
        String::from_utf8_lossy(&build.stderr)
    );
    let selfhost = String::from_utf8(build.stdout).unwrap();
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let package = TemporaryPackage(std::env::temp_dir().join(format!(
        "next-lang-constant-diamond-{}-{nonce}",
        std::process::id()
    )));
    fs::create_dir_all(&package.0).unwrap();

    // Each level uses its predecessor twice. Without declaration memoization,
    // this small, forward-referencing graph requires over a trillion visits.
    let mut source = String::from("const C0: long = 3141592653L\n");
    for level in 1..=40 {
        source.push_str(&format!(
            "const C{level}: long = C{} - C{} + 3141592653L\n",
            level - 1,
            level - 1
        ));
    }
    // Reverse declaration order to exercise forward references as well.
    source = source.lines().rev().collect::<Vec<_>>().join("\n");
    source.push_str("\nfn answer() -> long { C40 }\nfn main() { print(answer()) }\n");
    fs::write(package.0.join("main.nl"), source).unwrap();
    let compiled = Command::new("timeout")
        .args([
            "30",
            selfhost.trim(),
            "build",
            ".",
            "-o",
            "out.ll",
            "--runtime=core",
        ])
        .current_dir(&package.0)
        .output()
        .expect("compile the constant dependency graph");
    assert!(
        compiled.status.success(),
        "constant dependency build failed (status {:?}): {}",
        compiled.status.code(),
        String::from_utf8_lossy(&compiled.stderr)
    );
    let ir = fs::read_to_string(package.0.join("out.ll")).unwrap();
    assert!(
        ir.contains("ret i64 3141592653"),
        "the constant-returning function must return an immediate value"
    );
    let verified = Command::new("clang")
        .args(["-x", "ir", "-c", "out.ll", "-o", "out.o"])
        .current_dir(&package.0)
        .output()
        .expect("verify emitted constant IR with LLVM");
    assert!(
        verified.status.success(),
        "LLVM rejected constant IR: {}",
        String::from_utf8_lossy(&verified.stderr)
    );
}
