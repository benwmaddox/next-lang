use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

use crate::ast::Span;
use crate::emit::{EntryStackReservation, StackContract};
use crate::{checker, emit, lexer, parser, syntax_dump};

static TEMP_ID: AtomicUsize = AtomicUsize::new(0);
const COMPILER_STACK_SIZE: usize = 1024 * 1024 * 1024;
const MAX_PARSE_FILES: usize = 256;
const MAX_PARSE_SOURCE_BYTES: usize = 16 * 1024 * 1024;
const MAX_PARSE_PACKAGE_BYTES: usize = 64 * 1024 * 1024;
const MAX_PARSE_PACKAGE_TOKENS: usize = 4_000_000;
const MAX_PARSE_PACKAGE_NODES: usize = syntax_dump::MAX_TREE_NODES;
const MAX_PARSE_PACKAGE_EDGES: usize = syntax_dump::MAX_TREE_EDGES;
const MAX_PARSE_WORK_UNITS: usize = 72_000_000;

#[derive(Clone, Debug)]
pub struct CompileError {
    pub file: String,
    pub span: Span,
    pub message: String,
}

impl std::fmt::Display for CompileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{}:{}:{}: error: {}",
            self.file, self.span.line, self.span.col, self.message
        )
    }
}

#[derive(Clone, Debug)]
pub struct CompileOutput {
    pub llvm_ir: String,
    pub files: Vec<String>,
    pub tests: Vec<String>,
    pub memory: MemoryReport,
    pub contracts: Vec<StackContract>,
    pub stack_entries: Vec<EntryStackReservation>,
    pub stack_peak_expectations: Vec<StackPeakExpectation>,
    call_graph: Vec<Vec<usize>>,
    recursive_functions: Vec<bool>,
    recursion_budget_bytes: u64,
}

#[derive(Clone, Debug)]
pub struct StackPeakExpectation {
    pub test_index: usize,
    pub function_id: usize,
    pub function_name: String,
    pub limit_bytes: u64,
    pub source: String,
    pub span: Span,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ParseDump {
    pub tokens: String,
    pub tree: String,
}

#[derive(Clone, Debug, Default)]
pub struct MemoryReport {
    pub globals: Vec<GlobalMemory>,
    pub startup_claim_bytes: u64,
    pub job_headroom_bytes: u64,
    pub globals_budget_bytes: u64,
}

#[derive(Clone, Debug)]
pub struct GlobalMemory {
    pub name: String,
    pub offset_bytes: u64,
    pub size_bytes: u64,
}

#[derive(Debug)]
pub enum PackageError {
    Compile(CompileError),
    Tool(String),
}

impl std::fmt::Display for PackageError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PackageError::Compile(error) => error.fmt(f),
            PackageError::Tool(message) => write!(f, "nlc: tool failure: {message}"),
        }
    }
}

pub fn compile_package(package: &Path) -> Result<CompileOutput, CompileError> {
    match compile_package_internal(package, true) {
        Ok(output) => Ok(output),
        Err(PackageError::Compile(error)) => Err(error),
        Err(PackageError::Tool(message)) => Err(CompileError {
            file: package
                .file_name()
                .and_then(|x| x.to_str())
                .unwrap_or("<package>")
                .to_owned(),
            span: Span {
                file: 0,
                line: 1,
                col: 1,
                start_offset: 0,
                end_offset: 0,
            },
            message,
        }),
    }
}

/// Lex and parse a package without type checking. The dumps are deterministic for a
/// given byte-for-byte package and are the reference format for the self-hosted parser.
pub fn parse_package(package: &Path) -> Result<ParseDump, PackageError> {
    std::thread::scope(|scope| {
        std::thread::Builder::new()
            .name("nlc-parse".to_owned())
            .stack_size(COMPILER_STACK_SIZE)
            .spawn_scoped(scope, move || parse_package_on_worker(package))
            .map_err(|error| PackageError::Tool(format!("could not start parser thread: {error}")))?
            .join()
            .map_err(|_| PackageError::Tool("parser thread panicked".to_owned()))?
    })
}

