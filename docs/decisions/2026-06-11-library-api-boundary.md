# Library API boundary — public surface vs internal implementation

**Date:** 2026-06-11
**Status:** Accepted (2026-06-11, PR #581; S0 of the architecture redesign)

**Partially superseded:** The [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
replaces this record's target ownership assignment for sync wire and session
policy. The general tier and compatibility rules below remain active.

**Closes:** docs/TODO.md §14 "Canopy library API audit and documentation"
(boundary-declaration part; the per-symbol audit itself remains §7 work)
**Related:**
[EGW and Collaboration Responsibility Boundary](2026-07-21-egw-collaboration-responsibility-boundary.md) ·
[Architecture redesign proposal](../plans/2026-06-11-architecture-redesign-proposal.md) ·
[Framework genericity contract](2026-03-29-framework-genericity-contract.md)

## Why this record exists

Canopy is used today as an internal monorepo, but the stated direction
(TODO §14) is to publish it as a general projectional-editor library. Without
a declared boundary, every `moon ide analyze` audit re-litigates the same
question: a `pub` symbol with no in-tree caller is either dead code (internal
lens) or exactly the API an external consumer would call (library lens).
~55 flagged symbols across `core/`, `protocol/`, `projection/`, `editor/`
and ~100 `ffi/*` functions currently have no ground truth to be judged
against. This record supplies the ground truth.

## Decision

Packages in the canopy root module are classified into three tiers.

### Tier 1 — Library surface (stability intended)

| Package | Surface role |
|---|---|
| `core` | generic tree primitives: NodeId, ProjNode, SourceMap, reconcile |
| `projection` | `TreeEditorState[T]` interactive overlay |
| `editor` | `SyncEditor[T]` orchestration API |
| `protocol` (view) | ViewNode / ViewPatch / UserIntent wire boundary |
| `protocol/wire` (once created, redesign S1) | sync wire format + version protocol |
| `sync_session` (created in redesign S2) | transport-agnostic sync policy: SyncStatus, recovery state machine, SyncTransport seam |
| `ephemeral` | self-contained presence/collaboration primitive |

Tier 1 scope for `ephemeral` is the public presence/cursor **model**
(EphemeralHub, presence types, peer-cursor view); its binary codec and
namespace routing are implementation detail — after redesign S1 the frame
namespace moves to `protocol/wire`, and codec internals follow the
`*_internal` convention rather than the Tier 1 KEEP default.

Rules for Tier 1:

- "Unused by in-tree consumers" is **not** a deletion trigger. Audits default
  to **KEEP**; removal of a `pub` symbol requires a rationale in the commit
  message (what external use case it cannot serve).
- API changes follow the deprecation idiom
  (`#deprecated(skip_current_package=true)` + alias) and live at least one
  release cycle.
- `.mbti` diffs on these packages are reviewed as API changes, including
  trait-bound widening.

### Tier 2 — Language SPI (semi-stable, contract documented)

`lang/<L>/{proj,edits,companion,…}` families and, once extracted (redesign
S3), `lang/runtime`. The contract is what `ADDING_A_LANGUAGE.md` documents;
stability is owed to language implementers, not to end consumers. Until
`lang/runtime` exists, the json/markdown shapes are the reference, not
lambda (per `ADDING_A_LANGUAGE.md`'s own warning).

### Tier 3 — Internal (no stability contract)

`ffi/*`, `workspace/*`, `relay`, `llm`, `echo`, `cmd/main`,
`transport_ws` (created in redesign S2: WebSocket externs, an L3 adapter
behind the `sync_session` transport seam), and all `examples/*` packages.
Notes:

- `ffi/*` is consumed by in-tree frontends only. External frontends should
  consume via adapters (`docs/architecture.md` already says this); the
  ~100 exported functions carry **no** compatibility promise. The wire
  *format* relay speaks is Tier 1 (via `protocol/wire`); the relay *package
  API* is Tier 3.
- Audits on Tier 3 default to **TRIM** (with the usual cross-module grep of
  `examples/*` separate-module consumers, which workspace-scoped
  `moon ide` cannot see).

`lib/*` workspace members and submodules are separate modules with their own
versioning; they are out of scope for this record.

### Naming convention

Symbols named `*_internal` (e.g. `apply_text_edit_internal`) are
implementation detail **regardless of visibility**, in every tier. New
library API must not use the suffix; existing `pub *_internal` symbols are
candidates for narrowing, not for external documentation.

## Consequences

- Audit framing stops being re-litigated: tier decides the default verdict.
- The redesign's migration stages have a ground truth for "which breaks need
  compatibility shims" (Tier 1: always; Tier 2: for language implementers;
  Tier 3: none).
- A future published release needs only Tier 1 (and the Tier 2 contract doc)
  to be clean — a concrete, bounded milestone instead of "audit everything".

## Deferred

- The per-symbol audit sweep itself (TODO §7 aggregator-trim item) — now
  executable against this boundary.
- A release plan / first published version milestone (TODO §14 optional
  exit) — separate decision once Tier 1 `.mbti` surfaces are stable.
- Tier assignment for `ffi/host` and `lang/runtime` packages that do not
  exist yet — assigned in their introducing PRs (expected: ffi/host Tier 3,
  lang/runtime Tier 2). `sync_session` (Tier 1) and `transport_ws` (Tier 3)
  were assigned in redesign S2, their introducing PR; see the tier tables
  above.
