# Generic language SPI deepening — structured edits, patch traces, identity hints, and edit-port moves

**Date:** 2026-08-07
**Status:** Accepted
**Partially supersedes:** [Lambda edit bridge boundary](2026-06-15-lambda-edit-bridge-boundary.md)

**Related:**

- [Lambda edit bridge boundary](2026-06-15-lambda-edit-bridge-boundary.md)
- [Library API boundary](2026-06-11-library-api-boundary.md)
- [Framework genericity contract](2026-03-29-framework-genericity-contract.md)

## Decision

Deepen the generic language SPI in `lang/runtime` from the coarse
`compute_edit -> apply_span_edits -> Result[Unit, String]` contract to a richer
shape, and absorb the "richer channel" the 2026-06-15 Lambda boundary ADR kept
outside it:

1. **Structured results.** Edit computation returns typed
   `core.EditError`s (not a flattened `String`) and exposes the applied
   `SpanEdit` patch trace to callers. Per-op identity hints are first-class in
   the edit result rather than an unexpressible side concern.
2. **Language-owned extras.** Construction returns `(SyncEditor[T], E)` where
   `E` is a language-owned extras type (Lambda companion memos, Markdown
   semantic attachment). The editor owns construction order — parser →
   memos+extras → capabilities → editor — and the identity-hint channel,
   eliminating caller-threaded `Ref` side-channels.
3. **Moves are edit-port computation.** The editor-owned `move_node` is split
   into a pure `core::compute_move` (legality checks + whitespace-preserving
   span arithmetic, parameterized by language text policies: placeholder and
   separator) and a thin `SyncEditor::move_node` application shell. Languages
   express moves through their edit port — Lambda's `Drop` via `compute_move`,
   Markdown's `MoveBlock` via its existing `compute_move_block`.
4. **Lambda joins the common path.** `apply_lambda_tree_edit` ceases to be a
   contract-exceptional bridge; it becomes a thin wrapper over the shared apply
   path. Lambda remains a legacy stress case, not a language template.

The SPI stays a closure record (MoonBit's Self-based traits and the orphan rule
forbid trait parameters); `parse` stays a closure rather than a grammar value
(`@loom` grammar typing carries Token/Kind/Ast parameters that must not leak
into the SPI).

## Why the revisit condition is met

The 2026-06-15 ADR's revisit condition: *"only when at least one non-Lambda
language needs the same richer shape: typed edit errors, successful patch
traces, or editor-owned move/drop semantics."* All three sub-conditions now
have non-Lambda evidence:

1. **Markdown needs identity hints.** `apply_markdown_edit`
   (`lang/markdown/companion/markdown_companion.mbt`) duplicates
   `LanguageSpec::apply_edit` line-for-line to add `hint~` support; the coarse
   SPI calls `apply_span_edits` without a hint and cannot express per-op
   identity policy. A non-Lambda language has forked the bridge.
2. **Markdown already routes moves through its edit port.**
   `MoveBlock` dispatches to `compute_move_block` (600+ lines) inside
   `compute_markdown_edit`. The "editor-owned move" clause rested on
   `move_node` being editor-coupled; inspection shows the coupling is an
   artifact of mixing pure span planning with application (range resolution,
   hint taint, `apply_span_edits`). The pure planning is language-neutral span
   math; the placeholder and separator are language text policies.
3. **The `(SyncEditor[T], E)` construction shape is observed, not invented.**
   Markdown construction already returns a side product
   (`MarkdownSemanticAttachment`) by mutating a `Ref` inside `build_memos`.

## Boundary rules

- The SPI returns `core.EditError`. `TreeEditError` mapping stays at the
  editor/FFI boundary (`map_edit_error` remains there).
- The generic apply path requires only `T : Eq`. `Eq + Renderable` bounds
  discharge at language construction sites (placeholder policy), never on the
  shared path.
- `compute_move` is an *expression-level* move helper. Languages with
  block-level move semantics (Markdown) keep their own edit-port move logic.
- The identity-hint channel is framework-owned; languages receive an opaque
  handle, and reconcile consumes exactly the queue the apply path writes.
- Language-specific lookup structures (registry, `DefinitionIndex`) remain
  derivable from `ProjNode`; the shared `EditContext` provides bound-free
  `resolve` so languages do not reimplement it.

## Relationship to earlier decisions

This ADR partially supersedes the
[Lambda edit bridge boundary](2026-06-15-lambda-edit-bridge-boundary.md):

- **Superseded:** "Keep the contracts separate unless consumers migrate
  deliberately" → the contracts unify; consumers migrate in one deliberate
  sweep (JSON → Markdown → Lambda).
- **Superseded:** "Preserve the richer channel for Lambda" → the SPI is now
  the richer channel.
- **Superseded:** "Keep editor-coupled moves out of the SPI until another
  language shares the need" → the coupling was an artifact of the mixed
  implementation; Markdown's `compute_move_block` is the second adapter.
- **Superseded:** "Lambda remains a documented exception" → Lambda becomes a
  regular adapter, still a stress case.

**Remains active:**

- Closure-record SPI and `parse` closure (from the
  [library API boundary](2026-06-11-library-api-boundary.md) and the
  [framework genericity contract](2026-03-29-framework-genericity-contract.md)).
- Language-specific context derivation from `ProjNode`; the SPI is not widened
  for derivable context alone.
- `protocol/wire`, `sync_session`, `ephemeral` stability obligations.

## Rejected alternatives

### Keep the 2026-06-15 status quo; Lambda stays a documented exception

Rejected because Markdown's fork of the bridge demonstrates the SPI is already
too shallow for a non-Lambda language. The fork duplicates the bridge and risks
divergent hint and error behavior.

### Lambda-only `LanguageSpecV2` (explicitly rejected by the 2026-06-15 ADR)

Rejected again. Markdown's needs (identity hints, extras, edit-port moves) are
not Lambda's needs; a per-language fork multiplies bridges instead of deepening
one seam.

### Effectful `move_node` callback on `EditContext`

Rejected in the first revision: it would double-apply (the callback applies,
then the result protocol applies again), force `T : Eq + Renderable` onto the
generic path, and leak `TreeEditError` into the SPI. The pure-core split
dissolves all three objections.

### Grammar values instead of a `parse` closure

Rejected. `@loom.Grammar[Token, Kind, Ast]` would expose token/kind/Ast
parameters through the SPI, coupling it to Loom's grammar typing.

### Raw `SyncEditor::new_from_parts`

Rejected. Exposing parser/memo/capabilities parts publicly would leak
construction coherence invariants (source-ID allocation, document version,
hint channel, Watch anchors). `new_with_builder` keeps ownership with the
editor.

## Consequences

- `lang/runtime` `.mbti` regenerates; migration order is JSON → Markdown →
  Lambda, with `new_generic` removed only after all three migrate.
- Behavior deltas are deliberate and test-updated, not silent: hint taint on
  failed moves, hint pop on no-op batches, and error action strings
  (`"move_node: source"` → `"Resolve"`).
- Naming follows the `compute_*` convention (`compute_move` beside
  `compute_json_edit` / `compute_markdown_edit` / `compute_text_edit` /
  `compute_move_block`).
- `compute_move` is a shared *helper*; languages opt in. It is not the
  canonical move algorithm — Markdown's block move keeps its own semantics.
