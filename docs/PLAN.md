# Implementation plan

Started 2026-10-24, after the design rounds in DESIGN.md converged. Ben's decisions for the build: the compiler is written in **Rust**; it emits **LLVM IR as text** (as Burin's helper compiler does) and builds it with **clang**; development and tests run on **Linux (WSL)** first, Windows later.

## Roles

- **Claude** (manager and reviewer): writes each task (docs/tasks/T*.md) with its acceptance tests, reviews the diff and the test run, asks for fixes, commits and pushes. Keeps DESIGN.md and this plan current.
- **Codex, `gpt-6-luna`, reasoning `max`** (implementer): implements one task at a time in this repository. Never commits, never creates or switches branches. Ends each task with a short report (docs/tasks/T*-report.md): what it built, how to run it, what's left, and any place it had to choose something the task didn't say.
- **Codex, `gpt-6.1-sol`, reasoning `high`** (peer): reviews plans and tasks before they go to Luna, and is asked when a design question comes up during the build.

## Layout

```
Cargo.toml              workspace
compiler/               the `nlc` compiler (Rust): lexer, parser, checker, LLVM IR emitter, driver
runtime/                the small runtime the generated code links against (C, compiled by clang)
tests/                  language tests: one directory per program, with expected output
docs/                   DESIGN.md, EXAMPLES.md, PLAN.md, tasks/, reviews/
```

Commands (in WSL; Codex itself runs inside WSL, with its own settings in `~/.codex-nl` and the binary in `~/.local/codex-nl`): `cargo build`, `cargo test` (the compiler's own tests and the language tests), and `nlc run <dir>` / `nlc test <dir>` on a package directory. The Cargo target directory lives in the WSL home (`CARGO_TARGET_DIR=~/.cache/next-lang/target`), not on the Windows drive, so builds stay fast.

## Milestones

Each is small enough to review in one sitting, ends with passing tests, and maps to DESIGN.md's first steps.

- **M0 Pipeline,** in two tasks. T01: the whole path from source to a native program, with a typed representation between the checker and the emitter, functions, scalars, checked arithmetic and casts, `if`, calls, `print` and build errors. T02: `for` loops over `..` and `..=` ranges with `break`/`continue`, and `test` blocks with `nlc test`.
- **M1 Values.** Uses the refinement contract decided 2026-10-24 (DESIGN.md, "The refinement contract": prove it or write a cast). Then: `enum` with payloads and exhaustive `match`; `Option` and `Result` with `?`, `?.`, `??` (including `?? return/continue/break`); `struct` with field defaults and initialisers; named refinements and range refinements on integers (checked on store; `wrap` and `clamp`); `const` with compile-time evaluation.
- **M2 State and ids (DESIGN step 1, fixed-size part).** Fixed arrays `T[N]`, `list<T, N>`, `pool<T, N>` with generation-checked ids, as locals and in a small `global`, holding fixed-size fields only; structure-of-arrays layout, nested collections flattened; `Full` as a `Result`, `discard`; writable loop views and the no-removal-while-viewing rule. Step 1's cases that need text payloads, large-local scratch, iteration cleanup or suspension move to M3 or later; the task lists which cases it owns.
- **M3 Data stacks (DESIGN step 2).** Growing values (`Ascii`, then `Text` and `Bytes`) on compiler-assigned data stacks: stack contracts, fresh-result and append modes, iteration scopes, bounds per entry point, `inspect stacks`. All of DESIGN.md's step 2 acceptance cases.
- **M4 onwards** follow DESIGN.md's first steps 3 to 7 (refinements as LLVM facts, measured on DEFLATE; `check fast == reference`; effects; builders, `freeze` and parallel loops), each planned when the one before is done.

## Rules for every task

- Tests first-class: every feature lands with language tests (a program and its expected output, or a `test` block), and every error the compiler reports lands with a test that triggers it.
- Error messages name the line and say what to do, as DESIGN.md's Development experience asks.
- No dependency on Burin; code may be copied from it (D:\code\burin, Apache 2.0) with a note in the file.
- No new external Rust crates without saying why in the report.
- Keep it simple: no optimisation passes of our own; LLVM does that.
