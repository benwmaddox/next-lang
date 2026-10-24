use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

use crate::ast::Span;
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
    let typed = checker::check_package(programs, files.clone(), require_main).map_err(|e| {
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
    Ok(CompileOutput {
        llvm_ir: emit::emit(&typed),
        files,
        tests: typed.tests.iter().map(|test| test.name.clone()).collect(),
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
    clang(&ir, output)
}

pub fn run_package(package: &Path) -> Result<ExitStatus, PackageError> {
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
    clang(&ir, &binary)?;
    Command::new(&binary)
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
    clang(&ir, &binary)?;

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

fn clang(ir: &Path, output: &Path) -> Result<(), PackageError> {
    let runtime = Path::new(env!("CARGO_MANIFEST_DIR")).join("../runtime/nl_runtime.c");
    if !runtime.is_file() {
        return Err(PackageError::Tool(format!(
            "runtime source is missing: {}",
            runtime.display()
        )));
    }
    let result = Command::new("clang")
        .arg("-O1")
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
