# Self-hosted compiler compile-time regression

Date: 2026-10-27. Investigation only. Nothing in `selfhost/` was changed. The
fixes below were applied to exported copies and measured there.

## Summary

- **Guilty commit:** `82ecbc2` "E2b fix round: Sol's five findings, the none
  crash, and no name shadowing". It is the first-parent commit right after
  E2b (`a5c0b3a`) and E2c (`a2b9651`). None of the E3 commits on the candidate
  list changed the curve.
- **Cause:** the new package-wide shadow check `check_package_name_shadows`
  (selfhost/compiler.nl). It calls `is_shadowed_function_value` once for every
  declaration (each `let`, parameter, `for` counter and pattern binding).
  - That function scans every syntax node in the package.
  - For every parameter with the same name, it scans every node *again* to
    find a function that holds both.
  - `block_for_node` is a third whole-package scan, and `node_file_index` adds
    a cost per file to every step.
  - With N functions whose parameter names repeat (`value` everywhere, the
    normal case), this is O(N³).
  - The same check also calls `is_top_level_function` once per function. That
    is another O(N²) scan added by the same commit.
- **Fix:** keep every search inside the function that owns the declaration.
  Nodes are stored in postorder (children first, each node records its
  subtree size), so each search becomes a short local walk.
  - The owner function and the nearest enclosing block are found by walking
    forward from the node. The walk stays inside that function or block.
  - The candidate scan covers only the owner's subtree, with no nested
    whole-package loop.
  - Top-level functions come from one walk over the `Program` node's children.
  - No new tables are needed, and the memory reservation does not change.
- **Before/after**, scalar package, median of 3, pinned to one CPU:

  | Functions | HEAD | Fixed |
  | ---: | ---: | ---: |
  | 1,000 | 6.58 s | 0.14 s |
  | 2,000 | 54.07 s | 0.21 s |

  With locals, calls and loops at 1,000 functions: 40.39 s before, 0.59 s
  after. Generated IR, exit status and diagnostics are byte-identical to HEAD
  on all 685 packages under tests/ and on the generated packages, in both
  normal and `--test` builds.

## Correcting the baseline

The stack-bound note quoted "E2b: 10,000 functions in 0.12 s". E2b-report.md
does not say that. For the 10,000-function scalar corpus it records:

- compile to IR: 1.34 / 1.37 / 1.39 s
- whole build: 6.6 to 6.8 s

The 0.08 s compile-to-IR and 0.51 to 0.62 s whole-build figures in that report
belong to the 546-byte aggregate benchmark.

Reproduced on `a5c0b3a`: `shc build . -o out.ll --runtime=core` on the
10,000-function scalar package takes **1.53 s** (median of 3), in line with
the recorded 1.37 s. E2b takes 0.12 s at **1,000** functions, which is probably
where the 0.12 s figure came from.

## Method

- **Building each commit:**
  `git archive <commit> selfhost core | tar -x -C /mnt/d/tmp/ctime/c-<commit>`,
  then
  `~/.cache/next-lang/target/release/nlc --frontend=rust build <dir>/selfhost -o <dir>/shc`,
  under `ulimit -v 8000000`.
- **Timing:** `shc build . -o out.ll --runtime=core` run inside the generated
  package, under `ulimit -v 8000000` and `flock -x
  /home/ben/linuxbench/bench.lock`.
- **CPU pinning:** each run was pinned with `taskset -c 0`. Unpinned runs on
  this Core Ultra 9 185H varied by up to 2x (12.7 s against 6.4 s for the same
  HEAD row) while another agent's precommit was running. The bisect pass
  (second table) was unpinned and took one sample per commit, but its effect
  is about 40x, far beyond that noise.
- **Generators:**
  - *scalar* is `scripts/gen-selfhost-bench.py` (the E1/E2b corpus). It makes
    N functions `fn helper_NNNNNN(value: int) -> int { value + 1 }`, and
    `main` calls the last one.
  - *loop* is the same set of functions, each with a body like this. Every
    function calls the previous one, so there are N call sites and N `for`
    loops, and the names `value`, `a`, `total` and `k` repeat in every
    function.

    ```
    fn helper_000123(value: int) -> int {
        let a = value + 123
        var total = 0
        for k in 0..4 {
            total = total + helper_000122(a) + k
        }
        total
    }
    ```

## Timings at HEAD and E2b

