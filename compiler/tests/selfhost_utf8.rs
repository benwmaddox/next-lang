//! Original boundary vectors, checked against Rust's independent UTF-8 decoder.

use std::fmt::Write;
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
fn text_conversions_follow_utf8_boundary_rules() {
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let reference = env!("CARGO_BIN_EXE_nlc");
    let optimization = if std::env::var("NLC_LONG_TESTS").as_deref() == Ok("1") {
        "3"
    } else {
        "1"
    };
    let cached = Command::new("python3")
        .arg(root.join("scripts/build-selfhost-cached.py"))
        .args(["--reference", reference])
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
        "next-lang-utf8-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    )));
    fs::create_dir_all(&scratch.0).unwrap();

    let mut vectors: Vec<Vec<u8>> = (0..=255).map(|byte| vec![byte]).collect();
    for bytes in [
        &b""[..],
        &b"ASCII\0\x7f"[..],
        &b"\xc2\x80"[..],
        &b"\xdf\xbf"[..],
        &b"\xe0\xa0\x80"[..],
        &b"\xed\x9f\xbf"[..],
        &b"\xee\x80\x80"[..],
        &b"\xef\xbf\xbf"[..],
        &b"\xf0\x90\x80\x80"[..],
        &b"\xf4\x8f\xbf\xbf"[..],
        &b"\xc0\xaf"[..],
        &b"\xc1\xbf"[..],
        &b"\xe0\x9f\xbf"[..],
        &b"\xed\xa0\x80"[..],
        &b"\xed\xbf\xbf"[..],
        &b"\xf0\x8f\xbf\xbf"[..],
        &b"\xf4\x90\x80\x80"[..],
        &b"\xf5\x80\x80\x80"[..],
        &b"\xc2\x7f"[..],
        &b"\xe1\x80\x7f"[..],
        &b"\xf1\x80\x80\x7f"[..],
        &b"\xc2"[..],
        &b"\xe0\xa0"[..],
        &b"\xf0\x90\x80"[..],
        &b"\xc2\x80\xe0\xa0\x80\xf0\x90\x80\x80"[..],
    ] {
        vectors.push(bytes.to_vec());
        let mut prefixed = b"A\xc2\xa2".to_vec();
        prefixed.extend_from_slice(bytes);
        vectors.push(prefixed);
    }
    let mut source = String::from("fn main() {\n");
    let mut expected = String::new();
    for (index, bytes) in vectors.iter().enumerate() {
        let literal: String = bytes.iter().map(|byte| format!("\\x{byte:02X}")).collect();
        writeln!(
            source,
            "    let input_{index}: Bytes max {} = b\"{literal}\"",
            bytes.len()
        )
        .unwrap();
        writeln!(source, "    match input_{index}.validate_utf8() {{ ok(_) => print(-1L), err(issue_{index}) => print(issue_{index}.valid_up_to), }}").unwrap();
        writeln!(source, "    print(input_{index}.to_text().is_ok())").unwrap();
        writeln!(source, "    print(input_{index}.to_ascii().is_ok())").unwrap();
        let decoded = std::str::from_utf8(bytes);
        let offset = decoded
            .as_ref()
            .err()
            .map_or(-1, |error| error.valid_up_to() as i64);
        writeln!(
            expected,
            "{offset}\n{}\n{}",
            decoded.is_ok(),
            bytes.is_ascii()
        )
        .unwrap();
        if let Ok(text) = decoded {
            writeln!(source, "    print(input_{index}.to_text().unwrap().len())").unwrap();
            writeln!(expected, "{}", text.chars().count()).unwrap();
        }
    }
    source.push_str("}\n");
    fs::write(scratch.0.join("main.nl"), source).unwrap();
    fs::write(scratch.0.join("package.toml"), "capabilities = [\"out\"]\n").unwrap();
    let built = Command::new("timeout")
        .args([
            "90",
            &selfhost,
            "build",
            ".",
            "-o",
            "module.ll",
            "--runtime=core",
        ])
        .current_dir(&scratch.0)
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "UTF-8 probe build: {}",
        String::from_utf8_lossy(&built.stderr)
    );
    let program_ir = fs::read_to_string(scratch.0.join("module.ll")).unwrap();
    assert!(
        !program_ir.contains("call void @nl_core_nl_text_assert_valid("),
        "ordinary programs must not revalidate constructed Text"
    );
    let linked = Command::new(reference)
        .args(["link-ir", "module.ll", "-o", "program"])
        .env("NLC_OPT_LEVEL", optimization)
        .current_dir(&scratch.0)
        .output()
        .unwrap();
    assert!(
        linked.status.success(),
        "{}",
        String::from_utf8_lossy(&linked.stderr)
    );
    let output = Command::new("timeout")
        .arg("15")
        .arg(scratch.0.join("program"))
        .current_dir(&scratch.0)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        expected,
        "{} UTF-8 vectors",
        vectors.len()
    );

    // Corrupt only this generated test module, immediately before its constructor
    // assertion. User code has no facility for breaking the Text invariant.
    for (assertion_source, assertion_pointer) in [
        (
            "fn main() {}\ntest \"Text literal invariant\" { let value: Text max 1 = \"a\"; print(value) }\n",
            "%text.literal.assert.data.",
        ),
        (
            "fn make_text() -> Text max 1 { \"a\" }\nfn main() {}\ntest \"Text function invariant\" { print(make_text()) }\n",
            "%text.literal.assert.data.",
        ),
        (
            "fn copy(value: Text max 1) -> Text max 1 { value }\nfn main() {}\ntest \"Text borrowed-copy invariant\" { let source: Ascii max 1 = \"a\"; print(copy(source)) }\n",
            "%text.assert.data.",
        ),
    ] {
        fs::write(scratch.0.join("main.nl"), assertion_source).unwrap();
        let built = Command::new("timeout")
            .args([
                "60",
                &selfhost,
                "build",
                ".",
                "-o",
                "checked.ll",
                "--runtime=core",
                "--test",
            ])
            .current_dir(&scratch.0)
            .output()
            .unwrap();
        assert!(
            built.status.success(),
            "{}",
            String::from_utf8_lossy(&built.stderr)
        );
        let checked = fs::read_to_string(scratch.0.join("checked.ll")).unwrap();
        let assertion = checked
            .lines()
            .find(|line| {
                line.contains("call void @nl_core_nl_text_assert_valid(")
                    && line.contains(assertion_pointer)
            })
            .expect("test-mode Text construction must assert its invariant");
        let pointer = assertion
            .split_once("ptr %nl.ctx, ptr ")
            .unwrap()
            .1
            .split_once(", i64 ")
            .unwrap()
            .0;
        let corrupted = checked.replacen(
            assertion,
            &format!("  store i8 -1, ptr {pointer}, align 1\n{assertion}"),
            1,
        );
        fs::write(scratch.0.join("corrupted.ll"), corrupted).unwrap();
        let linked = Command::new(reference)
            .args(["link-ir", "corrupted.ll", "-o", "corrupted"])
            .current_dir(&scratch.0)
            .output()
            .unwrap();
        assert!(
            linked.status.success(),
            "{}",
            String::from_utf8_lossy(&linked.stderr)
        );
        let output = Command::new("timeout")
            .arg("15")
            .arg(scratch.0.join("corrupted"))
            .env("NLC_TEST_INDEX", "0")
            .current_dir(&scratch.0)
            .output()
            .unwrap();
        assert_eq!(
            output.status.code(),
            Some(70),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            String::from_utf8_lossy(&output.stderr)
                .contains("invalid Text constructed (compiler or core library bug)")
        );
    }
}
