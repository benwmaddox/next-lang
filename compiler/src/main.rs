use std::io::Write;
use std::path::Path;
use std::process::ExitCode;

use next_lang::{
    PackageError, build_package, inspect_contracts, inspect_memory, inspect_stacks, parse_package,
    run_package_args, test_package,
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
        "run" if !rest.is_empty() => {
            let arguments = if rest.get(1).is_some_and(|arg| arg == "--") {
                &rest[2..]
            } else {
                &rest[1..]
            };
            match run_package_args(Path::new(&rest[0]), arguments) {
                Ok(status) => ExitCode::from(status.code().unwrap_or(1) as u8),
                Err(error) => report_error(error),
            }
        }
        "test" if rest.len() == 1 => match test_package(Path::new(&rest[0])) {
            Ok(code) => ExitCode::from(code),
            Err(error) => report_error(error),
        },
        "parse" if (1..=3).contains(&rest.len()) => {
            let flags = &rest[1..];
            let want_tree = flags.iter().any(|arg| arg == "--tree");
            let want_tokens = flags.iter().any(|arg| arg == "--tokens");
            let valid_flags = flags.iter().all(|arg| arg == "--tree" || arg == "--tokens")
                && flags.len() == usize::from(want_tree) + usize::from(want_tokens);
            if !valid_flags {
                usage();
                ExitCode::from(3)
            } else {
                match parse_package(Path::new(&rest[0])) {
                    Ok(dump) => {
                        match (want_tokens, want_tree) {
                            (true, true) => {
                                write_stdout(format_args!(
                                    "== tokens ==\n{}== tree ==\n{}",
                                    dump.tokens, dump.tree
                                ));
                            }
                            (true, false) => write_stdout(format_args!("{}", dump.tokens)),
                            (false, true) => write_stdout(format_args!("{}", dump.tree)),
                            (false, false) => {}
                        }
                        ExitCode::SUCCESS
                    }
                    Err(error) => report_error(error),
                }
            }
        }
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
        "inspect" if rest.len() == 2 && rest[0] == "stacks" => {
            match inspect_stacks(Path::new(&rest[1])) {
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

fn write_stdout(args: std::fmt::Arguments<'_>) {
    let _ = std::io::stdout().lock().write_fmt(args);
}

fn usage() {
    eprintln!(
        "usage: nlc run <package-dir> [--allow-overcommit] | nlc build <package-dir> -o <file> | nlc test <package-dir> | nlc parse <package-dir> [--tree] [--tokens] | nlc inspect memory <package-dir> [--allow-overcommit] | nlc inspect contracts <package-dir> | nlc inspect stacks <package-dir>"
    );
}
