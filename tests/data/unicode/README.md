# E3c UTF-8 boundary coverage

No Unicode Consortium conformance files, UnicodeData.txt, SpecialCasing.txt or
their license files were present during the 2026-10-27 takeover. The E3c task
forbids network access, so this directory does not claim to vendor those data
sets. Unicode case mapping remains outside E3c.

`compiler/tests/selfhost_utf8.rs` supplies 306 original, generated boundary vectors:
every isolated byte; shortest and longest valid two-, three- and four-byte
sequences; overlong encodings; surrogate encodings; values above U+10FFFF;
bad continuation bytes; truncation; and valid prefixes before those sequences.
Rust's independent UTF-8 decoder supplies acceptance, `valid_up_to`, and
code-point-count oracles. The selfhost compiler builds the probe, whose output
also checks Bytes-to-Text and Bytes-to-Ascii conversion results.

The same integration test checks that ordinary construction emits no invariant
revalidation call. It corrupts a generated test module immediately before a
Text literal or borrowed-parameter copy assertion and requires failure kind 22
with child status 70, including construction in an ordinary function called by a test.
The corruption exists only in temporary test IR.

These vectors follow UTF-8 well-formedness rules; they are not copies of an
official Unicode test corpus and do not substitute for its later vendoring.