fn parse_package_on_worker(package: &Path) -> Result<ParseDump, PackageError> {
    let entries = fs::read_dir(package)
        .map_err(|e| PackageError::Tool(format!("cannot read package directory: {e}")))?;
    let mut paths = Vec::new();
    for entry in entries {
        let entry =
            entry.map_err(|e| PackageError::Tool(format!("cannot read package entry: {e}")))?;
        let path = entry.path();
        if path.extension().is_some_and(|extension| extension == "nl") && path.is_file() {
            paths.push(path);
        }
    }
    paths.sort();
    if paths.is_empty() {
        return Err(PackageError::Tool(
            "package has no .nl source files".to_owned(),
        ));
    }
    if paths.len() > MAX_PARSE_FILES {
        return Err(parse_limit_error(
            "<package>",
            format!("source file limit of {MAX_PARSE_FILES} per package exceeded"),
        ));
    }

    let mut dump = ParseDump::default();
    let mut package_bytes = 0usize;
    let mut package_tokens = 0usize;
    let mut package_nodes = 0usize;
    let mut package_edges = 0usize;
    for (file_id, path) in paths.into_iter().enumerate() {
        let file = path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("<source>")
            .to_owned();
        let bytes = fs::read(&path).map_err(|error| {
            PackageError::Tool(format!("cannot read source file '{file}': {error}"))
        })?;
        if bytes.len() > MAX_PARSE_SOURCE_BYTES {
            return Err(parse_limit_error(
                &file,
                format!("source byte limit of {MAX_PARSE_SOURCE_BYTES} per file exceeded"),
            ));
        }
        package_bytes = package_bytes.saturating_add(bytes.len());
        if package_bytes > MAX_PARSE_PACKAGE_BYTES {
            return Err(parse_limit_error(
                &file,
                format!("source byte limit of {MAX_PARSE_PACKAGE_BYTES} per package exceeded"),
            ));
        }
        let source = match String::from_utf8(bytes) {
            Ok(source) => source,
            Err(error) => {
                let offset = error.utf8_error().valid_up_to();
                let raw = error.into_bytes();
                let span = invalid_utf8_span(file_id, &raw, offset);
                return Err(PackageError::Compile(CompileError {
                    file,
                    span,
                    message: "source is not valid UTF-8; save the file as UTF-8".to_owned(),
                }));
            }
        };
        let tokens = lexer::lex(&source, file_id).map_err(|error| {
            PackageError::Compile(CompileError {
                file: file.clone(),
                span: error.span,
                message: error.message,
            })
        })?;
        package_tokens = package_tokens.saturating_add(tokens.len());
        if package_tokens > MAX_PARSE_PACKAGE_TOKENS {
            return Err(parse_limit_error(
                &file,
                format!("token limit of {MAX_PARSE_PACKAGE_TOKENS} per package exceeded"),
            ));
        }
        let program = parser::parse(tokens.clone(), &source).map_err(|error| {
            PackageError::Compile(CompileError {
                file: file.clone(),
                span: error.span,
                message: error.message,
            })
        })?;
        let (tree, nodes, edges) =
            syntax_dump::tree_dump(&file, source.len(), &program).map_err(|limit| {
                let message = if limit.edges > MAX_PARSE_PACKAGE_EDGES {
                    format!("child edge limit of {MAX_PARSE_PACKAGE_EDGES} per package exceeded")
                } else if limit.nodes > MAX_PARSE_PACKAGE_NODES {
                    format!("node limit of {MAX_PARSE_PACKAGE_NODES} per package exceeded")
                } else {
                    "tree dump limit exceeded".to_owned()
                };
                parse_limit_error(&file, message)
            })?;
        package_nodes = package_nodes.saturating_add(nodes);
        if package_nodes > MAX_PARSE_PACKAGE_NODES {
            return Err(parse_limit_error(
                &file,
                format!("node limit of {MAX_PARSE_PACKAGE_NODES} per package exceeded"),
            ));
        }
        package_edges = package_edges.saturating_add(edges);
        if package_edges > MAX_PARSE_PACKAGE_EDGES {
            return Err(parse_limit_error(
                &file,
                format!("child edge limit of {MAX_PARSE_PACKAGE_EDGES} per package exceeded"),
            ));
        }
        let work = package_bytes
            .saturating_add(package_tokens)
            .saturating_add(package_nodes)
            .saturating_add(package_edges);
        if work > MAX_PARSE_WORK_UNITS {
            return Err(parse_limit_error(
                &file,
                format!("parse work limit of {MAX_PARSE_WORK_UNITS} units per package exceeded"),
            ));
        }
        dump.tokens
            .push_str(&syntax_dump::token_dump(&file, &source, &tokens));
        dump.tree.push_str(&tree);
    }
    Ok(dump)
}

fn parse_limit_error(file: &str, message: String) -> PackageError {
    PackageError::Compile(CompileError {
        file: file.to_owned(),
        span: Span {
            file: 0,
            line: 1,
            col: 1,
            start_offset: 0,
            end_offset: 0,
        },
        message,
    })
}

fn invalid_utf8_span(file: usize, bytes: &[u8], offset: usize) -> Span {
    let prefix = &bytes[..offset.min(bytes.len())];
    let line = prefix.iter().filter(|byte| **byte == b'\n').count() + 1;
    let last_newline = prefix.iter().rposition(|byte| *byte == b'\n');
    let col = offset.saturating_sub(last_newline.map(|index| index + 1).unwrap_or(0)) + 1;
    Span {
        file,
        line,
        col,
        start_offset: offset,
        end_offset: offset.saturating_add(1),
    }
}

fn compile_package_internal(
    package: &Path,
    require_main: bool,
) -> Result<CompileOutput, PackageError> {
    std::thread::scope(|scope| {
        std::thread::Builder::new()
            .name("nlc-compile".to_owned())
            .stack_size(COMPILER_STACK_SIZE)
            .spawn_scoped(scope, move || {
                compile_package_on_worker(package, require_main)
            })
            .map_err(|error| {
                PackageError::Tool(format!("could not start compiler thread: {error}"))
            })?
            .join()
            .map_err(|_| PackageError::Tool("compiler thread panicked".to_owned()))?
    })
}

fn compile_package_on_worker(
    package: &Path,
    require_main: bool,
) -> Result<CompileOutput, PackageError> {
    let memory_config = read_memory_config(package)?;
    let entries = fs::read_dir(package)
        .map_err(|e| PackageError::Tool(format!("cannot read package directory: {e}")))?;
    let mut paths = Vec::new();
    for entry in entries {
        let entry =
            entry.map_err(|e| PackageError::Tool(format!("cannot read package entry: {e}")))?;
        let path = entry.path();
        if path.extension().is_some_and(|e| e == "nl") && path.is_file() {
            paths.push(path);
        }
    }
    paths.sort();
    if paths.is_empty() {
        return Err(PackageError::Tool(
            "package has no .nl source files".to_owned(),
        ));
    }
    let mut files = Vec::new();
    let mut programs = Vec::new();
    for path in paths {
        let file = path
            .file_name()
            .and_then(|x| x.to_str())
            .unwrap_or("<source>")
            .to_owned();
        let source = fs::read_to_string(&path)
            .map_err(|e| PackageError::Tool(format!("cannot read source file '{}': {e}", file)))?;
        let file_id = files.len();
        let tokens = lexer::lex(&source, file_id).map_err(|e| {
            PackageError::Compile(CompileError {
                file: file.clone(),
                span: e.span,
                message: e.message,
            })
        })?;
        let program = parser::parse(tokens, &source).map_err(|e| {
            PackageError::Compile(CompileError {
                file: file.clone(),
                span: e.span,
                message: e.message,
            })
        })?;
        files.push(file);
        programs.push(program);
    }
    let mut typed = checker::check_package(
        programs,
        files.clone(),
        require_main,
        memory_config.capabilities.clone(),
    )
    .map_err(|e| {
        PackageError::Compile({
            let file = files
                .get(e.span.file)
                .cloned()
                .unwrap_or_else(|| files[0].clone());
            CompileError {
                file,
                span: e.span,
                message: e.message,
            }
        })
    })?;
    typed.job_headroom_bytes = memory_config.job_headroom_bytes;
    typed.globals_budget_bytes = memory_config.globals_budget_bytes;
    typed.recursion_budget_bytes = memory_config.recursion_budget_bytes;
    let function_contracts = emit::stack_contracts(&typed);
    emit::apply_function_type_stack_contracts(&mut typed, &function_contracts);
    let contracts = emit::stack_contracts(&typed);
    let stack_entries = emit::entry_stack_reservations(&typed, &contracts);
    let mut stack_peak_expectations = Vec::new();
    for (test_index, test) in typed.tests.iter().enumerate() {
        collect_stack_peak_expectations(
            &typed.functions[test.function_id].body,
            test_index,
            &mut stack_peak_expectations,
        );
    }
    let memory = MemoryReport {
        globals: typed
            .globals
            .iter()
            .map(|global| GlobalMemory {
                name: global.name.clone(),
                offset_bytes: global.offset,
                size_bytes: global.size_bytes,
            })
            .collect(),
        startup_claim_bytes: typed.global_state_bytes,
        job_headroom_bytes: typed.job_headroom_bytes,
        globals_budget_bytes: typed.globals_budget_bytes,
    };
    let call_graph = typed
        .call_graph
        .iter()
        .map(|edges| edges.iter().map(|edge| edge.target).collect())
        .collect();
    let recursive_functions = typed
        .functions
        .iter()
        .map(|function| function.recursive)
        .collect();
    Ok(CompileOutput {
        llvm_ir: emit::emit(&typed),
        files,
        tests: typed.tests.iter().map(|test| test.name.clone()).collect(),
        memory,
        contracts,
        stack_entries,
        stack_peak_expectations,
        call_graph,
        recursive_functions,
        recursion_budget_bytes: typed.recursion_budget_bytes,
    })
}

