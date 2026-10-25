use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use next_lang::{PackageError, parse_package};

fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root")
        .to_path_buf()
}

fn read(path: &Path) -> String {
    fs::read_to_string(path)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", path.display()))
}

fn compare_error(package: &Path, dump_dir: &Path, name: &str) {
    let error = parse_package(package).expect_err("fixture should contain a syntax error");
    let actual = match error {
        PackageError::Compile(error) => format!("{error}\n"),
        PackageError::Tool(message) => panic!("unexpected tool error for {name}: {message}"),
    };
    assert_eq!(
        actual,
        read(&dump_dir.join(format!("{name}.stderr"))),
        "syntax error changed for {name}"
    );
    assert_eq!(read(&dump_dir.join(format!("{name}.exit"))).trim(), "2");
    assert!(!dump_dir.join(format!("{name}.dump")).exists());
    assert!(!dump_dir.join(format!("{name}.tokens")).exists());
    assert!(!dump_dir.join(format!("{name}.tree")).exists());
}

fn compare_success(package: &Path, dump_dir: &Path, name: &str) {
    let dump = parse_package(package).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert_tree_structure(&dump, name);
    let snapshot = read(&dump_dir.join(format!("{name}.dump")));
    let (tokens, tree) = split_snapshot(&snapshot, name);
    assert_eq!(dump.tokens, tokens, "token dump changed for {name}");
    assert_eq!(dump.tree, tree, "tree dump changed for {name}");
    assert!(!dump_dir.join(format!("{name}.stderr")).exists());
    assert!(!dump_dir.join(format!("{name}.exit")).exists());
    assert!(!dump_dir.join(format!("{name}.tokens")).exists());
    assert!(!dump_dir.join(format!("{name}.tree")).exists());
}

fn split_snapshot(snapshot: &str, name: &str) -> (String, String) {
    let combined = snapshot
        .strip_prefix("== tokens ==\n")
        .unwrap_or_else(|| panic!("combined snapshot {name} has no token header"));
    let (tokens, tree) = combined
        .split_once("== tree ==\n")
        .unwrap_or_else(|| panic!("combined snapshot {name} has no tree header"));
    (tokens.to_owned(), tree.to_owned())
}

fn live_only(category: &str, name: &str) -> bool {
    (category == "run"
        && matches!(
            name,
            "t19_expression_plus_1000"
                | "t19_expression_and_1000"
                | "t19_expression_call_1000"
                | "t19_expression_if_300"
                | "t19_expression_paren_1000"
                | "t12_sort_specialization_limit"
        ))
        || (category == "cases" && name == "long_line")
}

fn compare_live_only(package: &Path, dump_dir: &Path, name: &str) {
    for extension in ["dump", "tokens", "tree", "stderr", "exit"] {
        assert!(
            !dump_dir.join(format!("{name}.{extension}")).exists(),
            "live-only fixture {name} must not store a {extension} snapshot"
        );
    }
    let first = parse_package(package).unwrap_or_else(|error| panic!("{name}: {error}"));
    let second = parse_package(package).unwrap_or_else(|error| panic!("{name}: {error}"));
    assert_eq!(
        first, second,
        "live output changed between parses for {name}"
    );
    assert_tree_structure(&first, name);
}

#[derive(Default)]
struct TokenOffsets {
    starts: HashSet<usize>,
    ends: HashSet<usize>,
    eof: Option<usize>,
}

#[derive(Clone, Copy)]
struct TreeFrame {
    start: usize,
    end: usize,
    last_child_end: usize,
}

