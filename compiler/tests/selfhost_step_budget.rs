//! Manifest budgets are opt-in, shared across calls, and diagnosed before lowering.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

struct Scratch(PathBuf);

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn successful(command: &mut Command, what: &str) -> Output {
    let result = command
        .output()
        .unwrap_or_else(|error| panic!("{what}: {error}"));
    assert!(
        result.status.success(),
        "{what}: status {:?}\n{}\n{}",
        result.status.code(),
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
    result
}

fn package(scratch: &Scratch, name: &str, manifest: &str, source: &str) -> PathBuf {
    let directory = scratch.0.join(name);
    fs::create_dir_all(&directory).unwrap();
    fs::write(directory.join("package.toml"), manifest).unwrap();
    fs::write(directory.join("main.nl"), source).unwrap();
    directory
}

fn compile(selfhost: &str, directory: &Path) -> Output {
    Command::new("timeout")
        .args([
            "60",
            selfhost,
            "build",
            ".",
            "-o",
            "module.ll",
            "--runtime=core",
        ])
        .current_dir(directory)
        .output()
        .expect("run selfhost manifest probe")
}

#[test]
fn manifest_step_budgets_are_optional_checked_and_shared() {
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let reference = env!("CARGO_BIN_EXE_nlc");
    let cached = successful(
        Command::new("python3")
            .arg(root.join("scripts/build-selfhost-cached.py"))
            .args(["--reference", reference])
            .current_dir(root),
        "build working-tree selfhost compiler",
    );
    let selfhost = String::from_utf8(cached.stdout).unwrap().trim().to_owned();
    let scratch = Scratch(std::env::temp_dir().join(format!(
        "next-lang-step-budget-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    )));

    for (index, value) in [
        "",
        "-1",
        "1.5",
        "\"10\"",
        "10 MB",
        "_1",
        "1_",
        "1__0",
        "9223372036854775808",
        "18446744073709551616",
    ]
    .iter()
    .enumerate()
    {
        let directory = package(
            &scratch,
            &format!("invalid-{index}"),
            &format!("step_budget.main = {value}\n"),
            "fn main() {}\n",
        );
        let result = compile(&selfhost, &directory);
        let stderr = String::from_utf8_lossy(&result.stderr);
        assert_eq!(result.status.code(), Some(3), "value {value:?}: {stderr}");
        assert!(
            stderr.contains("step_budget.main"),
            "value {value:?}: {stderr}"
        );
        assert!(
            stderr.contains("nonnegative integer"),
            "value {value:?}: {stderr}"
        );
        assert!(
            !directory.join("module.ll").exists(),
            "invalid budget emitted IR"
        );
    }
    for (name, manifest, message) in [
        (
            "duplicate",
            "step_budget.main = 1\nstep_budget.main = 2\n",
            "listed more than once",
        ),
        ("missing-equals", "step_budget.main 10\n", "expected"),
    ] {
        let directory = package(&scratch, name, manifest, "fn main() {}\n");
        let result = compile(&selfhost, &directory);
        let stderr = String::from_utf8_lossy(&result.stderr);
        assert_eq!(result.status.code(), Some(3), "{name}: {stderr}");
        assert!(
            stderr.contains("step_budget.main") && stderr.contains(message),
            "{name}: {stderr}"
        );
        assert!(!directory.join("module.ll").exists());
    }

    let long_loop = "fn main() {\n    var index = 0L\n    while index < 10000001L { index += 1L }\n    print(index)\n}\n";
    let shared = "fn burn() {\n    var index = 0L\n    while index < 2L { index += 1L }\n}\nfn main() { burn(); burn(); print(99) }\n";
    for (name, manifest, source, expected_status, expected_stdout) in [
        (
            "unlimited",
            "capabilities = [\"out\"]\n",
            long_loop,
            0,
            "10000001\n",
        ),
        (
            "zero",
            "step_budget.main = 0\n",
            "fn main() { while true { continue } }\n",
            1,
            "",
        ),
        ("shared", "step_budget.main = 3\n", shared, 1, ""),
        ("exact", "step_budget.main = 4\n", shared, 0, "99\n"),
        ("separated", "step_budget.main = 1_000\n", shared, 0, "99\n"),
    ] {
        let directory = package(&scratch, name, manifest, source);
        let compiled = compile(&selfhost, &directory);
        assert!(
            compiled.status.success(),
            "{name}: {}",
            String::from_utf8_lossy(&compiled.stderr)
        );
        let ir = fs::read_to_string(directory.join("module.ll")).unwrap();
        assert_eq!(
            ir.contains("call i1 @nl_core_nl_context_step_budget_take("),
            name != "unlimited",
            "{name}: budget checks must be emitted only for an explicit budget"
        );
        successful(
            Command::new(reference)
                .args(["link-ir", "module.ll", "-o", "program"])
                .env("NLC_OPT_LEVEL", "3")
                .current_dir(&directory),
            &format!("link {name}"),
        );
        let output = Command::new("timeout")
            .arg("15")
            .arg(directory.join("program"))
            .current_dir(&directory)
            .output()
            .unwrap();
        assert_eq!(
            output.status.code(),
            Some(expected_status),
            "{name}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(output.stdout, expected_stdout.as_bytes(), "{name}");
        if expected_status == 0 {
            assert!(
                output.stderr.is_empty(),
                "{name}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        } else {
            assert!(
                String::from_utf8_lossy(&output.stderr).contains("loop step budget exhausted"),
                "{name}"
            );
        }
    }
    let maximum = package(
        &scratch,
        "maximum",
        "step_budget.main = 9223372036854775807\n",
        "fn main() {}\n",
    );
    let compiled = compile(&selfhost, &maximum);
    assert!(
        compiled.status.success(),
        "maximum budget: {}",
        String::from_utf8_lossy(&compiled.stderr)
    );
}
