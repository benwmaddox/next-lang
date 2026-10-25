# Sol: consistency audit, round 1

**Verdict: the documents still carry replaced contracts alongside the current decisions.** The largest conflicts concern stack reservation and movement, H1's appended corrections, the offset milestone's acceptance requirements, and completed work still presented as future work.

Read-only audit on 2026-10-25 of DESIGN, PLAN, the unfinished O1/H1 specifications and remaining task specifications, completion reports and Claude's task reviews, with source inspection in `compiler/`, `runtime/` and `selfhost/`. No build or test was run. O1 was being edited during the audit; implementation references below describe the observed working tree, not a claim that O1 is finished. Historical reports are evidence of decisions and completion, not new implementation instructions.

Findings are ordered by importance. Each proposed rewrite is intended to replace the affected text, not become another overriding appendix.

1. **P1 — The old rule that a computed bound sizes the data-stack reservation remains in the design.**

   **Locations:** `docs/DESIGN.md:194`, `:373`, `:444`, `:446`; compare `:381–387` and the Decided entry at `:890`.

   The Budget paragraph says the reservation is sized from the entry point's worst case. The loop analysis paragraph repeats that rule and gives an unbounded entry the default reservation. Those are T17's old runtime policy, whereas the adopted policy starts at 256 KiB or recent demand, grows to a cap, and uses the computed bound to provision storage only under `strict_stack`. The summary's “reserved per entry point” and the advice to rely on a “default reservation” preserve the same ambiguity.

   **Proposed rewrite:** “The compiler computes each entry point's conservative data-stack bound for inspection, warnings, admission estimates and `stack_peak`; ordinary stacks start small and grow to their configured cap, including when the bound is unknown. Only `strict_stack` provisions the full computed bound at startup.”

2. **P1 — Collection and builder addresses are still promised never to move.**

   **Locations:** `docs/DESIGN.md:259`, `:292`, `:311`, `:371`; compare `:374–378`, `:382`, `:889`.

   “A collection's arrays never move,” “nothing moves, and positions stay valid,” and the argument that adding cannot invalidate addresses because arrays are reserved at capacity are incompatible with relocation of the containing job stack. The valid guarantee is that element positions relative to their collection, and offsets relative to the stack, remain stable. A later allocation or a growth-capable call can invalidate an actual address even when a collection does not change shape. This matters directly to O3/O4's references and LLVM promises.

   **Proposed rewrite:** “Collection storage and reserve-ahead regions keep their relative layout; growth does not compact elements or move them between regions, but relocation may change every absolute address in a job stack. Generated references retain offsets and derive addresses again after growth-capable calls; global storage remains stationary.”

3. **P1 — H1 specifies two incompatible binary transports.**

   **Locations:** `docs/tasks/H1-selfhost-frontend.md:10` versus `:27`, `:37`.

   The original requirement is `parse <package> --binary <out-file>` with the child streaming into that file. Binding correction 7 instead requires `parse <package> --binary` on stdout, captured by the parent, because the existing `fs.write` truncates on every invocation. An implementer following the main body would build the rejected transport. The correction is supported by `docs/reviews/sol-H1-r1.md:15`.

   **Proposed rewrite:** “`parse <package> --binary` streams the binary tree to stdout; nlc captures it in a unique temporary file or pipe and consumes it only after successful child completion. Define child cwd, relative package mapping, symlink handling, and syntax/tool-failure forwarding here.” Delete the superseded file-argument instruction and integrate correction 7 into this section.

4. **P1 — H1's primary cache contract is still the invalidated version-only contract.**

   **Locations:** `docs/tasks/H1-selfhost-frontend.md:15` versus `:35–36`; `docs/PLAN.md:64`.

   H1 still tells the implementer to cache by selfhost source hash and compiler version. Its own binding correction requires actual compiler build identity, runtime, manifest, effective target/optimization/toolchain and wire version, plus concurrency and atomic publication. PLAN reduces this to “source hash” again. The crate version does not identify an emitter/runtime build (`docs/reviews/sol-H1-r1.md:13`).

   **Proposed rewrite:** “Build selfhost through an internal Rust-only path and cache the executable by sorted source paths/content, manifest, actual compiler build identity, runtime content, effective target and code-generation settings, toolchain and wire version. Lock concurrent cold builds and publish successful artifacts atomically.” Replace the shorter contracts in both H1 and PLAN, then place the invalidation and corruption tests in Acceptance.

