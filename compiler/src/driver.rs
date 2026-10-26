use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

use crate::ast::{Program, Span};
use crate::emit::{EntryStackReservation, StackContract};
use crate::typed::{TTypeKind, Ty, base_type, growing_collection_lanes};
use crate::{checker, emit, lexer, parser, syntax_dump, tree_reader};

// Rust's print macros panic on a broken pipe. CLI output is optional once a
// caller has closed its reader, so these wrappers drop stdout write errors.
macro_rules! println {
    () => {{
        let _ = writeln!(io::stdout().lock());
    }};
    ($($arg:tt)*) => {{
        let _ = writeln!(io::stdout().lock(), $($arg)*);
    }};
}

macro_rules! print {
    ($($arg:tt)*) => {{
        let _ = write!(io::stdout().lock(), $($arg)*);
    }};
}

static TEMP_ID: AtomicUsize = AtomicUsize::new(0);
const COMPILER_STACK_SIZE: usize = 1024 * 1024 * 1024;
const MAX_SOURCE_FILES: usize = 256;
const MAX_SOURCE_BYTES_PER_FILE: usize = 16 * 1024 * 1024;
const MAX_SOURCE_BYTES_PER_PACKAGE: usize = 64 * 1024 * 1024;
const MAX_PACKAGE_TOKENS: usize = 4_000_000;
const MAX_PACKAGE_NODES: usize = syntax_dump::MAX_TREE_NODES;
const MAX_PACKAGE_EDGES: usize = syntax_dump::MAX_TREE_EDGES;
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
    stack_mode: StackMode,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum StackMode {
    Pointer,
    Offset,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum BuildKind {
    Program,
    Test,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum LinkRuntime {
    C,
    Core,
}

struct LinkDescription<'a> {
    build_kind: BuildKind,
    stack_mode: StackMode,
    runtime: LinkRuntime,
    optimization: String,
    recursion: Option<&'a CompileOutput>,
}

struct LinkIrMetadata {
    build_kind: BuildKind,
    stack_mode: StackMode,
    runtime: LinkRuntime,
    tests: Vec<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Frontend {
    Rust,
    Selfhost,
}

impl Frontend {
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "rust" => Ok(Self::Rust),
            "selfhost" => Ok(Self::Selfhost),
            _ => Err(format!("front end must be rust or selfhost, got '{value}'")),
        }
    }

    pub fn from_environment() -> Result<Self, String> {
        match std::env::var("NLC_FRONTEND") {
            Ok(value) => Self::parse(&value),
            Err(std::env::VarError::NotPresent) => Ok(Self::Rust),
            Err(std::env::VarError::NotUnicode(_)) => {
                Err("NLC_FRONTEND must be valid UTF-8: rust or selfhost".to_owned())
            }
        }
    }
}

impl StackMode {
    fn from_environment() -> Result<Self, String> {
        match std::env::var("NLC_STACK_MODE") {
            Ok(value) if value == "pointer" => Ok(Self::Pointer),
            Ok(value) if value == "offset" => Ok(Self::Offset),
            Ok(value) => Err(format!(
                "NLC_STACK_MODE must be pointer or offset, got '{value}'"
            )),
            Err(std::env::VarError::NotPresent) => Ok(Self::Pointer),
            Err(std::env::VarError::NotUnicode(_)) => {
                Err("NLC_STACK_MODE must be valid UTF-8: pointer or offset".to_owned())
            }
        }
    }

