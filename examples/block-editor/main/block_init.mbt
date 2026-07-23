///|
let docs : Map[Int, BlockDoc] = Map::default()

///|
let replica_ids : Map[Int, String] = Map::default()

///|
let next_handle : Ref[Int] = { val: 1 }

///|
pub fn create_editor(replica_id : String) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  docs[handle] = BlockDoc::new(replica_id) catch { _ => return -1 }
  replica_ids[handle] = replica_id
  handle
}

///|
pub fn destroy_editor(handle : Int) -> Unit {
  docs.remove(handle)
  replica_ids.remove(handle)
}

///|
fn get_replica_id(handle : Int) -> String {
  replica_ids.get(handle).unwrap_or("unknown")
}

///|
/// Parse the length-prefixed TreeNodeId key produced by `TreeNodeId::key`.
fn parse_block_id(s : String) -> @container.TreeNodeId {
  guard s.split_once(":") is Some((length_view, rest)) else {
    return @container.root_id
  }
  let agent_length : Int = @strconv.from_str(length_view) catch {
    _ => return @container.root_id
  }
  guard agent_length > 0 && rest.length() > agent_length else {
    return @container.root_id
  }
  guard rest[agent_length] == ':' else { return @container.root_id }
  let agent = rest[:agent_length].to_owned()
  let sequence : Int = @strconv.from_str(rest[agent_length + 1:]) catch {
    _ => return @container.root_id
  }
  @container.TreeNodeId::TreeNodeId(agent, sequence) catch {
    _ => @container.root_id
  }
}

///|
fn count_blocks(doc : BlockDoc, parent_id : @container.TreeNodeId) -> Int {
  let children = doc.children(parent_id)
  for child in children; acc = children.length() {
    continue acc + count_blocks(doc, child)
  } nobreak {
    acc
  }
}

///|
fn emit_block_json(
  buf : StringBuilder,
  doc : BlockDoc,
  id : @container.TreeNodeId,
  parent_key : String,
  depth : Int,
  child_index : Int,
) -> Unit {
  let bt = doc.get_type(id)
  buf
  ..write_string("{\"id\":\"")
  ..write_json_escaped(id.key())
  ..write_string("\",\"block_type\":\"")
  ..write_json_escaped(block_type_name(bt))
  .write_string("\",\"level\":\"")
  match bt {
    Heading(n) => buf.write_json_escaped(n.to_string())
    _ => ()
  }
  buf.write_string("\",\"list_style\":\"")
  match bt {
    ListItem(Bullet) => buf.write_string("bullet")
    ListItem(Numbered) => buf.write_string("numbered")
    ListItem(Todo) => buf.write_string("todo")
    _ => ()
  }
  buf
  ..write_string("\",\"checked\":")
  ..write_string(if doc.get_checked(id) { "true" } else { "false" })
  ..write_string(",\"index\":")
  ..write_string(child_index.to_string())
  ..write_string(",\"parent_id\":\"")
  ..write_json_escaped(parent_key)
  ..write_string("\",\"depth\":")
  ..write_string(depth.to_string())
  ..write_string(",\"child_count\":")
  ..write_string(doc.children(id).length().to_string())
  ..write_string(",\"is_alive\":")
  ..write_string(if doc.is_alive(id) { "true" } else { "false" })
  ..write_string(",\"text\":\"")
  ..write_json_escaped(doc.get_text(id))
  .write_string("\"}")
  ()
}

///|
/// Emit JSON for all blocks in the subtree rooted at `parent_id`, in preorder.
/// `is_first` tracks whether this is the first block in the overall array (no comma prefix).
fn emit_blocks(
  buf : StringBuilder,
  doc : BlockDoc,
  parent_id : @container.TreeNodeId,
  depth : Int,
  is_first : Ref[Bool],
) -> Unit {
  let children = doc.children(parent_id)
  let parent_key = parent_id.key()
  // Indexed loop: i is the sibling index passed to emit_block_json.
  for i in 0..<children.length() {
    let id = children[i]
    if is_first.val {
      is_first.val = false
    } else {
      buf.write_string(",")
    }
    emit_block_json(buf, doc, id, parent_key, depth, i)
    // Recurse into children
    emit_blocks(buf, doc, id, depth + 1, is_first)
  }
}

///| Return the full block tree as JSON, in preorder (parents before children).

///|

///| Each block object contains: id, block_type, level, list_style, checked,

///| index (sibling order), parent_id, depth, child_count, is_alive, text.

