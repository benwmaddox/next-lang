# E3c benchmark report

Status: all E3c measurements and the committed-HEAD performance gate passed.
The full default staged-tree suite and long O1/O3 integration suite passed.

## Measurement setup

The standalone runner is [`scripts/bench-e3c-text.py`](../../scripts/bench-e3c-text.py).
It requires the fresh stage-zero release `nlc` and a selfhost compiler built
from this working tree. It takes the exclusive
`/home/ben/linuxbench/bench.lock` itself, pins measured processes to CPU 8,
and applies an 8,000,000 KiB address-space limit to child processes. Text
workload stage-zero builds use the stage-zero default C runtime; the selfhost
compiler emits core-runtime IR and the stage-zero `link-ir` command links it.
Both paths use O3. This follows the repository's standard comparison split.

The Text-heavy timing and copy microbenchmark used the same final source
revision, `7d963a47d2d217d00b56cdd413b2f4da6c96c55484cfb0fadf8bddad4b616a85`.
The Text-heavy invocation was:

```sh
TARGET_DIR=/home/ben/.cache/next-lang/target-takeover-e3c-20261028
SELFHOST_KEY=7d963a47d2d217d00b56cdd413b2f4da6c96c55484cfb0fadf8bddad4b616a85
python3 scripts/bench-e3c-text.py \
  --stage0 "$TARGET_DIR/release/nlc" \
  --selfhost "$TARGET_DIR/next-lang-test-selfhost/$SELFHOST_KEY/selfhost" \
  --target-dir "$TARGET_DIR" \
  --iterations 26000000 --print-every 106496 \
  --skip-bootstrap --skip-stack-report
```

The copy-only rerun that produced the checked-in raw CSV was:

```sh
python3 scripts/bench-e3c-text.py \
  --stage0 "$TARGET_DIR/release/nlc" \
  --selfhost "$TARGET_DIR/next-lang-test-selfhost/$SELFHOST_KEY/selfhost" \
  --target-dir "$TARGET_DIR" \
  --skip-bootstrap --skip-stack-report --copy-only
```

## Text-heavy workload

The generated workload's final measured run uses 26,000,000 iterations. Each iteration forms a
Unicode Text value from `"Ã©" + str(index)`, concatenates it between Ascii
pieces in a helper, slices the result by code-point range, compares the
returned Text with an oracle string, and feeds that result plus code-point
and byte lengths into a checksum. The input depends on the loop index, so
the text operations cannot be replaced by one constant result. It prints
sampled Text values and the final checksum. A Python
reference constructs the exact expected stdout; both compiler outputs and
every timed run must match byte-for-byte with exit status zero and empty
stderr. Five alternating stage-zero/selfhost runs report best, median, worst,
and worst-minus-best spread. The stdout SHA-256 and byte count are recorded
with the final results.
The default is 1,000,000 iterations. Its calibration medians were below 0.2
seconds, so the final run used 26,000,000 iterations to put both compiler
samples above one second. `print_every` was scaled by the same factor so the
checked output volume remained constant. The final report records the actual
iteration count and checksum.

The `render` parameter is `Text max 21 bytes max 22`: it permits a `long`
formatted in up to 20 ASCII characters plus the two-byte `Ã©` prefix. Adding
the two seven-byte Ascii literals gives the slice expression's declared upper
bound of `Text max 35 bytes max 36`; `slice` retains that receiver bound even
though this workload returns only eight code points (nine bytes).

## Text copy microbenchmark

The runner compiles a minimal package that causes the selfhost compiler to
emit one Text copy helper. It measures maximum data capacities of 8, 40, 64,
256, and 4096 bytes. At each capacity it tests an 8-byte live value and a
full-capacity value (with duplicate cases omitted at capacity 8).

Three paths are compared:

- the emitted Text helper, which copies the header fields and live bytes;
- a generic `memcpy` of the same 16-byte header plus live bytes;
- a generic `memcpy` of the entire header and maximum-capacity slot.

