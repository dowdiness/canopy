# Zipper as Transient Lens

## The Design Choice: State vs. Computation

A Zipper describes a position in a tree as a focus plus a path of one-hole contexts from root to that focus. There are two ways to use this in an editor:

**Zipper as state.** Store the Zipper persistently. After every text roundtrip (edit → CRDT op → reparse → new tree), synchronize the stored Zipper to the new tree. This requires a sync mechanism that can fail when the tree shape changes.

**Zipper as computation.** Store only a stable node identifier as the cursor. Construct a Zipper on demand when structural navigation or context information is needed. Discard it after. There is nothing to synchronize.

Canopy uses the second approach. The cursor is a node identity (stable across reparses via reconciliation). The Zipper is a transient lens — constructed, used, and discarded within a single operation.

---

## Why Node Identity Is Primary

Node identities survive text reparses automatically. Reconciliation matches old and new trees by constructor equality and preserves identities for matching nodes. This means:

- A remote user's text edit triggers a reparse. The cursor's node identity still exists in the new tree. No action needed.
- The local user types in the text pane. Same — the node identity survives.
- The user navigates the tree pane with arrow keys. Construct a Zipper from the current node identity, navigate, extract the new focus's node identity, store it.

The only case requiring special handling: structural edits that change the constructor at the cursor position (wrapping, unwrapping, deleting). Reconciliation assigns a fresh identity because the constructor changed. The old identity is gone.

---

## Cursor Relocation After Structural Edits

When a structural edit changes the cursor's constructor, the relocation strategy uses two tiers:

**Fast path:** check if the old node identity still exists in the new tree. If yes, cursor stays. This handles text edits and any edit where the constructor at the cursor position doesn't change. (A leaf edit that changes the constructor — e.g., replacing a variable name with a number — causes a constructor change, so it falls through to the slow path.)

**Slow path:** follow the text cursor. The existing text-edit handlers already encode cursor-after-edit intent — after wrapping in an if-expression, the text cursor moves to the condition hole so the user can immediately type. The tree cursor follows the text cursor via the source map's inverse lookup, ensuring both cursors agree.

This is simpler and more correct than path-index replay because each text-edit handler already knows where the cursor should land after its specific operation.

---

## Why Hole Support Matters

Structural edits modify text that the parser must re-consume. If the modified text triggers error recovery, the reparsed tree can have unexpected shape — different constructors, different nesting, different child counts.

**Hole support makes structural edits roundtrip-safe.** When the placeholder (`_`) is a valid expression everywhere in the grammar, every structural edit produces text that reparses to the expected structure:

- Deletion replaces a span with `_` — valid because Hole is a first-class expression
- Wrapping inserts parenthesized structure around existing text — valid by construction
- Unwrapping extracts exact source text from a child span — valid because it was valid before

Without Hole support, deletion could produce text the parser can't handle, and the reparsed tree would diverge from what the edit intended. With it, the text-edit handlers' FocusHint values land on the expected node — because that node actually exists in the reparsed tree.

This invariant also benefits Zipper construction: when building a transient Zipper from a NodeId via path indices, the tree structure matches the projection tree, so path replay succeeds. The ancestor-walk fallback in `focus_at` covers the remaining edge cases (error recovery during user-typed leaf edits, concurrent remote edits).

---

## Projection Isomorphism

The projection tree that links AST nodes to source spans is structurally isomorphic to the AST by construction:

- Child indices in the Zipper path correspond exactly to child indices in the projection tree
- Error recovery produces concrete leaf nodes that replace missing children — no synthetic wrappers or extra nesting levels
- Reconciliation operates on the projection tree's own children, preserving the one-to-one correspondence

This isomorphism means the bridge between Zipper positions and node identities is always correct: navigate the Zipper, look up the corresponding projection node by child index, extract its identity. The isomorphism holds because the projection builder constructs a mirror-image tree — one projection node per AST node, children in the same order.

**Precondition:** the bridge must use the current projection tree (after the memo chain evaluates), not a stale one from before the text edit.

---

## Hole Identity

When structural edits create placeholder holes, each hole needs stable identity for metadata tracking. The mechanism works in two layers:

**Ephemeral layer.** Holes carry a local integer that exists only between creation and the next reparse. This integer does not survive the text roundtrip — the parser assigns the same value to all holes.

**Stable layer.** After reconciliation, hole metadata is keyed by node identity, not the ephemeral integer. Reconciliation matches any hole with any hole (constructor equality ignores the integer), preserving node identity for holes in the same structural position.

This two-layer design means hole metadata survives the text roundtrip even though the hole's internal integer doesn't.

---

## Multiple Cursors and Remote Presence

Because the cursor is a node identity (one integer), scaling to multiple cursors is straightforward:

- **Multiple selections** for a single user: an array of node identities. The primary selection gets navigation and structural editing. Additional selections are passive highlights.
- **Remote user presence**: a map from user identifier to node identity. Trivial to serialize (one integer per user). Rendered by looking up the source span for each node identity.

A persistent Zipper would make both of these expensive — each cursor would carry a full root-to-focus path, and synchronization would be needed for every cursor after every edit. With node identity as the cursor, there is nothing to synchronize.

---

## The Structural Identity Problem

There is a deeper architectural question: how should an editor maintain identity for AST nodes across structural transformations?

Canopy uses **positional identity** — reconciliation matches nodes by constructor and position. This works well for text edits but poorly for structural edits that change shape. Wrapping a node changes the constructor at that position, causing reconciliation to assign fresh identities to the entire affected subtree.

An alternative is **permanent vertex identity** — every node gets a UID at creation that survives all transformations, including wrapping and relocation. This eliminates the relocation problem entirely but requires a structure-first architecture where edits operate on the graph directly, with no text intermediary. See `grove-and-structural-identity.md` for the full trade-off analysis.

A middle ground — **edit-aware reconciliation** — would pass the edit action to reconciliation as a hint, allowing it to trace identity through structural changes. This borrows the key insight from permanent identity (edits carry identity information that blind diffing discards) without abandoning the text-first architecture. This is a future enhancement path if the current relocation strategy proves insufficient.
