///|
/// Mutable store for cognition values, revisions, dependencies, and dirtiness.
pub(all) struct CognitionStore {
  priv values : Map[CognitionKey, CognitionValue]
  priv revisions : Map[CognitionKey, Revision]
  priv dependencies : Map[CognitionKey, Array[CognitionKey]]
  priv reverse_dependencies : Map[CognitionKey, Array[CognitionKey]]
  priv dirty : Map[CognitionKey, Bool]
  priv recompute_counts : Map[CognitionKey, Int]
  priv mut next_revision : Int
}

///|
pub fn CognitionStore::new() -> CognitionStore {
  {
    values: Map::default(),
    revisions: Map::default(),
    dependencies: Map::default(),
    reverse_dependencies: Map::default(),
    dirty: Map::default(),
    recompute_counts: Map::default(),
    next_revision: 0,
  }
}

///|
/// Set an input value, assign a new revision, and dirty all derived dependents.
pub fn CognitionStore::set_input(
  self : CognitionStore,
  key : CognitionKey,
  value : CognitionValue,
) -> Unit {
  self.values[key] = value.copy_value()
  self.bump_revision(key)
  self.dirty.remove(key)
  let _ = self.dirty_dependents(key)
  self.after_input_set(key)
}

///|
fn CognitionStore::after_input_set(
  self : CognitionStore,
  key : CognitionKey,
) -> Unit {
  match key {
    FileText(path) if self.repo_context_is_observed() => {
      self.mark_dirty(FileSummary(path))
      self.mark_dirty(RepoSummary)
    }
    _ => ()
  }
}

///|
fn CognitionStore::repo_context_is_observed(self : CognitionStore) -> Bool {
  self.values.contains(RepoSummary) ||
  self.reverse_dependencies.contains(RepoSummary)
}

///|
pub fn CognitionStore::get_value(
  self : CognitionStore,
  key : CognitionKey,
) -> CognitionValue? {
  match self.values.get(key) {
    Some(value) => Some(value.copy_value())
    None => None
  }
}

///|
pub fn CognitionStore::get_revision(
  self : CognitionStore,
  key : CognitionKey,
) -> Revision? {
  self.revisions.get(key)
}

///|
pub fn CognitionStore::dependencies_of(
  self : CognitionStore,
  key : CognitionKey,
) -> Array[CognitionKey] {
  self.dependencies.get(key).unwrap_or([]).copy()
}

///|
pub fn CognitionStore::dependents_of(
  self : CognitionStore,
  key : CognitionKey,
) -> Array[CognitionKey] {
  self.reverse_dependencies.get(key).unwrap_or([]).copy()
}

///|
pub fn CognitionStore::dependency_edges(
  self : CognitionStore,
) -> Array[Dependency] {
  let edges : Array[Dependency] = []
  for from, inputs in self.dependencies {
    for input in inputs {
      edges.push({ from, input })
    }
  }
  edges.sort_by(fn(a, b) {
    let by_from = a.from.compare(b.from)
    if by_from != 0 {
      by_from
    } else {
      a.input.compare(b.input)
    }
  })
  edges
}

///|
pub fn CognitionStore::is_dirty(
  self : CognitionStore,
  key : CognitionKey,
) -> Bool {
  self.dirty.contains(key)
}

///|
pub fn CognitionStore::dirty_keys(self : CognitionStore) -> Array[CognitionKey] {
  let keys = self.dirty.keys().to_array()
  keys.sort_by(fn(a, b) { a.compare(b) })
  keys
}

///|
pub fn CognitionStore::recompute_count(
  self : CognitionStore,
  key : CognitionKey,
) -> Int {
  self.recompute_counts.get(key).unwrap_or(0)
}

///|
/// Mark one artifact and all of its dependents dirty.
pub fn CognitionStore::mark_dirty(
  self : CognitionStore,
  key : CognitionKey,
) -> Unit {
  self.dirty[key] = true
  let _ = self.dirty_dependents(key)
}

///|
/// Mark all transitive dependents of `key` dirty and return newly dirtied keys.
pub fn CognitionStore::dirty_dependents(
  self : CognitionStore,
  key : CognitionKey,
) -> Array[CognitionKey] {
  let changed : Array[CognitionKey] = []
  self.collect_dirty_dependents(key, changed)
  changed.sort_by(fn(a, b) { a.compare(b) })
  changed
}

///|
/// Recompute dirty derived artifacts whose dependencies are already clean.
/// Returns the keys recomputed by this call, in deterministic order.
pub fn CognitionStore::recompute_dirty(
  self : CognitionStore,
) -> Array[CognitionKey] {
  let recomputed : Array[CognitionKey] = []
  while true {
    match self.next_ready_dirty_key() {
      Some(key) => {
        self.recompute_one(key)
        self.dirty.remove(key)
        recomputed.push(key)
      }
      None => break
    }
  }
  recomputed
}

///|
/// Convenience helper for examples and tests: mark one key dirty, recompute,
/// then return its current value.
pub fn CognitionStore::compute(
  self : CognitionStore,
  key : CognitionKey,
) -> CognitionValue? {
  self.mark_dirty(key)
  let _ = self.recompute_dirty()
  self.get_value(key)
}

