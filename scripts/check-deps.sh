#!/usr/bin/env bash
# Scope-aware dependency-rule checker.
#
# Rules (see docs/plans/2026-04-22-moonbit-workspace-reorganization.md):
#   [A] lib/*         must not import dowdiness/canopy/*
#   [B] lib/*         must not import example modules
#   [C] submodule/*   must not import dowdiness/canopy/*
#   [D] submodule/*   must not import example modules
#   [E] submodule/*   must not path-dep into dowdiness/canopy (moon.mod.json)
#
# Applies to all scopes (normal, test, wbtest) for [A]–[D].
# Exits non-zero on any violation. Intended to run in CI.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

python3 - <<'PY'
import json
import os
import re
import sys

ROOT = os.getcwd()
SKIP_DIR_NAMES = {
    ".mooncakes", ".worktrees", "_build", "_build_test_dir",
    "node_modules", ".vite", ".playwright", "dist",
    "playwright-report", "test-results",
}

def iter_files(target):
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [
            d for d in dirnames
            if d not in SKIP_DIR_NAMES and not d.startswith(".")
        ]
        if target in filenames:
            yield os.path.join(dirpath, target)

def nearest_module(path):
    d = os.path.dirname(path)
    while True:
        mmj = os.path.join(d, "moon.mod.json")
        if os.path.isfile(mmj):
            try:
                with open(mmj) as f:
                    return json.load(f).get("name", "?"), d
            except Exception:
                return "?", d
        parent = os.path.dirname(d)
        if parent == d:
            return "?", ROOT
        d = parent

IMPORT_BLOCK = re.compile(
    r'import\s*\{\s*([^}]*)\}(?:\s*for\s*"([^"]+)")?',
    re.DOTALL,
)
STR_LIT = re.compile(r'"([^"]+)"')

def parse_imports(path):
    try:
        text = open(path).read()
    except Exception:
        return
    text = re.sub(r'//[^\n]*', '', text)
    for m in IMPORT_BLOCK.finditer(text):
        body, scope = m.group(1), m.group(2) or "normal"
        for s in STR_LIT.finditer(body):
            yield scope, s.group(1)

# --- Classify each module by path ---
submodule_paths = set()
with open(os.path.join(ROOT, ".gitmodules")) as f:
    for line in f:
        line = line.strip()
        if line.startswith("path = "):
            submodule_paths.add(line[len("path = "):])

def classify(rel_path):
    rel = rel_path.replace(os.sep, "/")
    for sm in submodule_paths:
        if rel == sm or rel.startswith(sm + "/"):
            return "submodule"
    if rel.startswith("lib/"):
        return "lib"
    if rel.startswith("examples/"):
        return "example"
    if rel == ".":
        return "canopy"
    return "other"

module_category = {}  # name -> category
module_paths = {}     # name -> rel_path (first seen)
for mmj in iter_files("moon.mod.json"):
    try:
        data = json.load(open(mmj))
    except Exception:
        continue
    name = data.get("name")
    if not name:
        continue
    rel = os.path.relpath(os.path.dirname(mmj), ROOT) or "."
    module_category.setdefault(name, classify(rel))
    module_paths.setdefault(name, rel)

example_modules = {n for n, c in module_category.items() if c == "example"}

CANOPY = "dowdiness/canopy"

def is_canopy(sym):
    return sym == CANOPY or sym.startswith(CANOPY + "/")

def is_example(sym):
    return any(sym == n or sym.startswith(n + "/") for n in example_modules)

# --- Scan package imports ---
violations = []
scanned_pkgs = 0

for pkg_file in iter_files("moon.pkg"):
    scanned_pkgs += 1
    mod_name, _ = nearest_module(pkg_file)
    cat = module_category.get(mod_name, "other")
    pkg_rel = os.path.relpath(os.path.dirname(pkg_file), ROOT) or "."
    for scope, sym in parse_imports(pkg_file):
        if cat == "lib" and is_canopy(sym):
            violations.append(f"[A] lib pkg {pkg_rel} ({mod_name}, {scope}) → {sym}")
        if cat == "lib" and is_example(sym):
            violations.append(f"[B] lib pkg {pkg_rel} ({mod_name}, {scope}) → {sym}")
        if cat == "submodule" and is_canopy(sym):
            violations.append(f"[C] submodule pkg {pkg_rel} ({mod_name}, {scope}) → {sym}")
        if cat == "submodule" and is_example(sym):
            violations.append(f"[D] submodule pkg {pkg_rel} ({mod_name}, {scope}) → {sym}")

# --- Scan module path-deps ---
scanned_mods = 0
for mmj in iter_files("moon.mod.json"):
    scanned_mods += 1
    try:
        data = json.load(open(mmj))
    except Exception:
        continue
    name = data.get("name")
    cat = module_category.get(name, "other")
    if cat != "submodule":
        continue
    for dep_name, spec in (data.get("deps") or {}).items():
        # Rule E is about path-deps only; registry deps (string value, or
        # dict without "path" key) are not targeted by this rule even if the
        # name would match. If we ever want to forbid registry-deps on canopy
        # too, add rule F.
        if not (isinstance(spec, dict) and "path" in spec):
            continue
        if is_canopy(dep_name):
            violations.append(f"[E] submodule mod {name} has path-dep → {dep_name}")

# --- Report ---
if violations:
    print("Dependency rule violations:", file=sys.stderr)
    for v in violations:
        print(f"  {v}", file=sys.stderr)
    print(f"\n{len(violations)} violation(s) across {scanned_pkgs} packages, {scanned_mods} modules.",
          file=sys.stderr)
    sys.exit(1)

print(f"OK — {scanned_pkgs} packages and {scanned_mods} modules scanned, no rule violations.")
PY
