#!/usr/bin/env bash
# Shared-substrate version-drift checker (issue #441, canopy-internal slice).
#
# Invariant: every canopy workspace member that depends on dowdiness/incr must
# pin the SAME major.minor. incr's Single-Runtime constraint means a mixed-minor
# graph aborts at runtime on cross-runtime reads, so a silent skew (e.g. the
# lib/cognition TOML pin that evaded the #572 bump grep) is a latent break.
#
# Scope: canopy workspace members enumerated in moon.work (root + lib/* +
# examples/*). Submodules (loom, event-graph-walker) and worktrees are NOT
# members and are intentionally out of scope. Cross-repo (moondsp) coordination
# is deferred to a #441 follow-up.
#
# Exits non-zero if member incr minors disagree, printing the offending pins.
# Intended to run in CI as a required per-PR check, mirroring check-deps.sh.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

python3 - <<'PY'
import json
import os
import re
import sys

ROOT = os.getcwd()
TARGET = "dowdiness/incr"
MANIFEST_NAMES = ("moon.mod.json", "moon.mod")

def _import_block(text):
    # Return the body inside the first balanced `import { ... }` block.
    i = text.find("import")
    if i < 0:
        return ""
    j = text.find("{", i)
    if j < 0:
        return ""
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return text[j + 1:k]
    return text[j + 1:]

def load_manifest(path):
    """Return (name, deps) for either manifest format. deps maps dep-name to its
    spec: the version string for registry deps, or a {"path": ...} dict for
    path-deps. Extends check-deps.sh's load_manifest: the TOML branch there drops
    the `@version` (returns "registry"); here we KEEP it, since version drift is
    exactly what we check (the lib/cognition TOML pin is the #572 evader)."""
    # Unlike check-deps.sh, parse failures are FATAL here: this is a drift
    # guard, so silently dropping an unreadable member (returning {}) would be
    # a false-OK. Surface the failure instead.
    if path.endswith(".json"):
        try:
            data = json.load(open(path))
        except Exception as e:
            sys.exit(f"check-shared-substrate: cannot parse {path}: {e}")
        return data.get("name"), (data.get("deps") or {})
    # Experimental TOML moon.mod: name = "...", import { "pkg@ver", ... }.
    try:
        text = open(path).read()
    except Exception as e:
        sys.exit(f"check-shared-substrate: cannot read {path}: {e}")
    text = re.sub(r'#[^\n]*', '', text)
    name_m = re.search(r'(?m)^\s*name\s*=\s*"([^"]+)"', text)
    name = name_m.group(1) if name_m else None
    deps = {}
    for em in re.finditer(
        r'"([^"@]+)(?:@([^"]+))?"\s*(?:=\s*\{([^}]*)\})?',
        _import_block(text),
    ):
        dep_name, version, inline = em.group(1), em.group(2), em.group(3) or ""
        path_m = re.search(r'path\s*=\s*"([^"]+)"', inline)
        if path_m:
            deps[dep_name] = {"path": path_m.group(1)}
        else:
            deps[dep_name] = version or "registry"
    return name, deps

def workspace_members():
    """Member paths from moon.work (the `members = [ ... ]` string array)."""
    text = open(os.path.join(ROOT, "moon.work")).read()
    text = re.sub(r'#[^\n]*', '', text)
    m = re.search(r'members\s*=\s*\[(.*?)\]', text, re.DOTALL)
    if not m:
        sys.exit("moon.work: could not find a `members = [ ... ]` array")
    return re.findall(r'"([^"]+)"', m.group(1))

def member_manifest(member):
    base = os.path.normpath(os.path.join(ROOT, member))
    for mn in MANIFEST_NAMES:
        p = os.path.join(base, mn)
        if os.path.isfile(p):
            return p
    return None

def minor_of(version):
    """major.minor of a pin like '0.9.0' -> '0.9'. None if unparseable."""
    m = re.match(r'(\d+)\.(\d+)', version)
    return f"{m.group(1)}.{m.group(2)}" if m else None

# --- Collect incr pins across members ---
pins = []        # (member_rel, manifest_rel, version, minor)
path_deps = []   # (member_rel, manifest_rel, path) — informational, can't compare
unparseable = [] # (member_rel, manifest_rel, raw_spec)

for member in workspace_members():
    manifest = member_manifest(member)
    if manifest is None:
        continue
    _, deps = load_manifest(manifest)
    spec = deps.get(TARGET)
    if spec is None:
        continue
    manifest_rel = os.path.relpath(manifest, ROOT)
    # spec is either a version string (registry dep) or a dict. moon.mod.json
    # supports the object form {"path": ...} (rule-E shape) and {"version": ...}
    # (lib/visualizer used this earlier). Normalize before minor extraction so a
    # structured spec never reaches minor_of as a non-string.
    if isinstance(spec, dict):
        if "path" in spec:
            path_deps.append((member, manifest_rel, spec["path"]))
            continue
        version = spec.get("version")
        if not isinstance(version, str):
            unparseable.append((member, manifest_rel, spec))
            continue
        spec = version
    minor = minor_of(spec)
    if minor is None:
        unparseable.append((member, manifest_rel, spec))
        continue
    pins.append((member, manifest_rel, spec, minor))

# --- Report ---
distinct_minors = sorted({minor for _, _, _, minor in pins})

def show_pins():
    for member, manifest_rel, version, minor in sorted(pins):
        print(f"  {manifest_rel}: {TARGET} = {version}  (minor {minor})",
              file=sys.stderr)
    for member, manifest_rel, p in sorted(path_deps):
        print(f"  {manifest_rel}: {TARGET} = path-dep {p}  (not minor-comparable)",
              file=sys.stderr)

if unparseable:
    print(f"Unparseable {TARGET} pin(s):", file=sys.stderr)
    for member, manifest_rel, raw in sorted(unparseable):
        print(f"  {manifest_rel}: {TARGET} = {raw!r}", file=sys.stderr)
    sys.exit(1)

if len(distinct_minors) > 1:
    print(f"{TARGET} version drift across canopy workspace members:",
          file=sys.stderr)
    print(f"  disagreeing minors: {', '.join(distinct_minors)}", file=sys.stderr)
    show_pins()
    print("\nAll members depending on incr must pin the same major.minor "
          "(Single-Runtime constraint). Align the pins above.", file=sys.stderr)
    sys.exit(1)

if not pins:
    print(f"OK — no canopy workspace member pins {TARGET} (nothing to check).")
    sys.exit(0)

minor = distinct_minors[0]
print(f"OK — {len(pins)} member(s) agree on {TARGET} minor {minor}.")
for member, manifest_rel, version, _ in sorted(pins):
    print(f"  {manifest_rel}: {version}")
if path_deps:
    print(f"note: {len(path_deps)} path-dep member(s) skipped (not minor-comparable):")
    for member, manifest_rel, p in sorted(path_deps):
        print(f"  {manifest_rel}: {p}")
PY