fn collect_stack_peak_expectations(
    block: &crate::typed::TBlock,
    test_index: usize,
    output: &mut Vec<StackPeakExpectation>,
) {
    for statement in &block.statements {
        match &statement.kind {
            crate::typed::TStmtKind::Expect { source, kind } => {
                if let crate::typed::TExpectKind::StackPeak {
                    function_id,
                    function_name,
                    limit_bytes,
                } = kind
                {
                    output.push(StackPeakExpectation {
                        test_index,
                        function_id: *function_id,
                        function_name: function_name.clone(),
                        limit_bytes: *limit_bytes,
                        source: source.clone(),
                        span: statement.span,
                    });
                }
            }
            crate::typed::TStmtKind::If {
                then_block,
                else_block,
                ..
            } => {
                collect_stack_peak_expectations(then_block, test_index, output);
                if let Some(other) = else_block {
                    collect_stack_peak_expectations(other, test_index, output);
                }
            }
            crate::typed::TStmtKind::For { body, .. }
            | crate::typed::TStmtKind::ForEach { body, .. }
            | crate::typed::TStmtKind::Block(body) => {
                collect_stack_peak_expectations(body, test_index, output);
            }
            _ => {}
        }
    }
}

pub fn build_package(package: &Path, output: &Path) -> Result<(), PackageError> {
    let compiled = compile_package_internal(package, true)?;
    if let Some(parent) = output.parent().filter(|p| !p.as_os_str().is_empty()) {
        fs::create_dir_all(parent)
            .map_err(|e| PackageError::Tool(format!("cannot create output directory: {e}")))?;
    }
    let temp = TempDir::new()
        .map_err(|e| PackageError::Tool(format!("cannot create temporary directory: {e}")))?;
    let ir = temp.path.join("module.ll");
    fs::write(&ir, &compiled.llvm_ir)
        .map_err(|e| PackageError::Tool(format!("cannot write generated LLVM IR: {e}")))?;
    clang(&ir, output, false, &compiled)
}

pub fn run_package(package: &Path) -> Result<ExitStatus, PackageError> {
    run_package_args(package, &[])
}

pub fn run_package_args(
    package: &Path,
    args: &[std::ffi::OsString],
) -> Result<ExitStatus, PackageError> {
    let compiled = compile_package_internal(package, true)?;
    let temp = TempDir::new()
        .map_err(|e| PackageError::Tool(format!("cannot create temporary directory: {e}")))?;
    let ir = temp.path.join("module.ll");
    let binary = temp.path.join(if cfg!(windows) {
        "program.exe"
    } else {
        "program"
    });
    fs::write(&ir, &compiled.llvm_ir)
        .map_err(|e| PackageError::Tool(format!("cannot write generated LLVM IR: {e}")))?;
    clang(&ir, &binary, false, &compiled)?;
    Command::new(&binary)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .map_err(|e| PackageError::Tool(format!("cannot run native program: {e}")))
}

pub fn test_package(package: &Path) -> Result<u8, PackageError> {
    let compiled = compile_package_internal(package, false)?;
    if compiled.tests.is_empty() {
        println!("0 passed, 0 failed");
        return Ok(0);
    }
    let temp = TempDir::new()
        .map_err(|e| PackageError::Tool(format!("cannot create temporary directory: {e}")))?;
    let ir = temp.path.join("module.ll");
    let binary = temp.path.join(if cfg!(windows) {
        "program.exe"
    } else {
        "program"
    });
    fs::write(&ir, &compiled.llvm_ir)
        .map_err(|e| PackageError::Tool(format!("cannot write generated LLVM IR: {e}")))?;
    let native_frames = if compiled.stack_peak_expectations.is_empty() {
        clang(&ir, &binary, true, &compiled)?;
        None
    } else {
        Some(clang_with_frames(&ir, &binary, true, &compiled)?)
    };
    let native_bounds = native_frames
        .as_ref()
        .map(|frames| native_stack_bounds(&compiled, frames));

    let mut passed = 0usize;
    let mut failed = 0usize;
    for (index, name) in compiled.tests.iter().enumerate() {
        let budget_failures = compiled
            .stack_peak_expectations
            .iter()
            .filter(|expectation| expectation.test_index == index)
            .filter_map(|expectation| {
                let peak = function_stack_peak(
                    &compiled,
                    native_bounds.as_ref().expect("frame sizes were collected"),
                    expectation.function_id,
                );
                (peak >= expectation.limit_bytes).then(|| {
                    format!(
                        "  stack_peak({}) exceeded {} bytes\n",
                        expectation.function_name, expectation.limit_bytes
                    )
                })
            })
            .collect::<Vec<_>>();
        if !budget_failures.is_empty() {
            println!("FAIL {name}");
            for failure in budget_failures {
                print!("{failure}");
            }
            failed += 1;
            io::stdout()
                .flush()
                .map_err(|e| PackageError::Tool(format!("cannot write test status: {e}")))?;
            continue;
        }
        let output = Command::new(&binary)
            .env("NLC_TEST_INDEX", index.to_string())
            .output()
            .map_err(|e| PackageError::Tool(format!("cannot run test '{}': {e}", name)))?;
        if output.status.success() {
            println!("ok   {name}");
            passed += 1;
        } else {
            println!("FAIL {name}");
            failed += 1;
            match output.status.code() {
                Some(70) => println!("  test '{name}' ended with a runtime failure (exit code 70)"),
                Some(code) if code != 1 => println!("  test '{name}' exited with code {code}"),
                None => println!("  test '{name}' terminated abnormally"),
                _ => {}
            }
        }
        io::stdout()
            .flush()
            .map_err(|e| PackageError::Tool(format!("cannot write test status: {e}")))?;
        io::stdout()
            .write_all(&output.stdout)
            .map_err(|e| PackageError::Tool(format!("cannot forward test stdout: {e}")))?;
        io::stdout()
            .flush()
            .map_err(|e| PackageError::Tool(format!("cannot flush forwarded test stdout: {e}")))?;
        io::stderr()
            .write_all(&output.stderr)
            .map_err(|e| PackageError::Tool(format!("cannot forward test stderr: {e}")))?;
    }
    println!("{passed} passed, {failed} failed");
    Ok(if failed == 0 { 0 } else { 1 })
}

