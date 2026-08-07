# Rabbita Cancelable and Keyed Delayed Commands

**Date:** 2026-08-07
**Status:** Draft specification included in a Canopy pull request
**Publication:** No upstream Rabbita issue or comment was created.
**Owner boundary:** Rabbita scheduler/runtime, with Loomark as the motivating consumer.

## Problem Statement

Loomark's Raw Markdown textarea becomes slow when the document is large. A
browser probe over a roughly 20,000-character document found one native input
event per keystroke and one textarea listener, but each event synchronously
entered the editor transaction path. That path performs canonical-source
commit, parser/projection refresh, snapshot construction, receipt/history
work, and rendering on the browser's main thread.

The clean baseline took approximately 1,343 ms for ten characters, with
individual input work commonly around 100–150 ms. The current Loomark
workaround keeps the textarea responsive by retaining the latest native value
and using a 50 ms trailing debounce. It reduced the same typing probe to about
77 ms of input-loop time and about 240 ms until the canonical model settled,
with one commit instead of ten.

The workaround also had to implement application-owned state for:

- replacing an outstanding delayed input with a newer one;
- invalidating stale timers and queued messages;
- cancelling pending work when an external source or accepted snapshot wins;
- retaining selection information across a rejected edit and retry;
- preventing DOM repair after the Raw surface has disappeared; and
- preventing callbacks from surviving application lifecycle changes.

Rabbita already provides one-shot commands, delayed commands, scheduler
message delivery, and post-render effects. Its long-lived subscriptions have
an explicit unload lifecycle. Its delayed command primitive does not currently
provide an equivalent cancellation or cleanup contract.

Upstream Rabbita issue #139, “Cmd effects have no cancellation or cleanup
lifecycle,” describes the same framework gap: an asynchronous or callback-based
effect may continue after its owner is detached and may enqueue a stale
message. That issue is directly relevant to lifecycle cleanup, but it does not
by itself define keyed replacement or trailing-edge debounce semantics.

## Solution

Add an opt-in, lifecycle-aware scheduling primitive to Rabbita while keeping
message coalescing an explicit application policy.

From an application author's perspective:

- a one-shot delayed command continues to be available;
- a keyed debounce can replace an earlier pending command for the same purpose;
- a keyed command can be cancelled before it starts;
- pending commands are cleaned up when their owning application scope is
  disposed; and
- stale callbacks cannot deliver messages after cancellation or disposal.

Loomark should continue to own the meaning of Raw input. Rabbita should only
own the generic scheduling, replacement, cancellation, and lifecycle mechanics.

The highest test seam is the Rabbita scheduler/runtime. Loomark integration is
a secondary confirmation seam used after the generic primitive is proven.

## User Stories

1. As a Loomark user, I want the Raw textarea to accept keystrokes immediately,
   so that editor computation does not block native text entry.
2. As a Loomark user, I want rapid Raw edits to settle to the latest source,
   so that Preview and the canonical document do not process ten redundant
   full-source replacements.
3. As a Loomark user, I want the latest source to appear in the controlled
   textarea while a commit is pending, so that a rerender does not overwrite my
   native input.
4. As a Loomark user, I want a single isolated input to retain its current
   behavior, so that debouncing does not require a burst of events to work.
5. As a Loomark user, I want my caret and selection preserved when an edit is
   rejected, so that deferred processing does not move the cursor unexpectedly.
6. As a Loomark user, I want a newer edit to supersede an older repair, so that
   an earlier callback cannot erase text I entered afterward.
7. As a Loomark user, I want an edit that is pending while I leave Raw mode to
   follow a defined policy, so that switching views cannot silently lose text.
8. As a Loomark user, I want an explicit source replacement to supersede
   pending native input, so that loading a preset or external source does not
   get overwritten by an old timer.
9. As a Loomark user, I want a valid snapshot restore to supersede pending Raw
   input, so that an explicit restore remains authoritative.
10. As a Loomark user, I want a rejected snapshot request to leave pending Raw
    input intact, so that an invalid request does not discard valid user work.
11. As a Loomark user, I want closing a split Preview or unmounting the editor
    to stop obsolete DOM effects, so that missing controls do not produce
    spurious errors.
12. As a collaborator, I want the application to choose explicitly whether
    input may be coalesced, so that CRDT operations and presence updates are
    not silently dropped by a generic UI framework.
13. As an application author, I want to schedule a delayed command under a
    stable key, so that I can replace work for one purpose without affecting
    unrelated delayed work.
14. As an application author, I want different schedule keys to operate
    independently, so that a search debounce cannot cancel a persistence
    retry.
15. As an application author, I want to cancel a pending command declaratively
    from the update result, so that I do not have to retain an imperative timer
    handle in model state.
16. As an application author, I want cancellation to be scoped to one mounted
    application, so that two mounted applications cannot cancel each other's
    work by reusing a label.
17. As an application author, I want cancellation to be safe when a callback is
    already racing with the scheduler, so that a stale message cannot appear
    merely because a timer callback reached the queue boundary.
18. As an application author, I want existing fire-and-forget commands to keep
    working without cleanup boilerplate, so that the new lifecycle contract is
    backwards-compatible.
