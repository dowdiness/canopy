#!/usr/bin/env python3
"""Verify that every registry dependency has an explicit version.

The walk intentionally includes initialized submodules. Local path
dependencies are exempt because their source is supplied by the checkout.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {
    ".git",
    ".mooncakes",
    "_build",
    "node_modules",
    "dist",
    ".vite",
    ".playwright",
    "playwright-report",
    "test-results",
}

issues: list[str] = []
registry_count = 0


def report(path: Path, dependency: str, reason: str) -> None:
    issues.append(f"{path.relative_to(ROOT)}: {dependency}: {reason}")


def versioned(name: str, spec: object) -> bool:
    if isinstance(spec, str) and spec.strip():
        return True
    if isinstance(spec, dict) and isinstance(spec.get("version"), str):
        return bool(spec["version"].strip())
    if "@" in name:
        return bool(name.rsplit("@", 1)[1].strip())
    return False


def inspect_json(path: Path) -> None:
    global registry_count
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        report(path, "<manifest>", f"invalid JSON ({error})")
        return

    dependencies = data.get("deps") or {}
    if not isinstance(dependencies, dict):
        report(path, "<deps>", "must be an object")
        return

    for name, spec in dependencies.items():
        if isinstance(spec, dict) and "path" in spec:
            continue
        registry_count += 1
        if not versioned(name, spec):
            report(path, name, "registry dependency has no explicit version")


def inspect_toml(path: Path) -> None:
    global registry_count
    try:
        text = re.sub(r"#[^\n]*", "", path.read_text(encoding="utf-8"))
    except OSError as error:
        report(path, "<manifest>", str(error))
        return

    import_start = text.find("import")
    brace_start = text.find("{", import_start)
    if import_start < 0 or brace_start < 0:
        return

    depth = 0
    brace_end = len(text)
    for index in range(brace_start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                brace_end = index
                break

    body = text[brace_start + 1 : brace_end]
    dependency_pattern = re.compile(
        r'"([^"@]+)(?:@([^"}]+))?"\s*(?:=\s*\{([^}]*)\})?'
    )
    for match in dependency_pattern.finditer(body):
        name, dependency_version, inline = match.groups()
        if inline and re.search(r"\bpath\s*=", inline):
            continue
        registry_count += 1
        if not dependency_version or not dependency_version.strip():
            report(path, name, "registry dependency has no explicit version")


def main() -> int:
    for directory, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
        for filename in filenames:
            path = Path(directory) / filename
            if filename == "moon.mod.json":
                inspect_json(path)
            elif filename == "moon.mod":
                inspect_toml(path)

    if registry_count == 0:
        issues.append("no registry dependencies were found")
    if issues:
        print("registry manifest contract failed:", file=sys.stderr)
        for issue in issues:
            print(f"  {issue}", file=sys.stderr)
        return 1

    print(f"ok: {registry_count} registry dependencies have explicit versions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
