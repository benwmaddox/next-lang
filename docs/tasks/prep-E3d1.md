# Prep brief: E3d1 (builders, `grow` parameters, append transactions)

Status: brief for the model that writes and implements E3d1, right after E3c. It follows docs/tasks/prep-E3c.md. The scope is docs/tasks/E3-selfhost-collections-text.md: the E3d1 row of "Parts and order", "`grow` parameters and append transactions", "E3d1: builders" (in "`Ascii`, `Text` and `Bytes`"), "Layout and residence", the E3d1 lines of "Directed fixtures" and "Measurements", reference fix 4, and the E3d1 bullet of "Language friction fixes". Design background: DESIGN.md "The job's data stack" (reserve ahead, tight packing), "How the compiler places values" (fresh result, append, checkpoints, `take`, the `render`/`line` worked example) and "Loops can't quietly fill a stack"; the step-2 lines of DESIGN's validation list ("copies and moves", "append and bounds", "overlap and iteration cleanup").

Written 2026-10-27 against main at f413c13 (E3b), with E3a3 running and E3c not started. Selfhost line numbers drift, so selfhost code is cited by name only. Stage 0 is frozen, so its line numbers (checked) are stable.

## Scope checklist

E3d1 adds these, and nothing else:

- [ ] `+=` on `Ascii` only: a local builder, a struct field path, and (friction item, see question 3) a `grow` parameter. On `Text` and `Bytes` it is stage 0's numeric-operator error. A non-`Ascii` right side is `Ascii '+=' needs an Ascii value; found {type}`.
- [ ] Stage 0's proof rule for `+=`: the builder's length range plus the piece's range must fit the maximum, otherwise `cannot prove this append fits Ascii max N; use '{name}.try_append(value)' and handle Full`. Accept and refuse exactly what stage 0 does, in both directions (as E3b's proven pushes did).
- [ ] `try_append` on `Ascii`, `Text` (accepts `Text` or `Ascii`) and `Bytes` (accepts `Bytes` only), returning `Result<(), Full>`. Unused, it is the unused-`Result` error. `discard` accepts it.
- [ ] `Bytes.push(byte)` returning `Result<(), Full>`, with stage 0's proven-push rule: an unhandled push is allowed when the length fact proves room. `discard` accepts it.
- [ ] `take` with its move rules and texts (whole local `Ascii` only; no parameter; not inside a branch; not from outside a loop into its iteration; no widening; not out of its scope; no use after the move).
- [ ] `grow` parameters on `Ascii`, `Text` and `Bytes` only, with the argument a mutable place of the same kind. The argument may be a struct field (friction item). The callee publishes the new length only on success. Forwarding a `grow` parameter to another `grow` parameter.
- [ ] The `grow` width check, fixed (question 1): the argument's maximum must be at least the parameter's, in bytes and, for `Text`, in code points. Stage 0's check is inverted (pinned below).
- [ ] The `write`/`grow` call-path audit: `check_call_write_modes` checks place, mutability and live views only under `FLAG_MODE_WRITE`. `grow` arguments need the same checks.
- [ ] Append transactions: a checkpoint (length, code-point count for `Text`, stack top) before each `+=`, `try_append`, `Bytes.push` and append-mode call, restored when that append fails (`Full`, or an error propagated by `?` from the producer). Nested appends restore their own. Rollback covers one append, never a whole call (published-then-error is pinned below).
- [ ] Append mode for functions returning `Ascii` or `Result<Ascii, E>`: the callee writes straight into the builder past its accepted length. Other result kinds build in a temporary and copy. The choice is not observable, but the rollback is.
- [ ] Reserve-ahead regions for builders over the 4,096-byte threshold, tight packing of temporaries finished before anything is placed above them, and iteration scopes that free per-iteration scratch but keep outer builders.
- [ ] The loop-growth bound rule with stage 0's three texts (pinned below).
- [ ] The T30 in-place reassignment `buffer = f(buffer)` (a direct call whose one matching `write`/`grow` parameter is the assigned local itself, returned on every path, with no other alias). `s = s + s` and `t += t` take a safe path.
- [ ] Friction items: `out += x` on a `grow` parameter; `grow` on a struct field; a struct field receiving a longer `Ascii` (see "Friction items").
- [ ] A builder benchmark measured against stage 0 (see question 4: text_format).

