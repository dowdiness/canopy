# Design: Boundary Correction And Cross-Module Deduplication

**Parent:** [Paying Technical Debt](../development/technical-debt.md)
**Related:** [Module Structure](../architecture/modules.md), [Design Concerns](../design/design-concerns.md)
**Status:** Proposed
**Date:** 2026-03-15

---

## Problem

The repository has several places where logic or contracts live on the wrong
side of a package boundary:

- contiguous text-change logic exists in three places:
  - root `crdt/text_change`
  - `loom/core/delta`
  - `valtio/src/egwalker`
- `event-graph-walker` still contains a dead duplicate undo contract
- `SyncEditor` contains a character-by-character delete workaround for a missing
  CRDT text API
- `loom/graphviz` duplicates the canonical `graphviz` parser package
- `loom/incr` repeats low-level metadata access and handle wrappers across cell
  kinds

The result is not just duplicate code. Ownership is blurred:

- app-layer packages compensate for missing lower-level APIs
- standalone submodules are tempted to depend upward for reuse
- the same responsibility appears to have multiple owners

This plan fixes those boundary problems in dependency-safe order.

## Goal

Realign ownership so that:

1. each shared responsibility has one owner
2. dependency direction stays downward from apps to reusable libraries
3. hot-path duplication is removed without adding runtime overhead
4. temporary workarounds are replaced by upstream API fixes
5. active code paths are easier to reason about than compatibility layers

## Non-Goals

- No redesign of the active `SyncEditor` architecture
- No macro-style abstraction or code generation
- No `&Trait`-based indirection added to hot paths
- No forced unification of unrelated domain types just because they are
  structurally similar
- No standalone release-process overhaul in the first code changes

---

## Constraints

### Dependency Constraints

- `loom`, `event-graph-walker`, `graphviz`, `svg-dsl`, and `valtio` are
  reusable submodules and must not depend upward on the root `crdt` app module.
- Shared extraction must preserve an acyclic package graph.
- `loom/loom` already depends on `antisatori/graphviz`; any graphviz cleanup
  should converge on that canonical owner rather than introducing a third home.
- Shared leaf utilities used by both `crdt` and submodules should be created as
  independent MoonBit modules at monorepo root, not as packages inside the root
  `dowdiness/crdt` application module.

### Language Constraints

- MoonBit does not support the blanket-impl shape needed for:

```moonbit
impl[T : HasCellMeta] CellOps for T
```

- MoonBit does support supertraits and default trait methods, so repeated
  `CellOps` boilerplate can be reduced with:

```moonbit
trait CellOps: HasCellMeta { ... }
impl CellOps with ...
impl HasCellMeta for PullSignalData with meta(self) { self.meta }
impl CellOps for PullSignalData
```

This keeps dispatch cost unchanged while reducing repetition.

### Performance Constraints

- Text edit, parser edit, and recomputation hot paths must remain allocation- and
  dispatch-conscious.
- Shared abstractions should carry plain values and use static dispatch whenever
  possible.
- Any D05 cleanup in `loom/incr` must preserve the existing `&CellOps` usage
  pattern rather than introducing more runtime indirection.

---

## Active Boundary Problems

## D03. Duplicate Undo Contract In `event-graph-walker`

Two `Undoable` traits exist:

- public owner: `event-graph-walker/undo/undoable.mbt`
- dead duplicate: `event-graph-walker/internal/document/undoable.mbt`

The internal version is not part of the active path and should be deleted.

## D06. Missing Range Edit API In CRDT Text Layer

`SyncEditor` currently loops character-by-character because `TextDoc` only
offers single-item deletion:

- workaround owner today: `editor/sync_editor_text.mbt`
- real owner: `event-graph-walker/internal/document` and `event-graph-walker/text`

This debt should be paid in the CRDT text API, not in more editor helpers.

## D01. Shared Text-Change Logic With Wrong Ownership

The pure prefix/suffix contiguous diff is conceptually leaf logic, but the
current root `crdt/text_change` package depends on `loom/core`.

That means `loom/core` cannot depend on the current package without creating an
upward dependency and likely a cycle. The shared owner therefore cannot be the
current root package.

The correct direction is:

- create a new leaf package with a pure `TextChange` algorithm
- adapt that result outward for parser edits, text deltas, and Valtio ops

## D07. Root Wrapper Around Shared Text Change

`editor/text_diff.mbt` still defines `TextSplice`, which is structurally the
same concept as `TextChange`. Once D01 lands, this wrapper should be collapsed
to the shared type or reduced to parser-facing helpers only.

