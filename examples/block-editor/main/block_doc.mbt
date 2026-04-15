///|
/// The block identifier type — a tree node ID.
pub type BlockId = @container.TreeNodeId

///|
/// Sentinel for the document root (parent of all top-level blocks).
pub let root_block_id : @container.TreeNodeId = @container.root_id

///|
/// A collaborative block document.
///
/// Wraps a `Document` for block hierarchy and per-block text content.
/// Block ordering delegates to the tree CRDT's fractional indexing.
pub struct BlockDoc {
  priv tree : @container.Document
}

///|
pub fn BlockDoc::new(
  replica_id : String,
) -> BlockDoc raise @container.DocumentError {
  { tree: @container.Document::new(replica_id) }
}

///|
/// Create a block as the last child of `parent` (default: root).
pub fn BlockDoc::create_block(
  self : BlockDoc,
  block_type : BlockType,
  parent? : @container.TreeNodeId = root_block_id,
) -> @container.TreeNodeId raise @container.DocumentError {
  let id = self.tree.create_node(parent~)
  self.apply_block_type(id, block_type)
  id
}

///|
/// Create a block immediately after `after_id` in document order.
pub fn BlockDoc::create_block_after(
  self : BlockDoc,
  after_id : @container.TreeNodeId,
  block_type : BlockType,
) -> @container.TreeNodeId raise @container.DocumentError {
  let id = self.tree.create_node_after(parent=root_block_id, after=after_id)
  self.apply_block_type(id, block_type)
  id
}

///|
/// Delete a block: move it to the tree trash.
pub fn BlockDoc::delete_block(
  self : BlockDoc,
  id : @container.TreeNodeId,
) -> Unit raise @container.DocumentError {
  self.tree.delete_node(id)
}

///|
/// Move a block relative to a reference sibling.
///
/// - `Before`: insert before `ref_id` under the same parent
/// - `After`: insert after `ref_id` under the same parent
/// - `Inside`: move as last child of `ref_id`
pub fn BlockDoc::move_block(
  self : BlockDoc,
  id : @container.TreeNodeId,
  ref_id : @container.TreeNodeId,
  position : @canopy_core.DropPosition,
) -> Unit raise @container.DocumentError {
  // Legality: self-drop and root-move are rejected at the model boundary.
  if @container.tree_node_id_eq(id, ref_id) {
    return
  }
  if @container.tree_node_id_eq(id, root_block_id) {
    raise @container.DocumentError::Internal(
      detail="cannot move root block",
    )
  }
  // Before/After assume a flat block list (all blocks are root children).
  // Inside reparents into ref_id for future nesting support.
  match position {
    Before =>
      self.tree.move_node_before(
        target=id,
        parent=root_block_id,
        before=ref_id,
      )
    After =>
      self.tree.move_node_after(
        target=id,
        parent=root_block_id,
        after=ref_id,
      )
    Inside => self.tree.move_node(target=id, new_parent=ref_id)
  }
}

///|
/// Return children of `parent` in display order.
pub fn BlockDoc::children(
  self : BlockDoc,
  parent : @container.TreeNodeId,
) -> Array[@container.TreeNodeId] {
  self.tree.children(parent)
}

///|
pub fn BlockDoc::is_alive(self : BlockDoc, id : @container.TreeNodeId) -> Bool {
  self.tree.is_alive(id)
}

///|
pub fn BlockDoc::get_type(
  self : BlockDoc,
  id : @container.TreeNodeId,
) -> BlockType {
  let type_str = self.tree.get_property(id, "block_type").unwrap_or("paragraph")
  block_type_from_props(type_str, fn(k) { self.tree.get_property(id, k) })
}

///|
pub fn BlockDoc::set_type(
  self : BlockDoc,
  id : @container.TreeNodeId,
  t : BlockType,
) -> Unit {
  self.apply_block_type(id, t)
}

///|
pub fn BlockDoc::get_text(
  self : BlockDoc,
  id : @container.TreeNodeId,
) -> String {
  self.tree.get_text(id)
}

///|
/// Bulk-replace block text via a deterministic delete-then-insert sequence.
///
/// This is a convenience helper, not a transaction boundary: peers syncing
/// mid-sequence may observe intermediate partial states until all generated ops
/// have arrived and been applied.
pub fn BlockDoc::set_text(
  self : BlockDoc,
  id : @container.TreeNodeId,
  text : String,
) -> Unit {
  self.tree.replace_text(id, text) catch {
    _ => ()
  }
}

///|
/// Insert a single character at `pos` (preferred for typing).
pub fn BlockDoc::insert_char(
  self : BlockDoc,
  id : @container.TreeNodeId,
  pos : Int,
  ch : String,
) -> Unit {
  self.tree.insert_text(id, pos, ch) catch {
    _ => ()
  }
}

///|
/// Delete the character at `pos`.
pub fn BlockDoc::delete_char(
  self : BlockDoc,
  id : @container.TreeNodeId,
  pos : Int,
) -> Unit {
  self.tree.delete_text(id, pos) catch {
    _ => ()
  }
}

///|
pub fn BlockDoc::get_checked(
  self : BlockDoc,
  id : @container.TreeNodeId,
) -> Bool {
  self.tree.get_property(id, "checked") == Some("true")
}

///|
pub fn BlockDoc::set_checked(
  self : BlockDoc,
  id : @container.TreeNodeId,
  v : Bool,
) -> Unit {
  self.tree.set_property(id, "checked", if v { "true" } else { "false" })
}

// ── Private helpers ────────────────────────────────────────────────────────

///|
fn BlockDoc::apply_block_type(
  self : BlockDoc,
  id : @container.TreeNodeId,
  t : BlockType,
) -> Unit {
  let (type_str, props) = block_type_to_string(t)
  self.tree.set_property(id, "block_type", type_str)
  props.each(fn(k, v) { self.tree.set_property(id, k, v) })
}
