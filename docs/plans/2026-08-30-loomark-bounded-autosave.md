# Loomark bounded Autosave

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/1347>

The issue owns backlog status. This document owns the implementation
specification. The required reciprocal tracking pair is:

- issue: <https://github.com/dowdiness/canopy/issues/1347>
- plan: `docs/plans/2026-08-30-loomark-bounded-autosave.md`

Verify both links as part of the documentation acceptance criteria. The
implementation pull request may close #1347 only when every acceptance criterion
in this plan is satisfied.

## Domain language

### Document text

Document text is the current Markdown `String` in the Rabbita Model. Text input
updates it immediately. It is the only mutable current-text authority.

### Source record

A Source record is the durable representation of one Loomark document. IndexedDB
stores it under:

```text
source/v1/<document-id>
```

The record contains exactly the Document ID and Saved text. Loomark does not
persist scheduler state, pending edits, Catalog records, or name certificates.

### RepositorySnapshot

A `RepositorySnapshot` is the immutable in-memory view reconstructed from valid
Source records. It supplies the acknowledged Source for each Document ID and the
Catalog derived from those Sources. A successful Source transaction returns the
next acknowledged snapshot.

### Acknowledged Source

The acknowledged Source is the active document's Source in the current
`RepositorySnapshot`. Transaction completion, rather than request submission,
advances it. Completion does not guarantee a physical-media flush.

### Activation

An `Activation` contains a Document ID and a generation. The generation changes
on every document activation, including A → B → A. Delayed messages carry
Activation so work from an older ownership interval cannot affect the current
document.

### Checkpoint

A checkpoint is one coalesced intent to persist latest current text. It contains
no text. It has:

- an **epoch**, identifying one dirty interval;
- a **quiet revision**, identifying the latest committed edit within that
  interval; and
- an **eligibility**, either `Deferred` or `Eligible`.

`Deferred` means no save trigger has become due. Its quiet revision advances on
each committed edit without restarting the epoch's maximum timer. `Eligible`
means quiet, maximum-wait, or hidden-page handling has allowed an attempt.

### In-flight candidate

The in-flight candidate is the exact text captured for the one active Source
transaction. It remains in state until that transaction completes so completion
can be correlated with current text.

### Exact `Saved`

Loomark may publish `Saved` only when:

- current Document text exactly equals the acknowledged Source;
- no Source write is active; and
- no checkpoint is pending.

Document activation and creation remain gated on exact `Saved`, inactive IME
composition, and inactive creation.

## Why

Loomark writes current Markdown text to IndexedDB after input has been quiet for
250 ms. Quiet coalesces ordinary typing bursts, but it does not occur during an
uninterrupted stream of committed input. A user can therefore continue editing
while the recoverable Source remains indefinitely behind current Document text.

A maximum-wait trigger must coexist with slower Source writes. If every write
completion immediately starts another write whenever current text has changed,
storage latency becomes an accidental clock and produces a sequence of
back-to-back puts. The solution must limit the application's deliberate waiting
without creating a write train, persisting IME intermediates, accepting stale
document work, or introducing another text authority.

This plan specifies one private durability state machine in the Loomark app. It
preserves the Source-only repository and exact transaction-acknowledged meaning
of `Saved`.

## Scope

### In

Application state and transitions:

- `apps/loomark/app/model.mbt`
- `apps/loomark/app/update.mbt`
- `apps/loomark/app/update_wbtest.mbt`
- `apps/loomark/app/app.mbt`
- `apps/loomark/app/view.mbt`
- `apps/loomark/app/view_wbtest.mbt`

Production browser behavior:

- `apps/loomark/examples/vanilla/tests/standalone.spec.ts`

Product and architecture documentation:

- `apps/loomark/CONTEXT.md`
- `apps/loomark/README.md`
- `docs/decisions/2026-08-24-loomark-source-first-interactive-contract.md`
- `docs/README.md`

Generated interface review:

- `apps/loomark/app/pkg.generated.mbti`

### Out

- changes to the `source/v1` schema;
- a persisted Catalog or scheduler record;
- a second current-text field or cross-document draft map;
- a generic scheduler package or Rabbita runtime feature;
- another Source queue, writer actor, or storage adapter;
- automatic write retry;
- complete edit history, operation logs, CRDT state, Rope, or Piece Tree;
- a Worker, `localStorage` journal, chunked Source, or adaptive timing;
- cancellation support for `@cmd.delay`;
- strict physical-media durability;
- `unload` or unconditional `beforeunload` persistence;
- save-then-activate UX or an explicit discard/reload flow;
- remediation of the separate 1 MiB textarea/rendering long task; and
- upstream MoonBit core changes.

## Pre-implementation state

The private save state before this plan in
[`apps/loomark/app/model.mbt`](../../apps/loomark/app/model.mbt) was:

```text
Saved
Waiting
Saving(candidate)
Failed(failure)
```

In [`apps/loomark/app/update.mbt`](../../apps/loomark/app/update.mbt),
`TextChanged` applies one `TextChange`, updates current text, and schedules:

```moonbit
@cmd.delay(SaveRequested(activation, candidate), 250)
```

The delayed request acts only when its Activation and captured candidate remain
current. Different-text messages are ignored, but an equal-text ABA path such
as B → C → B can make an older B timer appear current before the final B has
been quiet for 250 ms.

