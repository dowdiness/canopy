///|
/// Default deterministic ranker based on query/path matching.
pub fn ContextRanker::path_match() -> ContextRanker {
  {
    score_summary: fn(query, key) { context_score_for_summary(query, key) },
    reason_summary: fn(query, key) { context_reason_for_summary(query, key) },
  }
}

///|
fn context_score_for_summary(query : String, key : CognitionKey) -> Int {
  match key {
    FileSummary(path) => context_score_for_path(query, path)
    _ => 0
  }
}

///|
fn context_reason_for_summary(query : String, key : CognitionKey) -> String {
  match key {
    FileSummary(path) => context_reason_for_path(query, path)
    _ => "workspace artifact"
  }
}

///|
fn context_score_for_path(query : String, path : String) -> Int {
  let filename = file_name_from_path(path)
  let stem = file_stem_from_name(filename)
  if query_contains_non_empty(query, path) {
    100
  } else if query_contains_non_empty(query, filename) {
    80
  } else if query_contains_name(query, stem) {
    60
  } else {
    0
  }
}

///|
fn context_reason_for_path(query : String, path : String) -> String {
  let filename = file_name_from_path(path)
  let stem = file_stem_from_name(filename)
  if query_contains_non_empty(query, path) {
    "path matched query: \{path}"
  } else if query_contains_non_empty(query, filename) {
    "filename matched query: \{filename}"
  } else if query_contains_name(query, stem) {
    "name matched query: \{stem}"
  } else {
    "workspace file summary"
  }
}

///|
fn query_contains_non_empty(query : String, needle : String) -> Bool {
  needle.length() > 0 && query.contains(needle)
}

///|
fn query_contains_name(query : String, name : String) -> Bool {
  name.length() > 1 && query.contains(name)
}

///|
fn file_name_from_path(path : String) -> String {
  match path.rev_split_once("/") {
    Some((_, name)) => name.to_owned()
    None => path
  }
}

///|
fn file_stem_from_name(filename : String) -> String {
  match filename.rev_split_once(".") {
    Some((stem, _)) => stem.to_owned()
    None => filename
  }
}
