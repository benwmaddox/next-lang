use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

struct Scratch(PathBuf);

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn impossible_text_bounds_are_diagnostics_not_compiler_overflows() {
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let cached = Command::new("python3")
        .arg(root.join("scripts/build-selfhost-cached.py"))
        .args(["--reference", env!("CARGO_BIN_EXE_nlc")])
        .current_dir(root)
        .output()
        .unwrap();
    assert!(
        cached.status.success(),
        "{}",
        String::from_utf8_lossy(&cached.stderr)
    );
    let selfhost = String::from_utf8(cached.stdout).unwrap().trim().to_owned();
    let scratch = Scratch(std::env::temp_dir().join(format!(
        "next-lang-text-capacity-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    )));
    fs::create_dir_all(&scratch.0).unwrap();
    let cases = [
        (
            "ascii-header",
            "fn invalid(value: Ascii max 9223372036854775807) {}\nfn main() {}\n",
        ),
        (
            "bytes-header",
            "fn invalid(value: Bytes max 9223372036854775807) {}\nfn main() {}\n",
        ),
        (
            "text-points",
            "fn invalid(value: Text max 9223372036854775807) {}\nfn main() {}\n",
        ),
        (
            "text-header",
            "fn invalid(value: Text bytes max 9223372036854775807) {}\nfn main() {}\n",
        ),
        (
            "bytes-to-text",
            "fn invalid(value: Bytes max 9223372036854775799) { let converted = value.to_text(); print(converted.is_ok()) }\nfn main() {}\n",
        ),
        (
            "text-result-tag",
            "fn invalid(value: Bytes max 9223372036854775791) { let converted = value.to_text(); print(converted.is_ok()) }\nfn main() {}\n",
        ),
        (
            "ascii-option-tag",
            "fn main() { let value: Ascii max 1 = \"a\"; let fitted = value.fit<Ascii max 9223372036854775799>(); print(fitted.is_some()) }\n",
        ),
        (
            "padding-header",
            "fn main() { let value = pad(\"x\", 9223372036854775807L); print(value.len()) }\n",
        ),
        (
            "zero-padding-header",
            "fn main() { let value = pad_zero(1L, 9223372036854775807L); print(value.len()) }\n",
        ),
        (
            "ascii-concat",
            "fn invalid(left: Ascii max 4611686018427387903, right: Ascii max 4611686018427387903) { let joined = left + right; print(joined.len()) }\nfn main() {}\n",
        ),
        (
            "bytes-concat",
            "fn invalid(left: Bytes max 9223372036854775799, right: Bytes max 1) { let joined = left + right; print(joined.count()) }\nfn main() {}\n",
        ),
    ];
    for (name, source) in cases {
        let directory = scratch.0.join(name);
        fs::create_dir_all(&directory).unwrap();
        fs::write(directory.join("main.nl"), source).unwrap();
        let result = Command::new("timeout")
            .args([
                "30",
                &selfhost,
                "build",
                ".",
                "-o",
                "module.ll",
                "--runtime=core",
            ])
            .current_dir(&directory)
            .output()
            .unwrap();
        let stderr = String::from_utf8_lossy(&result.stderr);
        assert_eq!(result.status.code(), Some(2), "{name}: {stderr}");
        assert!(
            result.stdout.is_empty(),
            "{name}: unexpected compiler stdout"
        );
        assert!(stderr.contains("error"), "{name}: {stderr}");
        assert!(
            !stderr.contains("not supported by the self-hosted compiler yet"),
            "{name}: {stderr}"
        );
        assert!(
            !directory.join("module.ll").exists(),
            "{name}: emitted invalid IR"
        );
    }
}
