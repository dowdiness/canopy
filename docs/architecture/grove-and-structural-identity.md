# Grove and Structural Identity

**Reference:** Adams et al., "Grove: A Bidirectionally Typed Collaborative Structure Editor Calculus" (POPL 2025). https://doi.org/10.1145/3704909

## Two Philosophies of Truth

There are two fundamentally different ways to build a collaborative editor around an AST:

**Text-first (Canopy).** Text is ground truth. The AST is derived via parsing. Structural edits are sugar for text edits — they compute a text transformation, apply it through the CRDT, and let the parser rebuild the tree. Collaboration happens at the character level.

**Structure-first (Grove).** The graph is ground truth. Text is a projection (pretty-printing). Edits are graph patches — edge insertions and deletions applied directly to a structural CRDT. There is no parser in the loop. Collaboration happens at the node level.

Each philosophy has a characteristic strength and a characteristic weakness:

| | Text-first | Structure-first |
|---|---|---|
| Free-form typing | Unobstructed — type anything, parser recovers | Constrained — every keystroke must map to a graph patch |
| Structural identity | Fragile — positional matching loses identity across reshaping | Permanent — vertex UIDs survive all transformations |
| Conflict representation | Absorbed into text merge (often lost) | First-class syntax (holes, local conflicts, relocation refs) |
| Language generality | Any language with a parser | Any language with a constructor grammar |

---

## The Grove Calculus

Grove's core data structure is a directed labeled multi-graph:

- **Vertices** have permanent unique identifiers and constructors. A vertex, once created, is never destroyed — it can only be disconnected by deleting its incoming edges.
- **Edges** have unique identifiers, position labels, and a state that progresses irreversibly: not-yet-constructed → live → deleted. This irreversibility is what makes patches commute.
- **Patch language** has only two operations — edge insertion and edge deletion — forming a 2P-Set CmRDT. Any two patches commute. No operational transform, no three-way merge.

Structural edits translate to patches:
- **Wrapping** = delete the edge to the original node, create a wrapper vertex, insert edges from parent to wrapper and from wrapper to original. The original vertex keeps its UID.
- **Deletion** = delete the incoming edge. The vertex persists (orphaned but recoverable).
- **Relocation** = delete old edge, insert new edge. Atomic — the vertex never disappears.

The multi-graph may contain conflicts: multiple edges at one position (local conflict), multiple incoming edges to one vertex (relocation conflict), or cycles (from concurrent relocations). **Decomposition** produces a *grove* — a set of well-formed trees where conflicts appear as first-class syntactic constructs (conflict markers, relocation references, unicycle references) that the type system and editor UI can reason about.

---

## Why This Matters for Canopy

### The identity problem

Canopy's reconciliation assigns node identities by matching old and new trees positionally, using constructor equality. When a structural edit changes the constructor at a position (wrapping adds a level, unwrapping removes one), reconciliation can't match old nodes to new nodes. All identities in the affected subtree are lost.

This matters because node identity is the anchor for:
- Zipper position persistence across the text roundtrip
- Hole metadata (creation context, expected type)
- UI state (collapsed nodes, selection, editing focus)
- Future: undo history, collaborative structural conflict detection

Grove avoids this entirely — vertex UIDs are permanent, assigned at creation, independent of tree position.

### The roundtrip problem

In text-first architecture, structural edits must survive a text roundtrip: edit → text change → CRDT op → reparse → new tree. The roundtrip can change tree shape (error recovery, parse ambiguity), breaking positional identity.

In structure-first architecture, there is no roundtrip. Edits modify the graph directly. The grove (tree view) is deterministically recomputed. The cursor's target vertex still has its UID.

### The conflict problem

When two users concurrently perform structural edits (one wraps a node, the other deletes it), text-level CRDTs produce a merged text that may not reflect either user's intent. The conflict is invisible — absorbed into the text merge.

Grove represents conflicts explicitly: local conflicts show competing children at one position, relocation references show nodes that were moved to conflicting locations, unicycle references break concurrent cyclic relocations. Users resolve these through normal editing, and the type system continues to operate on the conflicted state.

---

## Incremental Adoption Path

The gap between text-first and structure-first need not be crossed in one step:

### Level 0: Positional identity (current)

Reconciliation matches nodes by constructor and position. The cursor is a stable node identity; the Zipper is a transient computation constructed on demand for navigation and context. After structural edits, the tree cursor follows the text cursor (which the existing edit handlers position via FocusHint). Acceptable when structural editing is single-user.

### Level 1: Edit-aware reconciliation

Pass the edit action to reconciliation as a hint. For wrapping, reconciliation knows to look inside the wrapper for the original subtree. For unwrapping, it knows which child was promoted. Identity is preserved across the specific edit, though not across concurrent remote edits.

This borrows Grove's key insight — edits carry identity information that blind diffing discards — without adopting the graph CRDT.

### Level 2: Structural CRDT

Replace or supplement the text CRDT with a graph-based structural CRDT (Grove's 2P-Set model or equivalent). Structural edits become native graph patches with permanent vertex identity. Text editing either goes through a text-to-graph bridge or operates on a separate text CRDT for leaf content.

This is the point where Grove's architecture applies directly. It enables collaborative structural editing, explicit conflict representation, and type-aware conflict resolution.

---

## When to Move Along This Path

Level 0 is sufficient when:
- Structural editing is single-user (Zipper is a local UI affordance)
- Collaboration happens at the text level only
- Identity loss after structural edits is rare and tolerable (Hole support makes it so)

Level 1 becomes valuable when:
- Structural edits frequently cause identity loss that disrupts UX (expanded/collapsed state, selection, undo)
- Edit-aware reconciliation is a localized change (hint parameter, not an architectural shift)

Level 2 becomes necessary when:
- Multiple users need to perform concurrent structural edits with meaningful merge
- Conflict resolution needs to be visible and resolvable through normal editing
- The editor needs to guarantee that language services work on every collaboration state
