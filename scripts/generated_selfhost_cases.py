"""Generate deterministic scalar and E3c text cases for selfhost comparison."""

from __future__ import annotations

import argparse
import random
from pathlib import Path
import tempfile


def generate_seeded_cases(root: Path, work: Path, count: int) -> list[tuple[str, str]]:
    if count < 0 or count > 1000:
        raise ValueError("NLC_E1_GENERATED_COUNT must be between 0 and 1000")
    rng = random.Random(0xE1)
    cases: list[tuple[str, str]] = []
    base = work / "generated"
    valid_root = base / "valid"
    invalid_root = base / "invalid"
    valid_root.mkdir(parents=True)
    invalid_root.mkdir(parents=True)
    for index in range(count):
        package = valid_root / f"case-{index:04d}"
        package.mkdir()
        seed = rng.randint(-9, 9)
        start = rng.randint(-3, 0)
        end = rng.randint(0, 3)
        wide = rng.randint(-100, 100)
        source = (
            "fn adjust(value: int) -> int {\n"
            "    if value > 0 { value * 2 } else { value - 3 }\n"
            "}\n"
            "fn double(value: long) -> long { value * 2L }\n"
            "fn main() {\n"
            f"    var total = {seed}\n"
            f"    for item in {start}..={end} {{\n"
            "        if item % 2 == 0 { total += adjust(item) } else { total -= item }\n"
            "    }\n"
            f"    print(total + {rng.randint(-2, 2)})\n"
            f"    print(double({wide}L) / 2L)\n"
            "    print(false && (1 / 0 == 0))\n"
            "}\n"
        )
        (package / "main.nl").write_text(source)
        cases.append((package.relative_to(root).as_posix(), "build"))

    diagnostics = [
        "fn main() {\n    let value = 1\n    print(vaule)\n}\n",
        "fn main() {\n    let left: int = 1\n    let right: long = 2L\n    print(left + right)\n}\n",
        "fn main() {\n    let start = 0\n    let end = 2L\n    for index in start..end {}\n}\n",
        "fn value(flag: bool) -> int {\n    if flag { return 1 }\n}\n",
        "fn first() -> int { second() }\nfn second() -> int { first() }\nfn main() {}\n",
        "fn main() {\n    let item = 1\n    let item = 2\n}\n",
        "fn main(value: int) {}\n",
        "fn main() {\n    print(2147483648 + missing)\n}\n",
        "fn main() {\n    break\n}\n",
        "fn main() {\n    for index in 0..true {}\n}\n",
    ]
    rng.shuffle(diagnostics)
    for index in range(count):
        package = invalid_root / f"case-{index:04d}"
        package.mkdir()
        (package / "main.nl").write_text(diagnostics[index % len(diagnostics)])
        cases.append((package.relative_to(root).as_posix(), "diagnose"))

    # The E3c stream is independent so adding text coverage never changes the
    # long-standing scalar corpus or its 0xE1 random sequence.
    text_rng = random.Random(0xE3C)
    text_root = base / "text"
    text_valid_root = text_root / "valid"
    text_invalid_root = text_root / "invalid"
    text_valid_root.mkdir(parents=True)
    text_invalid_root.mkdir(parents=True)

    text_literals = (
        '"A\\0é"',
        '"😀Z"',
        '"é\\0B"',
        '"ß🦊\\0"',
    )
    ascii_literals = ('"a\\0"', '"word"', '"Z"', '"\\0xy"')
    replacement_literals = ('"Q"', '"R\\0"', '"!"')
    method_replacements = ('"X"', '"\\0Y"', '"K"')

    for index in range(count):
        package = text_valid_root / f"case-{index:04d}"
        package.mkdir()
        text_literal = text_rng.choice(text_literals)
        ascii_literal = text_rng.choice(ascii_literals)
        replacement_literal = text_rng.choice(replacement_literals)
        method_replacement = text_rng.choice(method_replacements)
        slice_start = text_rng.randrange(0, 2)
        source = "\n".join(
            (
                "struct Caption {",
                "    value: Text max 8 bytes max 32",
                "}",
                "",
                "fn read_text(value: Text max 8 bytes max 32) -> long { value.len() }",
                "fn copy_text(value: Text max 8 bytes max 32) -> Text max 8 bytes max 32 { value }",
                "fn maybe_text(value: Text max 8 bytes max 32) -> Option<Text max 8 bytes max 32> {",
                "    some(value)",
                "}",
                "fn replace_text(value: write Text max 8 bytes max 32, replacement: Text max 8 bytes max 32) -> Text max 8 bytes max 32 {",
                "    value = replacement",
                "    replacement",
                "}",
                "fn replace_for_bound(value: write Text max 8 bytes max 32) -> long {",
                f"    value = {method_replacement}",
                "    1L",
                "}",
                "",
                "fn main() {",
                f"    let source: Text max 8 bytes max 32 = {text_literal}",
                f"    let ascii: Ascii max 8 = {ascii_literal}",
                "    let caption = Caption { value: source }",
                "    print(caption.value.len())",
                "    print(caption.value.byte_len())",
                "    print(caption.value.slice(0L..caption.value.len()))",
                f"    print(caption.value.slice({slice_start}L..caption.value.len()))",
                "    print(caption.value == ascii)",
                "    print(caption.value < ascii)",
                "    print(read_text(ascii))",
                "    let owned = copy_text(ascii)",
                "    print(owned)",
                "    print(owned.byte_len())",
                "    match maybe_text(caption.value) {",
                "        some(value) => print(value),",
                "        none => print(\"missing\"),",
                "    }",
                "    let digit: Ascii max 1 = str(3)",
                "    print(digit)",
                "    var combined_source: Text max 8 bytes max 32 = caption.value",
                f"    let replacement: Text max 8 bytes max 32 = {replacement_literal}",
                "    let combined = combined_source + replace_text(combined_source, replacement)",
                "    print(combined)",
                "    print(combined_source)",
                "    var receiver: Text max 8 bytes max 32 = caption.value",
                "    print(receiver.slice(0L..replace_for_bound(receiver)))",
                "    print(receiver)",
                "}",
                "",
            )
        )
        (package / "main.nl").write_text(source, encoding="utf-8", newline="\n")
        cases.append((package.relative_to(root).as_posix(), "build"))

    text_diagnostics = [
        "fn main() {\n    let too_wide: Text max 1 bytes max 4 = \"é😀\"\n    print(too_wide)\n}\n",
        "fn needs_short(value: Text max 1 bytes max 4) -> long { value.len() }\n"
        "fn main() {\n    let wide: Text max 2 bytes max 8 = \"é😀\"\n    print(needs_short(wide))\n}\n",
        "fn main() {\n    let invalid: byte = 300\n    print(invalid)\n}\n",
        "fn main() {\n    let too_many_bytes: Bytes max 1 = b\"ab\"\n    print(too_many_bytes.count())\n}\n",
        "fn main() {\n    let text: Text max 4 bytes max 16 = \"view\"\n"
        "    let view = text.bytes()\n    print(view.len())\n}\n",
    ]
    text_rng.shuffle(text_diagnostics)
    for index in range(count):
        package = text_invalid_root / f"case-{index:04d}"
        package.mkdir()
        source = text_diagnostics[index % len(text_diagnostics)]
        (package / "main.nl").write_text(source, encoding="utf-8", newline="\n")
        cases.append((package.relative_to(root).as_posix(), "diagnose"))

    return cases


