# Validated diagnostic text replacements

Status: implemented in Loom PR #804 and squash-merged as
`778965a4c7d015be39a968966863a259330dc36c` on 2026-07-31. The Canopy parent
change records that published submodule commit and closes issue #1037. This
plan is limited to Loom diagnostic core values, validation, and pure in-memory
source transformation. Editor/protocol adaptation belongs to #1038.

## Scope

Extend Loom's existing `Diagnostic` model with neutral, named fix candidates.
Do not introduce a second diagnostic, source, range, edit-transaction, or
revision model. A candidate contains one or more source-qualified text
replacements and can be applied to an explicitly identified in-memory source.

Diagnostics remain outside `AnalysisProjection`. Producers retain lifecycle,
snapshot/revision, invalidation, and authoritative-evidence ownership. Fixes do
not contain source text, Canopy revisions, parser/CST/token/entity evidence,
`IdentityTransform`, `SyncEditor`, or protocol actions.

## Existing API First

### Reused project APIs

- `SourceId` remains the opaque source-file identity. `DiagnosticSource`
  remains producer identity and is never accepted as a fix source.
- `SourceSpan` remains the only source-qualified span and `TextRange` remains
  the validated, ordered, half-open UTF-16 code-unit range.
- `Diagnostic` remains the owning diagnostic model. Its constructor and new
  `fixes()` accessor preserve the existing defensive-copy boundary.
- Existing source-backed validation uses `String::length` for bounds and
  `String::get_view` to reject endpoints inside a surrogate pair.

### Reused MoonBit core APIs

- `Array::copy` owns constructor input and accessor output.
- `Array::sort_by` normalizes replacements by ascending start offset.
- `Array::fold` over a reversed normalized copy performs application from the
  end of the source toward the beginning.
- `String::length` and `String::get_view` validate the supplied source before
  any replacement is applied.
- `Option` continues to model optional diagnostic fields. A typed raised error
  reports expected construction/application failures.

### Checked but not selected

- `Map` and `Set` are unnecessary: every candidate is single-source, sorting is
  required, and adjacent comparisons validate all conflicts deterministically.
- `ArrayView` and `Iter` do not fit the public ownership boundary because stored
  edit/fix arrays must be defensively owned and returned as defensive copies.
- `StringBuilder` naturally builds forward, while the issue explicitly
  requires replacements to be applied in reverse source order. It is not used
  to obscure that observable algorithm.
- Generic `cmp` helpers add no policy beyond comparing existing `TextOffset`
  values. The normalized comparator uses their established order.
- Canopy `SpanEdit`, parser `Edit`, `IdentityTransform`, editor transactions,
  and `SyncEditor` lack source identity, replacement text, private validation,
  or the correct dependency direction.
- Renderer-only validation helpers are private to rendering and bind renderer
  error semantics. Fix application reuses the same core primitives at its own
  typed boundary rather than coupling the two public operations.

### New responsibility boundaries

- `TextReplacement` privately owns one `SourceSpan` and replacement `String`.
- `DiagnosticFix` privately owns a nonempty, normalized array of replacements,
  plus its title and applicability. Its named constructor enforces every
  source-independent invariant before a value exists.
- `DiagnosticFixError` reports structural or source-snapshot validation
  failures. It does not infer source identity or revision from diagnostic
  presentation data.
- `DiagnosticFix::apply` is a deterministic pure transformation over an
  explicit `SourceId` and `String`; it validates the entire edit set against
  that snapshot before producing output.

## Approved invariants

### Identity and ownership

All replacements in one candidate have exactly equal `SourceId` values. A
candidate with zero replacements or multiple source IDs is rejected. Equal
source names or text are irrelevant. `DiagnosticSource` is never converted to
or compared with `SourceId`.

The `TextReplacement`, `DiagnosticFix`, and `Diagnostic` fields are private.
Named constructors are the only public construction path. Constructor arrays
are copied before normalization; `edits()` and `fixes()` return owning copies.
Mutating caller input or accessor output cannot mutate stored values.

### Normalization and conflict policy

Replacements are normalized by ascending `TextRange.start`. Valid sets then
have an unambiguous order:

- two nonempty half-open ranges may touch (`previous.end == next.start`) but
  must not overlap;
