#!/usr/bin/env bash
# Dump every moon.pkg's import edges (scope-aware) and every module-level
# path-deps, for the whole repo minus noise. Output format is TSV; see the
# two section headers below. Handles both moon.mod.json and moon.mod (TOML).
#
# Usage: scripts/dump-deps.sh > docs/architecture/dep-graph-$(date +%F).txt
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

python3 - <<'PY'
import json
import os
import re
import sys

MANIFEST_NAMES = ("moon.mod.json", "moon.mod")

ROOT = os.getcwd()
SKIP_DIR_NAMES = {
    ".mooncakes", ".worktrees", "_build", "_build_test_dir",
    "node_modules", ".vite", ".playwright", "dist",
    "playwright-report", "test-results",
}
# Also skip hidden dirs except specific allow-list; we never want .claude, .git, etc.
ALLOWED_HIDDEN = set()

def iter_files(target_name):
    for dirpath, dirnames, filenames in os.walk(ROOT):
        # prune
        dirnames[:] = [
            d for d in dirnames
            if d not in SKIP_DIR_NAMES
            and not (d.startswith(".") and d not in ALLOWED_HIDDEN)
        ]
        if target_name in filenames:
            yield os.path.join(dirpath, target_name)

def module_for(path):
    """Walk up from path to find the nearest moon.mod.json or moon.mod (TOML); return (module_name, module_root)."""
    d = os.path.dirname(path)
    while True:
        for name in MANIFEST_NAMES:
            mp = os.path.join(d, name)
            if os.path.isfile(mp):
                try:
                    if name.endswith(".json"):
                        with open(mp) as f:
                            data = json.load(f)
                        return data.get("name", "?"), d
                    else:
                        text = open(mp).read()
                        m = re.search(r'^\s*name\s*=\s*"([^"]+)"', text, re.MULTILINE)
                        return (m.group(1), d) if m else ("?", d)
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

def parse_moon_pkg(path):
    """Yield (scope, imported_symbol) pairs."""
    try:
        with open(path, "r") as f:
            text = f.read()
    except Exception:
        return
    # Strip line comments (// ...) conservatively — don't eat inside strings.
    text = re.sub(r'//[^\n]*', '', text)
    for m in IMPORT_BLOCK.finditer(text):
        body = m.group(1)
        scope = m.group(2) or "normal"
        for s in STR_LIT.finditer(body):
            yield scope, s.group(1)

def parse_manifest_deps(path):
    """Yield (dep_name, kind, detail) for each declared dep in moon.mod.json or moon.mod (TOML).

    moon.mod.json: deps are dict entries (registry version string or {"path": …}).
    moon.mod:      deps are "pkg@version" entries inside import { … } (all registry).
    """
    try:
        if path.endswith(".json"):
            with open(path) as f:
                data = json.load(f)
            for name, spec in (data.get("deps") or {}).items():
                if isinstance(spec, str):
                    yield name, "registry", spec
                elif isinstance(spec, dict) and "path" in spec:
                    yield name, "path", spec["path"]
                else:
                    yield name, "other", json.dumps(spec)
        else:
            text = open(path).read()
            import_block = re.search(r'import\s*\{([^}]+)\}', text, re.DOTALL)
            if not import_block:
                return
            body = import_block.group(1)
            for dep_match in re.finditer(r'"([^"]+)@([^"]+)"', body):
                yield dep_match.group(1), "registry", dep_match.group(2)
    except Exception:
        pass

# -------------------------------------------------------------------
# Section A: package-level imports (moon.pkg)
# -------------------------------------------------------------------
print("### SECTION A: package-level imports (moon.pkg)")
print("# columns: module_name\tpackage_rel_path\tscope\timported_symbol")
rows_a = []
for pkg_file in iter_files("moon.pkg"):
    mod_name, mod_root = module_for(pkg_file)
    pkg_dir = os.path.dirname(pkg_file)
    pkg_rel = os.path.relpath(pkg_dir, mod_root) or "."
    for scope, sym in parse_moon_pkg(pkg_file):
        rows_a.append((mod_name, pkg_rel, scope, sym))
rows_a.sort()
for r in rows_a:
    print("\t".join(r))

print()
print("### SECTION B: module-level deps")
print("# columns: module_name\tmodule_path\tdep_name\tkind\tdetail")
rows_b = []
for manifest_name in MANIFEST_NAMES:
    for mm in iter_files(manifest_name):
        try:
            if mm.endswith(".json"):
                with open(mm) as f:
                    data = json.load(f)
            else:
                text = open(mm).read()
                data = {"name": "?"}
                m_name = re.search(r'^\s*name\s*=\s*"([^"]+)"', text, re.MULTILINE)
                if m_name:
                    data["name"] = m_name.group(1)
        except Exception:
            continue
        name = data.get("name", "?")
        mod_path = os.path.relpath(os.path.dirname(mm), ROOT) or "."
        for dep_name, kind, detail in parse_manifest_deps(mm):
            rows_b.append((name, mod_path, dep_name, kind, detail))
rows_b.sort()
for r in rows_b:
    print("\t".join(r))

print()
# -------------------------------------------------------------------
# Summary counts
# -------------------------------------------------------------------
print("### SECTION C: summary")
from collections import Counter
pkg_by_mod = Counter(r[0] for r in rows_a)
print(f"# total package-level import edges: {len(rows_a)}")
print(f"# total module-level dep edges:     {len(rows_b)}")
print(f"# packages (distinct module+path):  {len(set((r[0], r[1]) for r in rows_a))}")
print("# moon.pkg count by module:")
for mod, count in sorted(pkg_by_mod.items()):
    distinct_pkgs = len(set(r[1] for r in rows_a if r[0] == mod))
    print(f"#   {mod}\t{distinct_pkgs} packages\t{count} edges")
PY
