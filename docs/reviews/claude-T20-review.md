# Claude: T20 review (files, arguments and output)

**Verdict:** approved after one fix round.

Checked: cargo build and test pass (new compiler/tests/capabilities.rs covers 64 and 4,096-byte arguments, `--` removal, root escapes through symlinks, closed-pipe output). My probe (~/nlprobe/w2) through a helper taking `Fs` and using `?`: writing and reading back three lines gives `ok(3)`; `missing.txt` is `err(NotFound)`; `../etc/passwd` and `/etc/passwd` are both `err(Outside)`; `fs.list(".")` returns the files in sorted order.

Fix round 1 (prompt-T20-fix1.md), two rule changes now in DESIGN.md:

1. Luna had made every printing program need a `package.toml` granting `out` (134 fixtures gained one). Decided: no `capabilities` key, or no manifest, grants `out` only; `fs` and `env` are explicit; an explicit list replaces the default.
2. An unused `Result` compiled silently (a T03-era gap that T20 made common, since `out.line` returns one). It's now a build error; `main` and tests may return `Result`, and an `err` there prints `error: <value>` and exits 1. `discard` stays limited to `Full`. A failed `print` write fails the job (`nl_fail`).

Accepted deviations:

- `Args`/`Arg` are opaque read-only views with `count()`/`get()`, not `list<Arg, 64>` values (no copy, as the corrections require).
- `fs.list` fills `list<DirEntry, N>` (name and kind); `fs.join` returns `Result<Path, IoError>`.
- The "const calling a function that reads a file" case can't be written: capabilities can't exist in a `const`. Effect naming is covered through calls and function values instead.
- `NameTooLong` can't be produced on Linux (names are at most 255 bytes); no fixture.
