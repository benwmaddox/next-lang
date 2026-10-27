# LangArena ports

Ports of the 50 [LangArena](https://github.com/kostya/LangArena) tests (MIT; see LICENSE-LangArena), the self-hosted compiler's acceptance target (docs/PLAN.md). `run.js` and `test.js` are LangArena's parameter files, vendored unchanged; each entry's `checksum` is the expected output.

Conventions, one directory per test, named after the test in lowercase with `::` as `_` (`Binarytrees::Obj` -> `binarytrees_obj/`):

- `name`: the LangArena test name, one line.
- `main.nl` and `package.toml` (`capabilities = ["env", "out"]`): the program. Its first argument is the mode, `test` (small parameters from test.js) or `run` (full parameters from run.js); `env.args().get(0L)` is that argument (see `_skeleton/`). Parameters for both modes are written into the program as constants. It prints the checksum as one decimal line, last.
- `status` (optional): `pending-floats` (needs floats, step F1), `pending-threads`, `pending-regex`, or `pending-<reason>` while it can't be checked yet; absent means ready.
- The algorithm follows LangArena's reference implementations (rust/src/benchmarks/*.rs is a good source) closely enough that the checksum matches, written idiomatically for next-lang: bounded collections with capacities large enough for the run parameters, `write` parameters, pools and typed ids instead of pointers, no mutable globals, no name shadowing.

Check: `python3 bench/langarena/check.py --mode test` (and `--mode run --time`) builds every package with stage-0 nlc at NLC_OPT_LEVEL=3 and compares the output with the checksum.
