#!/usr/bin/env python3
"""Check freestanding core binaries for unresolved libc and recursive memory helpers."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


MEMORY_FUNCTIONS = {"memcpy", "memmove", "memset", "memcmp", "bcmp"}


def run(*arguments: str) -> str:
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(arguments)} failed: {result.stderr.strip()}")
    return result.stdout


def check(path: Path) -> None:
    undefined = run("nm", "-u", str(path)).strip()
    if undefined:
        raise RuntimeError(f"{path}: undefined symbols remain:\n{undefined}")

    program_headers = run("readelf", "-l", str(path))
    if re.search(r"\bINTERP\b", program_headers):
        raise RuntimeError(f"{path}: has an INTERP program header")
    dynamic = subprocess.run(
        ["readelf", "-d", str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    if re.search(r"\(NEEDED\)", dynamic.stdout):
        raise RuntimeError(f"{path}: has a dynamic NEEDED entry")

    symbols = {}
    for line in run("nm", "-n", "--defined-only", str(path)).splitlines():
        match = re.match(r"^([0-9a-fA-F]+)\s+([a-zA-Z])\s+(\S+)$", line)
        if match:
            symbols[match.group(3)] = match.group(2)
    for name in MEMORY_FUNCTIONS:
        if name not in symbols:
            raise RuntimeError(f"{path}: missing memory function {name}")
        if symbols[name].isupper():
            raise RuntimeError(f"{path}: memory function {name} is globally visible")

    disassembly = run("objdump", "-d", str(path))
    calls: dict[str, set[str]] = {}
    current = None
    for line in disassembly.splitlines():
        label = re.match(r"^[0-9a-fA-F]+ <([^>]+)>:$", line)
        if label:
            current = label.group(1)
            calls.setdefault(current, set())
            continue
        if current is None:
            continue
        instruction = re.search(r"\b(callq?|jmpq?)\s+[^<]*<([^>]+)>", line)
        if not instruction:
            continue
        opcode, target = instruction.groups()
        if opcode.startswith("jmp") and "+" in target:
            continue
        calls[current].add(target.split("+", 1)[0])

    for root in MEMORY_FUNCTIONS:
        pending = [(root, [root])]
        visited = set()
        while pending:
            function, chain = pending.pop()
            for target in calls.get(function, ()):
                if target == root:
                    raise RuntimeError(f"{path}: recursive memory-helper call chain: {' -> '.join(chain + [root])}")
                if target not in visited:
                    visited.add(target)
                    pending.append((target, chain + [target]))

    print(f"{path}: freestanding, local memory helpers, no recursive call path")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: scripts/check-core-binary.py <executable> [<executable> ...]", file=sys.stderr)
        return 2
    try:
        for argument in sys.argv[1:]:
            check(Path(argument))
    except (OSError, RuntimeError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
