# Block Editor: Project Vision

**Date:** 2026-03-28
**Status:** Conceptual design — not an implementation plan
**Reference:** Thymer (thymer.com) — IDE-like, keyboard-driven, local-first, real-time collaboration

> This document captures the product vision and architectural direction. Open questions are listed honestly — several must be resolved before implementation planning begins. See [documentation doctrine](../development/documentation-doctrine.md) for how this doc relates to architecture docs and implementation plans.

## What We're Building

A block-based document editor for small teams. Local-first, real-time collaboration, no lock-in. Documents are Markdown files on disk, edited as structured blocks in the UI.

Built on Canopy's existing architecture: eg-walker CRDTs, Loom incremental parsing, projectional editing via ProjNode[T], Rabbita UI framework.

## Product Principles

These emerged from our brainstorming and should guide every implementation decision:

1. **Typing is the lowest-friction input.** Block structure emerges from typing (`# `, `- `, ``` ` ` ` ```), not from menus or mode switches. The flow state is sacred.

2. **Trust comes from transparency.** Documents are `.md` files. Open them in vim, grep across them, git diff them. No proprietary format, no lock-in anxiety.

3. **Non-text is additive, never subtractive.** Images, tables, embeds enhance the experience. They never add cognitive or mechanical debt. A user who only knows basic Markdown can use the app without learning anything new.

4. **Structure serves the user, not the architecture.** The user thinks in blocks. The architecture should make block operations (move, nest, convert, delete) feel instant and safe, even under concurrent editing.

## Architecture Direction

### Three layers

```
UI              Renders blocks, handles input, Markdown shortcuts, slash commands
                    |
Document Model  MovableTree CRDT (structure) + FugueMax CRDT (per-block text)
                    |
Serialization   Import/export Markdown files
```

**Document model is the runtime source of truth.** During editing and collaboration, the tree CRDT and per-block text CRDTs are authoritative. Markdown is a serialization format for storage and interchange.

### Why two CRDTs

**Block structure** needs a tree CRDT because block operations (reorder, nest, move) are fundamentally tree mutations. Text cut-and-paste can't safely handle concurrent block moves — Kleppmann's algorithm can. Sibling ordering uses fractional indexing (Loro-style) for conflict-free insertion between blocks.

**Block content** needs text CRDTs because inline editing is fundamentally character-level. Each text-bearing block owns a FugueMax instance from eg-walker. This is what Canopy already does well.

**Joint invariant model (resolved):** Following Loro's approach, all containers (tree + per-block text CRDTs) live inside a **single document with a unified version vector and oplog**. They are not independent CRDTs — they share causal history. This guarantees document-level convergence.

- **Delete block while another peer edits its text:** Delete = move to a TRASH node (Kleppmann's model). Text edits on deleted blocks are preserved in the oplog, not rejected. If the block is restored via undo, the text edits surface. **Durability caveat:** TRASH content exists only in the CRDT oplog, not in the `.md` file. If the sidecar is lost, TRASH content is lost. This is acceptable — TRASH is a collaboration-session concept, not a persistence guarantee. The `.md` always reflects the visible document state.
- **Create block with initial text:** Two operations (tree create + text insert) grouped in a single commit/transaction. Causal delivery ensures a peer won't see the text insert without first seeing the node creation. Not atomic at the CRDT level, but atomic for event emission and undo.
- **Known risk:** Yjs has an open bug (#642) where undoing compound operations across nested types causes peer divergence. This pattern needs extensive testing in our implementation.

### Why Markdown serialization

- **No lock-in:** `.md` files work everywhere
- **Interoperability:** Import from Obsidian, Typora, any Markdown tool
- **Git-friendly:** Diffs, history, branching all work naturally
- **Trust signal:** Users can verify their data is portable at any time

**Round-trip expectations:** For a defined "supported subset" of Markdown (CommonMark + GFM tables + directives), we target `parse(export(model)) ≈ model` — the model survives a round-trip through Markdown, where "≈" means structural equivalence after normalization (e.g., `- ` and `* ` both produce a bullet list item, and export always emits `- `). We do NOT promise `export(import(md)) == md` byte-for-byte. Unsupported syntax is preserved as opaque raw blocks; editing an opaque block promotes it to a structured block (losing the original byte representation). The normalization rules and model equality definition are open questions.

### Inline formatting strategy

Start with **Markdown syntax in FugueMax text** — bold is `**text**` in the CRDT, hidden by the UI. This avoids building Peritext (a rich text CRDT) upfront.

Known limitation: concurrent formatting on overlapping ranges can produce syntactically broken Markdown. Loom's error recovery prevents crashes but doesn't preserve intent. This is acceptable for small team use (rare edge case) and can be upgraded to Peritext later if needed.

## Block Model (resolved)

### Container semantics: standalone items, no list containers

Following Notion and BlockNote, blocks are **standalone nodes with a `type` property**. There are no list-container or quote-container wrapper nodes. This is the industry-validated approach for tree CRDTs.

**Why this wins for a movable tree CRDT:**
- **Move = one tree op.** Moving a list item is one CRDT operation. Container models require multi-step transactions (move item + handle empty container).
- **No empty-container problem.** In a CRDT, auto-deleting empty containers is unsafe — another peer might concurrently be adding children. Standalone items eliminate this class of bug entirely.
- **Type change = property change.** Converting a bullet item to a paragraph is `set_property(type, paragraph)`, not a tree restructure.
- **Concurrent merge quality.** Two users both creating list items just create nodes with the same type. Container models create duplicate containers needing post-merge fixup.

**Visual grouping via run detection:** The renderer groups consecutive sibling blocks with the **same `type` AND same `style`** into visual lists (e.g., consecutive blocks with `type: listItem, style: bullet` render as one `<ul>`, while adjacent `style: numbered` blocks render as a separate `<ol>`). This is O(n) in siblings — trivially cheap. A bullet item adjacent to a numbered item produces two separate visual lists, not one mixed list.

**Ordered-list numbering** is a run-level rendering concern, not a per-item property. The first item in a numbered run renders as `1.` (or whatever the Markdown `start` attribute was on import); subsequent items auto-increment. On import, if the Markdown source has `3.` as the first item, the run starts at 3. On export, only the first item's start number is emitted; subsequent items use auto-numbering. There is no per-item `start` property — `start` is computed by the renderer from the run's first item position in the source Markdown. This avoids conflicts when concurrent edits reorder numbered items.

**Exceptions:**
- **Tables** are containers: `table > table_row > cells`. Tables have fixed structure that doesn't change type.
- **Toggle/collapsible** blocks are standalone with a `collapsed: bool` property. Children are tree children. No special container.

### Block types

#### Core (standard Markdown)

| Type | Markdown | Tree structure |
|---|---|---|
| Paragraph | Plain text | Leaf (text CRDT) |
| Heading | `# ` through `###### ` | Leaf (text CRDT + level property) |
| List item | `- `, `1. `, `- [ ] ` | Leaf or parent (text CRDT; properties: `style` (bullet/numbered/todo), `checked` (bool, todo only); children = any block type) |
| Quote | `> ` | Leaf or parent (text CRDT; children = any block type) |
| Code | ` ``` ` | Leaf (text CRDT + language property; Loom parses for syntax) |
| Divider | `---` | Leaf (no text CRDT) |

#### Extended (need Markdown extensions or conventions)

| Type | Serialization | Tree structure |
|---|---|---|
| Image | `![alt](src)` | Leaf (no text CRDT; src/alt as properties) |
| Table | GFM pipe tables | Container: table > table_row > cells (text CRDTs per cell) |
| Callout | `:::type ... :::` | Parent (style property; children = nested blocks) |
| Toggle | TBD | Parent (collapsed property; children = nested blocks) |
| Embed | TBD | Leaf (url property) |

#### Raw/opaque block (interoperability)

| Type | Serialization | Tree structure |
|---|---|---|
| Raw | Original Markdown bytes, verbatim | Leaf (text CRDT holding the original source) |

When the Markdown importer encounters syntax it doesn't recognize (HTML blocks, footnote definitions, custom extensions from other tools, etc.), it creates a `raw` block that preserves the original bytes verbatim in its text CRDT. The renderer displays raw blocks as monospace pre-formatted text (or collapsed with a "raw Markdown" label). On export, the raw block's text CRDT content is emitted unchanged. Editing a raw block's content is allowed but does not attempt to re-parse it into a structured block — the user can convert it manually via slash commands or type changes.

Block types without standard Markdown serialization (toggle, embed) should be deferred until the core block types work.

## How Canopy's Architecture Maps

The key insight: Canopy's incremental hylomorphism pipeline transfers directly. The type parameter changes from `@ast.Term` (lambda calculus) to `BlockType` (document blocks).

```
Document model
    | anamorphism (unfold block tree → ProjNode[BlockType])
ProjNode[BlockType]
    | catamorphism (fold ProjNode → rendered blocks)
UI
```

### What transfers — with caveats

The existing components are reusable in concept, but this is an architectural fork, not a retargeting exercise. Canopy today has a single text CRDT as ground truth with tree edits round-tripping through text. This proposal replaces that with a multi-CRDT document model. The mental models and algorithms transfer; the integration code largely does not.

- **eg-walker / FugueMax** → per-block text CRDT (algorithm unchanged, but now N instances per document instead of one)
- **Loom** → incremental parsing for inline Markdown + code syntax highlighting (framework unchanged, new grammars needed)
- **ProjNode[T]** → ProjNode[BlockType] (generic structure transfers, but the unfold logic is entirely new)
- **TreeEditorState** → block selection, drag-drop, collapsed state (concepts transfer, implementation needs rework for tree CRDT)
- **EphemeralHub** → peer cursors and presence (needs extension for per-block cursor tracking)
- **Rabbita** → block rendering (framework transfers, all renderers are new)

### What's new

- **MovableTree CRDT** — Kleppmann's algorithm for block structure. This is the biggest new component.
- **FractionalIndex** — sibling ordering. Needs a concrete replicated indexing scheme, not just "insert between two floats."
- **Markdown grammar for Loom** — parse/serialize `.md` files
- **Block renderers** — per-block-type UI components
- **Document type** — unified wrapper coordinating tree CRDT + per-block text CRDTs
- **Cross-CRDT undo** — UndoManager needs to span tree ops + text ops atomically

## Resolved Decisions

These were blocking open questions, now answered through research into Loro, Yjs, Automerge, Notion, BlockNote, ProseMirror, Obsidian, VS Code, and Zed.

### 1. Joint CRDT invariants → unified document model

All containers share a **single document with one version vector and one oplog** (Loro's model). Delete = move-to-TRASH, preserving text edits on deleted blocks. Create-with-initial-text = two ops in one commit, causally ordered. See "Why two CRDTs" section above for details.

### 2. Container semantics → standalone items, no list containers

Blocks are standalone tree nodes with a `type` property (Notion/BlockNote model). No list or quote containers. Run detection groups consecutive same-type siblings for rendering. Tables are the exception (container with row children). See "Block Model" section above for details.

### 3. External file authority → dual persistence with sidecar

No production system persists both Markdown and CRDT state as a coordinated pair. This is novel, but the pattern is analogous to Git (working tree + `.git/` object store).

```
On disk:
  document.md              — human-readable Markdown (always current)
  .canopy/document.crdt    — CRDT binary state (sidecar)
```

**Durability contract — what lives where:**

| State | Durable in `.md`? | In `.crdt` sidecar? | On sidecar loss |
|---|---|---|---|
| Visible block tree + content | Yes | Yes | Rebuilt from `.md` |
| Block properties (type, style, level, etc.) | Yes (encoded in Markdown syntax) | Yes | Rebuilt from `.md` |
| CRDT operation history + version vectors | No | Yes | Lost — fresh CRDT |
| TRASH (deleted blocks with preserved edits) | No | Yes | Lost |
| Undo/redo stack | No | Yes (or session-only) | Lost |
| Peer cursors / presence | No | No (ephemeral) | N/A |

**Flows:**

- **Save:** Write `.md` first (temp file + rename), then write `.crdt` (temp file + rename). Order matters: if the process crashes between the two writes, the `.md` is current and the `.crdt` is stale — the safe direction. The two files are NOT atomically paired. A stale `.crdt` is detected on next load via divergence check and corrected.
- **Load with sidecar:** Load `.crdt` for full CRDT state. Export CRDT to normalized Markdown. Compare against the `.md` file on disk (text diff, not model comparison — avoids the normalization problem). If they match: ready. If they diverge: the `.md` has been externally edited. Apply the text diff as block-level synthetic operations from a reserved "filesystem peer" agent ID (see reconciliation below). These synthetic ops are NOT undoable by the user — they represent external reality.
- **Load without sidecar** (file from git, email, etc.): Parse `.md`, create fresh CRDT. Collaboration history starts fresh.
- **External file change** (file watcher): Same as load-with-sidecar divergence path. Debounce to avoid self-triggered loops (ignore file changes within 1s of our own save). The watcher pauses during save and resumes after.
- **`.gitignore` policy:** `.canopy/` is gitignored — it's cache, not source of truth. `.md` files are committed. Losing `.canopy/` loses collaboration history but preserves all content. Analogous to `node_modules/` vs `package.json`.

**Reconciliation on external `.md` change:**

When the `.md` diverges from the CRDT, we need to ingest external changes into the multi-CRDT document model. V1 approach: **re-import, not diff.**

1. Parse the new `.md` into a fresh block tree (using Loom's Markdown grammar).
2. Parse the CRDT's current exported Markdown into a block tree (same grammar).
3. Run a **block-level structural diff** between the two trees: match blocks by position + content similarity (not CRDT identity). Produce a list of: added blocks, deleted blocks, changed blocks (content or properties), moved blocks.
4. Translate each diff entry into CRDT operations on the live document:
   - **Added block:** `tree.create(parent, position, type)` + `text.insert(content)` as "filesystem peer"
   - **Deleted block:** `tree.move(block, TRASH)` as "filesystem peer"
   - **Changed content:** character-level diff on the block's text, applied as insert/delete ops to that block's FugueMax instance
   - **Changed properties:** `tree.set_property(block, key, value)` as "filesystem peer"
   - **Moved block:** `tree.move(block, new_parent, new_position)` as "filesystem peer"

This is coarse — block matching by position is heuristic, and a fully rewritten block looks like delete + create (losing that block's CRDT history) — but it correctly translates external Markdown edits into the native tree + per-block text CRDT operations. Block-identity-preserving reconciliation (e.g., content-hash fingerprinting) is a future optimization.

**Key invariant:** `.md` is always authoritative for visible content. `.crdt` is an acceleration layer that can be rebuilt. If they conflict, trust the `.md`.

### 4. Undo across CRDTs → document-level undo with transaction grouping

Following Loro's model:
- **UndoManager operates at the document level**, not per-container. One undo stack for all tree ops + text ops.
- **Transaction grouping:** Multi-op user actions (e.g., convert paragraph to heading = `set_property` + text edit) are wrapped in `groupStart()`/`groupEnd()`. Everything in the group is one undo step.
- **Time-based merging:** Rapid sequential edits within a merge interval (~1000ms) collapse into one undo step.
- **Local undo only:** Undo reverts your own operations. Other peers' edits are preserved. From their perspective, your undo looks like a normal edit.
- **Undo creates new operations,** not rollbacks. This preserves CRDT convergence guarantees.

## Remaining Open Questions

These can be resolved during implementation. None are architectural blockers.

1. **Split view authority.** Rabbita has a text view + tree view today. A Markdown source pane is mechanically different — it's a serialization of many CRDTs, not a single text CRDT. Is it read-only? Editable (implies a re-import path)? Deferred until core editing works?

2. **Extended block serialization.** Toggle, embed, and other non-standard blocks need a Markdown convention. Directive syntax (`:::`)? HTML comments? Custom fenced blocks?

3. **Fractional index scheme.** The concrete key representation, tie-break rules for concurrent inserts at the same position, and growth/compaction strategy.

4. **Model equality and normalization.** What counts as "same model" after parse → export → parse? How are equivalent Markdown representations (e.g., `*` vs `-` bullets) normalized? When does an opaque raw block become structured? Note: the file-authority reconciliation sidesteps this by diffing at the Markdown text level, but normalization still matters for round-trip quality assertions.

5. **Block-identity-preserving reconciliation.** V1 uses text-level diff for external `.md` changes, which means external block moves look like delete + insert (losing per-block CRDT history). A future optimization could use LCS matching on block content hashes to detect moves and preserve identity. Not needed for v1.

6. **First end-to-end slice.** What is the minimal vertical cut that proves the architecture works? Candidate: paragraph + heading + list, single peer, save/load as Markdown, no collaboration. This should be defined before implementation planning.

## Non-Goals

- User accounts, permissions, workspaces
- Database/relational features (Notion-style databases)
- Plugin/extension system
- Mobile-native support
- Byte-exact Markdown round-trip

## References

### CRDT algorithms
- [Kleppmann — A highly-available move operation for replicated trees](https://martin.kleppmann.com/papers/move-op.pdf)
- [Loro — Movable tree CRDTs and Loro's implementation](https://loro.dev/blog/movable-tree)
- [Loro — Tree CRDT documentation](https://www.loro.dev/docs/tutorial/tree)
- [Loro — Undo/redo documentation](https://loro.dev/docs/advanced/undo)
- [Loro — Persistence documentation](https://loro.dev/docs/tutorial/persistence)
- [Made by Evan — CRDT: Mutable Tree Hierarchy](https://madebyevan.com/algos/crdt-mutable-tree-hierarchy/)
- [eg-walker paper](https://arxiv.org/abs/2409.14252)
- [Stewen & Kleppmann — Undo and Redo Support for Replicated Registers (PaPoC 2024)](https://arxiv.org/abs/2404.11308)
- [Bauwens & Gonzalez Boix — Nested Pure Operation-Based CRDTs (ECOOP 2023)](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ECOOP.2023.2)

### Block editor data models
- [Notion API — Block reference](https://developers.notion.com/reference/block)
- [Notion — Data model behind Notion](https://www.notion.com/blog/data-model-behind-notion)
- [BlockNote — Document structure](https://www.blocknotejs.org/docs/editor-basics/document-structure)
- [ProseMirror — Guide](https://prosemirror.net/docs/guide/)
- [BlockSuite — Working with Block Tree](https://block-suite.com/guide/working-with-block-tree.html)
- [Fluid Framework — Undo/redo and transactions](https://fluidframework.com/docs/data-structures/tree/undo-redo)

### File authority and persistence
- [Zed — How CRDTs make multiplayer text editing part of Zed's DNA](https://zed.dev/blog/crdts)
- [Tonsky — Local, first, forever (crdt-filesync)](https://tonsky.me/blog/crdt-filesync/)
- [Ink & Switch — Local-first software](https://www.inkandswitch.com/essay/local-first/)

### Reference product
- [Thymer](https://thymer.com/) — IDE-like, keyboard-driven, local-first editor