pub fn inspect_memory(package: &Path, allow_overcommit: bool) -> Result<(), PackageError> {
    let compiled = compile_package_internal(package, false)?;
    for global in &compiled.memory.globals {
        println!(
            "global {}: {} bytes (offset {}, alignment 8)",
            global.name, global.size_bytes, global.offset_bytes
        );
    }
    println!(
        "startup claim: {} bytes",
        compiled.memory.startup_claim_bytes
    );
    println!("job headroom: {} bytes", compiled.memory.job_headroom_bytes);
    println!(
        "guarantee waived: {}",
        if allow_overcommit { "yes" } else { "no" }
    );
    println!("local storage: excluded from startup claim");
    println!("map/set initialization: 9 bytes per slot (8-byte bucket plus 1-byte occupancy flag)");
    if compiled.memory.startup_claim_bytes > compiled.memory.globals_budget_bytes {
        println!(
            "warning: globals use {} bytes, above globals_budget of {} bytes",
            compiled.memory.startup_claim_bytes, compiled.memory.globals_budget_bytes
        );
    }
    Ok(())
}

pub fn inspect_contracts(package: &Path) -> Result<(), PackageError> {
    let compiled = compile_package_internal(package, false)?;
    for contract in &compiled.contracts {
        println!("function {}", contract.function);
        println!("  byte requirement: {}", contract.byte_requirement);
        if contract.parameters.is_empty() {
            println!("  parameters: none");
        } else {
            for parameter in &contract.parameters {
                println!("  parameter: {parameter}");
            }
        }
        println!("  result placement: {}", contract.result_placement);
    }
    Ok(())
}

pub fn inspect_stacks(package: &Path) -> Result<(), PackageError> {
    let compiled = compile_package_internal(package, false)?;
    let temp = TempDir::new().map_err(|error| {
        PackageError::Tool(format!("cannot create temporary directory: {error}"))
    })?;
    let ir = temp.path.join("module.ll");
    let binary = temp.path.join(if cfg!(windows) {
        "program.exe"
    } else {
        "program"
    });
    fs::write(&ir, &compiled.llvm_ir)
        .map_err(|error| PackageError::Tool(format!("cannot write generated LLVM IR: {error}")))?;
    let frames = clang_with_frames(&ir, &binary, false, &compiled)?;
    let native_bounds = native_stack_bounds(&compiled, &frames);

    for entry in &compiled.stack_entries {
        let contract = compiled
            .contracts
            .get(entry.function_id)
            .ok_or_else(|| PackageError::Tool("entry stack contract is missing".to_owned()))?;
        println!("entry point {}", entry.name);
        match entry.required_bytes {
            Some(bytes) => println!("  data stack worst case: {bytes} bytes"),
            None => println!("  data stack worst case: unbounded"),
        }
        println!(
            "  data stack reservation: {} bytes",
            entry.reservation_bytes
        );
        println!("  data stack touched: measured at runtime (test hook available)");
        let native = native_bounds
            .get(entry.function_id)
            .and_then(Option::as_ref);
        match native {
            Some(bound) => {
                println!("  native stack worst case: {} bytes", bound.bytes);
                println!(
                    "  native stack: {}",
                    if bound.recursive {
                        "recursive"
                    } else {
                        "nonrecursive"
                    }
                );
                if !bound.path.is_empty() {
                    let chain = bound
                        .path
                        .iter()
                        .filter_map(|id| compiled.contracts.get(*id))
                        .map(|contract| contract.function.as_str())
                        .collect::<Vec<_>>()
                        .join(" -> ");
                    println!("  native stack call chain: {chain}");
                }
            }
            None => println!("  native stack worst case: unbounded"),
        }

        let reachable = reachable_functions(&compiled.call_graph, entry.function_id);
        let mut source_lines = Vec::new();
        for function_id in &reachable {
            let Some(function_contract) = compiled.contracts.get(*function_id) else {
                continue;
            };
            if function_contract.span.line > 0 {
                source_lines.push(format_span(&compiled.files, function_contract.span));
            }
            for region in &function_contract.reserved_regions {
                let line = format_span(&compiled.files, region.span);
                source_lines.push(line.clone());
                if region.bytes > 64 * 1024 {
                    println!(
                        "  reserved region over 64 KB: {line} {} ({} bytes)",
                        region.name, region.bytes
                    );
                } else {
                    println!(
                        "  data region: {line} {} ({} bytes)",
                        region.name, region.bytes
                    );
                }
            }
            for loop_bound in &function_contract.loops {
                let line = format_span(&compiled.files, loop_bound.span);
                source_lines.push(line.clone());
                let growth = if loop_bound.growth_bytes_per_iteration == u64::MAX {
                    "unbounded".to_owned()
                } else {
                    format!("{} bytes", loop_bound.growth_bytes_per_iteration)
                };
                let iterations = loop_bound
                    .iteration_limit
                    .map(|count| format!("; at most {count} iterations"))
                    .unwrap_or_else(|| "; iteration limit from the checked input bound".to_owned());
                println!("  loop at {line}: growth per iteration {growth}{iterations}");
            }
            for site in &function_contract.copy_down_sites {
                let line = format_span(&compiled.files, site.span);
                source_lines.push(line.clone());
                println!(
                    "  copy-down site: {line} {} (old and new peak: {} bytes)",
                    site.name, site.bytes
                );
            }
        }
        source_lines.sort();
        source_lines.dedup();
        println!(
            "  source lines driving bound: {}",
            if source_lines.is_empty() {
                "none".to_owned()
            } else {
                source_lines.join(", ")
            }
        );
        if entry.required_bytes.is_none() || native.is_none() {
            println!(
                "  unbounded components: {}",
                if entry.required_bytes.is_none() && native.is_none() {
                    "data and native stack"
                } else if entry.required_bytes.is_none() {
                    "data stack"
                } else {
                    "native stack"
                }
            );
        } else {
            println!("  unbounded components: none");
        }
        if entry.recursive {
            println!(
                "  recursion budget: {} bytes",
                recursion_budget_for_report(&compiled)
            );
        }
        let _ = contract;
    }
    Ok(())
}

