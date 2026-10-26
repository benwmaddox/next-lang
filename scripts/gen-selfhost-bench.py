#!/usr/bin/env python3
"""Write a valid, uniquely named E1 package for compiler timing runs."""

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--functions", type=int, default=10000)
    args = parser.parse_args()
    if not 1 <= args.functions <= 100000:
        parser.error("--functions must be between 1 and 100000")
    args.package.mkdir(parents=True, exist_ok=False)
    source = args.package / "main.nl"
    with source.open("w", encoding="utf-8", newline="\n") as output:
        for index in range(args.functions):
            output.write(f"fn helper_{index:06d}(value: int) -> int {{ value + 1 }}\n")
        output.write("fn main() {\n")
        output.write(f"    print(helper_{args.functions - 1:06d}(3))\n")
        output.write("}\n")
    print(f"functions={args.functions} source_bytes={source.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
