# JSON Projectional Editor — Design

**Date:** 2026-03-29
**Status:** Approved (revised: architectural improvements + Codex review fixes)

## Goal

Build a JSON projection pipeline (`lang/json/`) that proves `framework/core/` works with a second real language. Validate via tests, not UI. Compare JSON boilerplate against lambda's to inform loomgen code generator design.

## Non-Goals

- Web UI (deferred — can reuse Rabbita or ideal editor later)
- FlatProj / incremental per-member derivation (deferred)
- Full edit handler parity with lambda

## Architecture

```
framework/core/                 ← MODIFY: add SpanEdit, FocusHint (shared across languages)

loom/examples/json/src/         ← existing: parser, grammar, JsonValue AST
  proj_traits.mbt               ← CREATE: TreeNode + Renderable trait impls
  value_convert.mbt             ← MODIFY: make parse_json_string pub
  moon.pkg                      ← MODIFY: add @loomcore import for traits

canopy/lang/json/
  proj/                         ← NEW: syntax_to_proj_node, populate_token_spans, memo builder
  edits/                        ← NEW: JsonEditOp, text edit handlers, bridge

canopy/editor/
  sync_editor.mbt               ← MODIFY: add SyncEditor::new_generic (3-memo, no FlatProj)
```

Same three-layer pattern as lambda:
1. Trait impls in type owner (`loom/examples/json/src/proj_traits.mbt`)
2. Projection builders in canopy (`lang/json/proj/`)
3. Edit handlers + editor bridge in canopy (`lang/json/edits/`)

## Prerequisite 1: Move SpanEdit + FocusHint to framework/core/

**Problem:** `SpanEdit` and `FocusHint` are defined in `lang/lambda/edits/types.mbt` but are structurally generic — they describe text span replacements and cursor hints with no lambda-specific content. The JSON editor needs the same types.

**Fix:** Move both to `framework/core/types.mbt`. Update `lang/lambda/edits/types.mbt` to re-export via `pub using @core { type SpanEdit, type FocusHint }`. JSON imports from `@core` directly — no lambda dependency.

This also establishes the convention: **edit result types are framework-level, edit operation enums are language-level.**

## Prerequisite 2: Add SyncEditor::new_generic (no FlatProj)

**Problem:** `SyncEditor::new` requires a `build_memos` callback returning `(Memo[VersionedFlatProj], ...)`. JSON has no FlatProj, and `lang/json/` should not depend on `@lambda_flat`.

**Fix:** Add a second public constructor that takes a 3-memo builder:

```moonbit
pub fn[T] SyncEditor::new_generic(
  agent_id, make_parser,
  build_memos : (Runtime, Signal[String], Signal[SyntaxNode?], ImperativeParser[T])
    -> (Memo[ProjNode[T]?], Memo[Map[NodeId, ProjNode[T]]], Memo[SourceMap]),
  capture_timeout_ms?,
) -> SyncEditor[T]
```

Internally sets `proj_memo = None`. The existing `new_lambda` is unchanged. `get_flat_proj()` returns `None` for editors created via `new_generic`.

**Why not just make proj_memo optional?** That still requires the JSON memo builder to return a 4-tuple with `None` as first element, typed as `Memo[VersionedFlatProj]?`. The JSON package would need to import `@lambda_flat` just for the type. A separate constructor avoids this entirely.

## Prerequisite 3: Make parse_json_string pub in loom

**Problem:** The projection builder needs to properly unescape JSON string values (handle `\"`, `\\`, `\n`, Unicode escapes). The JSON module already has `parse_json_string` in `value_convert.mbt` but it's private (`fn`, not `pub fn`).

**Fix:** Change to `pub fn parse_json_string(raw : String) -> String`. One-line change in the loom submodule.

## Component 1: TreeNode + Renderable for JsonValue

**Location:** `loom/examples/json/src/proj_traits.mbt` (new file)
**Dep change:** `@loomcore` already imported in JSON's `moon.pkg` as `@core` (same package).

### TreeNode

```
children:
  Null, Bool, Number, String, Error → []
  Array(items) → items
  Object(members) → members.map(m => m.1)   // values only

same_kind:
  constructor-tag equality (Null==Null, Bool==Bool, Array==Array, etc.)
```

**Design choice: values-only children for Object.** Key names appear in the parent Object's label and are accessible via token spans for rename operations. ProjNode children use **MemberNode spans** (not value-only spans) so delete operations remove the full member text.

**Known limitation:** Same-kind siblings in an Object (e.g., two Numbers) reconcile by positional order. This is the same as lambda's let-bindings. Acceptable for framework validation.

