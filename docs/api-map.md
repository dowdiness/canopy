# API Map — Agent Index

**Purpose:** Task-first index for agents. When you need to do X, look here before defining new code.
This is a lookup table, not documentation. If this disagrees with the code, the code wins.

Refresh with: `NEW_MOON_MOD=0 moon ide outline <pkg>` or `NEW_MOON_MOD=0 moon ide doc "<keyword>"`.

---

## Node Identity

**Want:** Create or compare tree node IDs.

| API | Location | Notes |
|-----|----------|-------|
| `NodeId` | `core/` | Opaque wrapper over `Int`. Use this, do not invent integers for nodes. |
| `NodeId::from_int` | `core/` | Construct from raw int (avoid unless crossing FFI boundary). |
| `next_proj_node_id(counter)` | `core/` | Monotonic counter for fresh `ProjNode` IDs. Prefer the constructors below in projection builders. |
| `ProjNode[T]` | `core/` | Generic projection node carrying value `T`. |
| `ProjNode::leaf(kind, syntax_node, counter)` | `core/` | Fresh childless projection node spanning a `SyntaxNode` in UTF-16 code-unit source offsets. Preferred for CST leaf projections. |
| `ProjNode::branch(kind, start, end, children, counter)` | `core/` | Fresh projection node with explicit half-open UTF-16 source span. Use `ProjNode::new` only when preserving/reusing a known ID. |

**Do not:** Create parallel `id: Int` fields or ad-hoc node numbering.

---

## Source Map / Position Lookup

**Want:** Map node IDs to text ranges, or find nodes at a cursor position.

`SourceMap` ranges are `@loomcore.Range` values interpreted as half-open
UTF-16 code-unit source offsets. Do not pass eg-walker item-space ranges or
ProseMirror tree positions to this API.

| API | Location | Notes |
|-----|----------|-------|
| `SourceMap` | `core/` | Canonical position index. One per editor instance. |
| `SourceMap::new()` | `core/` | Constructor. |
| `SourceMap::get_range(node_id)` | `core/` | `@loomcore.Range?` for a node, in UTF-16 source offsets. |
| `SourceMap::nodes_at_position(pos)` | `core/` | All nodes covering a UTF-16 source offset. |
| `SourceMap::innermost_node_at(pos)` | `core/` | Deepest node at a UTF-16 source offset. Use for hover/click. |
| `SourceMap::nodes_in_range(range)` | `core/` | All nodes overlapping a UTF-16 source range. |
| `SourceMap::apply_edit(edit_start, old_range)` | `core/` | Update ranges after a text deletion. Both arguments use UTF-16 source offsets. Call this, don't rebuild. |
| `SourceMap::rebuild_ranges()` | `core/` | Full rebuild (expensive — prefer `apply_edit`). |
| `SourceMap::set_token_span` | `core/` | Use for computed token-level ranges. |
| `SourceMap::set_span_from_token` | `core/` | Preferred direct-token registration helper: finds a direct visible token on a `SyntaxNode` and records its range. |
| `SourceMap::get_token_span` | `core/` | Read a recorded token-level span by role. |

**Do not:** Store `(start, end)` integers separately when `SourceMap` already tracks them.

---

## Text Editing / Diff

**Want:** Compute diffs between old and new text, or apply edits.

| API | Location | Notes |
|-----|----------|-------|
| `compute_edit(old, new)` | `editor/` | Returns `@loom_core.Edit`. Primary diff entry point. |
| `ViewUpdateState` | `editor/` | Tracks previous view state for incremental diff. |
| `ViewUpdateState::set_previous` / `set_had_errors` | `editor/` | Update before computing next diff. |
**Do not:** Call `apply_text_edit_internal` directly — it is internal with no stability guarantee. Route bulk text edits through `SyncEditor` or the public `compute_edit` path.

**Do not:** Implement custom LCS diff; `compute_edit` already does this.

---

## Protocol / View Rendering

**Want:** Annotate nodes with decorations, diagnostics, or lay out a view tree.

