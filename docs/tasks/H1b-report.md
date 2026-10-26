# H1b implementation report

## Scope

Implemented item 1 only: one package input policy for `run`, `build`, `test`,
`parse`, and `lex` under both `--frontend=rust` and `--frontend=selfhost` (or
`NLC_FRONTEND`). Items 2 to 4 were dropped after the compiler split, as recorded
in `docs/PLAN.md`, Order of work item 3; no frontend performance work or new
measurements were done.

## Policy

The front ends use the same limits, diagnostics, and check order. Source files
are regular `.nl` files sorted by filename. The package must contain at least
one and at most 256 source files. For each file, the compiler checks the
16 MiB per-file byte limit, the 64 MiB cumulative package byte limit, UTF-8,
lexing (including the 1,000,000-token per-file and 2,048 delimiter-nesting
limits), and the 4,000,000-token package limit. It then parses with the shared
nesting limits, counts at most 2,000,000 nodes and 2,000,000 child edges per
package, and checks the 72,000,000-unit work limit after those counts. Failures
use the same message and precedence in every command and front end. Invalid
UTF-8 is a syntax diagnostic with status 2 everywhere.

`lex` continues to print tokens for lexically valid but syntactically invalid
input. It attempts parsing so the shared nesting, tree, and work limits apply,
but ignores ordinary parser errors and prints no partial output on failures.
Run/build/test apply the parse input limits before checking or code generation.
Selfhost storage now matches the accepted source, token, and file capacities;
the directory-entry buffer remains sized for entries that are not source
files.

Node and edge counts are related: each source file contributes one `Program`
node, and every other node is one edge, so package edges equal nodes minus
files. With equal node and edge caps, the node limit always fires first; an
edge-only N+1 package cannot be constructed.

## Validation

Added `compiler/tests/input_policy.rs`. Its boundary matrix checks N and N+1
for the source-file, per-file byte, package byte, per-file token, package
token, node, work, and parser nesting limits under all five commands and both
front ends. It also checks invalid UTF-8 diagnostics and status 2 for every
command/frontend pair. N-boundary run/build/test cases proceed past input
validation to the expected later checker error; parse and lex succeed.

Both full suites passed on the final tree:

- `ulimit -v 8000000 && timeout 1800s env CARGO_TARGET_DIR=$HOME/.cache/next-lang/target NLC_FRONTEND=rust cargo test`
- `ulimit -v 8000000 && timeout 1800s env CARGO_TARGET_DIR=$HOME/.cache/next-lang/target NLC_FRONTEND=selfhost cargo test`

The selfhost stack contract is now 947,885,026 bytes worst-case with a
947,888,128-byte data-stack reservation, reflecting the removed policy-mode
arguments and unified loader path.
