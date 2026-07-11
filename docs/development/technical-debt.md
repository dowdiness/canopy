# Paying Technical Debt

This repository is a monorepo with reusable MoonBit submodules and an
application layer on top. Technical debt should be paid where the underlying
design pressure originates, not where it first becomes inconvenient.

## Core Rule

**Fix debt in the owning module. Do not accumulate downstream workarounds.**

Examples from this codebase:

- If `SyncEditor` needs range deletion but `TextState` only exposes single-item
  delete, the real fix belongs in `event-graph-walker/text`, not in more helper
  loops inside `editor/`.
- If multiple root packages need old/new text diffing, centralize that logic
  once in a shared root package instead of reimplementing prefix/suffix scans in
  `editor/`, `projection/`, and examples.
- If old projection-era APIs no longer describe the live editor flow, retire or
  archive them instead of keeping them half-active.

## Strategy

### 1. Fix at the Boundary That Owns the Invariant

Ask which package owns the invariant that is being violated:

- `event-graph-walker/` owns CRDT editing primitives and undoable text APIs
- `loom/` owns parser/edit representations and incremental parsing semantics
- `editor/` owns orchestration of CRDT + parser + projection derivation
- `projection/` owns pure tree/projection transforms and UI-state structures
- `cmd/`, `crdt.mbt`, and examples own I/O and presentation edges

Patch the lowest layer that can solve the problem cleanly.

### 2. Keep One Active Architecture

When a new design replaces an old one, prefer:

1. migrate callers,
2. delete or archive the retired path,
3. update docs immediately.

Do not leave parallel “temporary” flows alive unless both are still required by
shipping code.

### 3. Centralize Shared Logic Once

If two active packages need the same logic:

- extract a shared package at the root module boundary,
- keep package-specific adapters thin,
- delete duplicate implementations.

The shared package should hold the domain logic; adapters should only translate
to local return types.

### 4. Isolate Workarounds and Name the Missing API

Sometimes a local workaround is necessary. When that happens:

- keep it in one helper,
- comment which upstream API is missing,
- state which module should absorb the real fix,
- avoid copying the workaround elsewhere.

This turns “mystery behavior” into an explicit debt marker.

### 5. Avoid Upward Dependencies

Submodules are reusable libraries. Do not make lower-level or standalone
packages depend upward on the root `crdt` application package just to reuse a
helper.

If shared logic is truly cross-cutting, move it to a lower shared boundary.
Otherwise, keep the duplication local and intentional until a better boundary
exists.

### 6. Treat Docs as Part of the Debt Payment

In this repository, stale docs are operational debt. They misroute future work.

When changing architecture:

- update contributor-facing docs in `docs/architecture/` and `docs/design/`,
- update comments on the live code path,
- leave archive/plans alone unless they are being promoted back into active use.

## Refactor Order

Use this order for debt work:

1. Remove misleading docs/comments about the active path.
2. Centralize duplicated logic.
3. Split low-cohesion files inside the same package.
4. Move fixes into the owning submodule when an app-layer workaround reveals a
   missing core API.
5. Delete compatibility-only surfaces once callers are gone.

## Validation

Debt-payment changes still need the normal MoonBit workflow:

```bash
moon test
moon info
moon fmt
moon check
```

If a change crosses into a submodule, run that submodule's tests there as well.

## Current Active Debt Targets

As of 2026-03-15, the highest-value debt to pay next is:

1. Add range-delete support to `event-graph-walker/text` so `editor/` no longer
   needs character-by-character deletion loops.
2. Continue retiring projection compatibility-era public surface that is no
   longer part of the `SyncEditor` path.
3. Keep active architecture docs aligned with the current
   `SyncEditor -> TextState + UndoManager + ImperativeParser + memo-derived projection`
   design.

Detailed execution plan:

- [Boundary Correction And Cross-Module Deduplication](../archive/completed-phases/2026-03-15-boundary-correction-and-dedup-plan.md) (Complete)
