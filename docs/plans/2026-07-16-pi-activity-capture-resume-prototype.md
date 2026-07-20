# Pi session activity → Resume view prototype

**Status:** Product framing superseded. Phase 0 and the explicit in-memory
import remain technical and source-inspection evidence; follow-up work is owned
by the current PKE direction and plan.

**Note:** This plan's product framing (resumable technical memory as the
near-term PKE wedge) is superseded by
[Agent history as thinking environment](2026-07-18-agent-history-thinking-environment.md),
which reorients the PKE toward three-scale movement (Trace, Shape, Meaning)
over agent histories. The technical baseline, decoder, WorkBench source
inspection, and provenance evidence in this plan remain valid as historical
evidence.

## Goal and scope

A person should be able to resume technical work from a pi session without
re-entering the same context. The first slice imports a sanitized session into
the existing web prototype and compares a deterministic, source-backed Resume
view with chronology.

| In | Out |
|---|---|
| Reuse `examples/web/` and its Vite/Playwright harness | New app, MoonBit package, or public API |
| Bounded pi session-v3 JSONL decoder in pure TypeScript | Raw keyboard, screen, clipboard, or microphone capture |
| Sanitized fixed fixture, chronology, and Resume view | System/context prompts, hidden reasoning, credentials, provider payloads |
| Explicit browser import of one selected snapshot | Persistent imported content or arbitrary full tool output |
| Provenance, branch, compaction, accessibility, and determinism tests | Agent mutation authority, external provider calls, generated summaries |
| Pilot against the chronological fallback | System-wide, multi-project, automatic, or live capture |

A project-local pi extension, live delivery, durable activity storage,
synchronization, and semantic candidates remain deferred until the fixed slice
passes.

## Reuse check

The existing `examples/web` Posts page, application modules, Playwright spec,
and Vite configuration provide the local-first product and test harness.

| Candidate | Decision |
|---|---|
| Posts page and Vite/Playwright setup | Reuse as prototype host and interaction precedent. |
| Post and engagement stores | Do not reuse: pi activity has session ancestry, replay, privacy, and deletion semantics. |
| `PostRetrievalIndex` | Defer: the fixed Resume view is a deterministic projection, not relevance ranking. |
| `lib/cognition` and Generative UI replay/identity types | Use as design precedents only; raw activity is a separate authority. |
| MoonBit core collections and event-graph provenance | Checked for later extraction; Phase 0 adds no MoonBit code. |

A later MoonBit extraction must repeat Existing API First and must not acquire
an `incr` dependency without measured need.

## Verified pi 0.80.7 contract

Sources: pi `docs/extensions.md`, `docs/session-format.md`, exported TypeScript
declarations, and input-transform examples.

| Surface | Verified behavior |
|---|---|
| `input` | Raw input before skill/template expansion; extension commands bypass it; no pi entry ID is exposed. |
| `before_agent_start` | Effective expanded prompt before the agent loop; no pi entry ID is exposed. |
| `message_end` | Finalized message value; no entry ID is exposed; fires before persistence. |
| `tool_execution_start` | Tool call ID, name, and arguments. |
| `tool_execution_end` | Tool call ID, name, result, and error status; arguments come from the paired start event. |
| `agent_settled` | No automatic retry, compaction retry, or queued continuation remains. |
| Session events | Start, shutdown, compaction, tree navigation, and pre-fork intent are distinct; a successful fork creates a session with a parent-session relationship. |
| Custom entries | `pi.appendEntry()` persists extension data outside LLM context. |
| Session storage | Version-3 JSONL uses `id`/`parentId`; compaction appends a summary and retains older entries. |

Live hooks cannot derive identity from a pi entry ID they do not expose.

## Core contract

### Authority

| Layer | Authority |
|---|---|
| Pi source session | What the person sent, what the assistant returned, tools run, and conversation ancestry |
| Imported activity | Bounded read-only projection with source-session and source-entry references |
| Checkpoint anchors | Human-authored or explicitly accepted goals, decisions, questions, and next actions |
| Resume view | Disposable projection that cannot modify sources or anchors |

