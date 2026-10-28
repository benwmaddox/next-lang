# E3c byte fixture handoff

These new packages cover the byte-literal and cast requirements from
`prompt-E3c.md`. Existing `s0fix5_byte_*` packages remain as regressions for
`Bytes.push` bounds; these fixtures do not edit them.

| Package | Contract |
| --- | --- |
| `e3c_byte_array_literals` | Initialize `byte[4]` from the required hex/decimal literal list; read it and pass it to a function. |
| `e3c_byte_list_literals` | Same checks for `list<byte, 4>`. |
| `e3c_byte_bytes_literal` | Initialize `Bytes max 4` from a byte literal list and read its bytes. |
| `e3c_byte_checked_cast` | Checked casts at 0 and 255; `unchecked` casts preserve the low eight bits at 256 and 511; pass `byte` through a typed function parameter and return. |
| `e3c_byte_cast_negative`, `e3c_byte_cast_too_large` | Run-time checked casts from -1 and 256 fail the job. |
| `e3c_byte_literal_out_of_range` | Reject the literal element 256 at build time and name it in the selfhost diagnostic. |

## Stage-0 probes

The frozen stage-0 release binary at
`/home/ben/.cache/next-lang/target/release/nlc` produced `31, 139, 8, 0`
for both the `byte[4]` and `list<byte, 4>` fixtures. It accepts the
out-of-range byte-array literal `[1, 256, 3]` and prints `256`; E3c explicitly
requires a build error for that element, so that fixture uses the `rejects`
class. The selfhost rejection must be a real error and its explicit
`expected.selfhost.stderr` oracle must name `256`.

The binary `/home/ben/.cache/next-lang/target/release/nlc` rejects `(byte)x`
and `unchecked((byte)x)` while parsing, and rejects `[...]` as a `Bytes` value
without a collection annotation. Those forms therefore use checked-in
`expected.*` output files.

## Validation status

Stage-0 probes with `/home/ben/.cache/next-lang/target/release/nlc run` gave
`31, 139, 8, 0` for each byte-array/list fixture and `256` for the out-of-range
byte array. The expected-class cast fixtures use hand-written outputs because
stage 0 rejects their cast syntax while parsing.

The full focused comparison passed against fresh stage-0 references:

```text
timeout 300 scripts/compare-selfhost.sh --build \
    --only 'tests/e3/e3c_byte_*' --no-reference-cache
O1: built and matching 2; expected outputs matched 4; rejects 1; mismatches 0
```

This confirms the checked casts accept 0 and 255, the unchecked casts keep the
low eight bits of 256 and 511, and checked casts from -1 and 256 fail with
`bad cast`. The `rejects` fixture passes with the exact diagnostic
`main.nl:2:32: error: byte literal '256' is outside 0..255`.
