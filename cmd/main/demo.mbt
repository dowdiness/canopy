///| Demo - CRDT Editor demonstration

///|

///| Demonstrates the CRDT editor capabilities

///|
/// Print a separator
fn print_separator() -> Unit {
  println("================================================")
}

///|
/// Show editor state with agent name
fn show_editor(agent_name : String, editor : @editor.Editor) -> Unit {
  let text = editor.get_text()
  let cursor = editor.get_cursor()
  println("[\{agent_name}] Text: \"\{text}\" (cursor: \{cursor})")
}

///|
/// Show sync info (op count via SyncMessage)
fn show_sync_info(editor : @editor.Editor) -> Unit {
  try {
    let msg = editor.export_all()
    println("Operations (\{msg.op_count()} total in sync message)")
  } catch {
    _ => ()
  }
}

///|
/// Run CRDT editor demo
pub fn run_convergence_demo() -> Unit {
  println("Eg-walker CRDT Editor - Feature Demo")
  print_separator()
  println("")

  // Demonstration of basic editing
  println("Demo: Text editing with CRDT operations")
  print_separator()
  println("")
  let alice = @editor.Editor::new("alice")
  println("1. Alice types 'Hello'")
  try! alice.insert("Hello")
  show_editor("Alice", alice)
  println("")
  println("2. Alice types ' World'")
  try! alice.insert(" World")
  show_editor("Alice", alice)
  println("")
  println("3. Alice moves cursor to position 6 and inserts 'CRDT '")
  alice.move_cursor(6)
  try! alice.insert("CRDT ")
  show_editor("Alice", alice)
  println("")
  println("4. View operation log:")
  show_sync_info(alice)
  println("")
  println("5. Alice moves cursor to position 0 and inserts 'Hey! '")
  alice.move_cursor(0)
  try! alice.insert("Hey! ")
  show_editor("Alice", alice)
  println("")
  println("6. Final operation log:")
  show_sync_info(alice)
  println("")
  println("Version: \{alice.get_version()}")
  println("")
  print_separator()
  println("Key features demonstrated:")
  println("  • Position-based editing with cursor tracking")
  println("  • Operation log captures all edits")
  println("  • Each operation has causal metadata (LV, origin)")
  println("  • Frontier tracks the latest operations")
  println("")
}