5. **P1 — H1's main format and equality requirements still contradict its binding review corrections.**

   **Locations:** `docs/tasks/H1-selfhost-frontend.md:9–11`, `:21–23` versus `:31–34`, `:38`.

   The body says the parser “already holds this data” and requires an AST from every fixture, including syntax failures. The corrections explain that several values/roles/spans are currently discarded or reconstructed only for printing, require every AST field to be mapped explicitly, compare trees only for syntactically valid packages, and require diagnostics/status for syntax failures. The simple reader-validation sentence likewise leaves the old, weaker acceptance contract alongside the structural validation contract.

   **Proposed rewrite:** “Document a lossless AST-field-to-wire mapping, adding parser metadata where necessary, and validate bounded section arithmetic, tree structure, tags, ownership and spans before AST allocation. Compare every ordered AST field and file identity for syntactically valid inputs, including checker-invalid inputs, and compare the first diagnostic/status for syntax failures across repository, generated, mutation and boundary cases.” Integrate corrections 1–4 and 8 into the relevant sections and delete the override heading at line 27.

6. **P1 — PLAN requires full offset-suite coverage before the tasks that provide that coverage.**

   **Locations:** `docs/PLAN.md:37` (“each keeping the whole suite passing in both modes”) versus `:38`; `docs/tasks/O1-offset-runtime-and-inline-alloc.md:10`, `:19`.

   O1 explicitly permits everything outside its vertical slice to fail closed in offset mode and requires the whole suite in pointer mode plus the verified offset slice. O2–O6 supply the missing paths. The full-both-modes requirement would make O1 impossible under its specified scope; PLAN's very next entry also explicitly allows fail-closed paths assigned to subsequent O-tasks.

   **Proposed rewrite:** “O1–O5 preserve the full pointer-mode suite and expand a poison-verified offset corpus; unsupported offset paths fail closed and are assigned to the next applicable O-task. O6 establishes full selfhost/comparison coverage, and O7 switches defaults and deletes pointer mode after all required offset coverage passes.”

7. **P1 — H1 has three different default-switch/reference/fallback endpoints.**

   **Locations:** `docs/PLAN.md:38`, `:59`, `:63–64`; `docs/tasks/H1-selfhost-frontend.md:15`, `:25`, `:39`.

   PLAN says H1 makes selfhost the default and Rust remains *only* a comparison reference, but the hybrid-track entry retains Rust as “reference and fallback.” H1 explicitly leaves Rust the default and supplies a recommendation; switching is a separate decision. These are materially different production and maintenance contracts. The existing dual front ends are intentional, but their endpoint is not consistently stated.

   **Proposed rewrite:** “H1 adds and validates the selectable selfhost front end while Rust remains the default; a separately recorded decision switches production parsing after H1's report. After that switch, Rust parsing remains the explicitly selected comparison reference, with no automatic production fallback; retirement of the rest of the Rust compiler is a separate S3-era decision.” Apply this consistently to PLAN and H1.

8. **P1 — The offset milestone is said to deliver scheduler policies it never schedules.**

   **Locations:** `docs/DESIGN.md:387–391`; `docs/PLAN.md:31`, `:37`; `docs/tasks/T28-stack-cap.md:5`, `:10–11`.

   DESIGN says O1–O8 convert the compiler to “the design above,” which includes pooling, per-entry histories, trimming, clear-between-jobs, admission and strict preprovisioning. PLAN assigns O1–O8 addressing, I/O, selfhost, a growth cap and optional narrower offsets; its scheduler follow-up does not explicitly assign most of those policies. T28 mentions separate strict/Windows work and rejection of unsupported settings, but T28 is cancelled. The current manifest reader silently ignores unfamiliar keys (`compiler/src/driver.rs:1827–1828`), so there is no existing rejection policy to inherit automatically.

   **Proposed rewrite:** “O1–O7 deliver movable offset addressing, complete supported paths, default switching and the growth cap; pooling/history/trimming/clearing/admission belong to the scheduler milestone, with Windows commitment and strict-stack provisioning assigned separate tasks. Until implemented, the corresponding manifest settings must be rejected explicitly.” Narrow the implementation-status sentence and list these remaining tasks in PLAN.

