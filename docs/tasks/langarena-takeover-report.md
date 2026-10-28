# LangArena comparison audit and takeover report

## Changes

- Added a per-package audit note for every buildable package, retained idiomatic variant, and float-dependent pending port. The audit records whether a port matches Crystal's algorithm and data shape, was rewritten to match it, has a known remaining difference, or cannot yet run.
- Added `prep` handling to Calculator::Ast, Calculator::Interpreter, and the retained idiomatic Huffman encoder. The checker had accepted their numeric output without verifying that they stopped before timed rounds.
- Tightened `check.py` to require the exact one-line checksum and a successful prep invocation with one decimal line. It continues to allow a prep checksum equal to the normal checksum, since a benchmark can have zero checksum contribution from the timed rounds.
- Tightened `compare-rust.py` to verify every next-lang checksum and exit status, the prep output, the Rust runner's exit and result line, nonzero timing values, successful builds, and positive estimated net time. Any build or measurement failure now makes the script exit nonzero.
- The comparison reads each audit verdict. `like-for-like` and `rewritten-to-match` ports contribute to the headline geometric mean. `closest-possible`, variants, and library-substitute ports appear in separate sections.
- Documented that next-lang body time is an estimate obtained by subtracting separate whole-process measurements; the result includes process and timing noise.

## Validation

- `cargo build --offline --release` — passed. Cargo found the release stage-0 artifact up to date.
- `python3 -m py_compile bench/langarena/check.py bench/langarena/compare-rust.py` — passed.
- `NLC=/home/ben/.cache/next-lang/target/release/nlc python3 bench/langarena/check.py --mode test` — 46 checked, 0 failed, 5 pending on floats. This checks normal checksums and prep output shape for every buildable package, including variants and not-comparable ports.
- With the shared benchmark lock, `check.py --mode run --time maze_generator maze_generator_idiomatic` — both passed with checksum `3738188563`; this also confirms that equal prep and full checksums are valid for this benchmark.
- `compare-rust.py --runs 1 base64_encode` — real next-lang and LangArena Rust outputs passed; exit 0.
- `compare-rust.py --runs 1 binarytrees_obj` — real outputs passed and the `closest-possible` audit placed the result outside the headline; exit 0.
- A temporary subprocess-stub smoke test passed its valid case and confirmed nonzero exits for a wrong checksum, malformed prep output, prep failure, build failure, Rust nonzero exit, and a zero Rust timing. The temporary test script was removed.
- `git diff --check` — passed.

## Limits

The all-package `--mode run --time` command was stopped before it produced results to avoid running a broad timing workload while another task was active. Only the two maze-generator packages were checked at full parameters. The timing comparison remains an estimate from separate processes, as the output and README state. Five packages remain pending until float support lands: CSV::Parse, Distance::Jaro, Distance::NGram, Json::ParseDom, and Json::ParseMapping.
