# Loomark Raw input state reducer

Issue: #1223

## Boundary

`RawInputState` is the single owner of semantic Raw input state. The pure
transition boundary is:

```text
RawInputState + RawInputEvent -> (RawInputState, RawInputDecision)
```

The reducer never reads the DOM, editor, scheduler, clock, telemetry, or
provider state. `RawInputCoordinator` remains the imperative shell that
captures browser values, allocates tokens, schedules commands, performs
rebase/normalization, commits editor changes, and executes reducer decisions.

## State transition table

`—` means the event is a deterministic no-op. A guard failure must not mutate
state or cause a shell effect.

| Event | Guard | State change | Decision |
| --- | --- | --- | --- |
| `BeginDelivery(delivery)` | no active delivery, pending, live composition, capture, ordinary deferred input, or deferred composition | set `in_flight` | `Noop` |
| `BeginPendingDelivery(token)` | pending exists; no active delivery, composition, or deferred frontier | move pending to `in_flight` and clear pending | `Deliver(token, input)` |
| `FinishDelivery(token)` | active token matches | clear `in_flight` and its deferred capture; also clear a completion marker when no deferred composition or pending follow-up remains | `Noop` |
| `DiscardDelivery(token)` | active token matches | clear active, pending, composition, all deferred state, and completion marker | `Noop` |
| `CaptureDeferredBeforeInput(capture)` | active delivery or deferred ordinary input; no deferred composition | set `deferred_before_input` | `Noop` |
| `StoreDeferred(input)` | active delivery + capture; no deferred composition | clear capture and set deferred ordinary input; retain any pending batch waiting behind the active delivery | `Noop` |
| `BeginDeferredComposition(input)` | active delivery; no deferred composition | clear ordinary deferred/capture and completion marker; set deferred composition; retain an already pending ordinary input until the composition result replaces it | `Noop` |
| `UpdateDeferredComposition(input)` | deferred composition exists | replace deferred composition | `Noop` |
| `ClearDeferredCapture` | always | clear capture only | `Noop` |
| `ClearDeferred` | always | clear capture and ordinary deferred input | `Noop` |
| `ClearDeferredComposition` | always | clear deferred composition only | `Noop` |
| `StorePending(input)` | no live composition or deferred frontier | replace pending input (it may wait behind an active delivery) | `StoredPending` |
| `BeginComposition(input)` | no active delivery or deferred frontier | clear pending; set live composition | `Noop` |
| `UpdateComposition(input)` | live composition exists | replace live composition | `Noop` |
| `ClearComposition` | always | clear live composition | `Noop` |
| `MarkDeferredCompositionFinished` | deferred composition exists | set completion marker | `Noop` |
| `ClearDeferredCompositionFinished` | always | clear completion marker | `Noop` |
| `Cancel` | always | clear every semantic field | `Noop` |

The reducer may reject an event by returning the original state and
`Noop`. A successful pending store returns `StoredPending`; a successful
pending delivery returns `Deliver(token, input)`. In particular, an unpaired
`input` cannot create pending or deferred state, and an unmatched token cannot
finish or discard an active delivery.

## Invariants

- There is at most one `in_flight` delivery.
- `deferred` and `deferred_composition` are mutually exclusive.
- `deferred_before_input` is meaningful only with an active delivery or an
  existing ordinary deferred input.
- `pending` may wait behind one active delivery and may temporarily coexist
  with an ordinary deferred snapshot or deferred composition. A deferred
  composition result may replace it; cancellation/discard clears both.
- `pending` is not combined with a live composition.
- `composition` is not combined with an active delivery or deferred frontier.
- The completion marker is meaningful only for a deferred composition or the
  follow-up delivery created from one; it is cleared by cancellation,
  discard, failed rebase, and completion of that follow-up delivery.
- `BeginDeferredComposition` clears the ordinary deferred snapshot and its
  capture while retaining an already pending ordinary input. This preserves
  the #1222 IME-over-ordinary-input ordering and net-no-op behavior.
- A token mismatch is a no-op. Document/version/editor authorization remains
  in the shell and in Raw candidate normalization; the reducer does not infer
  an edit from an unpaired `input`.

## Migration order

1. Add pure transition tests for the table and make the reducer boundary
   explicit without changing coordinator behavior.
2. Move `pending` into `RawInputState`; keep scheduling and token allocation in
   the shell.
3. Move live `composition` into `RawInputState`; keep DOM composition event
   capture and editor delivery in the shell.
4. Move `deferred_composition_finished` into `RawInputState`; keep the
   after-render follow-up command in the shell.
5. Run targeted MoonBit checks/tests after every stage, inspect generated
   interfaces, then run Loomark browser validation.

## Existing shell scheduling and display policy

The migration does not change the existing imperative scheduling policy. A
pending batch whose debounce callback fires while delivery is blocked is
invalidated by `flush`/`cancel_pending`; deferred captures use the frontier
rebase path instead. This is intentionally shell-owned scheduling, not a
reducer transition.

`display_source` also retains the current precedence used by the textarea:
`composition`, `pending`, `deferred_composition`, `deferred`, `in_flight`, then
the committed source. The reducer migration moves these values under one
owner without changing that browser-visible ordering.

## Shell-owned state

`unmatched_before_input`, `composition_final_source`, suppression flags,
schedule/capture generations, timer handles, render-barrier handles,
telemetry, DOM selections/values, editor commits, and command execution remain
imperative-shell state. These values authorize or schedule effects; they are
not the semantic Raw frontier being reduced here.