9. **P1 — Completed tasks remain actionable backlog items, sometimes with their pre-fix bug descriptions.**

   **Locations and completion evidence:**

   | PLAN location | Text still presented as future/current problem | Completion evidence |
   | --- | --- | --- |
   | `docs/PLAN.md:33` | Touch-only-live task; “Today” a one-element list touches 48 MB | `docs/tasks/T23-report.md:5–9,24–35`; `docs/reviews/claude-T23-review.md:3–9` |
   | `docs/PLAN.md:34` | Design a chosen tool exit status | `docs/tasks/T24-report.md:5`; `docs/reviews/claude-T24-review.md:5` |
   | `docs/PLAN.md:35` | Fix recursive `else if` and the 2,048/1,000 mismatch | `docs/tasks/T22-report.md:5–9`; `docs/reviews/claude-T22-review.md:5` |
   | `docs/PLAN.md:36` | T32 operator dispatch and number output | `docs/tasks/T32-report.md:3–7`; `docs/reviews/claude-T32-review.md:3–7` |
   | `docs/PLAN.md:39` | T30 locality and in-place updates; dumper copy-down sites | `docs/tasks/T30-report.md:3–15,41`; `docs/reviews/claude-T27-review.md:7` says the five empty-buffer sites were already removed by T27 |
   | `docs/PLAN.md:41` | Crossed Option/Result diagnostic, hex byte escape, EPIPE panic | `docs/tasks/T24-report.md:7–9`; `docs/reviews/claude-T24-review.md:5` |
   | `docs/PLAN.md:43` | User `-> never`, before S1a-2 | `docs/tasks/T26-report.md:3–7,16`; `docs/reviews/claude-T26-review.md:5` |
   | `docs/PLAN.md:46` | Array/list literals; “today arrays start from fill” | `docs/tasks/T24-report.md:6`; `docs/reviews/claude-T24-review.md:5` |

   Reissuing these items risks duplicate work or undoing the approved implementations. T30's current proof conditions are also more precise than “only appends or rewrites.”

   **Proposed rewrite:** Replace these entries with a compact completed-task ledger linking each report/review, and delete their prospective acceptance instructions and obsolete “today” claims. Retain genuinely unfinished items such as buffering, byte matches, floating point and nested-layout flattening in the active backlog.

10. **P2 — The documented text layout omits T29 and describes T31's superseded handle.**

   **Locations:** `docs/DESIGN.md:157`, `:218–221`, `:727`; compare `docs/tasks/T29-report.md:5–9`, `docs/tasks/T31-report.md:5–7,62–77`, `docs/reviews/claude-T31-review.md:5–12`.

   DESIGN describes collection fields as `{class, slot, length}`; T31's final format stores a class plus a byte offset from the collection base, with lengths and code-point counts separately. It also describes class payload as per-class arrays without recording the final flat byte backing that replaced first-class huge LLVM arrays. The blanket performance summary (“small text inline, larger text in size classes”) overlooks T29's ordinary stored values, which are inline at *every* bound; class-backed storage applies to collection lanes. T31's Ascii map/set keys remain inline copies too. Size classes themselves were **not** removed by T29/T31.

   **Proposed rewrite:** “Ordinary stored Ascii/Text/Bytes values, including struct and sum payloads, hold lengths/counts plus bounded inline bytes; transient read descriptors borrow those bytes. Collection text lanes are inline up to 64 bytes and otherwise hold a class/collection-relative-byte-offset handle into flat class backing, while Ascii map/set keys remain inline.” Use this scope in Layout and Performance; keep the class allocation/reuse policy.

11. **P2 — The collection reservation formula excludes bookkeeping now explicitly required by the implementation.**

   **Location:** `docs/DESIGN.md:259`; compare `compiler/src/emit.rs:3734–3745`, `compiler/src/checker.rs:2495–2526` and `docs/tasks/T31-report.md:18`.

   The geometric sum is a bound on payload-slot bytes, not on all memory for a variable-size field. Each class also has two counters and a capacity-sized free-slot stack, and lanes have handles/lengths/counts. For capacity 1 and a 4,096-byte maximum, class payloads total 8,064 bytes and six classes' bookkeeping adds 144 bytes: already 8,208, above the asserted field bound of less than 8,192, even before lane metadata.

   **Proposed rewrite:** “Class payload bytes total less than capacity × twice the largest class, but total storage additionally counts lane metadata, each class's counters and free-slot indexes, alignment, collection headers and every enclosing capacity. Use the checked complete layout for bounds and inspection, not the payload-only geometric estimate.”

12. **P2 — T30's implemented assignment and placement rules are absent from the corresponding design contract.**

   **Locations:** `docs/DESIGN.md:307`, `:371`, `:441`; `docs/PLAN.md:39`; compare `docs/tasks/T30-report.md:7–15`, `compiler/src/emit.rs:4671`, `:4675–4688`.

   The design says any reassignment other than `s = s + piece` builds a temporary and copies down, and describes later locals going above a builder's region. T30 now also forwards eligible `buffer = f(buffer)` assignments in place and reserves direct block locals in stable size groups at block entry, small regions first. This is an approved change to the rules used by both inspection and emission, not merely an unimplemented optimization suggestion.

   **Proposed rewrite:** “A direct reassignment call updates in place when it has one matching write/grow parameter rooted at the assignment local, returns that parameter on every path and has no conflicting aliased argument; otherwise scratch/copy-down remains bounded and is reported with a rewrite suggestion. Direct block regions are planned at block entry, up to 64 KiB first and larger reserve-ahead regions afterward, retaining scope cleanup.”

