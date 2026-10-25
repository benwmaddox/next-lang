use std::ffi::OsString;
use std::fs;
use std::os::unix::ffi::OsStringExt;
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT_TEMP: AtomicUsize = AtomicUsize::new(0);

struct TempWorkspace(PathBuf);

impl TempWorkspace {
    fn new(label: &str) -> Self {
        let id = NEXT_TEMP.fetch_add(1, Ordering::Relaxed);
        let path =
            std::env::temp_dir().join(format!("nlc-t25-{label}-{}-{id}", std::process::id()));
        fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempWorkspace {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn nlc(args: &[&str], current_dir: Option<&Path>) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_nlc"));
    command.args(args);
    if let Some(current_dir) = current_dir {
        command.current_dir(current_dir);
    }
    command.output().expect("could not launch nlc")
}

fn write_package(package: &Path, source: &str) {
    fs::create_dir_all(package).unwrap();
    fs::write(package.join("main.nl"), source).unwrap();
    fs::write(
        package.join("package.toml"),
        "capabilities = [\"fs\", \"out\"]\n",
    )
    .unwrap();
}

#[test]
fn lex_matches_token_dump_and_skips_parsing_without_partial_output() {
    let workspace = TempWorkspace::new("lex");
    let package = workspace.path().join("package");
    fs::create_dir_all(&package).unwrap();
    fs::write(package.join("main.nl"), "fn main() { print(7) }\n").unwrap();

    let lex = nlc(&["lex", package.to_str().unwrap()], None);
    let parse = nlc(&["parse", package.to_str().unwrap(), "--tokens"], None);
    assert!(
        lex.status.success(),
        "{}",
        String::from_utf8_lossy(&lex.stderr)
    );
    assert!(
        parse.status.success(),
        "{}",
        String::from_utf8_lossy(&parse.stderr)
    );
    assert_eq!(lex.stdout, parse.stdout);
    assert!(lex.stderr.is_empty());

    fs::write(package.join("main.nl"), "fn main() { let = 1 }\n").unwrap();
    let lex = nlc(&["lex", package.to_str().unwrap()], None);
    let parse = nlc(&["parse", package.to_str().unwrap(), "--tokens"], None);
    assert!(
        lex.status.success(),
        "{}",
        String::from_utf8_lossy(&lex.stderr)
    );
    assert_eq!(lex.status.code(), Some(0));
    assert_eq!(parse.status.code(), Some(2));
    assert!(!lex.stdout.is_empty());
    assert!(
        parse.stdout.is_empty(),
        "parse --tokens prints only on success"
    );

    fs::write(package.join("a.nl"), "let x = 1\n").unwrap();
    fs::write(package.join("z.nl"), "@\n").unwrap();
    let failure = nlc(&["lex", package.to_str().unwrap()], None);
    assert_eq!(failure.status.code(), Some(2));
    assert!(
        failure.stdout.is_empty(),
        "a later lexical error must not leak earlier tokens"
    );
    let diagnostic = String::from_utf8_lossy(&failure.stderr);
    assert!(diagnostic.contains("z.nl:1:1: error:"), "{diagnostic}");
}

#[test]
fn lex_source_selection_handles_extensions_symlinks_invalid_names_and_ignored_entries() {
    let workspace = TempWorkspace::new("lex-listing");
    let package = workspace.path().join("package");
    fs::create_dir_all(&package).unwrap();
    fs::write(package.join(".nl"), "hidden\n").unwrap();
    fs::write(package.join("a.NL"), "upper\n").unwrap();
    fs::write(package.join("a.nl.bak"), "backup\n").unwrap();
    fs::create_dir(package.join("directory.nl")).unwrap();
    fs::write(package.join("target.bin"), "linked\n").unwrap();
    fs::write(package.join("source.nl"), "source\n").unwrap();
    symlink("target.bin", package.join("link.nl")).unwrap();
    symlink("missing.bin", package.join("dangling.nl")).unwrap();
    symlink("directory.nl", package.join("directory-link.nl")).unwrap();
    fs::write(
        package.join(OsString::from_vec(vec![0xff, b'.', b'n', b'l'])),
        "raw name\n",
    )
    .unwrap();
    for index in 0..10_000 {
        fs::write(package.join(format!("ignored-{index:05}.txt")), []).unwrap();
    }

    let output = nlc(&["lex", package.to_str().unwrap()], None);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let dump = String::from_utf8_lossy(&output.stdout);
    let headers = dump
        .lines()
        .filter(|line| line.starts_with("file "))
        .collect::<Vec<_>>();
    assert_eq!(
        headers,
        [
            "file \"link.nl\"",
            "file \"source.nl\"",
            "file \"<source>\""
        ]
    );
    assert!(output.stderr.is_empty());

    fs::write(
        package.join(OsString::from_vec(vec![
            b'i', b'n', b'v', b'a', b'l', b'i', b'd', b'.', b'n', b'l',
        ])),
        [0xff],
    )
    .unwrap();
    let invalid = nlc(&["lex", package.to_str().unwrap()], None);
    assert_eq!(invalid.status.code(), Some(2));
    assert!(invalid.stdout.is_empty());
    assert!(
        String::from_utf8_lossy(&invalid.stderr)
            .contains("invalid.nl:1:1: error: source is not valid UTF-8")
    );
}

#[test]
fn lex_accepts_256_sources_and_rejects_257() {
    let workspace = TempWorkspace::new("lex-count");
    let package = workspace.path().join("package");
    fs::create_dir_all(&package).unwrap();
    for index in 0..256 {
        fs::write(package.join(format!("file-{index:03}.nl")), []).unwrap();
    }
    let output = nlc(&["lex", package.to_str().unwrap()], None);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&output.stdout)
            .lines()
            .filter(|line| line.starts_with("file "))
            .count(),
        256
    );

