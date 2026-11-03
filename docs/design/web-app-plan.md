# Web app target (plan, 2026-10-30)

Goal (Ben): a web app where a request comes in, an optional cache is consulted, data is pulled from a database,
adjusted a little, formatted through a template, and returned as HTML or JSON. SQLite first; external libraries
are fine for the database and for HTTP.

## Pieces and where they come from

| Piece | Source |
| --- | --- |
| Worker threads, service jobs, mailboxes, reply slots | core (docs/design/mailboxes.md); `env.host()` is done |
| Sockets, accept/read/write, waiting without blocking a worker | `Net` capability: thin layer over `epoll` (Linux) and IOCP (Windows) in the C runtime |
| HTTP request parsing | picohttpparser (single file, MIT) behind the `Http` capability; response writing in next-lang |
| Database | SQLite amalgamation (public domain) as its own translation unit behind a `Db` capability; typed queries, one wait per `db.read { }` |
| Cache | an ordinary service job owning a bounded map; reached through its tagged mailbox with reply slots |
| Templates and JSON | next-lang library appending into a bounded output buffer |

## Order, each step ending in something that runs

1. Mailboxes and a worker pool: `mailbox<T, N>` with many senders, `spawn service`, single worker first, then several.
   Demo: a cache job answering several request jobs; checksum equal to a single-threaded run.
2. `Net` and a blocking echo server on one worker. Demo: `curl` receives bytes.
3. HTTP parse and respond on one worker, with routes such as `GET /thing/:id`. Demo: a JSON answer.
4. Suspend-on-I/O and the worker pool: many connections served by few threads.
5. SQLite: typed queries, a writer job and read jobs. Demo: a request returns rows.
6. The whole pipeline: request, optional cache, database, adjust, template, HTML or JSON.
7. Limits: reply-slot pool size as the busy limit (503), deadlines on waiting jobs, closed mailbox ends on failure.

Each of steps 4 and 6 gets a benchmark against a small Rust server doing the same work.

## Decisions taken

- SQLite is the first database; HTTP/1.1 only at first, with TLS left to a reverse proxy.
- JSON output is built by formatting into a bounded buffer first; a typed builder can follow.
- Native code is reached through capabilities, not a general `extern fn`.

# Roadmap after the first web target (2026-11-02)

## Goals (Ben, 2026-11-02)

1. **Competitive with Rust on resource use in many cases:** memory (resident and peak), CPU per request, binary size, startup time and
   build time for the same program. The language's bounds and up-front allocation are the means; the test is a side-by-side number.
2. **Easier to reason about than Rust for business logic and application code, especially compared with working around the borrow
   checker:** no lifetimes, no clone-to-satisfy-the-compiler, no `Arc<Mutex<..>>` plumbing for shared state; plain records, copy on
   assignment, bounds that are checked at build time and say what to change.

Both are measured, not claimed. Each program that goes into bench/ or apps/ gets a scoreboard row against its Rust counterpart:
resident and peak memory, CPU per request, binary size, startup, build time, and source lines; and a note of every place the Rust
version needs `clone`, `Arc`, `Mutex`, a lifetime annotation or an index instead of a reference where the next-lang one does not
(and the reverse: where next-lang needs a bound or a copy that Rust does not). Today's numbers: the web benchmark (bench/web) is
level with tokio at 64 to 1000 connections and uses 3.5 to 4 MB resident for the paced runs against Rust's 3.5 to 4 MB; Campfire's room
page uses 7 MB resident (13.7 MB peak). Not yet compared: binary size, startup and build time, and the readability side
(Campfire against the Rust port in the AgentLang benchmark, line for line).

Where it stands: the plan above is built and measured (docs/campfire-friction.md rounds 1 to 7, bench/web/README.md). The Campfire clone
runs sign-in, rooms and messages on SQLite at about 50k pages/s in 7 MB; the web benchmark is level with tokio at 64 to 1000
connections. A review of practical use (Ben asked, 2026-11-02) found what is missing for CLIs and for ordinary web apps. In order of
what unblocks the most:

## 1. CLI basics (Env capabilities)

- **Standard input (done 2026-11-02):** `env.stdin_read(out)` reads the next chunk into a `Bytes` (replacing its contents) and returns the
  length; 0 is the end of the input, -1 an error. Line-at-a-time reading is library code on top (tests/py/programs/cli_grep does it).
- **Environment variables (done 2026-11-02):** `env.getenv(name, out)` into a `Bytes` or `Text` (validated UTF-8 as for header reads);
  returns the length, or -1 when the variable is not set or does not fit. Declaring the variables a program reads in `package.toml`
  (so the build knows) is still to do.
- **Flag parsing:** a small library over `env.args()`: `--name value`, `--name=value`, `-f`, positional arguments, `--help` text built
  from the declarations, usage errors with exit code 2.
