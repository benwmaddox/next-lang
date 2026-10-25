use std::fs;
use std::path::Path;
use std::process::Command;

#[test]
fn every_run_fixture_matches_its_expected_result() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let fixture_root = root.join("tests/run");
    let mut fixtures = fs::read_dir(&fixture_root)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", fixture_root.display()))
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.is_dir())
        .collect::<Vec<_>>();
    fixtures.sort();
    assert!(
        !fixtures.is_empty(),
        "tests/run must contain end-to-end programs"
    );

    let mut failures = Vec::new();
    for fixture in fixtures {
        let name = fixture.file_name().unwrap().to_string_lossy();
        let mut command = Command::new(env!("CARGO_BIN_EXE_nlc"));
        command.arg("run").arg(&fixture);
        if name == "t20_probe" {
            command.current_dir(&fixture);
        }
        let output = command
            .output()
            .unwrap_or_else(|e| panic!("{name}: could not launch nlc: {e}"));
        if name == "t20_probe" {
            let _ = fs::remove_file(fixture.join("a.txt"));
        }
        let expected_stdout = fs::read_to_string(fixture.join("expected.stdout"))
            .unwrap_or_else(|e| panic!("{name}: cannot read expected.stdout: {e}"));
        let expected_stderr = fs::read_to_string(fixture.join("expected.stderr"))
            .unwrap_or_else(|e| panic!("{name}: cannot read expected.stderr: {e}"));
        let expected_exit: i32 = fs::read_to_string(fixture.join("expected.exit"))
            .unwrap_or_else(|e| panic!("{name}: cannot read expected.exit: {e}"))
            .trim()
            .parse()
            .unwrap_or_else(|e| panic!("{name}: expected.exit must contain a number: {e}"));

        let stdout = normalize(&String::from_utf8_lossy(&output.stdout), root, &fixture);
        let stderr = normalize(&String::from_utf8_lossy(&output.stderr), root, &fixture);
        let exit = output.status.code().unwrap_or(128);
        if stdout != expected_stdout || stderr != expected_stderr || exit != expected_exit {
            failures.push(format!("{name}: expected exit {expected_exit}, stdout {expected_stdout:?}, stderr {expected_stderr:?}; got exit {exit}, stdout {stdout:?}, stderr {stderr:?}"));
        }
    }
    assert!(
        failures.is_empty(),
        "language fixtures failed:\n{}",
        failures.join("\n")
    );
}

