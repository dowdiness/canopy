# Architectural Decision Records

Decisions record the rationale and scope of adopted changes. Before relying on
one, read its status and any supersession notes; a newer date alone does not
replace an earlier decision. Accepted requirements describe intended behaviour,
not proof that the current implementation meets it. See
[Documentation Doctrine](../development/documentation-doctrine.md#document-roles-and-conflicts).

Start with the affected component's README for its relevant decisions. The
links below preserve the previously curated selection; the directory contains
additional records. This index does not assign or change their status.
Exploratory proposals are listed separately in
[Design Explorations](../architecture/README.md#design-explorations).

## Decision index

- [Framework Genericity Contract](2026-03-29-framework-genericity-contract.md)
  — why `framework/` and `core/` must stay language-agnostic.
- [Identity and Reuse Mechanisms](2026-06-01-identity-and-reuse-mechanisms.md)
  — the three distinct parse/projection identity mechanisms, the #396 source-span
  tension, and why the BAND 2b cliff fix (#449) is an optimization, not a refactor.
- [Shared-substrate `incr` version lock](2026-06-10-shared-substrate-incr-version-lock.md)
  — requires Canopy/Loom/moondsp consumption to remain aligned, defines the
  bottom-up paired-bump protocol and drift guard, and defers cross-repo CI until
  shared-runtime work needs it (closes #441).
- [Lambda edit bridge boundary](2026-06-15-lambda-edit-bridge-boundary.md)
  — keeps Lambda's typed-error, patch-trace, editor-coupled bridge outside
  `LanguageSpec` after `ModuleProjection` removal (closes #634).
- [loomgen RawKind vs content-hash identity (L1-A)](2026-06-23-loomgen-rawkind-content-hash-identity.md)
  — severity of loomgen's sequential-renumber bug is MILD (nothing persisted/transmitted
  keys off the seam content hash); constrain loomgen with an append-only kind→raw
  registry (fork (i)), holding the seam hash-name migration (fork (ii)) as a documented
  escalation (loom #427 / #729).
- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
  — separates EGW core, its peer-sync companion, a payload-opaque collaboration
  runtime, infrastructure providers, and application policy.
- [Protocol v3 hard cutover](2026-07-22-protocol-v3-hard-cutover.md)
  — rejects v2 frames at endpoints and the relay rather than bridging the
  incompatible EGW 0.3 and 0.4 identity schemas.
- [Markdown semantic Preview ownership](2026-08-04-markdown-semantic-preview-ownership.md)
  — keeps the ordinary Markdown editor attachment-free while the private
  single-mount Loomark host retains one same-parser semantic Preview read model.
- [Generic language SPI deepening](2026-08-07-generic-language-spi-deepening.md)
  — deepens the `lang/runtime` SPI to structured errors, patch traces, identity
  hints, language-owned extras, and edit-port moves; partially supersedes the
  Lambda edit bridge boundary.
- [EGW staged publication responsibility boundary](2026-08-09-egw-staged-publication-responsibility-boundary.md)
  — keeps EGW core unchanged while an EGW-versioned companion owns causal
  sealing and publication outcomes; Loomark retains persistence and product
  resolution policy.
- [Markdown file-backed authority and external admission](2026-08-09-markdown-file-backed-authority-and-external-admission.md)
  — separates File and Causal Authority, Archive-backed and File-backed
  persistence, and bounded External admission for associated Markdown files.
- [Causal Authority residency](2026-08-12-causal-authority-residency.md)
  — preserves one causal authority while choosing warm or cold residency by
  access path; retained state remains a validated accelerator.
- [Authority-owned remote admission transition](2026-08-19-authority-owned-remote-admission-transition.md)
  — consumes one opaque EGW admission transition, reconciles exact effects without a full authority snapshot, and bounds grapheme-safe snapshot fallback.
- [Loomark Source repository](2026-08-29-loomark-source-repository.md)
  — makes versioned Source records independently authoritative, derives the
  Catalog in memory, atomically migrates `active`, and keeps normal saves to one
  Source transaction; its Source shape, empty-repository behavior, ordering,
  and completion policy are partially superseded by the following ADR.
- [Loomark document deletion](2026-08-31-loomark-document-deletion.md)
  — orders Recent documents by persisted Change order, permits empty repository
  snapshots, and coordinates Delete through pure per-document persistence lanes
  without blocking unrelated editing.
