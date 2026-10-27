use std::fs;
use std::path::{Path, PathBuf};

fn collect_core_sources(directory: &Path, sources: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(directory).expect("read core directory") {
        let path = entry.expect("read core directory entry").path();
        if path.is_dir() {
            collect_core_sources(&path, sources);
        } else if path.extension().is_some_and(|extension| extension == "nl") {
            sources.push(path);
        }
    }
}

#[test]
fn raw_fallible_system_calls_stay_inside_result_wrappers() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let mut sources = Vec::new();
    collect_core_sources(&root.join("core"), &mut sources);
    sources.sort();

    let raw_calls = [
        ("write", "write", "nl_core_sys_write"),
        ("map", "map", ""),
        ("protect", "protect", ""),
        ("ioctl", "ioctl", ""),
        ("statx", "statx", ""),
        ("sigaction", "sigaction", ""),
        ("openat", "openat", ""),
        ("close", "close", ""),
    ];
    let mut wrapper_calls = vec![0usize; raw_calls.len()];
    let mut wrapper_checks = vec![0usize; raw_calls.len()];
    let mut raw_injected_writes = 0usize;

    for path in &sources {
        let source = fs::read_to_string(path).expect("read core source");
        let mut function = "";
        let mut functions = Vec::<(String, String)>::new();
        for line in source.lines() {
            let code = line.split("//").next().unwrap_or("").trim();
            if let Some(declaration) = code.strip_prefix("fn ") {
                function = declaration.split('(').next().unwrap_or("");
                functions.push((function.to_string(), String::new()));
            }
            if let Some((_, body)) = functions.last_mut() {
                body.push_str(code);
                body.push('\n');
            }

            if code.contains("sys.is_error(") {
                if let Some((index, _)) = raw_calls
                    .iter()
                    .enumerate()
                    .find(|(_, (_, wrapper, _))| *wrapper == function)
                {
                    wrapper_checks[index] += 1;
                } else {
                    panic!(
                        "sys.is_error appears outside a Result wrapper in {} ({function})",
                        path.display()
                    );
                }
            }

            for (index, (call, wrapper, raw_exception)) in raw_calls.iter().enumerate() {
                if !code.contains(&format!("sys.{call}(")) {
                    continue;
                }
                if !raw_exception.is_empty() && function == *raw_exception {
                    raw_injected_writes += 1;
                } else if function == *wrapper {
                    wrapper_calls[index] += 1;
                } else {
                    panic!(
                        "raw sys.{call} call is outside its wrapper in {} ({function})",
                        path.display()
                    );
                }
            }
        }

        for (index, (call, wrapper, raw_exception)) in raw_calls.iter().enumerate() {
            let Some((_, body)) = functions.iter().find(|(name, _)| name == wrapper) else {
                continue;
            };
            if !raw_exception.is_empty() {
                assert!(
                    body.contains(&format!("{raw_exception}(")),
                    "write wrapper must preserve test-mode fault injection"
                );
            } else {
                assert_eq!(
                    wrapper_calls[index], 1,
                    "expected one raw sys.{call} in {wrapper}"
                );
            }
            assert_eq!(
                wrapper_checks[index], 1,
                "expected one sys.is_error check in {wrapper}"
            );
        }
    }

    assert!(
        raw_injected_writes > 0,
        "the write fault injector must retain the raw syscall backend"
    );
    for (index, (call, _, _)) in raw_calls.iter().enumerate() {
        assert_eq!(
            wrapper_checks[index], 1,
            "expected one Result wrapper for sys.{call}"
        );
    }
}
