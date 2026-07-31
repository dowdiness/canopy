# Source-backed plain-text diagnostic renderer

Status: implemented for issue #1036 on 2026-07-31 in Loom PR #796, squash
merge `b6018964340180047f52ba9b54556b06c3fdfc73`. The observable output
grammar and atomic failure contract below are the verified implementation
target.

## Scope

Add one source-backed plain-text renderer to Loom core after the source-aware
diagnostic model from #1035. The renderer consumes neutral diagnostics plus an
external source snapshot capability. It does not put source text in
`Diagnostic`, change producer ownership, expose parser evidence, migrate the
legacy compact formatter, or begin fixes from #1037.

Diagnostics remain outside `AnalysisProjection`. The producer continues to own
diagnostic lifecycle, revision, invalidation, and authoritative evidence. The
renderer is a deterministic presentation function over an explicit diagnostic
snapshot and explicit source snapshots.

## Existing API First

### Reused project APIs

- `TextOffset` and `TextRange` retain nonnegative, ordered, half-open UTF-16
  offsets. They do not validate against source text.
- `SourceId`, `SourceSpan`, `LabelStyle`, and `DiagnosticLabel` remain the only
  source-location model. No second diagnostic or span model is introduced.
- `LineIndex` remains the canonical LF, CRLF, and CR mapping from UTF-16 offsets
  to zero-based line/column values. Its clamping lookup is used only after
  renderer-boundary validation.
- `Diagnostic` and `DiagnosticSet` accessors preserve their defensive-copy
  boundaries. The legacy `format()` and `format_with_line_col()` methods remain
  compatibility paths and are not used as input to the new renderer.

### Reused MoonBit core APIs

- `String::length` supplies the UTF-16 source length.
- `String::get_view` validates bounds and rejects endpoints inside a surrogate
  pair without aborting. Valid views also avoid a source-slice copy.
- `StringBuilder` builds the final text. Rendering does not concatenate strings
  in a loop.
- `Array` traversal preserves diagnostic and label order. `Option` represents a
  missing provider resolution. A typed raised error reports invalid rendering
  input at the public boundary.

### Checked but not selected

- `Buffer` is byte-oriented and adds an encoding concern that a String result
  does not need.
- `Map` can group `SourceId` values, but grouping can be expressed with a small
  ordered Array because the contract preserves first occurrence and the
  expected label count is small. A Map must not become the source of output
  ordering.
- `Set` is unnecessary because labels are neither deduplicated nor reordered.
- `ArrayView` and `Iter` do not improve the external boundary: existing
  diagnostic accessors intentionally return owning defensive copies.
- sorting, `cmp`, overlap merging, and marker stacking are unnecessary when
  each label has its own deterministic subsection.
- Canopy `SourceSnapshot`, parser/CST/token APIs, graph-specific spans, editor
  protocol types, and `DiagnosticSource` have different responsibility or
  dependency direction and are not reused as source identity/provider state.
- `DiagnosticBuildError` remains responsible for source-independent diagnostic
  construction invariants. Rendering failures use a separate error boundary.

### New responsibility boundaries

- A source snapshot value binds one provider-owned source name, immutable source
  text, and provider-supplied `LineIndex` in one atomic resolution. Its fields
  are private. The renderer boundary verifies that the supplied index equals an
  index derived from exactly that text before using either value.
- A source provider is a private-field callback capability that resolves one
  complete snapshot for a `SourceId`. A render resolves each referenced ID once
  and never combines independently read name/text/index revisions.
- A render error reports missing source, source bounds, or invalid UTF-16
  boundary. It does not extend diagnostic construction errors or infer a
  location from prose, ordering, names, or token evidence.
- Package-private rendering helpers validate/group/render already-modelled
  data. They do not become a second public model.

## Invariants

### Source snapshot and identity

`SourceId` equality is the only grouping key. Equal name or equal text does not
merge distinct IDs. `DiagnosticSource` remains producer identity and is never
used for source lookup or grouping.