Assistant text is a claim. A successful tool result is observed evidence, not
proof of a broader claim. Compaction and branch summaries remain source material
and cannot replace covered activity.

### Identity and content

- Native identity is `(pi session ID, pi entry ID)`.
- Tool start/end correlate through `(pi session ID, toolCallId)` and retain the
  containing source entry when available.
- A future extension uses `(pi session ID, extension-minted capture ID)` and
  persists that ID in a custom entry before replay.
- Content digests support integrity checks, never identity; equal identity with
  different canonical content is an error.
- Replay of an existing identity is a no-op.

The fixed fixture contains manually sanitized excerpts. A real import first
normalizes metadata and source references while raw bodies remain transient.
The normalized model is metadata-only by default. Only an explicitly selected,
bounded excerpt that passes fail-closed sensitive-pattern checks may enter the
in-memory view; rejected text has no override in the first slice. Nothing is
written to browser persistence. Tool data uses per-tool allowlists; result text
must correlate to an allowlisted call on the selected ancestry path and is
retained only as a bounded excerpt. Unbounded or uncorrelated result bodies are
never imported. Omissions are visible diagnostics.

### Functional core and imperative shell

| Core | Shell |
|---|---|
| JSONL decode, normalization, branch selection, idempotent reduction, checkpoint selection, Resume projection | File selection/read, fixture load, DOM render, focus management, diagnostics |

The core accepts explicit values and returns readonly results or diagnostics. It
does not access the DOM, filesystem, clock, network, or `localStorage`.

## Delivery

### Phase 0 — Fixed transcript and view

1. Add a sanitized v3 fixture under `examples/web/tests/fixtures/` with a
   session header, ancestry, human goal, read/edit/validation activity, one
   failed result, assistant claims, accepted decision/question/next-step
   anchors, compaction, and at least two terminal paths.
2. Add a pure decoder. Before reading or retaining content, enforce limits for
   file bytes, line bytes, entry count, ancestry depth, and excerpt length.
   Reject malformed JSONL, unsupported versions, duplicate IDs, missing
   parents, and cycles. Retain only allowlisted metadata.
3. Add a pure reducer and Resume projection preserving order, ancestry,
   accepted anchors, evidence distinctions, and source references.
4. Add `resume.html`, register it in the Vite input map, and render chronology
   and Resume without mutating normalized activity.
5. Add Playwright coverage for the contract below.

Phase 0 passes when:

- [x] The same normalized activity produces byte-for-byte equivalent Resume
      model output across repeated runs.
- [x] Invalid bounds, versions, JSONL, identity, parentage, and cycles fail with
      diagnostics.
- [x] Replay is a no-op; identity/content mismatch is an integrity error.
- [x] `dist/resume.html` is emitted by the production build.
- [x] Human anchors, assistant claims, and tool evidence remain distinct and
      source-linked.
- [x] Compaction retains covered activity; terminal branches require explicit
      selection and never merge silently.
- [x] Keyboard and screen-reader users can switch views and inspect evidence on
      equivalent terms.

### Phase 1 — Explicit session import

1. Accept one user-selected `.jsonl` snapshot in memory; never scan `~/.pi`,
   watch files, or persist the import.
2. Show session ID, working directory, timestamp, and selected branch.
3. Require selection when several terminal paths exist. Same-file branches and
   `/fork` child sessions remain distinct.
4. Preserve selected-path activity across compaction; label summaries as
   summaries.
5. Show omissions and rejected-entry diagnostics, plus a `Forget imported
   session` action. Clearing or reloading removes the Canopy copy; deleting the
   pi session is separate.

Phase 1 passes when:

- [x] A current pi snapshot renders without re-entering its prompt.
- [x] No imported content reaches browser persistence.
- [x] Excluded blocks, metadata, custom messages, and tool bodies remain outside
      the normalized model; only accepted excerpts enter the in-memory view.
- [x] Diagnostics explain omissions, and Forget clears only the Canopy copy.

