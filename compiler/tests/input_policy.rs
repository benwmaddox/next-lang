use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

const FILE_LIMIT: usize = 16 * 1024 * 1024;
const PACKAGE_LIMIT: usize = 64 * 1024 * 1024;
const FILE_TOKEN_LIMIT: usize = 1_000_000;
const PACKAGE_TOKEN_LIMIT: usize = 4_000_000;
const NODE_LIMIT: usize = 2_000_000;
const WORK_LIMIT: usize = 72_000_000;

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

fn assert_boundary(
    nlc: &str,
    root: &Path,
    scratch: &Scratch,
    files: Vec<(&str, Vec<u8>)>,
    limit_message: &str,
    limit_location: Option<&str>,
) {
    let package = scratch.package();
    write_package(&package, files);
    for frontend in ["rust", "selfhost"] {
        for command in ["run", "build", "test", "parse", "lex"] {
            let output = run_command(
                nlc,
                root,
                &package,
                frontend,
                command,
                limit_location.is_some(),
                scratch,
            );
            if let Some(location) = limit_location {
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
                    diagnostic.starts_with(location)
                        && diagnostic.contains(&format!("error: {limit_message}")),
                    "{frontend} {command} returned the wrong N+1 diagnostic for {limit_message}: {}",
                    diagnostic
                );
            } else if command == "parse" || command == "lex" {
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

fn invalid_utf8_commands(nlc: &str, root: &Path, scratch: &Scratch) {
    let package = scratch.package();
    write_package(&package, vec![("main.nl", b"fn main() {}\n\xff".to_vec())]);
    let expected = b"main.nl:2:1: error: source is not valid UTF-8; save the file as UTF-8\n";
    for frontend in ["rust", "selfhost"] {
        for command in ["run", "build", "test", "parse", "lex"] {
            let output = run_command(nlc, root, &package, frontend, command, true, scratch);
            assert_eq!(output.status.code(), Some(2), "{frontend} {command}");
            assert!(output.stdout.is_empty(), "{frontend} {command}");
            assert_eq!(output.stderr, expected, "{frontend} {command}");
        }
    }
}

#[test]
fn every_command_and_frontend_uses_the_same_input_policy() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let scratch = Scratch::new();
    // File count: the N package has one checked source and 255 empty files.
    let mut files = vec![("file-000.nl", simple_main())];
    files.extend((1..256).map(|index| {
        (
            Box::leak(format!("file-{index:03}.nl").into_boxed_str()) as &str,
            Vec::new(),
        )
    }));
    assert_boundary(
        nlc,
        root,
        &scratch,
        files,
        "source file limit of 256 per package exceeded",
        None,
    );
    let mut files = vec![("file-000.nl", simple_main())];
    files.extend((1..257).map(|index| {
        (
            Box::leak(format!("file-{index:03}.nl").into_boxed_str()) as &str,
            Vec::new(),
        )
    }));
    assert_boundary(
        nlc,
        root,
        &scratch,
        files,
        "source file limit of 256 per package exceeded",
        Some("<package>:1:1"),
    );

    // Per-file and cumulative package source bytes.
    let mut exact_file = simple_main();
    exact_file.resize(FILE_LIMIT, b' ');
    assert_boundary(
        nlc,
        root,
        &scratch,
        vec![("main.nl", exact_file)],
        "source byte limit of 16777216 per file exceeded",
        None,
    );
    let mut over_file = simple_main();
    over_file.resize(FILE_LIMIT + 1, b' ');
    assert_boundary(
        nlc,
        root,
        &scratch,
        vec![("main.nl", over_file)],
        "source byte limit of 16777216 per file exceeded",
        Some("main.nl:1:1"),
    );
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
    assert_boundary(
        nlc,
        root,
        &scratch,
        package_files,
        "source byte limit of 67108864 per package exceeded",
        None,
    );
    let mut package_files = Vec::new();
    let mut main = simple_main();
    main.resize(FILE_LIMIT, b' ');
    package_files.push(("a.nl", main));
    for name in ["b.nl", "c.nl", "d.nl"] {
        package_files.push((name, vec![b' '; FILE_LIMIT]));
    }
    package_files.push(("e.nl", vec![b' ']));
    assert_boundary(
        nlc,
        root,
        &scratch,
        package_files,
        "source byte limit of 67108864 per package exceeded",
        Some("e.nl:1:1"),
    );

    // One million tokens per file, then one token over.
    assert_boundary(
        nlc,
        root,
        &scratch,
        vec![("main.nl", token_boundary_source("main", FILE_TOKEN_LIMIT))],
        "token limit of 1000000 per file exceeded",
        None,
    );
    assert_boundary(
        nlc,
        root,
        &scratch,
        vec![(
            "main.nl",
            token_boundary_source("main", FILE_TOKEN_LIMIT + 1),
        )],
        "token limit of 1000000 per file exceeded",
        Some("main.nl:2:1"),
    );

    // Four files at one million tokens each reach the package limit; an empty
    // fifth file contributes the first excess token (its EOF).
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
    assert_boundary(
        nlc,
        root,
        &scratch,
        package_files,
        "token limit of 4000000 per package exceeded",
        None,
    );
    let mut package_files = Vec::new();
    for (index, name) in ["a.nl", "b.nl", "c.nl", "d.nl"].into_iter().enumerate() {
        let function = if index == 0 {
            "main".to_owned()
        } else {
            format!("helper{index}")
        };
        package_files.push((name, token_boundary_source(&function, FILE_TOKEN_LIMIT)));
    }
    package_files.push(("e.nl", Vec::new()));
    assert_boundary(
        nlc,
        root,
        &scratch,
        package_files,
        "token limit of 4000000 per package exceeded",
        Some("e.nl:1:1"),
    );

    // The node limit crosses between file totals, while no earlier file is
    // itself over the cap. Empty source files adjust the Program-node parity.
    let node_files = vec![
        ("a.nl", statement_function("main", 333_332)),
        ("b.nl", statement_function("helper1", 333_331)),
        ("c.nl", statement_function("helper2", 333_331)),
    ];
    assert_eq!(2 * (333_332 + 333_331 + 333_331) + 4 * 3, NODE_LIMIT);
    assert_boundary(
        nlc,
        root,
        &scratch,
        node_files.clone(),
        "node limit of 2000000 per package exceeded",
        None,
    );
    let mut node_over_files = node_files;
    node_over_files.push(("d.nl", Vec::new()));
    assert_boundary(
        nlc,
        root,
        &scratch,
        node_over_files,
        "node limit of 2000000 per package exceeded",
        Some("d.nl:1:1"),
    );

    // Construct a valid package whose final file lands exactly on, and then
    // one unit above, the parse work bound. Work is bytes + tokens + nodes + edges.
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
    assert_boundary(
        nlc,
        root,
        &scratch,
        work_files.clone(),
        "parse work limit of 72000000 units per package exceeded",
        None,
    );
    let mut over_work_files = work_files;
    over_work_files.last_mut().unwrap().1.push(b' ');
    assert_boundary(
        nlc,
        root,
        &scratch,
        over_work_files,
        "parse work limit of 72000000 units per package exceeded",
        Some("pad-3.nl:1:1"),
    );

    // Grouped-expression nesting is allowed at 1,000 and diagnosed at 1,001.
    for depth in [1_000, 1_001] {
        let expression = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        let source = format!("fn main() {{ print({expression}); missing }}\n");
        let error = (depth == 1_001).then_some("main.nl:1:");
        assert_boundary(
            nlc,
            root,
            &scratch,
            vec![("main.nl", source.into_bytes())],
            "expression nesting limit of 1000 exceeded",
            error,
        );
    }

    invalid_utf8_commands(nlc, root, &scratch);
}
