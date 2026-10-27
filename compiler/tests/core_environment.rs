use std::path::Path;
use std::process::Command;

// The core runtime scans the environment for its NLC_* settings at startup.
// A short entry placed last must not be read past its terminator. Only the
// executable path and a null word follow the last entry at the top of the
// initial stack, so the program runs as `./p` to keep that tail short: before
// the fix, `X=1` then segfaulted core-runtime programs built by the
// self-hosted compiler.
#[test]
fn core_runtime_startup_tolerates_short_environment_entries() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler directory has a workspace root");
    let nlc = env!("CARGO_BIN_EXE_nlc");
    let temporary =
        std::env::temp_dir().join(format!("next-lang-core-environment-{}", std::process::id()));
    let package = temporary.join("package");
    std::fs::create_dir_all(&package).expect("create temporary package directory");
    std::fs::write(
        package.join("main.nl"),
        "fn main() {\n    var total = 0\n    for i in 0..5 {\n        total = total + i\n    }\n    print(total)\n}\n",
    )
    .expect("write package source");

    let selfhost = temporary.join("selfhost");
    let built = Command::new(nlc)
        .args(["--frontend=rust", "build", "selfhost", "-o"])
        .arg(&selfhost)
        .current_dir(root)
        .output()
        .expect("build the self-hosted compiler");
    assert!(
        built.status.success(),
        "self-hosted compiler build failed: {}",
        String::from_utf8_lossy(&built.stderr)
    );

    let compiled = Command::new(&selfhost)
        .args(["build", ".", "-o", "program.ll", "--runtime=core"])
        .current_dir(&package)
        .output()
        .expect("run the self-hosted compiler");
    assert!(
        compiled.status.success(),
        "self-hosted build failed: {}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let program = temporary.join("p");
    let linked = Command::new(nlc)
        .arg("link-ir")
        .arg(package.join("program.ll"))
        .arg("-o")
        .arg(&program)
        .env("NLC_OPT_LEVEL", "1")
        .output()
        .expect("link the core-runtime program");
    assert!(
        linked.status.success(),
        "link-ir failed: {}",
        String::from_utf8_lossy(&linked.stderr)
    );

    for entry in [
        ("X", "1"),
        ("X", ""),
        ("PAD", ""),
        ("NLC_STACK_PREALLOC", ""),
    ] {
        let run = Command::new("./p")
            .current_dir(&temporary)
            .env_clear()
            .env(entry.0, entry.1)
            .output()
            .expect("run the core-runtime program");
        assert!(
            run.status.success(),
            "program failed with only {}={} in its environment: status {:?}, stderr {}",
            entry.0,
            entry.1,
            run.status,
            String::from_utf8_lossy(&run.stderr)
        );
        assert_eq!(run.stdout, b"10\n");
    }
    std::fs::remove_dir_all(&temporary).ok();
}
