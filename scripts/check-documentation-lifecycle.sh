#!/usr/bin/env bash

set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

python3 - "$repo_root" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
legacy_backlog = "docs/" + "TODO.md"
ignored = {
    "scripts/check-documentation-lifecycle.sh",
    "scripts/test-documentation-lifecycle.sh",
}

listed = subprocess.run(
    [
        "git",
        "-C",
        str(root),
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "-z",
    ],
    check=True,
    stdout=subprocess.PIPE,
).stdout.decode().split("\0")

errors: list[str] = []
if (root / legacy_backlog).exists():
    errors.append(f"remove {legacy_backlog}; GitHub Issues is the canonical active backlog")

for relative in listed:
    if (
        not relative
        or relative in ignored
        or "archive" in Path(relative).parts
    ):
        continue
    path = root / relative
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    if legacy_backlog in text:
        errors.append(f"{relative} references the retired backlog {legacy_backlog}")

terminal_status = re.compile(
    r"^\s*(?:\*\*)?Status:(?:\*\*)?\s*"
    r"(Executed|Implemented|Complete|Completed|Done|Shipped|Superseded|Product framing superseded)\b",
    re.IGNORECASE | re.MULTILINE,
)
plans_dir = root / "docs/plans"
if plans_dir.is_dir():
    for path in sorted(plans_dir.rglob("*.md")):
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError) as error:
            relative = path.relative_to(root).as_posix()
            errors.append(f"{relative} cannot be read as UTF-8: {error}")
            continue
        match = terminal_status.search(text)
        if match:
            relative = path.relative_to(root).as_posix()
            errors.append(
                f"{relative} has terminal status {match.group(1)}; move it to docs/archive/"
            )

if errors:
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    raise SystemExit(1)

print("ok: documentation lifecycle uses GitHub Issues, active plans, and archive history")
PY