Median of 3 runs, in seconds, pinned to CPU 0. "HEAD" is `d6f7d62` (main).
The HEAD loop row at 2,000 functions is a single unpinned run.

| Package | N | E2b `a5c0b3a` | HEAD `d6f7d62` | HEAD fixed (fix3) |
| --- | ---: | ---: | ---: | ---: |
| scalar | 250 | 0.12 | 0.25 | 0.11 |
| scalar | 500 | 0.10 | 0.85 | 0.13 |
| scalar | 1,000 | 0.12 | 6.58 | 0.14 |
| scalar | 2,000 | 0.17 | 54.07 | 0.21 |
| scalar | 4,000 | 0.35 | - | 0.45 |
| scalar | 8,000 | 1.02 | - | 1.39 |
| scalar | 10,000 | 1.53 | - | 2.53 |
| loop | 250 | 0.11 | 0.93 | 0.14 |
| loop | 500 | 0.15 | 5.20 | 0.23 |
| loop | 1,000 | 0.25 | 40.39 | 0.59 |
| loop | 2,000 | 0.63 | 260 (1 run) | 1.19 |
| loop | 4,000 | 2.22 | - | 4.36 |

At HEAD, each doubling of N multiplies the time by about 7 to 8. That is the
cubic signature: doubling N multiplies an N³ cost by 8.

## Bisect over first-parent main

One unpinned sample per commit. The first-parent commits from `a5c0b3a` to
`d6f7d62` that touch `selfhost/` or `core/`:

| Commit | Step | scalar N=1000 (s) | loop N=500 (s) |
| --- | --- | ---: | ---: |
| `a5c0b3a` | E2b | 0.11 | 0.13 |
| `a2b9651` | E2c | 0.14 | 0.12 |
| **`82ecbc2`** | **E2b fix round (no name shadowing)** | **5.48** | **4.63** |
| `6d6bae9` | Merge E3a1 | 5.76 | 4.72 |
| `5a6b717` | E3a2 | 6.63 | 4.26 |
| `24e9805` | core environment scan | 5.52 | 4.23 |
| `f413c13` | E3b | 5.73 | 4.24 |
| `6515dfd` | E3a3 | 5.66 | 5.07 |
| `b34bc5c` | E3b fix round | 5.61 | 4.22 |
| `cb39680` | Merge E3a3 loop-exit fix | 5.65 | 4.30 |
| `d6f7d62` | HEAD | 6.37 | 4.31 |

The step from 0.14 s to 5.48 s happens in exactly one commit, `82ecbc2`.
Nothing later changes the N=1000 numbers by more than noise.

## Cause

### The profile

A `perf` profile of HEAD building the 1,000-function scalar package:

| Self time | Function | What it is |
| ---: | --- | --- |
| 54.7% | `nl_fn_80` | `is_shadowed_function_value` |
| 30.9% | `nl_fn_70` | `node_file_index` |
| 13.3% | `nl_context_set_top` | stack bookkeeping in the inner loops |
| 0.2% or less | anything else | |

How the ids were mapped to names:

- The stage-0 binary only has `nl_fn_<id>` symbols. A `clang` wrapper on
  `PATH` captured the generated `nlc-recursion-final.ll`, whose
  `; function <name>` comments give the names.
- In compiler.nl the ids follow declaration order with a fixed offset of 56.
- `objdump` agrees: `nl_fn_80` calls `nl_fn_70` four times and `nl_fn_79`
  (`block_for_node`) twice. Those are exactly the four `node_file_index` and
  two `block_for_node` calls in `is_shadowed_function_value`.

### Why it is cubic

Commit 82ecbc2 added `check_package_name_shadows` and calls it from
`check_package_bodies` and from the core build path. Its last loop:

```
for node in 0L..tables.nodes.count() {
    ... if not Let / Parameter / For / PatternBinding: continue
    if reserved_names[name_id] { fail ... }
    if is_shadowed_function_value(files, tables, compiler, node, node_file_index(...), name_id) { fail ... }
}
```

The same commit also changed `is_shadowed_function_value`. Before 82ecbc2 it
was called only for `Name` references that matched a function name. Now it
runs for every declaration. Its cost per call is:

1. A scan over all M nodes to find any `Function` or `Test` whose source span
   covers the reference.
2. `block_for_node(node)`: a scan over all M nodes for the smallest enclosing
   `Block`, calling `node_file_index` (cost per file) on every candidate.