19. As an application author, I want a cleanup callback to run at most once,
    so that aborting a request, closing a scope, and completing a request do
    not release the same resource twice.
20. As an application author, I want cleanup to run when the owning component
    or application is disposed, so that timers, listeners, and callback-based
    effects do not outlive their owner.
21. As a Rabbita maintainer, I want the scheduler to manage timer lifetime,
    so that applications do not need generation counters solely because the
    framework cannot cancel a timer.
22. As a Rabbita maintainer, I want keyed replacement to be opt-in, so that
    the framework never assumes that two messages with the same type are
    semantically interchangeable.
23. As a Rabbita maintainer, I want the API to work with the existing Command
    and Scheduler model, so that applications do not need a second effect
    system.
24. As a Rabbita maintainer, I want runtime tests to use deterministic timer
    control, so that cancellation and race behavior can be verified without
    wall-clock sleeps.
25. As a Rabbita maintainer, I want disposal behavior to work across supported
    JavaScript and browser runtimes, so that lifecycle guarantees do not depend
    on one test harness.
26. As a Canopy maintainer, I want editor-specific selection repair to remain
    outside Rabbita, so that the UI framework does not acquire Markdown or
    UTF-16 domain semantics.
27. As a Canopy maintainer, I want the editor's text-diff optimization to
    remain in the editor façade, so that scheduler changes do not become a
    prerequisite for core editing correctness.
28. As a performance investigator, I want to distinguish input-loop latency
    from canonical-settle latency, so that a debounce does not appear to be a
    false zero-cost optimization.
29. As a reviewer, I want tests to assert external behavior rather than
    internal generation counters, so that the implementation can change while
    lifecycle and ordering guarantees remain protected.
30. As a library consumer, I want the existing non-keyed delay behavior to
    remain available, so that adopting keyed scheduling is incremental rather
    than a forced migration.

## Implementation Decisions

### Ownership boundary

Rabbita owns generic effect scheduling:

- delayed execution;
- keyed replacement;
- cancellation before execution;
- cleanup registration;
- scheduler/application disposal; and
- stale callback suppression at the scheduler boundary.

The application owns domain semantics:

- whether a message can be coalesced;
- which value is the latest authoritative value;
- whether a failed message should be retried;
- how selection, focus, persistence, collaboration, and canonical source are
  reconciled; and
- whether an external operation supersedes pending user input.

The framework must not inspect message variants or automatically merge all
input events.

### Public naming

Use an opaque `ScheduleKey` for the identity of scheduled work. The key is
scoped to the owning Scheduler/application and must not be globally shared
state.

Use `debounce` for an opt-in trailing-edge replacement operation. The name
communicates that a newer command for the same key resets the wait and replaces
the older pending command.

Use `cancel` for the declarative cancellation operation. Keep the existing
`delay` primitive for independent one-shot work whose prior instances must not
be replaced.

Use `delay_ms` as the public duration label. It is clearer at call sites than a
bare integer and preserves the fact that the duration is wall-clock scheduling,
not a frame count.

### Command contract

A debounced command has these semantics:

- scheduling a key replaces the not-yet-started command currently registered
  for that key;
- the replacement waits for the complete delay after the latest schedule;
- when the command starts, the key is no longer pending;
- cancelling a key prevents its pending command from starting;
- cancellation is best-effort once execution has already begun;
- a callback that races with cancellation must check its active generation
  before enqueuing a message; and
- a disposed owner prevents both new effect delivery and stale message
  delivery.

The command remains declarative. Applications request scheduling or
cancellation by returning Commands; they do not store mutable timer handles in
their domain model.

### Cleanup contract

Extend the effect lifecycle without breaking existing fire-and-forget effects.
An effect may optionally provide an idempotent cleanup operation. The runtime
invokes cleanup when the owning scope is disposed or when a keyed pending effect
is replaced/cancelled, according to the effect's ownership contract.

Cleanup must not be assumed to interrupt arbitrary synchronous work already in
progress. It must prevent future callbacks and future message delivery where
the runtime controls the boundary.

The runtime must define whether cleanup is associated with the whole mounted
application, a component/state-machine scope, or both. The scope must be
stable and explicit; a command returned from one mounted application must not
be cancelled by a second application that happens to use the same key label.

### Keyed scheduling scope

Keys are scheduler-local. A human-readable namespace may be used to construct
or debug a key, but identity must not depend on a process-global mutable map.
This keeps multiple tabs, tests, and independent mounts isolated.

The initial feature should support one keyed trailing-edge policy. A general
`throttle`, `sample`, or multi-message buffer should not be added until a
separate use case establishes its semantics.

### Framework and application interaction

The generic primitive accepts a complete Command. It does not need to know the
payload type or how the command was produced. Loomark can therefore continue
to read the Raw selection at command execution time and attach its own
application-level validation and repair checks.

The framework's cancellation contract is a prerequisite for simplifying
Loomark's timer and stale-callback bookkeeping, but it does not replace
Loomark's input epoch, source conflict policy, or selection repair.

### Rendering and post-render effects