- an insertion point may equal the previous nonempty range's exclusive end;
- an insertion at a nonempty range's start or strictly inside it is rejected;
- multiple insertions at the same offset are rejected;
- any other equal-start pair is invalid, so no secondary ordering key or
  unstable-sort behavior becomes observable.

These rules extend ordinary half-open overlap semantics only where a
zero-width edit would otherwise create ambiguous replacement ordering.

### Snapshot validation and application

`DiagnosticFix::apply(source_id, source)` first requires the supplied ID to
equal the candidate's source. It then validates every normalized span against
the untouched input snapshot, in normalized order:

1. `end <= source.length()`;
2. `String::get_view(start_offset=start, end_offset=end)` succeeds, proving
   both endpoints are valid UTF-16 boundaries.

No transformation occurs until all replacements pass. Application then folds
the normalized edits in reverse order, replacing each half-open range with its
replacement string. Insertion is `start == end`, replacement has a nonempty
range and nonempty text, and deletion has a nonempty range and empty text.

Offsets remain UTF-16 code-unit offsets. Source text is supplied by the caller
and is never stored in a diagnostic or fix. The operation has no filesystem,
network, editor, parser, clock, random, revision, or mutable-session access.

### Diagnostic integration and revision policy

One diagnostic can own multiple candidates in caller order. Candidates remain
distinct even when their titles or edits happen to match. Selecting/applying
one candidate has no effect on any other candidate.

Fix ranges are snapshot-bound evidence. Existing diagnostic shift/drop/replay
transforms do not remap them. Transform reconstruction preserves fix values
byte-for-byte, while the host remains responsible for rejecting every fix after
any source revision change. Parser diagnostic identity includes fixes so replay
deduplication cannot silently retain an older candidate set.

Compact formatting and the source-backed renderer remain unchanged: neither
renders nor applies fixes in #1037.

## Behavioral boundary matrix

| Case | Required observation |
| --- | --- |
| Empty edit list | Constructor rejects |
| Insertion / replacement / deletion | Each applies with half-open UTF-16 semantics |
| Out-of-order edits | Constructor returns ascending normalized edits |
| Multiple non-overlapping edits | Reverse application produces the expected source |
| Touching nonempty edits | Accepted |
| Duplicate insertion point | Rejected |
| Insertion at range start/interior | Rejected as ambiguous |
| Insertion at range end | Accepted as a half-open touching boundary |
| Overlapping nonempty ranges | Rejected |
| Multiple sources | Constructor rejects before application |
| Wrong application source ID | Apply rejects before output |
| Endpoint past source length | Apply rejects before output |
| Surrogate-interior endpoint | Apply rejects before output |
| Valid emoji boundaries | Accepted as UTF-16 code-unit offsets |
| Constructor input mutation | Stored edits unchanged |
| Accessor output mutation | Stored edits/fixes unchanged |
| Multiple candidates | Order and distinct values preserved; one applies independently |
| Diagnostic transform | Labels/token follow current policy; fixes remain unchanged |
| Parser deduplication | Different fix sets remain different logical diagnostics |

## Tests-first sequence

1. Add focused Loom core tests for construction, normalization, conflict cases,
   source mismatch, UTF-16/bounds validation, application, multiple candidates,
   diagnostic integration, and defensive copies. Confirm failure because the
   API does not yet exist.
2. Add deterministic generated cases comparing normalized reverse application
   with a simple reference splice sequence.
3. Implement the smallest private-field values, typed error boundary, accessors,
   structural validation, and pure application needed by those tests.
4. Add `Diagnostic.fixes`, preserve fixes through diagnostic reconstruction,
   and include fixes in parser replay identity without changing presentation.
5. Re-export only the neutral public values through the Loom facade.
6. Run focused default/JavaScript/native release tests, then full Loom checks,
   formatting, interface generation, `.mbti` review, and a concrete multi-edit
   UTF-16 smoke scenario.

## Compatibility cutover

The `Diagnostic` constructor gains an optional `fixes=[]` argument, so existing
callers keep their behavior. No obsolete fix API exists to retain or shim.
Current Canopy protocol/editor/CodeMirror callers remain unchanged and do not
receive fixes in #1037.

The Loom PR must merge before Canopy records its commit. The Canopy PR may point
only to the published Loom merge commit and closes #1037 after the parent CI and
merge gates pass. #1038 begins only after that closure and cleanup.