3. A scan over all M nodes for earlier declarations of the same name, again
   calling `node_file_index` on each.
   - For each `Parameter` with the same name it runs **another scan over all M
     nodes** (`for owner in 0L..tables.nodes.count()`). That scan looks for a
     function holding both the parameter and the reference, and it has no
     early exit.
   - For each `Let` with the same name it calls `block_for_node` again (M).
   - For each `PatternBinding` with the same name it scans all M nodes for a
     `MatchArm`.

Let D be the number of declarations, P the number of parameters sharing one
name, and M the number of nodes. All three grow in proportion to N.

- In the scalar corpus every function's parameter is called `value`, so
  P = N. The cost is D × P × M, which is O(N³).
- In the loop corpus the lets `a` and `total` and the counter `k` repeat as
  well. `block_for_node` adds about L² × M for the repeated lets, where L is
  the number of lets sharing a name.

That explains the factor of 7 to 8 per doubling. Packages with unique names
would only hit the O(N²) part, which is why tests that rename everything look
fine.

The same function also calls `is_top_level_function(node)` once per
`Function` node. It scans every node for `Program` nodes and then walks the
whole child list. That is another O(N × M) loop added by this commit.

## Fix (confirmed)

The fix is fix3 below, applied to an exported HEAD and measured. All changes
are in selfhost/compiler.nl.

**How the node table is laid out.** Nodes are stored in postorder: children
come before their parent. Node `i`'s subtree is `[i - subtree + 1, i]`, and
its ancestors all have larger indices. So the nearest enclosing block or
function of `n` is the first node `j > n` of that kind with
`j - subtree(j) + 1 <= n`. Every node passed on the way lies inside that
ancestor, so the walk costs at most the ancestor's size.

The changes:

- **`block_for_node`:** walks forward from the node to the nearest enclosing
  `Block`. It stops at the owning `Function`/`Test`, or at `Program`.
- **New `enclosing_owner`:** the same forward walk, stopping at the owning
  `Function`/`Test`.
- **`is_shadowed_function_value`:**
  - Scans only the owner's subtree.
  - A `Parameter` with the same name in that subtree is enough. The nested
    owner scan is gone.
  - The `MatchArm` search for pattern bindings walks forward from the binding,
    inside the owner.
  - The per-candidate `node_file_index` calls are gone: everything in the
    owner's subtree is in the same file.
- **`check_package_name_shadows`:** marks top-level function names by walking
  each `Program` node's child list once. It no longer calls
  `is_top_level_function` per function.

