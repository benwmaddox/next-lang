#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# != 1 ]]; then
    echo "usage: scripts/gen-bench-corpus.sh <package-dir>" >&2
    exit 2
fi

python3 - "$repo_root" "$1" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
destination = (root / sys.argv[2]).resolve()
if destination != root and root not in destination.parents:
    raise SystemExit("benchmark package must be inside the repository")
manifest = root / "scripts/selfhost-bench-files.txt"
base = bytearray()
for row in manifest.read_text(encoding="utf-8").splitlines():
    if not row or row.startswith("#"):
        continue
    path = root / row
    data = path.read_bytes()
    base.extend(data)
    if not data.endswith(b"\n"):
        base.extend(b"\n")

target_lines_per_file = 4165
line_count = base.count(b"\n")
if line_count > target_lines_per_file:
    raise SystemExit(f"manifest has {line_count} lines; maximum is {target_lines_per_file}")
filler = b"a = b + c * d - e\n"
base.extend(filler * (target_lines_per_file - line_count))
if base.count(b"\n") != target_lines_per_file:
    raise SystemExit("benchmark line count did not reach its fixed target")

destination.mkdir(parents=True, exist_ok=True)
for old in destination.glob("*.nl"):
    old.unlink()
for index in range(13):
    (destination / f"bench-{index:02}.nl").write_bytes(base)

print(f"benchmark files=13 lines={13 * target_lines_per_file} bytes={13 * len(base)}")
PY
