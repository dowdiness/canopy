# ReachableFailure shared diagnostics design

Issue: #1039

## Scope

Project the existing Lambda `ReachableFailure` output through Loom's neutral
diagnostic model. The scope graph remains the resolver of record. This change
does not reimplement #617, does not move diagnostics into `AnalysisProjection`,
and does not introduce entity-backed diagnostic remapping.

## Behavioral boundary matrix

| Input state | Parser diagnostics | Semantic snapshot | Published result |
| --- | --- | --- | --- |
| Valid source, all references bound | empty | current, empty | empty |
| Valid source, unresolved reference | empty | current, warning | semantic warning |
| Recoverable syntax error with unresolved references | current | current | parser then semantic diagnostics |
| Semantic source differs from the coherent parser snapshot source | current | stale | parser diagnostics only |
| Parser snapshot source differs from editor text | stale | any | no diagnostics |
| Unresolved reference is corrected or bound | current | recomputed empty | prior warning is cleared |

## Accepted contract and invariants

1. `ReachableFailure` and `failures(graph, source_map)` remain producer-native
   data and the only unresolved-reference query. No second name resolver is
   added.
2. Lambda exposes a separate neutral diagnostic builder. Diagnostics are
   removed from `SemanticProjection`; annotations and decorations remain its
   presentation responsibility. `AnalysisProjection` never stores diagnostics.
3. The producer receives the editor parser's opaque `SourceId`. It constructs a
   `DiagnosticSource("lambda.semantic")` independently; producer identity and
   source-file identity are never interchangeable.
4. Each finding is a warning with stable code `lambda.unresolved_reference` and
   preserves the existing main message `Free variable '<name>'`.
5. The unresolved identifier's exact token range becomes the single primary
   `SourceSpan`. Lambda projection records the identifier token under a
   dedicated `REFERENCE_NAME_ROLE` on the reference's existing NodeId. This is
   required because parenthesized expressions reuse the inner NodeId while the
   ordinary node range includes the parentheses. `failures` resolves the
   reference NodeId through that token role in the current `SourceMap`; it does
   not fall back to a wider node range. Scope witnesses are likewise resolved
   before neutral construction: each scope records its structural owner node
   during graph construction, and the current `SourceMap` supplies that owner's
   range. A resolved owner range is a secondary label with message `searched
   lexical scope`; a witness without an authoritative range becomes a note. No
   location is inferred from a name, message, diagnostic position, scope-array
   position, or presentation DTO.
6. The neutral builder accepts the current source text as an external
   validation input but never stores it in a diagnostic. A typed
   `SemanticDiagnosticError` boundary rejects a range unless its offsets are
   non-negative and ordered, its end is at most `source.length()`, and
   `String::get_view(start~, end~)` confirms both offsets are
   valid UTF-16 code-point boundaries. Only then does the builder call
   `TextRange::from_offsets`. Invalid ranges are neither clamped nor emitted to
   the editor after a renderer failure.
7. All ranges remain half-open UTF-16 code-unit offsets. A label ending at the
   source length is valid, as is Loom's existing zero-width representation.
8. Loom constructors and accessors preserve label style/message and defensive
   copies. The producer never exposes a mutable internal diagnostic array.
9. Parser diagnostics are read from one coherent `Parser::snapshot()`. The
   Lambda diagnostic callback returns the exact parser source text alongside
   its neutral set. A private deterministic merge accepts semantic diagnostics
   only when editor text, parser snapshot source, and semantic source are equal;
   otherwise it publishes no mixed snapshot. Equal-source edits recompute from
   the current projection and scope graph; generic NodeId/entity remapping is
   not used.
10. Parser diagnostics retain order and semantic diagnostics append in scope
    graph order via `DiagnosticSet::copy` plus `add_all`.
11. The existing semantic-projection JSON shape remains compatible, but its
    `diagnostics` member is assembled at the FFI shell by the existing editor
    protocol adapter. The semantic producer does not construct protocol DTOs.
12. Plain text uses Loom's existing source-backed renderer. Editor patches use
    the existing editor publisher. Both consume the same neutral diagnostic.

## Existing API First

### Reused project and Loom APIs

- `ReachableFailure`, `failures`, and `visited_scopes`: authoritative semantic
  failure and witness; reused unchanged as the query.
- `SourceMap::get_token_span`, `SourceMap::get_range`, and existing UTF-16
  `Range`: authoritative identity-to-span conversion. A new reference-name role
  is necessary because no current role distinguishes a `VarRef` identifier from
  a parenthesized node range. A scope-owner query is added only because no
  existing scope-to-node/span API exists.
