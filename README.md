# next-lang (working name)

A small Rust compiler that lowers the initial next-lang subset to LLVM IR and uses clang to build native programs. The current pipeline supports functions, `int`, `long` and `bool`, checked arithmetic and casts, `if`, calls, and `print`.

Build and run the compiler in WSL:

```sh
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
```

Use `nlc run <package-dir>` to compile and run a package, or `nlc build <package-dir> -o <file>` to write a native executable. A package is a directory containing one or more `.nl` files.

The implementation status and remaining milestones are in [docs/PLAN.md](docs/PLAN.md); the full language design is in [docs/DESIGN.md](docs/DESIGN.md).
