# next-lang (working name)

next-lang is an experiment in a compiled language for servers, games and tools that tries to be correct, easy to read and fast without a garbage collector or a borrow checker. The trick is that every value has a known maximum size (lists have capacities, text has a max length, numbers can have ranges), and a function can only change what it's explicitly given. That turns a lot of bugs into build errors, and it lets memory live on per-job stacks where allocating is a bump and freeing a whole request's worth of data is one reset. It's meant to be memory safe without pointers: values are stored inline, elements of a collection are referred to by typed ids (an index plus a generation), and positions on a stack by offsets, so there are no dangling references or use-after-free. Threads share nothing mutable, so no data races either: they talk through mailboxes, snapshots of shared state, frozen read-only data and parallel loops.

```
fn describe(u: Unit) -> Ascii max 64 {
    $"{u.name}: {u.hp} hp"      // max length worked out at build time, built in place
}
```

Right now it's early. The full design is written up in [docs/DESIGN.md](docs/DESIGN.md) (short version: [docs/OVERVIEW.md](docs/OVERVIEW.md)). A first compiler written in Rust builds most of the language and is frozen as the reference. The main work is a self-hosted compiler written in next-lang itself, with a standard library that needs no C library. It handles structs, enums, `match`, `Option`/`Result` and a growing data stack today, is adding lists now, and the goal is for it to compile itself. Plan and progress: [docs/PLAN.md](docs/PLAN.md).

Compared with the same programs written in Rust (both fully optimised): next-lang already wins on allocation-heavy work, about 2.6x faster at text formatting and 1.5x on nested lists than idiomatic Rust, and level with Rust that's hand-tuned to reuse buffers. Memory use is equal or lower, and binaries are a third the size. It loses on tight arithmetic loops, 1.1x to 5x slower (10x on binary search), mostly because overflow and bounds checks are always on and stop vectorisation; removing the ones the compiler can prove unnecessary is next. [Benchmark details](docs/bench/2026-10-26-rough-baseline.md).

To try it (Linux or WSL, Rust and clang 18): `cargo build --release`, then `./target/release/nlc run <package-dir>`, where a package is a directory of `.nl` files.

Licensed under Apache 2.0 (Maddox Labs LLC); see [LICENSE](LICENSE).
