use std::io;
use std::path::Path;
use std::process::Command;

#[test]
fn selfhost_c_runtime_io_fixtures_match() -> Result<(), Box<dyn std::error::Error>> {
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return Ok(());
    }

    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "workspace root is missing"))?;
    let reference = env!("CARGO_BIN_EXE_nlc");
    let build = Command::new("python3")
        .arg(root.join("scripts/build-selfhost-cached.py"))
        .arg("--reference")
        .arg(reference)
        .current_dir(root)
        .env("NLC_FRONTEND", "rust")
        .output()?;
    assert!(
        build.status.success(),
        "stage-zero selfhost compiler build failed (status {:?}):\n{}\n{}",
        build.status.code(),
        String::from_utf8_lossy(&build.stdout),
        String::from_utf8_lossy(&build.stderr),
    );

    let compiler_path = String::from_utf8(build.stdout)?;
    let compiler_path = compiler_path.trim();
    if compiler_path.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "stage-zero selfhost compiler builder returned an empty path",
        )
        .into());
    }

    let check = Command::new("python3")
        .arg(root.join("scripts/check-selfhost-c-io.py"))
        .arg("--compiler")
        .arg(compiler_path)
        .current_dir(root)
        .env("NLC_FRONTEND", "rust")
        .output()?;
    assert!(
        check.status.success(),
        "selfhost C I/O check failed (status {:?}):\n{}\n{}",
        check.status.code(),
        String::from_utf8_lossy(&check.stdout),
        String::from_utf8_lossy(&check.stderr),
    );
    Ok(())
}