13. **P2 — Stack locking is forbidden in one section and recommended in another.**

   **Locations:** `docs/DESIGN.md:267` (“Job stacks are never locked”) versus `:387` and Decided `:890` (`strict_stack` combined with `prefault`/`locked`).

   An entry point cannot follow the strict-stack latency policy while satisfying the unconditional prohibition. The distinction is ordinary growable stacks versus strict stacks, not globals versus every job stack.

   **Proposed rewrite:** “Ordinary growable job stacks commit as used and are not locked; a strict entry point may additionally request prefaulting and locking of its preprovisioned stacks. Failure to obtain the requested backing or lock refuses startup.”

14. **P2 — “Demand” changes from two measurements into an undefined scalar in the trimming rule.**

   **Locations:** `docs/DESIGN.md:385`, `:388–390`, `:890`; compare reserve-ahead holes at `:371–373` and T23's sparse-lane measurements in `docs/tasks/T23-report.md:24–35`.

   Demand is defined as both the highest allocated offset and the pages written; trimming then compares “demand” to committed bytes and multiplies it by 1.25 without identifying which component it uses. A large sparse region can have a high allocated offset and few written pages. These are also used differently for clearing, commitment and shrinking address ranges, so one scalar cannot safely stand for them all. The Decided entry repeats the shorthand.

   **Proposed rewrite:** “Record virtual allocation high-water and per-job written-page demand separately, excluding inherited commitment. Specify commitment trimming from recent written-page demand and range shrinking/clear coverage from the relevant address high-water, with an explicit rule for sparse ranges; reports and the Decided summary must name the measurement used.”

15. **P2 — The refinement boundary section still teaches the replaced implicit-validation approach.**

   **Locations:** `docs/DESIGN.md:647–649`, `:859`; compare the explicit refinement contract at `:638–643`.

   The contract says unproved stores require a written cast or `fit`, never a hidden check. The later checking section instead says values enter refinements only through input/column parsing or `check`, and lists a different set of fixes. Ordinary local assignments, arguments and returns plainly also enter refined types under the preceding contract. The risk example repeats `check` as the remedy without connecting it to a proof.

   **Proposed rewrite:** “Every assignment, argument, return and field store into a refined type must be proved or use the explicit checked cast/`fit` contract; external decoding constructs checked refined values at its boundary. A preceding condition can establish a proof, while deep solver checks remain optional.”

16. **P2 — Fallible field writes are promised despite the accepted build-time assignment contract.**

   **Locations:** `docs/DESIGN.md:211`, `:680`, `:915`; compare `:626`, `:638–643`, `docs/reviews/claude-T16-review.md:13`, `docs/tasks/T16-report.md` under “Field overflow interpretation,” and `docs/tasks/T29-report.md:7–9`.

   DESIGN says writing a field beyond its maximum returns a handled Result and makes this an acceptance case. Ordinary assignment has no Result channel: T16 explicitly retained proof at build time, rejecting a wider value, while checked producer conversions/append operations have their own Result channels. Explicit casts that fail instead fail the job. Leaving these three cases conflated invites a new implicit error-returning assignment feature.

   **Proposed rewrite:** “Ordinary field assignment must satisfy the explicit refinement and maximum-size checks at build time; use a checked conversion/`fit` or a fallible capacity operation when failure is intended to be handled as a value. Updates stage fallible work before publication, so a failed checked operation leaves old fields unchanged.” Rewrite the acceptance case to test those actual forms.

17. **P2 — `discard` is still restricted to collections in DESIGN's body and Decided list.**

   **Locations:** `docs/DESIGN.md:211`, `:880`; compare `docs/tasks/T25-report.md:35–36`, `docs/reviews/claude-T25-review.md:7`.

   T25 broadened the accepted built-in capacity operations to Ascii/Text/Bytes `try_append` and `Bytes.push`; other Results, including arbitrary functions returning `Result<_, Full>`, remain rejected. Neither “a collection's expected errors” nor “a collection's expected error” describes that final rule.

   **Proposed rewrite:** “`discard` explicitly drops `Full` from designated built-in collection or Ascii/Text/Bytes capacity operations, including `try_append` and `Bytes.push`. It does not discard arbitrary Results, even when their error type is Full.”

18. **P2 — Compiler diagnostics still recommend `??` for Results, contradicting the implemented language.**

   **Locations:** `compiler/src/checker.rs:3712–3714`, `:4491–4493`, `:4539–4541`, `:5100–5102`; compare `:11800–11805`, `docs/DESIGN.md:560`, `docs/reviews/claude-T03-review.md:13`.

   The unused-Result/capacity messages suggest `??` “where supported,” but the same checker unconditionally rejects it on Result. This is stale user-facing advice, even though the implementation of `??` itself and the current DESIGN body agree. PLAN's grouped wording at `docs/PLAN.md:28` makes the distinction less clear as well.

   **Proposed rewrite:** “Handle this Result with `?` or `match`,” adding the designated `discard` remedy only for supported Full operations. Spell out in PLAN that `?.` and `??` operate on Option only; `?` propagates Option or Result under their respective return contracts.

