// Lambda editor analysis FFI — host ast-grep results -> MoonBit analysis facts.

///|
fn json_int_field(m : Map[String, Json], key : String) -> Result[Int, String] {
  match m.get(key) {
    Some(Json::Number(n, ..)) => {
      let i = n.to_int()
      if i.to_double() == n {
        Ok(i)
      } else {
        Err("field '" + key + "' must be an integer")
      }
    }
    Some(_) => Err("field '" + key + "' must be a number")
    None => Err("missing field '" + key + "'")
  }
}

///|
fn json_string_field(
  m : Map[String, Json],
  key : String,
) -> Result[String, String] {
  match m.get(key) {
    Some(Json::String(s)) => Ok(s)
    Some(_) => Err("field '" + key + "' must be a string")
    None => Err("missing field '" + key + "'")
  }
}

///|
fn parse_ast_grep_match(json : Json) -> Result[@analysis.AstGrepMatch, String] {
  let m = match json {
    Json::Object(m) => m
    _ => return Err("match entry must be an object")
  }
  let byte_start = match json_int_field(m, "byte_start") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let byte_end = match json_int_field(m, "byte_end") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let pattern_id = match json_string_field(m, "pattern_id") {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  Ok(@analysis.AstGrepMatch::AstGrepMatch(byte_start~, byte_end~, pattern_id~))
}

///|
fn parse_ast_grep_matches(
  json : Json,
) -> Result[Array[@analysis.AstGrepMatch], String] {
  let entries = match json {
    Json::Array(entries) => entries
    _ => return Err("expected an array of ast-grep matches")
  }
  let matches : Array[@analysis.AstGrepMatch] = []
  for entry in entries {
    match parse_ast_grep_match(entry) {
      Ok(m) => matches.push(m)
      Err(e) => return Err(e)
    }
  }
  Ok(matches)
}

///|
/// Apply JSON-encoded ast-grep results for a lambda editor handle.
///
/// The JSON shape is:
/// `[ { "byte_start": number, "byte_end": number, "pattern_id": string }, ... ]`.
/// Byte offsets are converted to UTF-16 positions only inside
/// `@analysis.from_ast_grep_matches`, which is the provider adapter boundary.
pub fn apply_ast_grep_results_json(
  handle : Int,
  matches_json : String,
) -> String {
  let h = match lambda_registry.get(handle) {
    Some(h) => h
    None => return "error: invalid handle"
  }
  let json = @json.parse(matches_json) catch {
    err => return "parse error: " + err.to_string()
  }
  let matches = match parse_ast_grep_matches(json) {
    Ok(matches) => matches
    Err(e) => return "parse error: " + e
  }
  let source = h.editor.get_text()
  let snapshot = @facts.SourceSnapshot::SourceSnapshot(
    doc_id=h.editor_id.0.to_string(),
    version=0,
    source~,
  )
  h.companion.set_pattern_analysis(
    @analysis.from_ast_grep_matches(matches, source, snapshot),
    snapshot,
  )
  "ok"
}
