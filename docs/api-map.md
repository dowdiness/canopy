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
| `ProjNode::leaf(kind, syntax_node, counter)` | `core/` | Fresh childless projection node spanning a `SyntaxNode`. Preferred for CST leaf projections. |
| `ProjNode::branch(kind, start, end, children, counter)` | `core/` | Fresh projection node with explicit span and children. Use `ProjNode::new` only when preserving/reusing a known ID. |

**Do not:** Create parallel `id: Int` fields or ad-hoc node numbering.

---

## Source Map / Position Lookup

**Want:** Map node IDs to text ranges, or find nodes at a cursor position.

| API | Location | Notes |
|-----|----------|-------|
| `SourceMap` | `core/` | Canonical position index. One per editor instance. |
| `SourceMap::new()` | `core/` | Constructor. |
| `SourceMap::get_range(node_id)` | `core/` | `Range?` for a node. |
| `SourceMap::nodes_at_position(pos)` | `core/` | All nodes covering a position. |
| `SourceMap::innermost_node_at(pos)` | `core/` | Deepest node at cursor. Use for hover/click. |
| `SourceMap::nodes_in_range(range)` | `core/` | All nodes overlapping a range. |
| `SourceMap::apply_edit(edit)` | `core/` | Update ranges after a text edit. Call this, don't rebuild. |
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

**Do not:** Build a parallel view representation outside `ViewNode`/`protocol/`.

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
