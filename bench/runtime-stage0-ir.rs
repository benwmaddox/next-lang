use next_lang::{compile_package_with_frontend, Frontend};
use std::env;
use std::fs;
use std::path::Path;
use std::process::ExitCode;

fn main() -> ExitCode {
    let arguments = env::args_os().skip(1).collect::<Vec<_>>();
    if arguments.len() != 2 {
        eprintln!("usage: runtime-stage0-ir <package> <output.ll>");
        return ExitCode::from(2);
    }

    let package = Path::new(&arguments[0]);
    let output = Path::new(&arguments[1]);
    let compiled = match compile_package_with_frontend(package, Frontend::Rust) {
        Ok(compiled) => compiled,
        Err(error) => {
            eprintln!("{error}");
            return ExitCode::from(2);
        }
    };

    if let Some(parent) = output.parent().filter(|path| !path.as_os_str().is_empty()) {
        if let Err(error) = fs::create_dir_all(parent) {
            eprintln!("cannot create output directory: {error}");
            return ExitCode::from(1);
        }
    }
    match fs::write(output, compiled.llvm_ir.as_bytes()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("cannot write LLVM IR: {error}");
            ExitCode::from(1)
        }
    }
}
