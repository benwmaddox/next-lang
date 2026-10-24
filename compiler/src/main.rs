use std::path::Path;
use std::process::ExitCode;

use next_lang::{PackageError, build_package, run_package};

fn main() -> ExitCode {
    let mut args = std::env::args_os();
    let _program = args.next();
    let Some(command) = args.next().and_then(|x| x.into_string().ok()) else {
        usage();
        return ExitCode::from(3);
    };
    let rest = args.collect::<Vec<_>>();
    match command.as_str() {
        "run" if rest.len() == 1 => match run_package(Path::new(&rest[0])) {
            Ok(status) => ExitCode::from(status.code().unwrap_or(1) as u8),
            Err(error) => report_error(error),
        },
        "build" if rest.len() == 3 && rest[1] == "-o" => {
            match build_package(Path::new(&rest[0]), Path::new(&rest[2])) {
                Ok(()) => ExitCode::SUCCESS,
                Err(error) => report_error(error),
            }
        }
        _ => {
            usage();
            ExitCode::from(3)
        }
    }
}

fn report_error(error: PackageError) -> ExitCode {
    match error {
        PackageError::Compile(error) => {
            eprintln!("{error}");
            ExitCode::from(2)
        }
        PackageError::Tool(message) => {
            eprintln!("nlc: tool failure: {message}");
            ExitCode::from(3)
        }
    }
}

fn usage() {
    eprintln!("usage: nlc run <package-dir> | nlc build <package-dir> -o <file>");
}
