# The core library: runtime and standard library without a C library

Design note for E1c (docs/PLAN.md, Order of work item 5). 2026-10-25, before any implementation.

This revision incorporates the peer review docs/reviews/sol-core-library-r1.md.

Citations of current behaviour are to commit 6a74a81. `runtime/nl_runtime.c` and `compiler/src/emit.rs` are unchanged in the working tree, so their line numbers hold there too. `compiler/src/driver.rs` has uncommitted edits, so its line numbers are from `git show 6a74a81:compiler/src/driver.rs`. `nlc link-ir` and `nlc test-ir` don't exist yet: they are described as the E1 spec defines them (docs/tasks/E1-selfhost-end-to-end-slice.md:29-66).

## Terms

- **libc:** the C standard library (glibc on our Linux hosts). It provides `printf`, `malloc` and `write`, and also the program's start-up code.
- **System call (syscall):** a direct request to the kernel. On x86-64 Linux it's the `syscall` instruction, with the call number in register `rax` and up to six arguments in other registers.
- **errno:** the kernel's error number (for example `ENOENT`, 2, "no such file"). A raw Linux system call returns it negated: a result from -4095 to -1 means failure with errno = -result.
- **Freestanding:** built without libc or the C start-up files. The program supplies its own entry point and every function it calls.
- **`_start`:** the symbol where the kernel starts a program. In a normal C program it belongs to libc's start-up code, which then calls `main`.
- **Initial stack:** what the kernel puts on the stack before `_start` runs: the argument count (`argc`), the argument pointers (`argv`), the environment pointers (`envp`) and the auxiliary vector (`auxv`, key-value pairs such as the page size).
- **Inline assembly (inline asm):** machine instructions written inside LLVM IR. A **constraint string** says which registers hold the inputs and outputs. **Clobbers** list what the instructions destroy, so LLVM saves anything it still needs.
- **Intrinsic:** an operation the compiler implements itself rather than a library function. In this note, `sys.write` and the others are intrinsics of the next-lang compiler. `llvm.memcpy` is an intrinsic of LLVM.
- **Libcall:** a call LLVM emits on its own to a library function, such as `memcpy` for a large copy, even when the source never called it.
- **Hook:** a core-library function that compiler-generated code calls by a fixed symbol name, such as `nl_print_int`.
- **Mapping:** a range of address space obtained from the kernel with `mmap`.
- **Pinned:** a data stack that may not move (grow by `mremap`) for a while, because something holds a raw address into it.
- **Linkage:** whether a symbol is visible outside its object file. An `internal` (local) symbol is seen only inside its own object; the linker never matches it with another file's symbol of the same name, and it isn't exported from the program.
- **Helper closure:** a function plus every function it can reach through calls, directly or indirectly.
- **BSS:** the part of an executable holding zero-initialised data. The kernel supplies it as zero pages, so it costs nothing until it's touched.

## Summary of decisions

1. **The core library is next-lang source, compiled by the self-hosted compiler into every program's module, in a "core dialect":** E1's subset, widened by two ordinary features that every package gets (int and long casts, `-> never`), plus a closed list of core-only forms: the `sys` type and operations, which are permanent, and the state block, a bootstrap form. The state block and two coding conventions have a retirement schedule. The self-hosted compiler accepts the core-only forms only while compiling the embedded core library.
2. **E1c keeps E1's runtime interface as the hook ABI, for as long as the third comparison leg needs it.** The core library defines `nl_print_int`, `nl_fail`, `nl_context_create` and the other functions E1's IR already calls, with the same names and C-level signatures. The program part of the IR is the same in both link modes except for three things listed in "The program IR in core mode". So a mismatch can be pinned on the compiler or on the core library by linking the same program IR against either runtime. Context-passing hooks replace this ABI before the first region-using core function (E3); "Retiring the hook ABI" says what replaces the third leg then.
3. **The `sys` operations are a fixed set of named intrinsics.** Each lowers to inline asm `syscall` through one small helper per argument count. They return the raw kernel result as a `long`. Only the embedded core library can name them.
4. **The entry is a compiler-emitted `_start` in module-level assembly.** It calls the core library's `nl_core_start`, which reads `argc`, `argv`, `envp` and `auxv` from the initial stack, calls the program's `main(argc, argv, envp)` and ends with `exit_group`. A program that links a C library gets libc's start-up instead; libc calls the same `main`, and the core library finds `auxv` by its own path.
5. **E1c maps the data stack as the C runtime does, but doesn't map or switch to its own native stack.** E1 has no recursion and no jobs. The native-stack design is below, for the task that admits `recursive`, and is deferred beyond E1c.
6. **The core library never calls libc, in either start-up variant.** It defines its own `memcpy`, `memmove`, `memset`, `memcmp` and `bcmp` as internal symbols in every build, so LLVM's libcalls bind to them inside the program's object file and nothing is exported. Their whole helper closure is marked `"no-builtins"` and contains no memory intrinsics. A post-link call-graph test enforces it.
7. **The core library's source is embedded in the self-hosted compiler** (a generated, checked-in source file), not read from disk at build time.
8. **Freestanding links use `clang -O{1,3} -nostdlib -static -Wl,-e,_start`.** `link-ir` picks this from a new header line, `; nlc.runtime core`, in header version 2.
9. **File I/O, the atomic write and the streaming file writer** follow when a later E-task needs files. Their design is in "File I/O in the core library". Each existing `Fs` operation keeps its current behaviour.
10. **UTF-8 is validated only at boundaries** (DESIGN.md:876). The core library keeps validating routines and trusting helpers apart, and test builds re-validate every `Text` they construct.

## What the C runtime does today

| Area | Where (nl_runtime.c) | Used by E1's IR | In E1c |
| --- | --- | --- | --- |
| Data stack: header page, 256 KiB movable mapping, guard page | nl_runtime.c:183-247 | yes (`nl_context_create`, `nl_context_base_offset` at 294-298) | yes |
| Data stack growth with `mremap`, `NLC_STACK_VERIFY` poisoning | 339-415, 418-438 | no (E1 allocates no regions, E1 spec:225) | no; lands with the first region user (E3) |
| Native stack bounds through `pthread_getattr_np`, recursion budget | 145-181, 249-271 | no (no recursion in E1) | no |
| Startup memory claim for shared state (overcommit, cgroup, touch pages) | 625-898 | no (no user globals) | no |
| File registry (grows with `realloc`) | 529-543, 900-903 | yes | yes, fixed table |
| Test selection from `NLC_TEST_INDEX`, test mode | 545-557 | yes | yes |
| `nl_fail`: flush, message, exit 1 or 70 | 905-936 | yes | yes |
| Expectation reports on stdout | 938-966 | yes | yes |
| Buffered stdout and stderr, terminal line buffering, shared-terminal ordering | 31-36, 1692-1815 | yes | yes |
| Decimal formatting | 995-1055 | yes (through `print`) | yes |
| Printing `int`, `long`, `bool` | 1373-1392 | yes | yes |
| Capability environment: SIGPIPE ignored, argument limits, file-system root | 1503-1548 | yes (`nl_env_create`, `nl_env_destroy`) | yes, except the test-build temporary root |
| Rooted file reads, writes, listings, joins (`openat2`, `getdents64`) | 1581-2295 | no (`Fs` is outside E1) | no; see "File I/O in the core library" |
| `Out` capability writes | 2297-2335 | no | no |
| UTF-8, Unicode upper-case table, integer parsing, padding | 1125-1362 | no | no; E3 |
| Test hooks: `NLC_TEST_DATA_STACK_BYTES`, `NLC_TEST_REPORT_STACK_RESIDENT`, `NLC_TEST_MEMORY_POLICY`, variable-lane snapshots | 106-128, 459-483, 559-617, 774-809 | no in E1's environment | no (see "Environment variables") |

The program side is the `define i32 @main(i32 %argc, ptr %argv)` that Rust emits (emit.rs:726-901): select the test, create the context, create the environment, register the files, run `main` or the selected test, destroy the environment and the context, return the status. The E1 spec makes the self-hosted compiler emit the same shape (E1 spec:228-244). The runtime declarations are emit.rs:168-248. Every runtime failure goes through `guard`, which branches to `call void @nl_fail(kind, file, line, col)` and `unreachable` (emit.rs:21959-21970).

Rust nlc builds with `clang -O{1|3} [-fstack-size-section] [-DNLC_TEST_BUILD=1] [-DNLC_STACK_MODE_OFFSET=1] module.ll runtime/nl_runtime.c -o program` (driver.rs:1449-1484 at 6a74a81), with `NLC_OPT_LEVEL` read at driver.rs:1378-1386. The test runner starts one child per test with `NLC_TEST_INDEX` and reports status 70 specially (driver.rs:813-890, the child at 869-870, the 70 line at 880).

## How the core library gets compiled (the bootstrapping decision)

At E1c the self-hosted compiler accepts only E1's subset: `int`, `long`, `bool` and `()`, functions, `let`/`var`, range loops, `if`, checked arithmetic, `print` and tests (E1 spec:74-148). There are no globals, structs, byte buffers, string literals or casts. The core library needs two 64 KiB output buffers, message text, reads of the initial stack and system calls. Three ways were considered:

- **(a) A core dialect (chosen).** The core library is written in E1's subset plus a closed list of additions. Ordinary features are added for every package; core-only forms are accepted only while the compiler checks the embedded core library. Each core-only form either stays privileged for good (`sys`) or is a bootstrap mechanism retired by a named task.
- **(b) The compiler emits the core library's IR from templates.** It's quick to start, but it puts the runtime in Rust-like string tables inside the compiler. That's C by another name, against "every runtime and standard-library need ... written in next-lang" (PLAN.md:31). It stays the fallback for the few things that must be machine code (`_start`, the syscall helpers, `rep movsb`).
- **(c) Rust nlc compiles the core library.** That needs `sys` support in Rust nlc, which is meant to keep the C runtime and freeze (PLAN.md:29, DESIGN.md:162). Rejected.

**The core dialect for E1c** is exactly E1's subset plus the forms below. Anything not listed is rejected in the core library as it is in a user package.

*Ordinary features, added for every package and compared against Rust nlc as usual:*

1. **Casts between `int` and `long`:** `(long)x` and `(int)x`. The narrowing cast is checked as Rust nlc checks it (`bad cast`, kind 10). Rust nlc already has both (tests/run/arithmetic uses `(int)12L`).
2. **`-> never`** as a result type, with the rules Rust nlc already applies (T26). The core library uses it for `nl_fail` and the entry; at the bottom, the only `never` operation is `sys.exit_group`.

*Core-only forms, accepted only in the embedded core unit:*

3. **The `sys` namespace:** the type `sys.Addr` and the operations in "The `sys` operations", with exactly the signatures given there. These are privileged for good.
4. **`sys.lit(b"...")`:** a byte-string literal, allowed only as this intrinsic's argument. It returns the `sys.Addr` of a private, NUL-terminated constant. It's part of the permanent `sys` set.
5. **The state block** (bootstrap): `sys.state()` and the manifest key `state_bytes` (below).

*Conventions, written in E1's subset with no checker change, and retired like the bootstrap form:*

- **Constants as functions:** `fn output_capacity() -> long { 65536L }`. E1 has no `const`, so a constant is a function with no parameters whose body is one literal; LLVM folds the call at -O1. Offsets inside the state block are written the same way.
- **Raw error results:** each system call's `long` result is tested with `sys.is_error(r)` at the call site, because the self-hosted compiler has no `Result` yet (see "Errors").

*Rules that hold for every core function:*

- **No hidden parameters.** Core-library functions take no `%nl.ctx` and no `%nl.top`, because in E1c they use no data-stack regions (their scratch is in the core state block, below). Every core function gets `nounwind`.
- **Checked arithmetic is E1's.** `+`, `-`, `*`, `/` and `%` on `int` and `long` are checked as in user code. A failure calls `nl_fail` with the usual kind and the core file's location, which is a core-library bug and is reported as one (`core/output.nl:12:5: integer overflow`). The one exception is the memory-function closure, where a failed check lowers to `llvm.trap` instead, so the closure makes no calls out (see "The memory functions").
- **`"no-builtins"`** goes on the memory-function closure only. LLVM's inliner refuses to inline a function whose `"no-builtins"` setting differs from its caller's: a two-function `.ll` experiment on clang 18.1.3 kept the call at -O1 and -O3. The hooks (`print`, later the stack-growth path) are meant to inline into user code, so they don't get the attribute. `alwaysinline` overrides that refusal, so it's never used across the closure's boundary (see "The memory functions").

