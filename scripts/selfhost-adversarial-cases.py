#!/usr/bin/env python3
"""Create deterministic lexer-only comparison cases for S1a-1."""

from pathlib import Path
import os
import random
import sys


root = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)


def package(name: str, files: dict[str, bytes]) -> Path:
    directory = out / name
    directory.mkdir(parents=True, exist_ok=True)
    for existing in directory.iterdir():
        if existing.is_dir() and not existing.is_symlink():
            import shutil
            shutil.rmtree(existing)
        else:
            existing.unlink()
    for file_name, data in files.items():
        path = directory / file_name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return directory


def regular(name: str, content: bytes) -> Path:
    return package(name, {"main.nl": content})


# Separator, comment, CRLF, lone CR, delimiter suppression, braces, and every
# operator plus each ambiguous prefix in an input that the parser need not accept.
operators = (
    b"( ) { } [ ] , : ; . ? ?. ?? .. ..= -> => + - * / % +% -% *% "
    b"+= -= *= /= %= >>= = == ! != < <= > >= & && | || ^ << >>\n"
)
regular(
    "operator_matrix",
    b"\n \t\n// comment with a retained line ending\n"
    b"a\r\nb\rc\n"
    b"; ;;;\n"
    b"(\n[\n]\n)\n{\n}\n"
    b"([{}])\n"
    b"1..=2 0x 0b 1__0 123abc 7u 8L 9l\n"
    + operators,
)
regular("trailing_no_lf", b"alpha // trailing comment without newline")
regular("mismatched_nested_delimiters", b"([)]")
regular("unclosed_nested_delimiters", b"([")
regular("unclosed_brace_is_not_a_lexer_error", b"{\n")
regular("unexpected_non_ascii_byte_quirk", "é".encode("utf-8"))
regular("valid_escape_and_unicode_spellings", b'"quote: \\" slash: \\\\ n: \\n t: \\t nul: \\0 hex: \\xAf raw: \xc3\xa9\xf0\x9d\x84\x9e" b"\\xff"\n')
regular("unsupported_escape", b'"bad \\q"')
regular("hex_escape_missing", b'"\\x"')
regular("hex_escape_one_digit", b'"\\xA"')
regular("hex_escape_non_hex", b'"\\xG0"')
regular("newline_inside_string", b'"first\nsecond"')
regular("trailing_string_backslash", b'"trailing\\')
regular("unclosed_string", b'"unclosed')
regular("control_bytes_and_raw_unicode", b'"\x00\x01\x02\x07\x08\x09\x0b\x0c\x0d\x0e\x1f\xc3\xa9\xf0\x9d\x84\x9e"')

for name, raw in (
    ("invalid_utf8_overlong", b"\n\xc0\xaf"),
    ("invalid_utf8_surrogate", b"\n\xed\xa0\x80"),
    ("invalid_utf8_truncated", b"ok\xe2\x82"),
):
    regular(name, raw)

# Put the output chunk boundary inside the six-byte JSON spelling of a NUL.
chunk_count = 174762
chunk_source = b'"' + (b"\x00" * chunk_count) + b'"\n'
regular("json_chunk_boundary", chunk_source)