**Validated outcome (2026-07-18):** The current 24,418,932-byte pi snapshot
imported from one explicit file selection, reduced to its single terminal path,
and produced the bounded Resume, chronology, and semantic-preview inputs
without prompt re-entry. Playwright verifies that import creates no
`localStorage`, `sessionStorage`, or IndexedDB state, Forget returns only this
page to the demo, and reload discards an imported fixture. Sensitive/excluded
content and malformed references remain covered by the closed decoder and
safe-corpus tests, with visible omission diagnostics.

### Phase 2 — Dogfood and compare

Use sanitized real Canopy sessions, including the session that established the
PKE direction. Before each pilot, predeclare the time bound and questions
covering goal, verified outcome, unresolved question, and next step. Compare
matched Resume and chronology conditions, counterbalance order when possible,
and record correctness, orientation time, source openings, missing evidence,
and corrections. Iterate the fixed view through direct human feedback before
widening capture.

The pilot passes only when an evaluator of an unseen transcript can, within five
minutes:

1. state the primary task;
2. identify a verified outcome without treating assistant prose as proof;
3. identify the unresolved question or next step; and
4. open source evidence for each answer.

Resume must improve correctness, time, or both without reducing traceability.
Otherwise record the failed hypothesis and stop before widening capture.

**Inspected outcome (2026-07-17):** The fixed Resume view was inspected
against a real Canopy session with no accepted checkpoints. The view correctly
reproduces session metadata, bounded excerpts, and evidence labels with source
references, but it does not explain what the session means. A person who reads
the fixed Resume still has to reconstruct intent, progress, and open questions
from chronology and evidence items. The fixed Resume product hypothesis fails:
the view is a correct, inspected technical baseline, but not the product view.
Chronology remains the fallback and comparison source, not the product view.

The Phase 2 dogfood-and-compare product comparison was replaced by a bounded
semantic briefing study, which failed because cardinality and content complexity
defeated byte-only chunking; no Cloudflare or study runtime remains in this PR.
The fixed viewer remains available as the comparison baseline; product framing
is superseded by
[Agent history as thinking environment](2026-07-18-agent-history-thinking-environment.md).

### Phase 3 — Project-local extension (gated)

Only after Phases 0–2 pass **and** a separate implementation plan and explicit
authorization are approved. Passing the semantic study does not authorize
capture or persistence.

1. Add `.pi/extensions/canopy-capture/` observing `input`,
   `before_agent_start`, finalized messages, paired tool start/end events,
   `agent_settled`, and session lifecycle events.
2. Store only policy, extension-minted identity, explicit checkpoint markers,
   and sanitized correlation metadata in custom entries; never duplicate native
   message bodies.
3. Provide `/canopy-capture on|off|status` and a persistent indicator. `off`
   suppresses Canopy custom records but not pi's native persistence.
   Extension-originated inputs are never classified as human input.
4. Persist accepted custom records immediately. Hook failure must not transform
   input, block tools, call a provider, or depend on Canopy availability.

Phase 3 passes when extension IDs survive reload, capture-off state is visible,
and extension failure leaves pi input and tool execution unchanged. Live
transport remains out of scope; it requires a separate durable-outbox,
idempotent-acknowledgment, cancellation, retention, and failure-isolation plan.

## Validation

```bash
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test
moon build --target js

cd examples/web
npx tsc --noEmit
npm run build
npx playwright test tests/post-app.spec.ts tests/pi-resume.spec.ts
cd ../..

# Only after Phase 3 authorization
pi -e .pi/extensions/canopy-capture/index.ts

NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
git diff --check
```

If the page changes visually, inspect it with human feedback before treating
Playwright as sufficient evidence.

## Risks

- **Sensitive input:** explicit file selection is not sanitization; false
  negatives remain possible and pi retains its independent source session.
- **False authority:** fluent assistant prose can resemble a decision; only
  human-authored or accepted anchors enter checkpoints.
- **Branch ambiguity:** same-file paths and forked child sessions are different
  histories.
- **Format coupling:** unsupported pi formats fail closed until reviewed.
- **Premature abstraction:** a MoonBit framework before UX validation creates
  API debt.
- **Surveillance drift:** a failed view does not justify broader passive
  capture; every source needs a named missing signal and privacy review.