fn reachable_functions(graph: &[Vec<usize>], root: usize) -> Vec<usize> {
    fn visit(graph: &[Vec<usize>], function: usize, seen: &mut [bool], result: &mut Vec<usize>) {
        if seen[function] {
            return;
        }
        seen[function] = true;
        result.push(function);
        for target in &graph[function] {
            visit(graph, *target, seen, result);
        }
    }
    let mut result = Vec::new();
    visit(graph, root, &mut vec![false; graph.len()], &mut result);
    result.sort_unstable();
    result
}

fn format_span(files: &[String], span: Span) -> String {
    format!(
        "{}:{}",
        files
            .get(span.file)
            .map(String::as_str)
            .unwrap_or("<source>"),
        span.line
    )
}

fn recursion_budget_for_report(compiled: &CompileOutput) -> u64 {
    const DEFAULT_NATIVE_STACK_BYTES: u64 = 8 * 1024 * 1024;
    const NATIVE_STACK_SAFETY_BYTES: u64 = 80 * 1024;
    if compiled.recursion_budget_bytes == 0 {
        DEFAULT_NATIVE_STACK_BYTES - NATIVE_STACK_SAFETY_BYTES
    } else {
        compiled
            .recursion_budget_bytes
            .min(DEFAULT_NATIVE_STACK_BYTES - NATIVE_STACK_SAFETY_BYTES)
    }
}

fn clang(
    ir: &Path,
    output: &Path,
    test_build: bool,
    compiled: &CompileOutput,
) -> Result<(), PackageError> {
    clang_internal(ir, output, test_build, compiled, false).map(|_| ())
}

fn clang_with_frames(
    ir: &Path,
    output: &Path,
    test_build: bool,
    compiled: &CompileOutput,
) -> Result<std::collections::HashMap<usize, u64>, PackageError> {
    clang_internal(ir, output, test_build, compiled, true)?.ok_or_else(|| {
        PackageError::Tool("optimized native frame sizes were not collected".to_owned())
    })
}

fn clang_internal(
    ir: &Path,
    output: &Path,
    test_build: bool,
    compiled: &CompileOutput,
    collect_native_frames: bool,
) -> Result<Option<std::collections::HashMap<usize, u64>>, PackageError> {
    let runtime = Path::new(env!("CARGO_MANIFEST_DIR")).join("../runtime/nl_runtime.c");
    if !runtime.is_file() {
        return Err(PackageError::Tool(format!(
            "runtime source is missing: {}",
            runtime.display()
        )));
    }
    let optimization = match std::env::var("NLC_OPT_LEVEL").as_deref() {
        Ok("1") | Err(_) => "1",
        Ok("3") => "3",
        Ok(value) => {
            return Err(PackageError::Tool(format!(
                "NLC_OPT_LEVEL must be 1 or 3, got '{value}'"
            )));
        }
    };
    let source = fs::read_to_string(ir)
        .map_err(|error| PackageError::Tool(format!("cannot read generated LLVM IR: {error}")))?;
    if !source.contains("nlc.recursion.targets=") {
        run_clang(
            ir,
            output,
            &runtime,
            test_build,
            optimization,
            collect_native_frames,
        )?;
        return if collect_native_frames {
            read_native_frame_sizes(output).map(Some)
        } else {
            Ok(None)
        };
    }

    let parent = ir.parent().unwrap_or_else(|| Path::new("."));
    let probe = parent.join("nlc-recursion-frame-probe");
    let patched_ir = parent.join("nlc-recursion-final.ll");
    run_clang(ir, &probe, &runtime, test_build, optimization, true)?;
    let mut frames = read_native_frame_sizes(&probe)?;
    for _ in 0..3 {
        let patched = patch_recursion_checks(&source, compiled, &frames)?;
        fs::write(&patched_ir, patched).map_err(|error| {
            PackageError::Tool(format!("cannot write recursion-checked LLVM IR: {error}"))
        })?;
        run_clang(
            &patched_ir,
            output,
            &runtime,
            test_build,
            optimization,
            true,
        )?;
        let final_frames = read_native_frame_sizes(output)?;
        if final_frames == frames {
            return if collect_native_frames {
                Ok(Some(final_frames))
            } else {
                Ok(None)
            };
        }
        frames = final_frames;
    }
    Err(PackageError::Tool(
        "optimized native frame sizes did not stabilize after recursion checks were added"
            .to_owned(),
    ))
}

