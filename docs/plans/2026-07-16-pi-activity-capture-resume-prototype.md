# Pi session activity → Resume view prototype

**Status:** ready for Phase 0. Live transport and long-term storage remain
separate follow-ups gated by the fixed prototype.

## Why

A developer who stops work must later reconstruct goal, verified outcomes,
unresolved questions, and next step. The
[PKE direction](../architecture/personal-knowledge-environment-direction.md)
initial wedge is resumable technical project memory. Pi already persists
structured, branching JSONL sessions. The smallest falsifiable slice is an
explicit import of a sanitized pi session into the existing browser prototype,
followed by a deterministic source-backed Resume View.

## Scope

| In | Out |
|---|---|
| `examples/web/` — reuse prototype host, Vite/Playwright harness; separate Resume page | Raw keyboard, clipboard, microphone, or screen capture |
| Bounded pi session-v3 JSONL decoder and normalized activity model in pure TypeScript | System prompts, context-file contents, hidden reasoning, credentials, API keys, provider payloads |
| Sanitized fixed fixture from a representative Canopy pi session | Moving raw message bodies into the normalized model without explicit excerpt selection and fail-closed content check |
| Deterministic chronological view and Resume View | Persisting arbitrary full tool output |
| Explicit browser file-import path for a pi session snapshot | Treating assistant prose, compaction summaries, or generated UI as knowledge authority |
| Playwright coverage for provenance, branch selection, compaction, accessibility, deterministic rendering | Agent mutation authority over Canopy or pi sessions |
| Small orientation pilot comparing Resume View with chronological fallback | External provider calls; system-wide or multi-project background capture |

**Deferred** until fixed slice passes: project-local pi extension for capture
policy and checkpoint markers; automatic or live delivery from pi to Canopy;
Canopy-owned durable storage and synchronization; MoonBit activity package;
semantic or generated checkpoint candidates.

## Current state

### Existing Canopy product prototype

`examples/web/posts.html` provides the prototype host: one-field local
capture, chronological fallback, source-backed lexical retrieval, explicit
ranking reasons, keyboard behavior, Playwright tests. Implementation split:

- `examples/web/src/post-app.ts`, `post-store.ts`, `post-events.ts`,
  `post-retrieval.ts`
- `examples/web/tests/post-app.spec.ts`
- `examples/web/vite.config.ts`

The Resume prototype shares this Vite app and visual language but must not
force pi activity into the existing post or engagement schemas. Posts are
person-authored; imported agent activity has different identity, provenance,
privacy, and deletion requirements.

### Integration boundary

The external agent runtime remains authoritative for its conversation session;
Canopy owns only the bounded imported projection. This slice is read-only with
respect to pi and does not grant the agent mutation authority.

### Verified pi surface

Package `@earendil-works/pi-coding-agent` 0.80.7. Source:
`docs/extensions.md`, `docs/session-format.md`, exported TypeScript
declarations, input-transform examples.

| Surface | Verified behavior |
|---|---|
| `input` | Raw input before skill/template expansion; extension commands bypass it; no pi entry ID exposed. |
| `before_agent_start` | Effective expanded prompt before agent loop; no pi entry ID exposed. |
| `message_end` | Finalized message value; no session entry ID exposed; fires before message is persisted. |
| `tool_execution_start` | Tool call ID, name, and arguments. |
| `tool_execution_end` | Tool call ID, name, result, and error status; arguments correlated from start event. |
| `agent_settled` | No automatic retry, compaction retry, or queued continuation remains. |
| Session events | Start, shutdown, compaction, tree navigation, pre-fork intent are distinct. A successful fork starts a new session with parent-session relationship. |
| Custom entries | `pi.appendEntry()` persists extension data without adding it to LLM context. |
| Session storage | Version-3 JSONL entries form a tree through `id`/`parentId`; compaction appends a summary, does not delete older entries. |

Live hooks do **not** justify deriving an activity ID from a pi entry ID.
Offline import uses native entry IDs; a future extension must mint and persist
its own capture identity when no native ID is exposed.