For each referenced `SourceId`, a render obtains at most one immutable snapshot.
One provider call returns the name, text, and index together; there are no three
independent lookups that can observe different revisions. The renderer rejects
a snapshot whose supplied index does not match `LineIndex::new(text)`. It has no
clock, filesystem, network, parser, editor, or mutable session access.

Locationless diagnostics do not consult the provider.

### Strict span validation

Construction continues to permit any ordered nonnegative `TextRange`, including
zero-width ranges. The renderer validates every labelled range before emitting
text:

1. the provider resolves the label's `SourceId`;
2. the provider-supplied index matches an index derived from the resolved text;
3. `start <= end <= source.length()`;
4. `String::get_view(start_offset=start, end_offset=end)` succeeds, proving that
   neither endpoint is inside a surrogate pair;
5. only then may the existing clamping `LineIndex` convert the endpoints.

Failure identifies the offending source/span and emits no partial rendering.
Combining marks are ordinary UTF-16 code units and are not grapheme-normalized.

### Stable ordering and copies

Diagnostics retain `DiagnosticSet` order. Within one diagnostic, source groups
use first label occurrence order and labels within a group retain their original
order. Multiple primary labels remain multiple primary labels. Notes retain
their stored order. No sorting, overlap merge, or deduplication is performed.

Provider values and temporary grouping arrays are render-local. Existing
diagnostic arrays are read through defensive-copy accessors, and no new public
accessor exposes a mutable Array.

### UTF-16 and line endings

Canonical spans remain half-open UTF-16 code-unit offsets. `LineIndex` continues
to recognize LF, CRLF, and CR. Displayed columns count UTF-16 code units rather
than bytes, scalar values, grapheme clusters, tabs, or terminal cells. The
renderer does not promise terminal-cell alignment for emoji, combining marks,
or tabs.

The inverse line/column operation used by the renderer and round-trip properties
is package-private and source-aware. After computing a candidate offset from a
line start and column, it requires both forward round-trip equality and
`String::get_view(start_offset=candidate, end_offset=candidate)` success. Thus a
coordinate inside a surrogate pair is outside the inverse domain even though
the existing forward `LineIndex::line_col` can map that raw code-unit offset.
Existing clamping APIs keep their behavior.

## Approved observable output contract

This contract supplies the snapshot-stable grammar that issue #1036 leaves open.

Each diagnostic uses this sectioned form:

```text
error[E123]: diagnostic message
--> src/main.mbt
primary 2:5-2:8: expected expression
  2 | let x = foo
    |     ^^^
secondary 4:1-4:4: declared here
  4 | foo
    | ---
= note: additional context
```

- The header is lowercase severity, optional `[code]`, a colon, one space, then
  the diagnostic message. Producer identity is omitted.
- User-facing lines and columns are one-based; the underlying `LineIndex`
  remains zero-based. The displayed column unit remains UTF-16.
- A source group begins with `-->`, followed by one space and its
  provider-supplied name.
- Each label has its own subsection. It starts with `primary` or `secondary`,
  its half-open start/end positions, and an optional `: label message`.
- Primary source markers use `^`; secondary markers use `-`.
- A zero-width label, including EOF, emits exactly one marker at its insertion
  column.
- A nonempty label renders every logical line it intersects; there is no
  clipping or ellipsis in the MVP. If the exclusive end is column zero of a
  later line, that end line is not included. A line-terminator-only intersection
  emits one marker at its UTF-16 position on the preceding logical line.
- Source lines omit their line terminators. Marker offsets still use the
  existing UTF-16 column, including positions within CRLF.
- Notes follow all source groups as `= note: ...`, in stored order.
- A locationless diagnostic consists of its header and notes only.
- Diagnostics in a set are separated by one empty line; an empty set renders an
  empty String.

No color, ANSI escape, terminal-width clipping, tab expansion, Unicode visual
width, source-name guessing, help field, or presentation-specific attachment is
part of this contract.

## Failure contract

Rendering is atomic. It first resolves and validates every labelled span, then
renders. One missing source, out-of-bounds endpoint, or surrogate-interior
endpoint raises a typed render error and produces no partial String. Errors are
reported in diagnostic/label encounter order. The MVP reports the first error;
it does not aggregate failures.

