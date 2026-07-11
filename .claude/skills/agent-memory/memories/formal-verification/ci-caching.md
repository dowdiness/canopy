---
summary: "CI caching strategy for moon prove: cache entire ~/.opam directory with stable key, skip opam init + install on hit, only run why3 config detect + moon prove"
created: 2026-04-12
status: resolved
tags: [ci, caching, opam, github-actions]
related: [.github/workflows/ci.yml]
---

# CI Caching for Formal Verification

## Problem

`opam install why3.1.7.2 z3` compiles from source, taking ~18 minutes on GitHub Actions. The `setup-ocaml@v3` action auto-caches but still re-resolves dependencies each run.

## Solution

Replace `setup-ocaml@v3` with direct opam install + `actions/cache@v4` on `~/.opam`:

```yaml
- name: Cache opam switch
  id: opam-cache
  uses: actions/cache@v4
  with:
    path: ~/.opam
    key: opam-why3-1.7.2-z3-${{ runner.os }}-${{ runner.arch }}

- name: Install opam
  if: steps.opam-cache.outputs.cache-hit != 'true'
  run: |
    sudo apt-get update -q
    sudo apt-get install -yq opam
    opam init --disable-sandboxing --yes

- name: Install Why3 and Z3
  if: steps.opam-cache.outputs.cache-hit != 'true'
  run: |
    eval $(opam env)
    opam install why3.1.7.2 z3 --yes

- name: Configure Why3 provers
  run: |
    eval $(opam env)
    why3 config detect
```

## Key details

- **Stable cache key**: `opam-why3-1.7.2-z3-{os}-{arch}` — only changes when we bump versions, forcing a rebuild.
- **`why3 config detect` always runs**: Even on cache hit, because `~/.why3.conf` isn't cached (it contains absolute paths that may differ between runners).
- **`--disable-sandboxing`**: Required on GitHub Actions (no bubblewrap in containers).
- **First run**: ~18min (cache miss, full compile). Subsequent runs: ~1min (cache hit, only detect + prove).