fn run_clang(
    ir: &Path,
    output: &Path,
    runtime: &Path,
    test_build: bool,
    optimization: &str,
    collect_stack_sizes: bool,
) -> Result<(), PackageError> {
    let mut command = Command::new("clang");
    command.arg(format!("-O{optimization}"));
    if collect_stack_sizes {
        command.arg("-fstack-size-section");
    }
    if test_build {
        command.arg("-DNLC_TEST_BUILD=1");
    }
    let result = command
        .arg(ir)
        .arg(runtime)
        .arg("-o")
        .arg(output)
        .output()
        .map_err(|e| PackageError::Tool(format!("cannot start clang: {e}")))?;
    if !result.status.success() {
        let stderr = String::from_utf8_lossy(&result.stderr);
        return Err(PackageError::Tool(format!(
            "clang failed\n{}",
            stderr.trim_end()
        )));
    }
    Ok(())
}

fn patch_recursion_checks(
    source: &str,
    compiled: &CompileOutput,
    frame_sizes: &std::collections::HashMap<usize, u64>,
) -> Result<String, PackageError> {
    let mut output = String::with_capacity(source.len());
    let mut patched_count = 0usize;
    for line in source.lines() {
        let Some((instruction, comment)) = line.split_once("; nlc.recursion.targets=") else {
            output.push_str(line);
            output.push('\n');
            continue;
        };
        let targets = comment
            .split(',')
            .filter(|target| !target.is_empty())
            .map(|target| {
                target.parse::<usize>().map_err(|error| {
                    PackageError::Tool(format!("invalid recursive target in generated IR: {error}"))
                })
            })
            .collect::<Result<Vec<_>, _>>()?;
        if targets.is_empty() {
            return Err(PackageError::Tool(
                "generated recursion check has no possible target".to_owned(),
            ));
        }
        let required = targets
            .iter()
            .map(|target| {
                native_stack_requirement(
                    *target,
                    compiled,
                    frame_sizes,
                    &mut vec![None; compiled.call_graph.len()],
                    &mut vec![false; compiled.call_graph.len()],
                )
            })
            .max()
            .unwrap_or(0);
        let Some((before, after)) = instruction.split_once("i64 0") else {
            return Err(PackageError::Tool(
                "generated recursion check is missing its frame-size placeholder".to_owned(),
            ));
        };
        output.push_str(before);
        output.push_str(&format!("i64 {required}"));
        output.push_str(after);
        output.push_str("; nlc.recursion.targets=");
        output.push_str(comment);
        output.push('\n');
        patched_count += 1;
    }
    if patched_count == 0 {
        return Err(PackageError::Tool(
            "recursive functions were found but no recursion checks were emitted".to_owned(),
        ));
    }
    Ok(output)
}

fn native_stack_requirement(
    function: usize,
    compiled: &CompileOutput,
    frame_sizes: &std::collections::HashMap<usize, u64>,
    memo: &mut [Option<u64>],
    visiting: &mut [bool],
) -> u64 {
    if let Some(requirement) = memo[function] {
        return requirement;
    }
    if visiting[function] {
        return u64::MAX;
    }
    visiting[function] = true;
    let frame = frame_sizes.get(&function).copied().unwrap_or(u64::MAX);
    let child = compiled.call_graph[function]
        .iter()
        .filter(|target| !compiled.recursive_functions[**target])
        .map(|target| native_stack_requirement(*target, compiled, frame_sizes, memo, visiting))
        .max()
        .unwrap_or(0);
    visiting[function] = false;
    let total = frame
        .saturating_add(128) // return address, alignment and outgoing call temporaries
        .saturating_add(child)
        .saturating_add(64 * 1024); // DESIGN's foreign-call margin, kept on every path
    memo[function] = Some(total);
    total
}

#[derive(Clone, Debug)]
struct NativeStackBound {
    bytes: u64,
    path: Vec<usize>,
    recursive: bool,
}

fn native_stack_bounds(
    compiled: &CompileOutput,
    frame_sizes: &std::collections::HashMap<usize, u64>,
) -> Vec<Option<NativeStackBound>> {
    const DEFAULT_NATIVE_STACK_BYTES: u64 = 8 * 1024 * 1024;
    const NATIVE_STACK_SAFETY_BYTES: u64 = 80 * 1024;
    const NATIVE_HELPER_MARGIN_BYTES: u64 = 64 * 1024;

    fn visit(
        function: usize,
        compiled: &CompileOutput,
        frames: &std::collections::HashMap<usize, u64>,
        recursive_cycle: &[bool],
        recursion_budget: u64,
        memo: &mut [Option<NativeStackBound>],
        visiting: &mut [bool],
    ) -> Option<NativeStackBound> {
        if recursive_cycle[function] {
            return Some(NativeStackBound {
                bytes: recursion_budget,
                path: vec![function],
                recursive: true,
            });
        }
        if let Some(bound) = &memo[function] {
            return Some(bound.clone());
        }
        if visiting[function] {
            return None;
        }
        visiting[function] = true;
        let frame = frames.get(&function).copied()?;
        let mut deepest = NativeStackBound {
            bytes: 0,
            path: Vec::new(),
            recursive: false,
        };
        for target in &compiled.call_graph[function] {
            if let Some(candidate) = visit(
                *target,
                compiled,
                frames,
                recursive_cycle,
                recursion_budget,
                memo,
                visiting,
            ) {
                if candidate.bytes > deepest.bytes {
                    deepest = candidate;
                }
            } else {
                visiting[function] = false;
                return None;
            }
        }
        visiting[function] = false;
        let mut path = vec![function];
        path.extend(deepest.path);
        let bound = NativeStackBound {
            bytes: frame.saturating_add(128).saturating_add(deepest.bytes),
            path,
            recursive: deepest.recursive,
        };
        memo[function] = Some(bound.clone());
        Some(bound)
    }

    let graph = &compiled.call_graph;
    // Marked recursive functions carry T19's run-time budget check even when
    // a particular target set happens not to recurse, so treating each as a
    // budgeted terminal path is conservative and linear in the graph size.
    let recursive_cycle = compiled.recursive_functions.clone();
    let default_recursion = DEFAULT_NATIVE_STACK_BYTES.saturating_sub(NATIVE_STACK_SAFETY_BYTES);
    let recursion_budget = if compiled.recursion_budget_bytes == 0 {
        default_recursion
    } else {
        compiled.recursion_budget_bytes.min(default_recursion)
    };
    let mut memo = vec![None; graph.len()];
    let mut results = Vec::with_capacity(graph.len());
    for function in 0..graph.len() {
        let result = visit(
            function,
            compiled,
            frame_sizes,
            &recursive_cycle,
            recursion_budget,
            &mut memo,
            &mut vec![false; graph.len()],
        )
        .map(|mut bound| {
            bound.bytes = bound.bytes.saturating_add(NATIVE_HELPER_MARGIN_BYTES);
            bound
        });
        results.push(result);
    }
    results
}