## D02. Duplicated Graphviz Parser Ownership

The canonical parser lives in `graphviz/src/lib/parser`, but `loom/graphviz`
contains a second copy of the parser stack under the same module name
`antisatori/graphviz`.

This is a boundary failure, not just code duplication. The same logical package
has two code owners.

## D04 and D05. Repeated `loom/incr` Handles And Metadata Plumbing

`SignalId`, `MemoId`, `RelationId`, `RuleId`, and `ReactiveId` are scattered
across files even though they all wrap `CellId`.

Likewise, `CellOps` impls repeat the same field forwarding across cell kinds.
These are lower-priority cleanups than D03/D06/D01 because they are local to
`loom/incr` and do not currently force upstream workarounds.

---

## Proposed Direction

## 1. Remove Dead Duplicates First

Delete code that no longer owns anything:

- remove `event-graph-walker/internal/document/undoable.mbt`

This is a safe warm-up change that reduces ambiguity before any API work.

## 2. Move Missing Capability Into The Owner

Add range-oriented text mutation where the invariant belongs:

- `Document::delete_range(start : Int, end : Int)`
- likely `Document::replace_range(start : Int, end : Int, text : String)`
- public `TextDoc` wrappers
- undo-aware range helpers for `TextDoc + UndoManager`

Then delete the editor-side span workaround.

Important boundary rule:

- `event-graph-walker/internal/document` must not depend on the public
  `event-graph-walker/text.Range` type
- the internal API should use primitive coordinates or an internal range type
- the public `TextDoc` layer can wrap that internal API with `@text.Range`

Undo scope rule for D06:

- reuse the existing `UndoManager` grouping mechanism
- record one range operation as one undo entry even if it contains multiple
  low-level items internally
- do not expand D06 to include a new `UndoManager` batch abstraction

## 3. Extract Pure Text Change To A Real Leaf

Introduce a small shared module that contains only:

```moonbit
pub struct TextChange {
  start : Int
  delete_len : Int
  inserted : String
}

pub fn compute_text_change(old_text : String, new_text : String) -> TextChange
```

Recommended placement:

- `lib/text-change/` as a monorepo-root sibling of `loom/`,
  `event-graph-walker/`, `graphviz/`, and `valtio/`
- with its own `moon.mod.json` so `crdt`, `loom`, and `valtio` all depend
  downward on the same leaf module
- start as a monorepo-local path dependency first; do not optimize for
  standalone publishing until the D01/D07 adapter and API shape has stabilized

Important rule:

- the package must implement the prefix/suffix algorithm directly
- it must not depend on `loom/core`
- it must be usable by `loom/core`, root `crdt`, and `valtio`

Adapters then stay local:

- `loom/core`: `TextChange -> Array[TextDelta]`
- root `crdt/editor`: `TextChange -> parser Edit`
- `valtio`: `TextChange -> DiffOp`

## 4. Converge On One Graphviz Parser Owner

Treat `graphviz/src/lib/parser` as canonical and retire `loom/graphviz`.

This cleanup should be split into two concerns:

1. code ownership cleanup inside the monorepo
2. standalone `loom` release/dependency policy

The first is a code refactor. The second is a packaging/release decision and
should not block earlier technical cleanup.

## 5. Use Supertraits To Reduce `loom/incr` Boilerplate

Adopt this pattern inside `loom/incr`:

```moonbit
priv struct CellMeta {
  cell_id : CellId
  label : String?
  mut changed_at : Revision
  mut durability : Durability
  subscribers : HashSet[CellId]
}

priv trait HasCellMeta {
  meta(Self) -> CellMeta
}

trait CellOps: HasCellMeta {
  cell_id(Self) -> CellId = _
  label(Self) -> String? = _
  changed_at(Self) -> Revision = _
  set_changed_at(Self, Revision) -> Unit = _
}
```

Then keep explicit per-type impls:

- `impl HasCellMeta for PullSignalData ...`
- `impl CellOps for PullSignalData`

This is the correct compromise for current MoonBit:

- less boilerplate
- no blanket impl
- no extra runtime overhead

Do not force every `CellOps` method through `CellMeta` if a cell kind has
special semantics. Shared defaults should only cover truly shared fields.
Outliers keep explicit overrides, for example:

- `PushEffectData` sentinel behavior for `changed_at` / `durability`
- push-cell `level()` accessors
- any cell kind whose subscriber or durability semantics differ from the common
  storage model

## 6. Consolidate Handle Wrappers Late