## Reuse check

| Candidate | Decision |
|---|---|
| `examples/web/posts.html` + Vite/Playwright | Reuse as prototype host and interaction precedent. |
| `LocalPostStore` / `LocalPostEventStore` | Do not reuse. Browser-local post/engagement IDs do not represent pi session ancestry or import replay. |
| `PostRetrievalIndex` | Do not use in fixed slice. Resume must be deterministic projection, not relevance ranking. |
| `lib/cognition` | Do not use as raw activity storage. Downstream context/indexing candidate, not conversation authority. |
| `GenerativeUiReplaySource` + provider identity wrappers | Checked as reducer/replay and opaque-ID precedents; not imported. Would couple unrelated domains. |
| Event-graph snapshot provenance | Checked as causal-provenance precedent; not imported across submodule boundary. |
| MoonBit core collections | Checked for later extraction. First slice adds no MoonBit code. |

If the fixed prototype succeeds, a follow-up must repeat Existing API First
before extracting a MoonBit package. That extraction must not acquire an
`incr` dependency unless measured behavior requires reactivity.

## Authority and data model

Four distinct layers:

1. **Pi source session** — authoritative for what was sent, returned, which
   tools ran, how conversation branched.
2. **Imported activity** — bounded read-only projection; every item retains
   source-session and source-entry reference.
3. **Checkpoint anchors** — goals, decisions, questions, next actions are
   human-authored or explicitly accepted. Fixed reducer does not infer from
   assistant prose.
4. **Resume View** — disposable projection over imported activity and accepted
   anchors. Cannot modify either.

Assistant text is a claim, not verification. A successful tool result is
observed evidence. A compaction or branch summary is source material with
provenance, not a replacement for earlier activity.

### Message-content boundary

The fixed fixture contains manually sanitized excerpts. For an imported real
session: the decoder normalizes metadata and source references while raw
message bodies remain in a transient source buffer. The normalized model is
metadata-only by default. A person may explicitly select a bounded excerpt for
the in-memory view; before it crosses the boundary, a fail-closed check
rejects credential-shaped tokens, private-key material, and other configured
sensitive patterns with a diagnostic. The first slice offers no override for
rejected text and writes no excerpt to browser persistence. Tool content never
uses this excerpt path. Tool-specific allowlists admit only minimum arguments
and outcome metadata needed for orientation.

This minimizes an additional Canopy copy; it does not claim to sanitize the
independently retained pi source session or detect every possible secret.

### Stable identity

- **Native imported entry:** `(pi session ID, pi entry ID)`.
- **Tool lifecycle:** correlate start/end with `(pi session ID, toolCallId)`,
  retaining the containing source-entry reference when available.
- **Future extension-only record:** `(pi session ID, extension-minted capture
  ID)`; minted ID must be stored in a custom entry before replay can rely on
  it.
- Content digests may support integrity checks, but identical text in
  different turns remains distinct activity.

Re-importing the same source identity is a semantic no-op. Equal identity with
different content is an integrity error, not an update.

## Functional core and imperative shell

- **Functional core:** bounded JSONL decode, normalization, branch-path
  selection, idempotent reduction, checkpoint selection, Resume model
  projection. Accept explicit values, return values or diagnostics; no
  DOM/filesystem/clock/network/`localStorage` access.
- **Imperative shell:** browser file selection, reading, fixture loading, DOM
  rendering, focus management, user-visible import errors.

Validated results expose readonly values or defensive copies. The decoder
rejects unsupported shapes with structured diagnostics.

## Steps

### Phase 0 — Fixed transcript and view

1. Add sanitized v3 pi fixture under `examples/web/tests/fixtures/` containing:
   session header and stable native entry ancestry; human-authored goal;
   read/edit/validation tool activity including one failed result; assistant
   claims distinguished from tool evidence; explicit accepted checkpoint
   anchors (decision, unresolved question, next step); compaction entry
   retaining covered source entries; at least two terminal tree paths.