The provider capability resolves a complete source snapshot, not three
independent lookups, so the renderer cannot mix source name, text, and index from
different revisions. The snapshot carries the provider-owned `LineIndex`; the
renderer rejects it with a typed source-index-mismatch error unless it equals
`LineIndex::new(text)`.

## Behavioral boundary matrix

| Case | Required observation |
| --- | --- |
| Locationless diagnostic | Header and ordered notes; provider is not called |
| Empty source, `0..0` | Valid one-marker primary/secondary subsection |
| EOF point | Valid one-marker subsection at `source.length()` |
| Single-line span | Exact half-open coordinates, source line, style marker, label message |
| Multiline span | Every intersected logical line; later `end = line:0` line excluded |
| Primary plus secondary | Both styles/messages survive in label order |
| Multiple primary labels | Every primary renders; no first-primary inference |
| Multiple sources | Groups keyed by ID in first-occurrence order |
| Equal names/text, different IDs | Separate source groups |
| LF / CRLF / CR | Existing `LineIndex` positions and stable source-line extraction |
| Emoji | Valid pair spans render with two UTF-16 columns |
| Surrogate-interior endpoint | Typed failure before output |
| Combining mark | Counted as its own UTF-16 code unit |
| Notes | Render after all source groups, in stored order |
| Missing source | Typed whole-render failure |
| Endpoint past source length | Typed whole-render failure, never clamped |
| DiagnosticSet | Stable diagnostic order and one empty-line separator |
| Defensive copies | Mutating returned arrays cannot affect later rendering |
| Provider snapshot | One atomic name/text/index resolution per referenced ID per render |
| Mismatched source index | Typed whole-render failure before any span conversion |

## Tests-first sequence

1. Add focused renderer snapshot tests for the boundary matrix and confirm they
   fail because the API does not exist.
2. Add strict offset/line-column property tests over offsets whose zero-width
   `String::get_view` succeeds, including monotonic forward conversion. The
   source-aware private inverse must round-trip those offsets and reject every
   surrogate-interior coordinate.
3. Implement the smallest private-field snapshot/provider/error types and the
   deterministic renderer needed by those tests.
4. Re-export only the public construction and rendering boundary through the
   Loom facade; keep helpers package-private.
5. Run core checks and release tests on default, JS, and native targets, then
   full Loom validation, formatting, interface generation, and `.mbti` review.
6. Run a concrete two-source smoke scenario proving primary/secondary ordering,
   UTF-16 positions, provider resolution count, and atomic invalid-range failure.

## Caller compatibility

The new renderer is additive. Current Loom/Canopy callers of `format()` and
`format_with_line_col()` remain on the compact compatibility path. No Canopy
editor/protocol/CodeMirror migration is required for #1036. The Canopy PR first
records the merged Loom commit and then validates that pointer from the full
workspace.

The Loom PR must merge before Canopy references it. The parent PR may contain
only a published Loom merge commit, this plan, and issue handoff material. It
must close #1036 only after Loom and Canopy CI/merge gates pass.

## Implementation evidence

- Loom core release tests passed 363/363 on the default, JavaScript, and native
  targets; the full Loom release suite passed 3647/3647.
- Full Loom check, formatter, interface drift, dependency-boundary,
  documentation, performance-guard, and README quick-start gates passed.
- Generated interfaces add only the source snapshot/provider/error boundary and
  the two plain rendering methods; no existing trait bound or visibility
  changed.
- Independent implementation review used `gpt-5.6-terra`. It passed after one
  trailing-whitespace snapshot finding was fixed and independently closed.
- A later CodeRabbit finding identified repeated full-source indexing for every
  rendered line. An isolated release probe measured 201.71 microseconds at 128
  lines and 12.70 milliseconds at 1024 lines. The validated-source fast path
  reduced those measurements to 3.28 and 36.46 microseconds respectively;
  `gpt-5.6-terra` independently re-reviewed the boundary change and passed it.
- The existing Loom structured-diagnostics ADR now records the provider-owned
  snapshot, source-text non-ownership, strict rejection, stable ordering, and
  producer/source identity principles without a concrete API inventory.
