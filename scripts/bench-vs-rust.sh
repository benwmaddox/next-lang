#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
target_dir="${CARGO_TARGET_DIR:-$HOME/.cache/next-lang/target}"
nlc="${NLC:-$target_dir/release/nlc}"
compiler="stage0"
time_runs=0
out_path=""
pairs_to_run=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --time)
            time_runs=1
            shift
            ;;
        --compiler)
            [[ $# -ge 2 ]] || { echo "missing value for --compiler" >&2; exit 2; }
            compiler="$2"
            shift 2
            ;;
        --out)
            [[ $# -ge 2 ]] || { echo "missing value for --out" >&2; exit 2; }
            out_path="$2"
            shift 2
            ;;
        *)
            pairs_to_run+=("$1")
            shift
            ;;
    esac
done

# Validate inputs
if [[ ! -x "$nlc" ]]; then
    echo "nlc not found at $nlc; run cargo build first or set NLC" >&2
    exit 2
fi

if [[ ! -x /usr/bin/time ]]; then
    echo "/usr/bin/time is required for benchmarking" >&2
    exit 2
fi

# List of benchmark pairs
all_pairs=(
    "tight_list"
    "struct_update"
    "calls"
    "increment_heavy"
    "search_heavy"
)

# If specific pairs requested, use those; otherwise use all
if [[ ${#pairs_to_run[@]} -gt 0 ]]; then
    pairs=("${pairs_to_run[@]}")
else
    pairs=("${all_pairs[@]}")
fi

# Create work directory
work="$(mktemp -d "$repo_root/.bench-vs-rust.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
work_relative="${work#"$repo_root"/}"

# Initialize results arrays
declare -A nl_times
declare -A rs_times
declare -A nl_rss
declare -A rs_rss
declare -A nl_size
declare -A rs_size
declare -A build_ok
declare -A output_match

cd "$repo_root"

echo "Building and testing benchmark pairs..."
echo

for pair in "${pairs[@]}"; do
    pair_dir="bench/vs-rust/$pair"

    if [[ ! -d "$pair_dir" ]]; then
        echo "Error: pair $pair not found at $pair_dir" >&2
        exit 2
    fi

    echo "=== $pair ==="

    # Build next-lang version
    nl_exe="$work/${pair}.nl"
    if NLC_OPT_LEVEL=3 "$nlc" build "$pair_dir" -o "$nl_exe" 2>&1; then
        build_ok["$pair.nl"]=1
        nl_size["$pair"]=$(stat -c %s "$nl_exe")
        echo "  next-lang: built ($(( ${nl_size[$pair]} / 1024 )) KiB)"
    else
        build_ok["$pair.nl"]=0
        echo "  next-lang: BUILD FAILED" >&2
        continue
    fi

    # Build Rust version
    rs_exe="$work/${pair}.rs"
    if rustc --edition 2021 -C opt-level=3 -C codegen-units=1 -C panic=abort -C strip=symbols \
        "$pair_dir/main.rs" -o "$rs_exe" 2>&1; then
        build_ok["$pair.rs"]=1
        rs_size["$pair"]=$(stat -c %s "$rs_exe")
        echo "  Rust:      built ($(( ${rs_size[$pair]} / 1024 )) KiB)"
    else
        build_ok["$pair.rs"]=0
        echo "  Rust: BUILD FAILED" >&2
        continue
    fi

    # Run both and compare output
    nl_out="$work/${pair}.nl.out"
    rs_out="$work/${pair}.rs.out"

    "$nl_exe" > "$nl_out" 2>&1 || true
    "$rs_exe" > "$rs_out" 2>&1 || true

    if diff -q "$nl_out" "$rs_out" > /dev/null 2>&1; then
        output_match["$pair"]=1
        echo "  Output:    MATCH"
    else
        output_match["$pair"]=0
        echo "  Output:    MISMATCH" >&2
        echo "    next-lang: $(head -1 "$nl_out")" >&2
        echo "    Rust:      $(head -1 "$rs_out")" >&2
        continue
    fi

    echo
done

echo
echo "Summary of builds and output matching:"
echo

# Check if all pairs succeeded
all_ok=1
for pair in "${pairs[@]}"; do
    nl_ok="${build_ok[$pair.nl]:-0}"
    rs_ok="${build_ok[$pair.rs]:-0}"
    out_ok="${output_match[$pair]:-0}"

    status="OK"
    if [[ $nl_ok -eq 0 ]]; then
        status="FAIL (next-lang build)"
        all_ok=0
    elif [[ $rs_ok -eq 0 ]]; then
        status="FAIL (Rust build)"
        all_ok=0
    elif [[ $out_ok -eq 0 ]]; then
        status="FAIL (output mismatch)"
        all_ok=0
    fi

    printf "%-20s %s\n" "$pair" "$status"
done

if [[ $all_ok -eq 0 ]]; then
    echo "Some pairs failed; not running timing benchmarks" >&2
    exit 1
fi

echo
if [[ $time_runs -eq 0 ]]; then
    echo "All pairs compiled and matched output. Run with --time to benchmark."
    exit 0
fi

echo "Running timing benchmarks (best of 5)..."
echo

# Timing run
for pair in "${pairs[@]}"; do
    nl_exe="$work/${pair}.nl"
    rs_exe="$work/${pair}.rs"
    nl_times_file="$work/${pair}.nl.times"
    rs_times_file="$work/${pair}.rs.times"

    echo "Timing $pair..."

    # next-lang timing (best of 5)
    > "$nl_times_file"
    for run in 1 2 3 4 5; do
        # Use flock to serialize benchmarks, taskset to pin CPU, /usr/bin/time to measure
        flock -x /home/ben/linuxbench/bench.lock bash -c \
            "taskset -c 8 /usr/bin/time -f '%e %M' -o '$work/${pair}.nl.tmp' '$nl_exe' > /dev/null"
        read -r elapsed rss < "$work/${pair}.nl.tmp"
        printf '%s %s\n' "$elapsed" "$rss" >> "$nl_times_file"
    done

    # Find best run
    nl_best=$(awk 'NR == 1 || $1 < best { best = $1; rss = $2 } END { print best, rss }' "$nl_times_file")
    read -r nl_elapsed nl_rss_val <<< "$nl_best"
    nl_times["$pair"]=$(printf "%.3f" "$nl_elapsed")
    nl_rss["$pair"]="$nl_rss_val"

    # Rust timing (best of 5)
    > "$rs_times_file"
    for run in 1 2 3 4 5; do
        flock -x /home/ben/linuxbench/bench.lock bash -c \
            "taskset -c 8 /usr/bin/time -f '%e %M' -o '$work/${pair}.rs.tmp' '$rs_exe' > /dev/null"
        read -r elapsed rss < "$work/${pair}.rs.tmp"
        printf '%s %s\n' "$elapsed" "$rss" >> "$rs_times_file"
    done

    # Find best run
    rs_best=$(awk 'NR == 1 || $1 < best { best = $1; rss = $2 } END { print best, rss }' "$rs_times_file")
    read -r rs_elapsed rs_rss_val <<< "$rs_best"
    rs_times["$pair"]=$(printf "%.3f" "$rs_elapsed")
    rs_rss["$pair"]="$rs_rss_val"

    printf "  next-lang: %s s, %s KiB\n" "${nl_times[$pair]}" "${nl_rss[$pair]}"
    printf "  Rust:      %s s, %s KiB\n" "${rs_times[$pair]}" "${rs_rss[$pair]}"
    echo
done

# Print results table
echo "Benchmark Results"
echo
printf "%-20s %-12s %-12s %-12s %-12s %-12s %-12s\n" "Pair" "NL Time" "RS Time" "Ratio" "NL RSS" "RS RSS" "NL Size"
printf "%s\n" "$(printf '%-20s %-12s %-12s %-12s %-12s %-12s %-12s\n' $(for ((i=0;i<7;i++)); do echo -n '-----------'; done))"

for pair in "${pairs[@]}"; do
    if [[ -z "${nl_times[$pair]:-}" ]]; then
        continue
    fi

    ratio=$(echo "scale=2; ${nl_times[$pair]} / ${rs_times[$pair]}" | bc)
    printf "%-20s %-12s %-12s %-12s %-12s %-12s %-12s KiB\n" \
        "$pair" \
        "${nl_times[$pair]}s" \
        "${rs_times[$pair]}s" \
        "${ratio}x" \
        "${nl_rss[$pair]} KiB" \
        "${rs_rss[$pair]} KiB" \
        "$(( ${nl_size[$pair]} / 1024 ))"
done

# Write markdown table if requested
if [[ -n "$out_path" ]]; then
    cat > "$out_path" <<EOF
# next-lang vs Rust Benchmarks

Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Build and Correctness

All pairs compiled successfully with matching output.

## Performance (best of 5 runs)

| Pair | next-lang | Rust | Ratio | NL RSS | RS RSS | Binary Size |
|------|-----------|------|-------|--------|--------|-------------|
EOF

    for pair in "${pairs[@]}"; do
        if [[ -z "${nl_times[$pair]:-}" ]]; then
            continue
        fi

        ratio=$(echo "scale=2; ${nl_times[$pair]} / ${rs_times[$pair]}" | bc)
        printf "| %s | %.3f s | %.3f s | %.2fx | %s KiB | %s KiB | %d KiB |\n" \
            "$pair" \
            "${nl_times[$pair]}" \
            "${rs_times[$pair]}" \
            "$ratio" \
            "${nl_rss[$pair]}" \
            "${rs_rss[$pair]}" \
            "$(( ${nl_size[$pair]} / 1024 ))" >> "$out_path"
    done

    echo "Results written to $out_path"
fi
