///| FFI exports for the Markdown editor — lifecycle (create, destroy, text I/O).
/// Handles start at 20000 to avoid collisions with lambda (0+) and JSON (10000+).

///|
let markdown_editors : Map[Int, @editor.SyncEditor[@md.Block]] = Map::new()

///|
let markdown_next_handle : Ref[Int] = { val: 20000 }

///|
pub fn create_markdown_editor(agent_id : String) -> Int {
  let handle = markdown_next_handle.val
  markdown_next_handle.val = handle + 1
  markdown_editors[handle] = @md_companion.new_markdown_editor(agent_id)
  handle
}

///|
pub fn destroy_markdown_editor(handle : Int) -> Unit {
  markdown_editors.remove(handle)
  markdown_view_states.remove(handle)
}

///|
pub fn markdown_get_text(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => ed.get_text()
    None => ""
  }
}

///|
/// Return markdown text with ZWSP placeholder lines stripped.
/// Only strips the "\n\u200B\n" pattern (empty-block sentinel from InsertBlockAfter),
/// preserving legitimate ZWSP in user content (code blocks, pasted text).
pub fn markdown_export_text(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => ed.get_text().replace_all(old="\n\u200B\n", new="\n\n")
    None => ""
  }
}

///|
pub fn markdown_set_text(handle : Int, text : String) -> Unit {
  match markdown_editors.get(handle) {
    Some(ed) => ed.set_text(text)
    None => ()
  }
}
