**Verdict: Request changes.** Valid E2b programs fail compilation, and a rejected program is accepted. Five findings follow; diagnostic wording/order differences are not findings.

Reviewed `a5c0b3a`, its report, the binding E2 spec, E2i interfaces, and stage-0 checker/typed/emitter paths. Line numbers below refer to the archived commit. Built `/tmp/sol-sh` once from `/tmp/sol-e2b-src/selfhost`; no checkout builds or Cargo runs. Probe packages and captured results are under `/tmp/sol-e2b-probes/`.

Commands: stage 0 was `$HOME/.cache/next-lang/target/release/nlc --frontend=rust run <pkg>`. Selfhost was, inside each package, `/tmp/sol-sh build . -o .x.ll --runtime=core`, followed by the cached `nlc link-ir .x.ll -o <pkg>/x` and execution. Unless stated otherwise, results use default O1. Empty streams are stated explicitly.

1. **[P1] Nullary enum values break struct literals.** `selfhost/compiler.nl:6027–6040` duplicates aggregate-source classification instead of using the updated shared functions. It treats every `Field` as an existing address and every `Name` as a local binding, although nullary constructors now use those node kinds.

   [Probe source](/tmp/sol-e2b-probes/enum_struct_nullary/main.nl):

   ```next
   enum E { A, B }
   struct S { e: E }
   fn main() { print(S {e: E.A}) }
   ```

   Stage 0: status 0, stdout `S { e: A }\n`, empty stderr. Selfhost writes IR successfully; linking exits 3, empty stdout, with `nlc: tool failure: clang failed` and `.x.ll:26:41: error: use of undefined value '%addr.7'`. It emits a copy from `%addr.7` although the constructor occupies `%agg.7`. Replacing `E.A` with `A` ([source](/tmp/sol-e2b-probes/enum_struct_unqualified_nullary/main.nl)) preserves stage-0 output but crashes selfhost itself: status 1, stderr `compiler.nl:6036:42: index out of range`. The qualified failure also reproduces at O3.

   **Recommendation:** use `aggregate_source_kind`/`aggregate_source_id` in struct-field initialization. Add both spellings as fixtures; E2c's nullary `none` will encounter the same distinction.

2. **[P1] A terminating constructor payload emits instructions after its exit.** Constructor phases 60/61 (`compiler.nl:6149–6170`) unconditionally store the operand and continue constructing after it returns, breaks, or continues.

   [Probe source](/tmp/sol-e2b-probes/never_payload/main.nl):

   ```next
   enum E { C(int), D }
   fn f() -> int { let x = E.C(return 6); 9 }
   fn main() { print(f()) }
   ```

   Stage 0: status 0, stdout `6\n`, empty stderr. Selfhost IR generation exits 0; linking exits 3, empty stdout, with `nlc: tool failure: clang failed` and `.x.ll:24:13: error: use of undefined value '%v6'`. The IR contains `ret i32 %v5` followed by a payload store using nonexistent `%v6`. Same result at O3. Separate [continue](/tmp/sol-e2b-probes/never_payload_continue/main.nl) and [break](/tmp/sol-e2b-probes/never_payload_break/main.nl) probes produce stage-0 stdout `0\n1\n7\n` and `0\n7\n`; both selfhost links fail on undefined `%v8`.

   **Recommendation:** propagate operand termination through constructor frames and enclosing uses; emit no stores, tag, later arguments, or subsequent instructions on that path. Reuse this rule for E2c constructors.

3. **[P2] Constructor calls ignore local shadowing.** `check_one_body`'s `Call` branch (`compiler.nl:3991`) searches functions/cases without first checking the local scope.

   [Probe source](/tmp/sol-e2b-probes/local_constructor_collision/main.nl):

   ```next
   enum E { C(int) }
   fn main() { let C = 1; print(C(3)) }
   ```

   Stage 0: status 2, empty stdout, stderr `main.nl:2:30: error: value 'C' has type int and cannot be called; use a function-typed value`. Selfhost builds, links, and runs successfully: status 0, stdout `C(3)\n`, empty stderr. Reproduces at O3.

   **Recommendation:** resolve visible values before functions and constructors, rejecting noncallable locals. Pin this for locals, parameters, and match bindings; the binding spec explicitly requires stage-0 name-resolution meaning.

4. **[P2] A constructor named `print` loses its payload copy helper.** `mark_struct_helpers` (`compiler.nl:7206–7217`) recognizes printing by spelling before testing the resolved constructor kind.

   [Probe source](/tmp/sol-e2b-probes/builtin_print_collision/main.nl):

   ```next
   struct S { x: int }
   enum E { print(S) }
   fn main() { match (print(S {x: 9})) { print(_) => () } }
   ```

   Stage 0: status 0, both streams empty. Selfhost: status 2, empty stdout, stderr `main.nl:1:1: error: self-hosted LLVM IR buffer limit exceeded`; no IR written. The constructor requires `S`'s copy helper, but the registry marks only its print helper; missing-helper detection sets `ir_overflow`. Naming the payload binding instead of ignoring it incidentally registers the copy helper and hides the defect.

   **Recommendation:** classify resolved calls consistently in checking, helper discovery, and emission. Constructor payloads must register copy regardless of case spelling.

5. **[P2] Many small enums cause cubic compile time.** `enum_type_matches` (`compiler.nl:1048`) repeatedly calls scanning `enum_type_id`, making each name lookup quadratic; N qualified constructors repeat that N times.

   [Generator](/tmp/sol-scale-large.py) creates `enum Ei { Ci(int) }` and, inside `main`, `let xi = Ei.Ci(1)` for `0 <= i < N`, then `print(7)`. [N=3200 source](/tmp/sol-e2b-probes/scale-3200/main.nl), [results](/tmp/sol-e2b-probes/scale-3200/results.json), [N=6400 source](/tmp/sol-e2b-probes/scale-6400/main.nl).

   Single unpinned wall-time samples: selfhost **IR only** takes 4.626s at 1600 and 35.200s at 3200; 6400 is killed by the probe's 45s timeout. Stage-0 **whole builds** take 0.651s, 0.905s, and 1.743s. Stage-0 binaries all exit 0 with stdout `7\n`, empty stderr; completed selfhost binaries match. The 6400 package is only 333,673 source bytes. IR growth stays linear: 2,248,008 to 4,277,344 bytes.

   **Recommendation:** retain stable type IDs and indexed name lookup instead of repeatedly translating enum ordinals by scanning the type table. Add a many-distinct-enums scaling check.

Other probes matched for nested layouts, active-payload equality/printing/copies, evaluation order, aggregate parameters/results, bool/integer matches, 500 arms, and rejection of missing/duplicate/unreachable arms and struct–enum cycles. A depth-40 sum DAG emitted 421,100 bytes. No edits to the frozen location ABI, addressing function, or exit/cleanup interfaces were found; the missed shared classification in finding 1 should be fixed before E2c builds on it.