Not in E3d1: unbounded builders and the starting-size estimate (E3d2); interpolated strings (E3d3); text in collection lanes (E3e); `const` (E3e); function values, so every indirect `grow` fixture stays `unsupported` (`function values`) until E4; `type` aliases (E4).

## Stage-0 implementation reference

All in compiler/src, frozen at `stage0-2026-10-26`. Line numbers checked today.

Checker (checker.rs, `impl Checker`):

- `grow` only on text kinds: the parameter registration at lines 1470 and 3979 (`grow parameters are for Ascii, Text, and Bytes builders; use read or write for other types`).
- Width: `growable_string_max` (2981) and `string_width_fits` (3005). Used for `grow` arguments in `check_indirect_call` (9027; message at 9123) and `check_direct_function_call` (9564; message at 9643). `string_width_fits(actual, expected)` is `actual <= expected` per field, which is the defect.
- `+=` on `Ascii`: the `AssignOp::Add` branch of the assignment in `check_statement` (about 5040-5075): parameter mode test, right-side type test, the `ascii_lengths` range sum, and the "cannot prove this append fits" text. A non-`Add` compound op on `Ascii` is `Ascii supports '+=' for append; use an explicit value assignment for replacement`.
- Method table, in the text-method branch of the method-call checker: `Text.try_append` (6866), `Bytes.try_append` (6929), `Bytes.push` (6995, with `proven_success` from `ascii_lengths`), `Ascii.try_append` (7107). Each refuses a non-`grow` parameter receiver with `{Kind}.try_append through a parameter requires 'grow' mode; 'write' cannot increase its length` (and the `Bytes.push` variant).
- `ascii_lengths` facts: an empty field path keeps a per-local (min, max) length range; a field path is always (0, max); `Ascii`/`Text` `try_append` removes the fact; `Bytes.try_append` sets (0, max); a proven `Bytes.push` adds one; an unproven one sets (0, max).
- Loop growth: `max_loop_iterations` (12990) gives the range loop's bound (`None` when unbounded); `check_loop_ascii_growth` (13257) with `loop_ascii_growth_roots_block` (13144) and `loop_ascii_growth_roots_expr` (13001). Called for range loops (5373) and for-each loops (5595). Roots appended only through `try_append` are "checked" and skip the bound. Only `Ascii` and `Bytes` maxima are tracked; `Text` has no `+=` or `push`, so it never reaches the rule.
- Builder in a loop without a maximum: in `check_statement`'s `Let` arm (message at 4799).
- `take`: `ExprKind::Take` in `check_expr_inner` (10301; the arm is 10445-10481); widening at 4854 and scope at 4869 (both in the `Let` arm); the return form at 5238; use after move at 10505.
- `discard`: 5669. Unused results: `require_handled_result` (3872).

Emitter (emit.rs, for reading the lowering, not for porting its pointer mode or up-front reservation):

- Append mode: `appendable_ascii_result` (4259), `returned_ascii_builder_local` (4211), `returned_result_ascii_builder` (4266), `new_append_variant` (6172), `function_type_supports_append` (12902), `emit_ascii_append_call` (12912), `emit_ascii_append_result_call` (12979), `emit_result_ascii_append_return` (12693), `emit_ascii_append_place` (13628).
- Appends: `emit_ascii_try_append` (13705), `emit_ascii_try_append_scratch` (13827), `emit_bytes_try_append` (13956), `emit_text_try_append` (14076), `emit_bytes_push` (14247), `append_expression_scratch` (1869).
- T30: `in_place_reassignment_parameter` (4686), `emit_direct_call_with_in_place_alias` (14465), `local_region_plan` (4736), `growing_ascii_locals` (4823), `emit_copy_growing_value` (14838).
- Loop growth for the stack bound: `block_growth_per_iteration` (2761), `expr_growth` (2814).

## Selfhost plug-in points

