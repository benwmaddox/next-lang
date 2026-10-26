#!/usr/bin/env python3
"""Generate the runtime's full Unicode uppercase mapping table."""

from pathlib import Path
import unicodedata


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "runtime" / "nl_unicode_upper.h"


def generate() -> str:
    version = unicodedata.unidata_version
    lines = [
        f"/* Generated from Unicode {version} uppercase mappings using Python's standard library. */",
        "/* Regenerate with scripts/gen-unicode-upper.py. */",
        f'static const char nl_unicode_version[] = "{version}";',
        "static const struct { uint32_t source; uint8_t length; uint32_t target[3]; } nl_upper_map[] = {",
    ]

    for source in range(0x110000):
        uppercase = chr(source).upper()
        if uppercase == chr(source):
            continue
        targets = [ord(character) for character in uppercase]
        if not 1 <= len(targets) <= 3:
            raise ValueError(
                f"U+{source:04X} has an uppercase mapping of {len(targets)} code points"
            )
        padded_targets = targets + [0] * (3 - len(targets))
        target_text = ", ".join(f"UINT32_C(0x{target:X})" for target in padded_targets)
        lines.append(
            f"    {{ UINT32_C(0x{source:X}), {len(targets)}, {{ {target_text} }} }},"
        )

    lines.append("};")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    with OUTPUT.open("w", encoding="ascii", newline="\n") as output:
        output.write(generate())