**Spelling.** `sys.write(fd, data, count)` already parses as a method call on the name `sys`, and `sys.Addr` as a qualified type name in a type position. So neither front end changes, and the byte-for-byte parse comparison between the Rust and self-hosted parsers is unaffected. Only the self-hosted checker gives these forms meaning, and only inside the core library.

**State.** The core library's process state (the output buffers and their lengths, flags, the file table, the page size, the `envp` and `auxv` addresses) lives in one zero-initialised block that the compiler emits as `@nl.core.state = internal global [N x i8] zeroinitializer, align 64`, in BSS. `sys.state()` returns its address. Its size N is set in the core library's manifest (`state_bytes = 147456`). The manifest key is accepted only for the embedded core unit; in a user package it stays an unknown key. Offsets inside the block are functions too (`fn state_lengths() -> long { 0L }`). It is mutable, so it can't become a `const`, and the language has no mutable globals; it is retired into the job context instead (below). This is the bottom layer, and it's written plainly.

**Retiring the bootstrap mechanisms.** Each one stays until the language feature that replaces it reaches the self-hosted compiler, and is retired in that task, with the harness comparing before and after:

| Mechanism or convention | Replaced by | Owning task |
| --- | --- | --- |
| Raw `long` results and `sys.is_error` at call sites | one `Result<long, Errno>` wrapper per operation; raw forms only inside the wrappers | E2 (`Result`, `?`) |
| Offsets into the state block as functions | a struct describing the state block's layout | E2 (structs) |
| NUL-terminated `ptr` strings in the hooks | context-passing hooks and compiler-emitted static tables | E3, before the first region-using core function; see "Retiring the hook ABI" |
| Constants as functions | `const` and constant arrays (T05) | proposed: E3, because E3's `Text` needs the Unicode upper-case table as constant data |
| `sys.state()` and `state_bytes` | a state struct reached through the job context record that `_start` creates and the context-passing hooks carry (no by-name access, as user code has none) | E3, with the context-passing hook ABI (E3a1), laid out as a struct once E3 rewrites the output buffers as `Bytes` and the file registry as a static table; which parts stay per process once the scheduler runs many jobs is the scheduler milestone's question |

PLAN's E list names structs, `Result` and `?` for E2 and `Text`, `Bytes` and builders for E3; E3 also adds `const` (but not user globals, which are removed from the language). Until a row's owning task lands, the mechanism stays.

**Rewriting upwards.** As E2 to E4 land, the core library moves to the richer language: `Result` for errors, structs for the context and state layout, `Bytes` for buffers. Each step is compared by the same harness, so a rewrite can't change behaviour unnoticed.

## The `sys` operations

### Memory without raw pointers in user-visible types

User code has no pointers and never will. The core library needs addresses at its bottom layer: the initial stack, mappings, static constants and syscall arguments. The rules:

- **`sys.Addr`** is a 64-bit, privileged, opaque address type, lowered to LLVM `ptr`. It has no arithmetic operators and no conversion to or from `long` except through the operations below. It can't appear outside the core library (see "Only the core library may use them").
- **Inside the core library, most code uses offsets.** A buffer is "the state block plus `state_buffer(stream)`", and a position in it is a `long` offset. Addresses come from `sys.offset(base, n)` only at the point of a load, a store or a system call.
- **Addresses stored in memory** (the `argv` and `envp` arrays, the `auxv` address kept in the state block) are read and written with `sys.load_addr` and `sys.store_addr`, never through a `long`. So no code forms an address from a number, except `sys.from_raw` on an `mmap` result.
- **Data-stack memory** (from E3, when the core library handles `Bytes` and `Text`) is reached only through `sys.stack_addr`, `sys.stack_load8` and `sys.stack_store8`. The rules, including when the address is formed, are in "The stack is pinned while the kernel holds an address into it".

Memory operations (core dialect only; this is the whole set for E1c):

```
sys.null() -> sys.Addr                                      // a null argument to a system call
sys.is_null(a: sys.Addr) -> bool                            // the end of argv and envp
sys.offset(base: sys.Addr, bytes: long) -> sys.Addr        // getelementptr i8, no inbounds
sys.distance(from: sys.Addr, to: sys.Addr) -> long          // to - from; both in one object
sys.from_raw(value: long) -> sys.Addr                       // inttoptr; only for mmap results
sys.load8(base: sys.Addr, offset: long) -> int              // zero-extended byte
sys.load32(base: sys.Addr, offset: long) -> int
sys.load64(base: sys.Addr, offset: long) -> long
sys.load_addr(base: sys.Addr, offset: long) -> sys.Addr     // a stored address (load ptr)
sys.store8(base: sys.Addr, offset: long, value: int)        // keeps the low 8 bits
sys.store32(base: sys.Addr, offset: long, value: int)
sys.store64(base: sys.Addr, offset: long, value: long)
sys.store_addr(base: sys.Addr, offset: long, value: sys.Addr)
sys.lit(b"text") -> sys.Addr                                // private NUL-terminated constant
sys.state() -> sys.Addr                                     // the core state block (bootstrap)
sys.is_error(result: long) -> bool                          // -4095 <= result <= -1
sys.copy_forward_bulk(dst: sys.Addr, src: sys.Addr, n: long)  // x86-64: rep movsb; arm64: ldp/stp loop
sys.fill_bulk(dst: sys.Addr, value: int, n: long)           // x86-64: rep stosb; arm64: stp loop
sys.call_main(argc: int, argv: sys.Addr, envp: sys.Addr) -> int   // calls the program's @main
```

Loads and stores are emitted with `align 1` unless the operation names a wider alignment, and are never `volatile`. `sys.distance` is an integer difference of the two addresses (`ptrtoint`, then subtract). It's used for sizes within one object (the state block, one mapping, the initial stack) and for `memmove`'s overlap test; its result is never turned back into an address. The two bulk operations are inline asm in place, not calls, and are used only by the memory functions. Not in E1c: the data-stack operations (`sys.stack_addr`, `sys.stack_load8`, `sys.stack_store8`), added in E3 with the rules in "The stack is pinned while the kernel holds an address into it", and 128-bit loads and stores (`sys.load128`, `sys.store128`), added by the memory-function speed work if the benchmark shows they're needed.

### The list

Numbers are Linux syscall numbers. arm64 uses the generic table, which lacks some older calls (it has no `open`, `rename` or `renameat`; it uses `openat` and `renameat2`).

| Operation (proposed signature) | Kernel call | x86-64 | arm64 | E1c | Used for |
| --- | --- | --- | --- | --- | --- |
| `sys.write(fd: int, data: sys.Addr, count: long) -> long` | write | 1 | 64 | yes | output, failure messages |
| `sys.exit_group(status: int) -> never` | exit_group | 231 | 94 | yes | the end of every run |
| `sys.map(addr: sys.Addr, length: long, prot: int, flags: int, fd: int, offset: long) -> long` | mmap | 9 | 222 | yes | the data stack |
| `sys.protect(addr: sys.Addr, length: long, prot: int) -> long` | mprotect | 10 | 226 | yes | making stack pages writable |
| `sys.remap(old: sys.Addr, old_length: long, new_length: long, flags: int, new_addr: sys.Addr) -> long` | mremap | 25 | 216 | no | stack growth (E3) |
| `sys.unmap(addr: sys.Addr, length: long) -> long` | munmap | 11 | 215 | no | growth, old guard pages, native stacks |
| `sys.advise(addr: sys.Addr, length: long, advice: int) -> long` | madvise | 28 | 233 | no | trimming, clearing (scheduler) |
| `sys.ioctl(fd: int, request: long, arg: sys.Addr) -> long` | ioctl | 16 | 29 | yes | "is this a terminal" (`TCGETS`, 0x5401 on both) |
| `sys.statx(dir: int, path: sys.Addr, flags: int, mask: int, out: sys.Addr) -> long` | statx | 332 | 291 | yes | same-terminal check; later file size and kind |
| `sys.sigaction(signal: int, action: sys.Addr, old: sys.Addr, set_size: long) -> long` | rt_sigaction | 13 | 134 | yes | ignore SIGPIPE |
| `sys.openat(dir: int, path: sys.Addr, flags: int, mode: int) -> long` | openat | 257 | 56 | yes | open the root `.` |
| `sys.close(fd: int) -> long` | close | 3 | 57 | yes | the root, later files |
| `sys.openat2(dir: int, path: sys.Addr, how: sys.Addr, how_size: long) -> long` | openat2 | 437 | 437 | no | files beneath the root |
| `sys.read(fd: int, data: sys.Addr, count: long) -> long` | read | 0 | 63 | no | file reads |
| `sys.getdents64(fd: int, data: sys.Addr, count: long) -> long` | getdents64 | 217 | 61 | no | listings |
| `sys.fsync(fd: int) -> long` | fsync | 74 | 82 | no | atomic write |
| `sys.renameat2(old_dir: int, old: sys.Addr, new_dir: int, new: sys.Addr, flags: int) -> long` | renameat2 | 316 | 276 | no | atomic write |
| `sys.unlinkat(dir: int, path: sys.Addr, flags: int) -> long` | unlinkat | 263 | 35 | no | removing the atomic write's own temporary file, test roots |
| `sys.mkdirat(dir: int, path: sys.Addr, mode: int) -> long` | mkdirat | 258 | 34 | no | the test-build temporary root |
| `sys.getrandom(out: sys.Addr, count: long, flags: int) -> long` | getrandom | 318 | 278 | no | temporary names (atomic write, test-build root) |
| `sys.clock_gettime(clock: int, out: sys.Addr) -> long` | clock_gettime | 228 | 113 | no | `NLC_STACK_STATS` growth time, the clock capability |

**Not needed:** `getrandom` in E1c. Nothing in E1's behaviour is random: the C runtime's only randomness is `mkdtemp` for the test-build root, which E1c defers (see "Behaviour E1c reproduces"). `rt_sigaction` *is* needed. Without it, writing to a closed pipe kills the process with SIGPIPE, but the C runtime ignores SIGPIPE (nl_runtime.c:1508), gets `EPIPE`, and fails with `<source>:0:0: standard output write failed`, status 1 or 70. Setting `SIG_IGN` needs no `sa_restorer`, because no handler frame is ever built. The kernel `struct sigaction` is handler, flags, restorer, mask (8 bytes each) on both architectures.

**Why `statx` and not `fstat`:** `struct stat` differs between x86-64 and arm64 (`st_mode` is at offset 24 on x86-64 and 16 on arm64), but `struct statx` is the same on every Linux architecture. The same-terminal check compares `stx_dev_major` (offset 136), `stx_dev_minor` (140) and `stx_ino` (32). That is the same test as comparing `st_dev` and `st_ino`. Called as `statx(fd, "", AT_EMPTY_PATH, STATX_INO, buf)`, it reads the descriptor itself. It needs Linux 4.11.

**Kernel baseline:** Linux 5.6 or later, on both architectures, because `openat2` needs 5.6 and every other call in the table is older. E1c's own calls run on older kernels too, but the baseline is what the core library promises. On an older kernel, or under a seccomp profile that refuses a call, the call's error is reported as the same `IoError` the C runtime gives (see "Paths and errors").

### Lowering

The compiler emits one internal helper per argument count, `@nl.sys.call0` to `@nl.sys.call6`, marked `alwaysinline nounwind`. Each `sys.*` operation becomes a call to the helper with its constant number from one table in the compiler (per architecture). Pointer arguments are passed after `ptrtoint`; the `memory` clobber tells LLVM the kernel may read or write any memory. x86-64:

```llvm
define internal i64 @nl.sys.call3(i64 %n, i64 %a, i64 %b, i64 %c) alwaysinline nounwind {
  %r = call i64 asm sideeffect "syscall",
         "={rax},{rax},{rdi},{rsi},{rdx},~{rcx},~{r11},~{memory},~{dirflag},~{fpsr},~{flags}"
         (i64 %n, i64 %a, i64 %b, i64 %c)
  ret i64 %r
}
; call6 adds {r10},{r8},{r9} for the fourth to sixth arguments.
```

