use std::path::Path;
use std::process::ExitCode;

use next_lang::{
    PackageError, build_package, inspect_contracts, inspect_memory, run_package_args, test_package,
};

fn main() -> ExitCode {
    let mut args = std::env::args_os();
    let _program = args.next();
    let Some(command) = args.next().and_then(|x| x.into_string().ok()) else {
        usage();
        return ExitCode::from(3);
    };
    let rest = args.collect::<Vec<_>>();
    match command.as_str() {
        "run" if !rest.is_empty() => match run_package_args(Path::new(&rest[0]), &rest[1..]) {
            Ok(status) => ExitCode::from(status.code().unwrap_or(1) as u8),
            Err(error) => report_error(error),
        },
        "test" if rest.len() == 1 => match test_package(Path::new(&rest[0])) {
            Ok(code) => ExitCode::from(code),
            Err(error) => report_error(error),
        },
        "build" if rest.len() == 3 && rest[1] == "-o" => {
            match build_package(Path::new(&rest[0]), Path::new(&rest[2])) {
                Ok(()) => ExitCode::SUCCESS,
                Err(error) => report_error(error),
            }
        }
        "inspect" if (rest.len() == 2 || rest.len() == 3) && rest[0] == "memory" => {
            let allow_overcommit = rest.len() == 3 && rest[2] == "--allow-overcommit";
            if rest.len() == 3 && !allow_overcommit {
                usage();
                return ExitCode::from(3);
            }
            match inspect_memory(Path::new(&rest[1]), allow_overcommit) {
                Ok(()) => ExitCode::SUCCESS,
                Err(error) => report_error(error),
            }
        }
        "inspect" if rest.len() == 2 && rest[0] == "contracts" => {
            match inspect_contracts(Path::new(&rest[1])) {
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
    eprintln!(
        "usage: nlc run <package-dir> [--allow-overcommit] | nlc build <package-dir> -o <file> | nlc test <package-dir> | nlc inspect memory <package-dir> [--allow-overcommit] | nlc inspect contracts <package-dir>"
    );
}
