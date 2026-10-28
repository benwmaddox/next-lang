use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

struct Scratch(PathBuf);

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn statistic(stderr: &str, name: &str) -> u64 {
    let prefix = format!("{name}=");
    stderr
        .lines()
        .filter(|line| line.starts_with("nl offset stack entry "))
        .flat_map(str::split_whitespace)
        .find_map(|field| field.strip_prefix(&prefix))
        .and_then(|number| number.parse().ok())
        .unwrap_or_else(|| panic!("missing {name}: {stderr}"))
}

#[test]
fn first_large_literal_survives_relocation_and_borrowed_slicing() {
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let reference = env!("CARGO_BIN_EXE_nlc");
    let cached = Command::new("python3")
        .arg(root.join("scripts/build-selfhost-cached.py"))
        .args(["--reference", reference])
        .current_dir(root)
        .output()
        .unwrap();
    assert!(
        cached.status.success(),
        "{}",
        String::from_utf8_lossy(&cached.stderr)
    );
    let selfhost = String::from_utf8(cached.stdout).unwrap().trim().to_owned();
    let scratch = Scratch(std::env::temp_dir().join(format!(
        "next-lang-text-relocation-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    )));
    fs::create_dir_all(&scratch.0).unwrap();
    // Put the literal before every type annotation/function declaration, so it
    // is the first expression node. Node zero must not double as planner scratch.
    let source = format!(
        "test \"large first literal\" {{\n    let payload = b\"{}\"\n    print(payload.count())\n    let sliced = head(payload)\n    expect sliced == b\"AAAA\"\n}}\nfn head(input: Bytes max 1048576) -> Bytes max 1048576 {{ input.slice(0L..4L) }}\n",
        "A".repeat(1024 * 1024)
    );
    fs::write(scratch.0.join("main.nl"), source).unwrap();
    fs::write(scratch.0.join("package.toml"), "capabilities = [\"out\"]\n").unwrap();
    let built = Command::new("timeout")
        .args([
            "120",
            &selfhost,
            "build",
            ".",
            "-o",
            "module.ll",
            "--runtime=core",
            "--test",
            "--test-region-threshold=0",
        ])
        .current_dir(&scratch.0)
        .output()
        .unwrap();
    assert!(
        built.status.success(),
        "{}",
        String::from_utf8_lossy(&built.stderr)
    );
    let linked = Command::new(reference)
        .args(["link-ir", "module.ll", "-o", "program"])
        .env("NLC_OPT_LEVEL", "1")
        .current_dir(&scratch.0)
        .output()
        .unwrap();
    assert!(
        linked.status.success(),
        "{}",
        String::from_utf8_lossy(&linked.stderr)
    );
    let output = Command::new("timeout")
        .arg("30")
        .arg(scratch.0.join("program"))
        .env("NLC_TEST_INDEX", "0")
        .env("NLC_TEST_STACK_FORCE_MOVE", "1")
        .env("NLC_STACK_STATS", "1")
        .env("NLC_STACK_VERIFY", "1")
        .env_remove("NLC_STACK_PREALLOC")
        .current_dir(&scratch.0)
        .output()
        .unwrap();
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(output.status.success(), "{stderr}");
    assert_eq!(output.stdout, b"1048576\n");
    assert!(statistic(&stderr, "growths") > 0, "{stderr}");
    assert!(statistic(&stderr, "relocations") > 0, "{stderr}");
    assert!(
        statistic(&stderr, "peak_used") < 3 * 1024 * 1024,
        "borrowed slice reserved an extra source-sized temporary: {stderr}"
    );
}
