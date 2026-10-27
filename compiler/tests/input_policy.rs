use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::Mutex;

const FILE_LIMIT: usize = 16 * 1024 * 1024;
const PACKAGE_LIMIT: usize = 64 * 1024 * 1024;
const FILE_TOKEN_LIMIT: usize = 1_000_000;
const PACKAGE_TOKEN_LIMIT: usize = 4_000_000;
const NODE_LIMIT: usize = 2_000_000;
const WORK_LIMIT: usize = 72_000_000;

// Mutex to prevent concurrent large-input runs from causing memory pressure.
static LARGE_INPUT_LOCK: Mutex<()> = Mutex::new(());

struct Scratch(PathBuf);

impl Scratch {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "next-lang-input-policy-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
        ));
        fs::create_dir_all(&path).expect("create input policy scratch directory");
        Self(path)
    }

    fn package(&self) -> PathBuf {
        self.0.join("package")
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn is_long_tests_mode() -> bool {
    std::env::var_os("NLC_LONG_TESTS").is_some_and(|v| v == "1")
}

// Each input-policy test explicitly drives both frontends, so one invocation
// of this integration test covers the same cases in both full suites.
fn run_input_policy_once() -> bool {
    std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost")
}

fn get_default_commands() -> &'static [&'static str] {
    &["parse", "build"]
}

fn get_all_commands() -> &'static [&'static str] {
    &["run", "build", "test", "parse", "lex"]
}

fn write_package(package: &Path, files: Vec<(&str, Vec<u8>)>) {
    let _ = fs::remove_dir_all(package);
    fs::create_dir_all(package).expect("create package");
    for (name, bytes) in files {
        fs::write(package.join(name), bytes).expect("write source file");
    }
}

fn run_command(
    nlc: &str,
    root: &Path,
    package: &Path,
    frontend: &str,
    command: &str,
    capture_stdout: bool,
    scratch: &Scratch,
) -> Output {
    let mut process = Command::new(nlc);
    process
        .arg(format!("--frontend={frontend}"))
        .arg(command)
        .arg(package)
        .current_dir(root)
        .stderr(Stdio::piped())
        .stdout(if capture_stdout {
            Stdio::piped()
        } else {
            Stdio::null()
        });
    match command {
        "build" => {
            process
                .arg("-o")
                .arg(scratch.0.join(format!("{frontend}-output")));
        }
        "parse" | "lex" | "run" | "test" => {}
        _ => unreachable!(),
    }
    process.output().expect("run nlc command")
}

fn assert_boundary_n(
    nlc: &str,
    root: &Path,
    scratch: &Scratch,
    limit_message: &str,
    commands: &[&str],
    frontends: &[&str],
) {
    let package = scratch.package();
    for frontend in frontends {
        for command in commands {
            let output = run_command(nlc, root, &package, frontend, command, false, scratch);
            if *command == "parse" || *command == "lex" {
                assert!(
                    output.status.success(),
                    "{frontend} {command} rejected N for {limit_message}: {}",
                    String::from_utf8_lossy(&output.stderr)
                );
            } else {
                assert_eq!(
                    output.status.code(),
                    Some(2),
                    "{frontend} {command} did not reach checking at N for {limit_message}: {}",
                    String::from_utf8_lossy(&output.stderr)
                );
                assert!(
                    !String::from_utf8_lossy(&output.stderr).contains(limit_message),
                    "{frontend} {command} rejected N for {limit_message}: {}",
                    String::from_utf8_lossy(&output.stderr)
                );
            }
        }
    }
}

fn assert_boundary_n_plus_one(
    nlc: &str,
    root: &Path,
    scratch: &Scratch,
    limit_message: &str,
    limit_location: &str,
    commands: &[&str],
    frontends: &[&str],
) {
    let package = scratch.package();
    for frontend in frontends {
        for command in commands {
            let output = run_command(nlc, root, &package, frontend, command, true, scratch);
            assert_eq!(
                output.status.code(),
                Some(2),
                "{frontend} {command} accepted N+1 for {limit_message}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            assert!(
                output.stdout.is_empty(),
                "{frontend} {command} wrote partial stdout for {limit_message}"
            );
            let diagnostic = String::from_utf8_lossy(&output.stderr);
            assert!(
                diagnostic.starts_with(limit_location)
                    && diagnostic.contains(&format!("error: {limit_message}")),
                "{frontend} {command} returned the wrong N+1 diagnostic for {limit_message}: {}",
                diagnostic
            );
        }
    }
}

