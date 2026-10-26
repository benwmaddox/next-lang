use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

struct Scratch(PathBuf);

use std::path::PathBuf;

impl Scratch {
    fn new() -> Self {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock is after the epoch")
            .as_nanos();
        let path =
            std::env::temp_dir().join(format!("next-lang-link-ir-{}-{stamp}", std::process::id()));
        fs::create_dir_all(&path).expect("create scratch directory");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn run(args: &[&Path], cwd: &Path) -> std::process::Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_nlc"));
    for argument in args {
        command.arg(argument);
    }
    command.current_dir(cwd).output().expect("run nlc command")
}

fn write_ir(path: &Path, build: &str, tests: &str, body: &str) {
    let source = format!(
        "; nlc-link-ir 1\n; nlc.build {build}\n; nlc.stack offset\n; nlc.recursion none\n{tests}source_filename = \"next-lang\"\n{body}\n; nlc-link-ir end\n"
    );
    fs::write(path, source).expect("write IR fixture");
}

#[test]
fn link_ir_uses_the_runtime_and_test_ir_runs_decoded_test_names() {
    let scratch = Scratch::new();
    let program = scratch.path().join("program.ll");
    let executable = scratch.path().join("program");
    write_ir(
        &program,
        "program",
        "",
        "define i32 @main(i32 %argc, ptr %argv) {\nentry:\n  ret i32 0\n}",
    );
    let linked = run(
        &[Path::new("link-ir"), &program, Path::new("-o"), &executable],
        scratch.path(),
    );
    assert!(
        linked.status.success(),
        "link-ir failed: {}",
        String::from_utf8_lossy(&linked.stderr)
    );
    let execution = Command::new(&executable)
        .output()
        .expect("run linked program");
    assert!(execution.status.success());

    let tests = scratch.path().join("tests.ll");
    write_ir(
        &tests,
        "test",
        "; nlc.test 0 706173736573\n; nlc.test 1 c3a9\n",
        "define i32 @main(i32 %argc, ptr %argv) {\nentry:\n  ret i32 0\n}",
    );
    let result = run(&[Path::new("test-ir"), &tests], scratch.path());
    assert!(
        result.status.success(),
        "test-ir failed: {}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert_eq!(
        result.stdout,
        "ok   passes\nok   é\n2 passed, 0 failed\n".as_bytes()
    );
    assert!(result.stderr.is_empty());
}

#[test]
fn test_ir_skips_linking_an_empty_test_module_and_rejects_program_modules() {
    let scratch = Scratch::new();
    let empty = scratch.path().join("empty.ll");
    write_ir(&empty, "test", "", "not valid LLVM");
    let result = run(&[Path::new("test-ir"), &empty], scratch.path());
    assert!(result.status.success());
    assert_eq!(result.stdout, b"0 passed, 0 failed\n");

    let program = scratch.path().join("program.ll");
    write_ir(&program, "program", "", "not valid LLVM");
    let result = run(&[Path::new("test-ir"), &program], scratch.path());
    assert_eq!(result.status.code(), Some(3));
    assert_eq!(
        result.stderr,
        b"nlc: tool failure: test-ir requires an IR file built with --test\n"
    );
}

#[test]
fn link_ir_rejects_bad_versions_stack_modes_recursion_and_truncation() {
    let scratch = Scratch::new();
    let cases = [
        (
            "unknown version",
            "; nlc-link-ir 2\n; nlc.build program\n; nlc.stack offset\n; nlc.recursion none\n; nlc-link-ir end\n",
        ),
        (
            "wrong stack mode",
            "; nlc-link-ir 1\n; nlc.build program\n; nlc.stack pointer\n; nlc.recursion none\n; nlc-link-ir end\n",
        ),
        (
            "recursion declaration",
            "; nlc-link-ir 1\n; nlc.build program\n; nlc.stack offset\n; nlc.recursion yes\n; nlc-link-ir end\n",
        ),
        (
            "recursion targets",
            "; nlc-link-ir 1\n; nlc.build program\n; nlc.stack offset\n; nlc.recursion none\ncall void @f() ; nlc.recursion.targets=0\n; nlc-link-ir end\n",
        ),
        (
            "end marker",
            "; nlc-link-ir 1\n; nlc.build program\n; nlc.stack offset\n; nlc.recursion none\n",
        ),
    ];
    for (index, (reason, source)) in cases.iter().enumerate() {
        let ir = scratch.path().join(format!("bad-{index}.ll"));
        fs::write(&ir, source).expect("write malformed IR");
        let output = scratch.path().join(format!("bad-{index}"));
        let result = run(
            &[Path::new("link-ir"), &ir, Path::new("-o"), &output],
            scratch.path(),
        );
        assert_eq!(result.status.code(), Some(3), "{reason}");
        assert!(
            String::from_utf8_lossy(&result.stderr)
                .starts_with("nlc: tool failure: invalid nlc-link-ir metadata:"),
            "{reason}: {}",
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(!output.exists(), "{reason} created an executable");
    }
}

#[test]
fn link_ir_version_two_selects_the_runtime_and_validates_the_core_hash() {
    let scratch = Scratch::new();
    let ir = scratch.path().join("v2.ll");
    let executable = scratch.path().join("v2");
    let hash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    let source = format!(
        "; nlc-link-ir 2\n; nlc.build program\n; nlc.stack offset\n; nlc.recursion none\n; nlc.runtime c\n; nlc.core {hash}\nsource_filename = \"next-lang\"\ndefine i32 @main(i32 %argc, ptr %argv) {{\nentry:\n  ret i32 0\n}}\n; nlc-link-ir end\n"
    );
    fs::write(&ir, source).expect("write version-two IR");
    let linked = run(
        &[Path::new("link-ir"), &ir, Path::new("-o"), &executable],
        scratch.path(),
    );
    assert!(
        linked.status.success(),
        "version-two C IR did not link: {}",
        String::from_utf8_lossy(&linked.stderr)
    );
    assert!(
        Command::new(&executable)
            .output()
            .expect("run version-two executable")
            .status
            .success()
    );

    for (name, runtime, core_hash) in [
        ("missing-runtime", "", format!("; nlc.core {hash}\n")),
        (
            "unknown-runtime",
            "; nlc.runtime libc\n",
            format!("; nlc.core {hash}\n"),
        ),
        ("missing-hash", "; nlc.runtime c\n", String::new()),
        (
            "uppercase-hash",
            "; nlc.runtime core\n",
            format!("; nlc.core {}\n", "A".repeat(64)),
        ),
    ] {
        let path = scratch.path().join(format!("{name}.ll"));
        let content = format!(
            "; nlc-link-ir 2\n; nlc.build program\n; nlc.stack offset\n; nlc.recursion none\n{runtime}{core_hash}; nlc-link-ir end\n"
        );
        fs::write(&path, content).expect("write malformed version-two IR");
        let output = scratch.path().join(name);
        let result = run(
            &[Path::new("link-ir"), &path, Path::new("-o"), &output],
            scratch.path(),
        );
        assert_eq!(result.status.code(), Some(3), "{name}");
        assert!(
            String::from_utf8_lossy(&result.stderr)
                .starts_with("nlc: tool failure: invalid nlc-link-ir metadata:"),
            "{name}: {}",
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(!output.exists(), "{name} created an executable");
    }
}
