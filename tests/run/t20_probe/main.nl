fn count_lines(fs: Fs, path: Path) -> Result<long, IoError> {
    var bytes: list<byte, 128> = list {}
    fs.read(path, bytes)?
    var lines: long = 0L
    for index in 0L..bytes.count() {
        if bytes[index] == 10 {
            lines += 1L
        }
    }
    ok(lines)
}

fn main(env: Env) -> Result<(), IoError> {
    let fs = env.fs
    fs.write("a.txt", b"one\ntwo\nthree\n")?
    print(count_lines(fs, "a.txt")?)

    var bytes: list<byte, 128> = list {}
    match fs.read("missing.txt", bytes) {
        err(NotFound) => print(NotFound),
        _ => print(-1)
    }
    match fs.read("../etc/passwd", bytes) {
        err(Outside) => print(Outside),
        _ => print(-1)
    }
    match fs.read("/etc/passwd", bytes) {
        err(Outside) => print(Outside),
        _ => print(-1)
    }

    var entries: list<DirEntry, 16> = list {}
    fs.list(".", entries)?
    let out = env.out
    for entry in entries {
        out.line(entry.name)?
    }
    ok(())
}
