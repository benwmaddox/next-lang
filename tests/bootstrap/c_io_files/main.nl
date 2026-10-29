fn write_data(env: Env, out: Out, data: Bytes max 4096) {
    match out.write(data) {
        ok(_) => (),
        err(_) => env.exit(3),
    }
}

fn fail_io(env: Env, error: IoError) -> never {
    let error_stream = env.err
    match error {
        IoError.NotFound => write_data(env, error_stream, b"io=NotFound\n"),
        IoError.NoPermission => write_data(env, error_stream, b"io=NoPermission\n"),
        IoError.TooLarge => write_data(env, error_stream, b"io=TooLarge\n"),
        IoError.TooMany => write_data(env, error_stream, b"io=TooMany\n"),
        IoError.NameTooLong => write_data(env, error_stream, b"io=NameTooLong\n"),
        IoError.BadPath => write_data(env, error_stream, b"io=BadPath\n"),
        IoError.Outside => write_data(env, error_stream, b"io=Outside\n"),
        IoError.Other(_) => write_data(env, error_stream, b"io=Other\n"),
        IoError.InvalidUtf8 => write_data(env, error_stream, b"io=InvalidUtf8\n"),
    }
    env.exit(2)
}

fn copy_path(path: Path) -> Bytes max 4096 {
    var bytes: Bytes max 4096 = Bytes.empty()
    for index in 0L..path.count() {
        match bytes.push(path[index]) {
            ok(_) => (),
            err(_) => return b"<name-too-long>",
        }
    }
    bytes
}

fn write_path(env: Env, out: Out, path: Path) {
    write_data(env, out, copy_path(path))
}

fn list_data_entries(fs: Fs, directory: Arg, entries: write list<DirEntry, 4>) -> Result<(), IoError> {
    fs.list_with_extension(directory, "data", entries)
}

fn read_entry_contents(fs: Fs, path: Path, contents: grow Bytes max 32) -> Result<(), IoError> {
    fs.read(path, contents)
}

fn main(env: Env) {
    let arguments = env.args()
    let directory = match arguments.get(0L) {
        some(value) => value,
        none => env.exit(2),
    }
    let fs = env.fs
    let out = env.out
    let input_path = match fs.join(directory, "input.data") {
        ok(path) => path,
        err(error) => fail_io(env, error),
    }
    var contents: Bytes max 32 = Bytes.empty()
    match fs.read(input_path, contents) {
        ok(_) => (),
        err(error) => fail_io(env, error),
    }

    let output_path = match fs.join(directory, "output.data") {
        ok(path) => path,
        err(error) => fail_io(env, error),
    }
    match fs.write(output_path, contents) {
        ok(_) => (),
        err(error) => fail_io(env, error),
    }
    var round_trip: Bytes max 32 = Bytes.empty()
    match fs.read(output_path, round_trip) {
        ok(_) => (),
        err(error) => fail_io(env, error),
    }
    write_data(env, out, b"read=")
    write_data(env, out, round_trip)
    write_data(env, out, b"entries=\n")

    var entries: list<DirEntry, 4> = list {}
    match list_data_entries(fs, directory, entries) {
        ok(_) => (),
        err(error) => fail_io(env, error),
    }
    for index in 0L..entries.count() {
        let entry = entries[index]
        let joined_path = match fs.join(directory, entry.name) {
            ok(path) => path,
            err(error) => fail_io(env, error),
        }
        var entry_contents: Bytes max 32 = Bytes.empty()
        match read_entry_contents(fs, joined_path, entry_contents) {
            ok(_) => (),
            err(error) => fail_io(env, error),
        }
        match entry.kind {
            FileKind.File => write_data(env, out, b"file="),
            FileKind.Directory => write_data(env, out, b"directory="),
            FileKind.Other => write_data(env, out, b"other="),
        }
        write_path(env, out, entry.name)
        write_data(env, out, b"\n")
    }
}