```diff
@@ fn block_for_node(
-    var found = -1L
-    var smallest = 9223372036854775807L
-    let value = tables.nodes[node]
-    for candidate in 0L..tables.nodes.count() {
-        if tables.nodes[candidate].kind != NodeKind.Block || node_file_index(tables.nodes, files, candidate) != file_index { continue }
-        let block = tables.nodes[candidate]
-        if block.start <= value.start && block.end >= value.end && block.end - block.start < smallest {
-            found = candidate
-            smallest = block.end - block.start
-        }
+    for candidate in node..tables.nodes.count() {
+        let syntax = tables.nodes[candidate]
+        if syntax.kind == NodeKind.Program { break }
+        if syntax.kind == NodeKind.Block && candidate - syntax.subtree + 1L <= node { return candidate }
+        if (syntax.kind == NodeKind.Function || syntax.kind == NodeKind.Test) && candidate - syntax.subtree + 1L <= node { break }
     }
-    found
+    -1L
+}
+
+fn enclosing_owner(tables: ParseTables, node: long) -> long {
+    for candidate in node + 1L..tables.nodes.count() {
+        let syntax = tables.nodes[candidate]
+        if syntax.kind == NodeKind.Program { break }
+        if (syntax.kind == NodeKind.Function || syntax.kind == NodeKind.Test) && candidate - syntax.subtree + 1L <= node { return candidate }
+    }
+    -1L
 }
@@ fn is_shadowed_function_value(
-    var unused = 0L
-    for candidate in 0L..tables.nodes.count() { ... owner span search ... }
-    if unused == 0L { return false }
+    let owner = enclosing_owner(tables, node)
+    if owner < 0L { return false }
     let reference_block = block_for_node(tables, files, node, file_index)
-    for candidate in 0L..tables.nodes.count() {
+    let first = owner - tables.nodes[owner].subtree + 1L
+    for candidate in first..owner + 1L {
         let kind = tables.nodes[candidate].kind
-        if node_file_index(tables.nodes, files, candidate) != file_index { continue }
         let declaration = tables.nodes[candidate]
-        if kind == NodeKind.Parameter && candidate != node && ... == name_id {
-            var belongs = false
-            for owner in 0L..tables.nodes.count() { ... }
-            if belongs { return true }
-        }
+        if kind == NodeKind.Parameter && candidate != node && compiler.token_name_ids[declaration.token] == name_id { return true }
         ... Let and For checks unchanged ...
         if kind == NodeKind.PatternBinding && ... {
-            for arm in 0L..tables.nodes.count() {
-                if tables.nodes[arm].kind == NodeKind.MatchArm && node_file_index(...) == file_index &&
-                    tables.nodes[arm].start <= declaration.start && tables.nodes[arm].end >= declaration.end &&
-                    tables.nodes[arm].start <= reference.start && tables.nodes[arm].end >= reference.end { return true }
+            for arm in candidate + 1L..owner {
+                let arm_syntax = tables.nodes[arm]
+                if arm_syntax.kind == NodeKind.MatchArm && arm - arm_syntax.subtree + 1L <= candidate &&
+                    arm_syntax.start <= reference.start && arm_syntax.end >= reference.end { return true }
             }
@@ fn check_package_name_shadows(
     for node in 0L..tables.nodes.count() {
         let syntax = tables.nodes[node]
-        if (syntax.kind == NodeKind.Function && is_top_level_function(tables, compiler, node)) || syntax.kind == NodeKind.Const {
-            let name_id = compiler.token_name_ids[syntax.token]
-            mark_reserved_name(compiler, name_id)
+        if syntax.kind == NodeKind.Const {
+            let const_name = compiler.token_name_ids[syntax.token]
+            mark_reserved_name(compiler, const_name)
+        }
+        if syntax.kind != NodeKind.Program { continue }
+        var child = compiler.child_first[node]
+        for step in 0L..syntax.subtree {
+            if child < 0L { break }
+            if tables.nodes[child].kind == NodeKind.Function {
+                let function_name = compiler.token_name_ids[tables.nodes[child].token]
+                mark_reserved_name(compiler, function_name)
+            }
+            child = compiler.child_next[child]
         }
     }
```

Two notes on the patch:

- The `mark_reserved_name(compiler, compiler.token_name_ids[...])` call has to
  read the name into a `let` first. Otherwise stage 0 rejects it as an
  overlapping `write` argument.
- The `files` and `file_index` parameters of `block_for_node` are now unused.
  A real patch should drop them.

**Why the semantics are unchanged.** The original asked whether *some*
`Function`/`Test` holds both the declaration and the reference. Functions do
not nest, so that is the reference's own owner. Its "smallest enclosing
`Block` by byte span" is the nearest `Block` ancestor.

**Equivalence check.** `cmp.sh` built every directory under tests/ (run, test,
e1, e2, e3: 683 packages) plus scalar-1000 and loop-500, with both HEAD's and
the fixed compiler. Exit status, stderr and the emitted `.ll` were compared
byte for byte, in normal and `--test` mode. The result was 685/685 identical
both times, including every `shadow_*` rejection and the `noshadow_*` test
packages.

### Alternative with a parent table (also measured)

Variant "fix" adds `node_parent: list<long, CHILD_LINK_CAPACITY>` to
`CompilerTables`, filled in `add_compiler_links`, and walks parents instead of
scanning forward.

- It produced the same identical results on all 390 tests/run packages.
- Its speed is about the same as fix3 (table below).
- It costs memory: `nlc inspect stacks` reports a data-stack worst case of
  7,248,095,393 bytes at HEAD and 7,264,095,401 bytes with the table, which is
  +16,000,008 bytes. The reservation grows by 15,998,976 bytes.
- HEAD has only about 944 MB of headroom under the `ulimit -v 8000000` cap,
  and `compiler/tests/stack_contracts.rs` pins these numbers, so the pins
  would need updating.

Use fix3 (no new table) unless a parent table is wanted for other reasons.

Pinned medians in seconds for the parent-table variant. "fix" covers only
`block_for_node`, `enclosing_owner` and `is_shadowed_function_value`. It
keeps the per-function `is_top_level_function` call, which accounts for most
of the gap to fix3 at large N.

