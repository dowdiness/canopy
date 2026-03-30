// JSON edit dispatch and handlers.
// Each handler computes text-level SpanEdits from a structural JsonEditOp.

///|
using @core {type ProjNode, type SourceMap, type SpanEdit, type FocusHint}

///|
/// Compute text-level span edits for a JSON structural edit operation.
/// Returns Ok(Some((edits, focus_hint))) on success, Ok(None) for unhandled ops,
/// or Err(msg) for invalid operations.
pub fn compute_json_edit(
  op : JsonEditOp,
  source : String,
  proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  match op {
    Delete(node_id~) => compute_delete(source, proj, source_map, node_id)
    AddMember(object_id~, key~) =>
      compute_add_member(source, proj, source_map, object_id, key)
    AddElement(array_id~) =>
      compute_add_element(source, proj, source_map, array_id)
    WrapInArray(node_id~) => compute_wrap_in_array(source, source_map, node_id)
    WrapInObject(node_id~, key~) =>
      compute_wrap_in_object(source, source_map, node_id, key)
    Unwrap(node_id~) => compute_unwrap(source, proj, source_map, node_id)
    ChangeType(node_id~, new_type~) =>
      compute_change_type(source_map, node_id, new_type)
    RenameKey(object_id~, key_index~, new_key~) =>
      compute_rename_key(source_map, object_id, key_index, new_key)
    CommitEdit(node_id~, new_value~) =>
      compute_commit_edit(source_map, node_id, new_value)
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
    _ => "f"
  }
}

///|
/// Escape a string for use as a JSON key or value.
/// Handles all control characters per RFC 8259 §7.
fn json_escape_key(key : String) -> String {
  let buf = StringBuilder::new()
  for ch in key {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      '\u0008' => buf.write_string("\\b")
      '\u000C' => buf.write_string("\\f")
      _ =>
        if ch.to_int() <= 0x1F {
          // Control character U+0000–U+001F: emit \uXXXX
          let code = ch.to_int()
          buf.write_string("\\u")
          buf.write_string(hex_digit(code / 0x1000 % 16))
          buf.write_string(hex_digit(code / 0x100 % 16))
          buf.write_string(hex_digit(code / 0x10 % 16))
          buf.write_string(hex_digit(code % 16))
        } else {
          buf.write_char(ch)
        }
    }
  }
  buf.to_string()
}

///|
/// Delete a node from its parent container.
/// For object members, uses the "member:N" token span to cover the full
/// "key": value text. For array elements, uses the node's own range.
/// Handles comma cleanup for proper JSON formatting.
fn compute_delete(
  source : String,
  proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  // Determine the delete range: for object members, use the member span
  // which covers "key": value; for other nodes, use the node's own range.
  let (range_start, range_end) = match
    find_parent_member_span(proj, source_map, node_id) {
    Some(span) => span
    None =>
      match source_map.get_range(node_id) {
        Some(r) => (r.start, r.end)
        None => return Err("node not found in source map")
      }
  }
  // Find parent to handle comma cleanup
  let (delete_start, delete_end) = find_delete_range_with_comma(
    source, range_start, range_end, proj, source_map, node_id,
  )
  let delete_len = delete_end - delete_start
  Ok(
    Some(
      (
        [SpanEdit::{ start: delete_start, delete_len, inserted: "" }],
        FocusHint::MoveCursor(position=delete_start),
      ),
    ),
  )
}

///|
/// If node_id is a child of an Object, return the member span (start, end)
/// from the parent Object's "member:N" token span.
/// Returns None if the node is not an Object member.
fn find_parent_member_span(
  proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
  node_id : NodeId,
) -> (Int, Int)? {
  match find_parent_object(proj, node_id) {
    Some((parent_id, child_index)) =>
      match
        source_map.get_token_span(
          parent_id,
          @json_proj.member_role(child_index),
        ) {
        Some(r) => Some((r.start, r.end))
        None => None
      }
    None => None
  }
}