    fs::write(package.join("file-256.nl"), []).unwrap();
    let output = nlc(&["lex", package.to_str().unwrap()], None);
    assert_eq!(output.status.code(), Some(2));
    assert!(output.stdout.is_empty());
    assert!(
        String::from_utf8_lossy(&output.stderr)
            .contains("source file limit of 256 per package exceeded")
    );
}

#[test]
fn fs_list_with_extension_filters_sorts_and_follows_symlinks() {
    let workspace = TempWorkspace::new("fs-listing");
    let package = workspace.path().join("package");
    let data = workspace.path().join("data");
    write_package(&package, LISTING_PROGRAM.replace("CAPACITY", "7").as_str());
    fs::create_dir(&data).unwrap();
    fs::write(workspace.path().join("outside.nl"), []).unwrap();
    fs::write(data.join("a.nl"), []).unwrap();
    fs::write(data.join(".nl"), []).unwrap();
    fs::write(data.join("upper.NL"), []).unwrap();
    fs::write(data.join("backup.nl.bak"), []).unwrap();
    fs::write(data.join("trailing."), []).unwrap();
    fs::create_dir(data.join("x.nl")).unwrap();
    fs::create_dir(data.join("target-dir")).unwrap();
    fs::write(data.join("target.bin"), []).unwrap();
    symlink("target.bin", data.join("link.nl")).unwrap();
    symlink("missing.bin", data.join("dangling.nl")).unwrap();
    symlink("target-dir", data.join("dirlink.nl")).unwrap();
    symlink("../outside.nl", data.join("escape.nl")).unwrap();
    fs::write(
        data.join(OsString::from_vec(vec![0xff, b'.', b'n', b'l'])),
        [],
    )
    .unwrap();
    for index in 0..10_000 {
        fs::write(data.join(format!("ignored-{index:05}.txt")), []).unwrap();
    }

    let run = nlc(&["run", package.to_str().unwrap()], Some(&data));
    assert!(
        run.status.success(),
        "{}",
        String::from_utf8_lossy(&run.stderr)
    );
    let mut expected =
        b"7Fa.nl\nOdangling.nl\nDdirlink.nl\nOescape.nl\nFlink.nl\nDx.nl\nF".to_vec();
    expected.extend_from_slice(&[0xff, b'.', b'n', b'l', b'\n']);
    expected.extend_from_slice(b"1\n");
    assert_eq!(run.stdout, expected);

    let small_package = workspace.path().join("small-package");
    write_package(
        &small_package,
        LISTING_PROGRAM.replace("CAPACITY", "6").as_str(),
    );
    let overflow = nlc(&["run", small_package.to_str().unwrap()], Some(&data));
    assert!(
        overflow.status.success(),
        "{}",
        String::from_utf8_lossy(&overflow.stderr)
    );
    assert_eq!(overflow.stdout, b"01\n");
}

