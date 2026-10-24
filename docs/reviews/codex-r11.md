# Round 11: `docs/DESIGN.md`

Reviewed after the Round 10 reply. This review is limited to Round 10's accepted initialization rules, `Ascii`, and full static allocation, with issues that affect steps 1–2 first.

## 1. `Ascii` cannot safely widen for writes

**Types / Text, ASCII and bytes; Memory / References, No overlapping arguments, and Copies and moves of growing values.** The design says an `Ascii` value is valid `Text` and may be passed where `Text` is expected at no cost. That is safe for a read-only parameter, but parameters can also be `write` or `grow`. Such a function can store a non-ASCII character, breaking the caller's `Ascii` guarantee. It may also need up to four UTF-8 bytes per character, while `Ascii max N` owns exactly N bytes. A no-copy call could therefore both invalidate the type and exceed its storage.

Limit the no-cost conversion to read-only parameters. A writable or growing call must either use an `Ascii` parameter, prove that every produced value is ASCII and fits the caller's byte bound, or explicitly convert/copy into suitably sized `Text` storage. **Acceptance:** an `Ascii` argument is read by a `Text` helper without a copy; a helper that writes a non-ASCII value or grows past the `Ascii` byte bound is rejected (or uses an explicit checked conversion); an ASCII-only update within the bound succeeds.

## 2. Initialization needs a private construction phase

**Memory / Static allocation; Correctness tools / Invariants; Types / How they are checked.** Defaults and `init` are said to receive the same invariant checks as any write, but `init` constructs a root field by field. For `start: Int 1..100`, `end: Int 1..100`, and `invariant start <= end`, an initializer assigning `start = 10` before `end = 20` has an incomplete root; it cannot yet check the whole-root invariant, and the design does not say whether it may read `end` before assignment.

Specify that initialization builds an unpublished root: a read of an uninitialized field is a build error, and every required field and fixed-array element must be assigned. Check field refinements as values are assigned, then check whole-root invariants on the completed root before publishing it or scheduling jobs. Defaults and restored saves use the same completed-root validation. Ordinary writes after publication retain the every-write invariant rule. **Acceptance:** assigning `start = 10` then `end = 20` succeeds; reading `end` before assignment is a build error; a completed root with `start > end` or an invalid configuration fails startup before any job runs.

## 3. Startup allocation is not an OS guarantee of permanent backing

**Memory / Static allocation.** Keeping all global state in a fixed allocation claimed at startup preserves Ben's no-growth decision, but “reserved and committed, so the operating system has promised the memory” and “can't run out of memory” overstate what the process can rely on. Linux's overcommit policy can allow commitments beyond available backing, and touching pages with `prefault` does not keep them resident; Windows documents `VirtualLock` for pages that must remain resident and avoid later page faults. See the [Linux overcommit documentation](https://www.kernel.org/doc/html/latest/mm/overcommit-accounting.html) and [Windows `VirtualLock` documentation](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtuallock).

Keep full startup allocation and no later global allocation, but distinguish that language-level capacity guarantee from OS backing. Define a supported startup policy for each target: if hard backing or residency is required, acquire it at startup and fail before jobs run when the OS refuses; describe `prefault` as moving first-touch faults to startup unless pages are also locked. **Acceptance:** refusing the requested startup backing/lock prevents job scheduling, and the reported memory separates the fixed state claim from any OS-enforced residency.

## Later

- SQLite's fixed heap needs a memory allocator mode that supports it (`MEMSYS3` or `MEMSYS5`), and startup must check that `sqlite3_config(SQLITE_CONFIG_HEAP, ...)` succeeds ([SQLite configuration](https://sqlite.org/c3ref/c_config_covering_index_scan.html)).

## Questions

None.