`SaveCompleted` installs the acknowledged `RepositorySnapshot`. When its
candidate is behind current text, the current completion branch immediately
starts another save. It does not require current text to have reached quiet or
maximum eligibility.

[`TextArea`](../../apps/loomark/internal/text_area/text_area.mbt) owns the
browser IME boundary. Native input events are ignored while
its private state is composing. A committed `compositionend` emits one final
`TextChanged`, followed by `CompositionEnded`. A cancelled or no-op composition
emits only `CompositionEnded`.

The [`source_repository`](../../apps/loomark/internal/source_repository/)
already provides:

- strict fixed-schema Source decoding;
- native JavaScript Source encoding;
- conservative first-line Catalog-name reuse with complete-parser fallback;
- one exact `save(snapshot, document_id, text)` command; and
- transaction-completion results containing the accepted snapshot.

The scheduler does not alter those responsibilities.

## Desired state

Loomark retains the 250 ms trailing quiet behavior and adds one 2,000 ms
maximum-wait timer per checkpoint epoch.

The phrase **2,000 ms maximum-wait** describes application policy:

- later edits do not restart that epoch's maximum timer;
- the timer becomes due at 2,000 ms; and
- its message makes the checkpoint eligible at the first event-loop opportunity
  when Rabbita can process it.

`setTimeout` supplies a minimum delay, not a wall-clock delivery upper bound.
Long tasks, background throttling, page freeze, and termination may postpone or
prevent processing. The policy does not guarantee an IndexedDB acknowledgment
within two seconds.

At most one Source write and one newer checkpoint exist. Write completion starts
a latest follow-up only when that checkpoint is already `Eligible`. Candidate
mismatch alone never starts a write.

Current text that exactly returns to its durability base is recognized without a
redundant transaction:

- in `Saved` or `Waiting`, the base is the active acknowledged Source; and
- in `Saving`, the base is the in-flight candidate.

Exact comparison uses the existing immutable `String` values. It adds no hash,
revision graph, mismatch certificate, or text copy.

## Product requirements

1. A short committed edit burst persists latest text after 250 ms quiet.
2. Uninterrupted committed input does not restart the epoch's 2,000 ms timer.
3. Quiet, maximum-wait, and hidden signals converge on one eligibility
   transition.
4. At most one Source transaction is active.
5. At most one newer checkpoint waits beside it.
6. A pending checkpoint does not own text.
7. Only exact transaction-acknowledged current text publishes `Saved`.
8. Returning exactly to acknowledged text before a write restores `Saved`
   without a put.
9. Returning exactly to the in-flight candidate removes pending work and waits
   for that transaction's completion.
10. Failure retains current text and the preceding acknowledged snapshot.
11. Failure never retries automatically while current text differs from that
    acknowledged Source; exact return to it restores truthful `Saved` without a
    write.
12. Retry writes latest committed text only after composition ends.
13. Intermediate composition values never become candidates.
14. Stale Activation, epoch, quiet revision, and completion messages are
    no-ops, including equal-text ABA within one dirty interval.
15. Hidden-page eligibility is best effort and follows the same composition,
    creation, failure, Activation, and single-flight rules.
16. Actual document activation and creation remain unavailable outside exact
    `Saved`.

## Performance requirements

The Text input target remains p95 and maximum at or below 10 ms in the
production browser test boundary.

`TextChanged` may perform these measured pure operations:

- current `TextChange::apply`;
- in-memory `RepositorySnapshot::source` lookup;
- exact `String` equality against the durability base;
- private state transitions; and
- lightweight command construction.

It must not perform:

- JSON encoding;
- Markdown parsing or Catalog-name derivation;
- IndexedDB access;
- RepositorySnapshot reconstruction;
- DOM initialization or complete textarea reads;
- Preview lowering; or
- complete history preparation.

The exact equality path is accepted only with the production gate recorded
below and must be remeasured after the integrated scheduler is complete.

## Evidence behind the selected behavior

### Quiet-only deferral

A production Chromium run dispatched 30 committed inputs with 100 ms waits. No
Source put occurred during the 3.021-second stream. The first put began about
252 ms after the final input. Trailing quiet alone therefore permits indefinite
deliberate deferral.

### Completion-driven amplification

A selected 1 MiB Source with input overlapping active writes produced 11–13 puts
in about three seconds under mismatch-driven completion. The persistence policy
must not use transaction completion as eligibility.

### Maximum-wait selection

A 6.2-second control requested input every 100 ms and compared one-, two-, and
five-second maximum timers across three production Chromium launches.

| Fixture / timer | Completed inputs | Checkpoints | Long tasks |
| --- | ---: | ---: | ---: |
| Practical / 1,000 ms | 61 / 61 / 61 | 6 / 6 / 6 | 0 / 0 / 0 |
| Practical / 2,000 ms | 61 / 61 / 61 | 3 / 3 / 3 | 0 / 0 / 0 |
| Practical / 5,000 ms | 60 / 61 / 61 | 1 / 1 / 1 | 0 / 0 / 0 |
| 1 MiB / 1,000 ms | 50 / 51 / 51 | 4 / 4 / 4 | 49 / 50 / 50 |
| 1 MiB / 2,000 ms | 51 / 51 / 48 | 2 / 2 / 2 | 51 / 51 / 47 |
| 1 MiB / 5,000 ms | 50 / 48 / 50 | 1 / 1 / 1 | 50 / 48 / 49 |