19. **P2 — PLAN assigns integer `str_fixed` to the completed T18 task and float `str_fixed` to a second task.**

   **Locations:** `docs/PLAN.md:32`, `:40`; compare `docs/tasks/T18-report.md:28,36` and `docs/reviews/claude-T18-review.md:3–7`.

   T18's approved scope explicitly leaves `str_fixed` to floating-point work. Keeping it in the T18 list creates a false incomplete prerequisite, while recursion is still called future M3 work on the same line despite completed T19 and the S0 entry.

   **Proposed rewrite:** “T18 completed integer parsing/formatting, padding and numeric helpers; `str_fixed` belongs solely to the later floating-point task. T19 completed opt-in recursion and its current native-budget checks; separate native job stacks and switching remain scheduler work.”

20. **P2 — PLAN lacks a current, unambiguous sequence for S1a, H1 and the offset work.**

   **Locations:** `docs/PLAN.md:59–64`, `:71–82`; `docs/tasks/H1-selfhost-frontend.md:3`, `:36`; `docs/tasks/O1-offset-runtime-and-inline-alloc.md:9–10`.

   PLAN does not give completed S1a-1/S1a-2 a milestone entry, still introduces S1 only as a parallel frozen-pool parser, and labels a mixed table of completed work, generics and later parallel prerequisites “before S1.” H1 depends only on S1a and T29, while O1 deliberately cannot compile all selfhost paths in offset mode until later O-tasks. H1's cache settings also omit the effective `NLC_STACK_MODE`, which can change generated ABI within the same compiler build. This leaves task order and selfhost bootstrap mode implicit during an active migration.

   **Proposed rewrite:** “Record S0, M3, S1a-1 and S1a-2 as complete, distinguish the remaining parallel/frozen S1 validation from H1 integration, and publish a single active queue with explicit H1/O6/O7 dependencies. If H1 runs before O6, build its child through a pinned Rust/pointer bootstrap path, include effective stack mode in the cache identity, and remove that pointer exception at O7.” Split the prerequisite table into completed, H1, parallel-tool and later-checker requirements.

21. **P2 — The initial N-stack design still has live open questions and a separate future two-stack prescription.**

   **Locations:** `docs/DESIGN.md:447`, `:451–454`, `:523–524`, `:579`, `:724`; compare `:367–370`, `:398–403`.

   “How large N grows” and “constant-base copies” are orphaned questions from compiler-assigned N stacks. The fast-path contract is still expressed as caching tops for multiple growing stacks and proving aliasing between them, whereas v1 has one data stack and proves separation between regions/arguments. The nested-growing paragraph also prescribes a later second data stack even though no currently scheduled milestone adopts that extension. Ordinary references to native stacks or different jobs' stacks are valid and need not be mechanically singularized.

   **Proposed rewrite:** “Cache the one job data-stack base/top and prove disjoint regions or arguments before emitting alias metadata; native-stack accounting is separate. Nested unbounded growing values remain refused; any later representation requires a separately reviewed extension to the one-data-stack contract.” Delete the N/constant-base open questions and the unadopted two-stack prescription; update per-stack contract wording to data plus native bytes.

22. **P2 — The promised zero-copy element view and flattened layout are actually temporary implementation paths, with their end split between unrelated entries.**

   **Locations:** `docs/DESIGN.md:200`, `:215–216`, `:251`, `:309`; `docs/PLAN.md:37` (O4), `:45`; `compiler/src/emit.rs:3612–3616`, `:11474–11538`, `:11562–11581`.

   T06's nested collections still keep each inner collection inline per enclosing element, and T13 still gathers SoA struct elements into contiguous scratch for argument passing and scatters writable arguments back. The body broadly presents flattening and borrowed/no-copy reads as the available behavior without identifying these exceptions. Both deviations were approved temporarily: `docs/reviews/claude-T06-review.md:13` assigns flattening before M4, and `docs/reviews/claude-T13-review.md:11` originally associated zero-copy calls with that follow-up; PLAN now assigns the latter to O4.

   **Proposed rewrite:** “The target layout flattens nested collection lanes; the current inline-inner-collection layout ends in the layout task before M4. Current SoA element arguments may gather/scatter scratch; O4 replaces that call representation with collection offset plus element index and updates its accounting, inspection and tests.” Give the remaining layout task an identifier and state its relationship to O4 so neither copy scheme becomes a permanent second ABI.

