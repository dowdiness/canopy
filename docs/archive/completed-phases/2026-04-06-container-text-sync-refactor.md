# Container Text Sync Refactor

**Status:** Complete

## Completion

This plan is complete.

Delivered:
- `Lv` and per-block `ItemId` are separated along the container text path.
- `container.Document` now has replayable text-op history, remote apply,
  dependency buffering, causal-parent-preserving sync export/import, and
  incremental export by version vector.
- The block editor now exposes this sync surface as the first real canopy-side
  consumer, with convergence coverage at the `BlockDoc` layer.

Follow-on work:
- Treat Phase 3 unified sync as a separate task.
- Keep relay/browser/WebSocket integration on the later integration plans,
  rather than extending this refactor plan further.

## Why

`event-graph-walker/container/` currently has tree-level remote sync primitives,
but block text is still a local-only wrapper around per-block `FugueTree`.
That is enough for Phase 2 text editing, but it is the wrong substrate for
Phase 3 unified sync: there is no per-block text op history, no export/import
boundary, and no merge path that composes with one shared document causal
graph.

The existing text sync stack in `internal/document/`, `internal/oplog/`, and
`internal/branch/` already solves export/import, dependency buffering, frontier
diffing, and merge ordering, but it assumes `Lv == Fugue item identity`. The
container path currently also relies on that coupling by storing per-block
`FugueTree`s directly with global document LVs as item ids, which produces the
architectural mismatch we want to avoid before building document-wide sync.

This task defines the refactor that should happen before Phase 3 lands, so that
unified sync is built on a stable text sync substrate rather than on a local
editing shortcut that would later be removed.

## Scope

In:
- `event-graph-walker/container/document.mbt`
- `event-graph-walker/container/text_block.mbt`
- `event-graph-walker/container/text_ops.mbt`
- `event-graph-walker/internal/fugue/`
- `event-graph-walker/internal/oplog/`
- `event-graph-walker/internal/branch/`
- `event-graph-walker/internal/document/`
- `event-graph-walker/container/*test.mbt`
- `event-graph-walker/internal/*test.mbt`
- `docs/TODO.md`

Out:
- Phase 3 document-wide `SyncMessage` and relay/browser integration
- Phase 4 document-level undo
- unrelated text-editor UX changes in canopy/editor or examples
- speculative optimizations not required by the new container text sync boundary

## Current State

- `container.Document` exports/applies only tree operations via
  `export_ops()` / `apply_remote_op()` in
  `event-graph-walker/container/document.mbt`.
- `container.TextBlock` is a thin local-only wrapper over `FugueTree[String]`
  with direct `insert_at` / `delete_at` mutation in
  `event-graph-walker/container/text_block.mbt`.
- Standalone text sync already exists in `internal/document/document.mbt`,
  backed by `internal/oplog/oplog.mbt` and `internal/branch/`.
- `FugueTree` storage is sparse and indexed directly by `Lv` in
  `internal/fugue/tree.mbt`.
- `OpLog`, `Branch`, `MergeContext`, and `DeleteIndex` all assume a single
  local integer is both the causal-graph LV and the Fugue item identity.

## Desired State

- Container block text has a real sync substrate: text operations can be
  recorded, exported, imported, and merged independently of tree ops.
- Shared document causal ordering and per-block text storage are separated
  cleanly enough that Phase 3 can add a document-wide sync protocol without
  first reworking the text internals again.
- The owning abstraction boundary is explicit:
  either container text reuses `OpLog`/`Branch` through a clean adapter, or the
  internals are refactored so `Lv` and per-block item identity are distinct.
- The post-refactor container text path is the one Phase 3 will build on; no
  second text sync architecture remains active.

## Decision To Make Up Front

Chosen path: **split-identity path**

Decision:
- Treat shared causal versioning and per-block Fugue storage identity as
  different concepts.
- Keep `RawVersion` / `(agent, seq)` as the canonical globally unique
  operation identity.
- Keep `Lv` as the replica-local causal-graph handle for those operations.
- Introduce `ItemId` as the per-block Fugue storage identity.

