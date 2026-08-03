///|
/// Default deterministic provider used by `CognitionStore::new`.
pub fn CognitionProvider::mock() -> CognitionProvider {
  {
    file_summary: fn(path, text) { mock_file_summary(path, text) },
    repo_summary: fn(items) { mock_repo_summary(items) },
  }
}

///|
fn mock_file_summary(path : String, text : String) -> String {
  let line_count = if text == "" { 0 } else { count_lines(text) }
  "\{path}: \{line_count} lines, \{text.length()} chars"
}

///|
fn mock_repo_summary(items : Array[String]) -> String {
  if items.length() == 0 {
    "repo summary: <empty>"
  } else {
    "repo summary:\n" + items.join("\n")
  }
}

///|
fn count_lines(text : String) -> Int {
  let mut lines = 1
  for ch in text {
    if ch == '\n' {
      lines += 1
    }
  }
  lines
}
