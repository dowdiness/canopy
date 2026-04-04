///|
let typo_correction_system_prompt : String =
  #|You are a Japanese/English text proofreader.
  #|Fix typos, misspellings, and grammatical errors in the given text.
  #|Respond ONLY with a JSON object in this exact format:
  #|{"original": "<original text>", "fixed": "<corrected text>"}
  #|Do not explain. Do not add any text outside the JSON.

///|
let structured_edit_system_prompt : String =
  #|You are an editor assistant. The user will provide text content and an editing instruction.
  #|Respond ONLY with a JSON array of edit operations. Each operation is one of:
  #|- {"action": "replace", "line": <1-based line number>, "old": "<text to find on that line>", "new": "<replacement text>"}
  #|- {"action": "insert", "line": <1-based line number>, "text": "<text to insert after this line>"}
  #|- {"action": "delete", "line": <1-based line number>}
  #|If no changes are needed, return an empty array: []
  #|Do not explain. Do not add any text outside the JSON array.

///|
pub fn format_edit_user_message(text : String, instruction : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("=== TEXT ===\n")
  let lines = split_lines(text)
  for i, line in lines {
    buf
    ..write_string((i + 1).to_string())
    ..write_string(": ")
    ..write_string(line)
    .write_string("\n")
  }
  buf..write_string("=== INSTRUCTION ===\n").write_string(instruction)
  buf.to_string()
}

///|
fn split_lines(text : String) -> Array[String] {
  let result : Array[String] = []
  let buf = StringBuilder::new()
  for ch in text {
    match ch {
      '\n' => {
        result.push(buf.to_string())
        buf.reset()
      }
      _ => buf.write_char(ch)
    }
  }
  let last = buf.to_string()
  if !last.is_empty() || result.is_empty() {
    result.push(last)
  }
  result
}