- **Gates.** `unsupported_category_for_node` / `unsupported_node_message` (compiler.nl): `NodeKind.Parameter` with `FLAG_MODE_GROW` is gated today with the text `write and grow parameters`; `NodeKind.Take` falls to the default (`this construct`). E3c should leave `+=` on `Ascii`, `try_append` and `Bytes.push` failing closed (the spec names `builders`). Read E3c's report for the exact strings it used, and remove them here.
- **Calls.** `check_call_write_modes` (compiler.nl): add the place, mutability and live-view checks for `FLAG_MODE_GROW`, the same-kind check, and the fixed width check. The overlap loop already covers `GROW`. `places_overlap`, `is_assignable_place`, `place_root_binding`, `active_view_overlaps_place` are the helpers. Passing: params.nl's `emit_location_descriptor_argument` / `emit_location_parameter`. A `grow` argument is a descriptor like `write`, plus the callee's view of length and code-point count.
- **Methods.** collections.nl's `collection_method_kind` and `emit_collection_method` are the list-method pattern; E3c is expected to add the text method table (probably a new selfhost/text.nl). Add `try_append` and `Bytes.push` there, with `Result<(), Full>` built the way `emit_collection_capacity_result_tag` builds it.
- **Proofs.** E3b's proven-push machinery (`prepare_loop_push_proofs`, `loop_push_is_proven`, `finish_loop_push_proofs`, `loop_iteration_count`, `invalidate_collection_counts_for_write_call` in collections.nl) is the model for the `ascii_lengths` facts and the loop-growth rule. Keep the two fact tables apart (stage 0 does); share the loop-count helper.
- **`discard`.** In `check_one_body`'s `NodeKind.Discard` branch, the accepted set is `COLLECTION_METHOD_PUSH` and `COLLECTION_METHOD_INSERT`. Add `try_append` and `Bytes.push`.
- **`take`.** Parser already builds `NodeKind.Take`. Add checker rules (a moved-locals set per function body, as stage 0's `moved_locals`, which is cleared once per function or test body and never per scope), and lowering: `take` moves ownership, not bytes, so the new binding names the same storage.
- **Regions and exits.** regions.nl: `plan_function_regions`, `region_consider_binding`, `region_consider_temporary`, `emit_region_scope_enter`, `emit_region_scope_exit`, `emit_current_top_load`/`_reference`. Exits through compiler.nl's `lower_scope_exit`; cleanups through `register_exit_cleanup` / `emit_registered_exit_cleanup`. A checkpoint restore is local to one append and is not an exit cleanup; the `grow` length publication on success is.
- **Assignment.** The `+=` lowering goes beside the existing compound-assignment emitter in `emit_expr_linear`'s assign branch, dispatching on the text kind. T30 goes in the plain-assignment path for a direct call.

E3a3's rules for every new emitter (PLAN "E3a3", docs/reviews/sol-selfhost-perf-r1.md "Changes to make"):

- the checkpoint (length, count, top) is SSA values, not memory;
- an iteration scope exit restores the compiler's top without publishing it to the context;
- a builder's reserve-ahead region is taken once where the builder is declared (in text_format, once per outer batch), never per inner iteration;
- the base is reloaded only after a real growth point (an append-mode or other call that can place regions, or the slow path), never between the stores of one append;
- typed builder byte, length and count stores get the program TBAA tag, as E3a3 does for collections.

## Test packages moving at E3d1

From tests/e1/classification.tsv at f413c13, by package name (rows move into a `# E3d1 begin` / `# E3d1 end` block, so line numbers will change). Recount after E3c lands: a row E3c already moved or left with another blocker changes this list. Classes here: `build`, `diagnose` (rejected with real text, same as stage 0), `rejects` (selfhost-only no-shadowing rejection), `expected`.

| Package | Now | At E3d1 | Needs from E3c too |
| --- | --- | --- | --- |
| tests/run/o1_offset_slice | unsupported | build | `str`, Ascii values; 262,120-byte builder, `grow` in a loop |
| tests/run/t14_ascii_move_branch | unsupported | diagnose | Ascii literals |
| tests/run/t14_ascii_move_escape | unsupported | diagnose | `Option<Ascii>` payloads |
| tests/run/t14_ascii_take_widen | unsupported | diagnose | |
| tests/run/t14_ascii_use_after_take | unsupported | diagnose | |
| tests/run/t14_ascii_write_append | unsupported | diagnose | |
| tests/run/t15_loop_overflow | unsupported | diagnose | `if` expression with Ascii |
| tests/run/t15_uninferred_loop_builder | unsupported | diagnose | |
| tests/run/t18_logsum_alignment | unsupported | build | `pad`, `str`, Ascii struct field |
| tests/run/t30_copy_down | unsupported | build | `b"..."`, Bytes values |
| tests/test/t29_dirty_inline_copy | unsupported | build | 9,000,000-byte Ascii read parameter |
| tests/run/noshadow_t17_worked_reservation | unsupported | build | `ascii_upper`, `str` |
| tests/test/noshadow_t25_bytes | unsupported | build | `validate_utf8`, `to_text`, `Utf8Error`, `b[i]`, slicing |
| tests/test/noshadow_t32_number_format | unsupported | build | `byte`, `to_ascii`, `Text max N bytes max M`, `.bytes()` |

14 rows: 7 to `build`, 7 to `diagnose`.

Stay where they are: t14_ascii_values (a `type` alias and a function value, E4); t16_collections (maps, sort, text in collections); noshadow_t06_discard_capacity (map, set and pool); t15_append_growth (`rejects`, and uses function values); t17_worked_reservation, t25_bytes, t32_number_format (`rejects`; their noshadow copies move); t14_ascii_loops (its `+=` are numeric, so it is E3c's). Undecided: t30_locality has no builder operation (a 1 MiB `Bytes.empty()` between small locals, T30's region order). It belongs to E3c; if E3c leaves it unsupported, check why before moving it here.

Ready-made oracle: t15_append_growth's expected.stdout (stage 0 output) pins checkpoint restore (`append_partial`, `collect_partial`), published-then-error (`append_origin`, `log_line`), nested capacity (`nested_capacity`), `out += echo(out)` (`overlap_fallback`), the in-loop non-qualifying reassignment (`merge_in_loop`), three interleaved builders and a 1,000,000-byte builder. The package itself stays `rejects`; copy its non-function-value parts into new tests/e3/d1_* fixtures.

## Friction items for E3d1

From the spec's "Language friction fixes" E3d1 bullet:

1. **`out += x` on a `grow` parameter.** Stage 0 refuses it in every form tried (p03, q40, q41, q43): a parameter, like a field path, has no length fact, so the range is (0, max) and nothing appended fits. Users had to write `discard out.try_append(x)`. The fix needs a rule; see question 3. Fixture: `expected` class whichever rule is chosen, since stage 0 refuses it.
2. **`grow` on a struct field.** Stage 0 already accepts a field argument (q32: `add(h.buf)` with equal maxima works and leaves the sibling field intact). What failed for porters was the width defect on a field (item 3) and `discard` on a user function's `Result<(), Full>` (p04: `discard accepts only built-in operations whose Result error is capacity Full`; correct behaviour, keep it). Fixtures: a field of a native struct and of a large struct (region) passed `grow`, sibling fields unchanged, under the forced-relocation check.
3. **A struct field receiving a longer `Ascii`.** Plain assignment is already refused correctly (p06: `expected Ascii max 4, found Ascii max 8; cast explicitly with (Ascii max 4)value`). Passing an `Ascii max 4` field to `grow Ascii max 8` builds in stage 0 and the program segfaults (q31: status 139, no output). This item reduces to the width fix on field arguments. Fixture: `expected` class, a build error.

## PLAN oracles for E3d1

PLAN.md's "Oracles" list names none for builders. Stage 0 is the oracle (t15_append_growth above, the T14/T15/T30 packages). The LangArena ports that use builders (base64_encode, base64_decode, csv_parse and others) all need `const` (E3e), so they can't serve until then; bench/langarena is another agent's, so read it only.

## Stage-0 probes and pinned answers

Run with `nlc --frontend=rust run` on 2026-10-27; probe sources deleted afterwards, so each is summarised.

| # | Program (summary) | Stage 0 result |
| --- | --- | --- |
| p01 | `var t: Text max 8 = "a"; t += "b"` | `operator '+' requires int or long values` (3:7), status 2 |
| p02 | `var b: Bytes max 8 = b"a"; b += b"b"` | same text |
| p03 | `fn add(out: grow Ascii max 8) { out += "x" }` | `cannot prove this append fits Ascii max 8; use 'out.try_append(value)' and handle Full` |
| p05 | `fn add(h: grow Holder)` (a struct) | `grow parameters are for Ascii, Text, and Bytes builders; use read or write for other types` |
| p09 | try_append/push at capacity, printed | `ok(())`, `err(Full)`; `Ascii max 3` "ab" + "c" ok, + "d" Full; `Text max 2` "é" + "ü" ok (len 2), + "x" Full; `Bytes max 2` b"a" push 98 ok, push 99 Full |
| p10 | `Text.try_append(b"b")` | `Text.try_append needs Text or Ascii; found Bytes max 1` |
| p11 | `Bytes.try_append("b")` | `try_append needs Bytes; found Ascii max 1` |
| p12 | `take` of a `Text` local | `take currently moves a whole local Ascii value; use 'let copy = value' for other values` |
| p13 | `take` of a read parameter | `take cannot move a caller-owned parameter; copy it into a local builder first` |
| p14 | `take` of an outer local inside a loop | `cannot move a value from outside a loop into its iteration; copy it inside the loop` |
| q37 | `var m: Ascii max 8 = take s` then `m += "c"`; `let moved = take inferred` | allowed; prints `abc`, `q`, `r` |
| q47 | `take` of a local declared inside the loop body | allowed |
| q48 | use of a local after `take` | `'outer' was moved by take and cannot be used again; use the new owner or copy it before moving` |
| r54 | `let m = take s; m` as a function's result | allowed, prints `ab` |
| p16 | `for i in 0..10 { b.push(1) }` on `Bytes max 4` (unhandled push) | `loop can grow 'b' to 10 bytes, above its Bytes max 4; handle 'b.push(byte)' returning Full or reduce the loop bound` (span: the `for`) |
| r51 | `for i in 0..n { out += "x" }` with `n: int` | `loop can grow 'out' to 2147483647 bytes, above its Ascii max 8; ...` (not the "no finite bound" text) |
| r52 | the same with `n: int 0..=4` on `Bytes max 4` push | allowed |
| p29, q39 | 50 iterations of `out += "xy"` into `Ascii max 100`; `for x in xs` (capacity 4) adding "ab" into `Ascii max 8` | allowed |
| q40 | `discard a.try_append("x"); a += "y"` | refused: try_append drops the length fact |
| q41 | `h.buf += "b"` on a field | refused: a field path is (0, max) |
| q43 | `if out.len() < 8 { out += "x" }` on a `grow` parameter | refused: no branch refinement |
| q49 | `out += "a" + "b"; out += "c"; out += "d"` into `Ascii max 3` | refused at the third append (the range is summed exactly) |
| p17 | `a.try_append("c")` as a statement | `this Result value is unused; handle it with '?', 'match', or '??' where supported` |
| p18 | `a.append("c")` | `method 'Ascii max 8.append' takes no arguments` (there is no `append`; DESIGN's `out.append(f(out))` is `out += f(out)` or `out.try_append(f(out))` here) |
| p19 | `s = s + s` on "ab" (`Ascii max 8`); `t += t` on "x" | `abab`; `xx` |
| p20 | a `grow` helper: two successful try_appends, then `err(E.Bad)` | `err(Bad)`, builder `xonetwo`: earlier appends stay published |
| r53 | `out.push(65)?` then `out.push(66)` through `grow Bytes max 4` holding `xyz` | `err(Full)`, builder `xyzA` |
| p26 | `s += piece(true)?; s += piece(flag)?` where `piece` appends "ab", errs or appends "cd" | `ok(Sabcdabcd)`; `err(Bad)` |
| q45 | `out.try_append(line(42))` (append mode, `Ascii max 6` result) into "abc" `Ascii max 8`, then `line(7)` | `ok(())` `abcn=42`; `err(Full)` `abcn=42` (no partial `n=7`) |
| q42 | `grow` forwarded through `mid` to `leaf` with `?`, five calls into `Ascii max 16` | four `ok(())`, then `err(Full)`, builder `abababababababab` |
| q44 | `s = rewrite(s)` twice, `rewrite(buffer: grow Ascii max 16)` appending "+" and returning `buffer` | `x++` |
| p21 | `var s = Ascii.empty()` (no annotation, outside a loop) | `Ascii.empty() needs a maximum from its destination; add a Ascii max N annotation` |
| p23 | a `let` passed to `grow` | `a write argument must be a var, a field of a var, or another write parameter` |
| p24 | `Ascii max 8` passed to `grow Text max 8` | `grow argument needs an Text builder with at least 32 bytes reserved; found Ascii max 8` |
| p27 | `a += piece()` with a `Text` result | `Ascii '+=' needs an Ascii value; found Text max 2 bytes max 8` |
| p28 | `both(s, s)` with `grow` then read | `arguments overlap, and at least one is passed as write; pass separate fields or a copy` |
| p30, q46 | `try_append` / `push` on a `write` parameter | `Ascii.try_append through a parameter requires 'grow' mode; 'write' cannot increase its length`; `Bytes.push through a parameter requires 'grow' mode; ...` |
| q32 | field `h.name: Ascii max 4` passed to `grow Ascii max 4` twice, appending "bc" | `ok(())`, `err(Full)`, `abc`, sibling `n` still 1 |
| q50 | `discard t.try_append("é")` five times in a loop, `Text max 3` | allowed (checked root); `ééé`, len 3, byte_len 6 |

### Stage-0 defects and the `grow` width cases

The `grow` width check (reference fix 4). Stage 0 tests `argument max <= parameter max`, field by field. Each case and the class its fixture gets:

| Probe | Argument to parameter | Stage 0 | Fixture class |
| --- | --- | --- | --- |
| p07 | `Ascii max 2` to `grow Ascii max 8` | accepted; the callee's `try_append("12345678")` gives `ok(())` and the caller prints `12345678` from an `Ascii max 2` | `expected` (a build error): defect under any rule |
| q35 | `Text max 2 bytes max 8` to `grow Text max 4 bytes max 8` | accepted; the caller ends with `ééé` (len 3) in a max-2 builder | `expected`: defect under any rule |
| q31 | an `Ascii max 4` struct field to `grow Ascii max 8`, appending six bytes | builds; the binary exits with status 139 (segfault) and no output | `expected`: defect under any rule |
| q34 | `Text max 4 bytes max 8` to the same (equal) | accepted, `ok(())`, `é` | `build` |
| p08 | `Ascii max 8` to `grow Ascii max 4` (larger) | refused: `grow argument needs an Ascii builder with at least 4 bytes reserved; found Ascii max 8` | `diagnose` under question 1's equal-only rule; `expected` (accepted) under the spec's "larger accepted" |
| q36 | `Text max 8 bytes max 8` to `grow Text max 4 bytes max 8` (more code points) | refused: `... at least 8 bytes reserved; found Text max 8 bytes max 8` | as p08 |
| s55 | `Text max 8 bytes max 4` to `grow Text max 4 bytes max 8` (too few bytes) | refused: `... at least 8 bytes reserved; found Text max 8 bytes max 4` | `diagnose` under either rule: correct behaviour |

Other defects (fixtures are `expected` class):
- **p22/q33**: `discard b.push(300)` on `Bytes` builds; `b[0]` then prints 44 (300 mod 256). DESIGN "Literals" and t20_invalid_byte (`cannot prove this value fits byte; use (byte)(256) for a checked cast or 256.fit<byte>() to handle failure`) say a non-fitting `byte` argument is a build error. The selfhost compiler refuses it.
- **q38**: stage 0 can't parse `while`, which the selfhost compiler has since E3b. Growth inside `while` has no stage-0 reference (question 5).

## Pitfalls from reviews and reports

- E3a3's performance rules above. E3d1 adds per-iteration work (checkpoints, scope resets) to every builder loop; text_format and the builder benchmark are where a regression shows. Run the IR test (compiler/tests/selfhost_performance_ir.rs) and add a builder module to it if it has room.
- A failed append must leave no partial bytes visible, including after an append-mode callee wrote part of its output (q45, t15_append_growth). Restore the top too, so a failed append's scratch doesn't stay reserved.
- Self-append and self-overlap: `t += t` (p19), `value.try_append(value.slice(1L..3L))` (noshadow_t25_bytes), `out += echo(out)` (t15 `overlap_fallback`). The source is read before the destination's length changes; an append-mode callee that reads the builder must not run in append mode (DESIGN: it builds in a temporary and copies).
- Evaluation order (spec "Evaluation of arguments and operands"): `try_append`, `+=` and `Bytes.push` are mutators, so a read argument evaluated before one of them in the same call is a snapshot. E2i's skip rule must list them.
- Relocation: a `grow` callee that forces a stack move must still publish into the caller's builder. Directed relocation fixtures: a `grow` argument whose callee grows the stack, for a local builder, a region-sized builder and a struct field.
- The spec's reference fix list puts the width fix in stage 0, but stage 0 is frozen (question 2).
- `t15_append_growth` and `t17_worked_reservation` stay `rejects`; don't "fix" them by editing the packages. Never edit an existing test package.
- The `write and grow parameters` gate text covers `NodeKind.Parameter` only for `grow`; after E3d1 it disappears from the construct table. Check that no committed `expected.diagnostic` or classification comment depends on it.

## Ambiguities and open questions

**Urgent, before E3c starts: question 4.** prompt-E3c.md's acceptance names text_format and tokenize, but neither can build at E3c.

1. **The width rule for a larger argument.** The spec says a larger argument is accepted. But the callee's type says `max N`, and a caller builder that already holds more than N bytes would give the callee a value longer than its type allows. Copying `out` into an `Ascii max N` local, or returning it as `Ascii max N` (t14_ascii_values' `append_result`), would then overflow. Making that safe needs a run-time length check at the call, and that check would be a failure, which the spec forbids for capacity. Recommended: **equal maxima only** (bytes and, for `Text`, code points). Both smaller and larger arguments are refused, with a new text naming both maxima. Larger arguments can come back when the descriptor carries the capacity. Manager to choose. Evidence: every `grow` call in tests/ passes equal maxima (t14_ascii_values, t15_append_growth, o1_offset_slice, t30_copy_down, t06_discard_capacity, t25_bytes and their noshadow copies), and so do the LangArena ports in today's working tree (base64, calculator, compress, csv_parse, etc_logparser, json, template: each `grow Bytes max N` matches its builder's declaration or `type` alias). Equal-only refuses no existing valid stage-0 program and no current oracle.
2. **Where the width fix lands.** Spec "Reference fixes in stage 0" item 4 says stage 0. Stage 0 is frozen, and the E3c manager answer says stage-0 defects are fixed only in the selfhost compiler. Recommended: stage 0 untouched; the width fixtures (p07, q31, q35 and their equals) are `expected` class with hand-written diagnostics; the text gains a code-point clause (stage 0's names bytes only).
3. **What `out += x` on a `grow` parameter means** (friction item 1). `+=` is a statement, so it can't return a `Result`, and capacity is never a run-time failure. Options: (a) prove it from the parameter's maximum alone (only pieces that fit an empty builder; useless in practice); (b) read `grow Ascii max N` as "at least N bytes free", which makes `+=` provable but changes the meaning of every `grow` signature and the valid output of t15_append_growth's `nested_capacity`; (c) on a `grow` parameter, `out += x` means `out.try_append(x)?`, allowed only where `?` on a `Result<(), Full>` is allowed (the enclosing function returns `Result<_, Full>`); elsewhere it stays stage 0's error. Recommended: (c), as an `expected`-class extension, since it changes no valid stage-0 program, with stage 0's error text kept elsewhere and its hint extended to name `try_append(x)?`. If the manager prefers no new sugar, keep stage 0's refusal and only improve the hint. This blocks only that friction fixture, not the rest of E3d1.
4. **text_format belongs to E3d1, and tokenize to E3e.** prompt-E3c.md asks E3c to show text_format and tokenize in the selfhost benchmark. text_format's hot loop is `output += line` (E3d1's `+=`), and tokenize keeps an `Ascii max 32` field in `list<Token, 2048>` (`text in collections`, E3e). Recommended: E3c reports both as not yet buildable; text_format is E3d1's builder benchmark (both compilers, best of five, bench lock), and tokenize waits for E3e.
5. **Growth inside `while`.** Stage 0 has no `while`, and the selfhost `while` has no termination or iteration bound. Recommended: a builder grown by `+=` or an unhandled `Bytes.push` inside `while` is the loop-growth error with stage 0's "no finite bound" text (`loop growth for '{name}' has no finite bound; use '{name}.try_append(piece)' and handle Full, or bound the loop and the bytes added each iteration`), `expected` class. `try_append` inside `while` is allowed (a checked root, as in q50).
6. **`Bytes.push` with a non-fitting literal** (p22/q33). Recommended: refuse with the E3c `byte` store text, `expected` class, and list it with the other stage-0 defects in the report.
7. **The checkpoint and `?` inside a `grow` callee.** Spec and probes agree that rollback is per append (p20, r53). Confirm that no fixture should expect call-wide rollback; recommended: none, and a fixture pins p20.
8. **T30 is not observable.** In-place reassignment versus copy prints the same (q44). Recommended: pin it with output fixtures plus an IR or `NLC_STACK_STATS` peak check (peak bounded by one value, not two), not by comparison with stage 0.

