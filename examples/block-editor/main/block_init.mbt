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
  docs[handle] = BlockDoc::new(replica_id)
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
  match replica_ids.get(handle) {
    Some(id) => id
    None => "unknown"
  }
}

///|
/// Parse "agent:counter" string into a TreeNodeId.
/// Splits on last ':' so agent IDs without ':' are safe.
fn parse_block_id(s : String) -> @tree.TreeNodeId {
  let mut last_colon = -1
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == ':' {
      last_colon = i
    }
  }
  if last_colon < 0 {
    return @tree.root_id
  }
  let agent = s[0:last_colon].to_string()
  let counter_str = s[last_colon + 1:].to_string()
  let mut counter = 0
  let mut neg = false
  let mut start = 0
  if counter_str.length() > 0 && counter_str[0] == '-' {
    neg = true
    start = 1
  }
  for i = start; i < counter_str.length(); i = i + 1 {
    let d = counter_str[i].to_int() - 48
    counter = counter * 10 + d
  }
  if neg {
    counter = -counter
  }
  @tree.tree_node_id_new(agent, counter)
}

///|
pub fn get_render_state(handle : Int) -> String {
  match docs.get(handle) {
    Some(doc) => {
      let buf = StringBuilder::new()
      buf.write_string("{\"blocks\":[")
      let children = doc.children(root_block_id)
      for i = 0; i < children.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(",")
        }
        let id = children[i]
        let (type_str, props) = block_type_to_string(doc.get_type(id))
        buf.write_string("{\"id\":\"")
        write_json_escaped(buf, id_key(id))
        buf.write_string("\",\"block_type\":\"")
        write_json_escaped(buf, type_str)
        buf.write_string("\",\"level\":\"")
        write_json_escaped(
          buf,
          match props.get("level") {
            Some(v) => v
            None => ""
          },
        )
        buf.write_string("\",\"list_style\":\"")
        write_json_escaped(
          buf,
          match props.get("list_style") {
            Some(v) => v
            None => ""
          },
        )
        buf.write_string("\",\"checked\":")
        buf.write_string(if doc.get_checked(id) { "true" } else { "false" })
        buf.write_string(",\"text\":\"")
        write_json_escaped(buf, doc.get_text(id))
        buf.write_string("\"}")
      }
      buf.write_string("]}")
      buf.to_string()
    }
    None => "{\"blocks\":[]}"
  }
}

///|
fn write_json_escaped(buf : StringBuilder, s : String) -> Unit {
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i]
    if ch == '"' {
      buf.write_string("\\\"")
    } else if ch == '\\' {
      buf.write_string("\\\\")
    } else if ch == '\n' {
      buf.write_string("\\n")
    } else if ch == '\r' {
      buf.write_string("\\r")
    } else if ch == '\t' {
      buf.write_string("\\t")
    } else if ch.to_int() < 0x20 {
      // JSON requires all control chars below 0x20 to be escaped
      buf.write_string("\\u00")
      let hi = (ch.to_int() >> 4) & 0xf
      let lo = ch.to_int() & 0xf
      buf.write_string(hex_digit(hi))
      buf.write_string(hex_digit(lo))
    } else {
      buf.write_string(s[i:i + 1].to_string())
    }
  }
}

///|
fn hex_digit(n : Int) -> String {
  match n {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "a"
    11 => "b"
    12 => "c"
    13 => "d"
    14 => "e"
    15 => "f"
    _ => "0"
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
      let new_id = doc.create_block_after(after_id, bt)
      id_key(new_id)
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
    Some(doc) => doc.delete_block(parse_block_id(id_str))
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
pub fn editor_import_markdown(handle : Int, md : String) -> Unit {
  match docs.get(handle) {
    Some(_) => {
      let replica_id = get_replica_id(handle)
      docs[handle] = block_doc_from_markdown(md, replica_id)
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