fn simple_main() -> Vec<u8> {
    b"fn main() { missing }\n".to_vec()
}

fn statement_function(name: &str, statements: usize) -> Vec<u8> {
    let mut source = String::with_capacity(22 + statements * 3);
    source.push_str(&format!("fn {name}() {{\n"));
    for _ in 0..statements {
        source.push_str("x;\n");
    }
    source.push_str("unknown\n}\n");
    source.into_bytes()
}

fn token_boundary_source(function: &str, token_count: usize) -> Vec<u8> {
    // Five declaration/header tokens and four trailing tokens surround the
    // semicolons. Semicolons do not create AST nodes.
    let fixed_tokens = 9;
    let semicolons = token_count - fixed_tokens;
    format!("fn {function}() {{{}unknown}}\n", ";".repeat(semicolons)).into_bytes()
}

#[test]
fn input_policy_file_count() {
    if !run_input_policy_once() {
        return;
    }
    let _lock = LARGE_INPUT_LOCK.lock().unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let scratch = Scratch::new();
    let commands = if is_long_tests_mode() {
        get_all_commands()
    } else {
        get_default_commands()
    };
    let frontends = &["rust", "selfhost"];
    let limit_msg = "source file limit of 256 per package exceeded";

    // N: one checked source and 255 empty files
    let mut files = vec![("file-000.nl", simple_main())];
    files.extend((1..256).map(|index| {
        (
            Box::leak(format!("file-{index:03}.nl").into_boxed_str()) as &str,
            Vec::new(),
        )
    }));
    let package = scratch.package();
    write_package(&package, files);
    assert_boundary_n(nlc, root, &scratch, limit_msg, commands, frontends);

    // N+1: add one more file
    fs::write(package.join("file-256.nl"), Vec::new()).expect("write file-256.nl");
    assert_boundary_n_plus_one(
        nlc,
        root,
        &scratch,
        limit_msg,
        "<package>:1:1",
        commands,
        frontends,
    );
}

#[test]
fn input_policy_per_file_bytes() {
    if !run_input_policy_once() {
        return;
    }
    let _lock = LARGE_INPUT_LOCK.lock().unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let scratch = Scratch::new();
    let commands = if is_long_tests_mode() {
        get_all_commands()
    } else {
        get_default_commands()
    };
    let frontends = &["rust", "selfhost"];
    let limit_msg = "source byte limit of 16777216 per file exceeded";

    // N: exact file limit
    let mut exact_file = simple_main();
    exact_file.resize(FILE_LIMIT, b' ');
    let package = scratch.package();
    write_package(&package, vec![("main.nl", exact_file)]);
    assert_boundary_n(nlc, root, &scratch, limit_msg, commands, frontends);

    // N+1: one byte over
    let mut over_file = simple_main();
    over_file.resize(FILE_LIMIT + 1, b' ');
    fs::write(package.join("main.nl"), over_file).expect("write main.nl");
    assert_boundary_n_plus_one(
        nlc,
        root,
        &scratch,
        limit_msg,
        "main.nl:1:1",
        commands,
        frontends,
    );
}

#[test]
fn input_policy_package_bytes() {
    if !run_input_policy_once() {
        return;
    }
    let _lock = LARGE_INPUT_LOCK.lock().unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let scratch = Scratch::new();
    let commands = if is_long_tests_mode() {
        get_all_commands()
    } else {
        get_default_commands()
    };
    let frontends = &["rust", "selfhost"];
    let limit_msg = "source byte limit of 67108864 per package exceeded";

    // N: four files totaling exactly the limit
    let mut package_files = Vec::new();
    let mut main = simple_main();
    main.resize(FILE_LIMIT, b' ');
    package_files.push(("a.nl", main));
    for name in ["b.nl", "c.nl", "d.nl"] {
        package_files.push((name, vec![b' '; FILE_LIMIT]));
    }
    assert_eq!(
        package_files
            .iter()
            .map(|(_, bytes)| bytes.len())
            .sum::<usize>(),
        PACKAGE_LIMIT
    );
    let package = scratch.package();
    write_package(&package, package_files);
    assert_boundary_n(nlc, root, &scratch, limit_msg, commands, frontends);

    // N+1: add one byte via a new file
    fs::write(package.join("e.nl"), b" ").expect("write e.nl");
    assert_boundary_n_plus_one(
        nlc, root, &scratch, limit_msg, "e.nl:1:1", commands, frontends,
    );
}