- Loom `SourceId`, `TextRange::from_offsets`, `SourceSpan`, `DiagnosticLabel`,
  `LabelStyle`, `Diagnostic`, `DiagnosticCode`, and `DiagnosticSource`: reused as
  the sole neutral model and validation boundary.
- `DiagnosticSet::empty`, `single`, `copy`, `push`, `items`, and `add_all`:
  collection construction, merging, deduplication, and defensive copying.
- `Diagnostic::render_plain` / `DiagnosticSet::render_plain` and the editor's
  existing current-source projection/publisher: reused without a second
  renderer or wire model.
- `Parser::snapshot`: reused because source, CST, AST, and parser diagnostics are
  updated atomically in one parse snapshot.

### MoonBit core APIs checked

- `Option.map/bind` and pattern matching: used for missing locations and optional
  semantic snapshots.
- `String::length` and `String::get_view`: reused to validate source bounds and
  UTF-16 code-point boundaries without slicing or storing source text.
- `Array.map`, `filter`, `filter_map`, `copy`, and `Iter` traversal: used for
  labels, notes, and protocol projection. Local mutable arrays remain only as
  builders returned from deterministic functions.
- `Map` and `Set`: checked but no new collection is needed. The existing scope
  graph and `DiagnosticSet` already own lookup/deduplication.
- `Result`: checked; Loom's raising range constructor is the existing typed
  validation contract, so a parallel result wrapper would add no value.
- comparison helpers, overlap checks, and sorting: checked and not needed. The
  scope graph already defines witness order, and no diagnostic correctness rule
  depends on label overlap or sorted spans.
- `ArrayView`: checked but not used because Loom's public diagnostic accessors
  intentionally return owning defensive copies.

### New responsibility boundaries

- A scope-owner field/query records the node that structurally opened a scope
  and resolves that producer-native identity through the current `SourceMap`.
  Existing APIs expose declaration binders and node-to-scope lookup, but no
  authoritative scope-to-source direction.
- `REFERENCE_NAME_ROLE` is the smallest producer/consumer contract that gives a
  `VarRef` an exact identifier span even when syntax wrappers reuse its NodeId;
  existing parameter and binding-name roles describe different tokens.
- `SemanticDiagnosticError` belongs to the Lambda-to-neutral conversion
  boundary. Loom's `DiagnosticBuildError` validates ordering but has no source
  text with which to reject out-of-bounds or surrogate-interior offsets.
- A private source-consistency merge in the editor is a pure functional core:
  `(editor source, parser snapshot, optional semantic snapshot) -> DiagnosticSet`.
  It is the only new combination policy and performs no I/O or mutation.

## Caller migration

- Lambda semantic tests consume the neutral diagnostic builder instead of a
  protocol array on `SemanticProjection`.
- Lambda capabilities expose a content-tagged semantic diagnostic snapshot built
  from the same reactive parser/projection inputs used by the current editor.
- The generic editor merges the current producer set with parser diagnostics and
  passes the combined neutral set to the existing publisher once.
- The semantic FFI composes its compatibility JSON through the editor adapter.
- Markdown and generic editors keep `LanguageCapabilities::default`; the new
  callback is optional and defaults to no semantic producer.

## Focused tests

1. Valid unresolved input produces one warning with the stable semantic code.
2. The exact identifier range is the primary half-open UTF-16 span, including an
   end boundary equal to source length. A parenthesized unresolved reference
   labels only the inner identifier, never the parentheses.
3. Primary/secondary styles and messages survive; multiple witnessed scopes
   become multiple labels, and missing scope ranges become notes.
4. Negative, reversed, out-of-bounds, and surrogate-interior producer ranges
   are rejected by the source-aware semantic conversion boundary and never
   reach the editor publisher.
5. Diagnostic/label/note access remains defensive-copy safe.
6. Diagnostic source identity is distinct from source-file identity.
7. A recoverable parser diagnostic and semantic warnings coexist in one editor
   patch.
8. Plain and editor adapters consume the same neutral diagnostic.
9. Correcting the reference clears the semantic warning.
10. A semantic source mismatch cannot join current parser diagnostics.
11. Generated interfaces and source inspection show no NodeId, SyntaxNode,
    ScopeId, or protocol DTO inside the neutral diagnostic.

## Validation

Run focused tests for `lang/lambda/scope`, `lang/lambda/semantic`, `editor`,
`lang/lambda/companion`, and `ffi/lambda`, followed by workspace `moon check`,
`moon test`, `moon info`, and `moon fmt`. Inspect every generated `.mbti` diff,
then fetch `origin/main` and push the committed clean HEAD normally so Lefthook
validates every affected MoonBit package. GitHub CI's `All Checks Passed` job
remains the exact-commit merge gate.