23. **P2 — H1 acknowledges two package-loading policies without choosing its production command contract.**

   **Locations:** `compiler/src/driver.rs:223–340` versus `:401–467`; `selfhost/source.nl:285–298`, `:304–347`; `docs/tasks/H1-selfhost-frontend.md:34`.

   The parse/lex path has file, per-file/package byte, package-token and tree/work limits and source diagnostics for invalid UTF-8. The compile path separately reads/lexes/parses files, lacks the same package policies and reports UTF-8 read failure as a tool failure. H1 offers “preserve each command” or “one intentional change,” while its unchanged main body simply forwards selfhost syntax errors and requires whole-suite identity. That leaves the accepted-program and error/status policy to be chosen during implementation. Text-dump equivalence does not resolve production compile behavior.

   **Proposed rewrite:** “H1 preserves current command-specific input limits, error precedence and statuses, passing an explicit command policy to the child and using that same policy in the Rust reference path. Any intentional unification of command limits is specified and tested separately rather than chosen implicitly during AST transport.” The two reference implementations may remain, but their command policy must agree.

24. **P2 — T20's temporary byte-list I/O bridge survived its stated endpoint.**

   **Locations:** `docs/PLAN.md:61` (“using list<byte, N> until T16 brings Bytes”); `compiler/src/emit.rs:20920–20947`; `runtime/nl_runtime.c:1673`, `:1719`; compare `docs/tasks/T16-report.md` paragraphs 1–2 and `docs/tasks/T20-report.md:8`.

   Both list-backed `nl_fs_read` and string/Bytes-backed `nl_fs_read_string` remain live; the emitter explicitly selects between them, and T16 says the new forms are supported alongside T20's forms. The “until T16” removal point has passed without removal or a decision to retain a permanent overload. O5 currently inherits both interfaces unless told otherwise.

   **Proposed rewrite:** “Bytes is the standard byte-buffer I/O representation; T20's byte-list overloads are a compatibility bridge removed in O5 after fixtures migrate. Both paths use the same bounded runtime byte-buffer operation during the transition.” This is a proposed endpoint; the audit found no existing explicit removal task for this bridge.

25. **P2 — Obsolete T28 and X1 instructions are still written as active task specifications.**

   **Locations:** `docs/tasks/T28-stack-cap.md:3` versus `:5–13`; `docs/tasks/X1-offset-stack-spike.md:3–7`, `:30–32`; compare `docs/PLAN.md:37–38` and `docs/tasks/prompt-O1.md:3`.

   T28's superseded header is followed by commands to implement the old min(bound, cap) reservation policy. X1 still says adoption is undecided and T28 is on hold, although the X1 gate is passed and O1 is in progress. There is no X1 report in main, so report-file absence alone makes the completed spike look unfinished; its report and subsequent rounds are in the spike worktree/branch. These are exactly the “old approach plus override” structures Ben asked to remove.

   **Proposed rewrite:** Replace T28 with a short cancellation record pointing to O7's growth-limit task, deleting its executable requirements. Replace main's X1 task with a completed-spike record pointing to the branch report's final round and O1's port, leaving historical experimental instructions in the historical branch.

26. **P2 — PLAN says to merge the spike while O1 explicitly forbids merging it.**

   **Locations:** `docs/PLAN.md:37`, first and last O1 descriptions; `docs/tasks/O1-offset-runtime-and-inline-alloc.md:7`.

   PLAN calls O1 a merge of the runtime/slice and ends by saying it merges changes into main. The task says “Don't merge the branch: port its changes ... by hand” because T27–T32 changed the storage representation. The broad word “merge” could mean integration informally, but it is an avoidable ambiguity in a task involving an actual spike branch.

   **Proposed rewrite:** “O1 ports the spike's runtime, mode/verify switches and supported slice by hand onto current main, adapting them to T29/T31/T32; do not merge the spike branch.” Use this wording at both PLAN occurrences.

27. **P2 — The memory theory still identifies by-address large values as the approach under review without naming its offset endpoint.**

   **Locations:** `docs/DESIGN.md:157`, `:398–402`; compare `:374–379`, `docs/PLAN.md:37` (O3/O4), `compiler/src/emit.rs:3958–3960`.

   Large-value borrowing/destination passing is still described as “passed by address” in the theory's list of exceptions, while the adopted generated ABI passes data-stack locations as offsets. Conversely, the source comment says lazy collections “must travel by address” to avoid whole-aggregate loads. Avoiding aggregate copies requires indirect access, not persistent machine addresses. Those phrases obscure the distinction between a borrowed location and its transient address.

   **Proposed rewrite:** “Large values are accessed through borrowed locations and caller-owned destinations rather than copied as whole aggregates; stack locations cross generated calls as offsets, with transient addresses derived only for access or pinned foreign calls. O3/O4 retire the current raw-pointer call paths.” Update the source comment when the corresponding migration lands.