#[test]
fn input_policy_per_file_tokens() {
    if !run_input_policy_once() {
        return;
    }
    let _lock = LARGE_INPUT_LOCK.lock().unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let scratch = Scratch::new();
    let commands = if is_long_tests_mode() {
        get_all_commands()
    } else {
        get_default_commands()
    };
    let frontends = &["rust", "selfhost"];
    let limit_msg = "token limit of 1000000 per file exceeded";

    // N: exactly one million tokens
    let package = scratch.package();
    let source_n = token_boundary_source("main", FILE_TOKEN_LIMIT);
    write_package(&package, vec![("main.nl", source_n)]);
    assert_boundary_n(nlc, root, &scratch, limit_msg, commands, frontends);

    // N+1: one token over
    let source_n_plus_1 = token_boundary_source("main", FILE_TOKEN_LIMIT + 1);
    fs::write(package.join("main.nl"), source_n_plus_1).expect("write main.nl");
    assert_boundary_n_plus_one(
        nlc,
        root,
        &scratch,
        limit_msg,
        "main.nl:2:1",
        commands,
        frontends,
    );
}

#[test]
fn input_policy_package_tokens() {
    if !run_input_policy_once() {
        return;
    }
    let _lock = LARGE_INPUT_LOCK.lock().unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let scratch = Scratch::new();
    let commands = if is_long_tests_mode() {
        get_all_commands()
    } else {
        get_default_commands()
    };
    let frontends = &["rust", "selfhost"];
    let limit_msg = "token limit of 4000000 per package exceeded";

    // N: four files at one million tokens each
    let mut package_files = Vec::new();
    for (index, name) in ["a.nl", "b.nl", "c.nl", "d.nl"].into_iter().enumerate() {
        let function = if index == 0 {
            "main".to_owned()
        } else {
            format!("helper{index}")
        };
        package_files.push((name, token_boundary_source(&function, FILE_TOKEN_LIMIT)));
    }
    assert_eq!(4 * FILE_TOKEN_LIMIT, PACKAGE_TOKEN_LIMIT);
    let package = scratch.package();
    write_package(&package, package_files);
    assert_boundary_n(nlc, root, &scratch, limit_msg, commands, frontends);

    // N+1: add empty file (contributes EOF token)
    fs::write(package.join("e.nl"), Vec::new()).expect("write e.nl");
    assert_boundary_n_plus_one(
        nlc, root, &scratch, limit_msg, "e.nl:1:1", commands, frontends,
    );
}

#[test]
fn input_policy_nodes() {
    if !run_input_policy_once() {
        return;
    }
    let _lock = LARGE_INPUT_LOCK.lock().unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let scratch = Scratch::new();
    let commands = if is_long_tests_mode() {
        get_all_commands()
    } else {
        get_default_commands()
    };
    let frontends = &["rust", "selfhost"];
    let limit_msg = "node limit of 2000000 per package exceeded";

    // N: three files with statements that hit the node limit
    let node_files = vec![
        ("a.nl", statement_function("main", 333_332)),
        ("b.nl", statement_function("helper1", 333_331)),
        ("c.nl", statement_function("helper2", 333_331)),
    ];
    assert_eq!(2 * (333_332 + 333_331 + 333_331) + 4 * 3, NODE_LIMIT);
    let package = scratch.package();
    write_package(&package, node_files);
    assert_boundary_n(nlc, root, &scratch, limit_msg, commands, frontends);

    // N+1: add empty file
    fs::write(package.join("d.nl"), Vec::new()).expect("write d.nl");
    assert_boundary_n_plus_one(
        nlc, root, &scratch, limit_msg, "d.nl:1:1", commands, frontends,
    );
}