| API | Location | Notes |
|-----|----------|-------|
| `Decoration` | `protocol/` | Visual annotation on a node range. |
| `Decoration::Decoration(...)` | `protocol/` | Named constructor. |
| `Diagnostic` | `protocol/` | Error/warning with range + message. |
| `Diagnostic::Diagnostic(...)` | `protocol/` | Named constructor. |
| `TokenSpan` | `protocol/` | Span for a single token (syntax highlighting). |
| `ViewNode` | `protocol/` | Node in the rendered view tree. |
| `ViewNode::ViewNode(...)` | `protocol/` | Named constructor. |
| `layout_to_view_tree(layout)` | `protocol/` | Convert a `Layout` from the pretty-printer to a `ViewNode` tree. |
| `LanguageCapabilities::with_to_view_node` | `editor/` | Install a language-specific `ProjNode` → `ViewNode` converter when generic `Renderable` conversion is not enough. Prefer refining `@protocol.proj_to_view_node`; wire this in `lang/*/companion`, not in `SyncEditor` or frontend adapters. |

**Do not:** Build a parallel view representation outside `ViewNode`/`protocol/`, or special-case language-specific view semantics in generic editor/frontend code.

---

## Incremental Computation

**Want:** Derive a value that auto-updates when inputs change.

| API | Location | Notes |
|-----|----------|-------|
| `Input[T]` (alias `Var`) | `loom/incr` | Mutable source cell. Create once, set with `.set(v)`. |
| `Derived[T]` (alias `Memo`) | `loom/incr` | Pure derived value. Reads inside compute fn run lazily. |
| `Watch[T]` (alias `Observer`) | `loom/incr` | Side-effectful sink — GC anchor. Must be kept alive. |
| `ReachableDerived[T]` (alias `HybridMemo`) | `loom/incr` | Derived that's also reachable from Watch. |
| `DerivedMap[K,V]` | `loom/incr` | Keyed incremental map. |
| `@incr.Runtime` | `loom/incr` | Shared runtime; editors in a workspace share one. |
| `rt.read(memo)` | `loom/incr` | **Correct** way to read a Derived. Do NOT use `memo.get()`. |
| Authoritative API reference | `loom/incr/docs/api-reference.md` | Read this before using `incr`; the `incr` skill may be outdated. |

**Do not:** Build ad-hoc cache-invalidation logic or use `memo.get()` directly.

---

## Parser Construction (Loom)

**Want:** Build or extend a parser, apply incremental edits to a parse tree.

| API | Location | Notes |
|-----|----------|-------|
| `@loom.Parser::new(...)` | `loom/loom` | Create a parser for a grammar. |
| `@loom.apply_edit(parser, edit)` | `loom/loom` | Incrementally update parse tree after a text edit. |
| `@loom.set_source(parser, src)` | `loom/loom` | Set full source (non-incremental). |
| `@loom_core.Edit` | `loom/loom` | Edit descriptor — produced by `compute_edit`. |
| Authoritative reference | `.claude/skills/loom` (skill) | Invoke `/loom` before writing parser code. |

**Do not:** Construct `@incremental.ImperativeParser` directly inside a `Memo` — this discards all incremental state. See loom skill.

---

## CRDT / Collaboration

**Want:** Apply remote ops, sync with peers, track cursors.

| API | Location | Notes |
|-----|----------|-------|
| `SyncEditor[T]` | `editor/` | Collaborative editor wrapping a CRDT document. |
| `encode_message` / `decode_message` | `editor/` | Binary sync protocol serialization. |
| `encode_sync_request` / `encode_sync_response` | `editor/` | Handshake messages. |
| `SyncStatus` / `SyncErrorReason` | `editor/` | Status enums for sync health. |
| `InMemoryRoom` | `editor/` | In-process test room (not production). |
| `RelayRoom` | `relay/` | Production relay — use for multi-peer routing. |
| `RelayRoom::on_connect` / `on_message` / `on_disconnect` | `relay/` | Lifecycle hooks. |
| `encode_peer_joined` / `encode_peer_left` | `relay/` | Presence messages. |

**Do not:** Implement custom binary framing; use `encode_message`/`decode_message`.

---

## Tree Structure / Projection

**Want:** Build an interactive tree editor, traverse children, manage editor state.