fn function_stack_peak(
    compiled: &CompileOutput,
    native_bounds: &[Option<NativeStackBound>],
    function_id: usize,
) -> u64 {
    let data = compiled
        .contracts
        .get(function_id)
        .map(|contract| contract.byte_requirement)
        .unwrap_or(u64::MAX)
        .saturating_add(emit::DATA_STACK_HELPER_MARGIN);
    data.saturating_add(
        native_bounds
            .get(function_id)
            .and_then(Option::as_ref)
            .map(|bound| bound.bytes)
            .unwrap_or(u64::MAX),
    )
}

fn read_native_frame_sizes(
    executable: &Path,
) -> Result<std::collections::HashMap<usize, u64>, PackageError> {
    let bytes = fs::read(executable).map_err(|error| {
        PackageError::Tool(format!(
            "cannot read optimized executable frame data: {error}"
        ))
    })?;
    if bytes.get(0..4) != Some(b"\x7fELF") || bytes.get(4) != Some(&2) || bytes.get(5) != Some(&1) {
        return Err(PackageError::Tool(
            "recursion frame extraction currently requires a 64-bit little-endian ELF executable"
                .to_owned(),
        ));
    }
    let section_offset = read_u64(&bytes, 40)? as usize;
    let section_entry_size = read_u16(&bytes, 58)? as usize;
    let section_count = read_u16(&bytes, 60)? as usize;
    let names_index = read_u16(&bytes, 62)? as usize;
    if section_entry_size < 64 || names_index >= section_count {
        return Err(PackageError::Tool("invalid ELF section table".to_owned()));
    }
    let mut sections = Vec::with_capacity(section_count);
    for index in 0..section_count {
        let offset = section_offset
            .checked_add(index.saturating_mul(section_entry_size))
            .ok_or_else(|| PackageError::Tool("ELF section table offset overflowed".to_owned()))?;
        sections.push(ElfSection {
            name_offset: read_u32(&bytes, offset)? as usize,
            section_type: read_u32(&bytes, offset + 4)?,
            offset: read_u64(&bytes, offset + 24)? as usize,
            size: read_u64(&bytes, offset + 32)? as usize,
            link: read_u32(&bytes, offset + 40)? as usize,
            entry_size: read_u64(&bytes, offset + 56)? as usize,
        });
    }
    let names = section_data(&bytes, &sections[names_index])?;
    let stack_section = sections
        .iter()
        .find(|section| elf_string(names, section.name_offset) == Some(".stack_sizes"))
        .ok_or_else(|| {
            PackageError::Tool(
                "clang did not emit the .stack_sizes section required for recursion".to_owned(),
            )
        })?;
    let stack_data = section_data(&bytes, stack_section)?;
    let mut sizes_by_address = std::collections::HashMap::<u64, u64>::new();
    let mut cursor = 0usize;
    while cursor < stack_data.len() {
        let address = read_u64(stack_data, cursor)?;
        cursor += 8;
        let (size, used) = read_uleb128(stack_data, cursor)?;
        cursor += used;
        sizes_by_address.insert(address, size);
    }
    let symtab = sections
        .iter()
        .find(|section| section.section_type == 2)
        .ok_or_else(|| {
            PackageError::Tool("optimized executable has no ELF symbol table".to_owned())
        })?;
    let strings = sections.get(symtab.link).ok_or_else(|| {
        PackageError::Tool("optimized executable has an invalid symbol string table".to_owned())
    })?;
    let string_data = section_data(&bytes, strings)?;
    let entry_size = if symtab.entry_size >= 24 {
        symtab.entry_size
    } else {
        24
    };
    let mut frame_sizes = std::collections::HashMap::new();
    for offset in (0..symtab.size).step_by(entry_size) {
        if offset + 24 > symtab.size {
            break;
        }
        let symbol_offset = symtab.offset + offset;
        let name_offset = read_u32(&bytes, symbol_offset)? as usize;
        let info = *bytes
            .get(symbol_offset + 4)
            .ok_or_else(|| PackageError::Tool("truncated ELF symbol table".to_owned()))?;
        if info & 0x0f != 2 {
            continue;
        }
        let Some(name) = elf_string(string_data, name_offset) else {
            continue;
        };
        let Some(id) = name
            .strip_prefix("nl_fn_")
            .and_then(|value| value.parse().ok())
        else {
            continue;
        };
        let address = read_u64(&bytes, symbol_offset + 8)?;
        let size = sizes_by_address.get(&address).copied().ok_or_else(|| {
            PackageError::Tool(format!(
                "clang did not report a final stack size for generated function {name}"
            ))
        })?;
        frame_sizes.insert(id, size);
    }
    Ok(frame_sizes)
}

#[derive(Clone, Copy)]
struct ElfSection {
    name_offset: usize,
    section_type: u32,
    offset: usize,
    size: usize,
    link: usize,
    entry_size: usize,
}

fn section_data<'a>(bytes: &'a [u8], section: &ElfSection) -> Result<&'a [u8], PackageError> {
    bytes
        .get(section.offset..section.offset.saturating_add(section.size))
        .ok_or_else(|| PackageError::Tool("ELF section extends past end of file".to_owned()))
}

fn elf_string(bytes: &[u8], offset: usize) -> Option<&str> {
    let tail = bytes.get(offset..)?;
    let end = tail.iter().position(|byte| *byte == 0)?;
    std::str::from_utf8(&tail[..end]).ok()
}

