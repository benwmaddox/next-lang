# T20: files, arguments and output through capabilities (self-hosting step S0, part 2)

Depends on T19. Same rules. Read DESIGN.md "Effects and capabilities" and the overview's `main(env: Env)`. This is a minimal first slice of effects, enough for the self-hosted lexer and parser (S1) to read source files and write their output; full effects and the process capability come later.

- **Entry with capabilities:** `fn main(env: Env)` (the old `fn main()` still works). `Env` gives `env.args() -> list<Arg, 64>` (each `Arg` a `list<byte, 4096>`, too long or too many arguments being a startup error), `env.fs: Fs`, `env.out: Out` and `env.err: Out`. Capabilities are ordinary read parameters: a function can only reach the file system if it's handed `fs`.
- **Effects in contracts:** functions that use `Fs` or `Out` get the effects `fs.read`, `fs.write` and `out` in their contracts, inferred transitively (like `print` today); they aren't cacheable (T05), aren't allowed in parallel bodies, and appear in function types (T11) the same way `print` does.
- **Bytes for now:** until M3 brings `Bytes` and `Text`, file contents are `list<byte, N>`. Operations:
  - `fs.read(path, buf: write list<byte, N>) -> Result<(), IoError>`: reads the whole file into `buf`; a file longer than `N` is `err(TooLarge)` and `buf` is left empty; `IoError` is an enum (`NotFound`, `NoPermission`, `TooLarge`, `Other(int)`).
  - `fs.list(dir, names: write list<Arg, N>) -> Result<(), IoError>` for a directory's entries (sorted, so output is deterministic).
  - `fs.write(path, data: list<byte, N>) -> Result<(), IoError>` (creates or replaces the file).
  - `out.write(data)` and `out.line(data)` for byte lists, plus `out.int(n)` and `out.long(n)` until T18's formatting exists.
  - Paths are `list<byte, 4096>` here; `"literal"` byte lists are allowed for paths and output (`b"..."` or a string literal in a byte-list context).
- **Tests:** `nlc test` gives tests an `Env` whose file system is a temporary directory (so tests can write and read files without touching the real one); a test can use `test "name" (env: Env) { ... }`.
- **Acceptance cases:** reading a file and counting its lines; a missing file (`NotFound`); a file larger than the buffer (`TooLarge`, buffer empty); writing then reading back; listing a directory in sorted order; arguments passed to `nlc run <dir> -- a b c`; a function reaching `fs` without being handed it (build error: it has no capability); a `const` calling a function that reads a file (build error naming `fs.read`); output to `out` and `err` separately.
- Report: docs/tasks/T20-report.md.
