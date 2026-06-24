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
# boundary rules"). "Language grammar" below = the out-of-module grammar
# modules in GRAMMAR_MODULES (dowdiness/lambda, dowdiness/json,
# dowdiness/markdown) — importing one is a language import even though it
# bypasses dowdiness/canopy/lang.
#   [F] core/** and protocol/** (incl. protocol/wire) import substrate only:
#       canopy-internal imports must stay within {core/**, protocol/**},
#       and no language grammar.
#   [G] editor/** must not import dowdiness/canopy/lang/* or a language
#       grammar in ANY scope, test/wbtest included.
#   [H] relay/** imports only protocol/wire, byte_codec, its own subtree,
#       and moonbitlang/* — never editor.
#   [I] lang/** must not import dowdiness/canopy/ffi/*; a language
#       lang/<L>/** must not import another language's packages or grammar
#       (lang/runtime is shared SPI, importable by every language);
#       lang/runtime itself must not import any language in normal scope
#       (test-scope fixtures are allowed).
#
# Dated waivers live in the EXCEPTIONS table below, keyed
# (rule, package, scope, import). Each waiver is printed on every run
# (never silent) and FAILS the check once it stops matching anything.
#
# All scopes (normal, test, wbtest) are checked for [A]-[D] and [F]-[I];
# the scope carve-outs are [I]'s lang/runtime clause and the scope-keyed
# EXCEPTIONS entries.
#
# NOT enforced here (deliberate gaps — do not read this lint as the full
# proposal section):
#   - the general "L(n) depends only on L(n-1)" layering (only the named
#     pairs above are checked);
#   - the positive clause "lang/<L> depends on lang/runtime + its grammar
#     only" — lang/* importing editor/core/protocol is the current S3
#     design and passes;
#   - editor/** importing ffi/*, and ffi/** imports generally;
#   - "ffi/<L> is the only home of editor-state JSON serialization"
#     (not expressible as an import rule).
#
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

def under(path, roots):
    """True when path equals a root or is nested under one (segment-aware)."""
    return any(path == r or path.startswith(r + "/") for r in roots)

def is_canopy(sym):
    return canopy_pkg(sym) is not None

def is_example(sym):
    return under(sym, example_modules)

# --- Package-level layering rules within dowdiness/canopy ([F]-[I]) ---

def canopy_pkg(sym):
    """Package path inside the canopy module ('' for the root package),
    or None if sym is not a canopy import."""
    if sym == CANOPY:
        return ""
    if sym.startswith(CANOPY + "/"):
        return sym[len(CANOPY) + 1:]
    return None

SUBSTRATE_ONLY_ROOTS = ("core", "protocol")  # [F] — protocol covers protocol/wire
RELAY_ALLOWED_ROOTS = (  # [H] — each allows its own subpackages
    CANOPY + "/protocol/wire",
    CANOPY + "/relay",  # intra-component imports if relay ever splits
    "dowdiness/byte_codec",
)

# Out-of-module grammar/language modules, keyed by the lang/<L> that owns
# each. A language may import its own grammar; nobody else's. core/protocol
# and editor may import none of them (a grammar import IS a language import
# for [F]/[G] purposes, just routed around dowdiness/canopy/lang).
GRAMMAR_MODULES = {
    "dowdiness/lambda": "lambda",
    "dowdiness/json": "json",
    "dowdiness/markdown": "markdown",
}

def grammar_lang(sym):
    """Owning language of an out-of-module grammar import, or None."""
    for root, lang in GRAMMAR_MODULES.items():
        if under(sym, (root,)):
            return lang
    return None

# Dated waivers: (rule, package, scope, import) -> reason. A waiver is
# printed on every run; a listed entry that no longer matches any import
# FAILS the check, so this table cannot rot silently. Adding a waiver for
# any rule is a data edit here, not new machinery.
EXCEPTIONS = {}
exceptions_used = set()

def waived(rule, pkg, scope, sym):
    key = (rule, pkg, scope, sym)
    if key in EXCEPTIONS:
        exceptions_used.add(key)
        return True
    return False

