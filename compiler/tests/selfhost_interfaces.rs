// The compiler is split across selfhost/compiler_*.nl; the audit reads them in name order.
fn selfhost_compiler_source() -> String {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../selfhost");
    let mut paths: Vec<_> = std::fs::read_dir(dir)
        .unwrap()
        .map(|entry| entry.unwrap().path())
        .filter(|path| {
            let name = path.file_name().unwrap().to_string_lossy();
            name.starts_with("compiler_") && name.ends_with(".nl")
        })
        .collect();
    paths.sort();
    paths.iter().map(|path| std::fs::read_to_string(path).unwrap()).collect()
}

#[test]
fn type_table_access_and_struct_classification_stay_behind_the_interface() {
    // This source audit belongs to the selfhost suite.
    if std::env::var("NLC_FRONTEND").as_deref() != Ok("selfhost") {
        return;
    }
    let mut in_type_module = false;
    let mut begin_count = 0;
    let mut end_count = 0;

    for (line_number, line) in selfhost_compiler_source().lines().enumerate() {
        if line.contains("// TYPE MODULE BEGIN") {
            assert!(
                !in_type_module,
                "nested type module at line {}",
                line_number + 1
            );
            in_type_module = true;
            begin_count += 1;
            continue;
        }
        if line.contains("// TYPE MODULE END") {
            assert!(
                in_type_module,
                "type module ends before it begins at line {}",
                line_number + 1
            );
            in_type_module = false;
            end_count += 1;
            continue;
        }

        let code = line.split("//").next().unwrap_or("");
        assert!(
            !code.contains("struct_types["),
            "direct struct table index at line {}",
            line_number + 1
        );
        if !in_type_module {
            assert!(
                !code.contains("type_records["),
                "type table index outside its module at line {}",
                line_number + 1
            );
        }

        let compact = code
            .chars()
            .filter(|character| !character.is_whitespace())
            .collect::<String>();
        let mut search_from = 0;
        while let Some(relative) = compact[search_from..].find("TY_STRUCT_BASE") {
            let start = search_from + relative;
            let end = start + "TY_STRUCT_BASE".len();
            let before = compact[..start].chars().last();
            let after = compact[end..].chars().next();
            assert!(
                !matches!(before, Some('<' | '>' | '=' | '!'))
                    && !matches!(after, Some('<' | '>' | '=')),
                "TY_STRUCT_BASE comparison at line {}",
                line_number + 1
            );
            search_from = end;
            if search_from >= compact.len() {
                break;
            }
        }
    }

    assert_eq!(begin_count, 1, "expected one type-module start marker");
    assert_eq!(end_count, 1, "expected one type-module end marker");
    assert!(!in_type_module, "type module is not closed");
}
