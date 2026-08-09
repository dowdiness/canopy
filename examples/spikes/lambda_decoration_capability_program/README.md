# Lambda decoration capability through a Formula

- **Reader:** Canopy and Incr maintainers reviewing a typed decoration seam.
- **Decision:** Determine whether the production decoration closure has exact ordered-array parity when projection, source-map, and external pattern analysis are typed ports.
- **Keep until:** This evidence receives review or is superseded.
- **Disposition:** Keep this executable spike as provisional evidence; move a durable decision to an ADR or remove it after review.

## Verdict

**Pass with constraints.** The Formula matches the production
`LanguageCapabilities.get_decorations` result for the finite workloads in the
disabled white-box test. This authorizes no production migration.

The imperative bridge receives an explicit `PatternState` value. It creates
separate defensive snapshots for `LambdaCompanion::set_pattern_analysis` and
`Source[PatternState?]`; both the outer facts array and each captures map are
copied. Projection, source-map, and the owned pattern snapshot are staged in one
shadow transaction. Clearing calls `clear_stale_pattern_analysis` and stages
`None`.

The Formula reads only its three declared ports: projection, source-map, then
pattern-state. `None` projection observes projection plus pattern-state; `Some`
observes all three. It performs semantic decoration construction first and
appends `@analysis.facts_to_decorations` output in fact order. No `Ref`,
`AnalysisProjection`, `LambdaCompanion`, editor, clock, or mutable host state is
captured or read by the callback.

The oracle is the production `LanguageCapabilities.get_decorations` closure,
reached through a fresh `ViewUpdateState` and `@editor.compute_view_patches`.
The emitted `SetDecorations` patch supplies the value; the updater's missing
initial empty patch means the exact array is empty. This deliberately tests the
raw capability closure. The Lambda FFI wrapper's pre-call stale clearing is a
separate imperative-shell policy and is not claimed by this spike.

## Workloads and boundaries

The test uses `(x) => x`, `SourceSnapshot`, and
`@analysis.from_ast_grep_matches(AstGrepMatch...)`. It covers empty/semantic
only, one and multiple ordered pattern facts, source and projection changes,
facts-only updates, editor-only updates with deliberately retained facts, a
three-source one-revision transaction, removal to `None`, and stale clear with
an empty target. It asserts full ordered `Array[Decoration]` equality plus
semantic and pattern CSS classes, manifest order, observation ordinals, and a
Formula/export local provenance pair.

Editor-only changes intentionally retain stored facts: `facts_to_decorations`
checks each fact against the stored snapshot, not the editor's new snapshot.
The later stale-clear workload drops both sides.

## Existing API First and limits

Reused APIs are `build_semantic_projection`, `facts_to_decorations`,
`compute_view_patches`, `SourceSnapshot::matches`, and typed `Source`/`View` /
`Store::transaction`/`Program`/`Formula`. `Map`, `Array`, `Option`, `Result`,
`String`/`StringView`, `Bytes`/`BytesView`, `Buffer`, and `cmp` were checked;
`Array`, `Option`, and `Result` are used, while `Set`, byte/string views,
`Buffer`, and `cmp` do not fit this evidence. No production helper is added.

Limitations are a manual bridge, sequential shadow-transaction evidence rather
than a cross-runtime or concurrency proof, no migration or automatic runtime
integration, no FFI stale-policy parity claim, local rather than generic
provenance, and open deep `Result` composition. Production retains its Ref as
the unchanged oracle implementation; the shadow Formula receives only an owned
Source value and performs no hidden Ref read.

Run from the repository root:

```bash
bash examples/spikes/lambda_decoration_capability_program/run.sh
```