One second doubled checkpoint opportunities relative to two seconds without an
input or long-task benefit. Five seconds lengthened deliberate exposure. The
1 MiB long tasks followed textarea/rendering work at every interval and are not
resolved by changing checkpoint frequency. Two seconds is the selected policy.

### Integrated production candidate: exact acknowledged-text comparison

The final revision-token candidate's exact comparison was measured in a
minified Warren production build on Chromium `149.0.7827.55`. No temporary app
instrumentation was present; the samples measure browser dispatch around the
final Text input path. Raw
samples are retained in
[`docs/evidence/2026-08-31-loomark-bounded-autosave-production-raw.json`](../evidence/2026-08-31-loomark-bounded-autosave-production-raw.json).

Each warmed cell used three fresh launches, ten warmup revert pairs, and fifty
measured pairs per launch.

| Fixture / operation | Samples | Browser dispatch p95 | Maximum |
| --- | ---: | ---: | ---: |
| Practical Preview / same-length mismatch | 150 | 1.1 ms | 3.7 ms |
| Practical Preview / exact revert | 150 | 1.0 ms | 1.7 ms |
| 64 KiB / same-length mismatch | 150 | 0.2 ms | 0.3 ms |
| 64 KiB / exact revert | 150 | 0.2 ms | 0.4 ms |
| 256 KiB / same-length mismatch | 150 | 0.7 ms | 0.8 ms |
| 256 KiB / exact revert | 150 | 0.7 ms | 1.0 ms |
| 1 MiB / same-length mismatch | 150 | 5.9 ms | 7.2 ms |
| 1 MiB / exact revert | 150 | 5.9 ms | 6.9 ms |

The 1 MiB cold tail used one mismatch/revert pair per fresh Chromium launch.

| 1 MiB cold operation | Samples | p95 | p99 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| Same-length mismatch | 50 | 4.9 ms | 5.1 ms | 5.1 ms |
| Exact revert | 50 | 4.1 ms | 4.3 ms | 4.3 ms |

Every exact revert restored activation controls before quiet, retained the
acknowledged Source, and produced zero puts, including after the stale 2,000 ms
maximum timer was delivered.

The 1 MiB active-overlap fixture requested 46 inputs with a 50 ms sleep across
three launches. Browser work stretched input-start gaps to at most 168.2 ms, so
no 250 ms quiet interval occurred during the stream. Each launch produced three
coalesced checkpoints at approximately 2.0–2.1, 4.2–4.3, and 5.8–6.0 seconds;
the final
Source matched current text. This replaces completion-driven trains with the
selected maximum epochs plus one final quiet checkpoint.

Overlap input dispatch p95 was 0.3 ms. One launch had a 25.6 ms maximum and the
launches retained 105–162 ms browser textarea/rendering long tasks. These are
the
known 1 MiB browser-input limitation rather than Source comparison or save
preparation, so this work does not claim frame responsiveness for that stress
fixture.

The dedicated exact-comparison path stays below the accepted 10 ms input gate,
so acknowledged comparison remains in `TextChanged`. If a later integrated
candidate makes that dedicated path exceed 10 ms, move acknowledged comparison
to the quiet/maximum eligibility task. That fallback keeps exact comparison and
avoids redundant puts, but publishes `Saved` only after deferred reconciliation.
Do not add a hash, mismatch certificate, Rope, or history structure for this
issue.

## Existing APIs to reuse

Project APIs:

- `Activation` and its generation;
- `@text_change.TextChange::apply`;
- `@source_repository.RepositorySnapshot::source`;
- `@source_repository.SourceRecord::text`;
- `@source_repository.save` and `SaveResult`;
- `@cmd.delay`, `@cmd.batch`, and `@cmd.none`;
- `@sub.batch` and `@sub.on_visibility_change`;
- existing TextArea composition messages; and
- existing RepositorySnapshot acceptance after transaction completion.

MoonBit core APIs:

- exact `String` equality and `String::length`;
- `Option` for one pending checkpoint;
- `Result` matching at Source completion; and
- enum pattern matching and guards.

No `Map`, `Set`, `Array` queue, timer registry, new text collection, or manual
loop is needed. Any private helper introduced must own a state-transition
responsibility rather than duplicate a core or project operation.

## Selected private model

The conceptual representation is:

```text
CheckpointEligibility =
  Deferred
  Eligible

Checkpoint = {
  epoch: Int
  quiet_revision: Int
  eligibility: CheckpointEligibility
}

SaveState =
  Saved
  Waiting(Checkpoint)
  Saving(in_flight_candidate: String, pending: Checkpoint?)
  Failed(failure: SaveFailure, retry_after_composition: Bool)

EditingState += last_checkpoint_epoch: Int
```

Equivalent private MoonBit variants are acceptable when they preserve the same
valid states. No public interface change is intended.

`last_checkpoint_epoch` allocates the next private checkpoint identity. It is
not persisted and resets safely with a new EditingState because Activation
generation separately fences document ownership.

