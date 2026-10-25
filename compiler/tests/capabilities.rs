use std::fs;
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

fn scratch(label: &str) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock is after the epoch")
        .as_nanos();
    let path = std::env::temp_dir().join(format!("nlc-t20-{label}-{}-{nonce}", std::process::id()));
    fs::create_dir_all(&path).expect("create T20 scratch directory");
    path
}

fn write_package(package: &Path, source: &str) {
    fs::create_dir_all(package).expect("create T20 package");
    fs::write(
        package.join("package.toml"),
        "capabilities = [\"fs\", \"out\", \"env\"]\n",
    )
    .expect("write T20 package manifest");
    fs::write(package.join("main.nl"), source).expect("write T20 program");
}

#[test]
fn arguments_exclude_the_separator_and_obey_startup_bounds() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let package = root.join("tests/run/t20_args");
    let scratch = scratch("args");
    let binary = scratch.join("args-program");

    let forwarded = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("run")
        .arg(&package)
        .arg("--")
        .args(["a", "b", "c"])
        .output()
        .expect("run nlc with forwarded arguments");
    assert!(forwarded.status.success());
    assert_eq!(
        String::from_utf8_lossy(&forwarded.stdout),
        "3\n1\n97\na\n1\n98\nb\n1\n99\nc\n"
    );
    assert!(forwarded.stderr.is_empty());

    let build = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("build")
        .arg(&package)
        .arg("-o")
        .arg(&binary)
        .output()
        .expect("build T20 argument program");
    assert!(
        build.status.success(),
        "T20 argument build failed: {}",
        String::from_utf8_lossy(&build.stderr)
    );

    let maximum_count = (0..64).map(|index| format!("a{index}")).collect::<Vec<_>>();
    let accepted_count = Command::new(&binary)
        .args(&maximum_count)
        .output()
        .expect("run with the maximum number of arguments");
    assert_eq!(accepted_count.status.code(), Some(0));
    assert_eq!(
        String::from_utf8_lossy(&accepted_count.stdout),
        "64\n2\n97\na0\n2\n97\na1\n2\n97\na2\n"
    );

    let too_many = Command::new(&binary)
        .args((0..65).map(|index| format!("a{index}")))
        .output()
        .expect("run with one argument over the limit");
    assert_eq!(too_many.status.code(), Some(1));
    assert!(
        String::from_utf8_lossy(&too_many.stderr)
            .contains("more than 64 program arguments were supplied")
    );

    let maximum_length = "x".repeat(4096);
    let accepted_length = Command::new(&binary)
        .arg(&maximum_length)
        .output()
        .expect("run with a maximum length argument");
    assert_eq!(accepted_length.status.code(), Some(0));
    let stdout = String::from_utf8_lossy(&accepted_length.stdout);
    assert!(stdout.starts_with("1\n4096\n120\n"));
    assert_eq!(stdout.lines().nth(3).map(str::len), Some(4096));

    let too_long = Command::new(&binary)
        .arg("x".repeat(4097))
        .output()
        .expect("run with one argument over the length limit");
    assert_eq!(too_long.status.code(), Some(1));
    assert!(
        String::from_utf8_lossy(&too_long.stderr)
            .contains("program argument is longer than 4096 bytes")
    );

    let _ = fs::remove_dir_all(scratch);
}

#[test]
fn filesystem_roots_and_directory_kinds_are_enforced() {
    let root = scratch("fs");
    let package = root.join("package");
    let work = root.join("work");
    let outside = root.join("outside");
    fs::create_dir_all(&work).expect("create program working directory");
    fs::create_dir(work.join("b")).expect("create directory entry");
    fs::write(work.join("a"), b"file").expect("create file entry");
    fs::write(outside.as_path(), b"outside").expect("create target outside the root");
    symlink(&outside, work.join("c")).expect("create escaping symlink");

    write_package(
        &package,
        r#"
fn show_outside(fs: Fs, out: Out, path: Path) -> Result<(), IoError> {
    var buffer: list<byte, 8> = list {}
    match fs.read(path, buffer) {
        err(Outside) => { out.line(b"outside")?; () },
        _ => { out.line(b"escaped")?; () }
    }
    ok(())
}

fn show_kind(out: Out, kind: FileKind) -> Result<(), IoError> {
    match kind {
        File => out.line(b"File"),
        Directory => out.line(b"Directory"),
        Other => out.line(b"Other")
    }
}

fn main(env: Env) -> Result<(), IoError> {
    let fs = env.fs
    let out = env.out
    show_outside(fs, out, b"/absolute")?
    show_outside(fs, out, b"../outside")?
    show_outside(fs, out, b"c")?
    var entries: list<DirEntry, 3> = list {}
    match fs.list(b".", entries) {
        ok(_) => {
            out.line(entries[0L].name)?
            show_kind(out, entries[0L].kind)?
            out.line(entries[1L].name)?
            show_kind(out, entries[1L].kind)?
            out.line(entries[2L].name)?
            show_kind(out, entries[2L].kind)?
            ()
        },
        _ => { out.line(b"list failed")?; () }
    }
    ok(())
}
"#,
    );

    let output = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("run")
        .arg(&package)
        .current_dir(&work)
        .output()
        .expect("run filesystem security program");
    assert!(
        output.status.success(),
        "T20 filesystem program failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        "outside\noutside\noutside\na\nFile\nb\nDirectory\nc\nOther\n"
    );
    assert!(output.stderr.is_empty());

    fs::remove_dir_all(root).expect("remove T20 filesystem scratch directory");
}

#[test]
fn output_write_returns_an_error_when_the_pipe_is_closed() {
    let root = scratch("broken-pipe");
    let package = root.join("package");
    write_package(
        &package,
        r#"
fn main(env: Env) -> Result<(), IoError> {
    let out = env.out
    let err = env.err
    match out.write(b"payload") {
        err(_) => (),
        ok(_) => { err.line(b"write unexpectedly succeeded")?; () }
    }
    ok(())
}
"#,
    );

    let mut child = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("run")
        .arg(&package)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("start output error test");
    drop(child.stdout.take());
    let output = child.wait_with_output().expect("wait for output test");
    assert_eq!(
        output.status.code(),
        Some(0),
        "broken-pipe program failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty());
    fs::remove_dir_all(root).expect("remove broken pipe scratch directory");
}

#[test]
fn print_exits_one_when_stdout_write_fails() {
    let root = scratch("print-broken-pipe");
    let package = root.join("package");
    fs::create_dir_all(&package).expect("create print failure package");
    fs::write(package.join("main.nl"), "fn main() { print(1) }\n")
        .expect("write print failure program");

    let mut child = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("run")
        .arg(&package)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("start print failure test");
    drop(child.stdout.take());
    let output = child
        .wait_with_output()
        .expect("wait for print failure test");
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("standard output write failed"));
    fs::remove_dir_all(root).expect("remove print failure scratch directory");
}