## Next steps

1. Read E3c's report: the text method table, the gate strings it left for builders, the `ascii_lengths`-style facts it built for `+` proofs, and its classification block. Recount the 14 rows above against the file.
2. Get the manager's answers to questions 1, 2, 3 and 5.
3. Write the E3d1 plan with one fixture per checklist bullet, the spec's E3d1 directed fixtures (the `render` example, three builders at once, failed append with nested checkpoints, published-then-error, `continue`/`break` keeping the outer builder, the loop-growth errors, `s = s + s`, `out += f(out)`, the width fixtures), and the probes above turned into tests/e3/d1_* packages.
4. Implement in selfhost/*.nl next to E3c's text code; regenerate selfhost/core_files.nl only if core/ changes.
5. Focused runs while working; the full selfhost suite, both comparison modes, the relocation check and `scripts/bench-vs-rust.sh --selfhost --time` once at the end.
6. Write docs/tasks/E3d1-report.md with the spec's report list.

Do not edit compiler/src, selfhost/, compiler/tests/ or scripts/ in the planning step.

## Manager answers (Claude, 2026-10-27)

- **Q1 (grow width rule):** Ben, 2026-10-27: **equal maxima only** (bytes, and code points for `Text`). Spec and DESIGN updated.
- **Q2:** the width fix lands in the self-hosted compiler only; stage 0 stays frozen. Its fixtures are `expected` class.
- **Q3 (`out += x` on a `grow` parameter):** Ben, 2026-10-27: **keep the refusal**, with a clearer hint pointing to `out.try_append(x)?`. No new sugar.
- **Q4:** agreed. text_format becomes E3d1's builder benchmark; tokenize waits for E3e. prompt-E3c.md is corrected.
- **Q5:** agreed. Growth inside `while` without a finite bound uses stage 0's no-finite-bound error text (`expected` class); `try_append` inside `while` stays allowed.
- **Q6:** agreed. `Bytes.push` of a value outside `byte` is refused with E3c's `byte` error text (`expected` class).
- **Q7:** agreed. Rollback covers one append, never a whole call; a fixture pins the published-then-error case (stage 0's `xonetwo`, `xyzA`).
- **Q8:** agreed. T30 in-place reassignment is tested with output fixtures plus a peak or IR check.