Why this path:
- The container design wants one shared document causal graph across tree ops
  and all block text ops.
- The current standalone text stack (`internal/document`, `internal/oplog`,
  `internal/branch`) assumes one integer can serve as both the causal-graph
  handle and the Fugue item identity.
- That coupling was acceptable when there was a single text CRDT, but it is the
  wrong model once one shared causal history spans many per-block text
  sequences.
- The eg-walker model and reference implementation distinguish globally unique
  operation identity from internal local integer handles. That supports the
  direction here even though this plan still needs to choose its own concrete
  type boundaries.
- Reusing the current `Lv == item id` coupling for container Phase 3 would
  likely make unified sync easier to prototype but would bake in an identity
  model we already expect to remove.

Consequences:
- Refactor `fugue`, `oplog`, `branch`, and container text code so per-block
  Fugue storage no longer depends on global document LVs as array indices.
- Build the container text sync substrate on top of that separation before
  implementing Phase 3 unified sync.
- Do not pursue the adapter path unless this plan is explicitly revised.

## Steps

1. Write a short design note inside this plan that chooses the adapter path or
   the split-identity path, with explicit reasons grounded in the current code.
2. Before changing internals, add characterization tests for current behavior:
   example tests for existing container text semantics and property-based tests
   for convergence, block independence, and delete/undelete winner rules.
   These tests should fail only on real behavioral drift, not on the internal
   shape of the implementation.
3. Introduce the minimal text-sync substrate required by that decision:
   per-block op history, remote-apply path, and version/frontier export surface.
4. Refactor container text editing to use that substrate instead of mutating
   `FugueTree` directly as a local-only shortcut.
5. Add or extend tests for the new substrate surface that did not exist before:
   remote text import with dependency buffering at container level,
   convergence across two replicas with interleaved tree and text history,
   and, if the split-identity path is chosen, behavior independence from any
   accidental `Lv == ItemId` assumption.
6. Update the backlog item so this plan is the canonical execution spec and
   Phase 3 can depend on it explicitly.

## Acceptance Criteria

- [ ] `container` text is no longer local-only; it has an explicit export/import
      and merge boundary suitable for Phase 3.
- [ ] The chosen architecture path is documented here before or alongside the
      first code change.
- [ ] Characterization tests for pre-refactor container text behavior exist
      before the internal refactor starts.
- [ ] There is one clear owner for text sync internals; no duplicate temporary
      sync path remains in container code.
- [ ] Two replicas can converge on per-block text state through the new
      container text sync substrate.
- [ ] Property-based tests cover convergence and at least one identity or
      isolation invariant relevant to the chosen architecture path.
- [ ] `docs/TODO.md` links this task to this plan instead of carrying the full
      implementation argument inline.

## Validation

```bash
cd event-graph-walker && moon check
cd event-graph-walker && moon test
moon check
moon test
```

Add targeted microbenchmarks if the chosen path changes storage density or
merge complexity in a way that could regress large multi-block documents.
Keep the property-based tests in the default `moon test` path rather than as a
separate optional suite unless runtime becomes prohibitive.

## Risks

- The adapter path may get unified sync working faster but preserve the wrong
  identity model, forcing a second migration soon after.
- The split-identity path is architecturally cleaner but touches core text
  internals (`fugue`, `oplog`, `branch`) and can widen the blast radius.
- Container tree sync currently uses a simpler tree-op export/apply flow; the
  eventual Phase 3 protocol will still need a clean composition story across
  tree and text messages.

## Notes

- Related design: `docs/plans/2026-03-29-container-design.md`
- Related completed phase: `docs/archive/completed-phases/2026-04-03-container-phase2-text.md`
- Key code references:
  `event-graph-walker/container/document.mbt`
  `event-graph-walker/container/text_block.mbt`
  `event-graph-walker/internal/document/document.mbt`
  `event-graph-walker/internal/oplog/oplog.mbt`
  `event-graph-walker/internal/branch/branch.mbt`
  `event-graph-walker/internal/fugue/tree.mbt`
