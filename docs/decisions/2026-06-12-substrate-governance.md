# Substrate governance: one consumption policy per dependency

**Date:** 2026-06-12
**Status:** Accepted (decision record)
**Amends:** [Shared-substrate `incr` version lock](2026-06-10-shared-substrate-incr-version-lock.md)
(generalizes its single-dependency policy to the full `dowdiness/*` substrate;
does not replace it — the incr lock value, bump protocol, and deferred
cross-repo extension point remain authoritative there)
**Related:** architecture redesign proposal §6 S5a
([docs/plans/2026-06-11-architecture-redesign-proposal.md](../plans/2026-06-11-architecture-redesign-proposal.md)) ·
resolver-identity guard `scripts/check-egw-resolver-identity.sh` (this PR) ·
incr drift guard `scripts/check-shared-substrate.sh` ([#574](https://github.com/dowdiness/canopy/pull/574))

## Why this record exists

The 2026-06-10 ADR governs one dependency (`incr`). The redesign proposal's
substrate rule generalizes it: **every `dowdiness/*` dependency has one
declared ownership policy — either a single consumption mechanism, or an
re-evaluation date.** This record once documented one such exception
(`event-graph-walker`); it was resolved by S5b (2026-07-05) — see amendments
below.

## What moon actually does with two sources (probed 2026-06-12)

`dowdiness/event-graph-walker` is declared from four manifests in a canopy
workspace build: three path-dep the **direct submodule** `./event-graph-walker`
(canopy root, `examples/ideal`, `examples/block-editor`) and one path-deps
**loom's nested copy** `loom/event-graph-walker` (`loom/examples/lambda`,
via `../../event-graph-walker`). Probe findings, against the canopy CI
toolchain on this date:

1. **moon dedupes the module by name and silently picks one winner.** The
   resolved package graph (`_build/packages.json`) sources *every*
   `dowdiness/event-graph-walker` package from the nested copy — including for
   the three members that explicitly path-dep the direct submodule. Zero
   occurrences of the direct path; no warning, no error. Which copy wins is
   unspecified behavior, observed not documented.
2. **moon validates no version constraint on path-deps.** With the winning
   copy's `moon.mod` edited to `version = "9.9.9"` against canopy's declared
   `"version": "0.3.0"`, `moon check` exits 0 with no diagnostic.
3. **Identity holds today by accident, not machinery.** Both gitlinks pin
   `b72d481` (egw 0.3.0). Nothing in the toolchain keeps them aligned; a
   drifted pair would mean canopy builds against an egw it does not declare,
   with zero signal.

These probes are point-in-time facts about an unspecified toolchain behavior —
the guard below asserts identity precisely so that the winner-selection rule
never matters.

## Decision

1. **One governed consumption policy per `dowdiness/*` dependency** (table
   below). New dependencies declare their mechanism on introduction; a second
   mechanism for an existing dependency requires amending this record with a
2. **`event-graph-walker` was the sole dual-source exception**, resolved by
   S5b (2026-07-05). Its two sources (direct submodule + loom's nested copy)
   were guarded by `scripts/check-egw-resolver-identity.sh`. After S5b, loom's
   nested copy was removed; canopy's direct submodule is the single source
   within the canopy workspace (its path-dep shadowing loom's registry pin —
   normal override semantics). The guard was updated in the same PR to compare
   the submodule's version against loom's registry pin and verify consistency
   across all workspace member manifests.

3. **S5b executed 2026-07-05.** Loom's nested egw copy was removed (loom PR
   #623); canopy's direct submodule is the single source within the workspace.
   The guard was updated to compare the submodule version against loom's
   registry pin, covering all workspace member manifests.
4. **Re-evaluation date: resolved by S5b (2026-07-05).** The 2026-09-12
   deadline was met. The ./rle submodule was also removed per its build-inert
   flag (same deadline).
   exception must be re-justified or the de-dup re-planned — dual-source
   without a horizon is exactly what this record exists to prevent.

## Policy table (verified 2026-06-12)

Mechanisms: `registry` (mooncakes pin) · `in-repo` (path-dep to a canopy
workspace directory) · `submodule` (path-dep into a vendored submodule) ·
`dual` (exception, guarded).

| Dependency | Mechanism | Policy notes |
|------------|-----------|--------------|
| `dowdiness/event-graph-walker` | submodule (`./event-graph-walker`) | Former dual-source exception, resolved by S5b (2026-07-05). Guard `check-egw-resolver-identity.sh` now checks version consistency across workspace members. |
| loom family: `loom`, `seam`, `pretty`, `text_change`, `moji`, `lambda`, `json`, `markdown`, `egglog`, `egraph`, `graph-dsl` | submodule (`./loom/...`) | Single mechanism — every consumer path-deps into the one vendored loom tree |
| in-repo libs: `byte_codec`, `zipper`, `btree`, `visualizer`, `dom_boundary`, `canopy-canvas-graph`, `rabbita_codemirror`, `rabbita-menu`, `rabbita-tabs`, `rabbita-treeview`, `rabbita-resizable`, `rabbita-status`, `rabbita-context-menu` | in-repo | Single mechanism — workspace members path-dep'ing each other |
| `dowdiness/order-tree` | submodule (`./order-tree`) | canopy's path-dep shadows egw's registry pin 0.1.0 inside the workspace build — normal moon override semantics, one declared source per build context, not a dual-source exception |
| `dowdiness/alga` | submodule (`./alga`) | Same shadowing shape (egw pins 0.3.0, graphviz pins 0.2.0; the path-dep wins in-workspace) |
| `dowdiness/svg-dsl` | submodule (`./svg-dsl`) | Shadows graphviz's registry pin in-workspace |
| `dowdiness/rle` | registry 0.2.2 | The `./rle` submodule was BUILD-INERT and removed in S5b (2026-07-05). All consumers use the registry pin. |
| `moonbit-community/rabbita` | submodule (`./rabbita`, vendored fork) | Single mechanism; fork status and patch documented in CLAUDE.md / the rabbita skill |

**Shadowing is not dual-source.** A registry pin inside a vendored module's
own manifest (egw pinning order-tree, graphviz pinning svg-dsl) is that
module's *standalone-build* declaration; inside the canopy workspace exactly
one path-dep'd directory provides the module, so there is one source per build
context and nothing to guard. The egw case was categorically different — **two
path-dep'd directories with the same module name in one workspace build**,
where moon picks a winner silently — until S5b (2026-07-05) removed the second
source. The shadowing-is-not-dual-source principle stands.

## Consequences

- S5b (2026-07-05) resolved the egw dual-source exception: loom's nested copy
  removed, guard updated, rle build-inert submodule removed.
- A drifted egw pair is no longer possible (single source). The version
  consistency guard remains to catch manifest skew across workspace members.
- S5b had its direction decided here and a forcing function: the guard broke
  loudly when loom dropped its nested copy, ensuring the topology change and
  the guard update landed in the same PR.
- Introducing a second source for any other substrate dependency has a named
  cost: amend this record, add a guard, set a date — or don't do it.
- The build-inert `./rle` submodule was removed in S5b.

## Source of truth on drift

Manifests and gitlinks are authoritative; the table is a 2026-06-12 snapshot.
If they disagree, update this record. The durable content is the judgment:
one mechanism per dependency, exceptions are guarded and dated, and
resolver identity is enforced by CI because the toolchain has been shown to
enforce nothing.
