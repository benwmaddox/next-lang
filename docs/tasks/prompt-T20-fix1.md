You are implementing next-lang, task T20 (files, arguments and output), fix round 1. Repo: /mnt/d/code/next-lang. Read docs/tasks/T20-files-and-args.md and docs/tasks/T20-report.md. Same rules: do not commit, do not create, switch or stash branches, do not edit docs/DESIGN.md, docs/PLAN.md, docs/EXAMPLES.md or docs/reviews/, use CARGO_TARGET_DIR=$HOME/.cache/next-lang/target, no external crates.

Reviewer decisions and findings:

1. **Default grant (decided by Claude as manager):** a package whose manifest has no `capabilities` key, or that has no package.toml at all, is granted `out` only. So `fn main() { print(1) }` with no manifest works again. `fs` and `env` (and `env.args()`) always need an explicit grant; an explicit `capabilities = [...]` list replaces the default (so `capabilities = ["fs"]` means no `out`). Remove the package.toml files you added to existing fixtures whose only purpose was granting `out` (keep the ones with other settings, and the renamed T19 manifests). Add fixtures: print with no manifest; print with `capabilities = ["fs"]` refused naming `out`; env.args() with no manifest refused naming `env`.

2. **An unused `Result` must be a build error.** DESIGN.md line 202: a `Result` "the code must handle". Today `fn f() -> Result<(), int> { err(3) }` then `f();` as a statement compiles and silently drops the error, and every `out.line(...)` in your fixtures drops its `Result<(), IoError>`. Make an expression statement (or a block's discarded value) of type `Result` a build error that says to handle it with `?`, `match`, `??` or (for `Full` from a collection) `discard`. `discard` stays limited to `Full`, as decided. So that output stays practical:
   - `fn main() -> Result<(), E>` and `fn main(env: Env) -> Result<(), E>` are allowed; an `err(e)` result prints `error: ` and the printed value of `e` to standard error and exits 1. Tests may likewise end with a `Result`, and an `err` fails the test with the printed value.
   - `print(...)` itself stays a statement with no result (a failed write to stdout from `print` exits the program with status 1 via nl_fail, as now if it does; check and state what happens).
   Update every existing fixture that drops a `Result` (use `?` with a `Result`-returning main where it reads naturally).

3. Add my probe as a fixture (adjusted to compile): write `a.txt` with three lines, count its lines through a helper taking `Fs` and using `?`; `missing.txt` gives `err(NotFound)`; `../etc/passwd` and `/etc/passwd` give `err(Outside)`; `fs.list(".")` shows `a.txt` and the program's own files in sorted order.

Run cargo build, cargo test and cargo fmt -- --check. Append a "Fix round 1" section to docs/tasks/T20-report.md, including what `print` does on a failed write.