///|
/// Blocks with children appear before their descendants in the array (preorder).
pub fn get_render_state(handle : Int) -> String {
  match docs.get(handle) {
    Some(doc) => {
      let buf = StringBuilder()
      let total = count_blocks(doc, root_block_id)
      buf
      ..write_string("{\"block_count\":")
      ..write_string(total.to_string())
      .write_string(",\"blocks\":[")
      emit_blocks(buf, doc, root_block_id, 0, { val: true })
      buf..write_string("]}").to_string()
    }
    None => "{\"block_count\":0,\"blocks\":[]}"
  }
}

///|
/// Escape a string and append to this buffer. Handles required JSON escapes (RFC 8259 §7).
fn StringBuilder::write_json_escaped(self : StringBuilder, s : String) -> Unit {
  let mut run_start = 0
  for i in 0..<s.length() {
    let ch = s[i]
    let escape : String? = if ch == '"' {
      Some("\\\"")
    } else if ch == '\\' {
      Some("\\\\")
    } else if ch == '\n' {
      Some("\\n")
    } else if ch == '\r' {
      Some("\\r")
    } else if ch == '\t' {
      Some("\\t")
    } else if ch.to_int() < 0x20 {
      let hi = (ch.to_int() >> 4) & 0xf
      let lo = ch.to_int() & 0xf
      Some("\\u00" + hex_char(hi).to_string() + hex_char(lo).to_string())
    } else {
      None
    }
    match escape {
      Some(esc) => {
        if run_start < i {
          self.write_string(s[run_start:i].to_owned())
        }
        self.write_string(esc)
        run_start = i + 1
      }
      None => ()
    }
  }
  if run_start < s.length() {
    self.write_string(s[run_start:].to_owned())
  }
}

///|
/// Convert a nibble (0–15) to its hex character.
fn hex_char(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).unsafe_to_char()
  } else {
    ('a'.to_int() + n - 10).unsafe_to_char()
  }
}

///|
pub fn editor_insert_block_after(
  handle : Int,
  after_id_str : String,
  block_type_str : String,
) -> String {
  match docs.get(handle) {
    Some(doc) => {
      let after_id = parse_block_id(after_id_str)
      let bt = block_type_from_props(block_type_str, fn(_k) { None })
      let new_id = doc.create_block_after(after_id, bt) catch { _ => return "" }
      new_id.key()
    }
    None => ""
  }
}

///|
pub fn editor_set_block_text(
  handle : Int,
  id_str : String,
  text : String,
) -> Unit {
  match docs.get(handle) {
    Some(doc) => doc.set_text(parse_block_id(id_str), text)
    None => ()
  }
}

///|
pub fn editor_delete_block(handle : Int, id_str : String) -> Unit {
  match docs.get(handle) {
    Some(doc) => doc.delete_block(parse_block_id(id_str)) catch { _ => () }
    None => ()
  }
}

///|
pub fn editor_set_block_type(
  handle : Int,
  id_str : String,
  type_str : String,
  level : Int,
  list_style : String,
) -> Unit {
  match docs.get(handle) {
    Some(doc) => {
      let bt = block_type_from_props(type_str, fn(k) {
        if k == "level" {
          Some(level.to_string())
        } else if k == "list_style" && list_style != "" {
          Some(list_style)
        } else {
          None
        }
      })
      doc.set_type(parse_block_id(id_str), bt)
    }
    None => ()
  }
}

///|
/// Move a block relative to a reference block.
///
/// `position_str` is one of "Before", "After", "Inside".
pub fn editor_move_block(
  handle : Int,
  id_str : String,
  ref_id_str : String,
  position_str : String,
) -> Bool {
  match docs.get(handle) {
    Some(doc) => {
      let position : @canopy_core.DropPosition = match position_str {
        "Before" => Before
        "After" => After
        "Inside" => Inside
        _ => return false
      }
      let id = parse_block_id(id_str)
      let ref_id = parse_block_id(ref_id_str)
      doc.move_block(id, ref_id, position) catch {
        _ => return false
      }
      true
    }
    None => false
  }
}

///|
pub fn editor_import_markdown(handle : Int, md : String) -> Unit {
  match docs.get(handle) {
    Some(_) => {
      let replica_id = get_replica_id(handle)
      let new_doc = block_doc_from_markdown(md, replica_id) catch {
        _ => return
      }
      docs[handle] = new_doc
    }
    None => ()
  }
}

///|
pub fn editor_export_markdown(handle : Int) -> String {
  match docs.get(handle) {
    Some(doc) => block_doc_to_markdown(doc)
    None => ""
  }
}
