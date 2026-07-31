# Lambda diagnostic fix through the editor protocol

Status: approved design contract for issue #1038. Implementation and merge
evidence will be appended only after the exact reviewed commits pass their
gates.

## Scope

Complete one vertical slice for Lambda input `if x then y`:

```text
Lambda parser diagnostic and fix
  -> Loom source-backed plain rendering
  -> Canopy revision-bound diagnostic snapshot
  -> producer-neutral SetDiagnostics metadata
  -> CodeMirror lint action
  -> typed ApplyDiagnosticFix intent
  -> current-snapshot validation
  -> CRDT/undo mutation and one parser synchronization
  -> cleared missing-else diagnostic
```

This issue does not add semantic diagnostics, generic fix extraction, or a
second diagnostic model. Diagnostics remain outside `AnalysisProjection`.
Loom retains parser diagnostic lifecycle and authoritative evidence; Canopy
owns only the editor publication snapshot and application registry. Source
text remains external to diagnostics and fixes.

## Existing API First

### Reused project APIs

- Loom `SourceId`, `SourceSpan`, `TextRange`, and `TextOffset` remain the only
  source and half-open UTF-16 location model. `DiagnosticSource` remains
  producer identity and is never used as source identity.
- Loom `Diagnostic`, `DiagnosticLabel`, `DiagnosticCode`, `DiagnosticFix`,
  `TextReplacement`, and `FixApplicability` remain the producer-native model.
  No Canopy replacement or fix value duplicates them.
- `DiagnosticFix::apply(source_id, source)` revalidates source identity, bounds,
  UTF-16 boundaries, normalized ordering, and non-overlap against the untouched
  source before the imperative editor shell mutates anything.
- `Diagnostic::render_plain(SourceProvider)` supplies the displayed message.
  The current editor source is supplied atomically as a
  `DiagnosticSourceFile`; source text is not stored in a diagnostic snapshot.
- `ViewUpdateState` already owns per-handle publication state and is therefore
  the owner of the current diagnostic snapshot. The registry is not placed in
  `AnalysisProjection`, a parser, a protocol DTO, or a global map.
- `SyncEditor::get_version()` returns an owning `@text.Version` value derived
  from the CRDT operation set. Equality exactly detects whether the editor is
  still at the registered operation snapshot. The value stays inside Canopy
  and is never encoded on the wire.
- `SyncEditor`'s existing CRDT/undo splice boundary is reused for commit.
  Existing peer-cursor and parser synchronization functions run once after all
  validated replacements have been committed.
- `UndoManager`'s existing time-window grouping remains the mechanism that
  combines the replacement operations themselves. The currently exposed API
  has no non-destructive way to separate that batch from adjacent user input,
  so event-graph-walker receives one additive `stop_capturing()` boundary.
- The existing `UserIntent` enum remains the sole inbound protocol and the
  existing adapter intent callback remains the sole CM6 action exit.

### Reused MoonBit core APIs

- `Array` preserves producer, label, diagnostic, and fix order. Constructor and
  accessor copies from Loom remain the defensive ownership boundary.
- `Array::mapi`, `filter_map`, `search_by`, and reverse traversal express
  snapshot-local ID assignment, lookup, and end-to-start commit.
- `Option` models optional wire metadata and the absence of a current snapshot.
  `Result`/typed catches remain at JSON, renderer, and Loom fix validation
  boundaries.
- `String::length` and `String::get_view` remain the canonical UTF-16 bounds and
  surrogate-boundary checks through Loom's fix application.

### Checked but not selected

- `Map` and `Set` are unnecessary. IDs are snapshot-local array positions, the
  expected counts are small, and array lookup preserves explicit ordering.
- `ArrayView` and `Iter` do not improve registry ownership because registered
  fixes must outlive the projection call and Loom accessors already return
  defensive owning copies.
- `StringBuilder` is owned by the plain renderer; the registry does not format
  diagnostic text itself.
- `cmp`, new overlap helpers, and new sorting helpers are unnecessary because
  `DiagnosticFix` already normalizes and validates replacements.
- `@incr.Revision`, parser tokens, CST nodes, entity IDs, diagnostic messages,
  source names, and list positions are not revision or location identities.
- `SyncEditor::apply_span_edits` is not the final commit boundary because it
  synchronizes the parser after every edit. `apply_text_edit_exact` is also not
  reused directly because its public policy requires grapheme boundaries,
  while diagnostic replacements are defined on valid UTF-16 boundaries.
- `SyncEditor::set_text` is not used for fixes: it does not record undo and can
  replace untouched CRDT content inside the combined span.
- `UndoManager::clear()` is not a capture boundary because it destroys prior
  undo and redo history. Toggling `set_tracking(false)` is also unsuitable
  because it would omit the diagnostic fix from undo history altogether.

### New responsibility boundaries

