use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

use crate::ast::Span;
use crate::emit::StackContract;
use crate::{checker, emit, lexer, parser};

static TEMP_ID: AtomicUsize = AtomicUsize::new(0);

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
            },
            message,
        }),
    }
}

fn compile_package_internal(
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
    let mut typed = checker::check_package(programs, files.clone(), require_main).map_err(|e| {
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
    let function_contracts = emit::stack_contracts(&typed);
    emit::apply_function_type_stack_contracts(&mut typed, &function_contracts);
    let contracts = emit::stack_contracts(&typed);
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
    Ok(CompileOutput {
        llvm_ir: emit::emit(&typed),
        files,
        tests: typed.tests.iter().map(|test| test.name.clone()).collect(),
        memory,
        contracts,
    })
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
    fs::write(&ir, compiled.llvm_ir)
        .map_err(|e| PackageError::Tool(format!("cannot write generated LLVM IR: {e}")))?;
    clang(&ir, output, false)
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
    fs::write(&ir, compiled.llvm_ir)
        .map_err(|e| PackageError::Tool(format!("cannot write generated LLVM IR: {e}")))?;
    clang(&ir, &binary, false)?;
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
    fs::write(&ir, compiled.llvm_ir)
        .map_err(|e| PackageError::Tool(format!("cannot write generated LLVM IR: {e}")))?;
    clang(&ir, &binary, true)?;

    let mut passed = 0usize;
    let mut failed = 0usize;
    for (index, name) in compiled.tests.iter().enumerate() {
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

fn clang(ir: &Path, output: &Path, test_build: bool) -> Result<(), PackageError> {
    let runtime = Path::new(env!("CARGO_MANIFEST_DIR")).join("../runtime/nl_runtime.c");
    if !runtime.is_file() {
        return Err(PackageError::Tool(format!(
            "runtime source is missing: {}",
            runtime.display()
        )));
    }
    let mut command = Command::new("clang");
    command.arg("-O1");
    if test_build {
        command.arg("-DNLC_TEST_BUILD=1");
    }
    let result = command
        .arg(ir)
        .arg(&runtime)
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

#[derive(Clone, Copy)]
struct MemoryConfig {
    job_headroom_bytes: u64,
    globals_budget_bytes: u64,
}

fn read_memory_config(package: &Path) -> Result<MemoryConfig, PackageError> {
    let path = package.join("next-lang.toml");
    let contents = match fs::read_to_string(&path) {
        Ok(contents) => contents,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok(MemoryConfig {
                job_headroom_bytes: 256 * 1024 * 1024,
                globals_budget_bytes: 64 * 1024 * 1024,
            });
        }
        Err(error) => {
            return Err(PackageError::Tool(format!(
                "cannot read package memory manifest '{}': {error}",
                path.display()
            )));
        }
    };
    let mut config = MemoryConfig {
        job_headroom_bytes: 256 * 1024 * 1024,
        globals_budget_bytes: 64 * 1024 * 1024,
    };
    for (line_number, line) in contents.lines().enumerate() {
        let line = line.split('#').next().unwrap_or("").trim();
        if line.is_empty() || (line.starts_with('[') && line.ends_with(']')) {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        if key != "job_headroom" && key != "globals_budget" {
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
