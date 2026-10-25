fn read_data(fs: Fs, buffer: write list<byte, 3>) -> Result<(), IoError> {
    fs.read("source", buffer)
}

fn read_wrapper(fs: Fs, buffer: write list<byte, 3>) -> Result<(), IoError> {
    read_data(fs, buffer)
}

fn write_data(fs: Fs, path: Path, data: Path) -> Result<(), IoError> {
    fs.write(path, data)
}

fn write_through_callback(
    fs: Fs,
    path: Path,
    data: Path,
    callback: fn(Fs, Path, Path) -> Result<(), IoError> effects fs.write
) -> Result<(), IoError> {
    callback(fs, path, data)
}

fn list_data(fs: Fs, entries: write list<DirEntry, 2>) -> Result<(), IoError> {
    fs.list(".", entries)
}

fn list_through_callback(
    fs: Fs,
    entries: write list<DirEntry, 2>,
    callback: fn(Fs, write list<DirEntry, 2>) -> Result<(), IoError> effects fs.read
) -> Result<(), IoError> {
    callback(fs, entries)
}

fn read_through_callback(
    fs: Fs,
    buffer: write list<byte, 3>,
    callback: fn(Fs, write list<byte, 3>) -> Result<(), IoError> effects fs.read
) -> Result<(), IoError> {
    callback(fs, buffer)
}

test "missing file is reported and clears the output list" (env: Env) {
    let fs = env.fs
    var buffer: list<byte, 3> = list {}
    match fs.read("missing", buffer) {
        err(NotFound) => { expect true },
        _ => { expect false }
    }
    expect buffer.count() == 0L
}

test "file read effects pass through wrappers and bounded function values" (env: Env) {
    let fs = env.fs
    var buffer: list<byte, 3> = list {}
    match fs.write("source", b"abc") { ok(_) => {}, _ => { expect false } }
    match read_wrapper(fs, buffer) {
        ok(_) => { expect buffer.count() == 3L },
        _ => { expect false }
    }
    match read_through_callback(fs, buffer, read_data) {
        ok(_) => { expect buffer.count() == 3L },
        _ => { expect false }
    }
}

test "write and list effects keep their bounds in function values" (env: Env) {
    let fs = env.fs
    var entries: list<DirEntry, 2> = list {}
    var buffer: list<byte, 3> = list {}
    match write_through_callback(fs, "callback", b"abc", write_data) {
        ok(_) => {},
        _ => { expect false }
    }
    match fs.read("callback", buffer) {
        ok(_) => { expect buffer.count() == 3L },
        _ => { expect false }
    }
    match list_through_callback(fs, entries, list_data) {
        ok(_) => { expect entries.count() == 1L },
        _ => { expect false }
    }
}

test "paths reject embedded zero and attempts to leave the root" (env: Env) {
    let fs = env.fs
    var buffer: list<byte, 3> = list {}
    var bad: Path = list {}
    discard bad.push(97)
    discard bad.push(0)
    discard bad.push(98)
    match fs.read(bad, buffer) {
        err(BadPath) => { expect true },
        _ => { expect false }
    }
    match fs.read("/absolute", buffer) {
        err(Outside) => { expect true },
        _ => { expect false }
    }
    match fs.read("../outside", buffer) {
        err(Outside) => { expect true },
        _ => { expect false }
    }
}

test "exact capacity succeeds and the next byte is too large" (env: Env) {
    let fs = env.fs
    var buffer: list<byte, 3> = list {}
    match fs.write("exact", b"abc") {
        ok(_) => {},
        _ => { expect false }
    }
    match fs.read("exact", buffer) {
        ok(_) => { expect buffer.count() == 3L },
        _ => { expect false }
    }
    match fs.write("large", b"abcd") {
        ok(_) => {},
        _ => { expect false }
    }
    match fs.read("large", buffer) {
        err(TooLarge) => { expect buffer.count() == 0L },
        _ => { expect false }
    }
}

test "directory entries are sorted and include their kind" (env: Env) {
    let fs = env.fs
    var entries: list<DirEntry, 4> = list {}
    match fs.write("z", b"") {
        ok(_) => {},
        _ => { expect false }
    }
    match fs.write("a", b"") {
        ok(_) => {},
        _ => { expect false }
    }
    match fs.list(".", entries) {
        ok(_) => {
            expect entries.count() == 2L
            expect entries[0L].name[0L] == 97
            expect entries[0L].kind == FileKind.File
            expect entries[1L].name[0L] == 122
        },
        _ => { expect false }
    }
    match fs.list("../outside", entries) {
        err(Outside) => { expect entries.count() == 0L },
        _ => { expect false }
    }
}

test "directory listing over capacity is empty" (env: Env) {
    let fs = env.fs
    var entries: list<DirEntry, 1> = list {}
    match fs.write("a", b"") { ok(_) => {}, _ => { expect false } }
    match fs.write("b", b"") { ok(_) => {}, _ => { expect false } }
    match fs.list(".", entries) {
        err(TooMany) => { expect entries.count() == 0L },
        _ => { expect false }
    }
}

test "directory listing exactly at capacity succeeds" (env: Env) {
    let fs = env.fs
    var entries: list<DirEntry, 1> = list {}
    match fs.write("only", b"") { ok(_) => {}, _ => { expect false } }
    match fs.list(".", entries) {
        ok(_) => { expect entries.count() == 1L },
        _ => { expect false }
    }
}

test "read publishes only written bytes and clears the count on failure" (env: Env) {
    let fs = env.fs
    var buffer: list<byte, 3> = list {}
    discard buffer.push(81)
    discard buffer.push(82)
    match fs.write("short", b"a") { ok(_) => {}, _ => { expect false } }
    match fs.read("short", buffer) {
        ok(_) => {
            expect buffer.count() == 1L
            expect buffer[0L] == 97
        },
        _ => { expect false }
    }
    match fs.read("missing", buffer) {
        err(NotFound) => { expect buffer.count() == 0L },
        _ => { expect false }
    }
}

test "join stays inside the root and checks its byte bound" (env: Env) {
    let fs = env.fs
    let expected: Path = b"folder/child"
    var long_path: Path = list {}
    for i in 0..4096 { discard long_path.push(97) }
    match fs.join("folder", "child") {
        ok(path) => { expect path == expected },
        _ => { expect false }
    }
    match fs.join("folder", "../../escape") {
        err(Outside) => { expect true },
        _ => { expect false }
    }
    match fs.join("/absolute", "child") {
        err(Outside) => { expect true },
        _ => { expect false }
    }
    match fs.join(long_path, "child") {
        err(TooLarge) => { expect true },
        _ => { expect false }
    }
}