The live-only baseline is the closest data-volume comparison; the full-slot
baseline performs more byte movement and will be reported separately. Before
timing, each path must produce the same header and live bytes and Python checks
an independently computed checksum. The C runner then takes five interleaved
100 ms samples for each path, checking the copied value after every sample.
The full-slot path also checks the copied tail through the maximum capacity;
the other paths are checked through the live data because they leave spare
capacity untouched.

For the 4096-byte shape, stage zero's package executable cannot pass its
preflight: the frozen stage-zero runtime exits with status 1 and
`main.nl:2:5: data stack exhausted` for this full-capacity Text fixture. The
harness permits only that exact known failure for that exact shape. It still
requires stage-zero compilation to produce an executable, checks the selfhost
fixture output, and validates the specialized and both generic copies over
their expected byte ranges before and after timing.
The table reports best, median, worst, and worst-minus-best picoseconds per
copy, plus generic-to-specialized median ratios in thousandths. Ratios above
1000 indicate the generic path took longer for that measured shape.
The nine raw measurement rows and their column names are preserved in
[`E3c-copy-samples.csv`](E3c-copy-samples.csv); the table below is derived from
that CSV. The table's copy timing is from the copy-only rerun, not the earlier
full Text+copy run.

## Bootstrap and stack report

The runner measures five fresh O1 stage-zero builds of the selfhost compiler,
checking every exit status and output executable, and reports best, median,
worst, and spread. It also captures the complete output of
`nlc inspect stacks selfhost`; that static bound is reported separately from
runtime memory measurements.

## Results

The final Text+copy run exited 0. Both Text workload outputs and every timed
Text sample matched the Python oracle exactly. A later copy-only rerun also
exited 0; all copy rows passed shape, timing, ratio, checksum, and byte-copy
checks before they were written to the raw CSV.

| Compiler | Best (s) | Median (s) | Worst (s) | Spread (s) | Spread / median |
| --- | ---: | ---: | ---: | ---: | ---: |
| Stage zero | 2.863418 | 3.076602 | 3.091579 | 0.228160 | 7.42% |
| Selfhost | 1.052183 | 1.112353 | 1.127471 | 0.075288 | 6.77% |

The stage-zero / selfhost median ratio is 2.766x. The workload used 26,000,000
iterations and printed every 106,496 iterations. Expected stdout was 2,460
bytes with SHA-256 `6c0affdf997ea9327bd926285334af92f4016dd290af6ea4454fba605a275849`.

Copy times are picoseconds per copy. Each triplet is best / median / worst,
followed by worst-minus-best spread. Ratios compare median generic time with
median specialized time. Full-slot results move more bytes than the live-only
baseline, so the ratios are shown separately.

| Max bytes | Live bytes | Specialized helper (ps) | Live-slot memcpy (ps) | Full-slot memcpy (ps) | Live / special | Full / special | Checksum |
| ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| 8 | 8 | 1595 / 1777 / 1877 / 282 | 1336 / 1391 / 1518 / 182 | 1383 / 1437 / 1551 / 168 | 0.782x | 0.808x | 14927459548890318277 |
| 40 | 8 | 1809 / 1837 / 1896 / 87 | 1367 / 1377 / 1450 / 83 | 1424 / 1471 / 1494 / 70 | 0.749x | 0.800x | 14927459548890318277 |
| 40 | 40 | 2642 / 2694 / 2966 / 324 | 1352 / 1382 / 1403 / 51 | 1547 / 1570 / 1577 / 30 | 0.512x | 0.582x | 15555067626922175933 |
| 64 | 8 | 1679 / 1726 / 1774 / 95 | 1427 / 1450 / 1585 / 158 | 1368 / 1376 / 1431 / 63 | 0.840x | 0.797x | 14927459548890318277 |
| 64 | 64 | 2771 / 2845 / 3070 / 299 | 1470 / 1525 / 1536 / 66 | 1484 / 1509 / 1518 / 34 | 0.536x | 0.530x | 7197773196159502777 |
| 256 | 8 | 1878 / 1906 / 1930 / 52 | 1389 / 1460 / 1583 / 194 | 5373 / 5406 / 5469 / 96 | 0.766x | 2.836x | 14927459548890318277 |
| 256 | 256 | 5574 / 5714 / 5778 / 204 | 5446 / 5495 / 5601 / 155 | 5459 / 5540 / 5585 / 126 | 0.961x | 0.969x | 8592011107271093243 |
| 4096 | 8 | 1513 / 1618 / 1732 / 219 | 1281 / 1381 / 1469 / 188 | 15068 / 16474 / 16579 / 1511 | 0.853x | 10.181x | 14927459548890318277 |
| 4096 | 4096 | 20135 / 20225 / 20332 / 197 | 19680 / 19758 / 19878 / 198 | 19595 / 19723 / 19773 / 178 | 0.976x | 0.975x | 9042670365026346105 |

