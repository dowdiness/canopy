// Identity-preserving hints for reconciliation across structural edits.
//
// An `IdentityTransform` records, in terms of the PREVIOUS projection tree's
// `NodeId`s, what structural transformation an edit performed. `reconcile`
// consumes it as a grove "Level 1" hint to carry node identity across a
// constructor change at a position (wrap / unwrap / move / rename) — exactly the
// case positional LCS reconciliation loses (see
// docs/architecture/grove-and-structural-identity.md).
//
// The vocabulary is token-agnostic: it names prev-tree topology, not the
// identity token. Today identity is the ProjNode `NodeId`; a future EntityId /
// match_entities layer can consume the same hints unchanged.

///|
/// A structural-edit hint, expressed against the previous projection tree.
pub(all) enum IdentityTransform {
  /// `inner` (a prev subtree) becomes a child of a newly introduced wrapper.
  /// `inner` and its descendants keep their identity; the wrapper is fresh.
  Wrap(inner~ : NodeId)
  /// `wrapper` is removed and the subtree `keep` is promoted in its place.
  /// `keep` and its descendants keep identity; `wrapper` retires.
  Unwrap(wrapper~ : NodeId, keep~ : NodeId)
  /// `subtree` is relocated; identity is preserved at the new site.
  Move(subtree~ : NodeId)
  /// `old` is semantically replaced; its identity retires (new node is fresh).
  Replace(old~ : NodeId)
  /// Only a leaf token under `node` changed; `node` and its ancestor spine keep
  /// identity. Closes the unary-chain spine-orphan failure of similarity diffing.
  RenameLeaf(node~ : NodeId)
  /// A fresh subtree is inserted under `parent` at `index`; siblings keep identity.
  InsertSubtree(parent~ : NodeId, index~ : Int)
  /// `node`'s subtree is deleted; its identity retires, siblings keep identity.
  DeleteSubtree(node~ : NodeId)
  /// Raw text / remote / undescribable edit: `reconcile` falls back to LCS.
  Opaque
} derive(Eq, Debug)
