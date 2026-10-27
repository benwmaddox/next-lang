use std::fs;
use std::path::Path;
use std::process::Command;

// Selfhost-specific parity and policy checks belong to the selfhost suite.
fn run_frontend_independent_check() -> bool {
    std::env::var("NLC_FRONTEND").as_deref() == Ok("selfhost")
}

#[test]
fn selfhosted_lexer_and_parser_match_the_rust_reference() {
    if !run_frontend_independent_check() {
        return;
    }
    let stage0_parity = std::env::var("NLC_STAGE0_PARITY").as_deref() == Ok("1");
    if stage0_parity {
        assert_eq!(
            std::env::var("NLC_LONG_TESTS").as_deref(),
            Ok("1"),
            "NLC_STAGE0_PARITY=1 requires NLC_LONG_TESTS=1"
        );
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let build = Command::new("python3")
        .arg(root.join("scripts/build-selfhost-cached.py"))
        .arg("--reference")
        .arg(nlc)
        .current_dir(root)
        .output()
        .expect("build or reuse the stage-zero selfhost compiler");
    assert!(
        build.status.success(),
        "selfhost build failed:\n{}",
        String::from_utf8_lossy(&build.stderr)
    );
    let selfhost = String::from_utf8(build.stdout)
        .expect("cached selfhost compiler path is UTF-8")
        .trim()
        .to_owned();

    if stage0_parity {
        for (mode, label) in [("--tokens", "lexer"), ("--parse", "parser")] {
            let comparison = Command::new(root.join("scripts/compare-selfhost.sh"))
                .arg(mode)
                .arg("--reference")
                .arg(nlc)
                .arg("--selfhost")
                .arg(&selfhost)
                .current_dir(root)
                .output()
                .unwrap_or_else(|error| {
                    panic!("run the selfhost {label} comparison harness: {error}")
                });
            assert!(
                comparison.status.success(),
                "selfhost {label} comparison failed (status {:?}):\n{}\n{}",
                comparison.status.code(),
                String::from_utf8_lossy(&comparison.stdout),
                String::from_utf8_lossy(&comparison.stderr)
            );
        }
    }

    let mut command = Command::new(root.join("scripts/compare-selfhost.sh"));
    command.arg("--build").arg("--reference").arg(nlc);
    if stage0_parity {
        command.arg("--no-reference-cache");
    }
    let comparison = command
        .current_dir(root)
        .output()
        .expect("run the selfhost build comparison harness");
    assert!(
        comparison.status.success(),
        "selfhost build comparison failed (status {:?}):\n{}\n{}",
        comparison.status.code(),
        String::from_utf8_lossy(&comparison.stdout),
        String::from_utf8_lossy(&comparison.stderr)
    );
}

#[test]
fn concurrent_cold_cache_builds_publish_reusable_artifacts() {
    if !run_frontend_independent_check() {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let temp = std::env::temp_dir().join(format!(
        "next-lang-selfhost-cache-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
    ));
    let target = temp.join("target");
    fs::create_dir_all(&temp).expect("create isolated cache test directory");
    let exe = if cfg!(windows) {
        "selfhost.exe"
    } else {
        "selfhost"
    };
    let run = || {
        let mut command = Command::new(nlc);
        command
            .args([
                "--frontend=selfhost",
                "parse",
                "tests/run/arithmetic",
                "--tree",
            ])
            .current_dir(root)
            .env("CARGO_TARGET_DIR", &target)
            .env("NLC_STACK_MODE", "offset")
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());
        command
    };

    let first = run().spawn().expect("start first cold-cache frontend");
    let second = run().spawn().expect("start second cold-cache frontend");
    let first = first.wait_with_output().expect("wait for first frontend");
    let second = second.wait_with_output().expect("wait for second frontend");
    assert!(
        first.status.success(),
        "first cold build failed: {}",
        String::from_utf8_lossy(&first.stderr)
    );
    assert!(
        second.status.success(),
        "second cold build failed: {}",
        String::from_utf8_lossy(&second.stderr)
    );
    assert_eq!(first.stdout, second.stdout);
    assert_eq!(first.stderr, second.stderr);

    let cache = target.join("next-lang-selfhost");
    let artifact = fs::read_dir(&cache)
        .expect("read selfhost cache")
        .flatten()
        .map(|entry| entry.path())
        .find(|path| path.is_dir())
        .expect("cold build published an artifact directory");
    let binary = artifact.join(exe);
    fs::write(&binary, b"corrupt").expect("corrupt cached executable");
    let repaired = run().output().expect("run with a corrupt cache artifact");
    assert!(
        repaired.status.success(),
        "corrupt artifact was not rebuilt: {}",
        String::from_utf8_lossy(&repaired.stderr)
    );
    fs::remove_file(&binary).expect("remove cached executable");
    let rebuilt = run().output().expect("run with a missing cache artifact");
    assert!(
        rebuilt.status.success(),
        "missing artifact was not rebuilt: {}",
        String::from_utf8_lossy(&rebuilt.stderr)
    );
    let _ = fs::remove_dir_all(&temp);
}

#[cfg(unix)]
#[test]
fn rust_and_selfhost_use_the_same_rooted_source_symlink_policy() {
    if !run_frontend_independent_check() {
        return;
    }
    use std::os::unix::fs::symlink;

    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let temp = std::env::temp_dir().join(format!(
        "next-lang-selfhost-symlink-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
    ));
    let package = temp.join("package");
    fs::create_dir_all(&package).expect("create symlink fixture package");
    fs::write(package.join("main.nl"), "fn main() {}\n").expect("write main source");
    fs::write(package.join("helper.nl"), "fn helper() {}\n").expect("write helper source");
    let outside = temp.join("outside.nl");
    fs::write(&outside, "fn outside() {}\n").expect("write outside source");
    let outside2 = std::env::temp_dir().join(format!(
        "next-lang-selfhost-outside-{}-{}.nl",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
    ));
    fs::write(&outside2, "fn outside2() {}\n").expect("write out-of-root source");
    let outside2_name = outside2.file_name().unwrap().to_string_lossy();
    symlink("helper.nl", package.join("linked.nl")).expect("create in-root source symlink");
    symlink("../outside.nl", package.join("escape.nl"))
        .expect("create source symlink within the rooted parent");
    symlink(
        Path::new("../..").join(outside2_name.as_ref()),
        package.join("beyond.nl"),
    )
    .expect("create source symlink escaping the rooted parent");

    let parse = |frontend: &str| {
        Command::new(env!("CARGO_BIN_EXE_nlc"))
            .args([format!("--frontend={frontend}"), "parse".to_owned()])
            .arg(&package)
            .args(["--tokens", "--tree"])
            .current_dir(root)
            .output()
            .expect("run frontend against symlink fixture")
    };
    let rust = parse("rust");
    let selfhost = parse("selfhost");
    assert!(
        rust.status.success(),
        "Rust parser failed: {}",
        String::from_utf8_lossy(&rust.stderr)
    );
    assert!(
        selfhost.status.success(),
        "selfhost parser failed: {}",
        String::from_utf8_lossy(&selfhost.stderr)
    );
    assert_eq!(selfhost.stdout, rust.stdout);
    assert_eq!(selfhost.stderr, rust.stderr);
    assert!(String::from_utf8_lossy(&rust.stdout).contains("escape.nl"));
    assert!(!String::from_utf8_lossy(&rust.stdout).contains("beyond.nl"));
    assert!(String::from_utf8_lossy(&rust.stdout).contains("linked.nl"));
    let _ = fs::remove_dir_all(&temp);
    let _ = fs::remove_file(outside2);
}

#[test]
fn frontends_report_invalid_utf8_as_the_same_syntax_diagnostic() {
    if !run_frontend_independent_check() {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let temp = std::env::temp_dir().join(format!(
        "next-lang-selfhost-invalid-utf8-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
    ));
    let package = temp.join("package");
    fs::create_dir_all(&package).expect("create invalid UTF-8 package");
    fs::write(package.join("main.nl"), b"fn main() {}\n\xff").expect("write invalid UTF-8 source");

    let compile = |frontend: &str| {
        Command::new(nlc)
            .arg(format!("--frontend={frontend}"))
            .arg("build")
            .arg(&package)
            .arg("-o")
            .arg(temp.join(format!("{frontend}-output")))
            .current_dir(root)
            .output()
            .expect("run compile with invalid UTF-8")
    };
    let rust = compile("rust");
    let selfhost = compile("selfhost");
    assert_eq!(rust.status.code(), Some(2));
    assert_eq!(selfhost.status.code(), Some(2));
    assert_eq!(rust.stdout, selfhost.stdout);
    assert_eq!(rust.stderr, selfhost.stderr);
    assert_eq!(
        rust.stderr,
        b"main.nl:2:1: error: source is not valid UTF-8; save the file as UTF-8\n"
    );

    let _ = fs::remove_dir_all(&temp);
}

#[test]
fn compile_frontends_reject_over_parse_source_limits() {
    if !run_frontend_independent_check() {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let temp = std::env::temp_dir().join(format!(
        "next-lang-selfhost-compile-limits-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
    ));
    let package = temp.join("package");
    fs::create_dir_all(&package).expect("create compile-limit package");
    let file_limit = 16 * 1024 * 1024;
    let package_limit = 64 * 1024 * 1024;
    let main = b"fn main() {}\n";
    fs::write(
        package.join("main.nl"),
        [vec![b' '; file_limit + 1 - main.len()], main.to_vec()].concat(),
    )
    .expect("write file-limit boundary source");

    let build = |frontend: &str, name: &str| {
        Command::new(nlc)
            .arg(format!("--frontend={frontend}"))
            .arg("build")
            .arg(&package)
            .arg("-o")
            .arg(temp.join(format!("{frontend}-{name}")))
            .current_dir(root)
            .output()
            .expect("run compile-policy boundary build")
    };
    let rust_file = build("rust", "file");
    let selfhost_file = build("selfhost", "file");
    assert_eq!(rust_file.status.code(), Some(2));
    assert_eq!(selfhost_file.status.code(), Some(2));
    assert_eq!(selfhost_file.stdout, rust_file.stdout);
    assert_eq!(selfhost_file.stderr, rust_file.stderr);
    assert!(
        String::from_utf8_lossy(&rust_file.stderr)
            .contains("source byte limit of 16777216 per file exceeded")
    );

    fs::remove_file(package.join("main.nl")).expect("remove per-file boundary source");
    let file_bytes = vec![b' '; file_limit];
    let padded_main = [vec![b' '; file_limit - main.len()], main.to_vec()].concat();
    fs::write(package.join("a.nl"), padded_main).expect("write package-limit main source");
    for name in ["b.nl", "c.nl", "d.nl"] {
        fs::write(package.join(name), &file_bytes).expect("write package-limit source");
    }
    fs::write(package.join("e.nl"), b" ").expect("write package-limit final byte");
    let total = fs::read_dir(&package)
        .expect("list package-limit sources")
        .flatten()
        .map(|entry| entry.metadata().unwrap().len() as usize)
        .sum::<usize>();
    assert_eq!(total, package_limit + 1);

    let rust_package = build("rust", "package");
    let selfhost_package = build("selfhost", "package");
    assert_eq!(rust_package.status.code(), Some(2));
    assert_eq!(selfhost_package.status.code(), Some(2));
    assert_eq!(selfhost_package.stdout, rust_package.stdout);
    assert_eq!(selfhost_package.stderr, rust_package.stderr);
    assert!(
        String::from_utf8_lossy(&rust_package.stderr)
            .contains("source byte limit of 67108864 per package exceeded")
    );

    let _ = fs::remove_dir_all(&temp);
}
