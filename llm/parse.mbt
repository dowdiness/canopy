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
          Some(Replace(line=line.to_int(), old~, new=new_text))
        _ => None
      }
    "insert" =>
      match (obj.get("line"), obj.get("text")) {
        (Some(Number(line, ..)), Some(String(text))) =>
          Some(Insert(line=line.to_int(), text~))
        _ => None
      }
    "delete" =>
      match obj.get("line") {
        Some(Number(line, ..)) => Some(Delete(line=line.to_int()))
        _ => None
      }
    _ => None
  }
}
