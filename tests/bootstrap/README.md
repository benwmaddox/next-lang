# C-runtime bootstrap fixtures

These three packages check the compiler-used C I/O path. They are separate from
the existing core-only classification table; they do not require a core I/O
port or runtime-specific classifications.

Run the C-runtime bootstrap check with an existing language-written compiler:

```sh
python scripts/check-selfhost-c-io.py --compiler /path/to/selfhost [--clang clang]
```

The script compiles all packages with `--runtime=c` at O1 and O3, links the IR
directly with clang and `runtime/nl_runtime.c` using
`-DNLC_STACK_MODE_OFFSET=1`, then compares status/stdout/stderr with the
checked-in oracles. It makes eight runs, including the `alpha beta` argument
case, record-field output, and `c_io_files/expected.args`. The files fixture
also joins and reads each listed entry by its `DirEntry.name` path while
preserving its output oracle. It runs from temporary package copies so
generated `output.data` does not touch the checkout. NLC test settings are
cleared for each run and `NLC_OPT_LEVEL` is set explicitly.

On failure, the script keeps its repo-local `.c-bootstrap-smoke-*` directory
with generated IR, binaries, command output, and `report.json`.

The checked outputs were captured from frozen Stage0 at both optimization
levels. Passing these is an I/O smoke check, not compiler-corpus validation.