///|
fn CognitionStore::bump_revision(
  self : CognitionStore,
  key : CognitionKey,
) -> Unit {
  self.next_revision += 1
  self.revisions[key] = Revision(self.next_revision)
}

///|
fn CognitionStore::collect_dirty_dependents(
  self : CognitionStore,
  key : CognitionKey,
  changed : Array[CognitionKey],
) -> Unit {
  match self.reverse_dependencies.get(key) {
    Some(dependents) =>
      for dependent in dependents {
        if !self.dirty.contains(dependent) {
          self.dirty[dependent] = true
          changed.push(dependent)
          self.collect_dirty_dependents(dependent, changed)
        }
      }
    None => ()
  }
}

///|
fn CognitionStore::next_ready_dirty_key(self : CognitionStore) -> CognitionKey? {
  let keys = self.dirty_keys()
  for key in keys {
    if self.dependencies_clean(key) {
      return Some(key)
    }
  }
  None
}

///|
fn CognitionStore::dependencies_clean(
  self : CognitionStore,
  key : CognitionKey,
) -> Bool {
  match self.dependencies.get(key) {
    Some(inputs) => {
      for input in inputs {
        if self.dirty.contains(input) {
          return false
        }
      }
      true
    }
    None => true
  }
}

///|
fn CognitionStore::set_dependencies(
  self : CognitionStore,
  key : CognitionKey,
  inputs : Array[CognitionKey],
) -> Unit {
  match self.dependencies.get(key) {
    Some(old_inputs) =>
      for input in old_inputs {
        match self.reverse_dependencies.get(input) {
          Some(dependents) => {
            let remaining = dependents.filter(fn(k) { k != key })
            if remaining.length() == 0 {
              self.reverse_dependencies.remove(input)
            } else {
              self.reverse_dependencies[input] = remaining
            }
          }
          None => ()
        }
      }
    None => ()
  }
  self.dependencies[key] = inputs.copy()
  for input in inputs {
    let dependents = self.reverse_dependencies.get(input).unwrap_or([])
    if !dependents.contains(key) {
      dependents.push(key)
    }
    self.reverse_dependencies[input] = dependents
  }
}

///|
fn CognitionStore::recompute_one(
  self : CognitionStore,
  key : CognitionKey,
) -> Unit {
  match key {
    FileText(_) => ()
    FileSummary(path) => self.recompute_file_summary(path)
    RepoSummary => self.recompute_repo_summary()
    QueryContext(query) => self.recompute_query_context(query)
  }
}

///|
fn CognitionStore::store_recomputed(
  self : CognitionStore,
  key : CognitionKey,
  value : CognitionValue,
  inputs : Array[CognitionKey],
) -> Unit {
  let was_new = !self.values.contains(key)
  self.values[key] = value.copy_value()
  self.set_dependencies(key, inputs)
  self.bump_revision(key)
  self.recompute_counts[key] = self.recompute_count(key) + 1
  self.after_recompute(key, was_new~)
}

///|
fn CognitionStore::after_recompute(
  self : CognitionStore,
  key : CognitionKey,
  was_new~ : Bool,
) -> Unit {
  match key {
    FileSummary(_) if was_new && self.values.contains(RepoSummary) =>
      self.mark_dirty(RepoSummary)
    _ => ()
  }
}

///|
fn CognitionStore::recompute_file_summary(
  self : CognitionStore,
  path : String,
) -> Unit {
  let input = FileText(path)
  let text = match self.values.get(input) {
    Some(Text(value)) => value
    _ => ""
  }
  self.store_recomputed(
    FileSummary(path),
    Summary(mock_file_summary(path, text)),
    [input],
  )
}

///|
fn CognitionStore::recompute_repo_summary(self : CognitionStore) -> Unit {
  let summary_keys = self.known_file_summary_keys()
  let items : Array[String] = []
  for key in summary_keys {
    match self.values.get(key) {
      Some(Summary(value)) => items.push(value)
      _ => ()
    }
  }
  let summary = if items.length() == 0 {
    "repo summary: <empty>"
  } else {
    "repo summary:\n" + items.join("\n")
  }
  self.store_recomputed(RepoSummary, Summary(summary), summary_keys)
}

///|
fn CognitionStore::recompute_query_context(
  self : CognitionStore,
  query : String,
) -> Unit {
  let repo_summary = match self.values.get(RepoSummary) {
    Some(Summary(value)) => value
    _ => "repo summary: <missing>"
  }
  self.store_recomputed(
    QueryContext(query),
    ContextBundle(["query: \{query}", repo_summary]),
    [RepoSummary],
  )
}

///|
fn CognitionStore::known_file_summary_keys(
  self : CognitionStore,
) -> Array[CognitionKey] {
  let keys : Array[CognitionKey] = []
  for key, _ in self.values {
    match key {
      FileSummary(_) => keys.push(key)
      _ => ()
    }
  }
  keys.sort_by(fn(a, b) { a.compare(b) })
  keys
}

///|
fn CognitionValue::copy_value(self : CognitionValue) -> CognitionValue {
  match self {
    Text(value) => Text(value)
    Summary(value) => Summary(value)
    ContextBundle(items) => ContextBundle(items.copy())
  }
}

///|
fn mock_file_summary(path : String, text : String) -> String {
  let line_count = if text == "" { 0 } else { count_lines(text) }
  "\{path}: \{line_count} lines, \{text.length()} chars"
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
