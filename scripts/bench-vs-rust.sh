#!/usr/bin/env bash
# bench-vs-rust.sh [--time] [pair...]: build each bench/vs-rust pair with stage-0
# nlc and rustc, both at their highest optimisation on the same CPU target, check
# the outputs are identical, and with --time report best-of-5 wall time and peak
# RSS (pinned to one core, under the WSL bench lock), plus binary sizes.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
nlc="${NLC:-${CARGO_TARGET_DIR:-$HOME/.cache/next-lang/target}/release/nlc}"
cpu="${BENCH_CPU:-8}"
time_runs=0
pairs=()
for arg in "$@"; do
    case "$arg" in
        --time) time_runs=1 ;;
        *) pairs+=("$arg") ;;
    esac
done
if [[ ${#pairs[@]} -eq 0 ]]; then
    for dir in "$repo_root"/bench/vs-rust/*/; do pairs+=("$(basename "$dir")"); done
fi
[[ -x "$nlc" ]] || { echo "nlc not found at $nlc; build it or set NLC" >&2; exit 1; }
work="$(mktemp -d /tmp/bench-vs-rust.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT

best_of_5() {
    local best=999999 peak=0 line seconds kib
    for _ in 1 2 3 4 5; do
        line=$( { /usr/bin/time -f "%e %M" taskset -c "$cpu" "$1" >/dev/null; } 2>&1 | tail -1)
        seconds=${line% *}; kib=${line#* }
        best=$(awk -v a="$best" -v b="$seconds" 'BEGIN { print (b < a) ? b : a }')
        (( kib > peak )) && peak=$kib
    done
    echo "$best $peak"
}

run() {
    local status=0
    printf "%-16s %8s %8s %7s %8s %8s %9s %9s\n" pair nl_s rust_s ratio nl_KiB rs_KiB nl_bytes rs_bytes
    for pair in "${pairs[@]}"; do
        local dir="$repo_root/bench/vs-rust/$pair"
        NLC_OPT_LEVEL=3 "$nlc" build "$dir" -o "$work/$pair.nl" >"$work/$pair.nl.log" 2>&1 \
            || { echo "$pair: next-lang build failed (see output below)"; cat "$work/$pair.nl.log"; status=1; continue; }
        rustc --edition 2021 -C opt-level=3 -C codegen-units=1 -C lto=fat -C panic=abort -C strip=symbols \
            "$dir/main.rs" -o "$work/$pair.rs" \
            || { echo "$pair: Rust build failed"; status=1; continue; }
        "$work/$pair.nl" >"$work/$pair.nl.out"
        "$work/$pair.rs" >"$work/$pair.rs.out"
        if ! cmp -s "$work/$pair.nl.out" "$work/$pair.rs.out"; then
            echo "$pair: OUTPUT DIFFERS"; status=1; continue
        fi
        if (( time_runs )); then
            read -r nl_s nl_kib < <(best_of_5 "$work/$pair.nl")
            read -r rs_s rs_kib < <(best_of_5 "$work/$pair.rs")
            ratio=$(awk -v a="$nl_s" -v b="$rs_s" 'BEGIN { if (b > 0) printf "%.2f", a / b; else print "n/a" }')
            printf "%-16s %8s %8s %7s %8s %8s %9s %9s\n" "$pair" "$nl_s" "$rs_s" "$ratio" "$nl_kib" "$rs_kib" \
                "$(stat -c %s "$work/$pair.nl")" "$(stat -c %s "$work/$pair.rs")"
        else
            echo "$pair: builds, outputs match"
        fi
    done
    return $status
}

if (( time_runs )); then
    flock -x /home/ben/linuxbench/bench.lock bash -c "$(declare -f best_of_5 run); $(declare -p pairs work nlc cpu time_runs repo_root); run"
else
    run
fi