fn assert_tree_structure(dump: &next_lang::ParseDump, name: &str) {
    let mut offsets = HashMap::<String, TokenOffsets>::new();
    let mut token_file = String::new();
    for line in dump.tokens.lines() {
        if let Some(file) = line.strip_prefix("file ") {
            token_file = file.trim_matches('"').to_owned();
            offsets.entry(token_file.clone()).or_default();
            continue;
        }
        let mut fields = line.split_whitespace();
        let Some(kind) = fields.next() else {
            continue;
        };
        let start = fields
            .next()
            .unwrap_or_else(|| panic!("malformed token line in {name}: {line}"))
            .parse::<usize>()
            .unwrap_or_else(|error| panic!("invalid token start in {name}: {error}"));
        let length = fields
            .next()
            .unwrap_or_else(|| panic!("malformed token line in {name}: {line}"))
            .parse::<usize>()
            .unwrap_or_else(|error| panic!("invalid token length in {name}: {error}"));
        let file_offsets = offsets.get_mut(&token_file).unwrap();
        file_offsets.starts.insert(start);
        file_offsets.ends.insert(start + length);
        // The parser can split `>>` and `>>=` into individual type closers.
        if matches!(kind, "Shr" | "ShrEq") {
            for offset in start + 1..start + length {
                file_offsets.starts.insert(offset);
                file_offsets.ends.insert(offset);
            }
        }
        if kind == "Eof" {
            file_offsets.eof = Some(start);
        }
    }

    let mut tree_file = String::new();
    let mut stack = Vec::<TreeFrame>::new();
    let mut roots = HashSet::new();
    for line in dump.tree.lines() {
        if let Some(file) = line.strip_prefix("file ") {
            tree_file = file.trim_matches('"').to_owned();
            stack.clear();
            continue;
        }
        if line.trim().is_empty() {
            continue;
        }
        let indentation = line.len() - line.trim_start_matches(' ').len();
        assert_eq!(indentation % 2, 0, "odd tree indentation in {name}: {line}");
        let depth = indentation / 2;
        let mut fields = line[indentation..].split_whitespace();
        let kind = fields
            .next()
            .unwrap_or_else(|| panic!("missing node kind in {name}: {line}"));
        let range = fields
            .next()
            .unwrap_or_else(|| panic!("missing node span in {name}: {line}"));
        let (start, end) = range
            .split_once("..")
            .unwrap_or_else(|| panic!("invalid node span in {name}: {line}"));
        let start = start
            .parse::<usize>()
            .unwrap_or_else(|error| panic!("invalid node start in {name}: {error}"));
        let end = end
            .parse::<usize>()
            .unwrap_or_else(|error| panic!("invalid node end in {name}: {error}"));
        assert!(start <= end, "reversed node span in {name}: {line}");
        if start == end && kind != "Program" {
            assert!(
                kind == "Call" && line.contains("name=\"default\""),
                "unexpected zero-width syntax node in {name}: {line}"
            );
        }

        let file_offsets = offsets
            .get(&tree_file)
            .unwrap_or_else(|| panic!("tree file {tree_file} has no token dump in {name}"));
        let synthetic_default = start == end && kind == "Call";
        if kind != "Program" && !synthetic_default {
            assert!(
                file_offsets.starts.contains(&start),
                "{kind} does not start at its first token in {name}: {line}"
            );
        }
        if !synthetic_default {
            assert!(
                file_offsets.ends.contains(&end),
                "{kind} does not end at its last token in {name}: {line}"
            );
        }

        while stack.len() > depth {
            stack.pop();
        }
        if depth == 0 {
            assert_eq!(kind, "Program", "top-level node is not Program in {name}");
            assert!(
                roots.insert(tree_file.clone()),
                "duplicate Program in {name}"
            );
            assert_eq!(start, 0, "Program must start at byte zero in {name}");
            assert_eq!(
                Some(end),
                file_offsets.eof,
                "Program must include the whole source file in {name}"
            );
        } else {
            assert_eq!(
                stack.len(),
                depth,
                "tree node skipped a parent depth in {name}: {line}"
            );
            let parent = stack.last_mut().expect("child has a parent");
            assert!(
                parent.start <= start && end <= parent.end,
                "child span escapes its parent in {name}: {line}"
            );
            assert!(
                start >= parent.last_child_end,
                "siblings overlap or are out of source order in {name}: {line}"
            );
            parent.last_child_end = end;
        }
        stack.push(TreeFrame {
            start,
            end,
            last_child_end: start,
        });
    }
    assert_eq!(
        roots.len(),
        offsets.len(),
        "not every token dump file has a Program node in {name}"
    );
}

