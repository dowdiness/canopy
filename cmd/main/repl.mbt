///| REPL - Read-Eval-Print Loop for the CRDT editor

///|

///| Provides interactive commands for editing and testing

///|
/// REPL state holding the editor
struct ReplState {
  editor : @editor.Editor
}

///|
/// Create a new REPL state
fn ReplState::new(agent_id : String) -> ReplState {
  { editor: @editor.Editor::new(agent_id) }
}

///|
/// Print help message
fn print_help() -> Unit {
  println("Eg-walker CRDT Editor - Interactive REPL")
  println("")
  println("Commands:")
  println("  insert <text>     - Insert text at cursor")
  println("  delete            - Delete character at cursor")
  println("  backspace         - Delete character before cursor")
  println("  move <pos>        - Move cursor to position")
  println("  show              - Display current text and cursor")
  println("  frontier          - Show current frontier")
  println("  ops               - Show all operations")
  println("  help              - Show this help message")
  println("  quit              - Exit the REPL")
  println("")
}

///|
/// Display current editor state
fn show_state(state : ReplState) -> Unit {
  let text = state.editor.get_text()
  let cursor = state.editor.get_cursor()
  println("Text: \"\{text}\"")

  // Show cursor position visually
  let mut cursor_line = "      "
  for i = 0; i < text.length(); i = i + 1 {
    if i == cursor {
      cursor_line = cursor_line + "^"
      break
    } else {
      cursor_line = cursor_line + " "
    }
  }
  if cursor == text.length() {
    cursor_line = cursor_line + "^"
  }
  println(cursor_line)
  println("Cursor: \{cursor}")
}

///|
/// Parse and execute a command - returns true to continue, false to quit
fn execute_command(state : ReplState, line : String) -> Bool {
  let trimmed = line.trim()
  if trimmed.length() == 0 {
    return true // Continue
  }

  // Split command and arguments - convert iterator to array
  let parts : Array[String] = []
  for part in trimmed.split(" ") {
    let s = part.to_string()
    if s.length() > 0 {
      parts.push(s)
    }
  }
  if parts.length() == 0 {
    return true
  }
  let command = parts[0]
  if command == "help" || command == "h" || command == "?" {
    print_help()
    return true
  }
  if command == "quit" || command == "exit" || command == "q" {
    println("Goodbye!")
    return false
  }
  if command == "show" || command == "s" {
    show_state(state)
    return true
  }
  if command == "insert" || command == "i" {
    if parts.length() < 2 {
      println("Error: insert requires text argument")
      println("Usage: insert <text>")
    } else {
      // Join all parts after command as text
      let mut text = parts[1]
      for i = 2; i < parts.length(); i = i + 1 {
        text = text + " " + parts[i]
      }
      try! state.editor.insert(text)
      println("Inserted: \"\{text}\"")
    }
    return true
  }
  if command == "delete" || command == "d" {
    let success = state.editor.delete()
    if success {
      println("Deleted character at cursor")
    } else {
      println("Nothing to delete")
    }
    return true
  }
  if command == "backspace" || command == "b" {
    let success = state.editor.backspace()
    if success {
      println("Deleted character before cursor")
    } else {
      println("Nothing to delete")
    }
    return true
  }
  if command == "move" || command == "m" {
    if parts.length() < 2 {
      println("Error: move requires position argument")
      println("Usage: move <position>")
    } else {
      // Parse position as integer
      let pos_str = parts[1]
      let mut pos = 0
      let mut valid = true

      // Simple manual parsing
      for i = 0; i < pos_str.length(); i = i + 1 {
        let c = pos_str[i]
        if c >= '0' && c <= '9' {
          pos = pos * 10 + (c.to_int() - '0'.to_int())
        } else {
          valid = false
          break
        }
      }
      if valid {
        state.editor.move_cursor(pos)
        println("Moved cursor to position \{pos}")
      } else {
        println("Error: invalid position '\{pos_str}'")
      }
    }
    return true
  }
  if command == "frontier" || command == "f" {
    println("Version: \{state.editor.get_version()}")
    return true
  }
  if command == "ops" || command == "o" {
    try {
      let msg = state.editor.export_all()
      println("Operations (\{msg.op_count()} total in sync message)")
    } catch {
      _ => ()
    }
    return true
  }
  println("Unknown command: '\{command}'")
  println("Type 'help' for available commands")
  true
}

///|
/// Run the REPL - simple demo mode (non-interactive for now)
pub fn run_repl(agent_id : String) -> Unit {
  println("Eg-walker CRDT Editor v0.1.0")
  println("Agent: \{agent_id}")
  println("")
  let state = ReplState::new(agent_id)

  // Demo commands
  println("Running demo commands...")
  println("")
  println("alice> insert Hello")
  let _ = execute_command(state, "insert Hello")
  println("alice> insert , World!")
  let _ = execute_command(state, "insert , World!")
  println("alice> show")
  let _ = execute_command(state, "show")
  println("")
  println("alice> move 5")
  let _ = execute_command(state, "move 5")
  println("alice> insert CRDT")
  let _ = execute_command(state, "insert CRDT")
  println("alice> show")
  let _ = execute_command(state, "show")
  println("")
  println("alice> ops")
  let _ = execute_command(state, "ops")
  println("")
  println("Demo complete!")
}