28. **P3 — DESIGN's Later list and first-step completion claims have not caught up with approved tasks.**

   **Locations:** `docs/DESIGN.md:905–920`; `docs/PLAN.md:29–30`, `:75–81`; compare `docs/reviews/claude-T09-review.md:3`, `claude-T10-review.md:3`, `claude-T18-review.md:3`, `claude-S1a-2-review.md:3–7`, and `docs/tasks/T16-report.md` acceptance coverage.

   The Later paragraph still lists map/set/queue/ring/grid and nested bounded text as future work, though those features are implemented. Conversely, “All ... step 2 acceptance cases” in M3 suggests scheduler reuse and other deferred cases are complete even though PLAN immediately schedules some later; fully flattened nested layout is also explicitly outstanding. The prerequisite table mixes already implemented owner parameters, collections, slicing and number helpers with unimplemented generics, file handles and parallel builders.

   **Proposed rewrite:** “Mark accepted tasks complete with report/review links and list only their concrete remaining cases, including nested flattening, pool copy/reset/return support and scheduler cleanup/reuse. Describe M3 as completing its assigned sequential cases, with explicit links for deferred acceptance cases, and move completed prerequisites out of the pending table.”

29. **P3 — The open-question list still reopens generic constraints already decided in the body and Decided list.**

   **Location:** `docs/DESIGN.md:899`; compare `:557–560`, `:594–611`, `:877` and T03's approved implementation.

   The entry says generics' constraints still need choosing between traits and interfaces, despite the explicit named-interface/impl decision. Error handling is also described as though only the overview's proposal exists, despite the Option-only `?.`/`??` contract and implemented propagation.

   **Proposed rewrite:** “Named interfaces with explicit impls and Option/Result propagation follow the contracts above; operator customization on declared types still needs a design.” If a fuller error-handling reference section is wanted, list it as documentation work rather than an undecided semantic choice.

30. **P3 — Optional narrow offsets still depend on an experiment that finished without measuring them.**

   **Locations:** `docs/PLAN.md:37` (O8 “if X1 round 2 shows they pay”); `docs/DESIGN.md:379`.

   X1's final report explicitly says the optional 32-bit variant was not attempted (spike worktree `docs/tasks/X1-report.md:311`); round 2 says the same at line 218. Thus no completed X1 result can satisfy O8's named trigger. The language's current 64 GiB default also cannot fit the proposed 32 GiB scaled range without an explicit restriction/64-bit selection rule. This remains a measurement proposal, not a second adopted offset format.

   **Proposed rewrite:** “Use 64-bit stack offsets throughout O1–O7. Afterward, consider a separately measured 32-bit/scaled-offset proposal that specifies alignment, range/cap compatibility and overflow checks before any adoption decision.”

31. **P3 — “Reserved once” in Performance still describes the immovable-stack implementation.**

   **Location:** `docs/DESIGN.md:728`; compare `:381–390`.

   State is reserved once, but job stacks may now be created, grown, moved, pooled, trimmed and released. The no-steady-state-allocation target can still hold for warmed, adequately provisioned workloads; the unconditional explanation does not.

   **Proposed rewrite:** “Globals are claimed once; warmed pooled stacks reuse their storage on measured steady-state paths. Stack creation, growth and trimming are explicit cold/resource events, reported separately from zero-allocation hot-path assertions.”

32. **P3 — The stack hook still calls a residency sample “touched,” after DESIGN explicitly separates those metrics.**

   **Locations:** `runtime/nl_runtime.c:439–457`; compare `docs/DESIGN.md:385`, `:389–390` and `docs/tasks/T17-report.md` under “Measured versus computed data-stack use.”

   The hook counts `mincore`-resident pages and prints `touched=...`; it cannot establish historical writes, commitment, or a job's demand, especially with paging or pooled inherited pages. DESIGN correctly calls `mincore` a resident sample. This matters because later pooling/admission tasks must not turn the existing test hook into the wrong source of truth.

   **Proposed rewrite:** “Report this hook as a current resident-page sample; retain allocation high-water as its own metric. The scheduler work adds independent per-job write/commit demand accounting before using history for trimming or admission.”

## Temporary implementation paths and their ends

The following inventory answers the implementation part of the audit; references are to the observed O1 working tree. “End” means a stated removal/replacement condition, not merely a hope that two implementations stay equivalent.

