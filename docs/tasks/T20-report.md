# T20 report: files, arguments and output

## Implemented

- Added `Env`, `Args`, `Arg`, `Fs`, and `Out` capability types. `main(env: Env)` and `test "name" (env: Env)` receive runtime environments; existing `main()` and parameterless tests still work. `Args` and `Arg` are read-only views over `argv` and its strings, with `count()`/`get()` access and no argument-byte copies. `nlc run <package> -- ...` removes the separator before forwarding arguments.
- Added package grants in `package.toml` for `fs`, `out`, and `env`, retaining T19's memory settings. Missing grants produce an error naming the `capabilities` key. Capabilities can be passed and held directly in locals; globals, constants, and aggregate/collection storage reject them. Migrated the existing printing fixtures to grant `out`, changed their function-type bounds from `effects print` to `effects out`, and renamed all T19 fixture manifests. Updated the T19 report's manifest reference.
- Added the closed effects `out`, `env`, `fs.read`, and `fs.write` to function types and transitive effect analysis. `print` now infers `out`; argument access infers `env`; reads and listings infer `fs.read`; writes infer `fs.write`. The tests cover wrappers and function-value bounds for file effects.
- Added `byte` as a checked `0..=255` refinement, byte strings, `IoError`, `FileKind`, `Path`, and `DirEntry`. File operations take bounded byte lists or an `Arg` view. `fs.read` fills exactly to capacity, probes one extra byte, and leaves its output list empty on errors. `fs.list` returns sorted raw-byte names and entry kinds, and clears its output on overflow/errors. `fs.write` and output calls retry interrupted and short writes. `out.write` and `out.line` return `Result<(), IoError>`; a closed pipe is reported as `Other(errno)`.
- Rooted filesystem operations at the program's working directory. Linux `openat2` uses `RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS`; absolute paths, escaping `..`, and symlinks outside the root return `Outside`. Embedded zero bytes return `BadPath`. Test children get and remove a separate temporary root. `fs.join` returns `Result<Path, IoError>` so bound and escape failures are observable.
- Added fixtures for argument forwarding and startup limits, manifest/capability errors, byte range checking, isolated test file I/O, exact and over-capacity reads/lists, sorted entry kinds, `fs.join`, and separate stdout/stderr. Added integration checks for 64 arguments and 4096-byte arguments, separator removal, root escapes and symlinks, directory kinds, and output failure. No external crates were added.

## Decisions and limits

- `Args` and `Arg` use opaque pointer-backed view types rather than materialized `list<Arg, 64>` and `list<byte, 4096>` values. This preserves the required read-only, no-copy argument access while exposing bounded `count()` and `get()` operations.
- The correction requiring directory entry kinds takes precedence over the original `fs.list` signature: the output is `list<DirEntry, N>`, where each entry has a byte-list `name` and a `FileKind`.
- The task does not state `fs.join`'s result type. It returns `Result<Path, IoError>` to report an overlong or escaping path.
- `NameTooLong` is handled when a directory component exceeds the 4096-byte `Arg` bound. Linux limits individual directory names to at most 255 bytes, so that case cannot be constructed on the requested runtime and has no executable boundary fixture.
- A source-level constant cannot call a function that reads a file while also respecting the capability rules: the function must receive `Fs` or `Env`, but capabilities cannot be constructed or stored in constants/globals. The constant evaluator identifies `fs.read` as the effect, but the acceptance program described in T20 is not expressible without violating those rules. Effect propagation for `fs.read` is covered through ordinary calls and function values.
- `fs.list` includes regular files, directories, and other entries using no-follow metadata; symlinks are classified as `Other`. Test roots are created per test child, so one test cannot observe another test's files.

## Verification

Ran in WSL:

```text
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build --workspace
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test --workspace
```

All commands passed. The test suite includes all existing run/test fixtures and the T20 capability, argument, file-system, and output checks.

## Fix round 1

- Packages without `package.toml`, and manifests without a `capabilities` key, receive `out` by default. An explicit capabilities array replaces that default; `fs` and `env` remain explicit grants. Removed the output-only manifests added to older fixtures while keeping the renamed T19 manifests and manifests with other settings. Added fixtures for default output, an explicit `fs`-only grant refusing `print`, and `env.args()` without an `env` grant.
- Dropping a `Result` in an expression statement or a discarded block value is now a build error with handling guidance. Statically proven successful collection operations retain their existing behavior, and `discard` remains limited to collection operations that can return `Full`. Updated output fixtures to use `?` and Result-returning entry points.
- `main` may return `Result<(), E>`. Returning `err(e)` writes `error: ` and the printed error value to stderr, then exits 1. Tests may end with `Result<(), E>`; `err(e)` prints the same diagnostic and fails that test. Added coverage for both paths.
- Added the filesystem probe: it writes three lines to `a.txt`, counts them through an `Fs` helper using `?`, checks `NotFound` and both outside-root path forms, then lists the package files in sorted order.
- A failed `print(...)` write to stdout calls `nl_fail` with `standard output write failed`. In a normal run this exits 1; in test mode, runtime failures use the existing exit code 70. A closed-pipe integration test verifies the normal-run behavior.

Verification passed:

```text
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build --workspace
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test --workspace
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check
```