The kernel destroys `rcx` (the return address) and `r11` (the saved flags). The other clobbers are the ones clang writes for any x86 inline asm. `exit_group` has no result. It's emitted inline as `call void asm sideeffect "syscall", "{rax},{rdi},~{rcx},~{r11},~{memory}"(i64 231, i64 %status)` followed by `unreachable`.

arm64: `svc #0`, with the number in `x8`, arguments in `x0` to `x5` and the result in `x0`:

```llvm
%r = call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},~{memory}"(i64 64, i64 %fd, i64 %buf, i64 %len)
```

### Errors

Every operation returns the kernel's raw result as a `long`. A result from -4095 to -1 is `-errno`; anything else is success (a count, a descriptor or an address). Every call site uses that exact test, `sys.is_error(r)`, never `r < 0L`. In E1c the test is written at each call site, because the self-hosted compiler has no `Result` yet. From E2 on, the core library wraps each operation once (`fn write(fd: int, data: sys.Addr, count: long) -> Result<long, Errno>`) and the raw forms are used only inside those wrappers. Nothing reads or writes libc's `errno` variable: there isn't one, and in the libc start-up variant the core library leaves libc's alone.

`mmap` returns an address or `-errno`. The core library applies `sys.is_error`, then converts with `sys.from_raw`.

### Only the core library may use them

- **The privilege belongs to the embedded core unit, not to a name or a path.** The compiler checks the core library from the source embedded in its own binary (see "Packaging") with a privileged flag set. A user package called `core`, or a directory called `core/` next to a user package, gets nothing.
- **In any other package,** `sys.<anything>` and `sys.Addr` resolve to nothing. Today that gives each compiler's ordinary error at that point: an E1-unsupported method call in the self-hosted compiler, and an unknown name or type in Rust nlc. Recommendation: once method calls enter the self-hosted subset, both compilers give one specific message where they resolve names, `sys operations are available only to the core library`. That's a small fix in Rust nlc, so `diagnose` cases keep matching byte for byte.
- **Core declarations aren't in the user's scope.** The user package is checked first, on its own, with no core names in scope (see "Build order inside the self-hosted compiler"). So user code can't name a core function, call it, or take it as a function value, and can't name a core type.
- **Privileged types can't leak in by another route.** A type alias, a generic argument or an inferred type can't produce `sys.Addr`: the name doesn't resolve in a user package, and no user-callable operation returns one. As a backstop, after inference the checker asserts that no expression, local, parameter, field or generic instance in the user package has a privileged type; a violation is an internal compiler error.
- **Core symbols are private.** Every core function and the state block are emitted with `internal` linkage, so they're absent from the program's exported symbols and no other object file can call them or collide with them. The exceptions are the symbols an outside party must find: `_start` (the linker's entry) and `main` in the libc variant (libc's start-up calls it). `nl_core_start`, which only `_start`'s module-level assembly references, is kept alive with `@llvm.used`, because the optimiser can't see that reference. User functions are `@nl_fn_<id>`, core functions `@nl_core_<name>`, and hooks keep their hook names (`@nl_print_int`), which no `@nl_fn_<id>` can equal. Core files get file ids after the user's files, so a failure inside the core library reports `core/output.nl:12:5: ...`.
- **Core tests come only from the embedded set.** The command that builds the core library's own `test` blocks (`nlc core-test`, self-hosted only) takes no source path and no package. It compiles the embedded unit and nothing else, so it can't be used to give privilege to other source.
- **Foreign bindings are trusted, not sandboxed.** `sys` restrictions limit next-lang source; they don't constrain what foreign code does (DESIGN.md:842). What the compiler does reserve is the names that could clash inside the program's module: a foreign binding may not name a C symbol that starts with `nl_core_` or `nl_fn_`, a name in the hook table, `_start`, or one of the five memory-function names. Other `nl_` names stay available, so a library such as libnl (`nl_socket_alloc`, `nl_connect`) can still be bound. Such a binding is a build error, so a binding can't bind to, or be confused with, a core symbol.
- **Effects:** the core library is trusted, like foreign code (DESIGN.md:713, 842). Hooks carry the effect of the user-visible operation they implement (`print` is `out`), taken from the built-in signature, not inferred from the core library's body. The audit report lists "core library (trusted, built in)".

## The program IR in core mode

E1c keeps E1's runtime interface. The core library defines these hooks, with the signatures E1's IR declares (emit.rs:168-248):

```
nl_context_create(i64, i64, ptr) -> ptr      nl_context_base_offset(ptr) -> i64
nl_context_destroy(ptr)                      nl_env_create(i32, ptr, i32) -> ptr
nl_env_destroy(ptr)                          nl_register_file(i32, ptr)
nl_test_selected_index() -> i32              nl_set_test_mode()
nl_print_int(i32)   nl_print_long(i64)   nl_print_bool(i1 zeroext)
nl_fail(i32, i32, i32, i32) noreturn cold nounwind
nl_expect_fail_compare(i32, i32, i32, ptr, i64, i64, i32)
nl_expect_fail_bool(i32, i32, i32, ptr)
```

