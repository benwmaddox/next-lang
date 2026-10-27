use std::collections::{BTreeSet, HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn selfhost_enabled() -> bool {
    std::env::var("NLC_FRONTEND").as_deref() == Ok("selfhost")
}

fn metadata_id(line: &str) -> Option<String> {
    let (left, _) = line.trim().split_once('=')?;
    let id = left.trim().strip_prefix('!')?;
    id.chars()
        .all(|ch| ch.is_ascii_digit())
        .then(|| id.to_owned())
}

fn metadata_rhs(line: &str) -> Option<String> {
    Some(
        line.trim()
            .split_once('=')?
            .1
            .chars()
            .filter(|ch| !ch.is_whitespace())
            .collect(),
    )
}

fn tbaa_tags(ir: &str) -> (String, String) {
    let mut context_type = None;
    let mut program_type = None;
    let mut definitions = HashMap::new();
    for line in ir.lines() {
        if let Some(id) = metadata_id(line) {
            let rhs = metadata_rhs(line).expect("metadata definition has a value");
            if rhs.contains("!{!\"contextbase\"") {
                context_type = Some(id.clone());
            }
            if rhs.contains("!{!\"programstorage\"") {
                program_type = Some(id.clone());
            }
            definitions.insert(id, rhs);
        }
    }
    let find_access_tag = |type_id: Option<String>| {
        let type_id = type_id.expect("optimized IR retains the TBAA type node");
        let expected = format!("!{{!{type_id},!{type_id},i640}}");
        definitions
            .iter()
            .find_map(|(id, rhs)| (rhs == &expected).then(|| id.clone()))
            .expect("optimized IR retains the scalar TBAA access tag")
    };
    (find_access_tag(context_type), find_access_tag(program_type))
}

#[derive(Default)]
struct BasicBlock {
    instructions: Vec<String>,
    successors: BTreeSet<String>,
}

struct Function {
    name: String,
    blocks: Vec<(String, BasicBlock)>,
}

fn branch_targets(instruction: &str) -> Vec<String> {
    let mut rest = instruction;
    let mut targets = Vec::new();
    while let Some(at) = rest.find("label %") {
        rest = &rest[at + "label %".len()..];
        let end = rest
            .find(|ch: char| !(ch.is_ascii_alphanumeric() || ch == '_' || ch == '.' || ch == '$'))
            .unwrap_or(rest.len());
        if end > 0 {
            targets.push(rest[..end].to_owned());
            rest = &rest[end..];
        }
    }
    targets
}

fn parse_functions(ir: &str) -> Vec<Function> {
    let mut functions = Vec::new();
    let mut current: Option<Function> = None;
    let mut current_block: Option<(String, BasicBlock)> = None;

    for line in ir.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("define ") {
            let name = trimmed
                .split('@')
                .nth(1)
                .and_then(|tail| tail.split(['(', ' ']).next())
                .unwrap_or("")
                .to_owned();
            current = Some(Function {
                name,
                blocks: Vec::new(),
            });
            current_block = None;
            continue;
        }
        let Some(function) = current.as_mut() else {
            continue;
        };
        if trimmed == "}" {
            if let Some(block) = current_block.take() {
                function.blocks.push(block);
            }
            functions.push(current.take().expect("function exists"));
            continue;
        }
        if !line.chars().next().is_some_and(char::is_whitespace) {
            if let Some((label, _)) = trimmed.split_once(':') {
                if !label.is_empty()
                    && label
                        .chars()
                        .all(|ch| ch.is_ascii_alphanumeric() || ch == '_' || ch == '.' || ch == '$')
                {
                    if let Some(block) = current_block.take() {
                        function.blocks.push(block);
                    }
                    current_block = Some((label.to_owned(), BasicBlock::default()));
                    continue;
                }
            }
        }
        if let Some((_, block)) = current_block.as_mut() {
            if trimmed.starts_with("br ") || trimmed.starts_with("switch ") {
                block.successors.extend(branch_targets(trimmed));
            }
            if !trimmed.is_empty() && !trimmed.starts_with(';') {
                block.instructions.push(trimmed.to_owned());
            }
        }
    }
    functions
}

