use std::fs;
use std::path::Path;
use std::process::Command;

#[test]
fn e2_reference_fixes_match_their_fixtures() {
    // This audit forces the Rust frontend for every fixture and is owned by
    // the selfhost suite.
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let fixtures = [
        "reference_unit_erasure",
        "reference_unit_field",
        "tolong",
        "reference_default_scope",
        "reference_default_unused",
        "reference_default_later",
        "reference_default_shadow",
        "reference_default_override",
        "reference_default_cycle",
        "reference_default_two_cycle",
        "reference_default_cycle_order",
        "reference_default_return",
        "reference_default_try",
        "reference_default_break",
        "reference_default_continue",
        "reference_default_expect",
        "reference_default_call_cycle",
        "reference_default_phase_entry",
        "reference_default_phase_body",
    ];
    let mut failures = Vec::new();
    for name in fixtures {
        let package = root.join("tests/e2").join(name);
        let output = Command::new(env!("CARGO_BIN_EXE_nlc"))
            .env("NLC_FRONTEND", "rust")
            .arg("run")
            .arg(&package)
            .output()
            .unwrap_or_else(|error| panic!("{name}: could not launch nlc: {error}"));
        let expected_stdout = fs::read(package.join("expected.stdout")).unwrap();
        let expected_stderr = fs::read(package.join("expected.stderr")).unwrap();
        let expected_exit: i32 = fs::read_to_string(package.join("expected.exit"))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        let actual_exit = output.status.code().unwrap_or(128);
        if output.stdout != expected_stdout
            || output.stderr != expected_stderr
            || actual_exit != expected_exit
        {
            failures.push(format!(
                "{name}: expected exit {expected_exit}, stdout {expected_stdout:?}, stderr {expected_stderr:?}; got exit {actual_exit}, stdout {:?}, stderr {:?}",
                output.stdout, output.stderr
            ));
        }
    }
    assert!(
        failures.is_empty(),
        "E2 reference fixtures failed:\n{}",
        failures.join("\n")
    );
}