def check_canopy_layering(pkg, scope, sym):
    """Yield [F]-[I] violation strings for one import of a canopy package."""
    target = canopy_pkg(sym)
    glang = grammar_lang(sym)
    if under(pkg, SUBSTRATE_ONLY_ROOTS):
        if target is not None and not under(target, SUBSTRATE_ONLY_ROOTS):
            yield (f"[F] {pkg} ({scope}) → {sym} "
                   f"(core/protocol import substrate only)")
        if glang is not None:
            yield (f"[F] {pkg} ({scope}) → {sym} "
                   f"(core/protocol must not import a language grammar)")
    if under(pkg, ("editor",)):
        is_lang_import = (target is not None and under(target, ("lang",))) \
            or glang is not None
        if is_lang_import and not waived("G", pkg, scope, sym):
            yield (f"[G] {pkg} ({scope}) → {sym} "
                   f"(editor must not import lang/* or a language grammar)")
    if under(pkg, ("relay",)) \
            and not under(sym, RELAY_ALLOWED_ROOTS) \
            and not sym.startswith("moonbitlang/"):
        yield (f"[H] {pkg} ({scope}) → {sym} "
               f"(relay allowlist: {', '.join(RELAY_ALLOWED_ROOTS)}, "
               f"moonbitlang/*)")
    if pkg.startswith("lang/"):
        own = pkg.split("/")[1]
        if target is not None and under(target, ("ffi",)):
            yield f"[I] {pkg} ({scope}) → {sym} (lang must not import ffi/*)"
        other_lang = (target is not None and target.startswith("lang/")
                      and target.split("/")[1] not in ("runtime", own))
        other_grammar = glang is not None and glang != own
        if own == "runtime":
            # Shared SPI: language imports are test-fixture-only.
            if (other_lang or other_grammar) and scope == "normal":
                yield (f"[I] {pkg} ({scope}) → {sym} "
                       f"(lang/runtime must not depend on a language)")
        elif other_lang or other_grammar:
            yield f"[I] {pkg} ({scope}) → {sym} (cross-language import)"

# --- Scan package imports ---
violations = []
scanned_pkgs = 0
canopy_import_counts = {}  # canopy pkg_rel -> number of parsed imports

for pkg_file in iter_files("moon.pkg"):
    scanned_pkgs += 1
    mod_name, _ = nearest_module(pkg_file)
    cat = module_category.get(mod_name, "other")
    pkg_rel = (os.path.relpath(os.path.dirname(pkg_file), ROOT) or ".") \
        .replace(os.sep, "/")
    if cat == "canopy":
        canopy_import_counts.setdefault(pkg_rel, 0)
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
            canopy_import_counts[pkg_rel] += 1
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
for key in sorted(EXCEPTIONS):
    rule, pkg, scope, sym = key
    if key in exceptions_used:
        print(f"NOTE [{rule}] waived: {pkg} ({scope}) → {sym} — "
              f"{EXCEPTIONS[key]}")
    elif canopy_import_counts.get(pkg, 0) == 0:
        # Distinguish a removed import from a scanner that never parsed the
        # package — following the stale-removal advice here would silently
        # disable the rule while the real problem is a broken scan.
        gap = (f"[{rule}] SCAN GAP: package {pkg} (waived in EXCEPTIONS) "
               f"yielded no imports — manifest missing or unparsable; fix "
               f"the scan before touching the exception table")
        if gap not in violations:
            violations.append(gap)
    else:
        violations.append(
            f"[{rule}] STALE exception: {pkg} ({scope}) → {sym} no longer "
            f"matches any import — remove it from EXCEPTIONS")

if violations:
    print("Dependency rule violations:", file=sys.stderr)
    for v in violations:
        print(f"  {v}", file=sys.stderr)
    print(f"\n{len(violations)} violation(s) across {scanned_pkgs} packages, {scanned_mods} modules.",
          file=sys.stderr)
    sys.exit(1)

print(f"OK — {scanned_pkgs} packages and {scanned_mods} modules scanned, no rule violations.")
PY
