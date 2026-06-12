#!/usr/bin/env bash
# Scope-aware dependency-rule checker.
#
# Module-scope rules (see docs/plans/2026-04-22-moonbit-workspace-reorganization.md):
#   [A] lib/*         must not import dowdiness/canopy/*
#   [B] lib/*         must not import example modules
#   [C] submodule/*   must not import dowdiness/canopy/*
#   [D] submodule/*   must not import example modules
#   [E] submodule/*   must not path-dep into dowdiness/canopy (moon.mod.json or moon.mod)
#
# Package-level layering rules inside the dowdiness/canopy module (see
# docs/plans/2026-06-11-architecture-redesign-proposal.md, "Dependency and
# boundary rules"):
#   [F] core/** and protocol/** (incl. protocol/wire) import substrate only:
#       their canopy-internal imports must stay within {core/**, protocol/**}
#       — no language, transport, or app imports.
#   [G] editor/** must not import dowdiness/canopy/lang/* in ANY scope,
#       test/wbtest included. Dated exceptions are listed in
#       EDITOR_LANG_EXCEPTIONS below; each waiver is printed on every run
#       (never silent) and FAILS the check if it stops matching anything.
#   [H] relay/** imports only dowdiness/canopy/protocol/wire,
#       dowdiness/byte_codec, and moonbitlang/* — never editor.
#   [I] lang/** must not import dowdiness/canopy/ffi/*; a language
#       lang/<L>/** must not import another language lang/<M>/**
#       (lang/runtime is shared SPI, importable by every language);
#       lang/runtime must not import any language in normal scope
#       (test-scope fixtures are allowed).
#
# Applies to all scopes (normal, test, wbtest) for [A]–[D] and [F]–[I]
# (the one scope carve-out is [I]'s lang/runtime clause, noted above).
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

MANIFEST_NAMES = ("moon.mod.json", "moon.mod")

def iter_manifests():
    """Yield every module manifest, legacy (moon.mod.json) or experimental
    TOML (moon.mod, adopted by event-graph-walker and lib/cognition)."""
    for name in MANIFEST_NAMES:
        yield from iter_files(name)

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
    """Return (name, deps) for either manifest format. deps maps dep-name to
    its spec: the version string for registry deps, or a {"path": ...} dict for
    path-deps (matching moon.mod.json's shape so rule E works uniformly)."""
    if path.endswith(".json"):
        try:
            data = json.load(open(path))
        except Exception:
            return None, {}
        return data.get("name"), (data.get("deps") or {})
    # Experimental TOML moon.mod: name = "...", import { "pkg@ver", ... }.
    try:
        text = open(path).read()
    except Exception:
        return None, {}
    text = re.sub(r'#[^\n]*', '', text)
    name_m = re.search(r'(?m)^\s*name\s*=\s*"([^"]+)"', text)
    name = name_m.group(1) if name_m else None
    deps = {}
    for em in re.finditer(
        r'"([^"@]+)(?:@[^"]+)?"\s*(?:=\s*\{([^}]*)\})?',
        _import_block(text),
    ):
        dep_name = em.group(1)
        inline = em.group(2) or ""
        path_m = re.search(r'path\s*=\s*"([^"]+)"', inline)
        deps[dep_name] = {"path": path_m.group(1)} if path_m else "registry"
    return name, deps

def nearest_module(path):
    d = os.path.dirname(path)
    while True:
        for mn in MANIFEST_NAMES:
            mmj = os.path.join(d, mn)
            if os.path.isfile(mmj):
                name, _ = load_manifest(mmj)
                return (name or "?"), d
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
for mmj in iter_manifests():
    name, _ = load_manifest(mmj)
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

# --- Package-level layering rules within dowdiness/canopy ([F]-[I]) ---

def canopy_pkg(sym):
    """Package path inside the canopy module ('' for the root package),
    or None if sym is not a canopy import."""
    if sym == CANOPY:
        return ""
    if sym.startswith(CANOPY + "/"):
        return sym[len(CANOPY) + 1:]
    return None

def under(pkg, roots):
    return any(pkg == r or pkg.startswith(r + "/") for r in roots)

SUBSTRATE_ONLY_ROOTS = ("core", "protocol")  # [F] — protocol covers protocol/wire
RELAY_ALLOWED = (CANOPY + "/protocol/wire", "dowdiness/byte_codec")  # [H]

