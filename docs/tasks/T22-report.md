# T22 report: parser nesting limits

## Implemented

- Changed the parser's expression recursion guard from 2,048 to the documented 1,000 expression constructs. It permits a terminal value at the boundary; the finished-tree walk checks shapes that the parser builds iteratively, such as left-associative binary chains. Added matching guards for right-associative coalescing and the cast-to-prefix recursive path.
- Replaced recursive `else if` parsing with a loop and a stack of pending `If` frames. The initial `if` is clause one, so clause 1,000 parses and clause 1,001 fails at its `if` token before that clause's condition or block is parsed. The AST and synthetic `Block` spans remain unchanged.
- Changed the block-limit diagnostic to `block nesting limit of 1000 exceeded`. Type errors continue to name the type limit; expression constructs use the expression-limit diagnostic.
- Expanded `syntax-tree-format.md` to define the counted constructs, root-print depth, branch-block counting, chain count, and diagnostic byte positions.
- Added debug-`nlc` generated boundary coverage for 1,000 and 1,001 grouped parentheses, `!` and `-` operators, `+` and `??` chains, calls, casts, match expressions, `if` clauses, active blocks, and nested types. The failures assert status 2 and the exact diagnostic position.

## Recursion audit

- `type_name` and `type_name_inner` recurse through nested generic, grouped, and function types. `type_depth` allows at most 1,000 active type parses.
- `block` recurses through nested block statements and loop/control-flow bodies. `block_depth` allows at most 1,000 active blocks; the function or test body is level one.
- Expression parsing recurses through nested prefix expressions, call arguments, indexes, struct fields, conditions, match arms, and right-associative `??`. `expression_depth` guards expression constructs at 1,000, and the finished-tree check enforces the same semantic depth on the completed AST.
- Cast expressions recurse from `cast_expression` directly through `prefix`, bypassing `expression`; the new `cast_depth` guard caps this path at 1,000.
- Grouped parentheses have their own 1,000-level `parenthesis_depth` guard.
- `if_expression` no longer recurses for `else if`; it closes its saved frames iteratively and counts the initial `if` toward the 1,000-clause limit.
- `expression_nesting_exceeded`, the finished-tree walk, is already an explicit `Vec` worklist and has no Rust recursion. The syntax-tree formatter recursively visits parsed ASTs; those inputs are limited by the parser counters above. The 1,000-clause formatter path is covered by the boundary test.

## Stress case and verification

A generated chain with 100,000 `else if` links after its initial `if` (1,800,047 bytes) failed at clause 1,001, line 1 column 18,020, with status 2. The debug `nlc parse` run took 0.14 seconds and reached 134,992 KiB peak RSS, including lexing the full source before parsing.

Ran from WSL:

```text
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo build
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo fmt --all -- --check
CARGO_TARGET_DIR=$HOME/.cache/next-lang/target cargo test
```

All commands passed. The full test suite includes every run/test fixture and all frozen parse-corpus comparisons. No parse dumps needed regeneration, and no external crates were added.

## Scope and choice

The task calls the 1,001st `else if` link the failure point. I count the initial `if` as clause one, matching the completed-tree walk's existing depth and the documented 1,000/1,001 chain boundary. There is no remaining T22 implementation work.

## Fix round 1: checker regression

The checker repeatedly inferred natural types while recursively asking whether each `+` operand could be Ascii. On a left-associated expression, that repeated the analysis of each earlier subtree. The numeric binary checker also cloned the complete typed left subtree at every node, which made a long chain quadratic even after the Ascii probe was cached. The checker now memoizes natural types and Ascii possibility per AST expression during one outer expression check, and moves the typed left subtree into its parent.

The T15 loop-growth analyses also revisited nested loop bodies. Loop write candidates are collected once per AST block and resolved in the current binding scope; checked-append and plain-append roots are summarized once per typed block. Those caches are cleared for each function or test. The added regression test compiles 1,000-term long, Ascii, `&&`, and nested-call expressions under a two-second debug bound, and checks 750 nested Ascii-growth loops under the same bound.

The table shows elapsed time for a debug `nlc inspect contracts` run. The pre-fix long-chain measurements through N=1,000 are the reviewer's recorded results; the other pre-fix values were measured with the saved pre-fix debug binary. Post-fix values are medians of three runs. For N=2,000, each package contains two independent 1,000-term expressions because the T22 parser limit rejects a single 2,000-deep chain. The two call chains are each 1,000 nested calls.

| Shape | Before N=250 | After N=250 | Before N=500 | After N=500 | Before N=1,000 | After N=1,000 | Before N=2,000 | After N=2,000 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `long` addition chain | 0.72 s | 0.0087 s | 5.75 s | 0.0157 s | 47.7 s | 0.0303 s | 93.471 s | 0.0428 s |
| Ascii concatenation proven to fit | 0.028 s | 0.0066 s | 0.049 s | 0.0129 s | 0.169 s | 0.0259 s | 0.318 s | 0.0363 s |
| `&&` chain | 0.006 s | 0.0058 s | 0.011 s | 0.0106 s | 0.020 s | 0.0203 s | 0.027 s | 0.0276 s |
| Nested calls | 0.006 s | 0.0061 s | 0.012 s | 0.0116 s | 0.024 s | 0.0228 s | 0.034 s | 0.0349 s |

The Ascii case uses `s: Ascii max 10 = "x"` and stores N copies of `s` in `Ascii max N`, so the checker must use the known length range to prove the concatenation fits. The N=2,000 values use two separate `Ascii max 1000` results. These timings cover parsing, checking, stack-contract inspection, and IR emission; the original regression is in checker work.
