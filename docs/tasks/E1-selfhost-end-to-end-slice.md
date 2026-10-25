# E1: the self-hosted compiler, end to end, for a small subset

Ben (2026-10-25): after H1b, focus on the self-hosted compiler getting all the way to a correct executable. This is the first step of the E-track (PLAN.md): every stage in next-lang, for a small part of the language, then widen it task by task.

## Pipeline

`nlc run selfhost -- build <package> -o <file.ll>` (in selfhost/, next-lang): the existing lexer and parser, then a new **checker** and **code generator** for the subset below, writing LLVM IR text that the existing C runtime (runtime/nl_runtime.c) links against. `nlc link-ir <file.ll> -o <exe>` (a small Rust bridge in nlc) runs clang on it with the same flags, runtime and target nlc uses, including T19's frame-size step if recursion is in the subset (it isn't in E1). A later task gives next-lang a process capability so the self-hosted compiler can run clang itself.

## The E1 subset

`int`, `long`, `bool`; integer literals with T18-style range rules for `int`/`long`; `fn` declarations with parameters and results (read mode only); `let` and `var` with inference and annotations; assignment and compound assignment; arithmetic `+ - * / %` with the language's overflow and division checks (failing through `nl_fail` exactly as Rust nlc does, same messages, line numbers and exit statuses), comparisons, `&&`, `||`, `!`; `if`/`else` (as statements and expressions); `for i in a..b` and `a..=b`, `break`, `continue`; `return`; `print` of `int`, `long`, `bool`; calls between functions in one package. Everything else is a clear error naming the construct ("not supported by the self-hosted compiler yet"), never wrong code.

## Checker

Name resolution, types, the subset's type rules and error messages. Where a program is wrong, the first error (by Rust nlc's phase, function and traversal order, as docs/reviews/sol-H1-r1.md describes) and its message and position must match Rust nlc's. Design for growth: the research report's S2 section (docs/research/selfhost-architecture.md) and DESIGN.md "The theory being tested": flat tables, ids not pointers, explicit work stacks or counted recursion, caller-owned scratch.

## Code generator

Emit LLVM IR text using the same runtime functions, calling conventions and failure paths as Rust nlc for these constructs. The subset needs no data-stack regions; when later E-tasks add them, the self-hosted code generator emits offset addressing only (DESIGN.md "The job's data stack"), never a pointer mode, so the self-hosted compiler is built for the final design from the start. Exact IR equality with Rust nlc is not required; behaviour is.

## Acceptance

- **Behavioural equality:** a harness (scripts/compare-selfhost.sh --build, run by cargo test) builds every package under tests/run and tests/test with both compilers. For each package the self-hosted compiler accepts, the executables' stdout, stderr and exit status must match exactly (and for tests, each test's result). For each package it rejects, it must reject with the "not supported yet" error, or with the same first error Rust reports when the program is invalid within the subset. Report the counts: built and matching, rejected as unsupported, mismatches (must be zero).
- Directed fixtures for every subset feature, each overflow and division failure, and invalid programs within the subset.
- Time and memory for building the benchmark-sized generated program of subset features, both compilers.
- Report: docs/tasks/E1-report.md, including what was awkward to write in next-lang and the plan for E2.
