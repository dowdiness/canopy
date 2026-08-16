#!/usr/bin/env bash
# Cloud Agent Build-time setup for Canopy.
#
# This runs during each Cursor Cloud "Build" (formerly the update script), and
# the resulting disk state is snapshotted into the bootable image every future
# agent session starts from. It must be idempotent: it may run on top of an
# already-prepared workspace, and the repo is re-cloned at its default branch
# before it runs.
#
# Keep long-running processes (dev servers) OUT of this file — put those in the
# `terminals` field of .cursor/environment.json so they start each session.
set -euo pipefail

# Canopy requires NEW_MOON_MOD=0 for every `moon` command (matches
# .github/actions/setup-moonbit); without it the rr_moon_mod TOML migration
# drops path fields from cross-repo deps.
export NEW_MOON_MOD=0
export PATH="$HOME/.moon/bin:$PATH"

# MoonBit toolchain, pinned to the same pair as CI. Normally already present in
# the base image; the guard makes a fresh base self-heal instead of failing.
if ! command -v moon >/dev/null 2>&1; then
  curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s 0.10.4+ade96c819
  export PATH="$HOME/.moon/bin:$PATH"
fi

# Submodules live under deps/ and are wiped by the per-Build re-clone.
git submodule update --init --recursive

# Warm the mooncakes registry (bounded retries for transient CDN flakes).
scripts/moon-update.sh

# JS FFI artifacts consumed by the web front-ends.
just build-js

# apps/web needs node ^22.15.0; prefer nvm's pinned 22.22.2 when available so
# npm's engines check is satisfied.
if [ -d "$HOME/.nvm/versions/node/v22.22.2/bin" ]; then
  export PATH="$HOME/.nvm/versions/node/v22.22.2/bin:$PATH"
fi
npm --prefix apps/web ci

# Optional: Warren tool for the standalone apps/loomark Rabbita app. The repo's
# scripts/install-local-warren.sh does the same thing but its origin-URL check
# fails under Cloud's token rewrite, so install the pinned package directly.
# Non-fatal: a Warren build failure must not fail the whole environment build.
moon install "$PWD/deps/rabbita/warren" --bin "$PWD/_build/tools/bin" || \
  echo "warn: Warren install skipped (apps/loomark dev unavailable)"
