# Pi session activity → Resume view prototype

**Status:** ready for Phase 0. Live transport and long-term storage remain
separate follow-ups gated by the fixed prototype.

## Why

A developer or researcher who stops work on a technical project must later
reconstruct the goal, verified outcomes, unresolved questions, and next step.
The initial wedge of the
[Personal Knowledge Environment direction](../architecture/personal-knowledge-environment-direction.md)
is resumable technical project memory: capture work already expressed through
an agent session, then restore orientation without requiring duplicate notes.

Pi already persists the current conversation as a structured, branching JSONL
session. The smallest falsifiable slice is therefore not a new capture daemon or
a new MoonBit framework. It is an explicit import of a sanitized pi session
into the existing browser product prototype, followed by a deterministic,
source-backed Resume View. A live extension is considered only after that fixed
view proves useful.

## Scope

In for the first slice:

- `examples/web/` — reuse the existing local-first product prototype and Vite /
  Playwright harness; add a separate Resume page rather than a new app.
- A bounded pi session-v3 JSONL decoder and normalized activity model in pure
  TypeScript.
- A sanitized fixed fixture derived from a representative Canopy pi session.
- A deterministic chronological view and Resume View over the same activity.
- An explicit browser file-import path for a pi session snapshot.
- Playwright coverage for provenance, branch selection, compaction preservation,
  accessibility, and deterministic rendering.
- A small orientation pilot comparing the Resume View with the chronological
  fallback.

Deferred until the fixed slice passes:

- A project-local pi extension for capture policy and checkpoint markers.
- Automatic or live delivery from pi to Canopy.
- Canopy-owned durable activity storage, retention, and synchronization.
- A MoonBit activity package or public API.
- Semantic or generated checkpoint candidates.

Out:

- Raw keyboard, clipboard, microphone, or screen capture.
- System prompts, context-file contents, hidden reasoning, credentials, API
  keys, or provider payloads.
- Moving raw user or assistant message bodies into the normalized activity
  model without explicit excerpt selection and a fail-closed content check.
- Persisting arbitrary full tool output in Canopy.
- Treating assistant prose, compaction summaries, or generated UI as knowledge
  authority.
- Agent mutation authority over Canopy or pi sessions.
- External provider calls.
- System-wide or multi-project background capture.

## Current state

### Existing Canopy product prototype

`examples/web/posts.html` already provides the least-wrong prototype host. It
has one-field local capture, a chronological fallback, source-backed lexical
retrieval, explicit ranking reasons, keyboard behavior, and Playwright tests.
Its implementation is split across:

- `examples/web/src/post-app.ts`
- `examples/web/src/post-store.ts`
- `examples/web/src/post-events.ts`
- `examples/web/src/post-retrieval.ts`
- `examples/web/tests/post-app.spec.ts`
- `examples/web/vite.config.ts`

The Resume prototype should share this Vite app and visual language but must not
force pi activity into the existing post or engagement schemas. Posts are
person-authored content; imported agent activity has different identity,
provenance, privacy, and deletion requirements.

### Integration boundary

The external agent runtime remains authoritative for its conversation session;
Canopy owns only the bounded imported projection and later curated memory. This
slice is read-only with respect to pi, does not grant the agent mutation
authority, and does not require Canopy to own an agent loop.

### Verified pi surface

The inspected pi package is `@earendil-works/pi-coding-agent` 0.80.7. Its
`docs/extensions.md`, `docs/session-format.md`, exported TypeScript declarations,
and input-transform examples establish the following:

| Surface | Verified behavior relevant here |
|---|---|
| `input` | Raw input before skill/template expansion; extension commands bypass it; no pi entry ID is exposed. |
| `before_agent_start` | Effective expanded prompt before the agent loop; no pi entry ID is exposed. |
| `message_end` | Finalized message value; the event itself exposes no session entry ID and fires before that message is persisted. |
| `tool_execution_start` | Tool call ID, name, and arguments. |
| `tool_execution_end` | Tool call ID, name, result, and error status; arguments must be correlated from the start event. |
| `agent_settled` | No automatic retry, compaction retry, or queued continuation remains. |
| Session events | Start, shutdown, compaction, actual tree navigation, and pre-fork intent are distinct events. A successful fork starts a new session with a parent-session relationship. |
| Custom entries | `pi.appendEntry()` persists extension data without adding it to LLM context. |
| Session storage | Version-3 JSONL entries form a tree through `id` and `parentId`; compaction appends a summary and does not delete older entries. |

The live hooks do **not** justify deriving an activity ID from a pi entry ID.
Offline import can use native entry IDs; a future extension must mint and persist
its own capture identity when no native ID is exposed.

### Missing behavior

