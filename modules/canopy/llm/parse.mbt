///|
pub fn parse_edit_actions(json_str : String) -> Array[EditAction] {
  let json = @json.parse(json_str) catch { _ => return [] }
  match json {
    Object(obj) =>
      match parse_single_action(obj) {
        Some(action) => [action]
        None => []
      }
    Array(arr) =>
      arr.filter_map(fn(item) {
        guard item is Object(obj) else { return None }
        parse_single_action(obj)
      })
    _ => []
  }
}

///|
/// Guard: reject fractional line numbers (e.g. 3.5) that to_int() would silently truncate.
fn is_integer(n : Double) -> Bool {
  n == n.to_int().to_double()
}

///|
fn parse_single_action(obj : Map[String, Json]) -> EditAction? {
  // Shorthand: {"original": "...", "fixed": "..."} without "action" field
  match (obj.get("original"), obj.get("fixed")) {
    (Some(String(original)), Some(String(fixed))) =>
      return Some(FixTypos(original~, fixed~))
    _ => ()
  }
  guard obj.get("action") is Some(String(action_type)) else { return None }
  match action_type {
    "fix_typos" =>
      // With explicit "action" field — same extraction, reached only if
      // the shorthand above didn't match (e.g. has "action" but no "original")
      match (obj.get("original"), obj.get("fixed")) {
        (Some(String(original)), Some(String(fixed))) =>
          Some(FixTypos(original~, fixed~))
        _ => None
      }
    "replace" =>
      match (obj.get("line"), obj.get("old"), obj.get("new")) {
        (Some(Number(line, ..)), Some(String(old)), Some(String(new_text))) =>
          if is_integer(line) {
            Some(Replace(line=line.to_int(), old~, new=new_text))
          } else {
            None
          }
        _ => None
      }
    "insert" =>
      match (obj.get("line"), obj.get("text")) {
        (Some(Number(line, ..)), Some(String(text))) =>
          if is_integer(line) {
            Some(Insert(line=line.to_int(), text~))
          } else {
            None
          }
        _ => None
      }
    "delete" =>
      match obj.get("line") {
        Some(Number(line, ..)) =>
          if is_integer(line) {
            Some(Delete(line=line.to_int()))
          } else {
            None
          }
        _ => None
      }
    _ => None
  }
}
