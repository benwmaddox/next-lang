use std::io::Write;
use std::path::Path;
use std::process::ExitCode;

use next_lang::{
    Frontend, PackageError, build_package_with_frontend, inspect_contracts, inspect_memory,
    inspect_stacks, lex_package_with_frontend, parse_package_with_frontend,
    link_ir, run_package_args_with_frontend, test_ir, test_package_with_frontend,
};

fn main() -> ExitCode {
    let mut args = std::env::args_os();
    let _program = args.next();
    let mut rest = args.collect::<Vec<_>>();
    let mut explicit_frontend = None;
    if rest
        .first()
        .is_some_and(|arg| arg.to_string_lossy().starts_with("--frontend="))
    {
        let arg = rest.remove(0);
        match parse_frontend_arg(&arg) {
            Ok(frontend) => explicit_frontend = Some(frontend),
            Err(()) => {
                usage();
                return ExitCode::from(3);
            }
        }
    }
    let Some(command) = rest.first().and_then(|x| x.to_str()).map(str::to_owned) else {
        usage();
        return ExitCode::from(3);
    };
    rest.remove(0);
    let separator = rest.iter().position(|arg| arg == "--");
    let frontend_end = separator.unwrap_or(rest.len());
    let frontend_positions = rest[..frontend_end]
        .iter()
        .enumerate()
        .filter_map(|(index, arg)| {
            arg.to_string_lossy()
                .starts_with("--frontend=")
                .then_some(index)
        })
        .collect::<Vec<_>>();
    if frontend_positions.len() > usize::from(explicit_frontend.is_some()) + 1 {
        usage();
        return ExitCode::from(3);
    }
    if let Some(index) = frontend_positions.first().copied() {
        if explicit_frontend.is_some() {
            usage();
            return ExitCode::from(3);
        }
        match parse_frontend_arg(&rest[index]) {
            Ok(frontend) => explicit_frontend = Some(frontend),
            Err(()) => {
                usage();
                return ExitCode::from(3);
            }
        }
        rest.remove(index);
    }
    let frontend = match explicit_frontend {
        Some(frontend) => frontend,
        None => match Frontend::from_environment() {
            Ok(frontend) => frontend,
            Err(message) => return report_error(PackageError::Tool(message)),
        },
    };
    match command.as_str() {
        "run" if !rest.is_empty() => {
            let arguments = if rest.get(1).is_some_and(|arg| arg == "--") {
                &rest[2..]
            } else {
                &rest[1..]
            };
            match run_package_args_with_frontend(Path::new(&rest[0]), arguments, frontend) {
                Ok(status) => ExitCode::from(status.code().unwrap_or(1) as u8),
                Err(error) => report_error(error),
            }
        }
        "test" if rest.len() == 1 => {
            match test_package_with_frontend(Path::new(&rest[0]), frontend) {
                Ok(code) => ExitCode::from(code),
                Err(error) => report_error(error),
            }
        }
        "link-ir" if rest.len() == 3 && rest[1] == "-o" => {
            match link_ir(Path::new(&rest[0]), Path::new(&rest[2])) {
                Ok(()) => ExitCode::SUCCESS,
                Err(error) => report_error(error),
            }
        }
        "test-ir" if rest.len() == 1 => match test_ir(Path::new(&rest[0])) {
            Ok(code) => ExitCode::from(code),
            Err(error) => report_error(error),
        },
        "lex" if rest.len() == 1 => {
            match lex_package_with_frontend(Path::new(&rest[0]), frontend) {
                Ok(tokens) => {
                    write_stdout(format_args!("{tokens}"));
                    ExitCode::SUCCESS
                }
                Err(error) => report_error(error),
            }
        }
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
                match parse_package_with_frontend(Path::new(&rest[0]), frontend) {
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
            match build_package_with_frontend(Path::new(&rest[0]), Path::new(&rest[2]), frontend) {
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
        "usage: nlc [--frontend=rust|selfhost] run <package-dir> [--frontend=rust|selfhost] [--allow-overcommit] [-- <args...>] | nlc build <package-dir> -o <file> [--frontend=rust|selfhost] | nlc test <package-dir> [--frontend=rust|selfhost] | nlc link-ir <file.ll> -o <exe> | nlc test-ir <file.ll> | nlc lex <package-dir> [--frontend=rust|selfhost] | nlc parse <package-dir> [--tree] [--tokens] [--frontend=rust|selfhost] | nlc inspect memory <package-dir> [--allow-overcommit] | nlc inspect contracts <package-dir> | nlc inspect stacks <package-dir>"
    );
}

fn parse_frontend_arg(argument: &std::ffi::OsStr) -> Result<Frontend, ()> {
    let value = argument.to_str().ok_or(())?;
    let value = value.strip_prefix("--frontend=").ok_or(())?;
    Frontend::parse(value).map_err(|_| ())
}