#[test]
fn snapshots_cover_every_run_and_test_package() {
    let root = workspace_root();
    for category in ["run", "test"] {
        let fixture_root = root.join("tests").join(category);
        let dump_dir = root.join("tests/parse/dumps").join(category);
        let mut packages = fs::read_dir(&fixture_root)
            .unwrap_or_else(|error| panic!("cannot read {}: {error}", fixture_root.display()))
            .map(|entry| entry.unwrap().path())
            .filter(|path| path.is_dir())
            .collect::<Vec<_>>();
        packages.sort();
        assert!(
            !packages.is_empty(),
            "{} has no fixture packages",
            fixture_root.display()
        );
        for package in packages {
            let name = package.file_name().unwrap().to_string_lossy().into_owned();
            if live_only(category, &name) {
                compare_live_only(&package, &dump_dir, &name);
            } else if dump_dir.join(format!("{name}.stderr")).exists() {
                compare_error(&package, &dump_dir, &name);
            } else {
                compare_success(&package, &dump_dir, &name);
            }
        }
    }
}

#[test]
fn syntax_and_boundary_cases_have_frozen_dumps() {
    let root = workspace_root();
    let cases = root.join("tests/parse/cases");
    let dump_dir = root.join("tests/parse/dumps/cases");
    let mut packages = fs::read_dir(&cases)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", cases.display()))
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.is_dir())
        .collect::<Vec<_>>();
    packages.sort();
    for package in packages {
        let name = package.file_name().unwrap().to_string_lossy().into_owned();
        if live_only("cases", &name) {
            compare_live_only(&package, &dump_dir, &name);
        } else if dump_dir.join(format!("{name}.stderr")).exists() {
            compare_error(&package, &dump_dir, &name);
        } else {
            compare_success(&package, &dump_dir, &name);
        }
    }
}

#[test]
fn parse_cli_dumps_without_checking_and_is_repeatable() {
    let root = workspace_root();
    let package = root.join("tests/run/unknown_name");
    let first = parse_package(&package).expect("type errors must not prevent parsing");
    let second = parse_package(&package).expect("repeat parse should succeed");
    assert_eq!(first, second);

    let cli = env!("CARGO_BIN_EXE_nlc");
    let output = Command::new(cli)
        .arg("parse")
        .arg(&package)
        .arg("--tree")
        .output()
        .expect("could not launch nlc parse");
    assert!(
        output.status.success(),
        "nlc parse checked the package: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(output.stdout, first.tree.as_bytes());
    assert!(output.stderr.is_empty());

    let token_output = Command::new(cli)
        .arg("parse")
        .arg(&package)
        .arg("--tokens")
        .output()
        .expect("could not launch nlc parse --tokens");
    assert!(token_output.status.success());
    assert_eq!(token_output.stdout, first.tokens.as_bytes());
    assert!(token_output.stderr.is_empty());

    let combined = Command::new(cli)
        .arg("parse")
        .arg(&package)
        .arg("--tokens")
        .arg("--tree")
        .output()
        .expect("could not launch nlc parse with both dump options");
    assert!(combined.status.success());
    assert_eq!(
        combined.stdout,
        format!("== tokens ==\n{}== tree ==\n{}", first.tokens, first.tree).as_bytes()
    );
    assert!(combined.stderr.is_empty());

    let no_dump = Command::new(cli)
        .arg("parse")
        .arg(&package)
        .output()
        .expect("could not launch nlc parse");
    assert!(no_dump.status.success());
    assert!(no_dump.stdout.is_empty());
    assert!(no_dump.stderr.is_empty());

    let bad_case = root.join("tests/parse/cases/bad_escape");
    let error = Command::new(cli)
        .arg("parse")
        .arg(&bad_case)
        .output()
        .expect("could not launch nlc parse on malformed input");
    assert_eq!(error.status.code(), Some(2));
    assert!(error.stdout.is_empty());
    assert_eq!(
        error.stderr,
        read(&root.join("tests/parse/dumps/cases/bad_escape.stderr")).as_bytes()
    );
}