A post-implementation comparison with
[OpenSeek at `738d63c`](https://github.com/moonbitlang/openseek/tree/738d63c20e1f40a356f8c03da585c7ba987188e5)
confirmed the identity split. Its `goal_auto_promotable` requires a marker newer
than the command baseline because identical text cannot prove that the current
intent persisted. Its Quick Open debounce stamps delayed work with an advancing
generation. Loomark applies that pattern as an ephemeral quiet revision rather
than a persisted marker or content hash. OpenSeek's cancellable custom
subscription is a viable future timer-lifetime optimization, but it adds no
correctness beyond revision fencing and has no measured benefit in this input
boundary.

## State invariants

1. `Saved` has no active write and no pending checkpoint.
2. `Waiting(checkpoint)` has no active write and current text is known to differ
   from the acknowledged Source.
3. `Saving(candidate, pending)` has exactly one active write for `candidate`.
4. A pending checkpoint refers to latest current text without storing it.
5. `Failed` has no active write and no automatically promotable checkpoint.
6. `Eligible` is monotone within one epoch; later edits do not downgrade it.
7. A new epoch is allocated only when dirty work first appears with no pending
   checkpoint.
8. Later Deferred edits in the same pending interval retain its epoch, advance
   its quiet revision, and do not restart its maximum timer.
9. All timer messages require current Activation and epoch.
10. Quiet additionally requires the checkpoint's latest quiet revision, so
    equal-text ABA cannot validate older work.
11. Completion requires current Activation and the exact active candidate.
12. RepositorySnapshot advances only from a successful acknowledged completion.
13. A failed attempt publishes `Saved` when current text still exactly equals
    the unchanged acknowledged Source; otherwise it publishes `Failed`.

## Messages

Replace the undifferentiated delayed save request with trigger-specific private
messages:

```text
QuietElapsed(Activation, epoch, quiet_revision)
MaximumElapsed(Activation, epoch)
VisibilityChanged(hidden: Bool)
SaveCompleted(Activation, candidate, SaveResult)
```

Existing messages remain for text, composition, Retry, creation, activation,
and Preview.

## Decisions and shell effects

Private transition logic returns only the effects the app shell must execute:

```text
ArmQuiet(Activation, epoch, quiet_revision)
ArmMaximum(Activation, epoch)
Persist(Activation, candidate)
NoEffect
```

The shell maps:

- `ArmQuiet` to `@cmd.delay(..., 250)`;
- `ArmMaximum` to `@cmd.delay(..., 2_000)`;
- `Persist` to `@source_repository.save`; and
- visibility to `@sub.on_visibility_change`; the update branch reads the
  current pending epoch when the page-global event is delivered.

The core does not read a clock, query browser visibility, access IndexedDB, or
mutate RepositorySnapshot.

## Exact text relation

After `TextChange::apply`, choose the durability base from save state.

### `Saved` or `Waiting`

The base is:

```text
editing.repository.source(editing.activation.document_id).text
```

- exact equality returns `Saved`, discards pending work, and arms no save timer;
- inequality creates or updates pending work; and
- a missing active Source fails closed as inequality and reaches the existing
  Source-save failure path rather than publishing `Saved`.

### `Saving(candidate, pending)`

The base is `candidate`.

- exact equality returns `Saving(candidate, None)` and arms no timer;
- inequality creates or updates one pending checkpoint; and
- completion of `candidate` later publishes `Saved` only if current text remains
  equal.

### `Failed(failure, retry)`

Text changes update current Document text and compare it with the unchanged
acknowledged Source. Exact equality returns `Saved` without a write. Inequality
preserves `Failed` and the Retry flag and arms no quiet or maximum timer. Only
explicit Retry may begin another write while inequality remains.

## Checkpoint creation and editing

When inequality first appears with no checkpoint:

1. increment `last_checkpoint_epoch`;
2. create `Checkpoint(epoch, quiet_revision=1, Deferred)`;
3. arm quiet with its epoch and quiet revision; and
4. arm maximum once for that epoch.

If composition is active, create the checkpoint without timers. The committed
`CompositionEnded` transition arms them.

A later unequal edit with an existing `Deferred` checkpoint:

- preserves epoch;
- increments quiet revision and arms that revision when not composing; and
- does not arm another maximum during normal input.

A later unequal edit with an existing `Eligible` checkpoint preserves
eligibility. When a write is active, it waits for completion. When no write is
active, the shared `maybe_persist` transition starts latest text as soon as all
blocks are clear.

## Unified eligibility transition

Quiet, maximum-wait, and hidden all call one private operation:

```text
make_pending_eligible
```

The operation:

1. validates Activation and epoch;
2. validates the latest checkpoint quiet revision for quiet;
3. changes `Deferred` to `Eligible`;
4. retains `Eligible` unchanged on races; and
5. calls `maybe_persist`.

`maybe_persist` starts latest current text only when:

- no Source write is active;
- composition is inactive;
- creation is inactive; and
- state is not `Failed`.

Otherwise eligibility remains pending. Quiet/maximum/hidden races therefore
produce one write.

## Complete transition table

Rows that persist assume current Activation and all message guards pass. A
failed guard is a no-op.

| State and event | Next save state | Effects |
| --- | --- | --- |
| `Saved`, unequal committed text | `Waiting(new Deferred)` | Arm quiet and maximum unless composing |
| `Waiting(p)`, text equals acknowledged Source | `Saved` | None |
| `Waiting(Deferred)`, unequal edit | same epoch, `Deferred` | Arm quiet unless composing |
| `Waiting(Eligible)`, unequal edit while composing | same epoch, `Eligible` | None |
| `Saving(A, _)`, text equals A | `Saving(A, None)` | None |
| `Saving(A, None)`, unequal edit | `Saving(A, Some(new Deferred))` | Arm quiet and maximum unless composing |
| `Saving(A, Some(Deferred))`, unequal edit | preserve epoch and `Deferred` | Arm quiet unless composing |
| `Saving(A, Some(Eligible))`, unequal edit | preserve epoch and `Eligible` | None |
| `Failed(f, retry)`, text equals acknowledged Source | `Saved` | None |
| `Failed(f, retry)`, other committed text | preserve `Failed(f, retry)` | None |
| `Waiting(Deferred)`, current quiet | `Saving(current, None)` if unblocked; otherwise `Waiting(Eligible)` | Persist if unblocked |
| `Saving(A, Some(Deferred))`, current quiet | `Saving(A, Some(Eligible))` | None |
| deferred checkpoint, current maximum | same eligibility result as quiet | Persist only when no write and unblocked |
| deferred checkpoint, hidden=true | same eligibility result as quiet | Persist only when no write and unblocked |
| any state, hidden=false | unchanged | None |
| active success for A, current equals A | `Saved` | Install acknowledged snapshot |
| active success for A, current differs, pending `Deferred` | `Waiting(Deferred)` | Install acknowledged snapshot |
| active success for A, current differs, pending `Eligible`, composition inactive | `Saving(current, None)` | Install snapshot; persist latest once |
| active success for A, current differs, pending `Eligible`, composition active | `Waiting(Eligible)` | Install snapshot; wait for composition end |
| active success for A, current differs, pending absent | `Waiting(new Deferred)` after incrementing `last_checkpoint_epoch` | Defensive fail-closed epoch; arm quiet and maximum when unblocked |
| active failure, current equals preceding acknowledged Source | `Saved` | Preserve current text and preceding snapshot |
| active failure, current differs from preceding acknowledged Source | `Failed(failure, false)` | Preserve current text and preceding snapshot |
| `Failed(f, false)`, Retry while composition inactive | `Saving(current, None)` | Persist latest text |
| `Failed(f, _)`, Retry while composition active | `Failed(f, true)` | None |
| stale timer or completion | unchanged | None |

## Composition transitions

`CompositionStarted` sets the existing composition flag and does not alter
checkpoint eligibility.

When a committed final `TextChanged` arrives during composition, exact relation
and checkpoint state update normally, but no timer or write starts.

`CompositionEnded` clears the flag and applies:

| Save state after clearing composition | Next state | Effects |
| --- | --- | --- |
| `Saved` | `Saved` | None |
| `Waiting(Eligible)` | `Saving(current, None)` | Persist latest text |
| `Waiting(Deferred)` | unchanged | Arm quiet and maximum for the same epoch |
| `Saving(A, None)` | unchanged | None |
| `Saving(A, Some(Eligible))` | unchanged | None; A remains the one active write |
| `Saving(A, Some(Deferred))` | unchanged | Arm quiet and maximum for the same epoch |
| `Failed(f, true)` | `Saving(current, None)` | Persist explicit Retry candidate |
| `Failed(f, false)` | unchanged | None |

The `Saving(A, Some(Eligible))` row is essential: composition ending must not
start a second write while A is active. A's completion later promotes the one
eligible latest checkpoint.

Arming a same-epoch maximum at composition end cannot postpone an earlier timer
because `@cmd.delay` does not cancel it. A later duplicate is harmless after
state or epoch changes.

A cancelled or no-op composition emits no `TextChanged`, creates no checkpoint,
and only clears the composition block.

## Completion transitions

### Success

A successful result first installs the acknowledged RepositorySnapshot returned
by the Source repository.

If current text equals the active candidate:

- publish `Saved`;
- discard any pending checkpoint created and then reverted; and
- ignore all later timer messages for that checkpoint.

If current text differs:

- pending `Deferred` returns to `Waiting(Deferred)`;
- pending `Eligible` starts exactly one latest write when composition is
  inactive;
- pending `Eligible` becomes `Waiting(Eligible)` when composition remains active;
  and
- a missing pending checkpoint increments `last_checkpoint_epoch`, creates one
  new Deferred checkpoint, and arms both quiet and maximum when unblocked.

Candidate mismatch alone never grants eligibility.

### Failure

Failure:

- retains latest current text;
- retains the preceding acknowledged RepositorySnapshot;
- discards pending automatic promotion;
- publishes `Saved` when current text exactly equals that Source; and
- otherwise stores one honest failure that requires explicit Retry.

No delayed quiet, maximum, hidden, or stale completion message can leave an
unequal `Failed` state. A later committed edit can leave it only by returning
exactly to the acknowledged Source.

## Visibility

Add `VisibilityChanged(Bool)` to `Msg` and compose subscriptions in
`apps/loomark/app/app.mbt`:

```text
@sub.batch([
  existing resize subscription,
  @sub.on_visibility_change(...),
])
```

Visibility is a page-global fact rather than document-owned delayed work. The
subscription therefore emits only the Boolean state. On delivery, the update
branch reads the current `Waiting` or `Saving(_, Some(_))` checkpoint and passes
its epoch to the shared eligibility transition. This avoids losing a hidden
event when Rabbita has processed input but has not yet refreshed the
subscription tagger. It also avoids applying captured document state: activation
and checkpoint ownership come from the current Model.

`hidden=true` with a current pending epoch invokes the shared eligibility
transition. It is not a separate save path. `hidden=false` and a missing current
epoch are no-ops.

The browser may freeze or terminate before Rabbita processes the event or before
IndexedDB completes. Documentation must describe hidden persistence as best
effort.

## Functional core and imperative shell

### Functional core

Keep deterministic decisions private to `apps/loomark/app`:

- exact relation to acknowledged or in-flight text;
- checkpoint allocation;
- eligibility;
- completion and failure transitions;
- composition unblock decisions;
- Retry decisions; and
- stale-message rejection.

Small private helpers may return updated state and conceptual effects. Tests
exercise these transitions without clocks or IndexedDB.

### Imperative shell

Keep effects in the existing Rabbita update shell:

- delayed command scheduling;
- visibility delivery;
- Source repository command execution;
- transaction result delivery;
- RepositorySnapshot installation;
- DOM rendering; and
- production timing observation.

Do not create a public durability package. The app update interface remains the
external seam.

## Implementation steps

Follow the repository's required implementation order.

### 1. Establish an isolated candidate

1. Fetch `origin/main`.
2. Create a dedicated clean worktree whose HEAD contains current `origin/main`.
3. Initialize submodules recursively.
4. Verify recorded submodule commits, configured-origin reachability, and
   dependency identity.
5. Confirm `deps/rabbita` still supplies the documented delay and visibility
   interfaces.

Do not implement in the research worktree or dirty primary checkout.

### 2. Confirm Existing API First

From the relevant package roots, inspect:

```bash
NEW_MOON_MOD=0 moon ide outline apps/loomark/app
NEW_MOON_MOD=0 moon ide outline apps/loomark/internal/source_repository
NEW_MOON_MOD=0 moon ide doc 'String::*'
NEW_MOON_MOD=0 moon ide doc 'Option::*'
NEW_MOON_MOD=0 moon ide find-references 'SaveRequested'
NEW_MOON_MOD=0 moon ide find-references 'SaveCompleted'
NEW_MOON_MOD=0 moon ide find-references 'can_activate'
```

Record reused APIs and rejected candidates in the pull request's Reuse check.

### 3. Freeze the behavior matrix

Treat the transition tables in this plan as the behavioral boundary matrix. Add
explicit test cases for state, trigger, composition, Activation, epoch,
completion result, exact relation, and expected effect before changing behavior.

The first failing test uses the current compile-safe state shape:

```text
current text latest + Saving(old) + successful completion(old)
→ current-model Waiting, no immediate save command
```

It must fail behaviorally because current code starts latest immediately. After
the private checkpoint types compile, migrate the same test fixture to:

```text
Saving(old, Some(Deferred)) + current latest + successful completion(old)
→ Waiting(the same Deferred checkpoint), no immediate Persist
```

The observable assertion does not change; only its state representation becomes
explicit.

### 4. Add the private state model

1. Add checkpoint eligibility, epoch, and quiet revision.
2. Extend `Saving` with one optional pending checkpoint.
3. Extend `Failed` with deferred Retry intent.
4. Initialize the epoch in every EditingState constructor and test fixture.
5. Update exhaustive view and helper matches.
6. Confirm `can_activate` remains exact `Saved` only.

Run targeted check and tests before continuing.

### 5. Implement exact relation

1. In `Saved` and `Waiting`, compare new text with the active acknowledged
   Source.
2. In `Saving`, compare new text with the in-flight candidate.
3. Preserve `Failed` through unequal edits and restore `Saved` on exact
   acknowledged revert.
4. Add exact revert tests before, during, and after a failed write.
5. Add missing-active-Source fail-closed coverage.

No parser, encoding, or IndexedDB work enters `TextChanged`.

### 6. Implement checkpoint creation

1. Allocate one epoch on the first unequal edit without pending work.
2. Arm quiet and maximum once for the new epoch when not composing.
3. Increment quiet revision and arm only that revision for later Deferred
   edits.
4. Preserve Eligible through later edits.
5. Create state without timers during composition.

### 7. Implement unified eligibility

1. Add quiet and maximum messages.
2. Fence both by Activation and epoch.
3. Fence quiet by exact checkpoint quiet revision.
4. Route both through one eligibility helper.
5. Start at most one write.
6. Add race tests in both message orders.

### 8. Replace completion-driven follow-up

1. Install successful snapshots before deciding next durability state.
2. Return exact candidate equality to `Saved`.
3. Leave Deferred latest text waiting.
4. Promote Eligible latest text once.
5. Preserve Eligible through composition.
6. Reconcile error completion with the unchanged acknowledged Source; publish
   `Saved` only on exact equality and otherwise enter `Failed` without automatic
   promotion.

### 9. Complete IME and Retry

1. Add every composition row from this plan.
2. Verify active write remains active at `CompositionEnded`.
3. Remember one Retry intent during composition.
4. Save only the final committed result.
5. Cover cancelled and no-op composition.

### 10. Add hidden-page eligibility

1. Add the visibility message.
2. Batch visibility with resize subscription.
3. Route hidden through shared eligibility.
4. Cover inactive, pending, active-write, composition, failure, creation, and
   stale Activation states.
5. Keep visible as a no-op.

### 11. Add production browser coverage

Extend `standalone.spec.ts` with:

- short-burst quiet behavior;
- uninterrupted 100 ms committed input;
- quiet/maximum race;
- active-write overlap;
- exact acknowledged revert;
- in-flight candidate revert;
- stale Activation and epoch;
- successful and failed completion;
- Retry during composition;
- committed, cancelled, and no-op composition;
- hidden best effort;
- exact stored Source after reload;
- put count; and
- activation controls before quiet after exact revert.

Use production Chromium and observable IndexedDB transactions. Do not assert
physical-media flush or termination completion.

### 12. Rerun the performance gate

Measure the final minified candidate, without permanent instrumentation, for:

- practical Preview;
- 64 KiB;
- 256 KiB;
- 1 MiB;
- insertion;
- same-length mismatch;
- exact acknowledged revert; and
- in-flight revert after scheduler integration.

Report p50, p95, p99 where sample count supports it, maximum, long tasks, puts,
and fresh-launch tails. The final browser input boundary must retain p95 and
maximum at or below 10 ms.

If integrated exact comparison causes the final candidate to exceed 10 ms:

1. move acknowledged-Source equality from `TextChanged` to the shared
   eligibility task;
2. keep in-flight completion equality outside input;
3. rerun the same gate; and
4. document that exact acknowledged revert becomes `Saved` after deferred
   reconciliation rather than immediately.

This fallback is evidence-triggered. Do not add a new text representation.

### 13. Update documentation

After behavior and measurements are final:

- define Autosave as quiet plus non-restarting maximum-wait policy in
  `apps/loomark/CONTEXT.md`;
- update `apps/loomark/README.md` with timing, exact Saved, and best-effort hidden
  semantics;
- update the accepted source-first interactive contract with the shipped
  bounded-attempt behavior and browser caveats;
- keep the plan entry in `docs/README.md` aligned with its final path and
  description; and
- keep the issue as the canonical status surface with a reciprocal plan link.

No new ADR is needed. The existing decision owns current-versus-saved text.

### 14. Review, synchronize, and publish

1. Run independent MoonBit review after the targeted loop is green.
2. Resolve every correctness and interface finding.
3. Fetch `origin/main` again.
4. If the candidate no longer contains it, synchronize and repeat affected
   checks, browser evidence, and review.
5. Commit the exact candidate.
6. Push normally so Lefthook validates that commit.
7. Fetch `origin/main` immediately before creating or updating the pull request.
8. Open the pull request only when current HEAD is pushed and still contains the
   current base.

## Acceptance criteria

### State and scheduling

- [ ] The first unequal committed edit allocates one checkpoint epoch.
- [ ] A new epoch arms 250 ms quiet and one 2,000 ms maximum timer.
- [ ] Later edits arm quiet without restarting maximum.
- [ ] Quiet, maximum, and hidden share one eligibility transition.
- [ ] Trigger races start exactly one write.
- [ ] At most one write and one pending checkpoint exist.
- [ ] Pending state contains no text.
- [ ] Candidate mismatch alone never starts a follow-up.
- [ ] Eligible pending text starts once after active success.
- [ ] Deferred pending text remains waiting after active success.

### Exact relation

- [ ] Acknowledged A → B → A returns to `Saved` without a put.
- [ ] In-flight A → B → A removes pending work and waits for A completion.
- [ ] Missing acknowledged Source never publishes `Saved`.
- [ ] Only exact acknowledged current text enables actual activation and
  creation.

### Stale-work safety

- [ ] Stale Activation quiet, maximum, and completion messages are ignored.
- [ ] Visibility reads only the current pending checkpoint at delivery.
- [ ] Stale checkpoint epochs are ignored, including equal-text A → B → A
  across dirty intervals.
- [ ] Stale quiet revisions are ignored, including B → C → B within one dirty
  interval.
- [ ] Old maximum duplicates after composition are harmless.

### IME and failure

- [ ] Intermediate composition values are never candidates.
- [ ] Eligible pending text during composition waits for the committed result.
- [ ] `CompositionEnded` never starts a second write while one is active.
- [ ] Cancelled and no-op composition create no dirty work.
- [ ] Failure preserves current text and the preceding acknowledged Source.
- [ ] Failure never retries automatically.
- [ ] Unequal edits after failure preserve Failed and arm no timer.
- [ ] Exact acknowledged revert after failure restores truthful `Saved` without
  a put, including when the active write fails after the revert.
- [ ] Retry during composition starts only after the final committed result.

### Browser lifecycle and recovery

- [ ] Hidden makes pending text eligible through the shared transition.
- [ ] Hidden remains composition-, creation-, failure-, current-activation-,
  and single-flight-safe.
- [ ] Visible is a no-op.
- [ ] Reload restores the exact acknowledged Source.
- [ ] Documentation calls hidden persistence best effort.

### Performance

- [ ] Final production Text input p95 is at or below 10 ms.
- [ ] Final production Text input maximum is at or below 10 ms for the accepted
  repository test boundary.
- [ ] Exact revert produces no redundant Source put.
- [ ] Active overlap no longer produces a completion-driven put train.
- [ ] Practical Preview and 1 MiB results are recorded across fresh launches.
- [ ] The pull request links raw production samples from the exact final commit.
- [ ] Existing 1 MiB textarea/rendering long tasks are reported separately and
  are not attributed to Source saving.

### Interfaces and documentation

- [ ] No public app interface is added.
- [ ] `pkg.generated.mbti` has no unintended change.
- [ ] Source schema and strict decoder are unchanged.
- [ ] Catalog remains in memory and Source-derived.
- [ ] CONTEXT, README, accepted ADR, issue link, and docs index agree with
  shipped behavior.

## Validation

### Targeted Red→Green loop

```bash
NEW_MOON_MOD=0 moon test apps/loomark/app --target js --release
NEW_MOON_MOD=0 moon check apps/loomark/app --target js --deny-warn
```

Run the failing test first, then the same targeted commands after each coherent
transition group.

### Source preparation regression guard

```bash
NEW_MOON_MOD=0 moon bench \
  --package dowdiness/loomark/internal/source_repository \
  --target js --release \
  --no-parallelize \
  --file source_preparation_benchmark_wbtest.mbt
```

The scheduler does not optimize Source preparation, but the benchmark confirms
that whole-Source checkpoint assumptions remain valid.

### Production Chromium and TypeScript

```bash
./scripts/test-loomark-standalone-e2e.sh
```

The script performs a production Warren build, TypeScript checking, and the
Playwright standalone suite.

### Workspace and generated interfaces

```bash
moon check
moon test
moon info
moon fmt

git diff -- apps/loomark/app/pkg.generated.mbti
git diff --stat
git diff --check
```

If `moon info` or `moon fmt` changes files, review and stage them before commit.
No widened trait bound or unintended public type is acceptable.

### Documentation

```bash
just hook-documentation-contract
```

Run Slopless on changed English Markdown and retain zero unresolved findings.

## Risks and mitigations

### One MiB exact comparison remains document-size-dependent

The final revision-token run observed a 7.2 ms maximum across warmed 1 MiB
mismatch/revert samples and 5.1 ms across cold samples. Later integrated state
or larger documents may cross 10 ms. The measured fallback moves acknowledged
comparison to eligibility without adding another authority.

### Uncancelled timers accumulate briefly

Every Deferred edit leaves a quiet timer and every epoch leaves a maximum
timer. Activation, epoch, quiet revision, and state guards make delivery
harmless without retaining candidate text. Timer cancellation is not required
for correctness.

### Browser scheduling is not a hard deadline

The 2,000 ms timer can be delayed by the event loop, throttling, freeze, or
termination. Product copy and tests must describe application policy rather than
a physical or wall-clock durability guarantee.

### Exact comparison is document-size-dependent

Comparison was measured through 1 MiB. Larger documents remain possible. The
final test boundary is evidence-based, and the fallback avoids equality in the
input task if integrated tails exceed budget.

### Visibility may not complete persistence

A hidden event only queues best-effort work. The browser may terminate before
transaction completion. No stronger claim is allowed.

### State-shape drift can create invalid combinations

Use variants and one optional pending checkpoint so invalid multi-write and
multi-pending states are unrepresentable. Centralize eligibility and
`maybe_persist` rather than duplicating trigger branches.

## Guarantees and non-guarantees

When the application can process messages, this design guarantees:

- a non-restarting maximum-wait policy per dirty epoch;
- single-flight Source writes;
- one coalesced pending checkpoint;
- exact transaction-acknowledged `Saved`;
- stale Activation and epoch rejection;
- no automatic retry; and
- no redundant put after an exact acknowledged revert on the accepted fast
  path.

It does not guarantee:

- timer delivery exactly at 2,000 ms;
- IndexedDB completion within a fixed duration;
- physical-media flush;
- completion during freeze or termination;
- responsiveness for every unbounded document size or synthetic delivery
  pattern;
- undo history after reload;
- cross-tab collaboration; or
- strict power-loss durability.

## Documentation decision

This plan refines behavior within the accepted current-versus-saved-text
architecture. No new ADR is needed. Update
`docs/decisions/2026-08-24-loomark-source-first-interactive-contract.md` when the
implementation and production evidence are final.

## References

Repository sources:

- [`apps/loomark/CONTEXT.md`](../../apps/loomark/CONTEXT.md)
- [`apps/loomark/app/model.mbt`](../../apps/loomark/app/model.mbt)
- [`apps/loomark/app/update.mbt`](../../apps/loomark/app/update.mbt)
- [`apps/loomark/app/update_wbtest.mbt`](../../apps/loomark/app/update_wbtest.mbt)
- [`apps/loomark/app/app.mbt`](../../apps/loomark/app/app.mbt)
- [`apps/loomark/app/view.mbt`](../../apps/loomark/app/view.mbt)
- [`apps/loomark/internal/text_area/text_area.mbt`](../../apps/loomark/internal/text_area/text_area.mbt)
- [`apps/loomark/internal/source_repository/`](../../apps/loomark/internal/source_repository/)
- [`deps/rabbita/rabbita/cmd/op.mbt`](../../deps/rabbita/rabbita/cmd/op.mbt)
- [`deps/rabbita/rabbita/sub/sub.mbt`](../../deps/rabbita/rabbita/sub/sub.mbt)
- [Current-versus-saved-text decision](../decisions/2026-08-24-loomark-source-first-interactive-contract.md)
- [Issue #1347](https://github.com/dowdiness/canopy/issues/1347)

Browser sources:

- [`setTimeout`, MDN](https://developer.mozilla.org/en-US/docs/Web/API/Window/setTimeout)
- [`visibilitychange`, MDN](https://developer.mozilla.org/en-US/docs/Web/API/Document/visibilitychange_event)
- [Page Lifecycle API, Chrome for Developers](https://developer.chrome.com/docs/web-platform/page-lifecycle-api)
- [`IDBTransaction.complete`, MDN](https://developer.mozilla.org/en-US/docs/Web/API/IDBTransaction/complete_event)
- [`IDBDatabase.transaction`, MDN](https://developer.mozilla.org/en-US/docs/Web/API/IDBDatabase/transaction)