- No bounded decoder imports pi session entries into Canopy.
- No normalized activity model separates human input, assistant claims, tool
  evidence, checkpoints, and session lifecycle.
- No Resume View compares a reduced orientation surface with chronology.
- No product evidence shows that the reduced view improves resumption.

## Reuse check

| Candidate | Decision |
|---|---|
| `examples/web/posts.html` and its Vite/Playwright setup | Reuse as the prototype host and interaction precedent. |
| `LocalPostStore` / `LocalPostEventStore` | Do not reuse as activity authority. Their browser-local post and engagement IDs do not represent pi session ancestry or import replay. |
| `PostRetrievalIndex` | Do not use in the fixed slice. Resume must first be a deterministic projection of explicit records, not relevance ranking. |
| `lib/cognition` | Do not use as raw activity storage. It is a downstream context/indexing candidate, not conversation or curated-memory authority. |
| `GenerativeUiReplaySource` and provider identity wrappers | Checked as reducer/replay and opaque-ID precedents, but not imported. Reusing them would couple unrelated domains and force a MoonBit boundary before the UX is validated. |
| Event-graph snapshot provenance | Checked as a causal-provenance precedent, but not imported across the submodule boundary. Pi ancestry remains pi-session ancestry. |
| MoonBit `Map`, `Set`, `Array`/`ArrayView`, `Option`/`Result`, `StringView`, and `BytesView` | Checked for a later MoonBit extraction. The first slice adds no MoonBit API, loop, helper, or collection code, so none is needed yet. |

If the fixed prototype succeeds, a follow-up plan must repeat Existing API First
before extracting a private MoonBit package. That extraction must not acquire an
`incr` dependency unless measured product behavior requires reactivity.

## Authority and data model

The prototype keeps four layers distinct.

1. **Pi source session.** Pi remains authoritative for what the person sent,
   what the assistant returned, which tools ran, and how the conversation
   branched.
2. **Imported activity.** A bounded, read-only projection copies only the event
   classes permitted by the import policy. Every item retains a source-session
   and source-entry reference.
3. **Checkpoint anchors.** Goals, decisions, questions, and next actions are
   human-authored or explicitly accepted fixture records. The fixed reducer does
   not infer them from assistant prose.
4. **Resume View.** A disposable projection over imported activity and accepted
   anchors. It cannot modify either.

Assistant text is a claim, not verification. A successful tool result is
observed evidence, not proof of the wider claim. A compaction or branch summary
is source material with provenance, not a replacement for earlier activity.

### Message-content boundary

The fixed fixture contains manually sanitized excerpts. For an imported real
session, the decoder first normalizes metadata and source references while raw
message bodies remain in a transient source buffer. The normalized model is
metadata-only by default. A person may explicitly select a bounded user or
assistant excerpt for the in-memory Resume View; before it crosses the boundary,
a fail-closed check rejects credential-shaped tokens, private-key material, and
other configured sensitive patterns with a diagnostic. The first slice offers
no override for rejected text and writes no selected excerpt to browser
persistence.

This policy minimizes an additional Canopy copy; it does not claim to sanitize
the independently retained pi source session or detect every possible secret.
Tool content never uses this excerpt path. Tool-specific allowlists admit only
the minimum arguments and outcome metadata needed for orientation.

### Stable identity

- Native imported entry: `(pi session ID, pi entry ID)`.
- Tool lifecycle: correlate start/end with `(pi session ID, toolCallId)` while
  retaining the containing source-entry reference when available.
- Future extension-only record: `(pi session ID, extension-minted capture ID)`;
  the minted ID must be stored in a custom entry before replay can rely on it.
- Canonical content and digests may support integrity checks, but identical text
  in different turns remains distinct activity.

Re-importing the same source identity is a semantic no-op. Equal identity with
different canonical content is an integrity error, not an update.

## Functional core and imperative shell

The first slice keeps the boundary inside `examples/web`:

- **Functional core:** bounded JSONL decode, normalization, branch-path
  selection, idempotent reduction, checkpoint selection, and Resume model
  projection. These functions accept explicit values, return values or
  diagnostics, and do not read the DOM, filesystem, clock, network, or
  `localStorage`.
- **Imperative shell:** browser file selection, file reading, fixture loading,
  DOM rendering, focus management, and user-visible import errors.

Validated results expose readonly values or defensive copies. The decoder
rejects unsupported shapes with structured diagnostics rather than silently
inventing defaults.

## Desired state

After Phases 0–2:

1. `resume.html` displays a fixed chronological activity list and a fixed Resume
   View from the same sanitized pi fixture.
2. The Resume View shows a source-backed current goal, accepted decisions,
   verified outcomes, unresolved questions, next step, and changed artifacts
   only when the fixture contains evidence for them.