2. Add pure bounded decoder. Accepts session v3; returns normalized activity
   or structured diagnostics. Before reading or retaining content, the shell
   enforces documented limits for file bytes, line bytes, entry count, ancestry
   depth, and selected-excerpt length. Duplicate
   IDs, missing parents, ancestry cycles, unsupported versions, malformed
   JSONL fail closed. Retains redacted provider/model identity; drops thinking
   blocks, images, unknown custom messages, raw provider metadata, tool result
   bodies, unsupported entries. Tool arguments use per-tool allowlist.

3. Add pure reducer and Resume projection: collapse replay by stable source
   identity; reject identity/content mismatch; preserve source order and
   ancestry; select only explicit accepted checkpoint anchors; keep assistant
   claims separate from verified tool outcomes; return source references for
   every Resume item.

4. Add `examples/web/resume.html` and thin DOM shell. Follow posts prototype
   typography and interaction principles. Use semantic headings, lists,
   buttons, status text, source links. Register in Vite input map; assert
   production build emits `dist/resume.html`.

5. Render chronology and Resume side by side or through explicit view toggle.
   Neither view may mutate normalized activity.

6. Add Playwright tests for deterministic output, source traceability,
   duplicate replay, identity collision, branch selection, compaction
   preservation, keyboard navigation, accessible names/structure.

### Phase 1 — Explicit pi session import

1. File-picker accepts one user-selected `.jsonl` snapshot. Browser reads in
   memory. First slice does not scan `~/.pi`, watch files, or write to
   `localStorage`.
2. Display source session ID, working directory, timestamp, selected branch
   before rendering content.
3. Multiple terminal branches require explicit selection. Do not conflate
   `/fork` children with same-file branches: forked sessions have their own
   session file and optional parent-session reference.
4. Preserve all selected-path activity across compaction. Display compaction
   summaries as labeled source claims; never substitute for or delete covered
   activity.
5. Show rejected-entry counts and diagnostics. Unsupported or sensitive content
   is omitted visibly, not silently.
6. `Forget imported session` action. First slice has no Canopy persistence;
   clearing page state or reloading removes the imported copy. Deleting the
   original pi session remains separate.

### Phase 2 — Dogfood and comparison

1. Import sanitized snapshots from real Canopy development sessions, including
   the PKE direction session.
2. Predeclare orientation questions and time bound before each pilot. Questions
   must cover: session goal, at least one verified outcome, unresolved
   question, next step.
3. Compare Resume View with chronological fallback. Matched transcripts,
   counterbalanced order with multiple participants. Record correctness, time
   to orientation, missing evidence, source-opening behavior, corrections.
4. Iterate through direct human feedback. Do not add automatic ranking,
   summarization, or generated UI to compensate for an inadequate event model.
5. Stop if Resume View does not improve orientation over chronology. Record
   failed hypothesis before widening capture.

### Phase 3 — Project-local pi extension (gated)

Only after Phases 0–2 pass.

1. Add trusted project-local extension under `.pi/extensions/canopy-capture/`.
   May observe `input`, `before_agent_start`, finalized messages, paired tool
   start/end, `agent_settled`, session lifecycle.
2. Do not duplicate native message bodies in custom entries. Use custom entries
   for capture policy, extension-minted identity, explicit checkpoint markers,
   sanitized correlation metadata.
3. Expose commands `/canopy-capture on|off|status` with persistent visible
   status indicator. `off` suppresses new Canopy custom records but does not
   change pi's native session persistence. Extension-originated inputs are not
   classified as human input.
4. Persist each accepted custom record immediately with `pi.appendEntry()`. Do
   not describe an in-memory buffer as a durable outbox.
5. Hook failure returns control to pi unchanged. Capture must not modify
   prompts, block tools, call a provider, or depend on Canopy availability.
6. Live delivery to Canopy is outside this plan. Later transport requires
   durable local outbox, idempotent acknowledgment, cancellation, retention,
   and failure-isolation plan before network or socket code.

## Acceptance criteria

### Fixed core and view

