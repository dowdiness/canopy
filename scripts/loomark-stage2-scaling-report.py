#!/usr/bin/env python3
"""Summarize the final isolated Stage 2 scaling evidence."""
import argparse
import statistics
from collections import defaultdict
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("raw", nargs="+")
args = parser.parse_args()

# The isolated capture was split deterministically: small owns 1/10/50K;
# large owns 100K/250K/500K and ordinary 1.27M; final replaces only the
# structure 1.27M IR and extract cells. Never pool partial or duplicate cells.
ALLOWED = {"isolated-small.log", "isolated-large.log", "isolated-final.log"}

def selected(path, fields):
    name = Path(path).name
    if name not in ALLOWED:
        raise ValueError(f"unexpected evidence source: {path}")
    corpus = fields["corpus"]
    target = int(fields["target"])
    phase = fields["phase"]
    if name == "isolated-small.log":
        return target in {1000, 10000, 50000}
    if name == "isolated-large.log":
        return not (corpus == "structure" and target == 1270000 and phase in {"ir", "extract"})
    return corpus == "structure" and target == 1270000 and phase in {"ir", "extract"}

groups = defaultdict(list)
for path in args.raw:
    for line in open(path, encoding="utf-8"):
        if not line.startswith("SAMPLE "):
            continue
        fields = dict(part.split("=", 1) for part in line.split()[1:])
        if selected(path, fields):
            run_kind = "cold" if fields["run"].startswith("cold-") else fields["run"]
            key = (run_kind, fields["corpus"], fields["target"], fields["bytes"], fields["phase"])
            groups[key].append(float(fields["us"]))

expected = {"cold": 3, "warm": 20}
if len(groups) != 84:
    raise SystemExit(f"expected 84 complete groups, found {len(groups)}")
for key, values in groups.items():
    if len(values) != expected[key[0]]:
        raise SystemExit(f"incomplete group {key}: n={len(values)}")

def percentile(values, p):
    values = sorted(values)
    position = (len(values) - 1) * p
    lower = int(position)
    upper = min(lower + 1, len(values) - 1)
    return values[lower] + (values[upper] - values[lower]) * (position - lower)

for (run, corpus, target, size, phase), values in sorted(
    groups.items(), key=lambda item: (item[0][1], int(item[0][2]), item[0][4], item[0][0])
):
    print(
        f"run={run}\t{corpus}\ttarget={target}\tbytes={size}\tphase={phase}"
        f"\tn={len(values)}\tmedian_ms={statistics.median(values)/1000:.3f}"
        f"\tp95_ms={percentile(values, .95)/1000:.3f}\tmax_ms={max(values)/1000:.3f}"
    )
