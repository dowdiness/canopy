#!/usr/bin/env bash
# Manifest-driven repository topology overview for the SessionStart hook.
set -euo pipefail

repo_root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

exec python3 - "$repo_root" <<'PY'
import configparser
import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath

PRIMARY_MODULE = "dowdiness/canopy"
root = Path(sys.argv[1])


def tracked_files():
    output = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z"],
    ).decode()
    return [PurePosixPath(path) for path in output.split("\0") if path]


def read_module(manifest):
    path = root / manifest
    if manifest.name == "moon.mod.json":
        data = json.loads(path.read_text())
        return data.get("name"), data.get("source")
    text = path.read_text()
    name_match = re.search(r'(?m)^\s*name\s*=\s*"([^"]+)"', text)
    source_match = re.search(r'(?m)^\s*source\s*=\s*"([^"]+)"', text)
    return (
        name_match.group(1) if name_match else None,
        source_match.group(1) if source_match else None,
    )


# Read the filesystem here (not tracked_files/modules) because those cover only
# parent-repo manifests: manifests inside submodule working trees are not listed
# by the parent's `git ls-files`, yet those submodules can still be moon.work
# members whose module name the overview must resolve.
def module_at(directory):
    for filename in ("moon.mod", "moon.mod.json"):
        manifest = root / directory / filename
        if manifest.is_file():
            name, _ = read_module(PurePosixPath(directory) / filename)
            return name
    return None


files = tracked_files()
module_files = [
    path for path in files if path.name in ("moon.mod", "moon.mod.json")
]
package_manifests = [
    path for path in files if path.name in ("moon.pkg", "moon.pkg.json")
]

# Prefer the current manifest when both formats exist during a migration.
modules = {}
for manifest in sorted(module_files, key=lambda path: path.name == "moon.mod.json"):
    directory = manifest.parent
    if directory not in modules:
        name, source = read_module(manifest)
        modules[directory] = {
            "manifest": manifest,
            "name": name,
            "source": PurePosixPath(source) if source else None,
        }

packages = {}
for manifest in sorted(
    package_manifests,
    key=lambda path: path.name == "moon.pkg.json",
):
    packages.setdefault(manifest.parent, manifest)
package_files = list(packages.values())

primary_roots = [
    directory
    for directory, module in modules.items()
    if module["name"] == PRIMARY_MODULE
]
if len(primary_roots) != 1:
    print(
        f"error: expected one {PRIMARY_MODULE} module manifest, found "
        f"{len(primary_roots)}",
        file=sys.stderr,
    )
    raise SystemExit(1)

primary_root = primary_roots[0]
primary = modules[primary_root]


def owner_of(package):
    package_dir = package.parent
    candidates = [
        directory
        for directory in modules
        if directory == package_dir or directory in package_dir.parents
    ]
    return max(candidates, key=lambda directory: len(directory.parts), default=None)


def import_path(package):
    relative = package.parent.relative_to(primary_root)
    source = primary["source"]
    if source and (relative == source or source in relative.parents):
        relative = relative.relative_to(source)
    if str(relative) == ".":
        return PRIMARY_MODULE
    return f"{PRIMARY_MODULE}/{relative.as_posix()}"


primary_packages = sorted(
    (package for package in package_files if owner_of(package) == primary_root),
    key=lambda package: package.parent.as_posix(),
)

work_text = (root / "moon.work").read_text()
members_match = re.search(r"members\s*=\s*\[(.*?)\]", work_text, re.S)
if not members_match:
    print("error: root moon.work has no members array", file=sys.stderr)
    raise SystemExit(1)
workspace_members = [
    PurePosixPath(member)
    for member in re.findall(r'"([^"]+)"', members_match.group(1))
]

submodules = []
config = configparser.ConfigParser()
config.read(root / ".gitmodules")
for section in config.sections():
    if not section.startswith("submodule "):
        continue
    submodules.append((config[section]["path"], config[section].get("url", "")))
submodules.sort()

primary_display = "." if str(primary_root) == "." else primary_root.as_posix()
print("=== Repository Topology (live manifests) ===")
print(f"Primary module: {PRIMARY_MODULE} ({primary_display})")
print("")
print(f"=== Primary module packages ({len(primary_packages)}) ===")
for package in primary_packages:
    physical = package.parent.as_posix()
    print(f"  {import_path(package):<58} {physical}/")

print("")
print(f"=== Root workspace modules ({len(workspace_members)}) ===")
for member in workspace_members:
    normalized = PurePosixPath(".") if str(member) in (".", "./") else member
    name = module_at(normalized)
    label = name or "(manifest unavailable)"
    print(f"  {normalized.as_posix():<46} {label}")

print("")
print(f"=== Git submodules ({len(submodules)}) ===")
for path, url in submodules:
    print(f"  {path:<30} {url}")

print("")
print("=== Ownership and workspace membership are independent axes; overlap is expected ===")
print("=== Sources: moon.mod[.json], moon.pkg[.json], moon.work, .gitmodules ===")
print("=== See docs/development/module-package-map.md for placement rules ===")
PY