| Package | N=1,000 | N=2,000 | N=4,000 | N=8,000 | N=10,000 |
| --- | ---: | ---: | ---: | ---: | ---: |
| scalar, fix | 0.16 | 0.24 | 0.55 | 1.87 | 2.72 |
| scalar, fix3 | 0.14 | 0.21 | 0.45 | 1.39 | 2.53 |
| loop, fix | 0.45 | 1.36 | 4.57 | - | - |
| loop, fix3 | 0.59 | 1.19 | 4.36 | - | - |

### Fixed scaling

At 1,000 to 4,000 functions the fixed compiler is within about 30% of E2b on
the scalar corpus, and each doubling costs about 1.5 to 2.2x.

Above that, both E2b and the fixed HEAD grow roughly quadratically:

- scalar 8,000 to 10,000: about 1.5x for E2b and 1.8x for fixed HEAD, against
  1.56x for a pure N² cost
- loop, each doubling: about 3.5x for E2b

These quadratic terms are older than this regression, and some arrived after
it. Profile of fix2 (an earlier variant equivalent to fix3) on the
4,000-function loop package, self time:

| Self time | Function |
| ---: | --- |
| 30% | `is_function_value_name` |
| 24% + 11% | `region_consider_binding` + `plan_function_regions` (regions.nl) |
| 17% | `nl_context_set_top` |
| 6% | `emit_function_definition` |
| 5% | `find_binding_in_scope` |

What each one does:

- **`is_function_value_name`** has `function_exists_by_name` inlined. That is
  a scan of all M nodes for every `Name` node that matches a function name:
  O(names × M). It predates E2b. A per-name boolean table filled in
  `intern_package_names`, like `enum_type_by_name`, would make it O(1).
- **Region planning** walks all bindings in the package for every function.
- **`emit_function_definition`** loops over all nodes and all bindings for
  every function.
- **`find_binding_in_scope`** scans the whole binding list.

These are follow-ups, not part of this regression. They are why fixed HEAD is
about 1.7x slower than E2b at 10,000 scalar functions (2.53 s against 1.53 s).

## Proposed regression test

Add a `check_shadow_scan_scaling` next to `check_enum_constructor_scaling` in
scripts/compare-selfhost-build.py, with the same shape:

- Generate the scalar corpus: one shared parameter name, which is what makes
  the shadow scan blow up. Unique names would hide the cubic term.
- Use N = 1,000 and N = 2,000, writing the package the same way
  `gen-selfhost-bench.py` does.
- Build each three times with `build <pkg> -o <ll>` (selfhost frontend, as the
  enum check does) and take the median.
- Assert that the time at 2,000 is at most **3x** the time at 1,000.

```python
def check_shadow_scan_scaling(stage0, root, env, work):
    """Shadow checks over many same-named parameters must not go super-quadratic."""
    scale_root = work / "shadow-scan-scaling"
    scale_root.mkdir()
    timings = {}
    for size in (1000, 2000):
        package = scale_root / f"scalar-{size}"
        package.mkdir()
        lines = [f"fn helper_{i:06d}(value: int) -> int {{ value + 1 }}" for i in range(size)]
        lines += ["fn main() {", f"    print(helper_{size - 1:06d}(3))", "}"]
        (package / "main.nl").write_text("\n".join(lines) + "\n")
        ...three timed builds, median, as in check_enum_constructor_scaling...
    if timings[2000] > 3.0 * timings[1000]:
        raise Mismatch(f"shadow check scaling: 1000={timings[1000]:.3f}s 2000={timings[2000]:.3f}s")
    return timings
```

**Margin, from the pinned medians:**

| Build | 1,000 | 2,000 | Ratio |
| --- | ---: | ---: | ---: |
| Fixed | 0.14 s | 0.21 s | 1.5x |
| HEAD | 6.58 s | 54.07 s | 8.2x |

- The 3x bound (1.5x per function) leaves 2x headroom for the fix and catches
  the regression by a factor of 2.7.
- Give each build a 120 s timeout and count a timeout as a failure. HEAD's
  2,000-function build takes about 54 s pinned and over 100 s on a busy
  machine.
- Do **not** add a 4,000-to-8,000 step under this bound. The remaining older
  quadratic terms give about 3x there (0.45 s to 1.39 s) and would make the
  check flaky.
- The test guards against super-quadratic growth in the declaration checks,
  not against the existing quadratic terms.
- Once the follow-ups above are fixed, a tighter per-function bound like the
  enum check's 1.75x could gate the loop corpus as well.
