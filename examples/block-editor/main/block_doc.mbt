///|
/// The block identifier type — a tree node ID.
pub type BlockId = @tree.TreeNodeId

///|
/// Sentinel for the document root (parent of all top-level blocks).
pub let root_block_id : @tree.TreeNodeId = @tree.root_id

///|
/// A collaborative block document.
///
/// Wraps a `TreeDoc` for block hierarchy and a per-block `TextDoc` map for
/// text content. Block ordering delegates to the tree CRDT's fractional indexing.
pub struct BlockDoc {
  priv tree : @tree.TreeDoc
  priv texts : Map[String, @text.TextDoc]
  priv replica_id : String
}

///|
pub fn BlockDoc::new(replica_id : String) -> BlockDoc {
  { tree: @tree.TreeDoc::new(replica_id), texts: {}, replica_id }
}

///|
/// Create a block as the last child of `parent` (default: root).
pub fn BlockDoc::create_block(
  self : BlockDoc,
  block_type : BlockType,
  parent? : @tree.TreeNodeId = root_block_id,
) -> @tree.TreeNodeId {
  let id = self.tree.create_node(parent~)
  self.texts[id_key(id)] = @text.TextDoc::new(self.replica_id)
  self.apply_block_type(id, block_type)
  id
}

///|
/// Create a block immediately after `after_id` in document order.
pub fn BlockDoc::create_block_after(
  self : BlockDoc,
  after_id : @tree.TreeNodeId,
  block_type : BlockType,
) -> @tree.TreeNodeId {
  let id = self.tree.create_node_after(parent=root_block_id, after=after_id)
  self.texts[id_key(id)] = @text.TextDoc::new(self.replica_id)
  self.apply_block_type(id, block_type)
  id
}

///|
/// Delete a block: move it to the tree trash.
pub fn BlockDoc::delete_block(self : BlockDoc, id : @tree.TreeNodeId) -> Unit {
  self.tree.delete_node(id)
}

///|
/// Move a block to a new parent.
pub fn BlockDoc::move_block(
  self : BlockDoc,
  id : @tree.TreeNodeId,
  new_parent~ : @tree.TreeNodeId,
) -> Unit {
  self.tree.move_node(target=id, new_parent~)
}

///|
/// Return children of `parent` in display order.
pub fn BlockDoc::children(
  self : BlockDoc,
  parent : @tree.TreeNodeId,
) -> Array[@tree.TreeNodeId] {
  self.tree.children(parent)
}

///|
pub fn BlockDoc::is_alive(self : BlockDoc, id : @tree.TreeNodeId) -> Bool {
  self.tree.is_alive(id)
}

///|
pub fn BlockDoc::get_type(self : BlockDoc, id : @tree.TreeNodeId) -> BlockType {
  let type_str = self.tree.get_property(id, "block_type").unwrap_or("paragraph")
  block_type_from_props(type_str, fn(k) { self.tree.get_property(id, k) })
}

///|
pub fn BlockDoc::set_type(
  self : BlockDoc,
  id : @tree.TreeNodeId,
  t : BlockType,
) -> Unit {
  self.apply_block_type(id, t)
}

///|
pub fn BlockDoc::get_text(self : BlockDoc, id : @tree.TreeNodeId) -> String {
  match self.texts.get(id_key(id)) {
    Some(tdoc) => tdoc.text()
    None => ""
  }
}

///|
/// Bulk-replace block text (atomic CRDT replace).
pub fn BlockDoc::set_text(
  self : BlockDoc,
  id : @tree.TreeNodeId,
  text : String,
) -> Unit {
  match self.texts.get(id_key(id)) {
    Some(tdoc) => {
      let len = tdoc.len()
      if len > 0 {
        tdoc.replace_range(@text.Range::from_ints(0, len), text) catch {
          _ => ()
        }
      } else if text != "" {
        tdoc.insert(@text.Pos::at(0), text) catch {
          _ => ()
        }
      }
    }
    None => ()
  }
}

///|
/// Insert a single character at `pos` (preferred for typing).
pub fn BlockDoc::insert_char(
  self : BlockDoc,
  id : @tree.TreeNodeId,
  pos : Int,
  ch : String,
) -> Unit {
  match self.texts.get(id_key(id)) {
    Some(tdoc) => tdoc.insert(@text.Pos::at(pos), ch) catch { _ => () }
    None => ()
  }
}

///|
/// Delete the character at `pos`.
pub fn BlockDoc::delete_char(
  self : BlockDoc,
  id : @tree.TreeNodeId,
  pos : Int,
) -> Unit {
  match self.texts.get(id_key(id)) {
    Some(tdoc) => tdoc.delete(@text.Pos::at(pos)) catch { _ => () }
    None => ()
  }
}

///|
pub fn BlockDoc::get_checked(self : BlockDoc, id : @tree.TreeNodeId) -> Bool {
  self.tree.get_property(id, "checked") == Some("true")
}

///|
pub fn BlockDoc::set_checked(
  self : BlockDoc,
  id : @tree.TreeNodeId,
  v : Bool,
) -> Unit {
  self.tree.set_property(id, "checked", if v { "true" } else { "false" })
}

// ── Private helpers ────────────────────────────────────────────────────────

///|
fn id_key(id : @tree.TreeNodeId) -> String {
  @tree.tree_node_id_key(id)
}

///|
fn id_eq(a : @tree.TreeNodeId, b : @tree.TreeNodeId) -> Bool {
  @tree.tree_node_id_eq(a, b)
}

///|
fn BlockDoc::apply_block_type(
  self : BlockDoc,
  id : @tree.TreeNodeId,
  t : BlockType,
) -> Unit {
  let (type_str, props) = block_type_to_string(t)
  self.tree.set_property(id, "block_type", type_str)
  props.each(fn(k, v) { self.tree.set_property(id, k, v) })
}
