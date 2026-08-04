#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

python3 - "$PROJECT_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
checks = {
    "examples/README.md": (
        "`ideal/`",
        "`block-editor/`",
        "`canvas/`",
        "`web/`",
        "`relay-server/`",
        "`rabbita/`",
    ),
    "docs/development/workflow.md": (
        "`loom/examples/",
        "`loom/loom/",
        "`event-graph-walker/`",
        "cd loom/",
        "cd event-graph-walker",
    ),
    "AGENTS.md": (
        "cd event-graph-walker",
    ),
    ".github/workflows/deploy-cloudflare.yml": (
        'DST="$GITHUB_WORKSPACE/examples/$EXAMPLE',
    ),
}

violations = []
for relative, forbidden in checks.items():
    path = root / relative
    text = path.read_text()
    for needle in forbidden:
        if needle in text:
            violations.append(f"{relative}: forbidden stale path {needle}")

benchmark = (root / ".github/workflows/benchmark.yml").read_text().splitlines()
for line in benchmark:
    if line.strip() == "- 'rle'":
        violations.append(".github/workflows/benchmark.yml: root-level rle filter")

if violations:
    print("stale layout paths found:", file=sys.stderr)
    print("\n".join(f"- {item}" for item in violations), file=sys.stderr)
    raise SystemExit(1)

print("ok: live layout paths match the workspace topology")
PY
