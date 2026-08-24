# Loomark projection execution is asynchronous and source-stamped

**Date:** 2026-08-12

**Status:** Accepted architecture; executor promotion rejected on 2026-08-15, synchronous placement retained.

**Issue:** [#1244](https://github.com/dowdiness/canopy/issues/1244)

**Conditional integration dependency:** [#1241 — canonical TextEvent admission correctness](https://github.com/dowdiness/canopy/issues/1241)

**Implementation plan:** [Loomark concurrent projection execution](../plans/2026-08-12-loomark-concurrent-projection-execution.md)

**Related:**

- [Causal Authority residency](2026-08-12-causal-authority-residency.md)
- [Indexed projection lifecycle](2026-07-22-indexed-projection-lifecycle.md)
- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
- [Markdown semantic Preview ownership](2026-08-04-markdown-semantic-preview-ownership.md)
- [Markdown semantic attachment boundary](../../deps/loom/docs/decisions/2026-08-04-markdown-semantic-attachment-boundary.md)
- [Markdown projection attachment boundary](../../deps/loom/docs/decisions/2026-08-03-markdown-projection-attachment-boundary.md)

## Context

Loomark currently advances causal authority, synchronizes the parser, reconciles
the editable Block projection, reads MarkdownIR for Preview, prepares persistence,
adopts the next application model, and presents the browser view on one
synchronous edit path. The path is coherent, but its interface forces every
future parser, semantic, persistence, and presentation cost into the authority
commit's main-thread task.

The existing keyed MarkdownIR attachment proves reuse inside one live parser,
but it does not provide an execution seam. Its `incr` runtime, scopes, watches,
and parser state are process-local mutable state. They cannot be serialized or
shared across a browser Worker. The current Warren release build also emits one
JavaScript entry. A production Worker therefore requires both a persistent
projection session created inside the Worker and a proven multi-entry build.

The earlier Markdown semantic Preview ownership decision describes the current
single-mount implementation: one main-thread editor owns both editable
projection and an opt-in semantic observer. This decision supersedes that
co-location and same-turn read policy only when #1244 completes. It preserves
the earlier renderer, security, demand, and single-current-source decisions.
The production target has one projection parser inside the selected executor
after the main-thread authority path relinquishes parser ownership. A browser
Worker is the preferred candidate, not an accepted production placement before
promotion evidence. The Gate 0 dual-parser differential harness is test evidence
and is removed before production cutover.

The 16 ms objective applies to measured main-thread responsiveness. It does not
require every derived projection to be presented in the same turn as its
causal mutation. Causal authority and derived projection have different
correctness obligations: every accepted mutation must retain authoritative
receipt/history evidence, while an intermediate projection that was never
presented may be superseded by a newer committed source.

## Decision

### 1. Separate authority mutation from projection execution and materialization

The authority linearization path ends after causal admission, the resulting
document version and source identity are known, a small receipt/effect value is
available, and required persistence work is scheduled. It does not materialize
or copy the full Markdown source, export history, prepare an archive, encode
JSON, transfer Worker input, synchronize a parser, reconcile Block structure,
lower MarkdownIR, compute diagnostics, materialize Preview, or mutate the DOM.

Full source or history materialization required by a Seed or persistence begins
after the authority result is available. If the current implementation cannot
provide an immutable source handle without a full scan or copy, it records the
need for later materialization rather than extending the authority critical
path.

This separation does not weaken commit semantics. A committed outcome remains
committed even if later source materialization, projection, persistence, or
presentation work fails. Those failures are recorded against the accepted
authority event and never become permission to retry the mutation.

### 2. Keep one application-lifetime Projection Adapter

One Loomark Projection Adapter owns projection demand, scheduling, result
adoption, and the lifecycle of its executor. It is created with the mounted
application and disposed with that application. Editor-session recovery or
replacement starts a new projection generation inside the same adapter rather
than creating an unrelated application currentness domain.

Loom continues to own parsing and Markdown semantic lowering. Canopy continues
to own projection construction, source maps, editable roles, and identity.
Loomark owns the mounted adapter, production execution policy, artifact demand,
and browser adoption. Live Loom or `incr` values never cross this seam.

### 3. Make projection placement conditional on evidence

The projection protocol supports both an in-process executor and a dedicated
browser Worker executor. Each executor owns one long-lived projection session
with its parser, `incr` runtime, semantic attachment, projection memos, and
collection lifecycle. Live parser or reactive values never cross an executor
seam; only explicit portable input and output values do.

The in-process executor defines and tests the protocol before Worker semantics
are implemented. A dedicated Worker is the preferred production placement
because it can isolate interactive main-thread work, but it becomes the
production decision only after the feasibility, correctness, latency, queue,
failure, and memory gates pass. The promotion record must state the measured
trade-off against the in-process executor. Production never silently switches
placement at runtime; an unavailable executor enters an explicit failure state.

#### 2026-08-15 promotion outcome

The [release-browser placement record](../performance/2026-08-15-loomark-projection-placement.md)
rejects both alternative executors. At 2,000 lines, no placement passed the
responsiveness gate; every 10,000- and 50,000-line cold Seed exceeded the
120-second censoring deadline. The subsequent
[main-thread characterization](../performance/2026-08-15-loomark-presentation-critical-path.md)
located the document-scaled interval in pre-frame JavaScript rather than
Rabbita view materialization, DOM mutation, layout, or paint. Moving projection
execution alone therefore did not establish a product-level benefit. Loomark
retains synchronous production placement. The
dedicated Worker and in-process executors remain private comparison modes behind
the executor seam; neither is a production fallback.

This outcome applies the conditional placement rule above. It does not reverse
the source-stamped protocol, adapter-lifetime ownership, currentness, failure,
or bounded-work decisions.

### 4. Stamp every projection request, group work item, and immutable artifact

A projection stamp contains:

- projection generation;
- adapter-lifetime projection sequence;
- exact source revision used for derivation;
- originating causal document version; and
- Block-intent frontier.

Generation names one projection-session incarnation, so replacing the session
invalidates its results. Sequence orders adapter observations and deliveries
across generations and never resets, wraps, or reuses a value during the
adapter lifetime. Source revision identifies changes to
the portable source payload and may remain unchanged when authority advances
without changing source. The document version fences authority mutations
against stale evidence.

Currentness requires the complete stamp rather than source revision alone. When
a source-equal causal advance preserves semantic input, current adoption may
reuse its artifact payload and publishes or wraps that payload with the new
projection sequence and causal document version. Only the newly stamped
artifact is current. An intent calculated against the older causal frontier
remains unauthorized.

Every `Seed`, `Advance`, and `Demand` carries the complete runtime-allocated
stamp into the executor. The executor echoes that stamp rather than synthesizing
one. Application adoption requires one single-use response claim containing
both the latest request ID and the complete stamp. A stale success or stale
error is ignored before payload decoding; a current malformed response or a
decoded envelope mismatch enters bounded failure recovery. Request IDs,
generation, and sequence fail closed before integer exhaustion can wrap or reuse
a correctness token.

### 5. Publish demand-defined consistency groups

One projection request may issue separate group work items. `NoDemand` is a
request disposition and issues no group work. Each issued group work item
derives one immutable Artifact Bundle for one demand-defined consistency group
and ends independently as presented, adopted without presentation, rejected,
superseded, invalidated, failed, or disposed. Materialization alone is not a
terminal outcome. Members of one group are adopted transactionally at one stamp;
unrelated groups do not form a global barrier.

The interactive Block group contains Block structure, selection/focus mapping,
and resolver evidence required by Block intent. Preview and diagnostics are
separate groups. Diagnostics never delay Block adoption; hidden Preview is not
computed or included; Block-only mode never waits for Preview; Raw remains an
authority-owned surface and never waits for a projection group.

When Block and Preview are simultaneously visible, each group exposes its own
stamp. Temporary lag is permitted only when the presentation makes that
currentness observable and no intent uses stale evidence. A later product
decision may require same-source presentation and accept the resulting
head-of-line blocking, but this ADR does not require it.

### 6. Bound pending projection work, not only queue slots

Pending projection work is bounded; authority history is never bounded or
coalesced by the projection scheduler. A newer committed source may replace
projection work that has not begun and has never been presented. Active work may
finish, but an obsolete result is rejected before application adoption.

The pending description is bounded by encoded bytes, retained source/effect
bytes, and Advance count as well as slot count. It may retain a bounded
contiguous Advance chain from the executor's acknowledged source. If continuity
cannot be retained within those bounds, the adapter replaces the chain with one
latest Seed request. Seed source materialization occurs outside the authority
critical path.

Exact slot counts, selected limits, and configuration mechanisms are
implementation policy recorded by the plan and promotion evidence; changing
them does not change the protocol or artifact interface.

Causal operations, receipts, and history are never coalesced inside a
full-history authority. That rule applies to the explicit restore oracle and a
future collaboration promotion path. Production LocalText owns no causal
history: browser drafts coalesce before one source-only acceptance and storage
replacement. Promotion requires evidence that ordinary full-history typing
does not degenerate into a
Seed per edit, burst work catches up, and obsolete tails become collectible.

### 7. Make Block-mode lag explicit

Block intent resolves only from the latest immutable Block artifact and carries
its source revision and causal document-version fence. While a newer bundle is
pending, Loomark exposes a typed pending state and does not silently apply an
intent to stale structure. Raw native input remains available. Browser evidence
must measure selected-executor response separately from main-thread task duration
and compare the Worker candidate when Gate 0C runs.

### 8. Require staged gates before executor promotion

Before authority and projection are decoupled, staged evidence must prove:

1. Warren can emit and serve page and Worker entries in direct and release
   builds without defining projection semantics.
2. A normalized projection protocol, pure adapter reducer, and in-process
   executor preserve the current observable projection contract.
3. A real Worker running the same protocol has differential parity after
   normalization, survives failure/restart, bounds Advance/Seed work and
   retained bytes under burst load, and records transport, interactive latency,
   presentation, and heap evidence.

Differential comparison covers observable source, Block structure and ranges,
semantic roles, MarkdownIR, diagnostics, Preview payload, and resolver evidence.
It normalizes or excludes Worker-local object identity, reactive-runtime
identity, timestamps, test-specific generation/sequence values, and incidental
map iteration order.

Dedicated-Worker promotion requires a recorded comparison against the
in-process executor. It may prefer main-thread isolation despite higher
end-to-end latency, but that trade-off must be explicit. If any stage fails,
implementation stops with evidence. Loomark does not ship a hidden synchronous
fallback under an asynchronous interface.

## Consequences

- The authority commit interface becomes deeper: callers receive one settled
  mutation result without coordinating parser, semantic, and presentation
  details.
- A causal mutation may produce zero projection artifacts. One projection
  request may issue zero or more group work items, each producing one Artifact
  Bundle.
- Intermediate committed sources may have no projection artifact if they were
  superseded before presentation. Their authority receipts and history remain
  complete.
- Projection presentation may become eventually current rather than same-turn.
  Currentness is explicit and testable through group stamps rather than call
  order.
- Worker packaging is proven infrastructure; Worker placement and protocol
  serialization become production architecture only after promotion.
- A promoted Worker owns a second live source representation plus
  parser/projection state. Memory, disposal, Seed frequency, pending bytes, and
  cutover retention require browser evidence.
- Block mode gains explicit feedback and pending/failure conditions. It never
  edits stale structure without an exact authority fence.
- Loom and Canopy retain their existing ownership: Loom defines parsing and
  semantics, Canopy defines projection, and Loomark defines execution policy and
  presentation. The execution seam changes only where that work runs.

## Rejected alternatives

### Keep all projection same-turn

This preserves current call order but leaves parser and semantic cost on the
authority task and cannot establish the requested main-thread isolation.

### Reparse from source in a fresh Worker for every edit

This avoids persistent Worker state but discards the incrementality and
collection contracts already established by Loom. It is retained only as the
Seed recovery path, not the steady-state design.

### Transfer live parser or reactive values across the Worker seam

Browser structured clone cannot preserve the process-local runtime identity,
closures, watches, scopes, or collection ownership required by Loom and `incr`.

### Publish every demanded lane through one global barrier

A global barrier gives simple same-source presentation but lets slow Preview or
diagnostic work delay interactive Block adoption. Demand-defined consistency
groups preserve atomicity where consumers share an invariant without restoring
head-of-line blocking between unrelated lanes.

### Fall back silently to same-turn projection

A silent fallback would make production responsiveness depend on an unobserved
runtime branch and invalidate the architecture's performance claim. Feasibility
failure stops executor promotion.
