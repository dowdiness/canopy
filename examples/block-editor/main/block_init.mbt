///|
let docs : Map[Int, BlockDoc] = Map::new()

///|
let replica_ids : Map[Int, String] = Map::new()

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
/// Parse "agent:counter" string into a TreeNodeId.
/// Splits on last ':' so agent IDs without ':' are safe.
fn parse_block_id(s : String) -> @container.TreeNodeId {
  match s.rev_split_once(":") {
    None => @container.root_id
    Some((agent, counter_view)) => {
      // Parse integer directly from StringView — no intermediate String allocation
      let mut counter = 0
      let mut neg = false
      let mut start = 0
      if counter_view.length() > 0 && counter_view[0] == '-' {
        neg = true
        start = 1
      }
      for i in start..<counter_view.length() {
        counter = counter * 10 + (counter_view[i].to_int() - 48)
      }
      if neg {
        counter = -counter
      }
      @container.tree_node_id_new(agent.to_string(), counter)
    }
  }
}

///|
pub fn get_render_state(handle : Int) -> String {
  match docs.get(handle) {
    Some(doc) => {
      let buf = StringBuilder::new()
      let children = doc.children(root_block_id)
      let parent_key = @container.tree_node_id_key(root_block_id)
      buf.write_string("{\"block_count\":")
      buf.write_string(children.length().to_string())
      buf.write_string(",\"blocks\":[")
      for i in 0..<children.length() {
        if i > 0 {
          buf.write_string(",")
        }
        let id = children[i]
        let bt = doc.get_type(id)
        buf.write_string("{\"id\":\"")
        write_json_escaped(buf, @container.tree_node_id_key(id))
        buf.write_string("\",\"block_type\":\"")
        write_json_escaped(buf, block_type_name(bt))
        buf.write_string("\",\"level\":\"")
        match bt {
          Heading(n) => write_json_escaped(buf, n.to_string())
          _ => ()
        }
        buf.write_string("\",\"list_style\":\"")
        match bt {
          ListItem(Bullet) => buf.write_string("bullet")
          ListItem(Numbered) => buf.write_string("numbered")
          ListItem(Todo) => buf.write_string("todo")
          _ => ()
        }
        buf.write_string("\",\"checked\":")
        buf.write_string(if doc.get_checked(id) { "true" } else { "false" })
        buf.write_string(",\"index\":")
        buf.write_string(i.to_string())
        buf.write_string(",\"parent_id\":\"")
        write_json_escaped(buf, parent_key)
        buf.write_string("\",\"text\":\"")
        write_json_escaped(buf, doc.get_text(id))
        buf.write_string("\"}")
      }
      buf.write_string("]}")
      buf.to_string()
    }
    None => "{\"block_count\":0,\"blocks\":[]}"
  }
}

///|
/// Escape a string for JSON output. Handles required escapes (RFC 8259 §7)
/// and writes directly to the buffer without per-character allocation.
fn write_json_escaped(buf : StringBuilder, s : String) -> Unit {
  // Track start of unescaped run to batch-copy normal characters
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
      // JSON requires all control chars below U+0020 to be \uXXXX escaped
      let hi = (ch.to_int() >> 4) & 0xf
      let lo = ch.to_int() & 0xf
      Some("\\u00" + hex_char(hi).to_string() + hex_char(lo).to_string())
    } else {
      None
    }
    match escape {
      Some(esc) => {
        // Flush the unescaped run before writing the escape sequence
        if run_start < i {
          buf.write_string(s[run_start:i].to_string())
        }
        buf.write_string(esc)
        run_start = i + 1
      }
      None => ()
    }
  }
  // Flush any remaining unescaped tail
  if run_start < s.length() {
    buf.write_string(s[run_start:].to_string())
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
      @container.tree_node_id_key(new_id)
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
      doc.move_block(id, ref_id, position) catch { _ => return false }
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
