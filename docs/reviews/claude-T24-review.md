# Claude: T24 review (small items before S1)

**Verdict:** approved after one fix round.

Checked: cargo build and test pass (new compiler/tests/stdout_pipe.rs covers every subcommand with a closed pipe). Probes ~/nlprobe/x1-x5: `env.exit(2)`/`env.exit(3)` give those statuses; `[...]` literals for arrays, lists, nested arrays with a trailing comma; `b"a\xffb"` written and read back gives byte 255; `"a\xff"` as Text refused with a clear message; matching `ok(x)` on an `Option<int>` now says "value has type Option<int>; use some(_) or none"; `nlc inspect stacks ... | head` exits 0. Luna's 10,000-element `const int[10000]` builds in 0.4 s.

Fix round 1:

1. `never` didn't fit other types (`env.exit(2)` as the tail of a `Result`-returning `main` was a type error); now it does, in tails, `if`/`match` branches and after `?`.
2. A `const` array of `Ascii` (the keyword table S1 needs) panicked the emitter; constant and global arrays and lists of Ascii, Text and Bytes are now static data (deduplicated bytes plus descriptors).
3. `for k in KW { ... }` with a capitalised const parsed `KW { ... }` as a struct literal; all control-flow heads now read a capitalised name before `{` as the name (parenthesise for a struct literal), documented in syntax-tree-format.md.
4. `Ascii max 8[3]` read `8[3]` as the maximum; `(Ascii max 8)[3]` now works and the error suggests it.

Noted, not required: `match` has no string-literal patterns (`match k { "let" => ... }`); S1 can use `==` chains, but string patterns would shorten keyword handling. Logged in PLAN as an optional convenience.