**Future options:** (B) Add Member variant to JsonValue, or (C) create JsonExpr wrapper.

### Renderable

```
kind_tag: "Null", "Bool", "Number", "String", "Array", "Object", "Error"

label:
  Null → "null"
  Bool(b) → b.to_string()
  Number(n) → format without trailing .0
  String(s) → quoted, truncated at 20 chars
  Array(items) → "[N items]"
  Object(members) → "{key1, key2, ...}"
  Error(msg) → "Error: " + msg

placeholder (per-kind):
  Null→"null", Bool→"false", Number→"0", String→"\"\"",
  Array→"[]", Object→"{}", Error→"null"

unparse: JSON serialization with proper escaping via json_escape helper
  Error(_) produces "null" (valid JSON)
```

## Component 2: Projection Builder (`lang/json/proj/`)

### `proj_node.mbt` — CST → ProjNode[JsonValue]

**Key insight: use MemberNode spans for Object children.** Each value ProjNode in an Object uses the parent MemberNode's `start`/`end`, not the value node's. This ensures `source_map.get_range()` returns the full member span (key + colon + value), enabling correct delete operations.

**Text extraction from CST nodes:** Uses seam's `SyntaxNode` API:
- Key text: `member_node.all_children()` → find first `SyntaxElement::Token(t)` where `t.kind() == StringToken.to_raw()` → `parse_json_string(t.text())`
- String values: `node.token_text(StringToken.to_raw())` → `parse_json_string(text)`
- Number values: `node.token_text(NumberToken.to_raw())` → parse_double
- Bool values: `node.find_token(TrueKeyword.to_raw())` to determine true/false
- Value nodes: `member_node.nth_child(0)` (first node child, not token child)

### `populate_token_spans.mbt`

Extracts key name spans from MemberNode's StringToken. Span covers the **entire quoted token** (including quotes). Must unwrap RootNode before walking children.

### `json_memo.mbt` — Memo builder

Returns 3 memos (not 4 — no FlatProj):
1. `Memo[ProjNode[JsonValue]?]` — reconciled projection tree
2. `Memo[Map[NodeId, ProjNode[JsonValue]]]` — node registry
3. `Memo[SourceMap]` — position tracking with token spans

No dependency on `@lambda_flat`.

## Component 3: Edit Handlers (`lang/json/edits/`)

### JsonEditOp enum (language-specific)

Delete, AddMember, AddElement, WrapInArray, WrapInObject, Unwrap, ChangeType, RenameKey, CommitEdit.

No generic UI ops (Select, Collapse, etc.) — those go through TreeEditorState directly.

### `compute_json_edit` returns `Result[(Array[SpanEdit], FocusHint)?, String]`

Uses the **shared** `SpanEdit` and `FocusHint` from `framework/core/` — same types as lambda.

### `apply_json_edit` bridge

Free function (not a method on SyncEditor) that:
1. Reads proj + source_map from SyncEditor memos
2. Calls `compute_json_edit`
3. Applies span edits in reverse document order via SyncEditor's public API

Requires `apply_text_edit_internal` to be made `pub` on SyncEditor.

### Key edit handler details

- **Delete:** Uses the MemberNode span (from source map) to remove the entire member including key+colon. Handles trailing comma cleanup.
- **Unwrap:** Guards single-element only. Returns Err for multi-element containers. Extracts value by finding the child ProjNode's original value span within the member span.
- **RenameKey:** Uses token span `"key:N"` to replace the quoted key. Applies `json_escape` to the new key.
- **AddMember/AddElement:** Inserts before closing delimiter. Handles comma insertion.

## Testing Strategy

Same as before, plus:
- **RenameKey test** with escaped characters
- **Duplicate-kind reconciliation** test
- **Error recovery** during intermediate typing states
- **get_flat_proj returns None** for JSON editor
- Assertions check actual values, not just `is Some(_)`

## Dependencies (no cross-language deps)

```
framework/core/     ← SpanEdit, FocusHint (shared)
lang/json/proj/     ← @core, @json, @loomcore, @seam, @incr, @loom
lang/json/edits/    ← @core, @json, @loomcore, lang/json/proj, editor
```

`lang/json/` does NOT import `@lambda_flat`, `@lambda_proj`, `@lambda_edits`, or `projection/`.

## Risks

1. **SyncEditor::new_generic** — New public constructor. Low risk with existing tests.
2. **SpanEdit/FocusHint move** — Re-export preserves backward compat. Low risk.
3. **apply_text_edit_internal visibility** — Making it pub is a minor API surface increase.
4. **Error recovery** — JSON parser has extensive recovery; projection must handle all states.
