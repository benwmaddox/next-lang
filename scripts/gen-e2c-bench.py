#!/usr/bin/env python3
"""Generate the E2c aggregate compile and runtime benchmark package."""

from __future__ import annotations

import argparse
from pathlib import Path


FUNCTIONS = 128
ITERATIONS = 3_000_000_000


def generate() -> str:
    lines = [
        "enum E2cBenchFailure { Invalid, Missing }",
        "struct E2cBenchCell { left: int, right: int }",
        "enum E2cBenchShape { Single(E2cBenchCell), Pair(E2cBenchCell, E2cBenchCell) }",
        "",
    ]
    for index in range(FUNCTIONS):
        lines.extend(
            [
                f"fn e2c_bench_score_{index}(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {{",
                "    let shape = input?",
                "    match shape {",
                f"        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + {index}L)",
                f"        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + {index}L)",
                "    }",
                "}",
                "",
            ]
        )
    lines.extend(
        [
            "fn e2c_bench_run() -> Result<long, E2cBenchFailure> {",
            "    var checksum: long = 0L",
            f"    for index in 0L..{ITERATIONS}L {{",
            "        let shape = if index % 2L == 0L {",
            "            E2cBenchShape.Single(E2cBenchCell { left: 1, right: 2 })",
            "        } else {",
            "            E2cBenchShape.Pair(E2cBenchCell { left: 1, right: 1 }, E2cBenchCell { left: 1, right: 2 })",
            "        }",
            "        checksum += e2c_bench_score_0(ok(shape))?",
            "    }",
            "    ok(checksum)",
            "}",
            "",
            "fn main() {",
            "    match e2c_bench_run() {",
            "        ok(value) => print(value)",
            "        err(_) => print(-1L)",
            "    }",
            "}",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package = args.output
    package.mkdir(parents=True, exist_ok=True)
    (package / "main.nl").write_text(generate(), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
