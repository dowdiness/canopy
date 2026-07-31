# Source-aware Loom diagnostics

Status: Design reviewed; Canopy projection approved by the user on 2026-07-31

Canonical issue: [#1035](https://github.com/dowdiness/canopy/issues/1035)

## Goal

Replace Loom's source-less primary range and unstyled related ranges with one
neutral label model whose locations remain correct when a diagnostic relates to
more than one source. Preserve the existing parser-owned diagnostic lifecycle,
UTF-16 offset convention, and Canopy protocol boundary.

This plan does not add source text, fixes, a renderer, semantic diagnostics, or
an analysis-projection diagnostic fact. Those remain sequenced through #1036,
#1037, #1038, and #1039.

## Current boundary

Loom currently validates non-negative `TextOffset` values and half-open
`TextRange` values, but `Diagnostic.primary`, `DiagnosticLabel.range`, and
token evidence have no source identity. All offset/relex transforms therefore
treat every range as if it belonged to the edited source. Parser replay and its
logical deduplication key likewise compare numeric ranges without a source.

Canopy's current editor projection has a narrower contract: one source-less
`from`/`to` range per protocol diagnostic. It consumes only parser diagnostics,
and the normal parser producer currently supplies zero or one primary range.
The protocol deliberately contains no Loom token, CST, entity, or parser
evidence.

## Model and invariants

### Source identity

`SourceId` is an opaque string key with exact value equality and hashing. It is
not a `DiagnosticSource`: producer identity and source identity remain distinct
types and fields. The value is neither normalized nor derived from a diagnostic
message, producer name, label order, or presentation artifact.

The proposed identity scope is a diagnostic/source-provider snapshot rather
than a globally unique file registry. A caller must keep one key stable for the
same logical source throughout construction, shifting, replay, and rendering.
Different keys are always different sources even when their text or numeric
ranges are equal. A parser stores an explicit source ID for its current source;
the generic model does not store source text.

The ID is passed explicitly through the complete parser ownership chain. The
public high-level parser factories, low-level `Parser`/`SyntaxParser` and
`ImperativeParser` constructors, parser entry points and contexts, standalone
`TokenBuffer` constructors, and block-reparse entry point all receive a
`SourceId`; no source-less overload remains. `ImperativeParser` owns the ID for
the lifetime of one logical source and supplies it to full and incremental
language callbacks. `TokenBuffer` stores the same ID and uses it whenever it
qualifies relex damage. Standalone `LexResult` adapters that create ranged
diagnostics also require the caller's ID. Resetting or editing source text does
not change the stored ID.

### Valid spans

`SourceSpan` contains one `SourceId` and one existing `TextRange`. Its fields are
private and its named constructor can only receive an already validated range.
Consequently negative offsets and `end < start` continue to fail through
`TextOffset`/`TextRange`; zero-width spans remain valid. Bounds, missing-provider
sources, and surrogate-interior boundaries require source text and therefore
remain provider/adapter validation for #1036.

All offsets remain half-open UTF-16 code-unit offsets. No byte, scalar-value,
line/column, or grapheme conversion enters this model.

### Styled labels and primary locations

`DiagnosticLabel` contains private `style`, `span`, and optional `message`
fields. `LabelStyle` has exactly `Primary` and `Secondary`. Its constructor and
accessors preserve all three values unchanged.

`Diagnostic` removes the source-less `primary` field. Its only public source
locations are styled labels. Zero, one, or multiple primary labels are valid;
array position does not confer primary status. Token evidence remains
producer-native, but its range becomes a source-aware span so a source-scoped
transform cannot corrupt it.

The parser producer creates a primary label and token evidence with the same
explicit parser source ID. Locationless parser/lexer infrastructure failures
remain representable with no labels.

### Private storage and defensive copies

`Diagnostic`, `DiagnosticLabel`, `SourceSpan`, `SourceEdit`, and token evidence
use private fields with named constructors and accessors. The `Diagnostic`
constructor copies incoming label and note arrays. Its label/note accessors
return copies. `DiagnosticSet::items()` and `copy()` retain their existing outer
array copy boundary. No accessor exposes an internally stored mutable array.

### Source-qualified edits

`SourceEdit` contains private `source_id` and existing parser `Edit` values. It
does not duplicate damage arithmetic or replacement text. Public diagnostic
offset/relex operations take either the edited `SourceId` explicitly or a
`SourceEdit`; the old source-less forms are removed without shims.

For an edit to source A, disposition is classified from labels whose source ID
equals A:

- labels in another source are ignored by disposition and preserved exactly;
- A labels before the damage are preserved;
- A labels after the damage are shifted by the existing delta rule;
- any overlapping A label drops the complete diagnostic;
- a diagnostic with no A label is preserved unchanged.

Token evidence does not independently cause a drop: the issue defines
preserve/shift/drop from labels. When A labels select `Shift`, same-source token
evidence shifts with them; when the diagnostic is preserved because it has no A
label, all token evidence is preserved unchanged. Parser-produced token
evidence shares its explicit source with its primary label, so its normal
lifecycle remains coherent without inventing a second invalidation policy.

Existing insertion-boundary behavior remains: zero-width evidence at the
insertion point and evidence crossing it shift, while evidence ending at the
insertion point remains before the edit. Source IDs, label styles, label
messages, notes, severity, code, and producer identity never change during a
transform.

Block-reparse offsetting and TokenBuffer relexing construct source-qualified
damage values. Parser replay examines primary labels for the parser's stored
source ID, and its deduplication key includes styled source spans while still
allowing refreshed token evidence.

### Formatting compatibility

Legacy `format()` and `format_with_line_col()` remain compact compatibility
surfaces, not the new multi-source renderer. For the existing parser shape of
exactly one primary label, they preserve the current `message [start,end]` and
line/column output. A diagnostic with no primary remains message-only. The
source-backed, all-label rendering contract belongs exclusively to #1036.

## Caller cutover

Loom constructors, parser recovery, replay, block reparse, token-buffer relex,
Lambda rename diagnostics, Markdown diagnostics, Graph DSL attachment and
one-shot projection entry points, tests, and facade re-exports migrate
together. Accessors replace direct field reads. There is no public source-less
diagnostic shift/drop/relex API after the cutover.

Canopy's `view_updater` migrates from the removed public fields to accessors and
explicit styled source spans. The independent Markdown FFI `SetDiagnostics`
producer migrates under the same approved current-source projection policy and
gains equivalent range/severity/code/clearing coverage; it must not keep
flattening every result to a `0..0` formatted string. `SyncEditor::get_errors()`
continues to use the legacy compact formatter. Diagnostics remain outside
`AnalysisProjection`, and the independent semantic protocol producer remains
untouched until #1039.

The separately rooted Canvas Graph DSL shell allocates one namespaced source ID
from its append-only handle at construction, passes it to the attachment, and
reuses it across source edits. The ID is neither the mutable Graph DSL source
text nor a producer identity. JS-target Canvas compilation and focused tests
are part of the caller-cutover gate because the root workspace does not include
that module.

## Approved Canopy projection

The issue requires multiple primary labels and multiple sources to be
representable, but the existing Canopy protocol can carry only one source-less
range per diagnostic. The issue does not define how that richer Loom value is
projected to this narrower current-document wire type. Selecting a label merely
because it is first would violate the no-list-position inference rule.

The narrow proposed policy is:

- use a stable, provider-snapshot-scoped parser ID for the current document;
- emit one existing protocol diagnostic for every `Primary` label whose source
  equals the current parser source;
- preserve the existing single item for the normal one-primary parser case;
- emit one `0..0` item only for a truly locationless diagnostic;
- do not project labels belonging only to another source into the current
  editor;
- retain all labels in Loom for the source-backed renderer introduced by #1036;
- do not change the protocol wire shape in #1035.

This policy preserves every current-source primary without inferring a location
from array order. Because it is a material adapter behavior not stated in
#1035, it was explicitly approved by the user before implementation.

### Canopy boundary matrix

| Loom labels | Current-source primary labels | Protocol result |
| --- | ---: | --- |
| none | 0 | one compatibility item at `0..0` |
| one current primary | 1 | one item with that range |
| multiple current primaries | multiple | one ordered item per primary |
| current secondary only | 0 | no item |
| other-source labels only | 0 | no item |
| current and other-source labels | current primary count | only the current primaries |

Every emitted item preserves the diagnostic message, severity, and optional
code. Secondary labels and other-source labels remain in Loom for later
source-backed rendering; neither list position nor presentation text supplies a
wire location. The editor and Markdown FFI share one deterministic projection
helper. A `SyncEditor` allocates its source identity once at construction and
reuses it for parser creation and every snapshot; direct one-shot language
entry points require an explicit caller-owned identity. No protocol field or
TypeScript adapter shape changes in this issue.

## Existing API First

Reused:

- `TextOffset` and `TextRange` for validation, UTF-16 units, half-open ranges,
  and checked offsetting;
- `Edit` for parser damage and delta arithmetic;
- `Option` mapping/pattern matching for optional code, messages, and evidence;
- `Array::copy`, `Array::map`, `Array::filter`, and search/fold operations for
  defensive copies and declarative label selection;
- Canopy's existing process-local editor construction counter as the allocation
  seed for a separately typed and namespaced parser `SourceId`; the value is
  allocated once before parser construction and is never derived from the CRDT
  agent, producer, text, projection, entity, or presentation state;
- `DiagnosticSet::items()` and `Diagnostic::labels()` defensive copies plus
  `Iter::flat_map`, `Iter::filter`, `Iter::map`, and `Iter::to_array` for the
  ordered current-source protocol projection;
- existing relex disposition, parser replay, and `DiagnosticSet` ordering and
  deduplication structure;
- the Canvas source registry's append-only handle as the construction identity
  seed for the separately rooted Graph DSL attachment; no second mutable
  counter or lookup collection is needed.

Checked but not reused:

- generic `Range` has public unvalidated `Int` fields and no source identity;
- the Graph DSL example's private-package `SourceSpan` has raw offsets and no
  source identity or validation;
- projection IDs, interning IDs, CRDT peer IDs, and `DiagnosticSource` identify
  different domains and must not become source IDs;
- `Map` and `Set` are unnecessary because transforms operate independently over
  the existing ordered label array;
- `ArrayView` and `Iter` are available, but owning defensive copies are required
  at the public boundary;
- `cmp` helpers and sorting are unnecessary because #1035 neither normalizes nor
  orders labels and does not compute unions;
- generic overlap helpers are unnecessary because the existing half-open relex
  disposition already defines insertion and deletion boundary behavior.

The existing generic editor and Markdown FFI conversions are inline, divergent
adapter code rather than reusable APIs. One new pure
`project_diagnostics_for_source(SourceId, DiagnosticSet)` helper therefore owns
only the Loom-to-existing-protocol narrowing policy. `Parser::source_id()`
remains the authoritative identity store; `SyncEditor` exposes it without
duplicating mutable state.

The private pure `source_graph_source_id(Int)` helper owns only the Canvas
handle namespace conversion. It is necessary because the separate JS-only
module must pass the same construction identity to `GraphAttachment` and its
focused lifecycle test without adding a second mutable counter, retaining a
duplicate field, or deriving identity from source text.

New type responsibility boundaries:

- `SourceId`: opaque equality-stable source key only;
- `SourceSpan`: pair an existing validated range with its source key;
- `DiagnosticLabel`: preserve presentation-neutral style, span, and message;
- `SourceEdit`: qualify existing parser damage with the edited source.

No new generic location, source registry, renderer, fix, map, sorting helper, or
source-text owner is introduced.

## Test-first acceptance map

Focused failing tests precede production edits and cover:

1. an A edit never shifts a B label;
2. an A edit never drops a diagnostic for a B overlap;
3. same-source shift/drop/replay retains existing boundary semantics;
4. primary/secondary style and label messages survive construction and shifts;
5. half-open insertion/deletion boundaries, including zero-width EOF;
6. negative and reversed ranges fail at the validated constructors;
7. caller mutation of input/output arrays cannot mutate a diagnostic or set;
8. existing compact formatting remains unchanged for zero/one primary;
9. multiple labels and 2–4 sources preserve all non-edited sources;
10. source identity is independent of producer identity;
11. same numeric ranges in different sources do not deduplicate;
12. parser replay shifts only parser-source evidence.

Property tests generate 2–4 source IDs and compare the transformed result with
a reference classification that changes only the selected source.

## Validation

Each MoonBit file edit is followed immediately by the narrowest applicable
`NEW_MOON_MOD=0 moon check`. Final Loom validation runs focused core/parser
tests, the full Loom suite, `moon info`, `moon fmt`, and interface-diff review.
After the Loom PR merges, Canopy updates only to the published Loom merge commit
and runs its focused editor tests plus the full workspace checks. Concrete A/B
shift, drop, deduplication, replay, and defensive-copy scenarios are retained as
execution evidence.