fn read_u16(bytes: &[u8], offset: usize) -> Result<u16, PackageError> {
    let value = bytes
        .get(offset..offset.saturating_add(2))
        .ok_or_else(|| PackageError::Tool("truncated ELF file".to_owned()))?;
    Ok(u16::from_le_bytes([value[0], value[1]]))
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32, PackageError> {
    let value = bytes
        .get(offset..offset.saturating_add(4))
        .ok_or_else(|| PackageError::Tool("truncated ELF file".to_owned()))?;
    Ok(u32::from_le_bytes([value[0], value[1], value[2], value[3]]))
}

fn read_u64(bytes: &[u8], offset: usize) -> Result<u64, PackageError> {
    let value = bytes
        .get(offset..offset.saturating_add(8))
        .ok_or_else(|| PackageError::Tool("truncated ELF file".to_owned()))?;
    Ok(u64::from_le_bytes([
        value[0], value[1], value[2], value[3], value[4], value[5], value[6], value[7],
    ]))
}

fn read_uleb128(bytes: &[u8], offset: usize) -> Result<(u64, usize), PackageError> {
    let mut value = 0u64;
    let mut shift = 0u32;
    for index in 0..10usize {
        let byte = *bytes
            .get(offset + index)
            .ok_or_else(|| PackageError::Tool("truncated .stack_sizes entry".to_owned()))?;
        let payload = (byte & 0x7f) as u64;
        if shift >= 64 && payload != 0 {
            return Err(PackageError::Tool(
                "invalid .stack_sizes ULEB128 value".to_owned(),
            ));
        }
        value |= payload.checked_shl(shift).unwrap_or(0);
        if byte & 0x80 == 0 {
            return Ok((value, index + 1));
        }
        shift += 7;
    }
    Err(PackageError::Tool(
        "invalid .stack_sizes ULEB128 value".to_owned(),
    ))
}

#[derive(Clone)]
struct MemoryConfig {
    job_headroom_bytes: u64,
    globals_budget_bytes: u64,
    recursion_budget_bytes: u64,
    capabilities: std::collections::HashSet<String>,
}

fn read_memory_config(package: &Path) -> Result<MemoryConfig, PackageError> {
    let path = package.join("package.toml");
    let contents = match fs::read_to_string(&path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(MemoryConfig {
                job_headroom_bytes: 256 * 1024 * 1024,
                globals_budget_bytes: 64 * 1024 * 1024,
                recursion_budget_bytes: 0,
                capabilities: ["out".to_owned()].into_iter().collect(),
            });
        }
        Err(error) => {
            return Err(PackageError::Tool(format!(
                "cannot read package manifest '{}': {error}",
                path.display()
            )));
        }
    };
    let mut config = MemoryConfig {
        job_headroom_bytes: 256 * 1024 * 1024,
        globals_budget_bytes: 64 * 1024 * 1024,
        recursion_budget_bytes: 0,
        capabilities: ["out".to_owned()].into_iter().collect(),
    };
    let mut capabilities_seen = false;
    for (line_number, line) in contents.lines().enumerate() {
        let line = line.split('#').next().unwrap_or("").trim();
        if line.is_empty() || (line.starts_with('[') && line.ends_with(']')) {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        if key == "capabilities" {
            if capabilities_seen {
                return Err(PackageError::Tool(format!(
                    "{}:{}: capabilities is listed more than once",
                    path.display(),
                    line_number + 1
                )));
            }
            capabilities_seen = true;
            config.capabilities.clear();
            let value = value.trim();
            let Some(items) = value
                .strip_prefix('[')
                .and_then(|value| value.strip_suffix(']'))
            else {
                return Err(PackageError::Tool(format!(
                    "{}:{}: expected capabilities to be an array such as [\"fs\", \"out\"]",
                    path.display(),
                    line_number + 1
                )));
            };
            for item in items
                .split(',')
                .map(str::trim)
                .filter(|item| !item.is_empty())
            {
                let Some(capability) = item
                    .strip_prefix('"')
                    .and_then(|item| item.strip_suffix('"'))
                else {
                    return Err(PackageError::Tool(format!(
                        "{}:{}: capability names must be quoted strings",
                        path.display(),
                        line_number + 1
                    )));
                };
                if !matches!(capability, "fs" | "out" | "env") {
                    return Err(PackageError::Tool(format!(
                        "{}:{}: unknown capability '{}'; capabilities currently supports fs, out, and env",
                        path.display(),
                        line_number + 1,
                        capability
                    )));
                }
                if !config.capabilities.insert(capability.to_owned()) {
                    return Err(PackageError::Tool(format!(
                        "{}:{}: capability '{}' is listed more than once",
                        path.display(),
                        line_number + 1,
                        capability
                    )));
                }
            }
            continue;
        }
        if key != "job_headroom" && key != "globals_budget" && key != "recursion_budget" {
            continue;
        }
        let bytes = parse_manifest_memory(value.trim()).ok_or_else(|| {
            PackageError::Tool(format!(
                "{}:{}: expected {} to be a nonnegative byte count or MB value",
                path.display(),
                line_number + 1,
                key
            ))
        })?;
        match key {
            "job_headroom" => config.job_headroom_bytes = bytes,
            "globals_budget" => config.globals_budget_bytes = bytes,
            "recursion_budget" => config.recursion_budget_bytes = bytes,
            _ => unreachable!(),
        }
    }
    Ok(config)
}

fn parse_manifest_memory(value: &str) -> Option<u64> {
    let value = value.replace('_', "");
    let value = value.trim();
    let (number, multiplier) = if let Some(number) = value.strip_suffix("GiB") {
        (number, 1024u64 * 1024 * 1024)
    } else if let Some(number) = value.strip_suffix("KiB") {
        (number, 1024u64)
    } else if let Some(number) = value.strip_suffix("KB") {
        (number, 1000u64)
    } else if let Some(number) = value.strip_suffix("GB") {
        (number, 1000u64 * 1000 * 1000)
    } else if let Some(number) = value.strip_suffix("MiB") {
        (number, 1024u64 * 1024)
    } else if let Some(number) = value.strip_suffix("MB") {
        (number, 1000u64 * 1000)
    } else if let Some(number) = value.strip_suffix('B') {
        (number, 1)
    } else {
        (value, 1024u64 * 1024)
    };
    number.trim().parse::<u64>().ok()?.checked_mul(multiplier)
}

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new() -> io::Result<Self> {
        let base = std::env::temp_dir();
        for _ in 0..100 {
            let id = TEMP_ID.fetch_add(1, Ordering::Relaxed);
            let path = base.join(format!("next-lang-{}-{id}", std::process::id()));
            match fs::create_dir(&path) {
                Ok(()) => return Ok(Self { path }),
                Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "could not allocate a unique temporary directory",
        ))
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}
