use std::fs;
use std::path::Path;
use std::process::Command;

#[test]
fn indexed_scalar_field_projection_avoids_materializing_the_row() -> Result<(), String> {
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return Ok(());
    }

    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .ok_or_else(|| "compiler crate has no workspace parent".to_owned())?;
    let compiler_build = Command::new("python3")
        .arg(root.join("scripts/build-selfhost-cached.py"))
        .arg("--reference")
        .arg(env!("CARGO_BIN_EXE_nlc"))
        .current_dir(root)
        .output()
        .map_err(|error| format!("build or reuse selfhost compiler: {error}"))?;
    if !compiler_build.status.success() {
        return Err(format!(
            "build or reuse selfhost compiler failed (status {:?}):\n{}",
            compiler_build.status.code(),
            String::from_utf8_lossy(&compiler_build.stderr)
        ));
    }
    let compiler_path = String::from_utf8(compiler_build.stdout)
        .map_err(|error| format!("selfhost compiler path is not UTF-8: {error}"))?;
    let compiler_path = compiler_path.trim();
    if compiler_path.is_empty() {
        return Err("selfhost compiler cache returned an empty path".to_owned());
    }

    let output_dir = root.join("target/b1-scalar-field-projection");
    fs::create_dir_all(&output_dir)
        .map_err(|error| format!("create scalar projection IR directory: {error}"))?;
    let output = output_dir.join("selfhost-regression.ll");
    let relative_output = output
        .strip_prefix(root)
        .map_err(|error| format!("IR output path is outside the workspace: {error}"))?
        .to_str()
        .ok_or_else(|| "IR output path is not UTF-8".to_owned())?;
    let built = Command::new(compiler_path)
        .args([
            "build",
            "tests/e3/b1_scalar_field_projection",
            "-o",
            relative_output,
            "--runtime=core",
        ])
        .current_dir(root)
        .output()
        .map_err(|error| format!("compile scalar projection fixture: {error}"))?;
    if !built.status.success() {
        return Err(format!(
            "selfhost fixture build failed (status {:?}):\n{}",
            built.status.code(),
            String::from_utf8_lossy(&built.stderr)
        ));
    }
    let ir = fs::read_to_string(&output)
        .map_err(|error| format!("read selfhost scalar projection IR: {error}"))?;

    // read_base is the first user function in the fixture, so it is nl_fn_0.
    let function = ir
        .split("define i64 @nl_fn_0(")
        .nth(1)
        .ok_or_else(|| "read_base is missing from emitted selfhost LLVM IR".to_owned())?;
    let body = function
        .split("\n}\n")
        .next()
        .ok_or_else(|| "read_base LLVM function has no closing brace".to_owned())?;
    let field_address = body.lines().find_map(|line| {
        let (address, instruction) = line.trim().split_once(" = ")?;
        if instruction.contains("getelementptr") && instruction.contains("coll.field.index.offset.")
        {
            Some(address.to_owned())
        } else {
            None
        }
    });
    let field_address =
        field_address.ok_or_else(|| "read_base has no direct scalar field GEP".to_owned())?;
    let field_load = format!("= load i64, ptr {field_address}");
    assert!(
        body.lines().any(|line| line.contains(&field_load)),
        "read_base must load the projected scalar from its field GEP:\n{body}"
    );
    assert!(
        body.lines()
            .any(|line| line.contains("call void @nl_fail(ptr %nl.ctx, i32 16")),
        "read_base must preserve the list index bounds check:\n{body}"
    );

    let index_node_id = body.lines().find_map(|line| {
        let (result, _) = line.trim().split_once(" = ")?;
        let suffix = result.strip_prefix("%coll.index.negative.")?;
        let id = suffix
            .chars()
            .take_while(|character| character.is_ascii_digit())
            .collect::<String>();
        (!id.is_empty()).then_some(id)
    });
    let index_node_id = index_node_id
        .ok_or_else(|| "read_base has no index bounds-check node marker".to_owned())?;
    let aggregate_result = format!("%v{index_node_id} = load ");
    let aggregate_address = format!("ptr %addr.{index_node_id},");
    assert!(
        !body.lines().any(|line| {
            let line = line.trim();
            line.starts_with(&aggregate_result)
                || (line.contains(" = load ") && line.contains(&aggregate_address))
        }),
        "the aggregate Index node must not produce its own scalar load:\n{body}"
    );
    assert!(
        !body.contains("coll.gather") && !body.contains("@nl.copy"),
        "read_base must not gather or copy the row before projecting its field:\n{body}"
    );
    assert!(
        !body.contains("region.offset"),
        "read_base must not reserve a large temporary for the projected row:\n{body}"
    );

    Ok(())
}
