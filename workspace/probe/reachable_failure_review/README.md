# PROTOTYPE — ReachableFailure review boundary

Run:

```bash
node workspace/probe/reachable_failure_review/tui.mjs
```

## Question

Does an opt-in wrapper beside `apply_lambda_tree_edit` provide the right
ownership boundary for one agent-authored Lambda edit? The wrapper snapshots
scope failures before the edit, delegates the mutation to the existing edit
path, reads the recomputed failures, and returns a detached review value. The
prototype checks whether that value can remain neutral to the agent producer
and avoid treating `NodeId` or `DeclId` as durable identity.

This is throwaway decision code. It does not parse Lambda, mutate a real
`SyncEditor`, or propose production APIs.

## Concrete scenario

The primary scenario renames the binder in:

```text
let x = 1
x
```

to:

```text
let y = 1
x
```

The reference `x` becomes free. The returned review contains:

- host-supplied attribution (`producer`, `edit_id`);
- the actual applied `SpanEdit` values, in source coordinates;
- the existing `FailureDiff`, whose failures already carry witness and
  location.

The original `TreeEditOp` is an input to the shell but is not published in the
report. This avoids presenting its graph-local target `NodeId` as durable review
identity. The caller can correlate the report through `edit_id`; the applied
source edits explain what changed.

## Seam comparison

| Seam | Fit | Decision |
| --- | --- | --- |
| `SyncEditor::apply_*` | Owns generic document mutation but cannot depend on Lambda scope semantics. It would also impose review work on ordinary edits. | Reject. |
| Existing `apply_lambda_tree_edit` | Owns Lambda edit application and returns the exact `SpanEdit` batch needed for remapping. Changing its return type would disturb every existing caller. | Keep unchanged. |
| Opt-in sibling wrapper in `lang/lambda/companion` | Can snapshot Lambda failures, delegate to `apply_lambda_tree_edit`, force the after projection, and return a typed value only when review is requested. | Choose. |
| FFI `handle_structural_intent` | Has an external producer, but is a Tier 3 adapter returning strings. A report here becomes a JSON/UI transport contract. | Reject. |
| `examples/ideal::commit_tree_edit` | Already records edit traces, but is one example shell and misses other agent hosts. | Reject as owner; useful as a future consumer. |

## Proposed deterministic core

```text
(attribution, applied SpanEdits, before failures, after failures)
  -> ReachableFailureReview {
       attribution,
       applied_edits,
       diff(remap_failures(before, applied_edits), after)
     }
```

The core receives values and returns a detached value. It performs no editor,
parser, FFI, clock, or provider access. In production it should directly reuse
`@lambda_scope.remap_failures` and `@lambda_scope.diff`; the JavaScript model in
this prototype only makes their already-tested behavior visible.

## Proposed imperative shell

An opt-in `review_lambda_tree_edit`-shaped wrapper would:

1. read the current projection and source map and snapshot `failures()`;
2. call the existing `apply_lambda_tree_edit`;
3. read the recomputed projection and source map and snapshot `failures()`;
4. invoke the deterministic core with the returned `SpanEdit` batch;
5. return `Result[ReachableFailureReview, TreeEditError]` to the agent host.

The agent host decides whether and where to publish the returned value. Neither
`AnalysisProjection`, the UI protocol, nor the FFI owns it.

## Observable test seam

The pure report builder is tested with four deterministic cases: binder rename,
failure resolution, position-only shift, and identical rebuild. One integration
test around the wrapper proves that the before snapshot is taken before mutation,
the after snapshot is forced after mutation, and the exact returned `SpanEdit`
batch is passed to the core.