    fn is_offset(self) -> bool {
        self == Self::Offset
    }
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

struct ParsedFile {
    name: String,
    source: String,
    tokens: Vec<lexer::Token>,
    program: Option<Program>,
    tree: Option<String>,
}

#[derive(Clone, Debug, Default)]
pub struct MemoryReport {
    pub globals: Vec<GlobalMemory>,
    pub collection_lanes: Vec<CollectionLaneMemory>,
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

#[derive(Clone, Debug)]
pub struct CollectionLaneMemory {
    pub collection: String,
    pub field: String,
    pub value_type: String,
    pub capacity: usize,
    pub before_bytes_per_element: usize,
    pub after_bytes_per_element: usize,
    pub inline_bytes: Option<usize>,
    pub size_classes: Vec<usize>,
}

#[derive(Debug)]
pub enum PackageError {
    Compile(CompileError),
    Tool(String),
}

fn stdout_write_all(bytes: &[u8], operation: &str) -> Result<(), PackageError> {
    match io::stdout().write_all(bytes) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => Ok(()),
        Err(error) => Err(PackageError::Tool(format!("{operation}: {error}"))),
    }
}

fn stdout_flush(operation: &str) -> Result<(), PackageError> {
    match io::stdout().flush() {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => Ok(()),
        Err(error) => Err(PackageError::Tool(format!("{operation}: {error}"))),
    }
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
    let frontend = Frontend::from_environment().map_err(|message| CompileError {
        file: package
            .file_name()
            .and_then(|name| name.to_str())
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
    })?;
    compile_package_with_frontend(package, frontend)
}

pub fn compile_package_with_frontend(
    package: &Path,
    frontend: Frontend,
) -> Result<CompileOutput, CompileError> {
    match compile_package_internal(package, true, frontend, None) {
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
    let frontend = Frontend::from_environment().map_err(PackageError::Tool)?;
    parse_package_with_frontend(package, frontend)
}

pub fn parse_package_with_frontend(
    package: &Path,
    frontend: Frontend,
) -> Result<ParseDump, PackageError> {
    std::thread::scope(|scope| {
        std::thread::Builder::new()
            .name("nlc-parse".to_owned())
            .stack_size(COMPILER_STACK_SIZE)
            .spawn_scoped(scope, move || package_dump_on_worker(package, frontend))
            .map_err(|error| PackageError::Tool(format!("could not start parser thread: {error}")))?
            .join()
            .map_err(|_| PackageError::Tool("parser thread panicked".to_owned()))?
    })
}

/// Lex a package with the same input policy as every other command. Parsing is
/// also required to enforce the shared tree, work, and nesting limits.
pub fn lex_package(package: &Path) -> Result<String, PackageError> {
    let frontend = Frontend::from_environment().map_err(PackageError::Tool)?;
    lex_package_with_frontend(package, frontend)
}

pub fn lex_package_with_frontend(
    package: &Path,
    frontend: Frontend,
) -> Result<String, PackageError> {
    std::thread::scope(|scope| {
        std::thread::Builder::new()
            .name("nlc-lex".to_owned())
            .stack_size(COMPILER_STACK_SIZE)
            .spawn_scoped(scope, move || lex_dump_on_worker(package, frontend))
            .map_err(|error| PackageError::Tool(format!("could not start lexer thread: {error}")))?
            .join()
            .map_err(|_| PackageError::Tool("lexer thread panicked".to_owned()))?
    })
}

fn package_dump_on_worker(package: &Path, frontend: Frontend) -> Result<ParseDump, PackageError> {
    let files = load_package(package, frontend)?;
    let mut dump = ParseDump::default();
    for file in files {
        dump.tokens.push_str(&syntax_dump::token_dump(
            &file.name,
            &file.source,
            &file.tokens,
        ));
        let tree = match file.tree {
            Some(tree) => tree,
            None => {
                syntax_dump::tree_dump(
                    &file.name,
                    file.source.len(),
                    file.program
                        .as_ref()
                        .expect("strict package parsing yields a program"),
                )
                .map_err(|_| {
                    PackageError::Tool("syntax tree exceeds the Rust tree dump limits".to_owned())
                })?
                .0
            }
        };
        dump.tree.push_str(&tree);
    }
    Ok(dump)
}

fn load_package(package: &Path, frontend: Frontend) -> Result<Vec<ParsedFile>, PackageError> {
    if frontend == Frontend::Selfhost {
        return run_selfhost_tree(package).map(|files| {
            files
                .into_iter()
                .map(|file| ParsedFile {
                    name: file.name,
                    source: file.source,
                    tokens: file.tokens,
                    program: Some(file.program),
                    tree: None,
                })
                .collect()
        });
    }

    load_rust_package(package, false)
}

fn lex_dump_on_worker(package: &Path, frontend: Frontend) -> Result<String, PackageError> {
    if frontend == Frontend::Selfhost {
        return run_selfhost_lex_dump(package);
    }
    let files = load_rust_package(package, true)?;
    let mut tokens = String::new();
    for file in files {
        tokens.push_str(&syntax_dump::token_dump(
            &file.name,
            &file.source,
            &file.tokens,
        ));
    }
    Ok(tokens)
}

fn load_rust_package(
    package: &Path,
    ignore_parse_errors: bool,
) -> Result<Vec<ParsedFile>, PackageError> {
    let entries = fs::read_dir(package)
        .map_err(|e| PackageError::Tool(format!("cannot read package directory: {e}")))?;
    let package_root = fs::canonicalize(package)
        .map_err(|e| PackageError::Tool(format!("cannot resolve package directory: {e}")))?
        .parent()
        .ok_or_else(|| PackageError::Tool("package directory has no parent".to_owned()))?
        .to_owned();
    let mut paths = Vec::new();
    for entry in entries {
        let entry =
            entry.map_err(|e| PackageError::Tool(format!("cannot read package entry: {e}")))?;
        let path = entry.path();
        if path.extension().is_some_and(|extension| extension == "nl")
            && path.is_file()
            && fs::canonicalize(&path).is_ok_and(|target| target.starts_with(&package_root))
        {
            paths.push(path);
        }
    }
    paths.sort();
    if paths.is_empty() {
        return Err(PackageError::Tool(
            "package has no .nl source files".to_owned(),
        ));
    }
    if paths.len() > MAX_SOURCE_FILES {
        return Err(parse_limit_error(
            "<package>",
            format!("source file limit of {MAX_SOURCE_FILES} per package exceeded"),
        ));
    }

    let mut files = Vec::with_capacity(paths.len());
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
        if bytes.len() > MAX_SOURCE_BYTES_PER_FILE {
            return Err(parse_limit_error(
                &file,
                format!("source byte limit of {MAX_SOURCE_BYTES_PER_FILE} per file exceeded"),
            ));
        }
        package_bytes = package_bytes.saturating_add(bytes.len());
        if package_bytes > MAX_SOURCE_BYTES_PER_PACKAGE {
            return Err(parse_limit_error(
                &file,
                format!("source byte limit of {MAX_SOURCE_BYTES_PER_PACKAGE} per package exceeded"),
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
        if package_tokens > MAX_PACKAGE_TOKENS {
            return Err(parse_limit_error(
                &file,
                format!("token limit of {MAX_PACKAGE_TOKENS} per package exceeded"),
            ));
        }
        let program = match parser::parse(tokens.clone(), &source) {
            Ok(program) => Some(program),
            Err(error) if ignore_parse_errors && !is_parser_nesting_limit(&error.message) => None,
            Err(error) => {
                return Err(PackageError::Compile(CompileError {
                    file: file.clone(),
                    span: error.span,
                    message: error.message,
                }));
            }
        };
        let tree = if let Some(program) = program.as_ref() {
            let (tree, nodes, edges) = syntax_dump::tree_dump(&file, source.len(), program)
                .map_err(|limit| {
                    let message = if limit.edges > MAX_PACKAGE_EDGES {
                        format!("child edge limit of {MAX_PACKAGE_EDGES} per package exceeded")
                    } else if limit.nodes > MAX_PACKAGE_NODES {
                        format!("node limit of {MAX_PACKAGE_NODES} per package exceeded")
                    } else {
                        "tree dump limit exceeded".to_owned()
                    };
                    parse_limit_error(&file, message)
                })?;
            package_nodes = package_nodes.saturating_add(nodes);
            if package_nodes > MAX_PACKAGE_NODES {
                return Err(parse_limit_error(
                    &file,
                    format!("node limit of {MAX_PACKAGE_NODES} per package exceeded"),
                ));
            }
            package_edges = package_edges.saturating_add(edges);
            if package_edges > MAX_PACKAGE_EDGES {
                return Err(parse_limit_error(
                    &file,
                    format!("child edge limit of {MAX_PACKAGE_EDGES} per package exceeded"),
                ));
            }
            let work = package_bytes
                .saturating_add(package_tokens)
                .saturating_add(package_nodes)
                .saturating_add(package_edges);
            if work > MAX_PARSE_WORK_UNITS {
                return Err(parse_limit_error(
                    &file,
                    format!(
                        "parse work limit of {MAX_PARSE_WORK_UNITS} units per package exceeded"
                    ),
                ));
            }
            Some(tree)
        } else {
            None
        };
        files.push(ParsedFile {
            name: file,
            source,
            tokens,
            program,
            tree,
        });
    }
    Ok(files)
}

fn is_parser_nesting_limit(message: &str) -> bool {
    matches!(
        message,
        "expression nesting limit of 1000 exceeded"
            | "type nesting limit of 1000 exceeded"
            | "block nesting limit of 1000 exceeded"
    )
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
    frontend: Frontend,
    stack_mode_override: Option<StackMode>,
) -> Result<CompileOutput, PackageError> {
    std::thread::scope(|scope| {
        std::thread::Builder::new()
            .name("nlc-compile".to_owned())
            .stack_size(COMPILER_STACK_SIZE)
            .spawn_scoped(scope, move || {
                compile_package_on_worker(package, require_main, frontend, stack_mode_override)
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
    frontend: Frontend,
    stack_mode_override: Option<StackMode>,
) -> Result<CompileOutput, PackageError> {
    let stack_mode = match stack_mode_override {
        Some(mode) => mode,
        None => StackMode::from_environment().map_err(|message| {
            PackageError::Compile(CompileError {
                file: package
                    .file_name()
                    .and_then(|name| name.to_str())
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
            })
        })?,
    };
    let parsed_files = load_package(package, frontend)?;
    let files = parsed_files
        .iter()
        .map(|file| file.name.clone())
        .collect::<Vec<_>>();
    let programs = parsed_files
        .into_iter()
        .map(|file| {
            file.program
                .expect("strict package loading yields a program")
        })
        .collect::<Vec<_>>();
    let memory_config = read_memory_config(package)?;
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
    if stack_mode.is_offset() {
        if let Some(reason) = emit::offset_spike_unsupported_reason(&typed, &contracts) {
            return Err(PackageError::Compile(CompileError {
                file: files
                    .first()
                    .cloned()
                    .unwrap_or_else(|| "<package>".to_owned()),
                span: Span {
                    file: 0,
                    line: 1,
                    col: 1,
                    start_offset: 0,
                    end_offset: 0,
                },
                message: format!("not supported in offset stack mode: {reason}"),
            }));
        }
    }
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
        collection_lanes: collection_lane_memory(&typed.types),
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
    let llvm_ir = if stack_mode.is_offset() {
        emit::emit_with_stack_mode(&typed, true)
    } else {
        emit::emit(&typed)
    };
    Ok(CompileOutput {
        llvm_ir,
        files,
        tests: typed.tests.iter().map(|test| test.name.clone()).collect(),
        memory,
        contracts,
        stack_entries,
        stack_peak_expectations,
        call_graph,
        recursive_functions,
        recursion_budget_bytes: typed.recursion_budget_bytes,
        stack_mode,
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
    let frontend = Frontend::from_environment().map_err(PackageError::Tool)?;
    build_package_with_frontend(package, output, frontend)
}

pub fn build_package_with_frontend(
    package: &Path,
    output: &Path,
    frontend: Frontend,
) -> Result<(), PackageError> {
    let compiled = compile_package_internal(package, true, frontend, None)?;
    if let Some(parent) = output.parent().filter(|p| !p.as_os_str().is_empty()) {
        fs::create_dir_all(parent)
            .map_err(|e| PackageError::Tool(format!("cannot create output directory: {e}")))?;
    }
    let temp = TempDir::new()
        .map_err(|e| PackageError::Tool(format!("cannot create temporary directory: {e}")))?;
    let ir = temp.path.join("module.ll");
    fs::write(&ir, &compiled.llvm_ir)
        .map_err(|e| PackageError::Tool(format!("cannot write generated LLVM IR: {e}")))?;
    clang(&ir, output, false, &compiled)?;
    for contract in &compiled.contracts {
        for site in &contract.copy_down_sites {
            let file = compiled
                .files
                .get(site.span.file)
                .map(String::as_str)
                .unwrap_or("<source>");
            eprintln!(
                "{file}:{}:{}: note: assignment to '{}' in '{}' uses a {}-byte copy-down temporary ({} bytes while the old value is live); pass it as a 'grow' or 'write' parameter and return it to update in place",
                site.span.line,
                site.span.col,
                site.name,
                contract.function,
                site.bytes / 2,
                site.bytes,
            );
        }
    }
    Ok(())
}

pub fn run_package(package: &Path) -> Result<ExitStatus, PackageError> {
    run_package_args(package, &[])
}

pub fn run_package_args(
    package: &Path,
    args: &[std::ffi::OsString],
) -> Result<ExitStatus, PackageError> {
    let frontend = Frontend::from_environment().map_err(PackageError::Tool)?;
    run_package_args_with_frontend(package, args, frontend)
}

pub fn run_package_args_with_frontend(
    package: &Path,
    args: &[std::ffi::OsString],
    frontend: Frontend,
) -> Result<ExitStatus, PackageError> {
    let compiled = compile_package_internal(package, true, frontend, None)?;
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
    let frontend = Frontend::from_environment().map_err(PackageError::Tool)?;
    test_package_with_frontend(package, frontend)
}

pub fn test_package_with_frontend(package: &Path, frontend: Frontend) -> Result<u8, PackageError> {
    let compiled = compile_package_internal(package, false, frontend, None)?;
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

    let mut budget_failures = vec![Vec::new(); compiled.tests.len()];
    for (index, _name) in compiled.tests.iter().enumerate() {
        let messages = compiled
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
        budget_failures[index] = messages;
    }
    run_test_cases(&binary, &compiled.tests, &budget_failures)
}

/// Link an LLVM module emitted by the self-hosted compiler.  The metadata is
/// parsed before clang is started so malformed or future IR versions fail as
/// tool errors rather than reaching the native toolchain.
pub fn link_ir(ir: &Path, output: &Path) -> Result<(), PackageError> {
    let metadata = read_link_ir_metadata(ir)?;
    let link = LinkDescription {
        build_kind: metadata.build_kind,
        stack_mode: metadata.stack_mode,
        runtime: metadata.runtime,
        optimization: optimization_level()?,
        recursion: None,
    };
    clang_internal(ir, output, &link, false).map(|_| ())
}

/// Run the tests described in a self-hosted test module.  An empty test list
/// is intentionally handled without invoking clang, matching `nlc test`.
pub fn test_ir(ir: &Path) -> Result<u8, PackageError> {
    let metadata = read_link_ir_metadata(ir)?;
    if metadata.build_kind != BuildKind::Test {
        return Err(PackageError::Tool(
            "test-ir requires an IR file built with --test".to_owned(),
        ));
    }
    if metadata.tests.is_empty() {
        println!("0 passed, 0 failed");
        return Ok(0);
    }
    let temp = TempDir::new()
        .map_err(|error| PackageError::Tool(format!("cannot create temporary directory: {error}")))?;
    let binary = temp.path.join(if cfg!(windows) {
        "program.exe"
    } else {
        "program"
    });
    let link = LinkDescription {
        build_kind: metadata.build_kind,
        stack_mode: metadata.stack_mode,
        runtime: metadata.runtime,
        optimization: optimization_level()?,
        recursion: None,
    };
    clang_internal(ir, &binary, &link, false)?;
    let budget_failures = vec![Vec::new(); metadata.tests.len()];
    run_test_cases(&binary, &metadata.tests, &budget_failures)
}

fn run_test_cases(
    binary: &Path,
    names: &[String],
    budget_failures: &[Vec<String>],
) -> Result<u8, PackageError> {
    let mut passed = 0usize;
    let mut failed = 0usize;
    for (index, name) in names.iter().enumerate() {
        let messages = budget_failures.get(index).map(Vec::as_slice).unwrap_or(&[]);
        if !messages.is_empty() {
            println!("FAIL {name}");
            for failure in messages {
                print!("{failure}");
            }
            failed += 1;
            stdout_flush("cannot write test status")?;
            continue;
        }
        let output = Command::new(binary)
            .env("NLC_TEST_INDEX", index.to_string())
            .output()
            .map_err(|error| PackageError::Tool(format!("cannot run test '{}': {error}", name)))?;
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
        stdout_flush("cannot write test status")?;
        stdout_write_all(&output.stdout, "cannot forward test stdout")?;
        stdout_flush("cannot flush forwarded test stdout")?;
        io::stderr()
            .write_all(&output.stderr)
            .map_err(|error| PackageError::Tool(format!("cannot forward test stderr: {error}")))?;
    }
    println!("{passed} passed, {failed} failed");
    Ok(if failed == 0 { 0 } else { 1 })
}

pub fn inspect_memory(package: &Path, allow_overcommit: bool) -> Result<(), PackageError> {
    let frontend = Frontend::from_environment().map_err(PackageError::Tool)?;
    let compiled = compile_package_internal(package, false, frontend, None)?;
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
    if !compiled.memory.collection_lanes.is_empty() {
        println!("collection text lanes (before -> after, bytes per element):");
        for lane in &compiled.memory.collection_lanes {
            print!(
                "  {}.{} ({}; capacity {}): {} -> {}",
                lane.collection,
                lane.field,
                lane.value_type,
                lane.capacity,
                lane.before_bytes_per_element,
                lane.after_bytes_per_element
            );
            if let Some(inline_bytes) = lane.inline_bytes {
                print!(", inline bytes {inline_bytes}");
            } else {
                print!(", slot classes {:?}", lane.size_classes);
            }
            println!(" bytes/element");
        }
    }
    if compiled.memory.startup_claim_bytes > compiled.memory.globals_budget_bytes {
        println!(
            "warning: globals use {} bytes, above globals_budget of {} bytes",
            compiled.memory.startup_claim_bytes, compiled.memory.globals_budget_bytes
        );
    }
    Ok(())
}

fn collection_lane_memory(types: &[crate::typed::TType]) -> Vec<CollectionLaneMemory> {
    let mut report = Vec::new();
    for (id, definition) in types.iter().enumerate() {
        let (element, capacity, map_or_set_key) = match &definition.kind {
            TTypeKind::Array { element, capacity }
            | TTypeKind::List { element, capacity }
            | TTypeKind::Queue { element, capacity }
            | TTypeKind::Ring { element, capacity }
            | TTypeKind::Grid {
                element, capacity, ..
            }
            | TTypeKind::Pool {
                element, capacity, ..
            } => (Some(*element), *capacity, None),
            TTypeKind::Map {
                key,
                value,
                capacity,
            } => (Some(*value), *capacity, Some(*key)),
            TTypeKind::Set { key, capacity } => (None, *capacity, Some(*key)),
            _ => continue,
        };
        if capacity == 0 {
            continue;
        }
        if let Some(element) = element {
            for lane in growing_collection_lanes(Ty(id), types).unwrap_or_default() {
                let (field, element_ty) = match &types[element.0].kind {
                    TTypeKind::Struct(fields) => (
                        fields
                            .get(lane.lane)
                            .map(|field| field.name.clone())
                            .unwrap_or_else(|| format!("lane{}", lane.lane)),
                        lane.ty,
                    ),
                    _ => ("element".to_owned(), lane.ty),
                };
                if let Some(memory) = collection_string_lane_memory(
                    &definition.name,
                    field,
                    element_ty,
                    capacity,
                    lane.max_bytes,
                    lane.class_bytes,
                    types,
                ) {
                    report.push(memory);
                }
            }
        }
        if let Some(key) = map_or_set_key {
            let key_ty = base_type(key, types);
            if let TTypeKind::Ascii { max_bytes } = &types[key_ty.0].kind {
                report.push(CollectionLaneMemory {
                    collection: definition.name.clone(),
                    field: "key".to_owned(),
                    value_type: format!("Ascii max {max_bytes}"),
                    capacity,
                    before_bytes_per_element: 16 + max_bytes,
                    after_bytes_per_element: 8 + max_bytes,
                    inline_bytes: Some(*max_bytes),
                    size_classes: Vec::new(),
                });
            }
        }
    }
    report
}

fn collection_string_lane_memory(
    collection: &str,
    field: String,
    ty: Ty,
    capacity: usize,
    max_bytes: usize,
    size_classes: Vec<usize>,
    types: &[crate::typed::TType],
) -> Option<CollectionLaneMemory> {
    let base = base_type(ty, types);
    let (value_type, descriptor_bytes, compact_descriptor_bytes) = match &types[base.0].kind {
        TTypeKind::Ascii { .. } => ("Ascii", 16usize, 8usize),
        TTypeKind::Bytes { .. } => ("Bytes", 16usize, 8usize),
        TTypeKind::Text { .. } => ("Text", 24usize, 16usize),
        _ => return None,
    };
    let inline = max_bytes <= 64;
    Some(CollectionLaneMemory {
        collection: collection.to_owned(),
        field,
        value_type: format!("{value_type} max {max_bytes}"),
        capacity,
        before_bytes_per_element: descriptor_bytes + usize::from(inline) * max_bytes,
        after_bytes_per_element: if inline {
            compact_descriptor_bytes + max_bytes
        } else {
            descriptor_bytes
        },
        inline_bytes: inline.then_some(max_bytes),
        size_classes,
    })
}

pub fn inspect_contracts(package: &Path) -> Result<(), PackageError> {
    let frontend = Frontend::from_environment().map_err(PackageError::Tool)?;
    let compiled = compile_package_internal(package, false, frontend, None)?;
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
    let frontend = Frontend::from_environment().map_err(PackageError::Tool)?;
    let compiled = compile_package_internal(package, false, frontend, None)?;
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

        if let Some(reported) = entry.required_bytes {
            let chain = entry
                .critical_path
                .iter()
                .filter_map(|id| compiled.contracts.get(*id))
                .map(|contract| contract.function.as_str())
                .collect::<Vec<_>>()
                .join(" -> ");
            println!("  data stack critical path: {chain}");

            let mut attributed = 0u64;
            for function_id in &entry.critical_path {
                let Some(function_contract) = compiled.contracts.get(*function_id) else {
                    return Err(PackageError::Tool(
                        "data-stack critical path references a missing function".to_owned(),
                    ));
                };
                let local_regions = function_contract
                    .local_regions
                    .iter()
                    .try_fold(0u64, |sum, region| sum.checked_add(region.bytes))
                    .ok_or_else(|| {
                        PackageError::Tool(
                            "data-stack critical path region total overflowed".to_owned(),
                        )
                    })?;
                if local_regions != function_contract.local_requirement {
                    return Err(PackageError::Tool(format!(
                        "data-stack attribution for '{}' lists {local_regions} local bytes, but the contract requires {}",
                        function_contract.function, function_contract.local_requirement
                    )));
                }
                for region in &function_contract.local_regions {
                    let line = format_span(&compiled.files, region.span);
                    println!(
                        "  critical path contribution: {line} {}.{} ({} bytes)",
                        function_contract.function, region.name, region.bytes
                    );
                    attributed = attributed.checked_add(region.bytes).ok_or_else(|| {
                        PackageError::Tool("data-stack attribution total overflowed".to_owned())
                    })?;
                }

                let copy_down_bytes = function_contract
                    .copy_down_sites
                    .iter()
                    .try_fold(0u64, |sum, site| sum.checked_add(site.bytes / 2))
                    .ok_or_else(|| {
                        PackageError::Tool("data-stack copy-down attribution overflowed".to_owned())
                    })?;
                if copy_down_bytes > function_contract.temporary_requirement {
                    return Err(PackageError::Tool(format!(
                        "data-stack attribution for '{}' lists more copy-down bytes than its temporary requirement",
                        function_contract.function
                    )));
                }
                for site in &function_contract.copy_down_sites {
                    let line = format_span(&compiled.files, site.span);
                    println!(
                        "  critical path contribution: {line} {} copy-down temporary for {} ({} bytes)",
                        function_contract.function,
                        site.name,
                        site.bytes / 2
                    );
                    attributed = attributed.checked_add(site.bytes / 2).ok_or_else(|| {
                        PackageError::Tool("data-stack attribution total overflowed".to_owned())
                    })?;
                }
                let other_temporaries = function_contract.temporary_requirement - copy_down_bytes;
                if other_temporaries > 0 {
                    println!(
                        "  critical path contribution: {} call/expression scratch ({} bytes)",
                        function_contract.function, other_temporaries
                    );
                    attributed = attributed.checked_add(other_temporaries).ok_or_else(|| {
                        PackageError::Tool("data-stack attribution total overflowed".to_owned())
                    })?;
                }
            }
            println!(
                "  critical path contribution: data-stack helper margin ({} bytes)",
                emit::DATA_STACK_HELPER_MARGIN
            );
            attributed = attributed
                .checked_add(emit::DATA_STACK_HELPER_MARGIN)
                .ok_or_else(|| {
                    PackageError::Tool("data-stack attribution total overflowed".to_owned())
                })?;
            if attributed != reported {
                return Err(PackageError::Tool(format!(
                    "data-stack critical path sums to {attributed} bytes, but the reported worst case is {reported} bytes"
                )));
            }
            println!("  data stack critical path sum: {attributed} bytes");
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
    let link = package_link_description(test_build, compiled)?;
    clang_internal(ir, output, &link, false).map(|_| ())
}

fn clang_with_frames(
    ir: &Path,
    output: &Path,
    test_build: bool,
    compiled: &CompileOutput,
) -> Result<std::collections::HashMap<usize, u64>, PackageError> {
    let link = package_link_description(test_build, compiled)?;
    clang_internal(ir, output, &link, true)?.ok_or_else(|| {
        PackageError::Tool("optimized native frame sizes were not collected".to_owned())
    })
}

fn package_link_description(
    test_build: bool,
    compiled: &CompileOutput,
) -> Result<LinkDescription<'_>, PackageError> {
    Ok(LinkDescription {
        build_kind: if test_build {
            BuildKind::Test
        } else {
            BuildKind::Program
        },
        stack_mode: compiled.stack_mode,
        runtime: LinkRuntime::C,
        optimization: optimization_level()?,
        recursion: Some(compiled),
    })
}

fn optimization_level() -> Result<String, PackageError> {
    match std::env::var("NLC_OPT_LEVEL").as_deref() {
        Ok("1") | Err(_) => Ok("1".to_owned()),
        Ok("3") => Ok("3".to_owned()),
        Ok(value) => Err(PackageError::Tool(format!(
            "NLC_OPT_LEVEL must be 1 or 3, got '{value}'"
        ))),
    }
}

fn read_link_ir_metadata(ir: &Path) -> Result<LinkIrMetadata, PackageError> {
    let source = fs::read_to_string(ir)
        .map_err(|error| PackageError::Tool(format!("cannot read LLVM IR: {error}")))?;
    let invalid = |reason: &str| {
        PackageError::Tool(format!("invalid nlc-link-ir metadata: {reason}"))
    };
    let lines = source.lines().collect::<Vec<_>>();
    let version = match lines.first().copied() {
        Some("; nlc-link-ir 1") => 1,
        Some("; nlc-link-ir 2") => 2,
        _ => return Err(invalid("missing or unknown header version")),
    };
    if lines.last().copied() != Some("; nlc-link-ir end") {
        return Err(invalid("missing end marker"));
    }
    if source.contains("nlc.recursion.targets=") {
        return Err(invalid("recursion target records are not supported by link-ir"));
    }

    let mut build_kind = None;
    let mut stack_mode = None;
    let mut runtime = None;
    let mut core_hash = None;
    let mut recursion_seen = false;
    let mut tests = Vec::new();
    for line in lines.iter().skip(1) {
        if !line.starts_with("; nlc.") {
            break;
        }
        if let Some(value) = line.strip_prefix("; nlc.build ") {
            if build_kind.is_some() {
                return Err(invalid("duplicate build kind"));
            }
            build_kind = Some(match value {
                "program" => BuildKind::Program,
                "test" => BuildKind::Test,
                _ => return Err(invalid("unknown build kind")),
            });
        } else if let Some(value) = line.strip_prefix("; nlc.stack ") {
            if stack_mode.is_some() {
                return Err(invalid("duplicate stack mode"));
            }
            stack_mode = Some(match value {
                "offset" => StackMode::Offset,
                _ => return Err(invalid("stack mode must be offset")),
            });
        } else if let Some(value) = line.strip_prefix("; nlc.recursion ") {
            if recursion_seen {
                return Err(invalid("duplicate recursion declaration"));
            }
            recursion_seen = true;
            if value != "none" {
                return Err(invalid("recursion must be none"));
            }
        } else if let Some(value) = line.strip_prefix("; nlc.runtime ") {
            if runtime.is_some() {
                return Err(invalid("duplicate runtime declaration"));
            }
            runtime = Some(match value {
                "c" => LinkRuntime::C,
                "core" => LinkRuntime::Core,
                _ => return Err(invalid("runtime must be c or core")),
            });
        } else if let Some(value) = line.strip_prefix("; nlc.core ") {
            if core_hash.is_some() {
                return Err(invalid("duplicate core hash"));
            }
            if value.len() != 64
                || !value
                    .bytes()
                    .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
            {
                return Err(invalid("core hash must be a lowercase SHA-256 hex digest"));
            }
            core_hash = Some(value.to_owned());
        } else if let Some(value) = line.strip_prefix("; nlc.test ") {
            let (index, encoded) = value
                .split_once(' ')
                .ok_or_else(|| invalid("malformed test record"))?;
            if index != tests.len().to_string() {
                return Err(invalid("test indices must be contiguous and ordered"));
            }
            if !encoded.bytes().all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
                || encoded.len() % 2 != 0
            {
                return Err(invalid("test names must use lowercase UTF-8 hex"));
            }
            let mut bytes = Vec::with_capacity(encoded.len() / 2);
            for pair in encoded.as_bytes().chunks_exact(2) {
                let high = link_ir_hex_nibble(pair[0]).ok_or_else(|| invalid("bad test name hex"))?;
                let low = link_ir_hex_nibble(pair[1]).ok_or_else(|| invalid("bad test name hex"))?;
                bytes.push(high * 16 + low);
            }
            let name = String::from_utf8(bytes)
                .map_err(|_| invalid("test name is not valid UTF-8"))?;
            tests.push(name);
        } else {
            return Err(invalid("unknown metadata field"));
        }
    }
    let build_kind = build_kind.ok_or_else(|| invalid("missing build kind"))?;
    let stack_mode = stack_mode.ok_or_else(|| invalid("missing stack mode"))?;
    if !recursion_seen {
        return Err(invalid("missing recursion declaration"));
    }
    let runtime = if version == 1 {
        if runtime.is_some() || core_hash.is_some() {
            return Err(invalid("version 1 metadata cannot declare a runtime or core hash"));
        }
        LinkRuntime::C
    } else {
        runtime.ok_or_else(|| invalid("missing runtime declaration"))?
    };
    if version == 2 && core_hash.is_none() {
        return Err(invalid("missing core hash"));
    }
    Ok(LinkIrMetadata {
        build_kind,
        stack_mode,
        runtime,
        tests,
    })
}

fn link_ir_hex_nibble(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        _ => None,
    }
}

fn clang_internal(
    ir: &Path,
    output: &Path,
    link: &LinkDescription<'_>,
    collect_native_frames: bool,
) -> Result<Option<std::collections::HashMap<usize, u64>>, PackageError> {
    let runtime = Path::new(env!("CARGO_MANIFEST_DIR")).join("../runtime/nl_runtime.c");
    if link.runtime == LinkRuntime::C && !runtime.is_file() {
        return Err(PackageError::Tool(format!(
            "runtime source is missing: {}",
            runtime.display()
        )));
    }
    let source = fs::read_to_string(ir)
        .map_err(|error| PackageError::Tool(format!("cannot read generated LLVM IR: {error}")))?;
    if !source.contains("nlc.recursion.targets=") {
        run_clang(
            ir,
            output,
            &runtime,
            link,
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
    run_clang(
        ir,
        &probe,
        &runtime,
        link,
        true,
    )?;
    let mut frames = read_native_frame_sizes(&probe)?;
    for _ in 0..3 {
        let Some(compiled) = link.recursion else {
            return Err(PackageError::Tool(
                "link-ir refuses recursion checks without call-graph metadata".to_owned(),
            ));
        };
        let patched = patch_recursion_checks(&source, compiled, &frames)?;
        fs::write(&patched_ir, patched).map_err(|error| {
            PackageError::Tool(format!("cannot write recursion-checked LLVM IR: {error}"))
        })?;
        run_clang(
            &patched_ir,
            output,
            &runtime,
            link,
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
    link: &LinkDescription<'_>,
    collect_stack_sizes: bool,
) -> Result<(), PackageError> {
    let mut command = Command::new("clang");
    command.arg(format!("-O{}", link.optimization));
    if collect_stack_sizes {
        command.arg("-fstack-size-section");
    }
    if link.runtime == LinkRuntime::C && link.build_kind == BuildKind::Test {
        command.arg("-DNLC_TEST_BUILD=1");
    }
    if link.runtime == LinkRuntime::C && link.stack_mode.is_offset() {
        command.arg("-DNLC_STACK_MODE_OFFSET=1");
    }
    if link.runtime == LinkRuntime::Core {
        command
            .arg("-nostdlib")
            .arg("-static")
            .arg("-Wl,-e,_start")
            .arg("-Wl,-no-pie")
            .arg("-Wl,--build-id=none");
    }
    command.arg(ir);
    if link.runtime == LinkRuntime::C {
        command.arg(runtime);
    }
    let result = command
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

const SELFHOST_WIRE_VERSION: u64 = 1;
const SELFHOST_CHILD_MAX_BYTES: u64 = 1024 * 1024 * 1024;

#[derive(Clone, Copy)]
struct Fingerprint(u64, u64);

impl Fingerprint {
    fn new() -> Self {
        Self(0xcbf29ce484222325, 0x84222325cbf29ce4)
    }

    fn feed(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.0 ^= u64::from(*byte);
            self.0 = self.0.wrapping_mul(0x100000001b3);
            self.1 ^= u64::from(*byte).wrapping_add(0x9e3779b97f4a7c15);
            self.1 = self.1.rotate_left(13).wrapping_mul(0xff51afd7ed558ccd);
        }
    }

    fn field(&mut self, label: &[u8], value: &[u8]) {
        self.feed(&(label.len() as u64).to_le_bytes());
        self.feed(label);
        self.feed(&(value.len() as u64).to_le_bytes());
        self.feed(value);
    }

    fn hex(self) -> String {
        format!("{:016x}{:016x}", self.0, self.1)
    }
}

struct CacheLock {
    path: PathBuf,
}

impl CacheLock {
    fn acquire(path: PathBuf) -> Result<Self, PackageError> {
        for _ in 0..600 {
            match fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&path)
            {
                Ok(mut file) => {
                    use std::io::Write;
                    let _ = writeln!(file, "{}", std::process::id());
                    return Ok(Self { path });
                }
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                    if cache_lock_is_stale(&path) {
                        let _ = fs::remove_file(&path);
                        continue;
                    }
                    std::thread::sleep(std::time::Duration::from_millis(50));
                }
                Err(error) => {
                    return Err(PackageError::Tool(format!(
                        "cannot create self-hosted compiler cache lock: {error}"
                    )));
                }
            }
        }
        Err(PackageError::Tool(
            "timed out waiting for the self-hosted compiler cache lock".to_owned(),
        ))
    }
}

fn cache_lock_is_stale(path: &Path) -> bool {
    let Ok(owner) = fs::read_to_string(path) else {
        return fs::metadata(path)
            .ok()
            .and_then(|metadata| metadata.modified().ok())
            .and_then(|modified| modified.elapsed().ok())
            .is_some_and(|age| age.as_secs() > 2);
    };
    let Some(pid) = owner.trim().parse::<u32>().ok().filter(|pid| *pid != 0) else {
        return fs::metadata(path)
            .ok()
            .and_then(|metadata| metadata.modified().ok())
            .and_then(|modified| modified.elapsed().ok())
            .is_some_and(|age| age.as_secs() > 2);
    };
    if pid == std::process::id() {
        return false;
    }
    #[cfg(target_os = "linux")]
    {
        !Path::new("/proc").join(pid.to_string()).exists()
    }
    #[cfg(not(target_os = "linux"))]
    {
        fs::metadata(path)
            .ok()
            .and_then(|metadata| metadata.modified().ok())
            .and_then(|modified| modified.elapsed().ok())
            .is_some_and(|age| age.as_secs() > 300)
    }
}

impl Drop for CacheLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn target_cache_root() -> PathBuf {
    if let Some(path) = std::env::var_os("CARGO_TARGET_DIR") {
        let path = PathBuf::from(path);
        return if path.is_absolute() {
            path
        } else {
            std::env::current_dir().unwrap_or_default().join(path)
        };
    }
    if let Some(home) = std::env::var_os("HOME") {
        return PathBuf::from(home).join(".cache/next-lang/target");
    }
    std::env::temp_dir().join("next-lang-target")
}

fn effective_optimization() -> Result<&'static str, PackageError> {
    match std::env::var("NLC_OPT_LEVEL").as_deref() {
        Ok("1") | Err(_) => Ok("1"),
        Ok("3") => Ok("3"),
        Ok(value) => Err(PackageError::Tool(format!(
            "NLC_OPT_LEVEL must be 1 or 3, got '{value}'"
        ))),
    }
}

fn command_version(program: &str) -> Result<Vec<u8>, PackageError> {
    let output = Command::new(program)
        .arg("--version")
        .output()
        .map_err(|error| {
            PackageError::Tool(format!("cannot query {program} toolchain version: {error}"))
        })?;
    if !output.status.success() {
        return Err(PackageError::Tool(format!("{program} --version failed")));
    }
    let mut value = output.stdout;
    value.extend_from_slice(&output.stderr);
    Ok(value)
}

fn selfhost_source_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../selfhost")
}

#[derive(Clone, Copy)]
struct SelfhostKeyInputs<'a> {
    wire_version: u64,
    nlc_binary: &'a [u8],
    runtime: &'a [u8],
    manifest: &'a [u8],
    sources: &'a [(Vec<u8>, Vec<u8>)],
    target: &'a [u8],
    optimization: &'a [u8],
    stack_mode: &'a [u8],
    clang: &'a [u8],
    rustc: &'a [u8],
}

fn compute_selfhost_cache_key(inputs: &SelfhostKeyInputs<'_>) -> String {
    let mut fingerprint = Fingerprint::new();
    fingerprint.field(b"wire-version", &inputs.wire_version.to_le_bytes());
    fingerprint.field(b"nlc-binary", inputs.nlc_binary);
    fingerprint.field(b"runtime-c", inputs.runtime);
    fingerprint.field(b"selfhost/package.toml", inputs.manifest);
    for (path, source) in inputs.sources {
        fingerprint.field(b"selfhost-source-path", path);
        fingerprint.field(b"selfhost-source", source);
    }
    fingerprint.field(b"target", inputs.target);
    fingerprint.field(b"optimization", inputs.optimization);
    fingerprint.field(b"stack-mode", inputs.stack_mode);
    fingerprint.field(b"clang", inputs.clang);
    fingerprint.field(b"rustc", inputs.rustc);
    fingerprint.hex()
}

fn selfhost_cache_key(selfhost_dir: &Path, stack_mode: StackMode) -> Result<String, PackageError> {
    let compiler = std::env::current_exe().map_err(|error| {
        PackageError::Tool(format!("cannot locate nlc build identity: {error}"))
    })?;
    let nlc_binary = fs::read(&compiler)
        .map_err(|error| PackageError::Tool(format!("cannot read nlc build identity: {error}")))?;
    let runtime = Path::new(env!("CARGO_MANIFEST_DIR")).join("../runtime/nl_runtime.c");
    let runtime = fs::read(&runtime)
        .map_err(|error| PackageError::Tool(format!("cannot read runtime source: {error}")))?;
    let manifest = selfhost_dir.join("package.toml");
    let manifest = fs::read(&manifest)
        .map_err(|error| PackageError::Tool(format!("cannot read selfhost manifest: {error}")))?;
    let mut sources = fs::read_dir(selfhost_dir)
        .map_err(|error| PackageError::Tool(format!("cannot list selfhost sources: {error}")))?
        .map(|entry| {
            entry.map(|entry| entry.path()).map_err(|error| {
                PackageError::Tool(format!("cannot read selfhost directory entry: {error}"))
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    sources.retain(|path| {
        path.extension().is_some_and(|extension| extension == "nl") && path.is_file()
    });
    sources.sort();
    let mut source_inputs = Vec::with_capacity(sources.len());
    for path in sources {
        let relative = path
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or_else(|| PackageError::Tool("selfhost source name is not UTF-8".to_owned()))?;
        source_inputs.push((
            relative.as_bytes().to_vec(),
            fs::read(&path).map_err(|error| {
                PackageError::Tool(format!(
                    "cannot read selfhost source '{}': {error}",
                    path.display()
                ))
            })?,
        ));
    }
    let target = std::env::var("TARGET")
        .unwrap_or_else(|_| format!("{}-{}", std::env::consts::ARCH, std::env::consts::OS));
    let optimization = effective_optimization()?;
    let clang = command_version("clang")?;
    let rustc = command_version("rustc")?;
    // Bootstrap generation is deliberately Rust-only and pointer-mode. Only
    // code-generation settings affect this artifact; frontend/test-runner
    // settings must not perturb its cache identity.
    Ok(compute_selfhost_cache_key(&SelfhostKeyInputs {
        wire_version: SELFHOST_WIRE_VERSION,
        nlc_binary: &nlc_binary,
        runtime: &runtime,
        manifest: &manifest,
        sources: &source_inputs,
        target: target.as_bytes(),
        optimization: optimization.as_bytes(),
        stack_mode: if stack_mode.is_offset() {
            b"offset"
        } else {
            b"pointer"
        },
        clang: &clang,
        rustc: &rustc,
    }))
}

fn selfhost_cached_binary() -> Result<PathBuf, PackageError> {
    let selfhost_dir = selfhost_source_dir();
    if !selfhost_dir.is_dir() {
        return Err(PackageError::Tool(format!(
            "selfhost source directory is missing: {}",
            selfhost_dir.display()
        )));
    }
    let stack_mode = StackMode::Pointer;
    let key = selfhost_cache_key(&selfhost_dir, stack_mode)?;
    let cache_root = target_cache_root().join("next-lang-selfhost");
    fs::create_dir_all(&cache_root).map_err(|error| {
        PackageError::Tool(format!("cannot create selfhost cache directory: {error}"))
    })?;
    let artifact_dir = cache_root.join(&key);
    let binary = artifact_dir.join(if cfg!(windows) {
        "selfhost.exe"
    } else {
        "selfhost"
    });
    if cached_artifact_valid(&artifact_dir, &binary) {
        return Ok(binary);
    }

    let _lock = CacheLock::acquire(cache_root.join("build.lock"))?;
    if cached_artifact_valid(&artifact_dir, &binary) {
        return Ok(binary);
    }
    if artifact_dir.exists() {
        fs::remove_dir_all(&artifact_dir).map_err(|error| {
            PackageError::Tool(format!(
                "cannot remove corrupt selfhost cache entry: {error}"
            ))
        })?;
    }
    let mut stage = None;
    for _ in 0..100 {
        let id = TEMP_ID.fetch_add(1, Ordering::Relaxed);
        let path = cache_root.join(format!("stage-{}-{id}", std::process::id()));
        match fs::create_dir(&path) {
            Ok(()) => {
                stage = Some(path);
                break;
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(PackageError::Tool(format!(
                    "cannot create selfhost cache staging directory: {error}"
                )));
            }
        }
    }
    let stage = stage.ok_or_else(|| {
        PackageError::Tool("cannot allocate a selfhost cache staging directory".to_owned())
    })?;
    let stage_guard = TempDir {
        path: stage.clone(),
    };
    let compiled = compile_package_on_worker(
        &selfhost_dir,
        true,
        Frontend::Rust,
        Some(StackMode::Pointer),
    )?;
    let ir = stage.join("module.ll");
    let staged_binary = stage.join(if cfg!(windows) {
        "selfhost.exe"
    } else {
        "selfhost"
    });
    fs::write(&ir, &compiled.llvm_ir)
        .map_err(|error| PackageError::Tool(format!("cannot write selfhost LLVM IR: {error}")))?;
    clang(&ir, &staged_binary, false, &compiled)?;
    let executable_bytes = fs::read(&staged_binary)
        .map_err(|error| PackageError::Tool(format!("cannot read selfhost executable: {error}")))?;
    fs::write(
        stage.join("artifact.hash"),
        FingerprintHash::of(&executable_bytes).as_bytes(),
    )
    .map_err(|error| PackageError::Tool(format!("cannot write selfhost cache marker: {error}")))?;
    fs::remove_file(&ir)
        .map_err(|error| PackageError::Tool(format!("cannot remove staged LLVM IR: {error}")))?;
    fs::rename(&stage, &artifact_dir).map_err(|error| {
        PackageError::Tool(format!("cannot publish selfhost cache artifact: {error}"))
    })?;
    drop(stage_guard);
    Ok(binary)
}

struct FingerprintHash;
impl FingerprintHash {
    fn of(bytes: &[u8]) -> String {
        let mut fingerprint = Fingerprint::new();
        fingerprint.feed(bytes);
        fingerprint.hex()
    }
}

fn cached_artifact_valid(directory: &Path, binary: &Path) -> bool {
    if !directory.is_dir() || !binary.is_file() {
        return false;
    }
    let marker = match fs::read_to_string(directory.join("artifact.hash")) {
        Ok(value) => value,
        Err(_) => return false,
    };
    let artifact = match fs::read(binary) {
        Ok(value) => value,
        Err(_) => return false,
    };
    marker == FingerprintHash::of(&artifact)
}

fn run_selfhost_tree(package: &Path) -> Result<Vec<tree_reader::RebuiltFile>, PackageError> {
    let binary = selfhost_cached_binary()?;
    run_selfhost_tree_with_binary(package, &binary)
}

fn run_selfhost_tree_with_binary(
    package: &Path,
    binary: &Path,
) -> Result<Vec<tree_reader::RebuiltFile>, PackageError> {
    let package = fs::canonicalize(package).map_err(|error| {
        PackageError::Tool(format!("cannot resolve package directory: {error}"))
    })?;
    let parent = package
        .parent()
        .ok_or_else(|| PackageError::Tool("package directory has no parent".to_owned()))?;
    let name = package
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| PackageError::Tool("package directory name is not UTF-8".to_owned()))?;
    let temp = TempDir::new().map_err(|error| {
        PackageError::Tool(format!("cannot create temporary tree directory: {error}"))
    })?;
    let tree_path = temp.path.join("tree.bin");
    let output_file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&tree_path)
        .map_err(|error| {
            PackageError::Tool(format!("cannot create temporary tree file: {error}"))
        })?;
    let child = Command::new(&binary)
        .args(["parse", name, "--binary"])
        .current_dir(parent)
        .stdin(Stdio::null())
        .stdout(Stdio::from(output_file))
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| PackageError::Tool(format!("cannot launch selfhost parser: {error}")))?;
    let result = child
        .wait_with_output()
        .map_err(|error| PackageError::Tool(format!("cannot wait for selfhost parser: {error}")))?;
    if !result.status.success() {
        let stderr = String::from_utf8_lossy(&result.stderr).into_owned();
        if result.status.code() == Some(2) {
            if let Some(error) = parse_child_diagnostic(&stderr) {
                return Err(PackageError::Compile(error));
            }
            return Err(PackageError::Tool(format!(
                "selfhost parser exited with status 2 without a diagnostic: {}",
                stderr.trim_end()
            )));
        }
        if let Some(message) = stderr.strip_prefix("nlc: tool failure: ") {
            return Err(PackageError::Tool(message.trim_end().to_owned()));
        }
        return Err(PackageError::Tool(match result.status.code() {
            Some(code) => format!(
                "selfhost parser exited with status {code}: {}",
                stderr.trim_end()
            ),
            None => format!(
                "selfhost parser terminated by a signal: {}",
                stderr.trim_end()
            ),
        }));
    }
    let metadata = fs::metadata(&tree_path).map_err(|error| {
        PackageError::Tool(format!("cannot inspect temporary tree file: {error}"))
    })?;
    if metadata.len() > SELFHOST_CHILD_MAX_BYTES {
        return Err(PackageError::Tool(
            "selfhost binary tree exceeds the reader size limit".to_owned(),
        ));
    }
    let bytes = fs::read(&tree_path)
        .map_err(|error| PackageError::Tool(format!("cannot read temporary tree file: {error}")))?;
    tree_reader::read_package(&bytes)
        .map_err(|error| PackageError::Tool(format!("invalid selfhost binary tree: {error}")))
}

fn run_selfhost_lex_dump(package: &Path) -> Result<String, PackageError> {
    let binary = selfhost_cached_binary()?;
    let package = fs::canonicalize(package).map_err(|error| {
        PackageError::Tool(format!("cannot resolve package directory: {error}"))
    })?;
    let parent = package
        .parent()
        .ok_or_else(|| PackageError::Tool("package directory has no parent".to_owned()))?;
    let name = package
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| PackageError::Tool("package directory name is not UTF-8".to_owned()))?;
    let output = Command::new(&binary)
        .args(["lex", name])
        .current_dir(parent)
        .stdin(Stdio::null())
        .output()
        .map_err(|error| PackageError::Tool(format!("cannot launch selfhost lexer: {error}")))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
        if output.status.code() == Some(2) {
            if let Some(error) = parse_child_diagnostic(&stderr) {
                return Err(PackageError::Compile(error));
            }
            return Err(PackageError::Tool(format!(
                "selfhost lexer exited with status 2 without a diagnostic: {}",
                stderr.trim_end()
            )));
        }
        if let Some(message) = stderr.strip_prefix("nlc: tool failure: ") {
            return Err(PackageError::Tool(message.trim_end().to_owned()));
        }
        return Err(PackageError::Tool(match output.status.code() {
            Some(code) => format!(
                "selfhost lexer exited with status {code}: {}",
                stderr.trim_end()
            ),
            None => format!(
                "selfhost lexer terminated by a signal: {}",
                stderr.trim_end()
            ),
        }));
    }
    String::from_utf8(output.stdout).map_err(|_| {
        PackageError::Tool("selfhost lexer produced non-UTF-8 token output".to_owned())
    })
}

fn parse_child_diagnostic(stderr: &str) -> Option<CompileError> {
    let line = stderr.strip_suffix('\n').unwrap_or(stderr);
    let (location, message) = line.rsplit_once(": error: ")?;
    let mut parts = location.rsplitn(3, ':');
    let col = parts.next()?.parse().ok()?;
    let line_number = parts.next()?.parse().ok()?;
    let file = parts.next()?.to_owned();
    Some(CompileError {
        file,
        span: Span {
            file: 0,
            line: line_number,
            col,
            start_offset: 0,
            end_offset: 0,
        },
        message: message.to_owned(),
    })
}

#[cfg(test)]
mod selfhost_ast_tests {
    use super::*;
    use crate::ast::Program;

    fn source_packages(root: &Path, relative: &str) -> Vec<PathBuf> {
        fn visit(path: &Path, packages: &mut Vec<PathBuf>) {
            let entries = match fs::read_dir(path) {
                Ok(entries) => entries,
                Err(_) => return,
            };
            let mut has_source = false;
            let mut children = Vec::new();
            for entry in entries.flatten() {
                let entry_path = entry.path();
                if entry_path
                    .extension()
                    .is_some_and(|extension| extension == "nl")
                {
                    has_source = true;
                } else if entry_path.is_dir() {
                    children.push(entry_path);
                }
            }
            if has_source {
                packages.push(path.to_owned());
            }
            children.sort();
            for child in children {
                visit(&child, packages);
            }
        }
        let mut packages = Vec::new();
        visit(&root.join(relative), &mut packages);
        packages.sort();
        packages
    }

    fn rust_programs(package: &Path) -> Option<Vec<(String, Program)>> {
        let root = fs::canonicalize(package).ok()?;
        let mut paths = fs::read_dir(package)
            .ok()?
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| {
                path.extension().is_some_and(|extension| extension == "nl") && path.is_file()
            })
            .filter(|path| fs::canonicalize(path).is_ok_and(|target| target.starts_with(&root)))
            .collect::<Vec<_>>();
        paths.sort();
        let mut programs = Vec::with_capacity(paths.len());
        for (file_id, path) in paths.into_iter().enumerate() {
            let name = path.file_name()?.to_str()?.to_owned();
            let bytes = fs::read(path).ok()?;
            let source = String::from_utf8(bytes).ok()?;
            let tokens = lexer::lex(&source, file_id).ok()?;
            let program = parser::parse(tokens, &source).ok()?;
            programs.push((name, program));
        }
        Some(programs)
    }

    #[test]
    fn selfhost_rebuilds_the_rust_ast_for_every_valid_fixture_package() {
        std::thread::Builder::new()
            .name("selfhost-ast-equality".to_owned())
            .stack_size(256 * 1024 * 1024)
            .spawn(compare_all_fixture_asts)
            .expect("start AST equality worker")
            .join()
            .expect("AST equality worker did not panic");
    }

    #[test]
    fn every_selfhost_cache_key_component_changes_the_key() {
        let base_sources = vec![(b"main.nl".to_vec(), b"fn main() {}".to_vec())];
        let base = SelfhostKeyInputs {
            wire_version: 1,
            nlc_binary: b"nlc-v1",
            runtime: b"runtime-v1",
            manifest: b"package-v1",
            sources: &base_sources,
            target: b"target-v1",
            optimization: b"1",
            stack_mode: b"pointer",
            clang: b"clang-v1",
            rustc: b"rustc-v1",
        };
        let key = compute_selfhost_cache_key(&base);
        let changed_source_path = vec![(b"other.nl".to_vec(), b"fn main() {}".to_vec())];
        let changed_source_content =
            vec![(b"main.nl".to_vec(), b"fn main() { print(1) }".to_vec())];
        let changed = [
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                wire_version: 2,
                ..base
            }),
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                nlc_binary: b"nlc-v2",
                ..base
            }),
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                runtime: b"runtime-v2",
                ..base
            }),
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                manifest: b"package-v2",
                ..base
            }),
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                sources: &changed_source_path,
                ..base
            }),
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                sources: &changed_source_content,
                ..base
            }),
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                target: b"target-v2",
                ..base
            }),
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                optimization: b"3",
                ..base
            }),
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                stack_mode: b"offset",
                ..base
            }),
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                clang: b"clang-v2",
                ..base
            }),
            compute_selfhost_cache_key(&SelfhostKeyInputs {
                rustc: b"rustc-v2",
                ..base
            }),
        ];
        assert!(changed.iter().all(|candidate| candidate != &key));
    }

    #[test]
    fn cache_artifacts_reject_missing_or_corrupt_executables() {
        let temp = TempDir::new().expect("create temporary cache directory");
        let binary = temp.path.join("selfhost");
        fs::write(&binary, b"selfhost executable").expect("write cache executable");
        let marker = FingerprintHash::of(b"selfhost executable");
        fs::write(temp.path.join("artifact.hash"), marker).expect("write cache marker");
        assert!(cached_artifact_valid(&temp.path, &binary));
        fs::write(&binary, b"corrupted executable").expect("corrupt cache executable");
        assert!(!cached_artifact_valid(&temp.path, &binary));
        fs::remove_file(&binary).expect("remove cache executable");
        assert!(!cached_artifact_valid(&temp.path, &binary));
    }

    #[cfg(unix)]
    #[test]
    fn child_signals_and_truncated_trees_are_tool_failures() {
        use std::os::unix::fs::PermissionsExt;

        let temp = TempDir::new().expect("create transport fixture directory");
        let package = temp.path.join("package");
        fs::create_dir(&package).expect("create package directory");
        fs::write(package.join("main.nl"), "fn main() {}\n").expect("write package source");

        let signal_child = temp.path.join("signal-child");
        fs::write(&signal_child, "#!/bin/sh\nkill -TERM $$\n").expect("write signal child");
        fs::set_permissions(&signal_child, fs::Permissions::from_mode(0o755))
            .expect("make signal child executable");
        let signal_error = run_selfhost_tree_with_binary(&package, &signal_child)
            .expect_err("a child killed by a signal must fail");
        assert!(
            matches!(&signal_error, PackageError::Tool(message) if message.contains("terminated by a signal")),
            "unexpected signal failure: {signal_error:?}"
        );

        let truncated_child = temp.path.join("truncated-child");
        fs::write(&truncated_child, "#!/bin/sh\nprintf 'NLASTB01'\n")
            .expect("write truncated-tree child");
        fs::set_permissions(&truncated_child, fs::Permissions::from_mode(0o755))
            .expect("make truncated-tree child executable");
        let truncated_error = run_selfhost_tree_with_binary(&package, &truncated_child)
            .expect_err("a truncated child tree must fail");
        assert!(
            matches!(&truncated_error, PackageError::Tool(message) if message.contains("invalid selfhost binary tree: truncated header")),
            "unexpected truncated-tree failure: {truncated_error:?}"
        );
    }

    fn compare_all_fixture_asts() {
        let workspace = Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("workspace root");
        let mut packages = Vec::new();
        for relative in ["tests/run", "tests/test", "tests/parse/cases"] {
            packages.extend(source_packages(workspace, relative));
        }
        let mut checked = 0usize;
        for package in packages {
            let Some(expected) = rust_programs(&package) else {
                continue;
            };
            let rebuilt = run_selfhost_tree(&package).unwrap_or_else(|error| {
                panic!(
                    "selfhost failed to rebuild Rust-valid package {}: {error}",
                    package.display()
                )
            });
            let actual = rebuilt
                .into_iter()
                .map(|file| (file.name, file.program))
                .collect::<Vec<_>>();
            assert_eq!(actual, expected, "AST mismatch in {}", package.display());
            checked += 1;
        }
        assert!(
            checked > 50,
            "fixture discovery found only {checked} valid packages"
        );
    }
}