///|
/// Walk the ProjNode tree to find a parent Object that contains node_id
/// as a direct child. Returns (parent_id, child_index) or None.
fn find_parent_object(
  root : ProjNode[@json.JsonValue],
  target_id : NodeId,
) -> (NodeId, Int)? {
  if root.kind is @json.Object(_) {
    for i, child in root.children {
      if child.id() == target_id {
        return Some((root.id(), i))
      }
    }
  }
  // Recurse into all children
  for child in root.children {
    match find_parent_object(child, target_id) {
      Some(found) => return Some(found)
      None => continue
    }
  }
  None
}

///|
/// Expand the delete range to include trailing or leading comma + whitespace.
fn find_delete_range_with_comma(
  source : String,
  start : Int,
  end : Int,
  _proj : ProjNode[@json.JsonValue],
  _source_map : SourceMap,
  _node_id : NodeId,
) -> (Int, Int) {
  let len = source.length()
  // Try consuming trailing comma + whitespace
  let mut trail = end
  while trail < len && is_ws_code(source[trail]) {
    trail = trail + 1
  }
  if trail < len && source[trail] == comma_code {
    trail = trail + 1
    // Also skip whitespace after the comma
    while trail < len && is_ws_code(source[trail]) {
      trail = trail + 1
    }
    return (start, trail)
  }
  // No trailing comma — try consuming leading comma + whitespace
  let mut lead = start - 1
  while lead >= 0 && is_ws_code(source[lead]) {
    lead = lead - 1
  }
  if lead >= 0 && source[lead] == comma_code {
    // Include the comma and whitespace before the node
    return (lead, end)
  }
  (start, end)
}

///|
/// Check if a UTF-16 code unit is ASCII whitespace.
fn is_ws_code(code : UInt16) -> Bool {
  code == 0x20 || // space
  code == 0x0A || // \n
  code == 0x0D || // \r
  code == 0x09 // \t
}

///|
let comma_code : UInt16 = 0x2C

///|
let close_brace_code : UInt16 = 0x7D

///|
let close_bracket_code : UInt16 = 0x5D

///|
/// Add a new member to an object.
/// Inserts `"key": null` before the closing `}`.
fn compute_add_member(
  source : String,
  _proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
  object_id : NodeId,
  key : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(object_id) {
    Some(r) => r
    None => return Err("object node not found in source map")
  }
  // Find the closing brace position
  let close_brace = range.end - 1
  if close_brace < 0 ||
    close_brace >= source.length() ||
    source[close_brace] != close_brace_code {
    return Err("cannot find closing brace for object")
  }
  let escaped = json_escape_key(key)
  let member_text = "\"" + escaped + "\": null"
  // Check if object already has members by looking for content between braces
  let has_members = has_content_between(source, range.start + 1, close_brace)
  let inserted = if has_members { ", " + member_text } else { member_text }
  let insert_pos = close_brace
  let focus_pos = insert_pos + inserted.length()
  Ok(
    Some(
      (
        [SpanEdit::{ start: insert_pos, delete_len: 0, inserted }],
        FocusHint::MoveCursor(position=focus_pos),
      ),
    ),
  )
}