3. Every displayed claim links to or identifies its source session entry.
4. A person can explicitly import a pi JSONL snapshot without transmitting or
   persistently storing it in Canopy.
5. Branches remain distinct, compaction does not erase prior activity, and
   replay does not duplicate entries.
6. The fixed view is keyboard operable and screen-reader legible.
7. A comparison with the chronological fallback records whether the reduction
   actually improves orientation. No product-value claim is made if it does
   not.

## Steps

### Phase 0 — Fixed transcript and view

1. Add a sanitized version-3 pi fixture under
   `examples/web/tests/fixtures/`. It must contain:
   - a session header and stable native entry ancestry;
   - a human-authored goal;
   - read, edit, and validation tool activity, including one failed result;
   - assistant claims clearly distinguished from tool evidence;
   - explicit accepted checkpoint anchors for a decision, unresolved question,
     and next step;
   - a compaction entry while retaining the covered source entries;
   - at least two terminal tree paths so branch selection is exercised.

2. Add a pure bounded decoder. It accepts session version 3 and returns
   normalized activity or structured diagnostics. Before reading or retaining
   content, the shell enforces documented limits for file bytes, line bytes,
   entry count, ancestry depth, and selected-excerpt length. Duplicate entry
   IDs, missing parents, ancestry cycles, unsupported versions, and malformed
   JSONL fail closed. The decoder retains redacted provider/model identity but
   drops thinking blocks, images, unknown custom messages, raw provider
   metadata, tool result bodies, and unsupported entries from the imported
   model. Tool arguments use a per-tool allowlist; generic argument objects
   never cross the boundary.

3. Add a pure reducer and Resume projection. It must:
   - collapse replay by stable source identity;
   - reject identity/content mismatch;
   - preserve source order and ancestry;
   - select only explicit accepted checkpoint anchors;
   - keep assistant claims separate from verified tool outcomes;
   - return source references for every Resume item.

4. Add `examples/web/resume.html` and a thin DOM shell. Follow the existing
   posts prototype's typography and interaction principles, but use semantic
   headings, lists, buttons, status text, and source links appropriate to a
   read-only orientation view. Register `resume.html` in the explicit Vite
   input map and assert that the production build emits `dist/resume.html`.

5. Render chronology and Resume side by side or through an explicit view toggle.
   Neither view may mutate the normalized activity.

6. Add Playwright tests for deterministic output, source traceability,
   duplicate replay, identity collision, branch selection, compaction
   preservation, keyboard navigation, and accessible names/structure.

### Phase 1 — Explicit pi session import

1. Add a file-picker action that accepts one user-selected `.jsonl` snapshot.
   The browser reads it in memory. The first slice does not scan `~/.pi`, watch
   files, or write imported content to `localStorage`.
2. Display the source session ID, working directory, timestamp, and selected
   branch before rendering imported content.
3. If multiple terminal branches exist, require an explicit branch selection.
   Do not call `/fork` children branches of the same file: forked sessions have
   their own session file and optional parent-session reference.
4. Preserve all selected-path activity across compaction. Display compaction
   summaries as labeled source claims; never substitute them for or delete
   covered activity in the knowledge ledger.
5. Show rejected-entry counts and diagnostics. Unsupported or sensitive content
   is omitted visibly, not silently treated as absent evidence.
6. Provide a clear `Forget imported session` action. Because the first slice
   has no Canopy persistence, clearing the page state or reloading removes the
   imported copy; deleting the original pi session remains a separate action.

### Phase 2 — Dogfood and comparison

1. Import sanitized snapshots from real Canopy development sessions, including
   the session that established the PKE direction.
2. Before each pilot, predeclare the orientation questions and time bound.
   Questions must cover the session goal, at least one verified outcome, the
   unresolved question, and the next step.
3. Compare the Resume View with the chronological fallback. Use matched
   transcripts and counterbalance presentation order when more than one person
   participates. Record correctness, time to orientation, missing evidence,
   source-opening behavior, and corrections.
4. Iterate the fixed view through direct human feedback. Do not add automatic
   ranking, summarization, or generated UI to compensate for an inadequate
   event model.
5. Stop if the Resume View does not improve orientation over chronology. Record
   the failed hypothesis before widening capture.

### Phase 3 — Project-local pi extension (gated follow-up)

Only begin after Phases 0–2 pass.

1. Add a trusted project-local extension under
   `.pi/extensions/canopy-capture/`. The extension may observe `input`,
   `before_agent_start`, finalized messages, paired tool start/end events,
   `agent_settled`, and session lifecycle events.