# [G] dated exceptions: (package, scope, import) -> reason. A waiver is
# printed on every run; a listed exception that no longer matches any
# import FAILS the check, so this list cannot rot silently.
_LAMBDA_FIXTURE_REASON = (
    "dated 2026-06-12: editor's lambda test fixture is pending replacement "
    "by a TestExpr-style neutral grammar (redesign proposal, 'Dependency "
    "and boundary rules'); remove this entry when editor tests stop "
    "importing lang/lambda"
)
EDITOR_LANG_EXCEPTIONS = {
    ("editor", "test", CANOPY + "/lang/lambda"): _LAMBDA_FIXTURE_REASON,
    ("editor", "wbtest", CANOPY + "/lang/lambda"): _LAMBDA_FIXTURE_REASON,
}
exceptions_used = set()

def check_canopy_layering(pkg, scope, sym):
    """Yield [F]-[I] violation strings for one import of a canopy package."""
    target = canopy_pkg(sym)
    if under(pkg, SUBSTRATE_ONLY_ROOTS) and target is not None \
            and not under(target, SUBSTRATE_ONLY_ROOTS):
        yield (f"[F] {pkg} ({scope}) → {sym} "
               f"(core/protocol import substrate only)")
    if under(pkg, ("editor",)) and target is not None \
            and under(target, ("lang",)):
        key = (pkg, scope, sym)
        if key in EDITOR_LANG_EXCEPTIONS:
            exceptions_used.add(key)
        else:
            yield f"[G] {pkg} ({scope}) → {sym} (editor must not import lang/*)"
    if under(pkg, ("relay",)) \
            and sym not in RELAY_ALLOWED and not sym.startswith("moonbitlang/"):
        yield (f"[H] {pkg} ({scope}) → {sym} "
               f"(relay allowlist: protocol/wire, byte_codec, moonbitlang/*)")
    if under(pkg, ("lang",)) and target is not None:
        if under(target, ("ffi",)):
            yield f"[I] {pkg} ({scope}) → {sym} (lang must not import ffi/*)"
        elif under(target, ("lang",)) and target != "lang":
            own = pkg.split("/")[1] if "/" in pkg else None
            tgt = target.split("/")[1]
            if own == "runtime":
                if tgt != "runtime" and scope == "normal":
                    yield (f"[I] {pkg} ({scope}) → {sym} "
                           f"(lang/runtime must not depend on a language)")
            elif tgt not in ("runtime", own):
                yield f"[I] {pkg} ({scope}) → {sym} (cross-language import)"

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
        if cat == "canopy":
            violations.extend(check_canopy_layering(pkg_rel, scope, sym))

# --- Scan module path-deps ---
scanned_mods = 0
for mmj in iter_manifests():
    scanned_mods += 1
    name, deps = load_manifest(mmj)
    cat = module_category.get(name, "other")
    if cat != "submodule":
        continue
    for dep_name, spec in deps.items():
        # Rule E is about path-deps only; registry deps (string value, or
        # dict without "path" key) are not targeted by this rule even if the
        # name would match. If we ever want to forbid registry-deps on canopy
        # too, add a new rule letter.
        if not (isinstance(spec, dict) and "path" in spec):
            continue
        if is_canopy(dep_name):
            violations.append(f"[E] submodule mod {name} has path-dep → {dep_name}")

# --- Report ---
for key in sorted(EDITOR_LANG_EXCEPTIONS):
    if key in exceptions_used:
        print(f"NOTE [G] waived: {key[0]} ({key[1]}) → {key[2]} — "
              f"{EDITOR_LANG_EXCEPTIONS[key]}")
    else:
        violations.append(
            f"[G] STALE exception: {key[0]} ({key[1]}) → {key[2]} no longer "
            f"matches any import — remove it from EDITOR_LANG_EXCEPTIONS")

if violations:
    print("Dependency rule violations:", file=sys.stderr)
    for v in violations:
        print(f"  {v}", file=sys.stderr)
    print(f"\n{len(violations)} violation(s) across {scanned_pkgs} packages, {scanned_mods} modules.",
          file=sys.stderr)
    sys.exit(1)

print(f"OK — {scanned_pkgs} packages and {scanned_mods} modules scanned, no rule violations.")
PY