Core-dialect types map to these directly: `int` is `i32`, `long` is `i64`, `bool` is `i1 zeroext`, `sys.Addr` is `ptr`, and `-> never` is `noreturn`. The hook table (one table in the compiler, next to E1's runtime-declaration table) holds each hook's name, signature and extra attributes (`cold` for `nl_fail`). When the compiler checks the core library, it verifies that each hook exists with that signature. A mismatch is an internal compiler error.

In core mode, the program part of the module differs from E1's C-runtime mode in exactly three ways:

1. The header says `; nlc.runtime core` (header version 2; see "Build and link").
2. The runtime-declarations section is empty, because the core library's definitions come later in the same module and LLVM IR allows a use before the definition.
3. `main` takes `envp` and calls `nl_core_init` first:

```llvm
define i32 @main(i32 %argc, ptr %argv, ptr %envp) {
entry:
  call void @nl_core_init(i32 %argc, ptr %argv, ptr %envp)
  ; ... then exactly E1's body: nl_test_selected_index, nl_context_create, nl_env_create, ...
```

Everything else is the same text. glibc accepts `main(argc, argv, envp)`, so in the self-hosted compiler's `--runtime=c` mode the only differences are the header, the declarations and the `nl_core_init` call. The harness builds the third leg with `--runtime=c`, never by editing IR text, and links it against `runtime/nl_runtime.c`, to tell a compiler bug from a core-library bug (see "Tests for E1c").

## The entry

### Freestanding `_start` (x86-64 Linux)

The compiler emits `_start` as module-level assembly, not as an IR function, so there is no prologue to worry about and no dependency on the `naked` attribute:

```llvm
module asm ".text"
module asm ".globl _start"
module asm ".type _start, @function"
module asm "_start:"
module asm "  .cfi_startproc"
module asm "  .cfi_undefined rip"      ; debuggers: there is no caller
module asm "  xor %ebp, %ebp"          ; mark the outermost frame
module asm "  mov %rsp, %rdi"          ; first argument: the initial stack
module asm "  and $-16, %rsp"          ; 16-byte alignment before the call
module asm "  call nl_core_start"
module asm "  ud2"                     ; nl_core_start never returns
module asm "  .cfi_endproc"
module asm ".size _start, . - _start"
```

On entry, `rsp` points at `argc`. The ABI already promises 16-byte alignment there, but the `and` costs nothing and protects against a loader that doesn't keep it. After `call` pushes the return address, the callee sees the usual alignment (`rsp` is 8 more than a multiple of 16). `rdx` holds a finaliser address from the dynamic loader, which is always zero in a static binary, and is ignored. The direction flag is clear and SSE is enabled at process start, as LLVM's code assumes. Nothing sets up thread-local storage: the `fs` base is 0, so any code that touched TLS would crash. The compiler emits no thread-locals and no stack-protector attributes (stack protectors read their canary from TLS).

The core library's side, in the core dialect:

```
// core/start.nl (freestanding only)
fn nl_core_start(initial: sys.Addr) -> never {
    let argc = sys.load64(initial, 0L)
    let argv = sys.offset(initial, 8L)
    let envp = sys.offset(argv, (argc + 1L) * 8L)
    // auxv starts after envp's terminating null entry
    sys.store_addr(sys.state(), state_auxv(), sys.offset(envp, (count_entries(envp) + 1L) * 8L))
    let status = sys.call_main((int)argc, argv, envp)
    sys.exit_group(status)
}

// core/start.nl (both variants)
fn nl_core_init(argc: int, argv: sys.Addr, envp: sys.Addr) {
    let state = sys.state()
    sys.store_addr(state, state_envp(), envp)     // environment lookups use main's envp
    sys.store64(state, state_page_size(), discover_page_size())
    sys.store32(state, state_print_fd(), 1)
}
```

`count_entries` walks the array with `sys.load_addr` until `sys.is_null`. `nl_core_init` does the process set-up that both start-ups share. The exit status is the low 8 bits of `main`'s result, as with libc's `exit`.

**Two things come from the start-up, and they're kept apart:**

- **The environment** for lookups (`NLC_TEST_INDEX` and the others) is the `envp` that `main` receives, in both variants. In the libc variant that's libc's environment array when `main` is called, which a foreign constructor may have changed with `setenv`. Lookups see the changed environment, as `getenv` would.
- **The auxiliary vector** (`AT_PAGESZ`, later `AT_SYSINFO_EHDR` for the vDSO) is initial-stack metadata, not part of the environment. Freestanding, `nl_core_start` records its address from the initial stack before `main` runs, as above. The libc variant has its own path, below. In the libc variant, the core library never scans past the end of the `envp` that `main` received, because that array may not be the one on the initial stack.

**The page size is assumed only where the architecture fixes it.** x86-64's base page size is architecturally 4096 bytes, so x86-64 builds use that constant. arm64 kernels may use 4, 16 or 64 KiB pages, so arm64 builds read `AT_PAGESZ` (key 6) from the `auxv`, and 4096 is never a default there. If no `AT_PAGESZ` is found (a freestanding kernel start-up always supplies it), the program fails at start-up with `nlc: startup failure: cannot determine the page size` and status 1. Freestanding builds still record the `auxv` address on both architectures, for later uses such as the vDSO.

### The libc start-up variant

A program that links a foreign C library that needs libc is linked normally: libc's own `_start` sets up libc (thread-local storage, the allocator, constructors) and calls `main(argc, argv, envp)`. That's the same `main` as above, and `nl_core_init` runs first, as before. The differences:

- No `_start` and no `nl_core_start` are emitted. `main` returns to libc, which runs `exit`, so the C library's `atexit` handlers and stdio buffers are flushed. The core library's own buffers are flushed before that, in `nl_context_destroy`.
- **On arm64, the auxiliary vector is read from `/proc/self/auxv`** in `nl_core_init`, with the core library's own `openat`, `read` and `close`, into a 512-byte area of the state block. It doesn't depend on `envp` at all. If `/proc` isn't mounted or the read fails, start-up fails with the page-size message above; there's no guessed value. That's a start-up dependency the C runtime doesn't have, and the report lists it. On x86-64 the libc variant needs no `auxv` in E1c's scope, so it doesn't read `/proc`.
- **The core library still never calls libc.** It uses its own memory functions, as internal symbols, exactly as in a freestanding build (see "The memory functions"). It makes its own system calls, and never touches libc's `errno`, stdio or allocator.
- **Output order with foreign code:** the core library flushes its own buffers before every foreign call whose binding declares the `out` effect. A binding that declares `out` must also leave nothing in the foreign library's own buffers when it returns: its C side flushes (for example `fflush(stdout)`) or writes unbuffered. Then neither side's output can overtake the other's. The binding generator emits that flush for bindings it wraps, the audit report lists `out` bindings, and a test with a C library that prints through `printf` between two next-lang prints checks the order on a pipe and on a terminal.
- **Tests specific to the variant:** a foreign C library with a constructor that calls `setenv("NLC_TEST_INDEX", ...)` before `main`. The test checks that the lookup sees the new value and that the page size still comes out right. This runs on x86-64, and on arm64 with a 16 KiB-page kernel when one is available to the test machines; until then the arm64 case is listed as unverified.

### The data stack in E1c

`nl_context_create` (core) does what nl_runtime.c:183-247 does in offset mode:

- It takes the page size that `nl_core_init` recorded, then the reservation: 256 KiB in offset mode unless `NLC_STACK_PREALLOC=1`, in which case it's the requested bytes (nl_runtime.c:190-195), rounded up to a page.
- It maps the header page, the stack and a guard page as one `PROT_NONE`, `MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE` range.
- It makes the header and the stack readable and writable with `mprotect`, leaving the guard page inaccessible.
- It puts the context in the header page.
- On failure it writes `nlc: data stack startup failure for entry '<name>' (reservation <n> bytes): <reason>` to stderr and exits with 1 (nl_runtime.c:96-104), with the same reasons.

`nl_context_base_offset` returns 0 (nl_runtime.c:294-298). E1's IR never reads the context's fields, so in E1c the context's layout is private to the core library. When generated code starts reading the context directly (the inline bump compares the top with the limit), the layout becomes shared. The core library will then declare the context as a struct, and the compiler will take field offsets from that one declaration, never from a second copy.

`nl_context_destroy` flushes output (`nl_fail(20, -1, 0, 0)` if the flush fails, nl_runtime.c:445). It skips `munmap`, because the process is about to exit and the memory goes with it. In E1c it doesn't print `NLC_STACK_STATS` (see "Environment variables").

### The native stack: not in E1c

E1 has no `recursive` functions, and `link-ir` refuses recursion headers (E1 spec:43). So nothing reads the native-stack bounds, and the kernel's main-thread stack (which grows on demand up to `RLIMIT_STACK`, 8 MiB by default) is enough. E1c doesn't map a native stack or switch to one. This is the design for the task that admits `recursive`, which replaces `pthread_getattr_np` (nl_runtime.c:145-181). It's deferred beyond E1c.

- **Mapping:** the core library maps `[guard pages | native stack]` with `MAP_NORESERVE` (and `MAP_STACK`). Its size is the entry's computed native bound (frame sizes from `-fstack-size-section`, which `clang_internal` already collects) plus the manifest's `recursion_budget` plus a 64 KiB margin, rounded to pages. The bounds are then known exactly, without pthreads or `/proc/self/maps`.
- **Switching is done by compiler-emitted assembly stubs, not inline asm.** A stack switch replaces the stack pointer and makes a call, which inline asm can't describe to LLVM: clobber lists don't cover the caller's red zone (the 128 bytes below `rsp` that leaf code may use on x86-64), alignment, unwinding, or getting the original stack back. So the compiler emits two real functions in module-level assembly, like `_start`, each with an explicit calling convention and CFI:
  - `nl_core_switch_noreturn(top, fn, a0, a1, a2)`, for freestanding start-up. It sets the stack pointer to `top` (16-byte aligned), clears the frame pointer, marks the outermost frame with `.cfi_undefined rip` (`lr` on arm64), and calls `fn(a0, a1, a2)`; `fn` must not return (the stub ends in a trap).
  - `nl_core_call_on_stack(top, fn, a0, a1, a2) -> i32`, for the libc variant, where `main` must return to libc. It follows the C calling convention (System V on x86-64, AAPCS64 on arm64). It saves the old stack pointer in a callee-saved register, switches, calls `fn`, switches back, restores, and returns `fn`'s result. Its CFI describes the saved stack pointer, so a debugger or unwinder walks from the new stack back to the libc frames. Because it's an ordinary called function, the caller's red zone lies below the caller's own stack pointer on the old stack and is never touched.
  - Both stubs are part of the compiler-emitted assembly, with `_start`, the syscall helpers and the bulk copies.
- **Tests for the stubs:** callee-saved registers survive `nl_core_call_on_stack` (checked by an assembly test that fills them with known values); the new stack's alignment at the call; return to libc's `main` caller with the right status; a backtrace through the switch in `gdb`; and guard-page probing of a large frame on the new stack (below).
- **The default budget changes meaning.** Today, with no `recursion_budget`, the budget is the main thread's stack size minus 80 KiB (nl_runtime.c:174-180), which depends on `RLIMIT_STACK`. With its own mapping, the core library uses a fixed default (8 MiB minus 80 KiB). Recommendation: change the C runtime's rule to the same fixed default in the same task, because it's still the reference and may take fixes, so the comparison stays exact.
- **Guard pages and big frames:** a frame larger than the guard can jump over it. In freestanding builds, every function gets `"probe-stack"="inline-asm"`, which makes LLVM touch each page of a large frame in order. That's what clang's `-fstack-clash-protection` does for C. Its cost is measured on the self-hosted parser.

## The memory functions

LLVM turns `llvm.memmove`, `llvm.memset` and large aggregate copies into calls to `memcpy`, `memmove` and `memset` whenever it doesn't expand them inline (emit.rs emits `llvm.memmove` in dozens of places, for example 6433 and 7908). Its MergeICmps pass can create `memcmp` calls, and on Linux it may turn `memcmp(...) == 0` into `bcmp`. Each of these must resolve to the core library's own code, in both start-up variants, because the core library never calls libc. E1's own programs may need none of them, but the link must not depend on that.

**Where they live:** `core/memory.nl`, in the core dialect, under their C names (`memcpy`, `memmove`, `memset`, `memcmp`, `bcmp`), with `internal` linkage and listed in `@llvm.compiler.used` so the optimiser keeps them although no IR calls them yet. One policy for both variants:

- They're emitted in every core-mode build, freestanding and libc variant alike.
- LLVM emits its libcalls during code generation, as references to the plain name `memcpy` and the others, in the same object file as these definitions. The assembler binds such a reference to the local definition in the same object, so the program's own libcalls reach the core's functions and the object file has no undefined memory-function symbol.
- Being local, they're never exported and never seen by the linker as definitions of the C names. So in the libc variant, libc and every foreign library keep calling libc's own `memcpy`, nothing is interposed in a dynamic link, and a static link against `libc.a` meets no duplicate definition.
- These binding claims are what the tests below check, not recalled behaviour. If a test shows that a libcall doesn't bind to the local definition (for example under LTO), the build is refused for that configuration and the design comes back for review; there's no fallback to libc's functions.

**The helper closure has no way back in:**

- **One mark for the whole closure.** The five functions and every function they can reach (`copy_forward`, `copy_backward`, `fill_forward` and the like) get the `"no-builtins"` function attribute. It tells LLVM that no library function may be assumed inside them, so LoopIdiomRecognize can't turn a copy loop into a `memcpy` call and MergeICmps can't create `memcmp`. Nothing outside the closure gets it, so the hooks can still inline into user code (see the core dialect's rules). A libcall LLVM creates outside the closure just binds to the core's function, as above.
- **No memory intrinsics in the closure.** Its bodies use only loads, stores, loops and the bulk-copy intrinsics below. Never `llvm.memcpy`, `llvm.memmove` or `llvm.memset`, which the backend may lower to a call whatever the attribute says.
- **No calls out of the closure.** A failed checked-arithmetic test inside it lowers to `llvm.trap`, not a call to `nl_fail`, because `nl_fail` flushes output and the flush's copy could become a `memcpy` call, closing a cycle. A negative length also traps. The closure makes no system calls.
- **No `alwaysinline` across the boundary.** `alwaysinline` overrides the inliner's refusal to mix `"no-builtins"` settings, so no function in the closure is `alwaysinline`, and the closure calls no `alwaysinline` function. The `sys` load, store and bulk-copy operations aren't calls; they lower to instructions in place.
- **The check is on the linked binary, transitively.** A test disassembles every core-mode test binary (`llvm-objdump -d`) after linking, at -O1 and -O3, and builds the call graph from the five entry points. Direct calls, tail-call jumps, and every clone or outlined copy LLVM made of a closure function (names with `.`-suffixes) count as edges. It fails if any path from one of the five reaches one of the five again, reaches any function outside the closure, or contains an indirect call. A direct-call scan alone would miss `memcpy -> helper -> memcpy`.
- **LTO is gated on the same check.** If a build uses LTO (for example with a foreign static library compiled for it), the call-graph test runs on the binary after LTO, and internalization must keep the `"no-builtins"` attributes and the `@llvm.used`/`@llvm.compiler.used` roots (`nl_core_start`, the memory functions). Until that test passes for an LTO configuration, that configuration isn't offered.
- **Nothing undefined that we didn't declare.** For a freestanding binary, `nm -u` must list nothing; a `-nostdlib` link already fails on one, and the test names the symbol. For the libc variant, there's no `-nostdlib` to catch a new libcall, so the test compiles the program's module to an object (`clang -c`) and checks that `nm -u` lists only the symbols that foreign bindings declare. `nm` on the same object must show the five memory functions as local (`t`), and `readelf --dyn-syms` on the linked program must not list them. One libc-variant program is linked both dynamically and statically against `libc.a` to show neither link clashes.

**Shape:** a sketch of `memmove` (proposed; core dialect):

```
// core/memory.nl. Speed matters; these are written for the code LLVM produces at -O1.
fn memmove(dst: sys.Addr, src: sys.Addr, n: long) -> sys.Addr {
    let gap = sys.distance(src, dst)          // dst - src
    if gap >= 0L && gap < n {
        copy_backward(dst, src, n)            // overlap with dst above src
    } else {
        copy_forward(dst, src, n)
    }
    dst
}

fn copy_forward(dst: sys.Addr, src: sys.Addr, n: long) {
    if n >= bulk_threshold() {                // 2048 bytes to start; measured
        sys.copy_forward_bulk(dst, src, n)    // x86-64: rep movsb
        return
    }
    let words = n / 8L
    for i in 0L..words {
        sys.store64(dst, i * 8L, sys.load64(src, i * 8L))
    }
    for i in words * 8L..n {
        sys.store8(dst, i, sys.load8(src, i))
    }
}
```

- **Small sizes** (under 16 bytes): overlapping loads and stores (two 8-byte moves cover 8 to 16 bytes), with no loop.
- **Medium sizes:** 8-byte word loops in E1c. If the benchmark misses its bar here, 16-byte vector moves follow, with `sys.load128` and `sys.store128` lowered to `<16 x i8>` loads and stores (baseline x86-64 SSE2 has them). At -O1, the default, LLVM doesn't vectorise loops, so explicit wide moves would matter.
- **Large sizes:** `sys.copy_forward_bulk` lowers on x86-64 to `rep movsb` (constraint `"={di},={si},={cx},0,1,2,~{memory},~{dirflag}"`), and `memset` uses `sys.fill_bulk`, which is `rep stosb`. On CPUs with fast string instructions (ERMS), these are close to the best copies for large blocks, and glibc uses them above a threshold too. Backward copies use word loops, because `rep movsb` with the direction flag set is slow.
- `memcmp` returns the difference of the first differing bytes as unsigned values (sign only, which is all callers may rely on). `bcmp` returns zero or non-zero.

**Measuring the speed:** a benchmark under `bench/memfn/` times each function against glibc's. It's one next-lang program in the libc variant. It calls glibc's functions through a foreign binding to a small C shim (`bench_libc_memcpy` and the others, each a plain call into glibc, compiled with `-O2`), and the core's functions through equally out-of-line calls, so call overhead is the same on both sides. The shim is a benchmark tool, not part of the core library.

- **Sizes:** 0 to 64 in steps of 1, then 128, 256, 512, 1 KiB, 4 KiB, 64 KiB, 1 MiB and 16 MiB.
- **Alignment:** destination and source aligned, and misaligned by 1 and by 7.
- **`memmove`:** forward and backward overlaps.
- **Method:** each size is repeated until the run lasts at least 100 ms. Best of 7, alternating the two builds, on pinned cores, holding the WSL benchmark lock. The report gives ns per call for small sizes and GB/s for large ones, with the CPU model and the clang version.
- **Bar:** within 1.25x of glibc for sizes up to 256 bytes and at or above 4 KiB, at both -O1 and -O3; anywhere worse is listed with a reason.
- **Whole program:** once the self-hosted compiler emits copies (E3), compare the self-hosted parser's wall time with the core library and with the C runtime.

## Packaging

**Where the source lives:** top-level `core/`, a sibling of `runtime/`. It's not part of the compiler, and it's compiled into every program the compiler builds, as `runtime/nl_runtime.c` is linked into every program Rust nlc builds.

```
core/
  package.toml            name = "core", state_bytes = ...
  start.nl                nl_core_start, nl_core_init, environment and auxv reading
  context.nl              nl_context_create/destroy, the data stack
  output.nl               buffers, flushing, terminal detection, print hooks
  fail.nl                 nl_fail, expectation reports, the message table
  format.nl               decimal formatting
  memory.nl               memcpy, memmove, memset, memcmp, bcmp
  linux/                  the platform layer for Linux (both architectures)
  macos/, windows/        later
```

A package is one directory (DESIGN.md:794). The core library is the exception. It's built from the files of `core/` plus those of the one platform directory for the target. That rule applies only to the embedded core unit. The syscall numbers live in the compiler's per-architecture table, and `struct statx` and `struct sigaction` have the same layout on both Linux architectures, so `core/linux/` serves x86-64 and arm64 alike. The only architecture-specific pieces are compiler-emitted: `_start`, the syscall helpers, the bulk-copy asm and, later, the stack-switch stubs.

**How it reaches a build: embedded, not read at build time.** The self-hosted compiler's `Fs` is rooted beneath its working directory with `RESOLVE_BENEATH` (nl_runtime.c:1527, 1656-1668). So it can't reach a fixed path such as the repository's `core/` from an arbitrary working directory. And reading `core/` from the working directory would let any directory there named `core/` become privileged. Instead:

- `scripts/embed-core.sh` generates `selfhost/core_files.nl` from `core/`. It holds one function per file, returning the file's name and bytes as a `b"..."` literal (`\xNN` escapes where needed). It also holds the SHA-256 of the core sources as a literal.
- The generated file is checked in, so Rust nlc builds the self-hosted compiler with no extra step. `cargo test` regenerates it in a temporary directory and fails if the checked-in copy differs (stale embed).
- The self-hosted compiler writes the hash into the IR header (`; nlc.core <hex>`), so a report always says which core library a binary was built with.
- When a self-hosted package needs a byte literal longer than the lexer's limits allow, the embed splits a file into several literals.
- **Input budgets are separate.** The input policy's limits (file count, file size, total bytes) apply to the user package alone; the embedded unit doesn't count against them. The core unit has its own fixed budget, checked by the same `cargo test` that checks staleness (for example at most 64 files and 1 MiB of source), so a growing core library can't push a user package over its limits, and the core can't grow unnoticed.

**Build order inside the self-hosted compiler:**

1. The user package goes through the whole E1 pipeline as now: front end, manifest, eligibility, checker.
2. Only if it is accepted does the compiler lex, parse and check the embedded core library, with the privileged flag on.
3. A diagnostic in the core library is a compiler bug. It's reported as `nlc: internal error in the core library: <file>:<line>:<col>: <message>` with status 3, and never affects the order or content of the user's diagnostics.
4. Emission puts the core library's functions after the user's, in a fixed order (core files sorted by name, then source order), so the module stays deterministic.

The core library is a few thousand lines at most, so parsing and checking it on every build costs milliseconds. The report measures it. Caching a compiled core object per target, optimisation level and build kind is a later option, but it would lose cross-module inlining of the hooks, so it needs a measurement first.

**How the two compilers relate to it:**

- Rust nlc never compiles the core library and gets no `sys` support. It keeps `runtime/nl_runtime.c` as the stage-0 reference until it's frozen (DESIGN.md:162).
- The self-hosted compiler links its programs with the core library from E1c on.
- The comparison harness (`scripts/compare-selfhost.sh --build`) compares behaviour as before. Rust nlc plus the C runtime is the reference; the self-hosted compiler plus the core library is the subject.
- A behaviour change goes into both runtimes in the same task, or it's a mismatch.
- While the hook ABI is the C runtime's, the harness also runs a third leg on every `build` case: the self-hosted IR linked against the C runtime (see "Tests for E1c"). It ends with that ABI, below.

**Retiring the hook ABI.** Two milestones are involved, and they're kept apart:

- **The fixed hook table lasts as long as the third leg needs it, and no longer.** The third leg only works while core-mode and C-mode program IR differ in the three listed ways. The first core function that needs data-stack regions (E3: `Bytes`, `Text`, builders) needs the context, so the hooks move to a context-passing ABI before that function lands. Context passing must also land before jobs or concurrent output, whichever comes first, because per-job state can't live in a process-wide block. That task removes the third leg and the `--runtime=c` mode.
- **The reference comparison lasts until Rust nlc freezes** (PLAN.md:29), independent of the ABI. It compares behaviour (stdout, stderr, status), not IR, so a new hook ABI doesn't affect it.
- **What replaces the third leg** when it's removed: the core library's own `test` blocks (built by `nlc core-test`), which pin each hook's output bytes and failure statuses; one contract fixture per hook in the hook table, a small IR program that calls the hook with edge-case arguments, whose expected stdout, stderr and status are recorded from the C runtime while the old ABI still links against it; and the reference comparison itself. A mismatch in the comparison that the fixtures don't reproduce is then a compiler fault until shown otherwise.
- **The memory functions keep their C signatures for good.** `memcpy`, `memmove`, `memset`, `memcmp` and `bcmp` never get a hidden context or job parameter, because LLVM's libcalls call them with the C signature.

## Behaviour E1c reproduces

Everything here is compared byte for byte (stdout, stderr, status) by the existing harness. Rows marked "own test" need a fixture of their own, because the harness never runs on a terminal or with a broken output.

### Output buffering and flush points

- **Buffers:** one 64 KiB buffer each for stdout and stderr (nl_runtime.c:31-36), in the core state block.
- **Terminal detection** happens once, lazily, on the first write or flush (nl_runtime.c:1710-1725). `is_terminal[i]` is `ioctl(fd, TCGETS, scratch) == 0`, for fds 1 and 2; that's what glibc's `isatty` does. The streams count as one shared terminal when both are terminals and `statx` shows the same device and inode. The state starts as "unknown".
- **When output is flushed:**
  1. A buffer that's full is flushed before more is copied in (1777-1782).
  2. A stream that's a terminal is line-buffered: a write is cut after each `\n` and flushed there (1785-1800).
  3. When both streams are the same terminal, writing to one first flushes the other if it holds anything (1770-1774).
  4. `flush_all` writes stdout then stderr. On a shared terminal with both non-empty, it writes the stream that wasn't written last first (1750-1764).
  5. Flush points: `nl_context_destroy` at the end of a run, `nl_fail`, and the start of each expectation report. Later tasks add `Env.exit`, `Out.*` (each write is flushed at once, 1805-1815, 2297-2335), and the start of every `Fs` read and listing (1849, 1907, 2113, 2178). `Fs.write` doesn't flush (2227-2248).
- **Writes** loop until done. `EINTR` is retried. A failed write keeps the unwritten tail at the front of the buffer, moved down (1737-1741), so a later flush retries exactly the missing bytes.
- **Error codes:** a `write` that returns 0 is treated as `EIO`. The C runtime uses `errno ? errno : EIO` there (1698, 1736), which can pick up a stale `errno`. The only consumer is the error code inside an `IoError.Other` from `Out`, which isn't in E1. Recommendation: make the C runtime use `EIO` too, when `Out` reaches the self-hosted compiler.
- **Print failures:** a print whose write fails calls `nl_fail(20, -1, 0, 0)` (968-970). That reports `<source>:0:0: standard output write failed`, even when the failing stream is stderr.

### Printing

- `nl_print_int` and `nl_print_long` format decimal digits, add `\n`, and write to the print fd (1 unless set to 2, 1364-1386). `nl_print_bool` writes `true\n` or `false\n` (1388-1392).
- Decimal formatting works on the non-positive side, so the minimum `long` needs no special case. That replaces the C runtime's unsigned-magnitude trick (1023-1025), which the core dialect can't express:

```
fn format_decimal(value: long, out: sys.Addr) -> long {
    var n = value
    if n > 0L { n = 0L - n }                   // n <= 0 from here on
    var digits = 1L
    var rest = n / 10L
    for i in 0L..19L {
        if rest == 0L { break }
        digits += 1L
        rest = rest / 10L
    }
    var at = 0L
    if value < 0L { sys.store8(out, 0L, 45); at = 1L }    // '-'
    var place = at + digits - 1L
    for i in 0L..digits {
        sys.store8(out, place, (int)(48L - n % 10L))      // n % 10 is in -9..=0
        n = n / 10L
        place -= 1L
    }
    at + digits
}
```

The digits are the same bytes as the C runtime's table version (995-1055). Speed matters little here: the compiler's large outputs go through `Fs`, not `print`.

### Failures

- `nl_fail(kind, file_id, line, col)` (905-936):
  1. It flushes both buffers, ignoring errors.
  2. It writes `<file>:<line>:<col>: <message>\n` to stderr directly, not through the buffer. `<file>` is the registered name, or `<source>` for an id that is negative, out of range or unregistered (900-903). `line` and `col` print as signed 32-bit decimals.
  3. It exits with 70 in test mode, otherwise 1.

  The message table is copied in full (kinds 1 to 21, `runtime failure` for any other kind), not only E1's kinds 1 to 9, 12, 13 and 20, so a later subset can't miss one.
- The message is built in a scratch area of the state block and written with one write loop. glibc's unbuffered `fprintf` also writes it in one call. The bytes are the same either way.
- **The file registry** is a fixed table of 1024 entries in the state block (user files are at most 256 under the input policy, then core files). The C runtime grows it with `realloc` and silently ignores a failed growth (529-543). An id at or past 1024 is ignored, so it reports `<source>`; the input policy keeps ids below that.
- Names and expectation sources are NUL-terminated constants, as now. The core library measures them by scanning for the zero byte, so a source with an embedded NUL is cut at the same place `printf("%s")` cuts it.

### Expectation reports (on stdout, not stderr)

- `nl_expect_fail_compare` (938-956) flushes both buffers, then writes to stdout directly:

  ```
    <file>:<line>:<col>: <source>
      left:  <left>
      right: <right>
  ```

  That's two spaces before the location, four before `left:` and `right:`, two spaces after `left:` and one after `right:`. The values are signed 64-bit decimals, or `true`/`false` (non-zero is true) when the bool flag is set.
- `nl_expect_fail_bool` (958-966) writes `  <file>:<line>:<col>: <source>\n    value: false\n`.
- The C runtime writes these through libc's `printf` and then `fflush(stdout)`. That is outside its own buffer, so it lands in the file right after the flush. The core library writes directly too, with the source written straight from its constant, however long it is. Output that a failing flush left in the buffer stays behind and is retried later, as in C.
- The test then returns 1, and its process ends with status 1 after `nl_context_destroy`.

### Test mode and the test-child protocol

- **Selection:** `nl_test_selected_index` (545-552) reads `NLC_TEST_INDEX` from `envp` (the first entry that starts with `NLC_TEST_INDEX=`, as `getenv` finds it). It reproduces `strtol(value, &end, 10)` exactly:
  - leading white space (space and `\t \n \v \f \r`) is skipped;
  - one optional `+` or `-`;
  - decimal digits, saturating at the `long` limits;
  - the value counts only if at least one digit was read and nothing follows the digits.

  An empty or missing value, no digits, trailing characters, a negative result or one above 2147483647 all give -1. So ` 3` and `+3` select test 3, `-0` selects test 0, and `3x` and `99999999999999999999` select none. A test pins each of these.
- **Dispatch:** the dispatch itself is in the program IR, unchanged. An index below the test count runs that test after `nl_set_test_mode`. Anything else falls through to `main` if there is one, or returns 0. This also holds in a program build, which has the same module (E1 spec:27).
- **Test mode** only changes the exit status of `nl_fail` (and later `Env.exit`, 1557-1566) to 70.
- **The runner side** (one child per test, `ok`/`FAIL` lines, the status-70 line, stdout forwarded before stderr) is Rust's `test-ir`, unchanged (E1 spec:44-51, driver.rs:813-890).

### Exit statuses

| Status | When |
| --- | --- |
| 0 | `main` returned, or the test passed, and the final flush succeeded |
| 1 | a runtime failure outside test mode; a failed expectation; a startup failure (data stack, arguments, root), in a test child too |
| 70 | a runtime failure in test mode, including a failed final flush (`nl_fail(20, -1, 0, 0)` after `nl_set_test_mode`) |
| killed by a signal | only for a crash the language should have prevented; never SIGPIPE, which is ignored |

### Startup checks that apply to E1's subset

In the order the IR calls them:

1. **Test selection:** none.
2. **`nl_context_create`:** the data-stack failures above, all exit 1.
3. **`nl_env_create`** (1503-1534):
   - It sets SIGPIPE to ignored.
   - More than 64 arguments after the program name gives `nlc: startup argument failure: more than 64 program arguments were supplied`. An argument longer than 4096 bytes gives `nlc: startup argument failure: a program argument is longer than 4096 bytes`. Both exit 1.
   - It opens the root with `openat(AT_FDCWD, ".", O_PATH | O_DIRECTORY | O_CLOEXEC)`. A failure gives `nlc: data stack startup failure: cannot open the file-system root` (the C runtime's wording, 1529) and exits 1.
4. **No memory claim:** E1 has no globals.

`nl_env_destroy` closes the root.

**Deferred, deliberately:** in test builds, the C runtime creates `/tmp/next-lang-test-XXXXXX` with `mkdtemp`, opens it as the root, and removes it at the end (1518-1528, 1540-1545, 1480-1500). In E1's subset no operation can see the root, so the only observable difference is a failure to create it (an unwritable `/tmp`). E1c doesn't create it. The task that brings `Fs` into the self-hosted compiler adds it, using `mkdirat` with a random name from `getrandom` (as `mkdtemp` does), and `getdents64` plus `unlinkat` for removal. The E1c report lists the difference.

### Environment variables

- **E1c honours `NLC_TEST_INDEX` and `NLC_STACK_PREALLOC`.**
- **The rest wait** for the first task with regions (E3), which makes them observable:
  - `NLC_STACK_STATS` prints after the final flush (447-457), so it changes stderr when set;
  - `NLC_STACK_VERIFY` matters only on growth;
  - test-build-only `NLC_TEST_DATA_STACK_BYTES` is validated before the offset-mode override (106-128, 189-195), so a malformed value fails startup even in offset mode;
  - `NLC_TEST_ALLOW_STACK_EXHAUSTION`, `NLC_TEST_REPORT_STACK_RESIDENT` and `NLC_TEST_MEMORY_POLICY`.
- **The harness runs with a fixed environment** in which all of these are unset (E1 spec:334), so E1c's comparison is exact.
- **The E1c report** lists each variable as reproduced or deferred. The reference runs in pointer mode and the subject in offset mode (E1 spec:226), so stack-statistics output differs between the two anyway, and can't be in the comparison.

## Build and link

### Flags

Freestanding (Linux x86-64 and arm64):

```
clang -O1|-O3 -nostdlib -static -Wl,-e,_start [-fstack-size-section] module.ll -o program
```

- **`-nostdlib`** links no C start-up files, no libc and no compiler support library. An unexpected libcall fails the link loudly.
- **`-static`** produces a static, non-PIE executable. clang shouldn't pass `-pie` to the linker with `-static`; a link test checks that `readelf -h` reports type `EXEC` and adds `-no-pie` if it doesn't. The same test checks that `readelf -l` shows no `INTERP` program header and `readelf -d` no `NEEDED` entries, so nothing loads a dynamic linker or a shared library. A static-PIE build would need code in `_start` that applies the executable's own relocations (see "Risks and open questions", item 6).
- **`-Wl,-e,_start`** is the linker's default entry anyway. It's written out so it's visible.
- **No `-D` flags:** there is no C file. The build kind reaches the core library through the IR header, which the compiler turns into a constant.
- **Frontend flags:** `-ffreestanding`, `-fno-builtin` and `-fno-stack-protector` are C frontend flags. It isn't established that they affect `.ll` input, and they may only give "argument unused" warnings. The build doesn't pass or rely on them; freestanding is expressed in the IR itself. That means `"no-builtins"` on the memory-function closure, `internal` linkage for core symbols, no `ssp`/`sspstrong` attributes anywhere, no thread-locals, and `"probe-stack"="inline-asm"` once own-mapped native stacks arrive.
- **Determinism:** `-Wl,--build-id=none` is added if the stage-2/stage-3 identity check (PLAN.md, Bootstrapping at S3) needs it.

The libc variant is the same command without `-nostdlib`, `-static` and `-e`, plus the foreign libraries. The core library's memory functions are still in the module, as internal symbols (see "The memory functions").

### The `link-ir` bridge

E1 defines `nlc link-ir <file.ll> -o <exe>` and `nlc test-ir <file.ll>` in compiler/src/driver.rs, sharing one clang path (`run_clang` takes the IR path and a link description), and a versioned header that refuses unknown lines with status 3 (E1 spec:29-66). E1c changes that contract:

- The header goes to `; nlc-link-ir 2` and gains `; nlc.runtime c|core` and `; nlc.core <sha256>`. A version-1 file means `runtime c`, so E1's files keep linking.
- The link description gains the runtime. For `c`, `run_clang` passes `runtime/nl_runtime.c` and the `-D` flags as today. For `core`, it passes the freestanding flags above and no runtime source.
- `NLC_OPT_LEVEL`, the "clang failed" error, the recursion refusal and the test runner are unchanged.
- The self-hosted compiler gets `--runtime=c|core`, with `core` the default from E1c on. `c` exists only for the third harness leg and is deleted with it (see "Retiring the hook ABI").

## Tests for E1c

- **The comparison:** `scripts/compare-selfhost.sh --build` unchanged, at -O1 and -O3, with zero mismatches.
- **The third leg** on every `build` case: the self-hosted IR in `c` mode, compared with the core-mode result. When the subject disagrees with the reference, this tells a compiler fault (both self-hosted legs wrong) from a core fault (only the core leg wrong).
- **A pseudo-terminal test** (through `script -q -c` or a small pty helper in the test) for line buffering and shared-terminal ordering. It compares the interleaved bytes against the C runtime with stdout and stderr on one terminal, and on two different ones.
- **A closed-pipe test:** stdout to a pipe whose reader has exited. It expects `<source>:0:0: standard output write failed` on stderr and status 1, or 70 in a test child.
- **A full-disk test:** stdout redirected to `/dev/full`, for the flush-failure path. `/dev/full` fails every write outright, so it doesn't exercise partial writes.
- **Partial writes, by injection:** in test builds only, the core library's system-call wrappers consult a fault plan in the state block ("the Nth `write` returns k bytes", "the Nth call of a given system call fails with errno e"). The file-I/O task reuses the same plan. Only the core library's own `test` blocks set it; nothing in the environment does. Those tests check that a short write continues from where it stopped, that `EINTR` is retried, and that a failed flush keeps exactly the unwritten tail for the next flush.
- **arm64:** the freestanding entry, syscalls and memory functions are run, not only cross-compiled, under `qemu-aarch64` user emulation, until an arm64 machine is in the test set.
- **`NLC_TEST_INDEX` parsing** cases, listed in "Test mode and the test-child protocol", against the C runtime.
- **Startup checks:** argument counts 64 and 65, an argument of 4096 and of 4097 bytes, and a working directory without search permission for the root open.
- **The memory-function tests:** the post-link call-graph check, the `nm -u` and local-symbol checks (see "The memory functions"), and correctness against a byte-by-byte reference for every size from 0 to 300 and every alignment from 0 to 15 (overlaps both ways for `memmove`). The correctness tests run in the core library's own `test` blocks, built by `nlc core-test` from the embedded set only and run with `test-ir`.
- **Privilege tests:** `diagnose` cases where a user package names `sys.write`, `sys.Addr` (directly, through a type alias, and as a generic argument), a core function and a hook name, and a foreign binding that names `memcpy`, `nl_print_int` or an `nl_core_` symbol. Each is refused; a binding to `nl_socket_alloc` is accepted. Cases that use forms outside E1's subset (aliases, generics, bindings) are added by the task that brings the form to the self-hosted compiler. A user package called `core`, and a `core/` directory beside one, gets no privilege.
- **System-call budget:** a test runs a scalar program under `strace -f -c` and checks there are no memory system calls beyond the context's `mmap` and `mprotect`s, and no `brk`. With no libc there can be no heap calls; this keeps it that way (DESIGN.md:164).

## File I/O in the core library

This follows when a later E-task brings `Fs` into the self-hosted compiler (PLAN.md:31). It's designed now because it fixes several `sys` signatures. The user-visible operations keep their current behaviour, which is the C runtime's (nl_runtime.c:1838-2295), except for the two additions DESIGN.md:160 decides. Any change to an existing operation's behaviour goes into both runtimes in the same task, or it's a mismatch.

### Paths and errors

- **Paths:** a path is extracted from its value as now (at most 4096 bytes, no NUL, not absolute, empty means `.`; 1581-1618) into a 4097-byte scratch area in the job's region, NUL-terminated.
- **Opening:** opens go through `sys.openat2(root, path, how, 24)`, with `how` holding `flags`, `mode` and `resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS` (1656-1668). An escape attempt fails with `EXDEV`.
- **Error mapping** (1466-1471), the same table in the core library:

  | errno | `IoError` |
  | --- | --- |
  | `ENOENT` | `NotFound` |
  | `EACCES`, `EPERM`, `EROFS` | `NoPermission` |
  | `EXDEV`, `ELOOP` | `Outside` |
  | any other | `Other(errno)` |

  `ENAMETOOLONG` is `Other`, as now. An absolute path is `Outside` and a path over 4096 bytes is `TooLarge`, from the path check (1581-1618). `TooLarge`, `TooMany`, `NameTooLong`, `BadPath` and `InvalidUtf8` come from the core library's own checks, never from errno.
- **Kernel refusals keep their `IoError`.** `ENOSYS` (an `openat2` the kernel lacks) stays `Other(38)`, and `EPERM` stays `NoPermission`, in both runtimes; the core library doesn't turn either into a failure of its own. `EPERM` alone can't tell a seccomp filter from an ordinary permission error, so nothing claims it does. There's no fallback to plain `openat`, which would weaken the beneath-the-root guarantee.
- **System-call context is added where an error is reported, not in the value.** The job context records which system call produced the most recent errno-based `IoError` (a small number naming the call, no allocation). Where a person sees the error (a runtime failure message, and a describing operation for `IoError` when the file-I/O task adds one) the text names the call and the errno, for example `openat2 failed with ENOSYS (38): needs Linux 5.6 or later, or was refused by a security policy`. Both runtimes do this the same way in the same task, so their output still matches.

### The operations, one by one

Each operation below keeps its current semantics exactly. All share the path check, the open beneath the root and the error table above. Results are published only on success: on any failure an output's length stays 0.

- **`fs.read(path, buffer)` into a bounded byte list** (`nl_fs_read`, 1838-1887):
  - **Order:** a capacity too large for the runtime's arithmetic is `TooLarge` first; then the path check; then flush output; then open with `O_RDONLY | O_CLOEXEC`.
  - **Loop:** read until the list's capacity is reached or a read returns 0. Retry `EINTR`, accept short reads.
  - **Probe:** if the list filled, read one more byte; any byte means `TooLarge` (1869-1878).
  - **Close,** then publish the length (1880-1886).
  - **Copying:** the list's elements are wider than bytes, so the C runtime copies through an 8 KiB scratch area (1856-1867). The core library does the same until O5 retires this form.
- **`fs.read(path, buffer)` into `Bytes`** (`nl_fs_read_string` with `is_text = 0`, 1889-1958): the same order, loop and probe, but each `read` goes straight into the destination's bytes, through an address derived from the offset immediately before the call (see "The stack is pinned while the kernel holds an address into it").
- **`fs.read(path, buffer)` into `Text` or `Ascii`** (`is_text = 1`): as for `Bytes`, then the bytes are validated where they lie with the boundary validator (below), which also counts code points. Invalid bytes give `InvalidUtf8`; more code points than the declared maximum give `TooLarge` (1940-1952). Either way the length stays 0. The file isn't read twice and the bytes aren't copied.
- **No size check before reading.** DESIGN.md:160 says reads "size the file". That size is advisory only: the core library may read it with `statx(fd, "", AT_EMPTY_PATH, STATX_SIZE)` to plan its reads, but it never changes a result. `TooLarge` is decided only by filling the destination and probing, as now, so a file that is larger at `statx` time but shrinks before it's read still reads normally. Early rejection would be a behaviour change in both runtimes, and isn't adopted.
- **`fs.list(dir, entries)`** (`nl_fs_list`, 2104-2147):
  - **Order:** capacity check, path check, flush, open with `O_RDONLY | O_DIRECTORY | O_CLOEXEC`.
  - **Records:** `getdents64` into an 8 KiB buffer, with the same record checks (1975-2014); a malformed record is `Other(EIO)`. `.` and `..` are skipped.
  - **Per entry, in this order:** a name over 4096 bytes is `NameTooLong`; one more entry than the capacity is `TooMany`; then the kind comes from a no-follow lookup (`fstatat` with `AT_SYMLINK_NOFOLLOW` in C, 2133; `statx` with the same flag in the core library), so a symbolic link is listed as "other", not as what it points to. A failed classification is that error, and the listing fails.
  - **Sort:** the same in-place heap sort by bytes (2079-2089), then publish the count.
- **`fs.list_with_extension(dir, ext, entries)`** (`nl_fs_list_with_extension`, 2161-2225). Its rules differ from `list`, and the difference is kept:
  - **Filter:** a name is kept only if it has a dot that isn't its first byte and the text after the last dot equals `ext` exactly (`nl_has_extension`, 2149-2159). So `.bashrc` has no extension and `a.` matches an empty `ext`. Names that don't match are skipped before any other check.
  - **Per entry, in this order:** `NameTooLong` for a name over 4096 bytes; then the kind; then `TooMany`.
  - **Kind follows permitted symbolic links:** the directory path and the name are joined and opened beneath the root with `O_PATH` (`nl_entry_kind_beneath`, 1670-1691), and the kind is read from that descriptor. So a link to a file inside the root is listed as a file. A link that escapes the root, a joined path over 4096 bytes, or any failure gives kind "other", never an error.
  - **Sort** as for `list`.
- **`fs.write(path, data)`** (`nl_fs_write`, 2227-2248): see "Writes" below. It doesn't flush output first.
- **`fs.join(dir, name)`** (`nl_fs_join`, 2250-2295): no system call and no flush. Either part starting with `/` is `Outside`; a joined length over 4096 is `TooLarge`; a `..` that would climb above the start, counted part by part, is `Outside`; a NUL byte is `BadPath`. A `/` is added between the parts only when needed.

### Writes

- **The plain write** is what `Fs.write` does today: open with `O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC` and mode `0666` (less the process umask), then write in a loop. Short writes continue from where they stopped, and `EINTR` is retried. A failed `close` counts as the error if nothing failed before it (2227-2248). A failure part-way leaves a truncated or partial file, as today; that's what the atomic write is for.
- **The atomic write** (`Fs.write_atomic(path, data)`, proposed) means a reader sees the old file or the new one, never half of either. Its error type says whether the replacement happened:

  ```
  enum AtomicWriteError {
      NotReplaced(IoError),          // the target is untouched
      ReplacedNotDurable(IoError),   // the target is the new file; surviving a crash is uncertain
  }
  ```

  The steps:
  1. **Split** the path into its directory and final name. A final name that's empty, `.` or `..` is `BadPath`.
  2. **Open the directory** with `openat2(root, dir, O_RDONLY | O_DIRECTORY | O_CLOEXEC, RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS)`. Every later step uses names relative to this descriptor, so nothing resolves outside the root.
  3. **Create the temporary file** with `openat(dirfd, tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0666)`. `tmp` is `.nl-tmp-` followed by 16 hexadecimal digits from 8 bytes of `getrandom`: always 24 bytes, whatever the target's name, so it can't exceed the 255-byte name limit (`NAME_MAX`) even when the target's name is at that limit. On `EEXIST`, draw a new name, up to 64 times, then fail with `Other(EEXIST)`.
  4. **Write** the data in a loop (short writes continue, `EINTR` is retried), then `fsync(fd)`, then `close(fd)`. The `close` is attempted even if the write or the `fsync` failed.
  5. **Commit** with `renameat2(dirfd, tmp, dirfd, name, 0)`. This replaces the target in one step; if the target is a symbolic link, the link itself is replaced, so the write still stays beneath the root.
  6. **Make the commit durable** with `fsync(dirfd)`.
  7. **Close the directory.** `close(dirfd)` runs on every path that opened it, success or failure.

  What happens on each failure:

  | Failure | Result | The target | Left behind |
  | --- | --- | --- | --- |
  | steps 1 to 3 (including `getrandom`) | `NotReplaced(that error)` | untouched | nothing |
  | step 4 or 5 | `NotReplaced(that error)`; the temporary file is removed with `unlinkat` | untouched | the temporary file, if the `unlinkat` also failed; the result keeps the first error |
  | step 6 | `ReplacedNotDurable(that error)` | already the new file; whether a crash would keep it is unknown | nothing |
  | step 7, after step 6 succeeded | success: the commit and its durability are already established, and Linux releases the descriptor even when `close` reports an error | the new file | nothing |
  | step 7, after an earlier failure | the earlier result, unchanged | as that row says | as that row says |
  | a crash between steps 3 and 5 | | untouched | a stray `.nl-tmp-*` file |
  | a crash between steps 5 and 6 | | the old or the new file, after recovery | possibly a stray `.nl-tmp-*` file |

  **No automatic cleanup of stray temporary files.** Neither a name nor a process id proves that a file belongs to a dead writer: ids are reused, and the same id means different processes in different PID namespaces. So the core library never deletes a file it didn't create in the same call. The API documentation names the `.nl-tmp-*` pattern, so a person or a tool can remove strays. The new file gets fresh permissions (`0666` less the umask), not the old file's; the documentation says so too.

  **Tests:** the test-build fault plan (see "Tests for E1c") fails each system call of the atomic write in turn (`openat2`, `getrandom`, `openat`, `write`, `fsync`, `close`, `renameat2`, `fsync` of the directory, `close` of the directory, `unlinkat`). Each case checks the result variant, the target's bytes, what's left in the directory, and that no descriptor stays open.
- **The streaming file writer** (proposed API) is for output too big to build in one buffer:

  ```
  var buffer: Bytes max 1048576 = Bytes.empty()           // a reserve-ahead region on the job's data stack
  var ir = env.fs.writer("out.ll", buffer, atomic)?        // opens once; borrows `buffer`
  ir.write(b"; nlc-link-ir 2\n")?                          // appends; writes out when the buffer is full
  emit_functions(ir)?                                      // a `write FileWriter` parameter
  ir.close()?                                              // the commit: writes out, then the atomic steps
  ```

  - **What the writer holds:** the descriptor, the buffer's offset, length and capacity, the atomic flag with the directory descriptor and temporary name, a failed state, and a link in the job's list of open writers (below). It's a value in the job's region. There's no heap, and no copy beyond the one into the buffer.
  - **`write(piece)`** copies into the buffer. When the piece doesn't fit, it first writes out the buffer, then either copies the piece in or, if the piece alone is at least the buffer's size, writes it straight from where it lies.
  - **A writer is a unique resource.** It can't be copied: `let other = ir` is refused. It can't be stored in a struct or a collection, or returned. It moves only with `take` (DESIGN.md:415), within its buffer's scope. A function uses it only through a `write FileWriter` parameter, which borrows it exclusively for the call.
  - **The buffer is borrowed exclusively.** From `writer(...)` until the writer ends, the buffer can't be read, written or passed anywhere else, and the checker refuses a buffer whose scope ends before the writer's. When the writer ends, the buffer is usable again, with length 0.
  - **Two ways to end, kept apart:**
    - **`close()` is the commit.** It writes out what's left, closes the descriptor, and for an atomic writer runs steps 4 to 7 of the atomic write. It consumes the writer. A plain writer returns `Result<(), IoError>`; an atomic one returns `Result<(), AtomicWriteError>`.
    - **`abort()` never publishes.** It closes the descriptor; an atomic writer also removes its temporary file, leaving the target untouched. A plain writer leaves the partial file, as a plain write that fails part-way does. It consumes the writer and returns nothing; nothing it does can publish.
  - **Every exit is covered.** Reaching the normal end of the writer's scope without `close` or `abort` is a build error, because a commit must be explicit. Every other exit aborts: an early `return`, a `?` that propagates, a `break` or `continue` out of the scope, a failure, or cancellation. The compiler inserts the `abort` on each early-exit edge. For a job failure or cancellation, the job-failure steps (DESIGN.md, "What failing a job does") abort the job's open writers after its pending I/O is cancelled and before its stack is reset.
  - **Errors:** the first failure is returned by the call that met it, and the writer enters the failed state. Later writes return the same `IoError` without writing. `close` on a failed writer aborts instead of committing, and returns the error (`NotReplaced` for an atomic writer).
  - **Cleanup without a heap:** each open writer's record lives in its own region on the data stack. Opening a writer links the record into a per-job list whose head is in the job context, with offsets as links; `close` and `abort` unlink it. The job-failure path walks the list. Nothing is allocated, and there's no fixed table to run out of.
  - **Proved before use:** control-flow fixtures (each exit kind, nested scopes, loops, `?` inside a callee that takes `write FileWriter`) and lifetime fixtures (a copy, a store, a use of the borrowed buffer, a buffer with a shorter scope, a second `close`, each refused at build time), plus runtime fixtures with the fault plan, must pass before the self-hosted compiler switches its own output to the writer.
  - **How the self-hosted compiler uses it:** today the compiler builds the whole module in one `Bytes` builder, sized by a derived bound, and writes it once, because `Fs.write` truncates on every call (E1 spec:70, 296-301). With an atomic streaming writer and a 1 MiB buffer, the compiler streams each section as it's emitted. Peak memory drops from the whole IR to the buffer. A build that fails during emission aborts, so the temporary file is removed and the target is never touched, which keeps E1's "nothing written on rejection" rule. The report compares peak RSS and wall time against the single-buffer write.

## UTF-8 in the core library

DESIGN.md:876: `Text` is valid UTF-8 by construction, checked only where bytes become `Text`, and trusted everywhere else. The core library keeps the two kinds of routine apart, in separate files, so a trusting helper can't be used at a boundary by mistake.

- **Boundary validators** (`core/utf8_validate.nl`) decode fully, with the C runtime's rules (1222-1271): no overlong forms, no surrogates, nothing above U+10FFFF, and a `valid_up_to` result. They're used only by `Bytes`-to-`Text` conversion, `validate_utf8`, file reads into `Text`, and foreign values arriving as `Text`. An ASCII fast path checks 8 bytes at a time (no byte has its top bit set), then falls back to decoding. Its speed is compared with the C runtime's `nl_utf8_validate` on the self-hosted parser's inputs.
- **Trusting helpers** (`core/utf8_trusted.nl`) assume validity and check nothing:
  - Counting code points counts the bytes that aren't continuation bytes (`10xxxxxx`).
  - The byte offset of code point `k` skips `k` lead bytes.
  - Building `Text` from pieces sums the pieces' code-point counts.
  - Printing, comparing, copying and writing `Text` treat it as bytes.

  This replaces the re-validation PLAN.md's small fix names (`nl_utf8_count` in `emit_text_to_data`, `nl_utf8_offset` for slices). The self-hosted compiler never adds it.
- **Upper-case mapping** keeps validity by construction: it decodes trusted input and encodes only valid code points. The Unicode table (`runtime/nl_unicode_upper.h` today) is generated into a core file of constant data, once the core dialect has constant arrays (E3 or later).
- **A test-build-only assertion:** in test builds (`; nlc.build test`), every core routine that constructs a `Text` re-validates the result with the boundary validator before returning it. Invalid bytes fail with a new kind, 22, `invalid Text constructed (compiler or core library bug)`, which exits 70 in a test child. Program builds never run it. The suite then catches any path that produces invalid `Text`, and the trusting helpers stay trusting in real programs. The C runtime gets the same assertion and kind in the same task, so the two runtimes stay identical.

## The stack is pinned while the kernel holds an address into it

DESIGN.md:161 and 385-391. The rules as the core library applies them:

- **Only the core library turns offsets into addresses.** Generated code passes offsets. `sys.stack_addr(ctx, offset)` derives `base + offset` immediately before the system call that uses it, and the result isn't kept. That's the rule DESIGN.md:386 sets for generated code, applied to core code.
- **Where the address may appear is a syntax rule.** `sys.Addr` is one type, so the checker can't tell a stack-derived address from one made by `sys.state()` or `sys.lit`. So `sys.stack_addr(ctx, offset)` is accepted only as a direct argument of a `sys.*` system-call operation (`sys.read(fd, sys.stack_addr(ctx, at), n)`). It can't be bound to a `let` or `var`, returned, stored or passed to any other function. The checker tests this in one place, with no flow analysis. A separate `sys.StackAddr` type was considered and rejected: it needs the same restriction on every use anyway.
- **When the address is formed is a lowering rule.** The syntax rule alone isn't enough: arguments are evaluated left to right (E1 spec), so in `sys.write(fd, sys.stack_addr(ctx, at), compute_count())` the third argument could grow the stack after the second was formed. So the compiler lowers every `sys.*` operation in two phases:
  1. **Evaluate.** Every argument expression is evaluated in its usual left-to-right place, into an offset or a scalar. For `sys.stack_addr(ctx, offset)` that means the `offset` expression only; no address is formed yet.
  2. **Derive, then operate.** After the last argument, the compiler loads the base from the context, adds each offset, and issues the system call at once, with no call in between.

  Forming an address has no side effect, so moving it after the other arguments changes no observable order. The same two phases apply to `sys.stack_load8(ctx, offset)` and `sys.stack_store8(ctx, offset, value)`: the offset and the value are evaluated first, then the base is loaded and the access made. Core code uses these two for data-stack bytes it reads or writes itself (UTF-8 validation in place, from E3). In a loop with no growth point, LLVM hoists the base load, so they cost what generated code's `base + offset` costs.
- **A test forces a relocation during argument evaluation.** In a test build, a core `test` block calls a system-call operation whose later argument calls a function that grows the stack by a forced move (a test hook makes the grow routine always move). The test checks that the kernel saw the new range: the bytes written come from the moved stack, and the old range, unmapped by the move, was never touched.
- **A blocking system call can't overlap growth.** The stack belongs to one job, and only that job's thread grows it, by calling the core library's grow routine. While the thread is inside `read` or `write`, the job isn't running, so nothing can move the stack. Parallel chunks reading a parent's stack can't grow it either, because the parent waits at the join (DESIGN.md:389).
- **Foreign calls** get addresses the same way, formed after all other arguments, and pin the stack until they return (DESIGN.md:387). The pin is a count in the context, raised before the call and lowered after it.
- **Foreign callbacks that receive buffer addresses keep the stack pinned.** When foreign code that holds a buffer address calls back into next-lang before returning, the stack stays pinned for the whole callback. The grow routine checks the pin count first: while it's above zero, growth is refused, and the job fails with a new failure kind, `data stack is pinned by a foreign call`, through the job-failure steps. To make that rare, the compiler grows the stack ahead of such a foreign call by the callbacks' computed bound, when it's known, so growth that a callback would need happens before the pin. The binding generator marks bindings that both take buffers and accept callbacks, and the audit report lists them.
- **Asynchronous operations stay unavailable** until the scheduler milestone has decided how they pin, including what happens on cancellation. The reason: with asynchronous I/O (the scheduler's suspended jobs, for example with `io_uring`), the kernel keeps the address after the call returns and writes later, by which time the job may have run and grown its stack. `mremap` would have moved the pages, so the kernel would write to the old range. No `sys` operation that leaves an address with the kernel after it returns is added before then. The milestone chooses between two options:
  - **A. Pin until completion.** The context counts I/O operations in flight. The grow routine waits for that count to reach zero (the job suspends until its own I/O completes) before it moves the stack. The cost is latency, only for jobs that grow with I/O in flight. Reads still land straight in their destination.
  - **B. A separate pinned I/O arena** per worker, never moved, registered with the kernel once (`io_uring` registered buffers suit this). The kernel reads into the arena, and the job copies into its destination when it resumes. The cost is one copy per operation and a fixed arena budget.

  Either option must also say how cancellation cleans up: a cancelled job's operations must be cancelled and confirmed finished before its stack is reset or returned to the pool (DESIGN.md, "What failing a job does", step 2), and for B before its arena slots are reused. Measure both under the scheduler milestone, on a file-heavy and a network-heavy load: throughput, per-operation latency, and how often a job grows with I/O in flight. The expectation is A for files (rare growth, and no copy) and B for sockets (many small operations in flight). The decision belongs to the measurement.

## Other targets

- **Linux arm64:**
  - **Syscalls:** `svc #0`, the generic syscall table above, `openat` and `renameat2` in place of the missing calls.
  - **`_start`:** `mov x29, #0; mov x30, #0; mov x0, sp; bl nl_core_start; brk #0`. `sp` is 16-byte aligned at entry.
  - **Bulk copies:** pairs of 8-byte or 16-byte loads and stores; there's no `rep movsb`, and the Armv8.8 copy instructions aren't baseline.
  - **Unchanged:** `statx`, `sigaction` and the core files.
- **macOS:**
  - **No stable syscall interface:** raw system calls aren't a stable interface, and static executables aren't supported. So every program uses the libc start-up variant. dyld starts the program, libSystem's start-up calls `main`, and the core library's platform layer (`core/macos/`) calls libSystem's `write`, `mmap`, `open` and others through foreign bindings (DESIGN.md:157).
  - **Libcalls:** the memory functions are the core library's own internal symbols, as on Linux. Large frames call `___chkstk_darwin`, which comes from libSystem, the operating system's required library.
  - **Moving a stack:** there is no `mremap`. It moves by `mach_vm_remap` through libSystem, or by copying committed pages; measure both.
  - **Other details:** symbols get a leading underscore, and `isatty` and `fstat` come from libSystem.
- **Windows:**
  - **No C library needed:** the platform layer (`core/windows/`) calls kernel32 (`GetStdHandle`, `WriteFile`, `VirtualAlloc`, `ExitProcess`, `GetCommandLineW`) or ntdll directly.
  - **Entry:** the entry is the core library's own (`-nostdlib -Wl,/entry:nl_core_start_windows -lkernel32`). It gets no initial-stack `argc`/`argv`, so it parses the UTF-16 command line itself.
  - **Libcalls:** LLVM emits `__chkstk` calls for frames over 4 KiB, so the core library provides `__chkstk` as compiler-emitted asm. The memory functions are its own internal symbols, as on Linux. Floats will need the `_fltused` symbol.
  - **Terminals and pipes:** `GetFileType` and `GetConsoleMode` stand in for `isatty`. A broken pipe is `ERROR_NO_DATA` or `ERROR_BROKEN_PIPE`, mapped to the same failure, since there's no SIGPIPE.
  - **The data stack:** `MEM_RESERVE` with 64 KB commits, and moves that copy only committed chunks (PLAN.md, Windows support).

## Risks and open questions

Each has a recommendation.

1. **Bootstrapping: the core library outgrows the dialect.** E1c's core is small, but E3 needs `Bytes`, builders and formatting of `Text`, and the core library must be written in whatever the self-hosted compiler accepts by then. *Recommendation:* adopt the core dialect (decision 1), with its forms listed exactly. Widen it only by features that are also user features (compared with Rust), plus the fixed `sys` set. Retire each bootstrap mechanism in the task named in its row of "Retiring the bootstrap mechanisms", rewrite each core file upward when its feature lands, and keep option (b), compiler-emitted IR and assembly, only for `_start`, the syscall helpers, the bulk-copy asm and the stack-switch stubs.
2. **Embedding the core source.** A generated, checked-in file can go stale, and long byte literals may hit lexer limits. *Recommendation:* use `scripts/embed-core.sh` with a `cargo test` staleness check, the core unit's own input budget, and the hash in every IR header. Add a real `embed` feature to the language when the compiler first needs to run outside the repository; that's a design question of its own.
3. **The hook ABI keeps the C runtime's shape.** Hooks take NUL-terminated `ptr` strings, `nl_print_int` takes no context, and the file registry is a fixed table. *Recommendation:* keep it only while the third comparison leg needs it, and replace it with a context-passing ABI and compiler-emitted static tables (files, entries) before the first region-using core function (E3), and in any case before jobs or concurrent output. The replacement checks are in "Retiring the hook ABI". The reference comparison against Rust nlc continues until Rust nlc freezes, independent of this.
4. **Unexpected libcalls.** LLVM may emit libcalls beyond the five memory functions: `fmod` for `frem` once floats arrive, `__udivti3` for 128-bit division, and newer LLVMs recognise more idioms (`strlen`). *Recommendation:* the pinned clang 18.1.3; `-nostdlib`, so a freestanding link fails loudly; the `nm -u` tests on the freestanding binary and on the libc variant's module object; and the post-link call-graph test for the memory functions. Each new libcall gets a core implementation, as an internal symbol, before the feature that triggers it lands.
5. **The libc variant's mixed output.** A C library's `printf` buffers in libc's stdout while the core library buffers its own, so their output can interleave out of order. *Recommendation:* the core library flushes its buffers before every foreign call whose binding declares the `out` effect, and a binding that declares `out` flushes its own library's output before it returns (see "The libc start-up variant"). Bindings that write to stdout must declare it, and the audit report lists them.
6. **Static non-PIE executables** load at a fixed address, so the program image gets no address randomisation (stacks and mappings still do). *Recommendation:* non-PIE for E1c. A static-PIE build needs `_start` to apply the image's relative relocations before any other code runs, about 30 lines of core code; it's a follow-up task after the scheduler, with a test that runs the same binary twice and checks the addresses differ.
7. **Edge cases where reproducing C exactly makes little sense** (a stale `errno` on a zero-byte write, ids past the registry's capacity, the test-build `mkdtemp` root). *Recommendation:* where a difference is unobservable in E1, list it in the report. Where it could be observed later, fix the C runtime to the cleaner rule in the same task, since it's still the reference and may take fixes.
8. **Kernel features.** `openat2` needs Linux 5.6, and some container seccomp profiles refuse it, which already affects the C runtime. *Recommendation:* the stated baseline (Linux 5.6, see "The list"); refusals keep their current `IoError` values (`Other(38)`, `NoPermission`); the failing system call is named where the error is reported, the same way in both runtimes (see "Paths and errors"). No fallback to unchecked `openat`, which would weaken the beneath-the-root guarantee.
9. **The clock without libc.** `clock_gettime` as a real system call costs about 100 ns, where glibc's vDSO path (a kernel-provided function mapped into the process) costs about 20 ns. *Recommendation:* use the system call first. When the clock capability lands and a measurement shows it matters, find `__vdso_clock_gettime` through `auxv`'s `AT_SYSINFO_EHDR` (a small ELF symbol lookup in the core library), using the `auxv` address recorded at start-up in freestanding builds, and `/proc/self/auxv` in the libc variant.
10. **Threads.** With workers there will be several threads, and the output buffers become shared state. Starting threads without libc means raw `clone` and `futex`. *Recommendation:* out of E1c. The scheduler milestone designs raw-`clone` workers in the core library, with per-worker contexts reached through the context pointer (no thread-locals), and a single-writer output path.
11. **Asynchronous I/O and pinning:** asynchronous operations stay unavailable until then; see the two options in "The stack is pinned while the kernel holds an address into it". *Recommendation:* the scheduler milestone measures both, and settles cancellation cleanup, before choosing.
12. **The native stack's default budget** changes from "RLIMIT_STACK minus 80 KiB" to a fixed 8 MiB minus 80 KiB when the core library maps its own stacks. *Recommendation:* change the C runtime in the same task, so the reference and the subject agree.
13. **Debugging freestanding binaries:** there's no libc backtrace, and `gdb` needs the `_start` CFI to stop unwinding cleanly. *Recommendation:* the CFI lines shown in `_start` and in the stack-switch stubs, and DWARF line tables from the compiler as a later task.
14. **The cost of the core library per build.** It's parsed, checked and optimised with every program. *Recommendation:* the E1c report measures the extra build time at -O1 and -O3. If it passes 50 ms, try a cached core object, measured against the loss of cross-module inlining.