#[test]
fn input_policy_work() {
    if !run_input_policy_once() {
        return;
    }
    let _lock = LARGE_INPUT_LOCK.lock().unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let scratch = Scratch::new();
    let commands = if is_long_tests_mode() {
        get_all_commands()
    } else {
        get_default_commands()
    };
    let frontends = &["rust", "selfhost"];
    let limit_msg = "parse work limit of 72000000 units per package exceeded";

    // N: Construct a valid package hitting the work bound exactly.
    // Work is bytes + tokens + nodes + edges.
    let per_function = [283_334, 283_333, 283_333];
    let work_main = statement_function("main", per_function[0]);
    let work_second = statement_function("helper1", per_function[1]);
    let work_third = statement_function("helper2", per_function[2]);
    let total_statements = per_function.iter().sum::<usize>();
    let file_count = 7usize;
    let token_count = 2 * total_statements + 11 * 3 + 4;
    let node_count = 2 * total_statements + 4 * 3 + 4;
    let edge_count = node_count - file_count;
    let filler_bytes = WORK_LIMIT
        - token_count
        - node_count
        - edge_count
        - work_main.len()
        - work_second.len()
        - work_third.len();
    assert!(filler_bytes < 4 * FILE_LIMIT);
    assert!(filler_bytes > 0);
    let mut work_files = vec![
        ("a.nl", work_main),
        ("b.nl", work_second),
        ("c.nl", work_third),
    ];
    let each_filler = filler_bytes / 4;
    let remainder = filler_bytes % 4;
    for index in 0..4 {
        let size = each_filler + usize::from(index < remainder);
        assert!(size <= FILE_LIMIT);
        let name = Box::leak(format!("pad-{index}.nl").into_boxed_str()) as &str;
        work_files.push((name, vec![b' '; size]));
    }
    assert_eq!(
        work_files
            .iter()
            .map(|(_, bytes)| bytes.len())
            .sum::<usize>()
            + token_count
            + node_count
            + edge_count,
        WORK_LIMIT
    );
    let package = scratch.package();
    write_package(&package, work_files);
    assert_boundary_n(nlc, root, &scratch, limit_msg, commands, frontends);

    // N+1: add one byte to the last file
    let pad_3_path = package.join("pad-3.nl");
    let mut content = fs::read(&pad_3_path).expect("read pad-3.nl");
    content.push(b' ');
    fs::write(&pad_3_path, content).expect("write pad-3.nl");
    assert_boundary_n_plus_one(
        nlc,
        root,
        &scratch,
        limit_msg,
        "pad-3.nl:1:1",
        commands,
        frontends,
    );
}

#[test]
fn input_policy_nesting() {
    if !run_input_policy_once() {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let scratch = Scratch::new();
    let commands = if is_long_tests_mode() {
        get_all_commands()
    } else {
        get_default_commands()
    };
    let frontends = &["rust", "selfhost"];
    let limit_msg = "expression nesting limit of 1000 exceeded";

    // N: nesting at exactly 1000
    let expression = format!("{}1{}", "(".repeat(1_000), ")".repeat(1_000));
    let source = format!("fn main() {{ print({expression}); missing }}\n");
    let package = scratch.package();
    write_package(&package, vec![("main.nl", source.into_bytes())]);
    assert_boundary_n(nlc, root, &scratch, limit_msg, commands, frontends);

    // N+1: nesting at 1001
    let expression = format!("{}1{}", "(".repeat(1_001), ")".repeat(1_001));
    let source = format!("fn main() {{ print({expression}); missing }}\n");
    fs::write(package.join("main.nl"), source).expect("write main.nl");
    assert_boundary_n_plus_one(
        nlc,
        root,
        &scratch,
        limit_msg,
        "main.nl:1:",
        commands,
        frontends,
    );
}

#[test]
fn input_policy_invalid_utf8() {
    if !run_input_policy_once() {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let scratch = Scratch::new();
    let all_commands = get_all_commands();
    let frontends = &["rust", "selfhost"];
    let package = scratch.package();

    write_package(&package, vec![("main.nl", b"fn main() {}\n\xff".to_vec())]);
    let expected = b"main.nl:2:1: error: source is not valid UTF-8; save the file as UTF-8\n";

    for frontend in frontends {
        for command in all_commands {
            let output = run_command(nlc, root, &package, frontend, command, true, &scratch);
            assert_eq!(output.status.code(), Some(2), "{frontend} {command}");
            assert!(output.stdout.is_empty(), "{frontend} {command}");
            assert_eq!(output.stderr, expected, "{frontend} {command}");
        }
    }
}