After D05 is stable, move ID wrappers into `loom/incr/types` or a dedicated
handles file and re-export them from `loom/incr`.

This is mostly a cohesion cleanup and should not be interleaved with higher-risk
API work.

Keep nominal wrapper types rather than collapsing them into untyped aliases.
The goal is shared location and clearer ownership, not weaker type distinction.

---

## Migration Order

Apply changes in this order:

1. **D03** Delete the dead internal undo trait.
2. **D06** Add range edit APIs to `event-graph-walker` and remove editor-side
   span-delete loops.
3. **D01** Extract pure text change into a leaf package and migrate adapters.
4. **D07** Remove `TextSplice` duplication and collapse editor wrappers.
5. **D02** Retire `loom/graphviz` and converge on canonical graphviz ownership.
6. **D05** Introduce `HasCellMeta` + supertrait-backed `CellOps` defaults.
7. **D04** Consolidate ID wrappers in `loom/incr/types`.

Rationale:

- start with dead-code and owner-local API cleanup
- pay the hottest downstream workaround before moving abstractions
- leave repo-boundary and lower-priority internal cleanup until after the core
  ownership fixes are done

---

## Package-Level Plan

## Root `crdt`

- stop owning logic that should be leaf-shared
- reduce `editor/text_diff.mbt` to parser-facing adaptation only
- keep `SyncEditor` orchestration as the integration boundary

## `event-graph-walker`

- own text mutation primitives completely
- expose the batch/range operations the editor needs
- remove stale internal contracts that no longer describe the public path

## `loom`

- own parser-specific delta/edit representations
- consume leaf text-change logic rather than root app helpers
- reduce `incr` metadata boilerplate with supertraits and shared metadata fields

## `graphviz`

- remain the only owner of DOT parser/formatter/trait logic
- become the single package imported by `loom/viz`

## `valtio`

- consume shared text-change logic as an adapter target
- do not become the owner of another local diff algorithm

---

## Resolved Decisions

### Leaf Text-Change Placement

The shared `TextChange` owner should be an independent MoonBit module at
monorepo root:

- `lib/text-change/`

This is cleaner than placing it under the root `dowdiness/crdt` module because
both the app and submodules can depend on it downward without ambiguity.

Initial dependency mode:

- start with monorepo-local path dependencies
- postpone standalone publishing and versioned reuse until the shared API and
  adapter shapes are stable after D01 and D07
- decide standalone release policy together with other submodule packaging work
  such as the D02 follow-up

### Graphviz Convergence Scope

D02 should fix code ownership inside the monorepo only:

- point `loom` at the canonical `graphviz/` via path dependency
- delete `loom/graphviz`
- move any unique tests into canonical `graphviz`

Do not couple D02 to a standalone release-process redesign. Standalone
`loom -> graphviz` packaging policy is a separate follow-up task.

### Projection Compatibility Types

`ProjectionEdit` and `ModelOperation` should not be retired speculatively.

D07 includes a real usage audit:

- if there are no active callers after `TextChange` unification, retire them
- if live callers remain, keep them as compatibility adapters over `TextChange`

### D06 Undo Scope

For D06, range undo should use the existing `UndoManager` grouping behavior:

- represent a range edit as one undo entry
- allow that entry to contain multiple low-level items internally
- avoid introducing a new explicit batch or range abstraction in `UndoManager`
  during D06

If future requirements need atomic grouping of multiple distinct range edits,
that should be a later focused design, not part of this phase.

---

## Validation

Each phase should compile and test independently.

### Root repo

```bash
moon fmt
moon check
moon test
moon info
```

### Cross-submodule work

For any phase touching submodules, also run the submodule-local checks:

```bash
cd event-graph-walker && moon check && moon test
cd loom/loom && moon check && moon test
cd loom/incr && moon check && moon test
cd graphviz && moon check && moon test
```

### Additional checks by phase

- D06: add regression tests for range delete/replace and undo grouping
- D01/D07: keep adapter tests in each consumer package, but move algorithm tests
  to the leaf package
- D02: verify `loom/loom/src/viz` still resolves DOT parse/format APIs from the
  canonical graphviz package
- D05: verify no new hot-path trait-object usage is introduced

---

## Remaining Open Questions

1. After D02, when should standalone `loom` switch from monorepo path
   dependencies to versioned published dependencies for shared libraries such as
   `graphviz` and the future `lib/text-change`?
2. After D07, are `ProjectionEdit` and `ModelOperation` fully unused, or do any
   external or example-facing compatibility callers still need them?

These questions affect packaging and later compatibility cleanup, but they do
not block D03 and D06.