| API | Location | Notes |
|-----|----------|-------|
| `InteractiveChildren[T]` | `projection/` | Enum over child variants in a tree editor. |
| `InteractiveTreeNode[T]` | `projection/` | A node in an interactive projection. |
| `TreeEditorState[T]` | `projection/` | Editor state for a tree view. |

---

## Text / Unicode

**Want:** Segment text by grapheme clusters, handle emoji, non-BMP characters.

| API | Location | Notes |
|-----|----------|-------|
| `lib/moji/` package | workspace member | UAX #29 grapheme cluster library. Use this for all Unicode segmentation. |
| Non-BMP `String::sub` | `lib/moji/` | Dangerous — see `project_unicode_failure_modes` memory. Surrogate pairs abort uncatchably. |

**Do not:** Implement per-codepoint iteration without checking moji. Do not call `String::sub` on user text without bounds from moji.

---

## Error Handling

**Want:** Signal a defect, propagate a domain error, or define a new error type.

| API | Pattern | Notes |
|-----|---------|-------|
| `fail("msg")` | any | Catchable defect signal. Prefer over `abort` when recovery is possible. |
| `abort()` | any | Uncatchable — use only when catching would produce silently wrong results. |
| `T!Error` return type | any | Fallible function signature. `!` propagates errors automatically. |
| `guard x is P else { fail(...) }` | any | Precondition check idiom. |

See `/moonbit-error-handling` skill for full conventions.

---

## Analysis / Pattern Matching

**Want:** Hold snapshot-bound analysis results, convert provider byte offsets to UTF-16, or render facts as decorations.

| API | Location | Notes |
|-----|----------|-------|
| `SourceSnapshot` | `lib/analysis/` | Doc identity: doc_id + version + 32-bit text_hash + utf16_len. Constructed from source text — do not build field-by-field. |
| `SourceSnapshot::SourceSnapshot(doc_id~, version~, source~)` | `lib/analysis/` | Computes text_hash and utf16_len from source string. |
| `SourceSnapshot::matches(other)` | `lib/analysis/` | Full identity check (all four fields). Stale-result gate. |
| `PatternMatchFact` | `lib/analysis/` | Snapshot-bound match: UTF-16 from/to, pattern_id, captures map. |
| `PatternMatchFact::is_current(snapshot)` | `lib/analysis/` | Returns false when fact's snapshot differs from current by doc_id, version, hash, or length. |
| `byte_offset_to_utf16(source, byte_offset)` | `lib/analysis/` | Adapter-boundary conversion: ast-grep UTF-8 byte offset → UTF-16 code units. Call only at the adapter boundary. |
| `AstGrepMatch` | `analysis_bridge/` | Named input type for ast-grep results (byte_start, byte_end, pattern_id). FFI-safe — prefer over bare tuples. |
| `from_ast_grep_matches(matches, source, snapshot)` | `analysis_bridge/` | Converts `Array[AstGrepMatch]` → `Array[PatternMatchFact]` via byte→UTF-16 at the boundary. |
| `facts_to_decorations(facts, snapshot)` | `analysis_bridge/` | Filters stale facts, maps current ones to `protocol.Decoration` with css_class and data. |
| `facts_to_match_list(facts, snapshot)` | `analysis_bridge/` | Filters stale facts, maps current ones to `MatchListEntry` (from, to, pattern_id) for jump UI. |

**Do not:** Pass ast-grep byte offsets directly to decorations — convert at the adapter boundary with `byte_offset_to_utf16` first. Do not add raw source text or source-map generation to `SourceSnapshot` before Phase 2.

---

## Standard Search Commands

```bash
# Find a type or function by name
NEW_MOON_MOD=0 moon ide doc "TypeName::*method*"
NEW_MOON_MOD=0 moon ide peek-def SymbolName

# See all public APIs in a package
NEW_MOON_MOD=0 moon ide outline core
NEW_MOON_MOD=0 moon ide outline editor
NEW_MOON_MOD=0 moon ide outline protocol
NEW_MOON_MOD=0 moon ide outline projection
NEW_MOON_MOD=0 moon ide outline relay

# Find all usages of a symbol
NEW_MOON_MOD=0 moon ide find-references SymbolName
```
