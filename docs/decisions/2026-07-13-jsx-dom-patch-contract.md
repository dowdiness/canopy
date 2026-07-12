# JSX DOM patch contract

**Date:** 2026-07-13  
**Status:** Accepted and frozen (V1 JSX DOM adapter contract)  
**Related:** [Generative UI input vertical slice](../plans/2026-07-12-generative-ui-input-vertical-slice.md) · [Generative UI direction](../architecture/generative-ui-direction.md)

## Why this record exists

Phase 3 has two implementations of the same candidate update: a pure dry-run
model and an imperative JavaScript DOM adapter. They must agree on the state
that a patch sequence produces. This record makes that agreement explicit so
future changes do not silently update only one side.

This is a restricted patch interpreter for the JSX session, not a general
virtual-DOM or renderer-neutral API.

## Decision

The pipeline is:

```text
validated candidate
  → pure JSX lowering
  → DomPatch sequence
  → pure dry-run validation
  → imperative DOM application
```

`DomPatch` is the shared semantic boundary. The dry-run model owns the pure
state transition; the DOM adapter owns JavaScript and DOM effects. Neither side
may invent different patch semantics.

## Patch semantics

| Patch | Required behavior |
| --- | --- |
| `MakeElement(parent, id, tag, attrs, index)` | Create an element, attach the internal `data-node-id`, normalize attributes, and insert it at `index`. |
| `MakeText(parent, id, text, index)` | Create and insert a text node at `index`. |
| `MakeExprSpan(parent, id, raw, index)` | Create an inert span containing the opaque expression text. It is never evaluated. |
| `SetText(id, text)` | Replace the text content of the existing node. |
| `SetExpr(id, raw)` | Replace the inert expression-span text. It is never evaluated. |
| `SetAttrs(id, attrs)` | Replace the renderer-owned attribute set, removing old attributes absent from the new set. |
| `Release(id)` | Remove the node from its parent and release its registry entry. |

All `Release` patches are processed before creation or insertion patches. This
makes sibling indexes refer to the post-release child list. V1 has no move or
reparent patch; a mount-boundary change remounts the supported root boundary.

The internal `data-node-id` is reserved and owned by the renderer. Source
attributes with that name are ignored, and the renderer's identity value is
preserved even when the name is absent from source attributes. Other
attributes are owned by the current JSX projection and follow `SetAttrs`
replacement semantics.

After a successful commit, `mounted_ids` is the complete set of currently
reachable mounted node IDs. It is the next reconciliation baseline; it is not
the subset of IDs touched by the latest patch sequence.

## Attribute normalization

Both the dry-run model and the DOM adapter apply this table:

| JSX attribute value | DOM representation |
| --- | --- |
| `StringLit(value)` | Set the string value. For `data-genui-*`, decode `&quot;`, `&gt;`, `&lt;`, and `&amp;` before setting it. Other attributes remain unchanged. |
| `Bare` | Set the attribute with an empty string value. |
| `ExprSpan(raw)` | Omit the attribute. V1 does not evaluate opaque expressions. |

The string-value normalizer is pure and shared by the dry-run model and the DOM
shell. The typed dry-run adapter and the JSON/JavaScript DOM adapter remain
separate boundary translations, but they must implement this same table.
Generated candidates therefore cannot create event handlers, URLs, or other
executable behavior through an expression-valued attribute. After
normalization, duplicate names use the last applicable value, matching the
DOM shell's source-order `setAttribute` behavior. Reserved and omitted values
do not displace an earlier applicable value.

## Commit and recovery ordering

1. Check the candidate base revision before parser or DOM work.
2. Lower the validated candidate into JSX and patches.
3. Apply the patches to the dry-run model.
4. If dry-run fails, preserve the last committed DOM, source, revision, and
   mounted IDs; mark the session dirty for repair.
5. For a remount, clear the old DOM registry only after dry-run succeeds.
6. Apply the patches to the real DOM.
7. Advance revision, mounted IDs, projected state, and committed source only
   after DOM application succeeds.
8. A DOM failure leaves the candidate uncommitted and marks the session dirty;
   the next successful render repairs the dirty root.

Cancellation is not part of this DOM patch contract. The request lifecycle
owns cancellation and must reject a cancelled or stale generation before it
invokes the session commit boundary; that pre-commit gate belongs to the Phase
0 lifecycle contract and its tests. The current synchronous session API does
not expose a cancellation parameter. Once DOM application begins, it is
linearized and cannot be rolled back by cancellation.

## Boundary tests

The contract is fixed by tests at both sides of the boundary:

- `lang/jsx/proj/dry_run_wbtest.mbt` verifies release-before-insert ordering,
  nested updates, invalid-parent rejection, pure failure behavior, and
  normalization of string, bare, expression, duplicate, reserved-name, and
  generative metadata values.
- `ffi/jsx/session_contract_wbtest.mbt` verifies entity decoding, ordinary
  attribute preservation, `SetAttrs` removal, duplicate and bare/expression
  behavior, renderer identity preservation, dry-run rejection, dirty-root
  repair, and successful candidate commits.

Any change to patch ordering, attribute normalization, registry ownership, or
commit ordering must update tests in both packages. A pure-model test alone is
insufficient because it cannot observe DOM effects; a DOM test alone is
insufficient because it cannot prove rejected candidates remain uncommitted.

## Consequences

- The dry-run model remains a small functional core rather than a second DOM
  implementation.
- The JavaScript adapter remains the imperative shell and is the only layer
  allowed to call DOM APIs.
- V1 deliberately omits expression evaluation, moves, reparents, rollback, and
  renderer-neutral generalization.
- A future renderer can adopt the semantic patch contract only after its own
  boundary conformance tests establish equivalent behavior.