Bootstrap used five O1 stage-zero builds of the same source revision. Best / median / worst time was 10.707875 / 11.003953 / 11.271495 seconds, with 0.563620 seconds spread (5.12% of median). Each build exited 0 and produced an executable. The `nlc inspect stacks selfhost` report gave a 7,265,160,119-byte data-stack worst case and a 7,265,161,216-byte reservation; the native-stack worst case was 8,056,488 bytes and recursive. Its native call chain was `main -> compile_selfhost_package -> compile_embedded_core -> check_package_bodies -> check_one_body -> check_format_text_builtin -> format_text_width_maximum -> evaluate_collection_capacity`. The data-stack critical path passed through `emit_registered_type_helpers -> emit_type_helpers_for_kind -> emit_struct_default_helpers -> emit_expr_linear -> emit_text_literal_value -> decode_string_token -> append_unicode_byte_value`.

Bootstrap and stack inspection were completed in the first invocation for the
same final source revision; that invocation stopped later at the obsolete
stage-zero `--runtime=core` build flag. The successful Text+copy invocation
skipped those completed steps. Bootstrap, stack, Text and copy measurements
all used CPU 8, the same shared lock, and the same 8,000,000 KiB child-process
address-space limit.

| Deferred measure | Reason |
| --- | --- |
| Builder benchmark | Deferred to E3d1; `text_format` requires builders |
| `tokenize` benchmark | Deferred to E3e; text-in-collections remains unsupported |

## Committed-HEAD standard comparison

`scripts/bench-vs-rust.sh --selfhost --time` exited 0 using source commit
`5ea0a5a8cb1df78b1e16ba1738d84adeb6840fbf`, the fresh release reference, CPU 8, the shared
benchmark lock, and the 8,000,000 KiB address-space limit. It checked the
stage-zero/Rust outputs for all 11 pairs and the selfhost outputs wherever
supported. The raw table is retained in [E3c-vs-rust.csv](E3c-vs-rust.csv).
The standard script reports best-of-five wall times and peak RSS; it does not
retain individual samples or publish their spread. The standalone E3c
measurements above report their spreads separately.

| E3a3 pair | Previous selfhost best (s) | Current best (s) | Change |
| --- | ---: | ---: | ---: |
| calls | 0.22 | 0.22 | +0.00% |
| increment_heavy | 0.68 | 0.64 | -5.88% |
| struct_update | 0.83 | 0.78 | -6.02% |
| tight_list | 0.53 | 0.50 | -5.66% |

All four pass the no-greater-than-10% regression gate against the previous
E3a3 report. `struct_math` also builds and matches (selfhost best 0.32s).
`collatz`, `nested_lists`, `request_scratch`, `search_heavy`, `text_format`,
and `tokenize` remain unsupported by selfhost in this matrix and have dash
columns. In particular, `text_format` needs E3d1 builders and `tokenize` needs
E3e text collection lanes, as expected by the E3c prompt.