2. Do not duplicate native message bodies in custom entries. Use custom entries
   for capture policy, extension-minted identity, explicit checkpoint markers,
   and sanitized correlation metadata that native entries cannot express.
3. Expose unambiguous commands such as `/canopy-capture on|off|status` and a
   persistent visible status indicator. `off` suppresses new Canopy custom
   records but does not change pi's independent native session persistence.
   Extension-originated inputs are not classified as human input.
4. Persist each accepted custom record immediately with `pi.appendEntry()`.
   Do not describe an in-memory buffer as a durable outbox.
5. A hook failure must return control to pi unchanged. Capture must not modify
   prompts, block tools, call a provider, or depend on Canopy being available.
6. Live delivery to a Canopy process is outside this plan. Any later transport
   requires a durable local outbox, idempotent acknowledgment, cancellation,
   retention, and failure-isolation plan before network or socket code lands.

## Acceptance criteria

### Fixed core and view

- [ ] The sanitized fixture decodes without unsupported implicit defaults.
- [ ] Oversized input, unsupported versions, malformed JSONL, duplicate native
      IDs, missing parents, and ancestry cycles fail closed with diagnostics.
- [ ] Replaying an imported source identity is a no-op; equal identity with
      different content is an integrity diagnostic.
- [ ] The same normalized activity produces byte-for-byte equivalent Resume
      model output across repeated runs.
- [ ] The explicit Vite input map includes `resume.html`, and a production build
      emits `examples/web/dist/resume.html`.
- [ ] Assistant claims, tool evidence, and human-accepted anchors are visibly
      distinct.
- [ ] Every Resume item exposes a source reference.
- [ ] Compaction leaves covered activity available and labels its summary as a
      summary.
- [ ] Multiple terminal branches require an explicit selection and never merge
      silently.
- [ ] Keyboard and screen-reader users can import, choose a branch, switch views,
      inspect sources, and forget imported state on equivalent terms.

### Explicit import

- [ ] A person can select a current pi session snapshot and render it without
      entering the same prompt again.
- [ ] No imported session content is written to browser persistence in the
      first slice.
- [ ] Thinking blocks, images, raw provider metadata, system/context material,
      unknown custom messages, and full tool-result bodies do not enter the
      normalized Canopy activity model.
- [ ] Raw user and assistant text stays outside the normalized model by default;
      only explicitly selected bounded excerpts that pass the fail-closed
      content check enter the in-memory view.
- [ ] Import diagnostics state what was omitted and why.
- [ ] Reloading or using `Forget imported session` clears the Canopy copy while
      leaving the independently owned pi session unchanged.

### Falsifiable product test

For a transcript the evaluator has not seen, the predeclared Resume condition
passes only if the evaluator can, within five minutes:

1. state the primary task;
2. identify at least one verified outcome without treating assistant prose as
   verification;
3. identify the unresolved question or next step; and
4. open the source evidence for each answer.

The same questions are attempted with the chronological fallback. Record both
correctness and time. Passing the five-minute bound alone does not establish
product value: the Resume View must improve correctness, time, or both without
reducing source traceability. This is a pilot result, not a statistical claim.

### Gated extension

- [ ] The extension is not started until the fixed-view product test passes.
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

If the web page changes visually, run the browser prototype and inspect it with
human feedback before treating Playwright as sufficient evidence.

## Risks

- **Imported-content sensitivity.** A pi session may contain secrets in ordinary
  user text or tool output. Explicit file selection does not make the content
  safe. Metadata-first normalization, explicit bounded excerpt selection, and
  fail-closed checks minimize the additional Canopy projection, but false
  negatives remain possible and the source session remains sensitive and
  independently retained by pi.
- **False checkpoint authority.** A fluent assistant summary can look like a
  decision. The fixed slice accepts only explicit human-authored or accepted
  anchors.
- **Branch ambiguity.** A JSONL file can contain several terminal paths, while a
  fork is a separate child session. Conflating the two would produce a false
  history.
- **Format coupling.** The decoder targets pi session v3. A new pi format must
  fail closed until its migration or compatibility contract is reviewed.
- **Premature abstraction.** Extracting a MoonBit activity framework before the
  Resume interaction stabilizes would turn product uncertainty into public API
  debt.
- **Surveillance drift.** Failure of the fixed view is not evidence that more
  passive capture is needed. Every wider source requires a named missing signal
  and a new privacy review.

## Notes

- Pi owns its session even after import. Canopy owns only the bounded imported
  projection and any later curated memory. Deleting one copy does not imply
  deletion of the other.
- `lib/cognition` may later index accepted activity-derived context, but it does
  not become the raw activity ledger.
- Generated or adaptive Resume instruments remain disposable projections and
  are considered only after the deterministic view beats the chronological
  alternative.
