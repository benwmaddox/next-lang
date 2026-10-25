use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

fn scratch() -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock is after the epoch")
        .as_nanos();
    let path = std::env::temp_dir().join(format!("nlc-stdout-pipe-{}-{nonce}", std::process::id()));
    fs::create_dir_all(&path).expect("create stdout pipe scratch directory");
    path
}

fn as_arg(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn assert_closed_pipe_succeeds(args: &[String]) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap_or_else(|error| panic!("could not start nlc {args:?}: {error}"));
    drop(child.stdout.take());
    let output = child
        .wait_with_output()
        .unwrap_or_else(|error| panic!("could not wait for nlc {args:?}: {error}"));
    assert_eq!(
        output.status.code(),
        Some(0),
        "nlc {args:?} failed with stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "nlc {args:?} wrote to stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn every_cli_subcommand_quietly_accepts_a_closed_stdout_pipe() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let scratch = scratch();
    let quiet_package = scratch.join("quiet-package");
    fs::create_dir_all(&quiet_package).expect("create quiet package");
    fs::write(quiet_package.join("main.nl"), "fn main() {}\n").expect("write quiet package source");
    let built_binary = scratch.join("quiet-program");
    let array_package = root.join("tests/run/t24_array_literals");
    let test_package = root.join("tests/test/t24_byte_escape");
    let parse_package = root.join("tests/parse/cases/string_escaping");

    let cases = vec![
        vec!["run".to_owned(), as_arg(&quiet_package)],
        vec![
            "build".to_owned(),
            as_arg(&quiet_package),
            "-o".to_owned(),
            as_arg(&built_binary),
        ],
        vec!["test".to_owned(), as_arg(&test_package)],
        vec![
            "parse".to_owned(),
            as_arg(&parse_package),
            "--tokens".to_owned(),
            "--tree".to_owned(),
        ],
        vec![
            "inspect".to_owned(),
            "memory".to_owned(),
            as_arg(&array_package),
        ],
        vec![
            "inspect".to_owned(),
            "contracts".to_owned(),
            as_arg(&array_package),
        ],
        vec![
            "inspect".to_owned(),
            "stacks".to_owned(),
            as_arg(&array_package),
        ],
    ];

    for args in cases {
        assert_closed_pipe_succeeds(&args);
    }
    fs::remove_dir_all(scratch).expect("remove stdout pipe scratch directory");
}
