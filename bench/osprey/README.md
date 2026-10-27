# Osprey benchmark ports

Ports of the 24 cases of the [Osprey language benchmark suite](https://www.ospreylang.dev/benchmarks/) (https://github.com/MelbourneDeveloper/osprey, MIT, Copyright (c) Christian Findlay). Each case there is a small program (Rust, C, C#, OCaml and others) that must print exactly the contents of `expected.txt`; `bench.json` and `expected.txt` here are copied unchanged from the Osprey repository, and the algorithms follow its Rust references (`benchmarks/cases/<case>/<case>.rs`) with the same sizes and operations. Osprey's harness is `benchmarks/run.sh`.

MIT License notice: Osprey's license permits use, copy, modification and distribution provided the copyright and permission notice are included; the notice is Copyright (c) Christian Findlay, and the full text is in the Osprey repository's LICENSE.

Cases: ackermann binarytrees coins collatz coprime digitsum exprtree factorial fib gcdsum hanoi isqrt josephus listops mergesort mutual nestedloop pascal powmod primes quicksort tak textstats wordfreq.

## Conventions

One directory per case:

- `main.nl` and `package.toml`: the program. Plain cases use `capabilities = ["out"]`; seeded cases use `["env", "out"]`.
- `expected.txt` and `bench.json`: copied from Osprey.
- `status` (optional): `pending-<reason>` while the case can't be expressed in the stage-0 compiler yet; absent means ready. (None are pending at the moment.)
- All numbers are `long` (the references use `i64`), values stay in range as in the references, and integer overflow fails at run time, so the checked arithmetic is part of the measurement. Osprey itself checks every integer operation, but the Rust baseline here is built with `-C overflow-checks=off`, the setting Osprey's own table uses.
- Recursive functions are marked `recursive` where the reference recurses. Where the reference uses a `while` loop, the port uses a counted `for`.
- Boxed trees (binarytrees, exprtree) use a `pool` with typed ids, one fresh pool per tree; leaves are allocated like the reference's boxed leaves. Stage 0 has no generic enums, so a node is a struct (`Option` children, or an `op` enum plus `value`).
- Persistent-list cases (mergesort, quicksort) allocate fresh sequences at every split, partition and join like the references do. Stage 0 refuses a large local list held across a recursive call, so the sequences are segments `(start, length)` of one bump-allocated `list<long, N>` passed as `write`.

## Difference: the seed comes from the first argument, not stdin

Six cases (exprtree listops mergesort quicksort textstats wordfreq) read a seed from stdin in Osprey (the harness pipes `0`, meaning seed 1, so compilers can't fold the work). next-lang has no stdin yet, so these ports read the first command-line argument with the same meaning: `0` is seed 1. Any other decimal argument `m` selects seed `m mod 2147483646 + 1` (the references draw a random seed there instead). `check.py` passes `0`.

Other stage-0 differences: `Ascii` has no `contains` or `starts_with`, so textstats scans bytes, and `Arg` has no integer parser, so the seed is parsed digit by digit.

## Run

    python3 bench/osprey/check.py                # build every case, compare stdout with expected.txt exactly
    python3 bench/osprey/check.py --time         # also best-of-5 wall time and peak RSS, next-lang vs Rust
    python3 bench/osprey/check.py fib tak        # selected cases

Needs the stage-0 compiler at `~/.cache/next-lang/target/release/nlc` (override with `NLC`; built with `NLC_OPT_LEVEL=3`) and, for `--time`, an Osprey checkout at `/mnt/d/tmp/osprey` (override with `OSPREY`), `rustc`, `taskset` and `/usr/bin/time`. Timing runs each program 5 times, pinned with `taskset -c 8`, interleaving next-lang and Rust, under `flock -x /home/ben/linuxbench/bench.lock`. The Rust reference is Osprey's `<case>.rs` built with `rustc -C opt-level=3 -C overflow-checks=off` and given `0` on stdin. `--no-rust` skips the Rust column.
