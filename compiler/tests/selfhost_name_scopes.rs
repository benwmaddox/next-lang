#![cfg(unix)]

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

struct TempDirectory(PathBuf);

impl TempDirectory {
    fn new() -> Self {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock is after the Unix epoch")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "next-lang-name-scope-{}-{nonce}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed),
        ));
        fs::create_dir_all(&path).expect("create temporary benchmark directory");
        Self(path)
    }
}

impl Drop for TempDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn checked_output(output: Output, context: &str) -> Output {
    assert!(
        output.status.success(),
        "{context} failed (status {:?}):\n{}\n{}",
        output.status.code(),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
    );
    output
}

fn median(mut samples: Vec<Duration>) -> Duration {
    samples.sort_unstable();
    samples[samples.len() / 2]
}

fn build_time(selfhost: &Path, package: &Path) -> Duration {
    let started = Instant::now();
    let output = Command::new("timeout")
        .arg("30")
        .arg(selfhost)
        .args(["build", ".", "-o", "out.ll", "--runtime=core"])
        .current_dir(package)
        .env("NLC_FRONTEND", "selfhost")
        .env("NLC_OPT_LEVEL", "1")
        .output()
        .expect("run the selfhost compiler under timeout");
    checked_output(output, "selfhosted name-scope scaling build");
    started.elapsed()
}

#[test]
fn repeated_parameter_name_checks_scale_subcubically() {
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return;
    }

    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let reference = env!("CARGO_BIN_EXE_nlc");
    let build = Command::new("python3")
        .arg(root.join("scripts/build-selfhost-cached.py"))
        .arg("--reference")
        .arg(reference)
        .current_dir(root)
        .output()
        .expect("build or reuse the selfhost compiler");
    let build = checked_output(build, "stage-zero selfhost build");
    let selfhost = String::from_utf8(build.stdout)
        .expect("cached selfhost compiler path is UTF-8")
        .trim()
        .to_owned();

    let temporary = TempDirectory::new();
    let generator = root.join("scripts/gen-selfhost-bench.py");
    let mut timings = Vec::new();
    for functions in [1_000, 2_000] {
        let package = temporary.0.join(functions.to_string());
        let generated = Command::new("python3")
            .arg(&generator)
            .arg(&package)
            .arg("--functions")
            .arg(functions.to_string())
            .current_dir(root)
            .output()
            .expect("run the existing selfhost benchmark generator");
        checked_output(generated, "generate repeated-parameter package");

        // Warm process and file-system caches before collecting three samples.
        build_time(Path::new(&selfhost), &package);
        let samples = (0..3)
            .map(|_| build_time(Path::new(&selfhost), &package))
            .collect::<Vec<_>>();
        let elapsed = median(samples);
        if std::env::var_os("NLC_TIMING").is_some() {
            eprintln!("{functions} repeated-parameter functions: {elapsed:?}");
        }
        timings.push(elapsed);
    }

    let [one_thousand, two_thousand] = timings.as_slice() else {
        unreachable!("both scale sizes are recorded")
    };
    assert!(
        *two_thousand <= *one_thousand * 4 + Duration::from_millis(500),
        "repeated-parameter name checking grew too quickly: 1k={one_thousand:?}, 2k={two_thousand:?}"
    );
}