///|
/// Check if there is any non-whitespace content between two positions.
fn has_content_between(source : String, start : Int, end : Int) -> Bool {
  let mut i = start
  while i < end {
    if not(is_ws_code(source[i])) {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// Add a null element to an array.
/// Inserts `null` before the closing `]`.
fn compute_add_element(
  source : String,
  _proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
  array_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(array_id) {
    Some(r) => r
    None => return Err("array node not found in source map")
  }
  let close_bracket = range.end - 1
  if close_bracket < 0 ||
    close_bracket >= source.length() ||
    source[close_bracket] != close_bracket_code {
    return Err("cannot find closing bracket for array")
  }
  let has_elements = has_content_between(source, range.start + 1, close_bracket)
  let inserted = if has_elements { ", null" } else { "null" }
  let insert_pos = close_bracket
  let focus_pos = insert_pos + inserted.length()
  Ok(
    Some(
      (
        [SpanEdit::{ start: insert_pos, delete_len: 0, inserted }],
        FocusHint::MoveCursor(position=focus_pos),
      ),
    ),
  )
}

///|
/// Wrap a node in an array: `value` -> `[value]`.
/// Uses a single replacement to avoid FugueMax interleaving issues.
fn compute_wrap_in_array(
  source : String,
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  let existing = source[range.start:range.end].to_string()
  let wrapped = "[" + existing + "]"
  let edit = SpanEdit::{
    start: range.start,
    delete_len: range.end - range.start,
    inserted: wrapped,
  }
  Ok(
    Some(
      ([edit], FocusHint::MoveCursor(position=range.start + wrapped.length())),
    ),
  )
}

///|
/// Wrap a node in an object: `value` -> `{"key": value}`.
/// Uses a single replacement to avoid FugueMax interleaving issues.
fn compute_wrap_in_object(
  source : String,
  source_map : SourceMap,
  node_id : NodeId,
  key : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  let escaped = json_escape_key(key)
  let existing = source[range.start:range.end].to_string()
  let wrapped = "{\"" + escaped + "\": " + existing + "}"
  let edit = SpanEdit::{
    start: range.start,
    delete_len: range.end - range.start,
    inserted: wrapped,
  }
  Ok(
    Some(
      ([edit], FocusHint::MoveCursor(position=range.start + wrapped.length())),
    ),
  )
}

///|
/// Unwrap a single-child container: `[value]` -> `value` or `{"k": value}` -> `value`.
fn compute_unwrap(
  source : String,
  _proj : ProjNode[@json.JsonValue],
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  // Find the node in the projection tree to check it has exactly one child
  let node = match
    @core.get_node_in_tree(
      // We need a way to find the node — use source_map to validate
      // and then work with text directly
      _proj, node_id,
    ) {
    Some(n) => n
    None => return Err("node not found in projection tree")
  }
  if node.children.length() != 1 {
    return Err(
      "unwrap requires exactly one child, found " +
      node.children.length().to_string(),
    )
  }
  let child = node.children[0]
  let child_range = match source_map.get_range(child.id()) {
    Some(r) => r
    None => return Err("child node not found in source map")
  }
  // Extract the child's text and replace the whole container
  let child_text = source[child_range.start:child_range.end].to_string()
  let edit = SpanEdit::{
    start: range.start,
    delete_len: range.end - range.start,
    inserted: child_text,
  }
  Ok(
    Some(
      (
        [edit],
        FocusHint::MoveCursor(position=range.start + child_text.length()),
      ),
    ),
  )
}

///|
/// Change a node's type to a new placeholder value.
fn compute_change_type(
  source_map : SourceMap,
  node_id : NodeId,
  new_type : JsonType,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  let placeholder = match new_type {
    JNull => "null"
    JBool => "false"
    JNumber => "0"
    JString => "\"\""
    JArray => "[]"
    JObject => "{}"
  }
  let edit = SpanEdit::{
    start: range.start,
    delete_len: range.end - range.start,
    inserted: placeholder,
  }
  Ok(
    Some(
      (
        [edit],
        FocusHint::MoveCursor(position=range.start + placeholder.length()),
      ),
    ),
  )
}

///|
/// Rename an object key.
/// Uses source_map.get_token_span(object_id, "key:N") to find the key span.
fn compute_rename_key(
  source_map : SourceMap,
  object_id : NodeId,
  key_index : Int,
  new_key : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let role = @json_proj.key_role(key_index)
  let key_range = match source_map.get_token_span(object_id, role) {
    Some(r) => r
    None => return Err("key span not found for " + role)
  }
  let escaped = json_escape_key(new_key)
  let new_text = "\"" + escaped + "\""
  let edit = SpanEdit::{
    start: key_range.start,
    delete_len: key_range.end - key_range.start,
    inserted: new_text,
  }
  Ok(
    Some(
      (
        [edit],
        FocusHint::MoveCursor(position=key_range.start + new_text.length()),
      ),
    ),
  )
}

///|
/// Commit an inline edit by replacing the node's text with new_value.
fn compute_commit_edit(
  source_map : SourceMap,
  node_id : NodeId,
  new_value : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  let edit = SpanEdit::{
    start: range.start,
    delete_len: range.end - range.start,
    inserted: new_value,
  }
  Ok(
    Some(
      ([edit], FocusHint::MoveCursor(position=range.start + new_value.length())),
    ),
  )
}
