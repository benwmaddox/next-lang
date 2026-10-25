use next_lang::compile_package;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

static NEXT_PACKAGE: AtomicU64 = AtomicU64::new(0);

struct TempPackage(PathBuf);

impl TempPackage {
    fn new(name: &str, source: &str) -> Self {
        let path = std::env::temp_dir().join(format!(
            "next-lang-checker-perf-{}-{}-{name}",
            std::process::id(),
            NEXT_PACKAGE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&path).expect("create temporary package");
        fs::write(path.join("main.nl"), source).expect("write temporary source");
        Self(path)
    }

    fn path(&self) -> &std::path::Path {
        &self.0
    }
}

impl Drop for TempPackage {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn assert_compiles_quickly(name: &str, source: &str) {
    let package = TempPackage::new(name, source);
    let start = Instant::now();
    let result = compile_package(package.path());
    let elapsed = start.elapsed();
    if std::env::var_os("NLC_TIMING").is_some() {
        eprintln!("{name}: {elapsed:?}");
    }
    result.unwrap_or_else(|error| panic!("{name} stress package failed to compile: {error}"));
    assert!(
        elapsed < Duration::from_secs(2),
        "{name} checker regression: {elapsed:?} for 1,000 terms"
    );
}

#[test]
fn large_expression_shapes_are_checked_in_linear_time() {
    let terms = 1_000;
    let long_sum = vec!["a"; terms].join(" + ");
    assert_compiles_quickly(
        "long-sum",
        &format!("fn main() {{\n    let a = 1L\n    print({long_sum})\n}}\n"),
    );

    let ascii_sum = vec!["s"; terms].join(" + ");
    assert_compiles_quickly(
        "ascii-sum",
        &format!(
            "fn main() {{\n    let s: Ascii max 10 = \"x\"\n    let joined: Ascii max {terms} = {ascii_sum}\n}}\n"
        ),
    );

    let boolean_chain = vec!["a"; terms].join(" && ");
    assert_compiles_quickly(
        "boolean-chain",
        &format!("fn main() {{\n    let a = true\n    print({boolean_chain})\n}}\n"),
    );

    let nested_calls = format!("{}a{}", "id(".repeat(terms), ")".repeat(terms));
    assert_compiles_quickly(
        "nested-calls",
        &format!(
            "fn id(value: long) -> long {{ value }}\n\nfn main() {{\n    let a = 1L\n    print({nested_calls})\n}}\n"
        ),
    );
}

#[test]
fn nested_ascii_loop_growth_proofs_remain_quick() {
    let depth = 750;
    let mut source = format!("fn main() {{\n    var a: Ascii max {depth} = Ascii.empty()\n");
    for index in 0..depth {
        source.push_str(&"    ".repeat(index + 1));
        source.push_str(&format!("for i{index} in 0..1 {{\n"));
    }
    source.push_str(&"    ".repeat(depth + 1));
    source.push_str("a += \"x\"\n");
    for index in (0..depth).rev() {
        source.push_str(&"    ".repeat(index + 1));
        source.push_str("}\n");
    }
    source.push_str("}\n");
    assert_compiles_quickly("nested-ascii-loop-growth", &source);
}

#[test]
fn long_text_and_bytes_concatenations_and_many_fields_remain_linear() {
    let terms = 1_000;
    let text_sum = vec!["piece"; terms].join(" + ");
    assert_compiles_quickly(
        "long-text-sum",
        &format!(
            "fn main() {{\n    let piece: Text max 1 bytes max 4 = \"😀\"\n    let joined: Text max {terms} bytes max {} = {text_sum}\n    print(joined.len())\n}}\n",
            terms * 4
        ),
    );

    let bytes_sum = vec!["piece"; terms].join(" + ");
    assert_compiles_quickly(
        "long-bytes-sum",
        &format!(
            "fn main() {{\n    let piece: Bytes max 1 = b\"x\"\n    let joined: Bytes max {terms} = {bytes_sum}\n    print(joined.len())\n}}\n"
        ),
    );

    let fields = (0..terms)
        .map(|index| format!("field_{index}: Text max 1"))
        .collect::<Vec<_>>()
        .join(", ");
    let values = (0..terms)
        .map(|index| format!("field_{index}: \"x\""))
        .collect::<Vec<_>>()
        .join(", ");
    assert_compiles_quickly(
        "many-growing-fields",
        &format!(
            "struct Many {{ {fields} }}\nfn main() {{\n    let value = Many {{ {values} }}\n    print(value.field_999.len())\n}}\n"
        ),
    );
}
