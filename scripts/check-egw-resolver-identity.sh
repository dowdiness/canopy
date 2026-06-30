#!/usr/bin/env bash
# event-graph-walker resolver-identity guard (S5a dual-source exception;
# docs/decisions/2026-06-12-substrate-governance.md).
#
# Invariant: the two egw sources reachable in a canopy build pin the SAME
# commit, and that commit's declared version matches canopy's manifest:
#   (a) canopy's direct submodule   — gitlink HEAD:event-graph-walker
#   (b) loom's nested submodule     — gitlink <HEAD:loom>:event-graph-walker
#
# Why this is enforced here and nowhere else (probed 2026-06-12, moon in
# canopy CI toolchain): moon dedupes the module by NAME and silently picks one
# winner — the resolved package graph (_build/packages.json) sources every
# dowdiness/event-graph-walker package from the nested copy (b), even for
# workspace members whose manifest path-deps the direct submodule (a). moon
# also validates no version constraint on path-deps: with the winning copy's
# moon.mod set to version 9.9.9 against canopy's declared "0.3.0", moon check
# exits 0 with no warning. So if the two gitlinks drift, canopy builds against
# whichever copy moon happens to pick, with zero toolchain signal.
#
# This guard asserts what the COMMITS pin (gitlink-level), not what local
# working trees contain. It requires the loom submodule (and its nested egw)
# to be initialized — CI checks out with `submodules: recursive`.
#
# If the nested copy disappears from loom's tree (S5b: loom migrates to
# registry egw), this guard must be UPDATED in the same PR to compare canopy's
# submodule version against loom's registry pin — it fails loudly rather than
# guessing.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

fail() { echo "check-egw-resolver-identity: $*" >&2; exit 1; }

direct_sha=$(git rev-parse HEAD:event-graph-walker) \
  || fail "cannot read gitlink HEAD:event-graph-walker"
loom_sha=$(git rev-parse HEAD:loom) \
  || fail "cannot read gitlink HEAD:loom"

if ! git -C loom rev-parse --verify "${loom_sha}^{commit}" >/dev/null 2>&1; then
  fail "loom submodule object store lacks the pinned commit ${loom_sha}.
  Initialize submodules first: git submodule update --init --recursive"
fi

if ! nested_sha=$(git -C loom rev-parse "${loom_sha}:event-graph-walker" 2>/dev/null); then
  fail "loom@${loom_sha} has no event-graph-walker gitlink.
  The dual-source topology this guard asserts has changed (S5b executed?).
  Update this guard in the same PR: compare canopy's submodule version
  against loom's registry pin instead. See
  docs/decisions/2026-06-12-substrate-governance.md."
fi

if [ "${direct_sha}" != "${nested_sha}" ]; then
  fail "event-graph-walker gitlink drift between the two resolution paths:
    canopy direct submodule (HEAD:event-graph-walker):      ${direct_sha}
    loom nested submodule   (<HEAD:loom>:event-graph-walker): ${nested_sha}
  moon silently builds the whole workspace against ONE of these (observed:
  the nested copy) — a drifted pair means canopy may not be building the egw
  it declares. Bump the lagging gitlink; bump order per the version-lock ADR:
  egw -> loom -> canopy (each merged before its parent advances)."
fi

# Version layer: the (now provably single) pinned egw commit's declared
# version must match what EVERY canopy workspace member that declares the dep
# claims for it — moon itself never checks this (probe above), and a bump PR
# that edits the root manifest + gitlinks can silently miss the example
# manifests (examples/ideal, examples/block-editor also pin a version).
# Scope: moon.work members, mirroring check-shared-substrate.sh — submodule
# manifests (e.g. loom/examples/lambda's) belong to their own repos.
pinned_version=$(git -C event-graph-walker show "${direct_sha}:moon.mod" \
  | sed -n 's/^version = "\(.*\)"/\1/p') \
  || fail "cannot read moon.mod from event-graph-walker at ${direct_sha}
  (submodule object store missing the pinned commit? run:
  git submodule update --init --recursive)"
[ -n "${pinned_version}" ] \
  || fail "cannot extract version from event-graph-walker moon.mod at ${direct_sha}"

PINNED_VERSION="${pinned_version}" python3 - <<'PY' || exit 1
import json
import os
import re
import sys

TARGET = "dowdiness/event-graph-walker"
pinned = os.environ["PINNED_VERSION"]

def members():
    text = re.sub(r'#[^\n]*', '', open("moon.work").read())
    m = re.search(r'members\s*=\s*\[(.*?)\]', text, re.DOTALL)
    if not m:
        sys.exit("check-egw-resolver-identity: moon.work has no members array")
    return re.findall(r'"([^"]+)"', m.group(1))

def declared_in(member):
    """Return (manifest_rel, version-or-None) if the member declares TARGET, else None. Handles both moon.mod (TOML) and moon.mod.json (legacy)."""
    for name in ("moon.mod.json", "moon.mod"):
        p = os.path.normpath(os.path.join(member, name))
        if not os.path.isfile(p):
            continue
        if name.endswith(".json"):
            try:
                spec = (json.load(open(p)).get("deps") or {}).get(TARGET)
            except Exception as e:
                sys.exit(f"check-egw-resolver-identity: cannot parse {p}: {e}")
            if spec is None:
                return None
            version = spec.get("version") if isinstance(spec, dict) else spec
            return p, version
        text = re.sub(r'#[^\n]*', '', open(p).read())
        m = re.search(
            r'"' + re.escape(TARGET) + r'(?:@([^"]+))?"\s*(?:=\s*\{([^}]*)\})?',
            text)
        if m is None:
            return None
        version = m.group(1)
        if version is None and m.group(2):
            vm = re.search(r'version\s*=\s*"([^"]+)"', m.group(2))
            version = vm.group(1) if vm else None
        return p, version
    return None

found = [d for d in (declared_in(m) for m in members()) if d is not None]
if not found:
    # The root manifest path-deps egw today; an empty scan means the scanner
    # is broken or the topology changed — never a clean pass.
    sys.exit(f"check-egw-resolver-identity: no workspace member declares "
             f"{TARGET} — scanner or topology broken, refusing to pass")

stale = [(p, v) for p, v in found if v is not None and v != pinned]
if stale:
    lines = "\n".join(f"    {p}: declares {v}" for p, v in stale)
    sys.exit(f"check-egw-resolver-identity: {TARGET} version mismatch — "
             f"pinned submodule commit declares {pinned}, but:\n{lines}\n"
             f"  moon does not validate path-dep versions — align them by hand.")

print(f"  {len(found)} workspace manifest(s) agree on version {pinned}:")
for p, _ in found:
    print(f"    {p}")
PY

echo "OK — both egw resolution paths pin ${direct_sha} (version ${pinned_version})."
