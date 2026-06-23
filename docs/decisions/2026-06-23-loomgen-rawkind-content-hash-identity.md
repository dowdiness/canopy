# loomgen RawKind numbering vs. seam content-hash identity (L1-A)

**Date:** 2026-06-23
**Status:** Accepted (decision record)
**Related:** loom [#427](https://github.com/dowdiness/canopy/issues/427) (gate: fix L1-A + re-baseline before loomgen build) ·
canopy [#729](https://github.com/dowdiness/canopy/issues/729) (the L1-A fix in `07-loomgen-design.md`) ·
[`07-loomgen-design.md`](../design/07-loomgen-design.md) ·
[2026-06-01 identity-and-reuse-mechanisms](2026-06-01-identity-and-reuse-mechanisms.md) ·
loom analysis [`2026-06-20-parser-generation-direction.md` §4.5](../../loom/docs/analysis/2026-06-20-parser-generation-direction.md) ·
loom ADR [`2026-03-14-physical-equal-interner`](../../loom/docs/decisions/2026-03-14-physical-equal-interner.md)

## Why this record exists

The Layer-1 adversarial pass on the loomgen design (loom §4.5, 2026-06-20) found a
latent **correctness bug — "L1-A"** — and left one question explicitly unresolved:
how bad is it? This record settles the severity from evidence and decides the fix.
It is **non-blocking** for the merged `@grammar` work; it is the *emitter's* gate
(loom #427), distinct from the #444 throughput gate (perf, already done) and #449
(deep-subtree reuse, a different axis).

## The bug (L1-A)

Two statements in the codebase collide:

1. **loomgen's promised contract** ([`07-loomgen-design.md`](../design/07-loomgen-design.md),
   "Generation idempotency"): generated `syntax_kind.g.mbt` has *"Stable ordering,
   sequential `to_raw` integers, never reads `.g.mbt` as input."*

2. **The real hand-maintained registry**
   ([`loom/examples/lambda/syntax/syntax_kind.mbt`](../../loom/examples/lambda/syntax/syntax_kind.mbt),
   as of 2026-06-23): `to_raw` is an **append-only stability registry**, not a
   sequence. Raw `24` and `26` are skipped (`LetKeyword => 23`, `EqToken => 25`,
   `LetDef => 27`); `FnKeyword => 43` and `FatArrowToken => 44` are appended despite
   their mid-enum positions; comments hand-annotate `// NEW:` and `// (raw 37)`.

A *sequential* regenerator that never reads prior state renumbers existing kinds on
any `Term`-enum edit (insert a variant mid-enum → every later kind shifts) — actively
undoing the discipline the gaps and comments encode.

**Why this is identity-affecting, not cosmetic.** Seam bakes the raw int into
structural identity ([`loom/seam/cst_node.mbt`](../../loom/seam/cst_node.mbt), as of
2026-06-23): `CstToken::CstToken` computes
`combine_hash(combine_hash(k, string_hash(text)), provenance)` with `k = RawKind.inner`
(`:48`); `CstNode::new` seeds the recursive structural hash with `let mut h = k`
(`:279`); and `Eq` compares `self.kind == other.kind` directly after the hash
fast-path (`:143`, `:380`). The hash feeds `Eq`/`Hash`/interning/reuse — load-bearing
(see the physical-equal-interner ADR, O(n²)→O(n)). So renumbering a kind changes the
content hash **and** structural identity of every node containing it.

## Severity: MILD — settled by evidence

The open question (loom §4.5): *does any persisted/transmitted artifact key off the
seam content hash?* If yes, a renumber silently invalidates persisted state (**severe**,
favoring fork (ii)); if the hash is in-memory only, the blast radius is one recompile
(**mild**, fork (i) suffices). Reading the actual persistence/transmission layer
settles it.

**What survives from one loomgen build to the next?** Only two things: (a) source
**text** files, and (b) the SQLite op log. Text is ground truth — re-parsed into a
fresh CST under the current numbering, immune to renumbering. So the question reduces
to: *does a persisted/transmitted op carry a seam content-hash or RawKind int?*

Evidence (as of 2026-06-23):

| Surface | What it carries | Keys off seam hash? |
|---------|-----------------|---------------------|
| Op log persistence ([`examples/ideal/web/server/store.ts`](../../examples/ideal/web/server/store.ts)) | opaque relayed op strings, `(id, room_id, data)` | no |
| The op itself ([`protocol/user_intent.mbt`](../../protocol/user_intent.mbt) `UserIntent`) | `TextEdit(from, to, insert)` (text edits) + `StructuralEdit`/`SelectNode`/`CommitEdit` addressing by `@core.NodeId` | no |
| `NodeId` ([`core/types.mbt`](../../core/types.mbt) `struct NodeId(Int)`) | allocation-order int (`assign_fresh_ids` counter), "survives reparses" | no — not hash-derived |
| Wire view/annotation ([`protocol/view_node.mbt`](../../protocol/view_node.mbt)) | `ViewNode.kind_tag : String` (AST variant **name**), `ViewAnnotation.kind/label/severity : String`, `TokenSpan.role : String`, UTF-16 offsets | no — keys off **names** + NodeId |
| Source map (`core/source_map.mbt` `to_json`) | node id / range / token-role spans | no raw kind |
| Persistent identity (`ProjectionIdentityTracker`, see [identity ADR](2026-06-01-identity-and-reuse-mechanisms.md) mechanism #2) | **source offset + key** windows | no |
| `content_hash` / `structural_path` / `.md.annotations.json` | — | **do not exist** in code or on disk; named only as the loom §4.5 inferred open question |

Corroborating: `to_raw` fires (calibrated) in seam and the lambda language package,
but is **absent** across `protocol/`, `ffi/`, `editor/`, `sync_session/`,
`transport_ws/`, and `adapters/` — the raw int never escapes the MoonBit process.

**Conclusion.** The seam content hash is a **runtime, in-memory** structural-equality
accelerator (interning, reuse, `Eq` fast-path), recomputed every run from whatever
`to_raw()` currently returns. Nothing persisted or transmitted keys off it; the
identity that *does* persist (NodeId, ProjectionIdentityTracker) is allocation-order /
source-offset based, and the wire layer already addresses by stable **names**. A
RawKind renumber is therefore internally consistent within a single recompile — its
blast radius is one rebuild of all in-tree consumers, with no stale persisted state.
**Severity is MILD.**

## Decision

**Adopt fork (i): constrain loomgen with a persistent append-only kind→raw registry.**
Since loomgen is *unimplemented* ([`07-loomgen-design.md`](../design/07-loomgen-design.md),
"implementation not started"), fork (i) costs ~nothing today: it is a **doc-contract
correction** that writes down the invariant the hand-discipline already enforces. The
concrete action is correcting the "Generation idempotency" section (its false
"sequential / never-reads" promise).

**Hold fork (ii) (migrate seam's content hash onto a stable kind name) as the
documented escalation path**, triggered only if the severity precondition ever
becomes true (see *Escalation trigger* below).

### The corrected loomgen idempotency contract

This block replaces the false "Generation idempotency" promise in
[`07-loomgen-design.md`](../design/07-loomgen-design.md). It is the load-bearing
artifact of fork (i) — the exact obligation loomgen must honor.

loomgen reads a persistent, append-only **kind→raw registry** as a second input.
Existing kinds keep their assigned raw across any `Term`-enum edit; retired or deleted
kinds keep their raw as a tombstone (never reissued); only newly introduced kinds
receive a fresh raw (the next unused integer). Regeneration is **idempotent given the
registry**: re-running loomgen with the same `Term` enum *and* registry produces
identical `.g.mbt` files, and editing the enum reshuffles nothing already assigned. The
registry's concrete form — a sidecar manifest, `#loom.kind(raw=N)` annotations on the
`Term` variants, or reading the prior generated output — is a loomgen implementation
choice; the contract is only that such a stable record exists and is honored.

## Rationale

1. **Problem-first.** The persisted-staleness problem fork (ii) solves **does not
   exist today** (severity MILD). Don't pay a high-risk source migration for a
   non-manifest problem.

2. **(i) matches the proven hand-discipline.** The existing registry already does
   exactly this, by hand. loomgen merely automates it. (i) preserves a known-correct
   invariant; it does not invent one.

3. **(ii) relocates the registry — it does not eliminate it.** "Move identity onto the
   kind name" frees loomgen to renumber, but to keep hashing fast on seam's hottest
   path you must intern kind names to stable ints — which is a name→int registry living
   *inside seam* instead of in loomgen. The stability requirement moves; it does not
   vanish. Meanwhile the migration touches the most performance-critical, most-ADR'd
   invariant in the system (physical-equal-interner; #396's source-span tradeoff). High
   risk, mild payoff. (Both reviewers — advisor + Codex — confirmed this argument.)

4. **(iii) deterministic name-hashed raws — rejected.** A scheme where loomgen derives
   raws by hashing kind names (stateless, no registry file) was considered. It buys
   little over (i): it requires collision handling, discards the hand-curated numbering
   and its comments, and forces a one-time full renumber — all for no benefit given
   mild severity. Rejected.

5. **Reserve the extension point, don't just defer.** Recording fork (ii) with a precise
   trigger means the coupling (raw-int-as-identity) is a *documented known limitation*
   with a ready escalation, not a silent landmine.

## Escalation trigger (when fork (ii) becomes necessary)

Re-open this decision and execute fork (ii) if **any persisted or cross-build-transmitted
artifact comes to key off the seam content hash or a raw RawKind int** — concretely, if
a future feature (a) writes a CST content-hash or RawKind into the op log, a document
save format, a wire message, or an annotation cache, **and** (b) reads it back in a
later build for comparison or lookup. Until both hold, the hash stays in-memory and (i)
is sufficient. The regression signal: a new persisted field whose value is, or derives
from, `CstNode.hash` / `CstToken.hash` / `RawKind.inner`.

## Where the fix lands (cross-repo)

- **canopy** owns the fix: correct the "Generation idempotency" section of
  [`07-loomgen-design.md`](../design/07-loomgen-design.md) per the contract above
  (resolves the substance of #729). **No seam code changes** under fork (i).
- **loom** #427 (the gate) references this record; the seam hash contract in
  `loom/seam/cst_node.mbt` is **unchanged**.
- loom analysis §4.5's open question is now settled by this record (MILD).

## Source of truth on drift

Code and generated `.mbti` files are authoritative. This record names specific
files/lines **as of 2026-06-23** to fix the evidence map; if a name here disagrees with
the code, the code wins and this record should be updated. The durable content is the
**judgment**: severity is MILD because nothing persisted/transmitted keys off the seam
hash; fork (i) now, fork (ii) only on the escalation trigger.
