#!/usr/bin/env python3
"""Create deterministic lexer-only comparison cases for S1a-1."""

from pathlib import Path
import os
import random
import sys


root = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
parser_mode = len(sys.argv) > 3 and sys.argv[3] == "--parse"
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

if parser_mode:
    parser_cases = out / "parser_directed"
    parser_cases.mkdir(exist_ok=True)
    package(
        "parser_exceptional_fields",
        {
            "main.nl": (
                b'enum Choice { Empty, Value(int), Pair(int, int) }\n'
                b'struct Pair { left: int = 0, right: int }\n'
                b'type Dotted = package . nested . Item\n'
                b'type Grouped = ( int )\n'
                b'type UnitType = ( )\n'
                b'type FunctionType = fn(int, write long, grow Bytes max 4) -> Text bytes max 8 effects out, env, fs.read, fs.write, reads state . nodes, writes state.items\n'
                b'type EmptyFunctionType = fn();\n'
                b'type TextSize = Text max 12 bytes max 48\n'
                b'type TextBytes = Text bytes max 48\n'
                b'type PoolOrder = pool<int, 4, Owner>\n'
                b'type GridArguments = grid<int, 2, 3>\n'
                b'type MapArguments = map<int, long, 4>\n'
                b'type SetArguments = set<int, 4>\n'
                b'type CheckedRange = int 0..=10\n'
                b'type WrappedRange = int -2..2 wrap\n'
                b'type ClampedRange = int 0..=7 clamp\n'
                b'type NestedType = Foo<Bar<Baz>>\n'
                b'struct Box<T> { value: T }\n'
                b'const ANSWER: int = 42\n'
                b'global ready: bool prefault = true\n'
                b'global ordinary: bool = false\n'
                b'fn identity<T>(value: T) -> T { return value }\n'
                b'recursive fn recurse(value: int) -> int { return value }\n'
                b'fn no_args() {}\n'
                b'fn modes(value: int, target: write int, buffer: grow Bytes max 4) -> int { return value }\n'
                b'test "empty body" {}\n'
                b'test "escaped \\xFF" (env: Env) {\n'
                b'    let missing: UnitType\n'
                b'    var value: int = 1\n'
                b'    value = 2; value += 3; value -= 1; value *= 2; value /= 2; value %= 2; value >>= 1\n'
                b'    let shorthand = Pair { left: value, right }\n'
                b'    let chain = (shorthand).left.add(1).to_long().to_long()\n'
                b'    let empty_call = f()\n'
                b'    let qualified = Choice.Value(1)(2)\n'
                b'    let indirect = (value + 1)(2)\n'
                b'    let indexed = value[1]\n'
                b'    let gridded = value[1, 2]\n'
                b'    let optional = value?.plus(1)\n'
                b'    let fitted = value.fit<int>()\n'
                b'    let casted = (int)value\n'
                b'    let tried = result?\n'
                b'    let try_then_call = result?()\n'
                b'    let returned = return value\n'
                b'    let bare_return = return\n'
                b'    let break_value = break\n'
                b'    let continue_value = continue\n'
                b'    let unary_negative = -value\n'
                b'    let array = [1, 2, 3,]\n'
                b'    let list_value = list {}\n'
                b'    let pool_value = pool {}\n'
                b'    let map_value = map {}\n'
                b'    let set_value = set {}\n'
                b'    let queue_value = queue {}\n'
                b'    let ring_value = ring {}\n'
                b'    expect     1 + 1 == 2\n'
                b'    discard take value\n'
                b'    { let nested: int = 0 }\n'
                b'    for i in 0..=2 { continue; break }\n'
                b'    for i: int in 0..2 { discard i }\n'
                b'    for item in array { discard item }\n'
                b'    for i, x in array { discard x }\n'
                b'    for i, x, y in array { discard i }\n'
                b'    if true { 1 }\n'
                b'    if true { 1 } else if false { 2 } else { 3 }\n'
                b'    match true { true => 1, false => 0, _ => 2 }\n'
                b'    match Choice.Value(1) { Choice.Value(value) => value, Choice.Empty => 0 }\n'
                b'    match 2 { 1 => 10, _ => 0 }\n'
                b'    match Choice.Pair(1, 2) { Pair(value, _) => value, _ => 0 }\n'
                b'    match false { false => { let local = 0; local }, true => 1 }\n'
                b'    expect -1 - 2 == -3; expect 1 * 2 / 2 % 3 == 1\n'
                b'    expect 1 +% 2 -% 1 *% 3 == 0\n'
                b'    expect 1 == 1 && true || false\n'
                b'    expect 1 != 2; expect 1 < 2; expect 1 <= 2; expect 2 > 1; expect 2 >= 1\n'
                b'    expect 1 & 2 | 4 ^ 8 == 0\n'
                b'    expect 1 << 2 >> 1 == 2\n'
                b'    expect false ?? true\n'
                b'    expect !false\n'
                b'    expect 1.to_long() == 1L\n'
                b'    expect () == ()\n'
                b'    let decoded_utf8 = "\\xC3\\xA9"\n'
                b'    let decoded_invalid = "\\xFF"\n'
                b'    let decoded_truncated = "\\xE2\\x82"\n'
                b'    expect b"\\xC3\\xA9\\xFF\\xE2\\x82" == b"\\xC3\\xA9\\xFF\\xE2\\x82"\n'
                b'}\n'
            )
        },
    )
    package("parser_type_error", {"main.nl": b'test "checker is skipped" { let value: int = "wrong"; missing(value) }\n'})
    package("parser_syntax_before_later_lex_error", {"a.nl": b'test "bad" { let = 1 }\n', "z.nl": b'@\n'})
    package("parser_syntax_before_later_byte_limit", {"a.nl": b'test "bad" { let = 1 }\n', "z.nl": b' ' * (file_limit + 1)})
    package("parser_virtual_gt_and_shifts", {
        "main.nl": (
            b'test "virtual type closers" {\n'
            b'    let a: Foo<Bar<Baz>> = value\n'
            b'    let b: Foo<Bar<Baz>>=value\n'
            b'    expect 8 >> 1 == 4\n'
            b'}\n'
        )
    })
    package("parser_virtual_gt_error_column", {"main.nl": b'test "bad" { let value: Foo<Bar<Baz>>= }\n'})

    # The completed-tree walk visits the right subtree first (LIFO), but blocks
    # push the tail before statements. These packages keep competing branches
    # and the root-print exception under direct comparison.
    package("parser_tree_walk_competing", {
        "main.nl": (
            b'fn run() {\n'
            b'    print(1 + (2 + (3 + 4)))\n'
            b'    let value = if true { 1 + 2 } else { 3 + (4 + 5) }\n'
            b'    match true { _ => { let x = 1 + 2; 3 + 4 } }\n'
            b'}\n'
            b'test "walk" { let x = 1 + 2; 3 + 4 }\n'
        )
    })

    # Exercise every parser counter at its exact boundary. The cases are
    # generated from source fragments so the successful input is exactly 1,000
    # counted nodes/frames and the paired failure adds one.
    def expression_package(name: str, expression: str) -> None:
        package(name, {"main.nl": f'test "nesting" {{ {expression} }}\n'.encode("ascii")})

    for kind, make_expression in (
        ("parentheses", lambda n: "(" * n + "1" + ")" * n),
        ("unary", lambda n: "!" * n + "true"),
        ("binary", lambda n: "1 + " * n + "1"),
        ("calls", lambda n: "f(" * n + "1" + ")" * n),
        ("casts", lambda n: "(int)" * n + "1"),
    ):
        expression_package(f"parser_nesting_{kind}_1000", make_expression(1000))
        expression_package(f"parser_nesting_{kind}_1001", make_expression(1001))

    for name, call_count, paren_count in (
        ("parser_mixed_call_parentheses_1000", 499, 501),
        ("parser_mixed_call_parentheses_1001", 500, 501),
    ):
        expression_package(
            name,
            "f(" * call_count + "(" * paren_count + "1" + ")" * paren_count + ")" * call_count,
        )

    for call_count, label in ((1000, "1000"), (1001, "1001")):
        nested_for = b"for i in 0..1 {\n" * 999
        nested_call = b"f(" * call_count + b"1" + b")" * call_count
        contents = b'test "mixed stack" {\n' + nested_for + nested_call + b"\n" + b"}\n" * 1000
        package(f"parser_mixed_blocks_calls_{label}", {"main.nl": contents})

    for count, label in ((999, "1000"), (1000, "1001")):
        blocks = "for i in 0..1 {" * count + "true" + "}" * count
        expression_package(f"parser_nesting_blocks_{label}", blocks)

        nested_type = "int"
        for _ in range(count):
            nested_type = f"list<{nested_type}, 1>"
        package(f"parser_nesting_types_{label}", {"main.nl": f"type Deep = {nested_type}\n".encode("ascii")})

    # Build each level independently to avoid relying on Python recursion and
    # retain exactly the requested count of nested condition/scrutinee nodes.
    nested_if = "true"
    nested_match = "true"
    for _ in range(1000):
        nested_if = f"if {nested_if} {{ true }} else {{ false }}"
        nested_match = f"match {nested_match} {{ _ => true }}"
    expression_package("parser_nesting_if_1000", nested_if)
    nested_if = f"if {nested_if} {{ true }} else {{ false }}"
    expression_package("parser_nesting_if_1001", nested_if)
    expression_package("parser_nesting_match_1000", nested_match)
    nested_match = f"match {nested_match} {{ _ => true }}"
    expression_package("parser_nesting_match_1001", nested_match)

    def else_if_chain(count: int) -> str:
        return "if true { true } " + " ".join("else if true { true }" for _ in range(count - 1)) + " else { true }"

    expression_package("parser_nesting_else_if_1000", else_if_chain(1000))
    expression_package("parser_nesting_else_if_1001", else_if_chain(1001))

    walk_chain = "1 + " * 1000 + "1"
    expression_package("parser_walk_binary_1001", "1 + " + walk_chain)
    expression_package("parser_walk_root_print", f"print({walk_chain})")
    expression_package("parser_walk_root_ordinary", walk_chain)
    expression_package(
        "parser_walk_competing_branches",
        f"if true {{ {walk_chain} }} else {{ {walk_chain} }}",
    )
    expression_package(
        "parser_walk_statement_against_tail",
        f"if true {{ let first = {walk_chain}; {walk_chain} }} else {{ let second = {walk_chain}; {walk_chain} }}",
    )
    package("parser_walk_capacity_expression", {"main.nl": f"type Capacity = int[{walk_chain}]\n".encode("ascii")})
    package("parser_walk_function_type_expression", {"main.nl": f"type Callback = fn(int[{walk_chain}]) -> int\n".encode("ascii")})
    package(
        "parser_walk_before_later_syntax_error",
        {
            "a.nl": f'test "deep" {{ {"1 + " * 1001}1 }}\n'.encode("ascii"),
            "z.nl": b'test "bad" { let = 1 }\n',
        },
    )

    # Integer edge values cover every radix and suffix while retaining signs
    # independently from the decoded unsigned magnitude.
    max_u128 = (1 << 128) - 1
    max_i128 = (1 << 127) - 1
    min_i128_magnitude = 1 << 127
    binary_values = [0, (1 << 64) - 1, 1 << 64, min_i128_magnitude, max_u128]
    literal_lines = [
        f'    expect {value} == {value}' for value in (0, (1 << 64) - 1, 1 << 64, min_i128_magnitude, max_u128)
    ]
    literal_lines += [
        '    expect 0xffffffffffffffffL == 0xffffffffffffffffL',
        '    expect 0x10000000000000000l == 0x10000000000000000l',
        '    expect 0x80000000000000000000000000000000 == 0x80000000000000000000000000000000',
        '    expect 0xffffffffffffffffffffffffffffffff == 0xffffffffffffffffffffffffffffffff',
        '    expect 0b' + format(binary_values[1], 'b') + ' == 0b' + format(binary_values[1], 'b'),
        '    expect 0b' + format(binary_values[2], 'b') + 'l == 0b' + format(binary_values[2], 'b') + 'l',
        '    expect 0b' + format(binary_values[3], 'b') + ' == 0b' + format(binary_values[3], 'b'),
        '    expect 0b' + format(binary_values[4], 'b') + ' == 0b' + format(binary_values[4], 'b'),
        '    expect 18_446_744_073_709_551_615L == 18446744073709551615',
        '    expect -0 == 0',
        f'    expect -{min_i128_magnitude} == -{min_i128_magnitude}',
        f'    expect {max_i128} == {max_i128}',
    ]
    package("parser_integer_edges", {
        "main.nl": (
            'type SignedEdges = int -170141183460469231731687303715884105728..=170141183460469231731687303715884105727\n'
            'type NegativeZeroRange = int -0..=0\n'
            'test "integer edges" {\n' + '\n'.join(literal_lines) + '\n}\n'
        ).encode("ascii")
    })
    for name, literal in (
        ("separator_trailing", "1_"),
        ("separator_leading", "_1"),
        ("separator_double", "1__0"),
        ("hex_prefix_empty", "0x"),
        ("hex_prefix_separator", "0x_FF"),
        ("hex_bad_digit", "0x1G"),
        ("binary_bad_digit", "0b2"),
        ("binary_prefix_empty", "0b"),
        ("decimal_bad_suffix", "123abc"),
        ("magnitude_overflow", str(1 << 128)),
    ):
        package(f"parser_bad_integer_{name}", {"main.nl": f'test "bad" {{ {literal} }}\n'.encode("ascii")})

    package("parser_stack_peak_units", {"main.nl": b'fn work() {}\ntest "units" { expect stack_peak(work) < 2 MB }\n'})
    package("parser_stack_peak_overflow", {"main.nl": f'fn work() {{}}\ntest "overflow" {{ expect stack_peak(work) < {max_u128} GB }}\n'.encode("ascii")})
    long_name = "generic" + "x" * 400
    package("parser_long_duplicate_generic", {"main.nl": f'fn f<{long_name}, {long_name}>() {{}}\n'.encode("ascii")})
    effect_name = "Unknown" + "y" * 400
    package("parser_long_unknown_effect", {"main.nl": f'type Callback = fn() effects {effect_name}\n'.encode("ascii")})

    # An output token is deliberately sized so decoded NUL escaping crosses the
    # 1 MiB write buffer after earlier tree rows have already been emitted.
    nul_count = 174762
    package("parser_decoded_output_boundary", {"main.nl": b'test "escape boundary" { b"' + (b'\\0' * nul_count) + b'" }\n'})

    # Parse limits are run with no dump flags: Rust counts trees even when the
    # caller requests no dump. The terminal break keeps every integer as a
    # statement, giving two nodes per repeated source line.
    node_root = parser_cases / "parser_node_limits_no_dump"
    node_limit_n1_files = None
    for count, extra_unary, case_name in (
        (999992, False, "n"),
        (999992, True, "n1"),
    ):
        per_file = [count // 4] * 4
        for index in range(count % 4):
            per_file[index] += 1
        files = {}
        unary_pending = extra_unary
        for file_index, line_count in enumerate(per_file):
            if unary_pending:
                lines = b'!true\n' + b'1\n' * (line_count - 1)
                unary_pending = False
            else:
                lines = b'1\n' * line_count
            files[f"{file_index}.nl"] = f'test "node-{file_index}" {{\n'.encode() + lines + b'break\n}\n'
        package(f"parser_node_limit_{case_name}", files)
        if case_name == "n1":
            node_limit_n1_files = files

    # The node walk only runs after a file parses successfully. Keep a package
    # that has already built over-limit candidate nodes before the final syntax
    # error, and a paired node/work overflow where the node diagnostic must win.
    syntax_before_node = dict(node_limit_n1_files)
    last_file = sorted(syntax_before_node)[-1]
    syntax_before_node[last_file] = syntax_before_node[last_file].replace(
        b'break\n}\n', b'let = 1\nbreak\n}\n'
    )
    package("parser_syntax_before_node_limit", syntax_before_node)
    nodes_and_work = dict(node_limit_n1_files)
    file_limit = 16 * 1024 * 1024
    for file_name, contents in nodes_and_work.items():
        nodes_and_work[file_name] = contents + b" " * (file_limit - len(contents))
    package("parser_node_limit_before_work", nodes_and_work)

    work_lines = 225000
    work_tokens = 2 * work_lines + 9
    work_nodes = 2 * work_lines + 4
    work_edges = work_nodes - 1
    target_bytes = 72000000 - 4 * (work_tokens + work_nodes + work_edges)
    work_root = parser_cases / "parser_work_limits_no_dump"
    source_files = {}
    for file_index in range(4):
        prefix = f'test "work-{file_index}" {{\n'.encode("ascii")
        body = b'1\n' * work_lines + b'break\n}\n'
        source_files[f"{file_index}.nl"] = prefix + body
    base_bytes = sum(map(len, source_files.values()))
    padding = target_bytes - base_bytes
    for file_index, name in enumerate(sorted(source_files)):
        source_files[name] += b' ' * (padding // 4 + (1 if file_index < padding % 4 else 0))
    package("parser_work_limit_n", source_files)
    over_files = dict(source_files)
    over_files["3.nl"] += b' '
    package("parser_work_limit_n1", over_files)

    # A fresh deterministic parser mutation seed complements S1a-1's lexer
    # mutations; these run only with --tree to compare decoded fields.
    parse_seed = 0x51A2A
    parse_rng = random.Random(parse_seed)
    parser_fuzz_root = out / "parser-fuzz"
    parser_fuzz_root.mkdir(exist_ok=True)
    for case in parser_fuzz_root.iterdir():
        if case.is_dir():
            import shutil
            shutil.rmtree(case)
    parser_bases = [
        b'test "escape \\xFF" { let x: Foo<Bar<Baz>>=value; expect 0xFF +% 1 == 0 }\n',
        b'fn f(x: int) -> int { if x > 0 { x } else if x == 0 { 0 } else { -x } }\n',
        b'test "match" { match true { true => Choice.One(1), false => Choice.Empty } }\n',
        b'type Callback = fn(grow Bytes max 4) -> Text bytes max 8 effects reads state.items\n',
    ]
    (out / "parser-fuzz-seed.txt").write_text(f"0x{parse_seed:x}\n", encoding="ascii")
    for case_index in range(300):
        data = bytearray(parse_rng.choice(parser_bases))
        mutation_count = 1 + parse_rng.randrange(4)
        for _ in range(mutation_count):
            if not data or parse_rng.randrange(4) == 0:
                at = parse_rng.randrange(len(data) + 1)
                data[at:at] = bytes([parse_rng.randrange(256)])
            else:
                at = parse_rng.randrange(len(data))
                if parse_rng.randrange(5) == 0:
                    del data[at]
                else:
                    data[at] = parse_rng.randrange(256)
        case = parser_fuzz_root / f"case-{case_index:03}"
        case.mkdir()
        (case / "main.nl").write_bytes(data)

print("generated lexer and parser operator, spelling, UTF-8, field, boundary, paired-error, and deterministic mutation cases")
