# Shared-substrate `incr` version lock

**Date:** 2026-06-10
**Status:** Accepted (decision record)
**Amended by:** [Substrate governance: one consumption policy per dependency](2026-06-12-substrate-governance.md)
(2026-06-12 — generalizes this record's single-dependency policy to all
`dowdiness/*` substrate and adds the `event-graph-walker` resolver-identity
guard alongside the incr drift guard; the lock value, bump protocol, and
deferred cross-repo extension point below remain authoritative here)
**Closes:** [#441](https://github.com/dowdiness/canopy/issues/441) (BAND 1b — cross-repo `incr` version-lock)
**Related:**
[Ecosystem vision §5.2 / §5.7 / §7.3](../research/2026-06-01-moondsp-canopy-ecosystem-vision.md) ·
[BAND 1–2 execution spec, PR B1/B2](../plans/2026-06-01-band1-2-ecosystem-foundation.md) ·
canopy-internal drift guard PR [#574](https://github.com/dowdiness/canopy/pull/574)
(`scripts/check-shared-substrate.sh`) ·
bump precedent PRs: incr#237, egglog#12, loom#277, canopy#575

## Why this record exists

`dowdiness/incr` is the one dependency consumed by **two independent products** —
canopy (with its vendored `loom` tree) and the sibling `dowdiness/moondsp` repo.
incr's **Single-Runtime constraint** (a cross-runtime cell read aborts) means any
future shared-graph work across the two products requires both to build against the
*same* incr. Nothing in the toolchain keeps two separate repos on the same incr
minor, and incr's compatibility handles carry no removal date — so a future incr
removal could force both products to migrate simultaneously with no staging room.

This record fixes the lock (which version, which consumers), the protocol for the
next bump, and — deliberately — **what is and is not enforced by machinery today**,
so the deferred cross-repo enforcement is a named extension point rather than a
silent gap. It does not specify scripts or CI YAML; that is execution (PR B1/B2 in
the BAND 1–2 spec).

> **Re-baseline note.** #441's body ("canopy root 0.5.2, moondsp 0.6.0") and an
> earlier vision-doc draft (§5.2: "moondsp 0.6.0") are **both stale**. Every cross-repo
> claim below was re-verified against the live repos on 2026-06-10 (`gh api`); the
> verified topology differs from both prior write-ups (see the table). Cross-repo
> claims in this record are point-in-time facts, not standing guarantees — re-verify
> before the next bump.

## The lock (verified 2026-06-10)

| Field | Value |
|-------|-------|
| Dependency | `dowdiness/incr` |
| Exact target | **0.9.0** |
| Required minor | **0.9** (consumers must agree on major.minor) |
| Consumer repos | canopy (incl. vendored `loom`), `dowdiness/moondsp` |
| Compat-handle status | `Signal` / `Memo` / `HybridMemo` / `MemoMap` still present as of 0.9.0 — **no announced removal date, no deprecation attribute** |
| Removal policy | Removal of any compat handle requires updating *this* ADR with a dated removal target **before** the incr release that drops it, plus a paired consumer-migration plan |
| Owner | canopy/moondsp maintainer (Koji Ishimoto) |

### Verified pin topology

| Repo / member | incr pin | Form |
|---------------|----------|------|
| canopy `moon.mod.json` (root) | 0.9.0 | registry, JSON |
| canopy `lib/visualizer/moon.mod.json` | 0.9.0 | registry, JSON |
| canopy `lib/cognition/moon.mod` | 0.9.0 | registry, TOML `import` |
| canopy `examples/canvas/moon.mod.json` | 0.9.0 | registry, JSON |
| loom `loom/`, `egglog`, `examples/*`, vendored `incr` | 0.9.0 | registry pins + vendored gitlink |
| moondsp `moon.mod` (root lib, v0.5.1) | 0.9.0 | registry, TOML `import` |
| moondsp `specs/loom-backend-canary`, `specs/loom-mini-cst` | — | **path-dep** into `../../../canopy/loom/incr/incr`; excluded from the published module |

Two facts from this topology shape the enforcement decision below:

1. **moondsp has exactly one registry incr consumer** — its root `moon.mod`. The two
   `specs/*` members are dev spikes that path-dep into a sibling canopy checkout, so
   they cannot pin a divergent registry version; they consume whatever incr canopy
   provides. moondsp therefore has **no intra-repo skew surface** to guard.
2. **canopy has four registry pins across two manifest formats** (JSON ×3 + TOML ×1),
   which historically skewed — `lib/cognition`'s TOML pin evaded a grep-based bump.
   That multiplicity is exactly why canopy needs an intra-repo guard and moondsp does
   not.

## Decision

1. **Lock the shared substrate at incr minor 0.9** across canopy, loom, and moondsp,
   with 0.9.0 as the current exact target. This record is the single source of truth
   for that value.

2. **Enforce the canopy-internal invariant per-PR** via `scripts/check-shared-substrate.sh`
   (shipped in #574): canopy CI fails when its members disagree on the incr major.minor.
   This is the *required-per-PR* form — the simplest of the three options the vision
   §7.3 left open — chosen because canopy's four-pin / two-format surface is where
   skew has actually occurred.

3. **Do not add a moondsp intra-repo guard, and do not build cross-repo CI now.** A
   moondsp guard mirroring #574 would check a single pin against itself (zero value —
   see topology fact 1). A genuine cross-repo check (moondsp's pin == canopy's pin)
   requires both repos checked out together and only *bites* when a shared incr
   *runtime* spans both products — a **BAND 3+ precondition that has not landed**.
   Per §5.2, skew-removal is necessary-but-not-sufficient for a shared runtime (ESM
   heap-isolation is a separate, still-open blocker), so building cross-repo CI today
   reserves machinery against an inactive precondition. It is recorded here as a named
   extension point (below), to be built when shared-runtime work activates the
   Single-Runtime constraint — not before.

## Bump protocol (next incr minor)

The dependency graph ripples **bottom-up**, one PR per repo, each merged before its
parent references the new SHA (so required CI never points at an unpushed commit):

```
incr  →  egglog  →  loom  →  canopy
                                 ‖  (paired, same minor)
                              moondsp
```

- **Per-PR edits:** registry-pin strings in each consuming manifest (JSON and TOML
  `import` blocks both — do not trust a grep that only finds JSON), plus vendored
  submodule gitlink advances in loom/canopy (build-neutral when the path-dep'd source
  is unchanged, done for hygiene).
- **canopy ↔ moondsp are paired**, not sequential: open both PRs at the same minor.
  Each repo's own CI validates its local pins (canopy via #574). A peer-root
  cross-check stays a **manually-run / paired-branch gate**, never a required status
  that blocks on the peer's branch — that would deadlock two PRs each waiting on the
  other against stale `main`.
- **Compat-handle removal** is not a routine bump: it requires updating this ADR with
  a dated removal target and a paired migration plan first (see removal policy above).

Precedent for the 0.8.0 → 0.9.0 bump: incr#237 → egglog#12 → loom#277 → canopy#575,
with moondsp aligned independently.

## Deferred extension point (not built now)

A cross-repo enforcement mechanism — either a scheduled workflow that checks out both
repos and compares pins, or a paired-branch gate run at bump time — is the BAND 1b
"CI cross-check" from vision §7.3. It is **deferred until shared-runtime work (BAND 3+)
makes the Single-Runtime constraint load-bearing across the two products.** Until then
the lock is enforced by this record plus the paired-PR discipline above; canopy's
internal agreement is the only part with active machinery, which matches where skew
risk actually lives today.

## Consequences

- The next contributor bumping incr has a written, ordered protocol and does not have
  to reconstruct the topology or guess merge order.
- A compat-handle removal cannot arrive as a surprise: the policy field forces a dated
  ADR update ahead of the dropping release.
- No machinery is built for a cross-repo failure mode that cannot occur until shared
  runtimes exist; the gap is named, not hidden.
- If moondsp later grows a second registry incr consumer, topology fact 1 no longer
  holds and a moondsp intra-repo guard should be reconsidered.

## Source of truth on drift

The pin values in the manifests are authoritative; the tables above are a 2026-06-10
snapshot to fix the topology. If a pin here disagrees with a manifest, the manifest
wins and this record should be updated. The durable content is the *judgment*: lock at
one minor, enforce internally where skew actually occurs, defer cross-repo machinery
until a shared runtime needs it, and gate compat-handle removal behind a dated ADR
update.