- **Run another program:** `env.run(program, args, stdin, stdout_buffer)` with a bounded output and an exit code; declared capability.
- **Exit codes and error output conventions** documented; a CLI example (a `grep`-like or `wc`-like tool) in the tests.
- Files outside the current directory (today's rule confines `Fs` paths beneath it): a declared `fs` root list in `package.toml`.

## 2. Outgoing connections

- **`net_connect` and a client:** TCP connect (with a deadline), then an HTTP/1.1 client (`env.http_get/post` into bounded buffers) that
  suspends the job on I/O like the server side does; DNS by the system resolver in a worker.
- **TLS:** outgoing first (HTTPS requests), then incoming; through the system library, behind a capability (no TLS written here).
- Use: webhooks, calling another service, fetching a feed. Test against a local server written in next-lang.

## 3. Web application library

- **JSON:** parse into a declared struct (bounded, with the first error's position) and print from one; today only templates print JSON.
- **Forms and query strings:** percent-decoding and `a=b&c=d` into a struct (Campfire has a hand-written one).
- **Sessions, CSRF tokens, rate limiting (per address, in a fixed table), request logging, a background-job pattern** (a service with `tick`):
  as library code and examples, built on what exists (`random_token`, `password_verify`, `db_exec`, services).
- **More databases:** PostgreSQL through a capability (typed queries checked at build time against a schema file as for SQLite).
- **Templates for `Text`:** the generator knows `Bytes` and `Ascii` only; teach it `Text` so names and bodies read through `Text` fields
  (validated UTF-8, code points counted) are used without conversion.
- **Static files** from a directory (with a bounded cache) and compression for responses.

## 4. Performance

- **16 connections:** next-lang is 18-24% behind tokio (219k against 271k on 4 cores) because its median is about 10 us slower, even at
  50 req/s. First measure busy cores and CPU per request at 16 and 64 connections for the shared pool and for socket-owning workers, then
  the options recorded in the review: choose the worker at wake time, keep the cache service's data on one core (or a cache per worker),
  and soft affinity.
- **Stack estimation: step 1 done (2026-11-02), see below.** The build now computes a data-stack bound per entry point from each
  function's block sizes and the call graph (selfhost/stack_estimates.nl) and the runtime reserves that; `NLC_REPORT_STACKS=1` prints
  what each job used and reserved; tests/py/test_stack_estimates.py checks reserved >= used and well below the old default. Native-stack sizing done (128 KiB + 4 KiB per call level, 16 KiB steps). Left: the typical-run estimate to start commit from, exact (not summed) frame sizes, recursion bounded by the
  recursion budget, and the other items below.
- **Fix the stack estimation process, then size every job from it (Ben, 2026-11-02).** Before step 1 the sizes were constants: a job reserved
  64 MiB of address space for its data stack (`NLC_JOB_STACK_RESERVE_BYTES`) and 1 MiB for its native stack (coroutines; 64 MiB for plain
  threads), whatever the job does. The design has an estimate per entry point (DESIGN.md "The job's data stack": a worst case from the
  build, and a typical-run estimate with loops counted as 5 rounds), but nothing the build computes reaches the runtime: the
  self-hosted compiler's output carries only `; nlc.stack offset`. (I have not checked what the stage 0 compiler still does.) Work:
  1. **Compute per entry point** (every `main`, spawned function and service handler) a data-stack worst case, a typical-run estimate and a
     native-stack bound (frame sizes up the call graph; recursion and indirect calls marked unbounded), and check them in `inspect stacks`.
  2. **Emit them** as a table the runtime reads at spawn: reserve the worst case (rounded up, with the configured headroom), commit nothing
     beyond what is used, start from the typical estimate; reserve the native stack from its bound plus a margin; an unbounded entry keeps
     today's default or the configured cap.
  3. **Validate the estimates against what jobs touch:** record each job's high-water marks (data stack and native stack) at exit under an
     environment switch, and a test that fails when an estimate is below a measured value (too low is a crash waiting to happen) or more
     than 4x above it on the benchmark programs (too high wastes address space).
  4. **Shrink what the runtime itself puts on the stack:** several HTTP and capability functions hold 4 KB scratch arrays
     (`unsigned char scratch[4096]` for text arguments), so every connection touches two pages of native stack for nothing; read arguments in
     place or size the scratch from the argument.
  Targets, measured on the web benchmark and Campfire: at 1000 connections at most 13 MB resident (tokio: 13.0; now 17.8, 15.5 KB per
  connection against 9.3) and at most 2 GB of virtual address space (Rust: 0.28; now 100); idle and 64-connection numbers must not rise. See
  bench/web/README.md "Memory against Rust".
- **Request path cost:** where the 10 us goes (coroutine switch, the HTTP layer, user CPU 5 us against Rust's 2.7).
- Keep: 4-connection result (ahead of the thread-per-connection server), low CPU at slow rates (checked at 50 / 500 / 5000 req/s).

## 5. Platform

- **Windows:** sockets (IOCP), coroutines/fibers and the driver features that are Linux-only today (templates, services run through the
  Linux driver); then a macOS port of the same capability layer.
- **Hosting:** a container recipe and a systemd example; graceful shutdown on SIGTERM (stop accepting, finish in-flight requests).

## 6. Compiler and tooling quality

- **Open compiler bugs (docs/campfire-friction.md 24 (the push form is fixed), 25):** `for x in list` with the element's field passed on gives a stale value;
  pushing a loop element into another list of the same type generates IR that clang rejects; a `Bytes` inside a struct reached through a
  `write` parameter cannot grow (`grow` is for builders only).
- **Tests take 10 to 15 minutes before a commit:** split into a fast set that runs on every commit and the full set on the server.
- **Remove the Python generator references** (`tools/tmpl.py`, `tools/svc.py`) once their comparison corpus is turned into golden files.
- **A formatter and an editor protocol (language server),** so the build-time errors show where the code is written.
- **Package manager:** dependencies by path or git, version pinning, a lock file; today a program is one directory.

## Order

1 (CLI basics) and 2 (outgoing connections) first: each opens a whole kind of program. Then 3 (JSON, forms, library), then 4 and 5 in
parallel with them as measurements and ports allow; 6 as it hurts.

## Developer and agent experience

Done 2026-11-02 (AGENTS.md, docs/LANGUAGE.md, docs/campfire-friction.md round 8): agent entry point, a tested language tour, `nlc check`, caret diagnostics and `--json`, `nlc test --filter`, `scripts/test-related.sh`, whitespace `nlc fmt`. Still open, in the order that hurts: report more than one error per run, name structs in mismatch errors, a layout-aware formatter, an LSP (diagnostics first, built on `check --json`), shortening the full suite.
