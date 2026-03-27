# Block Editor Design: Notion-like App from Canopy

**Date:** 2026-03-28
**Status:** Draft
**Reference:** Thymer (thymer.com) — IDE-like, keyboard-driven, local-first, real-time collaboration

## Goal

Build a block-based document editor on top of Canopy's existing CRDT and incremental parsing infrastructure. Small team collaboration. Mixed media blocks (rich text, code, images, tables, embeds). Local-first with no lock-in — documents are Markdown files.

## Non-Goals

- User accounts, permissions, workspaces (out of scope)
- Database/relational features (Notion tables-as-databases)
- Plugin/extension system
- Mobile support

## Architecture: Three Layers

```
Layer 3: UI (Rabbita / React)
         Renders blocks, handles input, drag-drop, slash commands
              |
Layer 2: Document Model (Block Tree + Block Content)
         MovableTree CRDT (structure) + FugueMax CRDT (per-block text)
              |
Layer 1: Serialization (Markdown)
         Import/export to .md files
```

Layer 2 is the source of truth at runtime. Markdown is a serialization format for storage and interchange. The UI never talks to the Markdown layer directly — it only talks to the document model.

## Layer 1: Serialization (Markdown)

### Import (parse .md -> block tree)

A new Loom grammar for Markdown. Parses a `.md` file into a CST, then a fold pass converts it into a block tree. Each block becomes a tree CRDT node with its own FugueMax text CRDT initialized from the block's text content.

Mapping:

| Markdown syntax | Block |
|---|---|
| `# Heading` | `{ type: heading, level: 1, text: "Heading" }` |
| `Paragraph text` | `{ type: paragraph, text: "Paragraph text" }` |
| `- Item` | `{ type: list_item, style: bullet, text: "Item" }` |
| `1. Item` | `{ type: list_item, style: numbered, text: "Item" }` |
| `- [ ] Task` | `{ type: list_item, style: todo, checked: false, text: "Task" }` |
| `` ```lang ... ``` `` | `{ type: code, lang: "lang", text: "..." }` |
| `![alt](src)` | `{ type: image, src: "src", alt: "alt" }` |
| `> Quote` | `{ type: quote, children: [...] }` |
| `---` | `{ type: divider }` |
| `\| a \| b \|` (GFM table) | `{ type: table, children: [rows...] }` |
| `:::note ... :::` | `{ type: callout, style: "note", children: [...] }` |

### Export (block tree -> .md)

Walk the tree in order. Each block type has a serializer. Nesting is represented by indentation (lists) or container syntax (quotes, callouts).

### Round-trip invariant

`export(import(markdown)) == markdown` for all supported syntax. Unsupported syntax passes through as a raw text block — nothing is ever lost.

### When serialization happens

- **Save:** Auto-save or manual save -> export to `.md` file on disk
- **Load:** Open a file -> import from `.md` -> initialize block tree + text CRDTs
- **Never during collaboration** — peers sync CRDT operations, not Markdown text

## Layer 2: Document Model

Two CRDTs working together.

### 2a: MovableTree CRDT (block structure)

Based on Kleppmann's "A highly-available move operation for replicated trees" algorithm, with Loro-style fractional indexing for sibling ordering.

```
BlockNode {
  id : BlockId              // globally unique (agent_id, lamport_timestamp)
  block_type : BlockType    // heading, paragraph, code, image, ...
  properties : Map[String, Value]  // level, lang, src, checked, style...
}
```

Tree operations (all CRDT-safe under concurrency):
- `create(parent, position, block_type)` — insert new block
- `move(node, new_parent, new_position)` — reorder or nest
- `delete(node)` — tombstone a block
- `set_property(node, key, value)` — change type, level, language, etc.

Sibling ordering via fractional indexing. Inserting between positions 0.25 and 0.5 creates 0.375 — no renumbering.

Concurrent move safety via Kleppmann's undo-do-redo:
1. Operations totally ordered by Lamport timestamp
2. Out-of-order remote ops: undo back, apply, redo forward
3. Cycle-creating moves silently dropped
4. All replicas converge — formally proven correct

### 2b: FugueMax Text CRDT (per-block content)

Each text-bearing block owns a FugueMax CRDT from eg-walker.

```
BlockContent {
  text : TextDoc           // FugueMax CRDT
}
```

Inline formatting (bold, italic, code, links): stored as Markdown syntax characters within the FugueMax text. The UI hides markers and renders styled text. Toggling bold = inserting/removing `**` characters.

This avoids needing a Peritext-style rich text CRDT. FugueMax handles all inline content. Concurrent formatting edge cases (overlapping bold ranges) are handled by Loom's error recovery during re-parse. Peritext can be added later if this proves insufficient.

### 2c: Document (unified type)

```
Document {
  id : DocId
  tree : MovableTree[BlockNode]         // block structure CRDT
  contents : Map[BlockId, BlockContent]  // per-block text CRDTs
  metadata : Map[String, Value]          // title, created, modified
}
```

### Sync protocol

```
SyncMessage {
  tree_ops : Array[TreeOp]                  // block create/move/delete/set_property
  text_ops : Map[BlockId, Array[TextOp]]    // per-block insert/delete
  ephemeral : EphemeralState                // cursors, presence (not persisted)
}
```

