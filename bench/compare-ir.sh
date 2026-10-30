#!/bin/bash
# Optimized IR and assembly for one LangArena port from stage 0, stage 3 and LangArena's Rust, side by
# side, to see what each front end gives LLVM. Run in WSL/Linux from anywhere in the repository.
#
#   bench/compare-ir.sh <port> [rust-symbol-regex]
#
# Writes target/compare-ir/<port>/{s0,s3,rust}.{ll,s} and prints instruction counts: the whole module and
# its largest functions (ours have numbered names, Rust's are matched by the optional regex).
#
# Needs: STAGE3 (a self-hosted compiler; default: the newest .selfhost-stage-chain-*/stage3),
# target/compiler-runtime-benchmarks/stage0-ir-helper (see bench/compare-compiler-runtimes.md),
# LANGARENA (the LangArena clone; default /mnt/d/tmp/langarena), clang and cargo.
set -euo pipefail
port=${1:?usage: compare-ir.sh <port> [rust-symbol-regex]}
rust_pattern=${2:-}
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
arena=${LANGARENA:-/mnt/d/tmp/langarena}
stage3=${STAGE3:-$(ls -td .selfhost-stage-chain-*/stage3 2>/dev/null | head -1)}
helper=target/compiler-runtime-benchmarks/stage0-ir-helper
package=bench/langarena/$port
out=target/compare-ir/$port
mkdir -p "$out"
[ -f "$package/main.nl" ] || { echo "no such port: $port" >&2; exit 2; }
[ -n "$stage3" ] && [ -x "$stage3" ] || { echo "set STAGE3 to a self-hosted compiler" >&2; exit 2; }
[ -x "$helper" ] || { echo "build $helper first (bench/compare-compiler-runtimes.md)" >&2; exit 2; }

# Stage 0: its IR comes from the compiler library; optimize with the same clang the others use.
"$helper" "$package" "$out/s0.ll"
clang -O3 -S -x ir "$out/s0.ll" -o "$out/s0.s" 2>/dev/null

# Stage 3: IR from the self-hosted compiler, the C runtime and the offset stack.
"$stage3" build "$package" -o "$out/s3.ll" --runtime=c
clang -O3 -DNLC_STACK_MODE_OFFSET=1 -S -x ir "$out/s3.ll" -o "$out/s3.s" 2>/dev/null

# Rust: LangArena's own crate, built once with its max-perf profile; the assembly holds every benchmark.
rust_target=${RUST_IR_TARGET:-$HOME/.cache/langarena-rust-ir}
rust_asm=$(ls "$rust_target"/max-perf/deps/*.s 2>/dev/null | head -1 || true)
if [ -z "$rust_asm" ]; then
    echo "building LangArena's Rust once for assembly (a few minutes) ..." >&2
    (cd "$arena/rust" && cargo rustc --profile max-perf --target-dir "$rust_target" -q -- --emit=asm,llvm-ir -C strip=none 2>&1 | tail -3 >&2)
    rust_asm=$(ls "$rust_target"/max-perf/deps/*.s | head -1)
fi
cp "$rust_asm" "$out/rust.s"
cp "${rust_asm%.s}.ll" "$out/rust.ll" 2>/dev/null || true

count_instructions() { # assembly file -> instruction count
    grep -cE '^\s+[a-z][a-z0-9]*(\s|$)' "$1" | cat
}
function_sizes() { # assembly file, regex for the label (or empty = all) -> "size name", largest first
    awk -v pattern="$2" '
        /^\.L/ { next }
        /^[A-Za-z_$][A-Za-z0-9_.$@]*:/ { name = $1; sub(/:$/, "", name); next }
        /^[ \t]+[a-z][a-z0-9]*([ \t]|$)/ { if (name != "" && (pattern == "" || name ~ pattern)) size[name]++ }
        END { for (n in size) print size[n], n }' "$1" | sort -rn | head -6
}

printf '\n%-8s %14s\n' stage "asm instructions"
for stage in s0 s3 rust; do
    printf '%-8s %14d\n' "$stage" "$(count_instructions "$out/$stage.s")"
done
echo
echo "largest functions (instructions):"
echo "-- stage 0";  function_sizes "$out/s0.s" ""
echo "-- stage 3";  function_sizes "$out/s3.s" "^nl_fn_"
echo "-- rust${rust_pattern:+ matching $rust_pattern}"; function_sizes "$out/rust.s" "$rust_pattern"
echo
echo "files: $out/{s0,s3,rust}.{ll,s}"