- [ ] Sanitized fixture decodes without unsupported implicit defaults.
- [ ] Oversized input, unsupported versions, malformed JSONL, duplicate native
      IDs, missing parents, ancestry cycles fail closed with diagnostics.
- [ ] Replaying an imported source identity is a no-op; equal identity with
      different content is an integrity diagnostic.
- [ ] Same normalized activity produces byte-for-byte equivalent Resume model
      output across repeated runs.
- [ ] Explicit Vite input map includes `resume.html`; production build emits
      `examples/web/dist/resume.html`.
- [ ] Assistant claims, tool evidence, and human-accepted anchors are visibly
      distinct.
- [ ] Every Resume item exposes a source reference.
- [ ] Compaction leaves covered activity available and labels its summary as a
      summary.
- [ ] Multiple terminal branches require explicit selection and never merge
      silently.
- [ ] Keyboard and screen-reader users can import, choose a branch, switch
      views, inspect sources, and forget imported state on equivalent terms.

### Explicit import

- [ ] A person can select a current pi session snapshot and render it without
      re-entering the same prompt.
- [ ] No imported session content is written to browser persistence in first
      slice.
- [ ] Thinking blocks, images, raw provider metadata, system/context material,
      unknown custom messages, full tool-result bodies do not enter the
      normalized activity model.
- [ ] Raw user/assistant text stays outside the normalized model by default;
      only explicitly selected bounded excerpts passing fail-closed content
      check enter the in-memory view.
- [ ] Import diagnostics state what was omitted and why.
- [ ] Reloading or `Forget imported session` clears the Canopy copy while
      leaving the pi session unchanged.

### Falsifiable product test

For an unseen transcript, the predeclared Resume condition passes only if the
evaluator can, within five minutes:

1. state the primary task;
2. identify at least one verified outcome without treating assistant prose as
   verification;
3. identify the unresolved question or next step;
4. open the source evidence for each answer.

The same questions are attempted with the chronological fallback. Record both
correctness and time. Passing the five-minute bound alone does not establish
product value: the Resume View must improve correctness, time, or both without
reducing source traceability. Pilot result, not a statistical claim.

### Gated extension

- [ ] Extension not started until fixed-view product test passes.
- [ ] Custom entries do not copy native user or assistant message bodies.
- [ ] Extension-minted IDs survive session reload because they are persisted in
      custom entries.
- [ ] Capture-off state is visible and suppresses new Canopy custom records
      without claiming to disable pi's native session persistence.
- [ ] Extension failure never blocks or transforms pi input or tool execution.

## Validation

```bash
# Workspace baseline and JS artifacts
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test
moon build --target js

# Existing web prototype plus new Resume page
cd examples/web
npx tsc --noEmit
npm run build
npx playwright test tests/post-app.spec.ts tests/pi-resume.spec.ts

# If Phase 3 is later authorized
pi -e .pi/extensions/canopy-capture/index.ts

# Documentation and interface drift
cd ../..
NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
git diff --check
```

If the web page changes visually, run the browser prototype and inspect with
human feedback before treating Playwright as sufficient evidence.

## Risks

- **Imported-content sensitivity.** Pi sessions may contain secrets in ordinary
  text or tool output. Explicit file selection does not make content safe.
  Metadata-first normalization, bounded excerpt selection, and fail-closed
  checks minimize the additional Canopy projection, but false negatives remain
  possible and the source session remains independently retained by pi.
- **False checkpoint authority.** A fluent assistant summary can look like a
  decision. Fixed slice accepts only explicit human-authored or accepted
  anchors.
- **Branch ambiguity.** A JSONL file can contain several terminal paths; a
  fork is a separate child session. Conflating them produces false history.
- **Format coupling.** Decoder targets pi session v3. A new format must fail
  closed until migration or compatibility is reviewed.
- **Premature abstraction.** Extracting a MoonBit framework before the Resume
  interaction stabilizes turns product uncertainty into public API debt.
- **Surveillance drift.** Fixed-view failure is not evidence that more passive
  capture is needed. Every wider source requires a named missing signal and a
  new privacy review.