- Three opaque protocol IDs identify a publication snapshot, one underlying
  diagnostic within that snapshot, and one candidate within that diagnostic.
  Their wire representation is an integer token; consumers may only echo it.
- Private snapshot state inside `ViewUpdateState` owns its ID, source ID, CRDT
  version, and registered diagnostic/fix entries. It stores Loom fix values but
  no source text and exposes no mutable collection. Its representation uses
  only public component types because MoonBit forbids a public struct's private
  field from depending on a private type; no registry representation is added
  to the public API.
- A deterministic snapshot builder renders protocol rows and registers only
  fixes whose source equals the current editor source.
- One editor-private commit helper applies an already revalidated Loom fix
  from end to start through CRDT/undo, then synchronizes peer cursors and the
  parser exactly once. It does not perform publication or protocol work.
- event-graph-walker's `UndoManager::stop_capturing()` marks only the next
  recorded operation as the start of a new group. It neither clears history
  nor disables tracking. Calling it before and after the replacement batch
  isolates the batch on both sides while preserving normal time grouping for
  every replacement inside the batch.

## Approved invariants

### Parser diagnostic and help

Only the missing-`else` recovery point receives stable code
`loom.lambda.expected_else`. The diagnostic has one zero-width primary label at
EOF, a help note explaining that an `if` expression requires an else branch,
and one `Always` candidate titled for inserting the missing branch.

The existing ordered `Diagnostic.notes` channel is the help channel for this
slice. Adding a second structured help model would exceed #1038 and would not
be rendered by the already-merged #1036 contract. The note is rendered as
`= note: ...` by the existing source-backed renderer.

The first failing parser test obtains the candidate from the diagnostic,
applies it with `DiagnosticFix::apply`, and reparses the exact output. That test
defines the replacement only when the real Lambda grammar accepts it and the
`loom.lambda.expected_else` diagnostic disappears. No implementation or plan
text alone establishes the replacement.

### Snapshot identity and lifetime

Snapshot IDs are monotonically allocated within one `ViewUpdateState` lifetime.
Diagnostic IDs are the underlying `DiagnosticSet` encounter indices. When one
Loom diagnostic projects to multiple current-source primary rows, every row
echoes the same diagnostic ID. Fix IDs are candidate encounter indices within
that diagnostic. They are opaque tokens, not stable cross-snapshot identities.

Every publication of nonempty diagnostics creates and installs a new snapshot,
even when its values compare equal to the previous publication. Publishing an
empty diagnostic set clears the registry. A source edit may leave the old
registry object present until the next view update, but version mismatch makes
all its actions immediately invalid.

The stored `@text.Version` is compared only for equality with the current
editor version. Any local, remote, undo, redo, or causally visible operation
invalidates the action, including a conservative invalidation whose visible
text happens to compare equal. `@incr.Revision` is neither stored nor exposed.

### Source and rendering

The snapshot source ID must equal `SyncEditor::parser_source_id()`. A fix is
registered only when its first replacement source equals that ID; Loom's
constructor guarantees the rest of the candidate has the same source. Foreign
source candidates are not sent to the frontend.

For parser diagnostics, the message sent to the editor is the #1036 plain
rendering over the exact current source, using the stable provider name
`<input>`. The renderer remains atomic and strictly validates every label. For
compatibility, a diagnostic that cannot be rendered because it references a
source outside this single-document provider keeps its neutral message and has
no registered actions. Location is still taken only from explicit current
source primary labels; it is never inferred from text, code, order, or token
evidence.

Offsets remain half-open UTF-16 code-unit offsets. Zero-width EOF labels remain
`from == to == source.length()`.

### Protocol compatibility

The existing diagnostic DTO gains nullable `snapshot_id` and `diagnostic_id`
plus an ordered `fixes` array. Each summary contains only opaque ID, title, and
producer-neutral applicability. Replacement text, source text, CRDT version,
Loom token/CST/entity evidence, and parser-native types are absent.

Existing diagnostic constructors default the new fields to no IDs and no
fixes. Existing adapters may ignore them. JSON always emits the fields so the
wire shape is deterministic; legacy TypeScript producers may omit them and the
CM6 adapter treats omission as no action.

`UserIntent::ApplyDiagnosticFix(snapshot_id, diagnostic_id, fix_id)` is a
dedicated typed variant. JSON decoding requires all three integer fields and
rejects missing, wrong-typed, or negative values. No replacement, range,
source, or structural-operation string is accepted inbound.

### Action and application

CM6 creates an action only when a diagnostic has both IDs and a fix summary.
The action title is the fix title. Its callback ignores CM6's current `from`
and `to` values and invokes the existing intent callback with the three captured
IDs. It never dispatches a document change.