#[test]
fn bytes_builder_streams_256_file_contents_into_the_package_buffer() {
    let workspace = TempWorkspace::new("bytes-files");
    let package = workspace.path().join("package");
    let data = workspace.path().join("data");
    write_package(&package, BYTES_FILES_PROGRAM);
    fs::create_dir(&data).unwrap();
    for index in 0..256usize {
        let name = format!("file-{index:03}.nl");
        fs::write(data.join(name), [index as u8; 256 * 1024]).unwrap();
    }

    let run = nlc(&["run", package.to_str().unwrap()], Some(&data));
    assert!(
        run.status.success(),
        "{}",
        String::from_utf8_lossy(&run.stderr)
    );
    assert_eq!(run.stdout, b"67108864 0 255\n");
}

#[test]
fn bytes_dynamic_index_checks_the_live_length() {
    let workspace = TempWorkspace::new("bytes-index");
    let package = workspace.path().join("package");
    write_package(
        &package,
        r#"
fn read_byte(value: Bytes max 8, index: long) -> byte {
    value[index]
}

fn main() {
    let value: Bytes max 8 = b"a"
    if read_byte(value, 1L) == 0 {}
}
"#,
    );
    let run = nlc(&["run", package.to_str().unwrap()], None);
    assert!(!run.status.success());
    assert!(run.stdout.is_empty());
    assert!(
        String::from_utf8_lossy(&run.stderr).contains("index out of range"),
        "{}",
        String::from_utf8_lossy(&run.stderr)
    );
}

#[test]
fn bytes_push_inside_a_loop_must_handle_possible_full_results() {
    let workspace = TempWorkspace::new("bytes-loop-push");
    let package = workspace.path().join("package");
    write_package(
        &package,
        r#"
fn main() {
    var value: Bytes max 2 = Bytes.empty()
    for index in 0..3 { value.push(97) }
}
"#,
    );
    let run = nlc(&["run", package.to_str().unwrap()], None);
    assert_eq!(run.status.code(), Some(2));
    assert!(run.stdout.is_empty());
    assert!(
        String::from_utf8_lossy(&run.stderr)
            .contains("loop can grow 'value' to 3 bytes, above its Bytes max 2"),
        "{}",
        String::from_utf8_lossy(&run.stderr)
    );
}

const LISTING_PROGRAM: &str = r#"
fn main(env: Env) -> Result<(), IoError> {
    let fs = env.fs
    let out = env.out
    var entries: list<DirEntry, CAPACITY> = list {}
    match fs.list_with_extension(".", "nl", entries) {
        ok(_) => {
            out.long(entries.count())?
            for entry in entries {
                match entry.kind {
                    File => out.write(b"F")?,
                    Directory => out.write(b"D")?,
                    Other => out.write(b"O")?
                }
                out.write(entry.name)?
                out.line(b"")?
            }
        },
        err(TooMany) => out.long(entries.count())?
    }
    var empty_extension: list<DirEntry, 1> = list {}
    fs.list_with_extension(".", "", empty_extension)?
    out.long(empty_extension.count())?
    out.line(b"")?
    ok(())
}
"#;

const BYTES_FILES_PROGRAM: &str = r#"
fn main(env: Env) -> Result<(), IoError> {
    let fs = env.fs
    let out = env.out
    var entries: list<DirEntry, 256> = list {}
    fs.list_with_extension(".", "nl", entries)?
    var package: Bytes max 67108864 = Bytes.empty()
    for entry in entries {
        var file: Bytes max 262144 = Bytes.empty()
        fs.read(entry.name, file)?
        package.try_append(file).unwrap()
    }
    if package.try_append(b"x").is_ok() { return err(TooLarge) }
    out.long(package.count())?
    out.write(b" ")?
    out.long(package[0L].to_long())?
    out.write(b" ")?
    out.long(package[67108863L].to_long())?
    out.line(b"")?
    ok(())
}
"#;