The existing post-render phase remains an explicit DOM effect phase. A generic
keyed delayed command must not automatically decide whether a post-render write
is still valid against the current model. The application continues to provide
model revision, mode, surface availability, and input-epoch checks for DOM
repair.

A future keyed post-render effect may reuse the same lifecycle machinery, but it
is not required for the first implementation unless the runtime can specify
clear ordering and disposal guarantees.

### Compatibility and migration

Existing delayed commands remain valid and retain their current independent
one-shot behavior. The new keyed API is additive.

Loomark can migrate its timer replacement and disposal mechanism first, then
retain its domain-specific coordinator for pending source, selection, retry,
and canonical-source conflict decisions.

The text-diff reuse change in the Canopy editor façade is independent of this
Rabbita specification and must not be folded into the framework API.

## Testing Decisions

### Test seam

Use the highest existing seam: the Rabbita scheduler/runtime harness. The
runtime already has lifecycle-oriented subscription tests with controllable
browser callbacks and explicit unload assertions. Extend that style with a
controllable timer backend or timer harness rather than using real 50 ms sleeps.

A small integration seam in Loomark should remain as a regression guard, but it
should not be the primary proof of generic scheduler behavior.

### External behavior over implementation details

Tests should observe:

- which Commands run;
- which messages reach the update loop;
- whether cleanup ran and ran only once;
- whether replacement leaves only the latest command;
- whether cancellation suppresses future delivery; and
- whether disposal suppresses future delivery.

Tests should not assert a particular generation counter, map layout, timer ID,
or internal Ref arrangement.

### Required scheduler/runtime cases

1. A non-keyed delayed command still runs once.
2. Two different keys both run independently.
3. Scheduling the same key twice runs only the latest command.
4. Repeated same-key scheduling waits from the latest call, proving trailing
   debounce rather than fixed-window coalescing.
5. Cancelling a pending key prevents its command and message.
6. Cancelling an unknown or already-fired key is harmless.
7. Replacing a key invokes cleanup for the superseded pending effect exactly
   once when cleanup is registered.
8. Application disposal invokes cleanup for every pending keyed effect.
9. Disposal is idempotent.
10. A callback that reaches the timer boundary after cancellation cannot enqueue
    a stale message.
11. A callback that has already started follows the documented best-effort
    cancellation contract.
12. Key reuse after a command fires creates a fresh schedule.
13. Keys from separate scheduler/application instances do not interfere.
14. Existing fire-and-forget effects require no cleanup callback.
15. Supported JavaScript/browser targets compile and execute the same lifecycle
    contract.

### Loomark integration cases

After the generic runtime tests pass, retain or add external-behavior tests for:

- rapid Raw typing settling to the latest source;
- one commit for a same-task input burst;
- pending Raw input surviving a mode change;
- external source replacement superseding pending Raw input;
- valid snapshot restore superseding pending Raw input;
- rejected snapshot restore preserving pending Raw input;
- rejected Raw input preserving selection and avoiding stale repair; and
- split Preview closing before repair without a missing-DOM error.

The existing browser benchmark should report both input-loop latency and
canonical-settle latency, plus commit count. The performance target is not zero
settle latency; it is prompt native input with bounded and observable deferred
settling.

### Prior art

The scheduler lifecycle tests should follow Rabbita's existing subscription
cleanup and retained-subscription/tagger-refresh tests. Loomark integration
should follow its existing fresh-context browser tests and snapshot-based
external behavior assertions. Canopy's prior browser performance notes already
separate input handling, model refresh, rendering, and paint timing; the new
benchmark should preserve that phase distinction.

## Out of Scope

- Automatically debouncing every DOM input event.
- Automatically dropping or merging arbitrary Rabbita Messages.
- Choosing whether CRDT operations, undo entries, presence updates, or
  persistence writes may be coalesced.
- Markdown parsing, projection, snapshot, or history optimization.
- UTF-16 selection mapping, focus restoration, or controlled-input repair.
- Worker offload or background parsing.
- A general stream-processing, throttle, sample, or buffer API.
- Replacing the existing `Sub` lifecycle model; subscriptions remain the owner
  of long-lived external signals.
- Changing the public behavior of existing non-keyed delayed Commands.
- Editing or publishing the upstream Rabbita GitHub issue from this repository.
- Updating Canopy's vendored Rabbita submodule as part of this local
  specification.

## Further Notes

This specification is local-only by request. Upstream issue #139 is a reference
for the lifecycle gap, not a publication target for this document.

The most important distinction is between **cancellation** and **coalescing**:

- cancellation is a framework resource/lifecycle guarantee;
- coalescing is an application semantic decision;
- debounce is a reusable opt-in scheduling policy built on cancellation; and
- domain repair remains an application responsibility.

The current Loomark workaround demonstrates that this split is practical. A
Rabbita lifecycle-aware keyed scheduler would remove timer and stale-callback
plumbing, but it would not remove the need for a Loomark-level policy object
that understands canonical source, selection, editor rejection, and external
source authority.

No upstream Rabbita issue or comment was created while writing this
specification. The document is included in a Canopy pull request as a local
analysis/specification; it does not propose publishing to the Rabbita tracker.