After MoonBit accepts and commits the intent, the host reads the authoritative
source and applies that result through `TextChange`, then applies the newly
computed diagnostic patches. The browser integration uses the real Lambda FFI
artifact, so the action itself still cannot bypass CRDT, undo, or revalidation.

MoonBit accepts an action only when all of these hold in order:

1. a current registry exists;
2. the snapshot ID equals the current registry ID;
3. the stored CRDT version equals `SyncEditor::get_version()`;
4. the stored and current parser source IDs are equal;
5. the diagnostic ID exists;
6. the fix ID exists under that diagnostic;
7. `DiagnosticFix::apply` succeeds against the current source ID and text.

Any failure returns rejection without mutation. The frontend-supplied action
contains no content that can influence the replacement.

After successful pure validation, the imperative shell records all replacement
operations in one undo group, committing them from end to start. It calls
`stop_capturing()` immediately before the first operation and immediately after
the last operation. Thus an ordinary edit inside the capture timeout before or
after the fix is a distinct undo step, while every operation in a multi-edit
fix remains one step. Because all ranges were validated against the untouched
source and later offsets are committed first, each original offset remains
valid. Peer cursors and the parser observe only the final source. The current
registry is cleared on success, so replaying the action rejects before the next
publication as well as after it.

## Behavioral boundary matrix

| Case | Required observation |
| --- | --- |
| Lambda `if x then y` | EOF primary label, stable code, help note, one named fix |
| Candidate replacement | Applying it yields grammar-valid exact source and clears missing-else code |
| Plain rendering | Published message contains header, `<input>` source block, EOF marker, and help note |
| Metadata JSON | Nullable IDs and ordered fix summaries encode deterministically |
| Typed intent JSON | Three IDs round-trip; missing/wrong/negative fields reject |
| Current snapshot | Selected fix applies through CRDT/undo and parser |
| Stale snapshot ID | Rejects without source mutation |
| Stale CRDT version | Rejects without source mutation |
| Unknown diagnostic/fix ID | Rejects without source mutation |
| Two candidates | Only the selected candidate is resolved and applied |
| Multiple replacements | Final source is exact; parser exposes no intermediate state |
| Undo capture boundary | Prior input, the whole fix batch, and subsequent input are three undo steps even inside the capture timeout |
| Source mismatch | Candidate is not registered or application rejects |
| Bounds/UTF-16/non-overlap | Loom revalidation rejects before mutation |
| Replay | A successfully used action rejects immediately |
| CM6 zero-width diagnostic | Point marker exposes action; click emits IDs only |
| Existing non-fix diagnostic | Renders as before and has no CM6 action |
| Defensive ownership | Mutating caller/accessor arrays cannot alter registered fixes |

## Tests-first and publication sequence

1. In event-graph-walker, first add a failing undo-manager test in which prior
   input, a multi-operation fix batch, and subsequent input all occur inside
   the capture timeout. Add `stop_capturing()` so undo observes three groups,
   with the entire fix batch in the middle group. Validate and independently
   review it, then push, open its PR, wait for required CI, and squash merge.
2. In Loom, add the missing-else parser test first. It must fail before the
   diagnostic carries the stable code/help/fix, then prove the candidate output
   reparses cleanly.
3. Implement only the Lambda producer using existing Loom diagnostic values and
   `ParserContext::report`; no Loom core API is added unless the test proves the
   existing public context accessors are insufficient.
4. Validate and independently review Loom, push its branch, open the Loom PR,
   wait for required CI, squash merge, and record the public merge commit.
5. Update the Canopy worktree's event-graph-walker and Loom pointers only to
   their public merge commits.
6. Add failing protocol JSON tests, snapshot/application tests, Lambda FFI
   round-trip tests, and CM6 action/E2E tests before their corresponding
   implementations.
7. Implement the protocol IDs/metadata/intent, snapshot registry, atomic editor
   commit shell, Lambda FFI intent endpoint, and adapter action in narrow
   red-green slices.
8. Run affected default/JS/native release tests, workspace check/test, JS build,
   TypeScript checks, and the CM6 Playwright test. Inspect every generated
   `.mbti` change and execute concrete current/stale/multi-edit scenarios.
9. Obtain independent implementation review, resolve findings, refresh from
   `origin/main`, run the exact-head PR validator, then create and merge the
   Canopy PR only after raw required CI and mergeability gates pass.

## Compatibility and ownership cutover

The Loom parser diagnostic changes producer output additively. The Canopy
diagnostic DTO and `UserIntent` change additively; there is no obsolete fix API
or compatibility shim. Existing non-fix producers keep constructor defaults.
The TypeScript adapter accepts old diagnostic objects without metadata.

The event-graph-walker and Loom PRs must merge first. The Canopy parent PR may
reference only their public squash merge commits. Issue #1039 does not begin
until #1038's Canopy PR is merged, the issue is closed, and all #1038
branches/worktrees are cleaned.
