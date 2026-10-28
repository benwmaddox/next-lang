use std::path::Path;
use std::process::Command;

// Real memory, not the worst-case bound (Ben, 2026-10-27): the self-hosted
// compiler's peak resident set on its own source must stay within a budget.
// Its worst-case data-stack bound is reported by stack_contracts.rs.
const PEAK_RSS_BUDGET_KIB: u64 = 512 * 1024;

#[test]
fn selfhost_compiler_peak_memory_on_its_own_source_stays_within_budget() {
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return;
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
        .expect("build or reuse the self-hosted compiler");
    assert!(
        build.status.success(),
        "selfhost build failed:\n{}",
        String::from_utf8_lossy(&build.stderr)
    );
    let selfhost = String::from_utf8(build.stdout)
        .expect("cached selfhost path is UTF-8")
        .trim()
        .to_owned();
    let output_name = format!(".memory-check-{}.ll", std::process::id());
    // The child's exit status doesn't matter here (the compiler can't build
    // itself yet); its peak resident set does.
    let script = "import resource, subprocess, sys\n\
                  subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)\n\
                  print(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss)\n";
    let measured = Command::new("python3")
        .arg("-c")
        .arg(script)
        .arg(&selfhost)
        .args(["build", "selfhost", "-o", &output_name, "--runtime=core"])
        .current_dir(root)
        .output()
        .expect("run the self-hosted compiler under getrusage");
    let _ = std::fs::remove_file(root.join("selfhost").join(&output_name));
    let _ = std::fs::remove_file(root.join(&output_name));
    let peak_kib: u64 = String::from_utf8_lossy(&measured.stdout)
        .trim()
        .parse()
        .unwrap_or_else(|_| {
            panic!(
                "no peak RSS reported: {}",
                String::from_utf8_lossy(&measured.stderr)
            )
        });
    eprintln!("selfhost compiler peak RSS on selfhost/: {peak_kib} KiB");
    assert!(
        peak_kib < PEAK_RSS_BUDGET_KIB,
        "selfhost compiler peak RSS {peak_kib} KiB exceeds {PEAK_RSS_BUDGET_KIB} KiB"
    );
}