Peers exchange SyncMessages. Tree ops applied with Kleppmann's cycle check. Text ops applied with FugueMax merge. Convergence guaranteed by both CRDTs independently.

## Layer 3: UI

### Block rendering pipeline

Canopy's existing hylomorphism, with T = BlockType instead of @ast.Term:

```
Document (tree CRDT + text CRDTs)
    | anamorphism (unfold tree -> ProjNode)
ProjNode[BlockType]
    | catamorphism (fold ProjNode -> HTML)
Rendered blocks (UI)
```

### Block types and renderers

| Type | Interaction | Creation shortcut |
|---|---|---|
| paragraph | Click to edit, type naturally | Default (just type) |
| heading | Larger text, level 1-6 | `# ` at line start |
| bulleted_list | Bullet points, Tab to nest | `- ` or `* ` |
| numbered_list | Numbered items, Tab to nest | `1. ` |
| todo_list | Checkbox items | `[ ] ` |
| toggle | Collapsible section with children | Slash command |
| quote | Styled block with left border | `> ` |
| callout | Colored container with icon | Slash command |
| code | Syntax highlighted, language selector | ` ``` ` |
| image | Inline display, click to resize | Paste/drop, or slash command |
| table | Grid editing, Tab between cells | Slash command |
| divider | Horizontal rule | `---` |
| embed | URL preview card | Paste URL, or slash command |

### Input handling

**Typing flow:**
1. User types in a block -> FugueMax text insert ops
2. Loom incrementally parses block text (inline formatting or code syntax)
3. ProjNode updates -> UI re-renders that block only
4. Other blocks untouched (incremental)

**Markdown shortcuts (zero learning curve):**
Type the syntax prefix at the start of a block -> detected by input handler -> translated to tree CRDT operations (set_property for type conversion, create for new blocks).

**Slash commands (progressive disclosure):**
Type `/` -> fuzzy-searchable command palette -> insert block of chosen type. For block types with no Markdown shortcut (image, table, embed) or for users who don't know shortcuts.

**Block operations:**
- Enter at end of block -> create new block after current
- Backspace at start of empty block -> delete block
- Tab -> move block deeper (nest under previous sibling)
- Shift+Tab -> move block shallower (unnest)
- Drag handle -> move block to drop target (tree CRDT move op)
- Cmd+Shift+Up/Down -> move block up/down among siblings

**Split view (Canopy's unique strength):**
- Left: rendered blocks (primary editing experience)
- Right: Markdown source (live-updating, editable)
- Changes in either side propagate through the document model
- Same pattern as Rabbita's current tree view + text view

## Component Mapping

### Reused from Canopy (unchanged or minor adaptation)

| Component | Role |
|---|---|
| eg-walker / FugueMax | Per-block text CRDT |
| Loom (framework) | Incremental parser for inline formatting + code blocks |
| ProjNode[T] | ProjNode[BlockType] — same generic, new type parameter |
| SourceMap | Maps block IDs to Markdown source spans (for split view) |
| TreeEditorState | Block selection, drag-drop, collapsed toggles |
| EphemeralHub | Peer cursors and presence |
| Rabbita | Block rendering framework (extend with new renderers) |
| UndoManager | Extend to handle tree ops + text ops together |

### New components to build

| Component | Purpose |
|---|---|
| MovableTree CRDT | Kleppmann's algorithm for block structure |
| FractionalIndex | Sibling ordering within the tree |
| Markdown grammar (Loom) | Parse/serialize .md files |
| Block renderers | Per-block-type UI components |
| Slash command palette | Block type insertion UI |
| Document type | Unified wrapper over tree + contents |
| Sync coordinator | Multiplexes tree ops + text ops into SyncMessage |

## Key Design Decisions

1. **Text-as-Markdown for inline formatting (not Peritext):** Start with Markdown syntax in FugueMax text. Simpler, leverages existing infrastructure. Upgrade to Peritext later if concurrent formatting conflicts become a real problem.

2. **Movable tree CRDT for block structure (not text surgery):** Block reordering, nesting, and moving are first-class tree operations with formal correctness guarantees. No risk of duplicated or lost blocks under concurrency.

3. **Markdown as serialization (not runtime format):** The CRDTs are authoritative during editing. Markdown is the storage/exchange format. This gives us both collaboration correctness and no lock-in.

4. **Loom for two parsing jobs:** (a) Markdown grammar for import/export and split-view sync, (b) per-block inline parsing for rich text rendering and code syntax highlighting. Both are incremental.

5. **Block type conversion via property change:** Converting a paragraph to a heading is `set_property(type, heading)`, not structural surgery. Fast and CRDT-safe.

## References

- [Kleppmann — A highly-available move operation for replicated trees](https://martin.kleppmann.com/papers/move-op.pdf)
- [Loro — Movable tree CRDTs and Loro's implementation](https://loro.dev/blog/movable-tree)
- [Made by Evan — CRDT: Mutable Tree Hierarchy](https://madebyevan.com/algos/crdt-mutable-tree-hierarchy/)
- [Thymer](https://thymer.com/) — reference product
- [eg-walker paper](https://arxiv.org/abs/2409.14252)
