# Cognition Runtime Recompute Strategy Follow-up

> **Archived 2026-05-26.** This dependency-cleanup follow-up shipped in
> PR #358 (`4c5e0bb`): deleted-file dependency edges are cleaned, graph
> invariants are tested, caller-string path identity is pinned, and rename/move
> semantics are documented as delete+add. It is no longer an active
> `docs/TODO.md` item.

## Why

PR #355 added the minimal cognition runtime; PR #357 added workspace file
registry and explicit file removal. The next follow-up should decide whether to
keep derived artifact recomputation explicit in `CognitionStore` or start moving
`FileSummary`, `RepoSummary`, and `QueryContext` into `@incr` cells.

Decision: keep artifact recomputation explicit for the next follow-up. Use the
follow-up to tighten dependency cleanup and graph invariant tests. Treat an
`@incr` artifact migration as a separate spike after the domain graph invariants
are pinned.

## Scope

In:
- `lib/cognition/store.mbt`
- `lib/cognition/cognition_test.mbt`
- `lib/cognition/reactive.mbt` only if metadata snapshots need a tiny helper

Out:
- real LLM calls
- frontend integration
- vector database, network sync, CRDT changes, or agent framework work
- WS2 editor coordinator/shared-runtime migration work
- canvas/workflow UI work
- file rename/move semantics beyond documenting whether they are delete+add for now
- broad path canonicalization beyond pinning the current path-identity contract
- performance optimization; this plan may add measurement hooks or benchmark
  gates, but optimization still requires a measured bottleneck first

## Current State

- Architecture scope and non-goals are `docs/architecture/cognition-runtime.md`.
  The runtime is a small, separate graph with deterministic mock recomputation.
- `CognitionStore` owns artifact values, file registry, revisions,
  dependencies, reverse dependencies, dirty keys, recompute counts, and a small
  `CognitionReactive` metadata wrapper.
- `CognitionReactive` currently backs store-wide revision and dependency-edge
  snapshots only. Artifact values are not `@incr` cells.
- `lib/cognition/cognition_test.mbt` is the behavior contract: input
  validation, sorted registry, explicit removal, dirty propagation, selective
  recomputation, first-build seeding, immutable returned values, and demo trace.

## Option A: Keep Store-explicit Recompute

Use `CognitionStore` as the source of truth for the domain dependency graph and
keep `@incr` limited to metadata snapshots.

Benefits:
- Preserves the current public API and test contract directly: callers can still
  inspect dirty keys, dependency edges, recompute order, and recompute counts.
- Keeps artifact lifecycle explicit. File removal can synchronously clean stored
  values, revisions, dependency records, reverse edges, and counts.
- Avoids a dual source of truth between domain dependency maps and `@incr`'s
  internal graph.
- Fits the current mock runtime: the hard problems are registry/removal and
  dependency invariants, not expensive recomputation.

Costs:
- Manual dependency bookkeeping must be kept correct.
- Dynamic dependencies such as repo summary adopting newly registered files need
  targeted tests.

Follow-up work, in priority order:
1. Add invariant-oriented tests around dependency cleanup, separating the two
   observable phases:
   - immediately after `remove_file("a.mbt")` in a graph containing `a.mbt` and
     `b.mbt` after `compute(QueryContext("what changed?"))`: `known_files()`
     excludes `a.mbt`, `get_value(FileText("a.mbt"))` and
     `get_value(FileSummary("a.mbt"))` are `None`, and `RepoSummary` plus
     `QueryContext("what changed?")` are dirty;
   - after `recompute_dirty()`: `dependency_edges()` contains no edge mentioning
     `a.mbt`, `dependents_of(FileText("a.mbt"))` and
     `dependents_of(FileSummary("a.mbt"))` are empty, and `RepoSummary`
     dependencies contain `FileSummary("b.mbt")` but not
     `FileSummary("a.mbt")`.
2. Pin the current path-identity contract with a small test. Today the store keys
   paths as caller strings; decide explicitly whether `./foo.mbt` and `foo.mbt`
   are distinct in this package. Do not implement canonicalization until a
   workspace/root policy exists. Add a doc note only if the tested behavior needs
   explanation for callers.
3. Document rename/move as delete+add for this milestone: callers should model a
   rename or move as `remove_file(old_path)` followed by
   `set_input(FileText(new_path), Text(contents))`, unless a separate plan
   introduces explicit identity-preserving file moves.
4. Factor small cleanup helpers if needed, e.g. remove incoming references to an
   artifact key in addition to removing its outgoing dependency record.
5. Add a compact architecture-doc example showing the dependency graph before
   and after `remove_file`, if the cleanup behavior changes or new invariants are
   not obvious from API names.
6. Keep this follow-up focused on deterministic tests. A separate generated
   add/edit/remove sequence property test can follow if the deterministic tests
   reveal broader graph-state risk. That property should assert that every
   dependency edge references either an active `FileText`, an active
   `FileSummary`, `RepoSummary`, or a live `QueryContext`, and generators should
   crash on invalid generated states rather than silently skip them.