def _snapshot(root: Path, work: Path, cases: list[tuple[str, str]]) -> list[tuple[str, str, bytes]]:
    prefix = work.relative_to(root)
    return [
        (
            Path(package).relative_to(prefix).as_posix(),
            kind,
            (root / package / "main.nl").read_bytes(),
        )
        for package, kind in cases
    ]


def selftest(count: int = 8) -> None:
    if count < 0 or count > 1000:
        raise ValueError("selftest count must be between 0 and 1000")
    with tempfile.TemporaryDirectory(prefix="generated-selfhost-cases-") as directory:
        root = Path(directory)
        first_work = root / "first"
        second_work = root / "second"
        first = generate_seeded_cases(root, first_work, count)
        second = generate_seeded_cases(root, second_work, count)
        if _snapshot(root, first_work, first) != _snapshot(root, second_work, second):
            raise AssertionError("generated source and package order are not deterministic")
        if len(first) != 4 * count:
            raise AssertionError(f"expected {4 * count} packages, generated {len(first)}")
        if sum(kind == "build" for _, kind in first) != 2 * count:
            raise AssertionError("expected two build packages per generated index")
        if sum(kind == "diagnose" for _, kind in first) != 2 * count:
            raise AssertionError("expected two diagnostic packages per generated index")
        if generate_seeded_cases(root, root / "empty", 0):
            raise AssertionError("count zero unexpectedly generated packages")
    print(f"generated selfhost cases deterministic: count={count}, total={4 * count}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true", help="check deterministic generated output")
    parser.add_argument("--count", type=int, default=8, help="number of generated cases per corpus")
    args = parser.parse_args()
    if not args.selftest:
        parser.error("pass --selftest to run the standalone generator check")
    selftest(args.count)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