#[test]
fn every_test_fixture_matches_its_expected_result() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let fixture_root = root.join("tests/test");
    let mut fixtures = fs::read_dir(&fixture_root)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", fixture_root.display()))
        .map(|entry| entry.unwrap().path())
        .filter(|path| path.is_dir())
        .collect::<Vec<_>>();
    fixtures.sort();
    assert!(
        !fixtures.is_empty(),
        "tests/test must contain nlc test packages"
    );

    let mut failures = Vec::new();
    for fixture in fixtures {
        let name = fixture.file_name().unwrap().to_string_lossy();
        let output = Command::new(env!("CARGO_BIN_EXE_nlc"))
            .arg("test")
            .arg(&fixture)
            .output()
            .unwrap_or_else(|e| panic!("{name}: could not launch nlc test: {e}"));
        let expected_stdout = fs::read_to_string(fixture.join("expected.stdout"))
            .unwrap_or_else(|e| panic!("{name}: cannot read expected.stdout: {e}"));
        let expected_stderr = fs::read_to_string(fixture.join("expected.stderr"))
            .unwrap_or_else(|e| panic!("{name}: cannot read expected.stderr: {e}"));
        let expected_exit: i32 = fs::read_to_string(fixture.join("expected.exit"))
            .unwrap_or_else(|e| panic!("{name}: cannot read expected.exit: {e}"))
            .trim()
            .parse()
            .unwrap_or_else(|e| panic!("{name}: expected.exit must contain a number: {e}"));

        let stdout = normalize(&String::from_utf8_lossy(&output.stdout), root, &fixture);
        let stderr = normalize(&String::from_utf8_lossy(&output.stderr), root, &fixture);
        let exit = output.status.code().unwrap_or(128);
        if stdout != expected_stdout || stderr != expected_stderr || exit != expected_exit {
            failures.push(format!("{name}: expected exit {expected_exit}, stdout {expected_stdout:?}, stderr {expected_stderr:?}; got exit {exit}, stdout {stdout:?}, stderr {stderr:?}"));
        }
        if name == "harness" {
            let run = Command::new(env!("CARGO_BIN_EXE_nlc"))
                .arg("run")
                .arg(&fixture)
                .output()
                .expect("could not launch nlc run on the test fixture");
            if run.status.code() != Some(0)
                || String::from_utf8_lossy(&run.stdout) != "777\n"
                || !run.stderr.is_empty()
            {
                failures.push(format!(
                    "harness: nlc run should execute main only; got exit {:?}, stdout {:?}, stderr {:?}",
                    run.status.code(),
                    String::from_utf8_lossy(&run.stdout),
                    String::from_utf8_lossy(&run.stderr)
                ));
            }
            let output_path =
                std::env::temp_dir().join(format!("nlc-test-build-{}", std::process::id()));
            let _ = fs::remove_file(&output_path);
            let build = Command::new(env!("CARGO_BIN_EXE_nlc"))
                .arg("build")
                .arg(&fixture)
                .arg("-o")
                .arg(&output_path)
                .output()
                .expect("could not launch nlc build on the test fixture");
            if !build.status.success() {
                failures.push(format!(
                    "harness: nlc build should check test bodies; got {}",
                    String::from_utf8_lossy(&build.stderr)
                ));
            } else {
                let built = Command::new(&output_path)
                    .output()
                    .expect("built test fixture did not run");
                if built.status.code() != Some(0)
                    || String::from_utf8_lossy(&built.stdout) != "777\n"
                    || !built.stderr.is_empty()
                {
                    failures.push(format!(
                        "harness: built package should run main only; got exit {:?}, stdout {:?}, stderr {:?}",
                        built.status.code(),
                        String::from_utf8_lossy(&built.stdout),
                        String::from_utf8_lossy(&built.stderr)
                    ));
                }
            }
            let _ = fs::remove_file(output_path);
        }
    }
    assert!(
        failures.is_empty(),
        "test-harness fixtures failed:\n{}",
        failures.join("\n")
    );
}

#[test]
fn build_command_writes_a_runnable_native_program() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let package = root.join("tests/run/arithmetic");
    let output_path = std::env::temp_dir().join(format!("nlc-build-test-{}", std::process::id()));
    let _ = fs::remove_file(&output_path);
    let build = Command::new(env!("CARGO_BIN_EXE_nlc"))
        .arg("build")
        .arg(&package)
        .arg("-o")
        .arg(&output_path)
        .output()
        .expect("could not launch nlc build");
    assert!(
        build.status.success(),
        "nlc build failed: {}",
        String::from_utf8_lossy(&build.stderr)
    );
    let run = Command::new(&output_path)
        .output()
        .expect("built native program did not run");
    let expected = fs::read_to_string(package.join("expected.stdout")).unwrap();
    assert_eq!(run.status.code(), Some(0));
    assert_eq!(String::from_utf8_lossy(&run.stdout), expected);
    assert!(
        run.stderr.is_empty(),
        "native program wrote unexpected stderr: {}",
        String::from_utf8_lossy(&run.stderr)
    );
    let _ = fs::remove_file(output_path);
}

fn normalize(text: &str, root: &Path, fixture: &Path) -> String {
    let mut normalized = text.to_owned();
    normalized = normalized.replace(&root.to_string_lossy().to_string(), "<repo>");
    normalized = normalized.replace(&fixture.to_string_lossy().to_string(), "<package>");
    replace_temp_paths(&normalized)
}

fn replace_temp_paths(text: &str) -> String {
    let marker = "/tmp/next-lang-";
    let mut result = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(index) = rest.find(marker) {
        result.push_str(&rest[..index]);
        rest = &rest[index + marker.len()..];
        if let Some(end) = rest.find('/') {
            result.push_str("<temp>");
            rest = &rest[end..];
        } else {
            result.push_str(marker);
            break;
        }
    }
    result.push_str(rest);
    result
}
