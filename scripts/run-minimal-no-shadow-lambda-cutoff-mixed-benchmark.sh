#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
PACKAGE=examples/spikes/minimal_no_shadow_lambda_projection/main
CYCLES=3
P13=cutoff_benchmark.mbt
P14=mixed_cutoff_benchmark.mbt
CLEANUP=

if [[ ${1:-} == --record ]]; then
  [[ $# -eq 2 ]] || { echo 'usage: run-minimal-no-shadow-lambda-cutoff-mixed-benchmark.sh [--record DIR]' >&2; exit 2; }
  OUT=$2
  rm -rf "$OUT"
  mkdir -p "$OUT"
elif [[ $# -eq 0 ]]; then
  OUT=$(mktemp -d)
  CLEANUP=$OUT
else
  echo 'usage: run-minimal-no-shadow-lambda-cutoff-mixed-benchmark.sh [--record DIR]' >&2
  exit 2
fi
trap '[[ -z "$CLEANUP" ]] || rm -rf "$CLEANUP"' EXIT

printf '%s\n' '== P1.4 behavioral precondition =='
./scripts/run-minimal-no-shadow-lambda-projection.sh >/dev/null
printf '%s\n' 'P1.2 behavioral gate: PASS'

python3 - "$ROOT" "$PACKAGE" "$P13" "$P14" "$OUT" "$CYCLES" <<'PY'
import json
import os
import re
import statistics
import subprocess
import sys
from pathlib import Path

root, package, p13, p14, output, cycles = sys.argv[1:]
cycles = int(cycles)
out = Path(output)
out.mkdir(parents=True, exist_ok=True)
TIME = re.compile(r'^\s*([0-9.]+)\s+(ns|µs|ms)\s+±', re.MULTILINE)
TEST = re.compile(r'\("P1\.[34] ([^"]+)"\) ok')
UNITS = {"ns": 0.001, "µs": 1.0, "ms": 1000.0}
# Each tuple is (file, benchmark index). A=AlwaysChanged, B=Eq cutoff.
scenarios = {
    "medium/whitespace": {"A": (p13, 3), "B": (p13, 2)},
    "large/whitespace": {"A": (p13, 4), "B": (p13, 5)},
    "medium/early-changing": {"A": (p14, 0), "B": (p14, 1)},
    "medium/late-changing": {"A": (p14, 2), "B": (p14, 3)},
    "large/early-changing": {"A": (p14, 4), "B": (p14, 5)},
    "large/late-changing": {"A": (p14, 6), "B": (p14, 7)},
    "medium/mixed-50": {"A": (p14, 8), "B": (p14, 9)},
    "large/mixed-50": {"A": (p14, 10), "B": (p14, 11)},
}
policies = {"A": "always_changed", "B": "eq_cutoff"}
records = []

def invoke(target, file_name, index, raw):
    command = [
        "moon", "bench", "--release", "--target", target,
        "-p", package, "-f", file_name, "-i", str(index),
    ]
    completed = subprocess.run(
        command,
        cwd=root,
        env={**os.environ, "NEW_MOON_MOD": "0"},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    text = completed.stdout
    if "Total tests: 1, passed: 1, failed: 0." not in text:
        raise SystemExit(f"unexpected benchmark result: {target} {file_name} {index}")
    timing = TIME.search(text)
    test = TEST.search(text)
    if timing is None or test is None:
        raise SystemExit(f"could not parse: {target} {file_name} {index}")
    mean_us = float(timing.group(1)) * UNITS[timing.group(2)]
    raw.write(f"\n===== file={file_name} index={index} name={test.group(1)} =====\n{text}")
    return mean_us

for target in ("native", "js"):
    with (out / f"{target}.raw.log").open("w") as raw:
        print(f"\n== {target}: preliminary process per scenario/policy ==")
        for scenario, arms in scenarios.items():
            for arm in ("A", "B"):
                file_name, index = arms[arm]
                value = invoke(target, file_name, index, raw)
                print(f"preliminary {scenario:26} {policies[arm]:14} {value:9.2f} µs")
        for cycle in range(cycles):
            order = ("A", "B", "B", "A") if cycle % 2 == 0 else ("B", "A", "A", "B")
            print(f"\n{target} cycle {cycle + 1}: {''.join(order)}")
            for scenario, arms in scenarios.items():
                values = []
                for position, arm in enumerate(order):
                    file_name, index = arms[arm]
                    value = invoke(target, file_name, index, raw)
                    records.append({
                        "target": target,
                        "scenario": scenario,
                        "cycle": cycle + 1,
                        "position": position + 1,
                        "arm": arm,
                        "policy": policies[arm],
                        "mean_us": value,
                    })
                    values.append(f"{arm}={value:.2f}")
                print(f"{scenario:26} " + " ".join(values))

(out / "abba-records.json").write_text(json.dumps(records, indent=2) + "\n")
with (out / "abba-records.tsv").open("w") as file:
    file.write("target\tscenario\tcycle\tposition\tarm\tpolicy\tmean_us\n")
    for record in records:
        file.write("\t".join(str(record[key]) for key in (
            "target", "scenario", "cycle", "position", "arm", "policy", "mean_us"
        )) + "\n")

summary = []
for target in ("native", "js"):
    for scenario in scenarios:
        subset = [r for r in records if r["target"] == target and r["scenario"] == scenario]
        deltas = []
        percentages = []
        for cycle in range(1, cycles + 1):
            ordered = sorted(
                (r for r in subset if r["cycle"] == cycle),
                key=lambda r: r["position"],
            )
            for offset in (0, 2):
                pair = ordered[offset:offset + 2]
                a = next(r["mean_us"] for r in pair if r["arm"] == "A")
                b = next(r["mean_us"] for r in pair if r["arm"] == "B")
                deltas.append(b - a)
                percentages.append((b - a) / a * 100.0)
        baseline = [r["mean_us"] for r in subset if r["arm"] == "A"]
        candidate = [r["mean_us"] for r in subset if r["arm"] == "B"]
        summary.append({
            "target": target,
            "scenario": scenario,
            "baseline_median_us": statistics.median(baseline),
            "candidate_median_us": statistics.median(candidate),
            "median_paired_delta_us": statistics.median(deltas),
            "median_pair_percentage": statistics.median(percentages),
            "paired_delta_min_us": min(deltas),
            "paired_delta_max_us": max(deltas),
            "candidate_wins": sum(delta < 0 for delta in deltas),
            "pairs": len(deltas),
        })

break_even = []
for target in ("native", "js"):
    for size in ("medium", "large"):
        rows = {
            row["scenario"].split("/", 1)[1]: row
            for row in summary
            if row["target"] == target and row["scenario"].startswith(size + "/")
        }
        benefit = -rows["whitespace"]["median_paired_delta_us"]
        early_overhead = rows["early-changing"]["median_paired_delta_us"]
        late_overhead = rows["late-changing"]["median_paired_delta_us"]
        point_overhead = max(0.0, early_overhead, late_overhead)
        observed_worst_overhead = max(
            0.0,
            rows["early-changing"]["paired_delta_max_us"],
            rows["late-changing"]["paired_delta_max_us"],
        )
        point_threshold = None
        observed_worst_threshold = None
        if benefit > 0:
            point_threshold = point_overhead / (benefit + point_overhead)
            observed_worst_threshold = observed_worst_overhead / (
                benefit + observed_worst_overhead
            )
        break_even.append({
            "target": target,
            "size": size,
            "equivalent_edit_benefit_us": benefit,
            "early_changing_median_overhead_us": early_overhead,
            "late_changing_median_overhead_us": late_overhead,
            "point_changing_overhead_us": point_overhead,
            "point_break_even_equivalent_edit_rate": point_threshold,
            "observed_worst_pair_overhead_us": observed_worst_overhead,
            "observed_worst_pair_break_even_rate": observed_worst_threshold,
            "mixed_50_delta_us": rows["mixed-50"]["median_paired_delta_us"],
            "mixed_50_candidate_wins": rows["mixed-50"]["candidate_wins"],
            "mixed_50_pairs": rows["mixed-50"]["pairs"],
        })

(out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
(out / "break-even.json").write_text(json.dumps(break_even, indent=2) + "\n")
lines = [
    "# P1.4 semantic-changing and mixed cutoff results",
    "",
    f"Cycles: {cycles}; six adjacent AB/BA pairs per target/scenario. Preliminary invocations use separate processes; every recorded moon bench process performs its own intra-process batches.",
    "",
    "| Target | Scenario | Baseline median | Candidate median | Median paired delta | Median pair % | Range | Wins |",
    "|---|---|---:|---:|---:|---:|---:|---:|",
]
for row in summary:
    lines.append(
        f"| {row['target']} | {row['scenario']} | {row['baseline_median_us']:.2f} µs | "
        f"{row['candidate_median_us']:.2f} µs | {row['median_paired_delta_us']:+.2f} µs | "
        f"{row['median_pair_percentage']:+.2f}% | "
        f"{row['paired_delta_min_us']:+.2f}…{row['paired_delta_max_us']:+.2f} µs | "
        f"{row['candidate_wins']}/{row['pairs']} |"
    )
lines += [
    "",
    "## Break-even sensitivity",
    "",
    "Uses p > H / (B + H). The point estimate uses the larger positive median changing overhead. The observed-worst sensitivity uses the largest positive paired changing delta. Neither is a confidence bound or production edit distribution.",
    "",
    "| Target | Size | B | Early median H | Late median H | Point p | Observed-worst H | Sensitivity p | Mixed-50 delta | Mixed wins |",
    "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|",
]
for row in break_even:
    point = "n/a" if row["point_break_even_equivalent_edit_rate"] is None else f"{row['point_break_even_equivalent_edit_rate'] * 100.0:.2f}%"
    sensitivity = "n/a" if row["observed_worst_pair_break_even_rate"] is None else f"{row['observed_worst_pair_break_even_rate'] * 100.0:.2f}%"
    lines.append(
        f"| {row['target']} | {row['size']} | {row['equivalent_edit_benefit_us']:.2f} µs | "
        f"{row['early_changing_median_overhead_us']:+.2f} µs | "
        f"{row['late_changing_median_overhead_us']:+.2f} µs | {point} | "
        f"{row['observed_worst_pair_overhead_us']:.2f} µs | {sensitivity} | "
        f"{row['mixed_50_delta_us']:+.2f} µs | {row['mixed_50_candidate_wins']}/{row['mixed_50_pairs']} |"
    )
(out / "SUMMARY.md").write_text("\n".join(lines) + "\n")
print("\n" + "\n".join(lines))
PY

printf '\nP1.4 artifacts: %s\n' "$OUT"
printf '%s\n' 'P1.4 RESULT: semantic-changing overhead, mixed workload, and fixture break-even recorded. No production policy is selected.'