# Sorted package order and selection behavior: only exact .nl regular files count.
selection = out / "selection"
selection.mkdir(parents=True, exist_ok=True)
(selection / "a.nl").write_bytes(b"a\n")
(selection / ".nl").write_bytes(b"not an extension match\n")
(selection / "upper.NL").write_bytes(b"not selected\n")
(selection / "tail.nl.").write_bytes(b"not selected\n")
(selection / "folder.nl").mkdir()
(selection / "real-dir").mkdir()
(selection / "real-dir" / "nested.nl").write_bytes(b"nested\n")
(selection / "target.txt").write_bytes(b"target\n")
(selection / "linked.nl").symlink_to("target.txt")
(selection / "directory-link.nl").symlink_to("real-dir", target_is_directory=True)
(selection / "dangling.nl").symlink_to("missing-target")
fd = os.open(os.fsencode(selection) + b"/\xff.nl", os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
os.write(fd, b"raw-name\n")
os.close(fd)
for index in range(10000):
    (selection / f"ignored-{index:05}.txt").write_bytes(b"ignored")

# The file count is checked before reading any source. Empty files each emit Eof.
for count in (256, 257):
    directory = out / f"source_file_count_{count}"
    directory.mkdir(parents=True, exist_ok=True)
    for old in directory.glob("*.nl"):
        old.unlink()
    for index in range(count):
        (directory / f"file-{index:03}.nl").write_bytes(b"")

# Byte limits include the exact boundary and the first byte beyond it. Whitespace
# keeps the successful boundary cases small in token output while exercising all
# source staging bytes.
file_limit = 16 * 1024 * 1024
package_limit = 64 * 1024 * 1024
regular("source_file_bytes_n", b" " * file_limit)
regular("source_file_bytes_n1", b" " * (file_limit + 1))
package("source_package_bytes_n", {f"{i}.nl": b" " * file_limit for i in range(4)})
package(
    "source_package_bytes_n1",
    {**{f"{i}.nl": b" " * file_limit for i in range(4)}, "z.nl": b" "},
)
package(
    "source_package_bytes_before_utf8",
    {**{f"{i}.nl": b" " * file_limit for i in range(4)}, "z.nl": b"\xff"},
)

# Per-file token limits include Eof. Package token limits are checked only after
# the current file finishes lexing, so the fifth file can supply paired errors.
per_file_tokens = 1_000_000
token_source = lambda names: b"x " * names
regular("token_file_n", token_source(per_file_tokens - 1))
regular("token_file_n1", token_source(per_file_tokens))
four_full_files = {f"{letter}.nl": token_source(per_file_tokens - 1) for letter in "abcd"}
package("token_package_n", four_full_files)
package("token_package_n1", {**four_full_files, "z.nl": b""})
package("token_package_lex_error_precedes_package_limit", {**four_full_files, "z.nl": b"@"})

# Delimiter depth N/N+1 and the check-order pairs inside one file.
regular("delimiter_depth_n", b"(" * 2048 + b")" * 2048)
regular("delimiter_depth_n1", b"(" * 2049 + b")" * 2049)
regular("token_then_unclosed_delimiter", b"x " * 999999 + b"(")
regular("token_then_mismatched_delimiter", b"x " * 999999 + b")")
regular("token_then_lexer_error", b"x " * 1000000 + b"@")
regular("delimiter_error_before_token_push", b"x " * 997952 + b"(" * 2049)
package("later_file_failure_has_no_stdout", {"a.nl": b"good\n", "z.nl": b"@"})
package("earlier_lex_error_precedes_later_source_limit", {"a.nl": b"@", "z.nl": b" " * (file_limit + 1)})
package("source_limit_precedes_same_file_lexer_error", {"main.nl": b" " * file_limit + b"@"})

# Deterministic byte-level mutation corpus. The seed is written into the harness
# work directory and each mutation is its own package for exact failure capture.
seed = 0x51A1A
rng = random.Random(seed)
bases = [
    (root / "tests/parse/cases/string_escaping/main.nl").read_bytes(),
    (root / "tests/run/arithmetic/main.nl").read_bytes(),
    (root / "tests/parse/cases/byte_columns/main.nl").read_bytes(),
]
(out / "fuzz-seed.txt").write_text(f"0x{seed:x}\n", encoding="ascii")
fuzz_root = out / "fuzz"
fuzz_root.mkdir(exist_ok=True)
for case in fuzz_root.iterdir():
    if case.is_dir():
        import shutil
        shutil.rmtree(case)
for case_index in range(300):
    data = bytearray(rng.choice(bases))
    mutation_count = 1 + rng.randrange(3)
    for _ in range(mutation_count):
        if not data or rng.randrange(4) == 0:
            at = rng.randrange(len(data) + 1)
            data[at:at] = bytes([rng.randrange(256)])
        else:
            at = rng.randrange(len(data))
            if rng.randrange(5) == 0:
                del data[at]
            else:
                data[at] = rng.randrange(256)
    (fuzz_root / f"case-{case_index:03}").mkdir()
    (fuzz_root / f"case-{case_index:03}" / "main.nl").write_bytes(data)

print("generated operator, spelling, UTF-8, package-selection, boundary, paired-error, and 300 fuzz cases")