fn natural_loops(function: &Function) -> Vec<HashSet<String>> {
    if function.blocks.is_empty() {
        return Vec::new();
    }
    let labels: HashSet<_> = function
        .blocks
        .iter()
        .map(|(label, _)| label.clone())
        .collect();
    let entry = function.blocks[0].0.clone();
    let mut predecessors: HashMap<String, Vec<String>> = HashMap::new();
    for (source, block) in &function.blocks {
        for target in &block.successors {
            if labels.contains(target) {
                predecessors
                    .entry(target.clone())
                    .or_default()
                    .push(source.clone());
            }
        }
    }

    let mut dominators: HashMap<String, HashSet<String>> = HashMap::new();
    for label in &labels {
        dominators.insert(
            label.clone(),
            if label == &entry {
                HashSet::from([entry.clone()])
            } else {
                labels.clone()
            },
        );
    }
    loop {
        let mut changed = false;
        for label in labels.iter().filter(|label| *label != &entry) {
            let preds = predecessors.get(label).cloned().unwrap_or_default();
            let mut next = if let Some(first) = preds.first() {
                dominators[first].clone()
            } else {
                HashSet::new()
            };
            for pred in preds.iter().skip(1) {
                next.retain(|item| dominators[pred].contains(item));
            }
            next.insert(label.clone());
            if dominators[label] != next {
                dominators.insert(label.clone(), next);
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }

    let mut loops = Vec::new();
    for (source, block) in &function.blocks {
        for header in &block.successors {
            if !labels.contains(header) || !dominators[source].contains(header) {
                continue;
            }
            let mut natural_loop = HashSet::from([header.clone(), source.clone()]);
            let mut pending = vec![source.clone()];
            while let Some(node) = pending.pop() {
                for pred in predecessors.get(&node).into_iter().flatten() {
                    if natural_loop.insert(pred.clone()) && pred != header {
                        pending.push(pred.clone());
                    }
                }
            }
            loops.push(natural_loop);
        }
    }
    loops
}

fn assert_hot_loop_ir(pair: &str, ir: &str, context_tag: &str, program_tag: &str) {
    let functions = parse_functions(ir);
    let mut checked_loops = 0;
    for function in functions
        .iter()
        .filter(|function| function.name.starts_with("nl_fn_"))
    {
        let blocks: HashMap<_, _> = function
            .blocks
            .iter()
            .map(|(label, block)| (label.as_str(), block))
            .collect();
        for natural_loop in natural_loops(function) {
            let loop_instructions: Vec<_> = natural_loop
                .iter()
                .filter_map(|label| blocks.get(label.as_str()))
                .flat_map(|block| block.instructions.iter())
                .collect();
            let is_index_loop = loop_instructions
                .iter()
                .any(|line| line.contains("%coll.index."));
            if !is_index_loop {
                continue;
            }
            checked_loops += 1;
            for line in &loop_instructions {
                assert!(
                    !line.contains("@nl_context_reservation_bytes")
                        && !line.contains("@nl_stack_grow")
                        && !line.contains("%nl.scope.end."),
                    "{pair} {} hot loop contains per-iteration region reservation in:\n{line}",
                    function.name
                );
            }
            if pair != "tight_list" {
                assert!(
                    loop_instructions.iter().any(|line| {
                        line.starts_with("store ")
                            && line.contains(&format!("!tbaa !{program_tag}"))
                    }),
                    "{pair} {} hot loop has no typed program-store marker",
                    function.name
                );
            }
            for (label, block) in function
                .blocks
                .iter()
                .filter(|(label, _)| natural_loop.contains(label))
            {
                for line in &block.instructions {
                    let is_context_base_load = line.contains("load ptr")
                        && line.contains(&format!("!tbaa !{context_tag}"));
                    assert!(
                        !is_context_base_load,
                        "{pair} {} hot loop reloads the context base in block {label}; its !tbaa tag identifies the context-base load:\n{line}",
                        function.name
                    );
                }
            }
        }
    }
    assert!(
        checked_loops > 0,
        "{pair} has no optimized user loop with a %coll.index marker"
    );
}

fn assert_raw_alias_tags(pair: &str, ir: &str) {
    assert!(ir.contains("!9001 = !{!\"context base\", !9000}"));
    assert!(ir.contains("!9004 = !{!\"program storage\", !9000}"));
    let mut function = String::new();
    let mut tagged_base_loads = 0;
    for line in ir.lines() {
        if line.trim().starts_with("define ") {
            function = line
                .split('@')
                .nth(1)
                .and_then(|tail| tail.split(['(', ' ']).next())
                .unwrap_or("")
                .to_owned();
        }
        if line.contains("load ptr")
            && line.contains("ptr %sys.ptr.")
            && function == "nl_context_current_base"
        {
            assert!(
                line.contains("!tbaa !9002"),
                "{pair} context-base load lost its TBAA marker: {line}"
            );
            tagged_base_loads += 1;
        }
        if line.trim_start().starts_with("store ") && line.contains("ptr %sys.ptr.") {
            assert!(
                !line.contains("!tbaa !9003"),
                "{pair} raw sys/context store was tagged as program storage: {line}"
            );
        }
    }
    assert_eq!(
        tagged_base_loads, 1,
        "{pair} should tag only nl_context_current_base's header load"
    );
    assert!(
        ir.lines()
            .any(|line| line.trim_start().starts_with("store ") && line.contains("!tbaa !9003")),
        "{pair} emitted no typed program-storage store marker"
    );
}

fn run(command: &mut Command, what: &str) -> std::process::Output {
    let output = command
        .output()
        .unwrap_or_else(|error| panic!("{what}: {error}"));
    assert!(
        output.status.success(),
        "{what} failed (status {:?}):\n{}\n{}",
        output.status.code(),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    output
}

struct Scratch(PathBuf);

impl Scratch {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "next-lang-e3a3-ir-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
        ));
        fs::create_dir_all(&path).expect("create E3a3 IR scratch directory");
        Self(path)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn selfhost_benchmark_loops_keep_base_and_top_hot() {
    if !selfhost_enabled() {
        return;
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("compiler crate has a workspace root");
    let scratch = Scratch::new();
    let reference = env!("CARGO_BIN_EXE_nlc");
    let cache = run(
        Command::new("python3")
            .arg(root.join("scripts/build-selfhost-cached.py"))
            .arg("--reference")
            .arg(reference)
            .current_dir(root),
        "build or reuse the working-tree selfhost compiler",
    );
    let selfhost = String::from_utf8(cache.stdout)
        .expect("cached selfhost compiler path is UTF-8")
        .trim()
        .to_owned();

    for pair in ["increment_heavy", "struct_update", "tight_list", "calls"] {
        let package = scratch.0.join(pair);
        fs::create_dir(&package).expect("create temporary benchmark package");
        fs::copy(
            root.join("bench/vs-rust").join(pair).join("main.nl"),
            package.join("main.nl"),
        )
        .expect("copy benchmark source to scratch package");
        let input = package.join("module.ll");
        run(
            Command::new(&selfhost)
                .args(["build", ".", "-o", "module.ll", "--runtime=core"])
                .current_dir(&package),
            &format!("build {pair} with selfhost"),
        );
        let input_ir = fs::read_to_string(&input).expect("read generated LLVM IR");
        assert_raw_alias_tags(pair, &input_ir);
        let optimized = package.join("module.opt.ll");
        run(
            Command::new("clang")
                .args(["-O3", "-S", "-emit-llvm"])
                .arg(&input)
                .arg("-o")
                .arg(&optimized),
            &format!("optimize {pair} IR with clang -O3"),
        );
        let ir = fs::read_to_string(&optimized).expect("read optimized LLVM IR");
        let (context_tag, program_tag) = tbaa_tags(&ir);
        assert_hot_loop_ir(pair, &ir, &context_tag, &program_tag);
    }
}
