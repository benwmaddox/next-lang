//! E3a3-fix: `break` and `continue` must release the data-stack space that
//! blocks between the jump and the loop body reserved, even when the loop
//! body itself holds no region slots. Each fixture jumps out of an 8 KB
//! region local millions of times, so a leak would climb to gigabytes.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const PEAK_LIMIT: u64 = 1024 * 1024;

const FIXTURES: [&str; 6] = [
    "tests/e3/e3a3fix_continue_if",
    "tests/e3/e3a3fix_break_inner",
    "tests/e3/e3a3fix_continue_match",
    "tests/e3/e3a3fix_continue_nested",
    "tests/e3/e3a3fix_expression_exits",
    "tests/e3/e3a3fix_while_exits",
];

fn selfhost_enabled() -> bool {
    std::env::var("NLC_FRONTEND").as_deref() == Ok("selfhost")
}

fn run(command: &mut Command, what: &str) -> std::process::Output {
    let output = command
        .output()
        .unwrap_or_else(|error| panic!("{what}: {error}"));
    assert!(
        output.status.success(),
        "{what} failed (status {:?}):\n{}\n{}",
        output.status.code(),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    output
}

struct Scratch(PathBuf);

impl Scratch {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "next-lang-loop-exit-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
        ));
        fs::create_dir_all(&path).expect("create loop-exit scratch directory");
        Self(path)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn stat(stderr: &str, name: &str) -> u64 {
    let line = stderr
        .lines()
        .find(|line| line.starts_with("nl offset stack entry "))
        .unwrap_or_else(|| panic!("no stack stats line in:\n{stderr}"));
    let key = format!("{name}=");
    let start = line
        .find(&key)
        .unwrap_or_else(|| panic!("{name} missing from stats line: {line}"))
        + key.len();
    line[start..]
        .split(' ')
        .next()
        .and_then(|value| value.parse().ok())
        .unwrap_or_else(|| panic!("malformed {name} in stats line: {line}"))
}

#[test]
fn selfhost_loop_exits_release_nested_block_reservations() {
    if !selfhost_enabled() {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let scratch = Scratch::new();
    let reference = env!("CARGO_BIN_EXE_nlc");
    let cache = run(
        Command::new("python3")
            .arg(root.join("scripts/build-selfhost-cached.py"))
            .arg("--reference")
            .arg(reference)
            .current_dir(root),
        "build or reuse the working-tree selfhost compiler",
    );
    let selfhost = String::from_utf8(cache.stdout)
        .expect("cached selfhost compiler path is UTF-8")
        .trim()
        .to_owned();

    for fixture in FIXTURES {
        let source = root.join(fixture);
        let name = source.file_name().expect("fixture has a name").to_owned();
        for optimization in ["1", "3"] {
            for threshold in [None, Some("--test-region-threshold=0")] {
                let package = scratch.0.join(&name).join(format!(
                    "o{optimization}-{}",
                    if threshold.is_some() { "t0" } else { "default" }
                ));
                fs::create_dir_all(&package).expect("create fixture copy");
                for file in ["main.nl", "package.toml"] {
                    fs::copy(source.join(file), package.join(file))
                        .expect("copy fixture to scratch package");
                }
                let what = format!("{fixture} at O{optimization} {threshold:?}");
                let mut build = Command::new(&selfhost);
                build
                    .args(["build", ".", "-o", "module.ll", "--test"])
                    .env("NLC_OPT_LEVEL", optimization)
                    .current_dir(&package);
                if let Some(threshold) = threshold {
                    build.arg(threshold);
                }
                run(&mut build, &format!("build {what} with selfhost"));
                run(
                    Command::new(reference)
                        .args(["link-ir", "module.ll", "-o", "program"])
                        .env("NLC_OPT_LEVEL", optimization)
                        .current_dir(&package),
                    &format!("link {what}"),
                );
                let output = Command::new(package.join("program"))
                    .env("NLC_STACK_STATS", "1")
                    .env_remove("NLC_STACK_PREALLOC")
                    .env_remove("NLC_TEST_STACK_FORCE_MOVE")
                    .current_dir(&package)
                    .output()
                    .unwrap_or_else(|error| panic!("run {what}: {error}"));
                let stderr = String::from_utf8_lossy(&output.stderr);
                assert!(output.status.success(), "{what} failed: {stderr}");
                let expected =
                    fs::read(source.join("expected.stdout")).expect("read fixture expected output");
                assert_eq!(output.stdout, expected, "{what} stdout");
                let peak = stat(&stderr, "peak_used");
                assert!(
                    peak < PEAK_LIMIT,
                    "{what} leaked data-stack space across loop exits: peak_used={peak}"
                );
            }
        }
    }
}
