#!/usr/bin/env bash
# event-graph-walker version-consistency guard (post-S5b single source;
# docs/decisions/2026-06-12-substrate-governance.md).
#
# Invariant: the egw version pinned by canopy's submodule matches the version
# pinned by every workspace member that declares dowdiness/event-graph-walker,
# including loom's examples/lambda which resolves egw from registry.
#
# After S5b (2026-07-05), loom's nested egw copy was removed — there is only
# one gitlink to check. The guard focuses on version consistency: the
# submodule's declared version must match every workspace member manifest.
#
# Why the version layer is still enforced (probed 2026-06-12): moon validates
# no version constraint on path-deps. A bump that edits the root manifest +
# gitlink can silently miss example manifests. The workspace-member scan
# catches that.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

fail() { echo "check-egw-resolver-identity: $*" >&2; exit 1; }

direct_sha=$(git rev-parse HEAD:event-graph-walker) \
  || fail "cannot read gitlink HEAD:event-graph-walker"

# Extract pinned version from the submodule commit's moon.mod
pinned_version=$(git -C event-graph-walker show "${direct_sha}:moon.mod" \
  | sed -n 's/^version = "\(.*\)"/\1/p') \
  || fail "cannot read moon.mod from event-graph-walker at ${direct_sha}
  (submodule object store missing the pinned commit? run:
  git submodule update --init --recursive)"
[ -n "${pinned_version}" ] \
  || fail "cannot extract version from event-graph-walker moon.mod at ${direct_sha}"

# Extract loom's registry pin from examples/lambda/moon.mod
lam_version=$(sed -n 's/.*dowdiness\/event-graph-walker@\([^"]*\).*/\1/p' \
  loom/examples/lambda/moon.mod 2>/dev/null) \
  || fail "cannot read moon.mod at loom/examples/lambda/moon.mod"
[ -n "${lam_version}" ] \
  || fail "loom/examples/lambda/moon.mod does not declare dowdiness/event-graph-walker"

if [ "${pinned_version}" != "${lam_version}" ]; then
  fail "version mismatch between canopy submodule and loom's registry pin:
    canopy submodule (HEAD:event-graph-walker):    version ${pinned_version}
    loom registry pin   (examples/lambda/moon.mod): version ${lam_version}
  Both must agree. Bump order: egw submodule → loom moon.mod → canopy pointer."
fi

# Version layer: the (now provably consistent) pinned egw commit's declared
# version must match what EVERY canopy workspace member that declares the dep
# claims for it — moon itself never checks this.
# Scope: moon.work members, mirroring check-shared-substrate.sh.

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
echo "OK — submodule pin ${direct_sha} (version ${pinned_version}) matches loom registry pin (${lam_version}) and all workspace manifests agree."