7. Keep `lib/cognition/reactive.mbt` as metadata-only unless a test exposes a
   missing dependency-edge snapshot bump.

## Current Hybrid: Metadata-only `@incr`

This is the current architecture: `CognitionReactive` uses `@incr` for the
store-wide revision input and dependency-edge snapshot, while artifact values
and domain dependencies remain explicit in `CognitionStore`.

Keep this hybrid shape for the next follow-up.

Benefits:
- Preserves the current public API while still exercising the `@incr` substrate
  for metadata that is safe to snapshot.
- Avoids dynamic artifact-cell lifecycle and disposal work during file-removal
  cleanup.
- Leaves a migration seam: more metadata can move into `CognitionReactive` only
  when it does not duplicate the domain dependency graph.

Guardrails:
- Do not mirror `values`, `dirty`, or per-artifact recompute state into `@incr`
  without a test that proves the explicit store has become insufficient.
- If a benchmark or production trace motivates artifact cells, prototype one
  artifact family first and preserve the current tests unchanged.

## Option B: Move Artifacts into `@incr` Cells

Represent file summaries, repo summary, and query contexts as `@incr.Input` /
`@incr.Derived` chains and read them through persistent `Watch` anchors.

Potential benefits:
- Lets the `@incr` runtime track cell-level dependencies automatically.
- Could become useful once artifact recomputation is expensive or when multiple
  derived views share a richer graph.

Costs and blockers:
- Dynamic keys require lifecycle design: one cell per file and one cell per
  query, plus disposal/removal semantics for deleted files and stale queries.
- The current public API exposes domain-level dirty state, dependency edges, and
  recompute counts. A cell migration must either emulate those explicitly or
  change the behavior contract.
- `dependency_edges()` currently returns domain edges (`RepoSummary ->
  FileSummary(path)`), not raw `@incr` internals. Keeping that API likely still
  needs explicit dependency maps, creating duplicate bookkeeping.
- `@incr` usage must obey the persistent-anchor rule: long-lived derived chains
  stored in a struct need `Watch`/`Scope` ownership; reads inside compute closures
  should use `.get()` / `.get_or_abort()`, while store methods should use watch
  reads outside the graph.
- Removal must avoid retained cells for deleted files; otherwise the first
  registry follow-up risks turning into a memory/lifecycle migration.

If this is revisited, run it as a narrow spike:
1. Prototype only `FileSummary(path)` as a per-file derived cell while preserving
   the existing `CognitionStore` API.
2. Add lifecycle tests for file removal and deleted-cell disposal before moving
   `RepoSummary` or `QueryContext`.
3. Keep the current tests unchanged; any required test rewrite is evidence that
   the migration is no longer a small follow-up.

## Acceptance Criteria for the Next Follow-up

- [ ] Existing `lib/cognition/cognition_test.mbt` behavior remains unchanged.
- [ ] At least one deterministic stale-edge test covers removing one file from a
      two-file repo/query graph.
- [ ] Immediately after `remove_file(deleted_path)` in a test that already ran
      `compute(QueryContext("what changed?"))`, `known_files()` excludes the
      deleted path, deleted `FileText`/`FileSummary` values are absent, and
      `RepoSummary` plus `QueryContext("what changed?")` are dirty.
- [ ] At minimum after `recompute_dirty()`, no `Dependency` returned by
      `dependency_edges()` mentions the deleted path. It is acceptable if the
      implementation provides this stronger guarantee immediately after
      `remove_file`.
- [ ] After `recompute_dirty()`, `dependents_of(FileText(deleted_path))` and
      `dependents_of(FileSummary(deleted_path))` are empty.
- [ ] After `recompute_dirty()`, `RepoSummary` dependencies contain the remaining
      file summary and do not contain the deleted file summary.
- [ ] Current path identity is pinned by a test: either `./foo.mbt` and `foo.mbt`
      are distinct, or a separate canonicalization plan owns changing that
      behavior.
- [ ] Rename/move semantics are documented as `remove_file(old_path)` plus
      `set_input(FileText(new_path), Text(contents))`, unless an explicit move API
      is introduced by a separate plan.
- [ ] `moon -C lib/cognition check` and `moon -C lib/cognition test` pass.
- [ ] No real LLM, frontend, CRDT, network, vector DB, or agent-framework scope
      enters the change.

## Measurement Gate

Do not move artifacts into `@incr` for performance reasons without fresh data.
If explicit recomputation becomes suspect, add a small benchmark or trace that
reports file count, dependency-edge count, dirty-key count, recompute counts, and
wall-clock time for representative add/edit/remove/query sequences. Use that data
to decide whether an artifact-cell spike is justified.

## Validation

```bash
moon -C lib/cognition check
moon -C lib/cognition test
moon check
moon test
```

## Recommendation

Implement Option A next, keeping the current Option C metadata-only hybrid. The
current risk is explicit graph hygiene, and moving artifacts into `@incr` would
add dynamic-cell lifecycle work before the domain invariants are fully tested.
Reconsider Option B only after cleanup tests make the artifact graph contract
precise and fresh measurements show pressure for cell-level recomputation.
