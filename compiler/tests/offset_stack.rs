use next_lang::{build_package, compile_package};
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

static ENV_LOCK: Mutex<()> = Mutex::new(());

fn package(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root")
        .join(name)
}

struct EnvRestore(Vec<(&'static str, Option<OsString>)>);

impl EnvRestore {
    fn set(values: &[(&'static str, Option<&str>)]) -> Self {
        let mut previous = Vec::with_capacity(values.len());
        for (key, value) in values {
            previous.push((*key, std::env::var_os(key)));
            unsafe {
                if let Some(value) = value {
                    std::env::set_var(key, value);
                } else {
                    std::env::remove_var(key);
                }
            }
        }
        Self(previous)
    }
}

impl Drop for EnvRestore {
    fn drop(&mut self) {
        for (key, value) in self.0.drain(..).rev() {
            unsafe {
                if let Some(value) = value {
                    std::env::set_var(key, value);
                } else {
                    std::env::remove_var(key);
                }
            }
        }
    }
}

fn assert_allocator_is_only_on_slow_path(ir: &str, allocator: &str) {
    assert!(
        ir.contains(&format!("call {allocator}")),
        "{allocator} missing from IR"
    );
    assert!(
        ir.contains("label %stack.alloc.fast."),
        "inline fast block missing"
    );
    assert!(
        ir.contains("label %stack.alloc.slow."),
        "slow block missing"
    );
    let mut in_fast_block = false;
    for line in ir.lines() {
        let label = line.trim_end().ends_with(':');
        if label {
            in_fast_block = line.trim().starts_with("stack.alloc.fast.");
        } else if in_fast_block {
            assert!(
                !line.contains("@nl_stack_alloc"),
                "runtime allocator appeared in fast block: {line}"
            );
        }
    }
}

#[test]
fn region_allocation_is_inline_in_pointer_and_offset_modes() {
    let _lock = ENV_LOCK.lock().expect("environment lock");
    for mode in ["pointer", "offset"] {
        let _environment = EnvRestore::set(&[("NLC_STACK_MODE", Some(mode))]);
        let compiled = compile_package(&package("tests/run/o1_offset_cache_call"))
            .expect("cache-call fixture should compile in both stack modes");
        let allocator = if mode == "offset" {
            "i64 @nl_stack_alloc_offset"
        } else {
            "ptr @nl_stack_alloc"
        };
        assert_allocator_is_only_on_slow_path(&compiled.llvm_ir, allocator);
        let main = compiled
            .llvm_ir
            .split("; function main\n")
            .nth(1)
            .expect("main function is emitted")
            .split("}\n")
            .next()
            .expect("main function has a body");
        let call = main
            .find("call void @nl_fn_0(")
            .expect("main calls the stack-placing grower");
        let previous = main[..call]
            .lines()
            .rev()
            .find(|line| !line.trim().is_empty())
            .expect("the call has a preceding instruction");
        let writeback = if mode == "offset" {
            "@nl_context_set_top_offset"
        } else {
            "@nl_context_set_top"
        };
        assert!(
            previous.contains(writeback),
            "main publishes its cached top immediately before a stack-placing call in {mode} mode: {previous}"
        );
    }
    let _environment = EnvRestore::set(&[("NLC_STACK_MODE", Some("offset"))]);
    let unsupported = std::env::temp_dir().join(format!(
        "next-lang-offset-unsupported-{}",
        std::process::id()
    ));
    std::fs::create_dir_all(&unsupported).expect("create unsupported fixture");
    std::fs::write(
        unsupported.join("main.nl"),
        "fn main() {\n    var values: map<long, long, 1024> = map {}\n    print(values.count())\n}\n",
    )
    .expect("write unsupported fixture");
    let error = compile_package(&unsupported).expect_err("maps are outside the offset slice");
    assert!(error.message.contains("not supported in offset stack mode"));
    assert!(error.message.contains("offset stack slice"));
    let _ = std::fs::remove_dir_all(unsupported);
}

#[test]
fn offset_slice_fixtures_run_on_a_fixed_stack_at_o1_and_o3() {
    let _lock = ENV_LOCK.lock().expect("environment lock");
    for optimization in ["1", "3"] {
        for fixture in ["o1_offset_slice", "o1_offset_cache_call"] {
            let _environment = EnvRestore::set(&[
                ("NLC_STACK_MODE", Some("offset")),
                ("NLC_OPT_LEVEL", Some(optimization)),
            ]);
            let root = package(&format!("tests/run/{fixture}"));
            let binary = std::env::temp_dir().join(format!(
                "next-lang-{fixture}-o{optimization}-{}",
                std::process::id()
            ));
            build_package(&root, &binary).expect("offset fixture should build");
            let output = Command::new(&binary)
                .output()
                .expect("run offset fixture");
            let expected =
                std::fs::read(root.join("expected.stdout")).expect("read expected fixture output");
            assert!(
                output.status.success(),
                "{fixture} at O{optimization} failed: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            assert_eq!(output.stdout, expected, "{fixture} at O{optimization}");
            let _ = std::fs::remove_file(binary);
        }
    }
}
