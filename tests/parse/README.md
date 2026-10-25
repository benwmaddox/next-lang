# Parse reference corpus

`dumps/run/` and `dumps/test/` contain the combined `nlc parse --tokens --tree` output (or first syntax diagnostic) for every package in `tests/run/` and `tests/test/`, except the live-only stress fixtures below. Successful snapshots use one `.dump` file per package to reduce filesystem overhead. `cases/` adds malformed syntax, UTF-8 and integer boundaries, an empty file, a 70,000-byte line, and excessive nesting. Their expected output is in `dumps/cases/`, except the live-only long line.

The 1,000-deep expression fixtures (`t19_expression_plus_1000`, `t19_expression_and_1000`, `t19_expression_call_1000`, `t19_expression_if_300`, and `t19_expression_paren_1000`), `t12_sort_specialization_limit`, and `cases/long_line` have no frozen dumps. The integration test parses each package twice, checks byte-for-byte repeatability, and validates every live tree's span structure. This keeps stored dumps below 100 KB each without weakening the corpus checks.

Run `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test` to compare the implementation against these frozen files. Tests never update snapshots. To intentionally regenerate them after reviewing a format change, run `CARGO_TARGET_DIR=$HOME/.cache/next-lang/target scripts/update-parse-dumps.sh --update`.