| Paths doing related work | Evidence | Stated end / audit result |
| --- | --- | --- |
| Pointer and offset stack ABIs, allocators, top/base access and emission | `compiler/src/driver.rs:71–94`; `compiler/src/emit.rs:138–161`; `runtime/nl_runtime.c:255–312,399–418,477–485` | **Yes: O7**, in `docs/PLAN.md:37–38` and `docs/DESIGN.md:391`. O1's fail-closed slice is intentional; the incompatible full-suite promise is finding 6. Include pointer-only analysis/report helpers and tests in the O7 removal inventory, not just the environment switch. |
| Rust and next-lang lexers/parsers/dumpers | `compiler/src/lexer.rs`, `parser.rs`, `syntax_dump.rs`; `selfhost/lexer.nl`, `parser.nl`, `dump.nl`, `parse_output.nl`; `compiler/tests/selfhost.rs:19–47` | **Partial/conflicting:** H1 ends the selfhost-as-standalone-only stage; the later default switch ends routine production Rust parsing. Rust reference parsing deliberately remains for differential tests, while PLAN also says “fallback”; finding 7 resolves the endpoint. Rust compiler retirement is explicitly a later decision (`docs/PLAN.md:69`), not something H1 promises. |
| Rust parse-only package loading, Rust compile package loading, and corresponding selfhost loading | `compiler/src/driver.rs:223–340,401–467`; `selfhost/source.nl:285–347` | **H1 is the stated reconciliation point, but its policy is not chosen.** Finding 23 recommends preserving each command's behavior across both front ends. Independent reference code may remain; unexplained policy divergence should not. |
| Contiguous element gather/copy-back versus in-place collection lane/index access | `compiler/src/emit.rs:11474–11538,11562–11581`; `docs/reviews/claude-T13-review.md:11` | **Yes: O4**, now named in `docs/PLAN.md:37`. Its old association with the layout follow-up needs consolidating (finding 22). Ordinary scratch for a genuinely non-place result or overlap-safe fallback is not automatically obsolete. |
| Nested inline collection layout versus fully flattened nested SoA layout | `compiler/src/emit.rs:3612–3616`; `docs/reviews/claude-T06-review.md:13`; `docs/PLAN.md:45` | **Yes: before M4**, but the remaining task has no identifier and its dependency on O4 is unstated. The design should identify current versus target behavior (finding 22). |
| Byte-list I/O versus Bytes/Text I/O | `compiler/src/emit.rs:20920–20947`; `runtime/nl_runtime.c:1673,1719` | **The named endpoint has passed:** PLAN said “until T16,” but both remain. No replacement end is stated (finding 24). |
| Inline string storage, collection lane/class storage, and transient string descriptors | `compiler/src/emit.rs:3453–3463,3785–3805,3830–3876`; `docs/tasks/T29-report.md:5–9`; `docs/tasks/T31-report.md:5–7` | **These are distinct representation roles, not evidence that T29/T31 left the old stored-pointer scheme enabled.** Stored values and lanes are pointer-free; transient/static descriptors remain purposeful. O2/O3 convert surviving stack references to offsets, not static literal addresses into stack offsets. DESIGN needs the scoped description in finding 10. |
| `type_size` versus `type_size_legacy`, plus checked sizing in the checker | `compiler/src/emit.rs:3830–3947`; `compiler/src/checker.rs:2442–2465,2574–2598` | **No removal end is stated for the `legacy` name.** Some separation represents inline storage versus collection/descriptor layout and is intentional; do not delete one routine solely because its name says legacy. Document/rename the representation roles and have the layout task explicitly audit their shared rules; the checked and emitted size implementations must continue to agree. |
| General radix integer formatter versus optimized decimal formatter | `docs/tasks/T32-report.md:5–7` | **Intentional specialization, not a temporary competing implementation.** Bases 2/8/16 still need the general formatter; decimal uses the measured path. No removal end is required. |

Two requested topics are already consistent in their central contracts: Option-only `??` is correctly stated at `docs/DESIGN.md:560` and enforced by the checker (the remaining problem is the diagnostics in finding 18); capability grants correctly default to `out` only and explicit lists replace that default (`docs/DESIGN.md:786`, `compiler/src/driver.rs:1737–1782`, `docs/reviews/claude-T20-review.md:9`). Historical T20 reports describe their fix sequence; they should not be read as restoring the old requirement for an output-only manifest. Likewise, no live N-data-stack implementation was found; the N-stack remnants are documentation, while the pointer/offset duplication is the explicitly bounded O1–O7 migration.

The rejected mandatory slide-down placement rule is explicitly replaced at `docs/DESIGN.md:367`; `:372` retains sliding only as a possible optimization. T30's scratch/copy-down fallback for an unproved reassignment (`docs/tasks/T30-report.md:7–9`) is a separate, intentional case, not a reason to restore the old placement contract or remove every memmove.
