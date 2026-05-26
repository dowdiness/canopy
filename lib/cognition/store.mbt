///|
priv struct ContextPackSelection {
  items : Array[ContextItem]
  stats : ContextPackStats
}

///|
/// Mutable store for cognition values, revisions, dependencies, and dirtiness.
pub(all) struct CognitionStore {
  priv values : Map[CognitionKey, CognitionValue]
  priv workspace_files : Map[String, Bool]
  priv revisions : Map[CognitionKey, Revision]
  priv dependencies : Map[CognitionKey, Array[CognitionKey]]
  priv reverse_dependencies : Map[CognitionKey, Array[CognitionKey]]
  priv dirty : Map[CognitionKey, Bool]
  priv recompute_counts : Map[CognitionKey, Int]
  priv provider : CognitionProvider
  priv ranker : ContextRanker
  priv reactive : CognitionReactive
}

///|
pub fn CognitionStore::new() -> CognitionStore {
  CognitionStore::new_with_provider(CognitionProvider::mock())
}

///|
/// Create a cognition store with a deterministic summary provider.
pub fn CognitionStore::new_with_provider(
  provider : CognitionProvider,
) -> CognitionStore {
  CognitionStore::new_with_provider_and_ranker(
    provider,
    ContextRanker::path_match(),
  )
}

///|
/// Create a cognition store with deterministic summary and ranking policies.
pub fn CognitionStore::new_with_provider_and_ranker(
  provider : CognitionProvider,
  ranker : ContextRanker,
) -> CognitionStore {
  let dependencies : Map[CognitionKey, Array[CognitionKey]] = Map::default()
  {
    values: Map::default(),
    workspace_files: Map::default(),
    revisions: Map::default(),
    dependencies,
    reverse_dependencies: Map::default(),
    dirty: Map::default(),
    recompute_counts: Map::default(),
    provider,
    ranker,
    reactive: CognitionReactive::CognitionReactive(dependencies),
  }
}

///|
/// Set an input value, assign a new revision, and dirty all derived dependents.
pub fn CognitionStore::set_input(
  self : CognitionStore,
  key : CognitionKey,
  value : CognitionValue,
) -> Bool {
  match (key, value) {
    (FileText(_), Text(_)) => {
      self.store_input(key, value)
      true
    }
    _ => false
  }
}

///|
/// Return the active workspace file paths known to the cognition store.
pub fn CognitionStore::known_files(self : CognitionStore) -> Array[String] {
  let paths = self.workspace_files.keys().to_array()
  paths.sort_by(fn(a, b) { a.compare(b) })
  paths
}

///|
/// Remove one workspace file input and dirty derived artifacts that referenced it.
pub fn CognitionStore::remove_file(
  self : CognitionStore,
  path : String,
) -> Bool {
  if !self.workspace_files.contains(path) {
    false
  } else {
    let text_key = FileText(path)
    let summary_key = FileSummary(path)
    self.workspace_files.remove(path)
    if self.repo_context_is_observed() {
      self.mark_dirty(RepoSummary)
    }
    let _ = self.dirty_dependents(summary_key)
    let _ = self.dirty_dependents(text_key)
    self.remove_artifact_state(text_key)
    self.remove_artifact_state(summary_key)
    let _ = self.reactive.bump_revision()
    true
  }
}

///|
fn CognitionStore::store_input(
  self : CognitionStore,
  key : CognitionKey,
  value : CognitionValue,
) -> Unit {
  match key {
    FileText(path) => self.workspace_files[path] = true
    _ => ()
  }
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
  self.reactive.dependency_edges()
}

///|
pub fn CognitionStore::current_revision(self : CognitionStore) -> Revision {
  self.reactive.current_revision()
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
/// Build a provenance-bearing, item-budgeted context bundle for `query`.
pub fn CognitionStore::pack_context(
  self : CognitionStore,
  query : String,
  max_items : Int,
) -> Array[ContextItem] {
  self.pack_context_with_options(query, ContextPackOptions::new(max_items~))
}

///|
/// Build a provenance-bearing context bundle constrained by item count and
/// cumulative payload character count.
pub fn CognitionStore::pack_context_with_budget(
  self : CognitionStore,
  query : String,
  max_items : Int,
  max_chars : Int,
) -> Array[ContextItem] {
  self.pack_context_with_options(
    query,
    ContextPackOptions::new(max_items~, max_chars~),
  )
}

///|
/// Build a provenance-bearing context bundle using explicit packing options.
pub fn CognitionStore::pack_context_with_options(
  self : CognitionStore,
  query : String,
  options : ContextPackOptions,
) -> Array[ContextItem] {
  let key = context_key_for_options(query, options)
  let _ = self.compute(key)
  match self.get_value(key) {
    Some(ContextItems(items)) => items
    _ => []
  }
}

///|
/// Build context and return deterministic selection telemetry.
pub fn CognitionStore::pack_context_with_stats(
  self : CognitionStore,
  query : String,
  options : ContextPackOptions,
) -> (Array[ContextItem], ContextPackStats) {
  let _ = self.compute(context_key_for_options(query, options))
  let candidates : Array[ContextItem] = []
  let inputs : Array[CognitionKey] = [RepoSummary]
  self.build_context_candidates(query, candidates, inputs)
  let selection = select_context_items(candidates, options)
  (selection.items, selection.stats)
}

///|
fn context_key_for_options(
  query : String,
  options : ContextPackOptions,
) -> CognitionKey {
  match options.max_chars {
    Some(max_chars) if options.truncate_items =>
      TruncatedContext(query, options.max_items, max_chars)
    Some(max_chars) => BudgetedContext(query, options.max_items, max_chars)
    None => PackedContext(query, options.max_items)
  }
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
  let revision = self.reactive.bump_revision()
  self.revisions[key] = revision
}

///|
fn CognitionStore::remove_artifact_state(
  self : CognitionStore,
  key : CognitionKey,
) -> Unit {
  self.values.remove(key)
  self.revisions.remove(key)
  self.dirty.remove(key)
  self.recompute_counts.remove(key)
  self.remove_dependency_record(key)
  self.remove_incoming_references(key)
}

///|
fn CognitionStore::remove_incoming_references(
  self : CognitionStore,
  key : CognitionKey,
) -> Unit {
  let affected : Array[CognitionKey] = []
  for from, inputs in self.dependencies {
    if inputs.contains(key) {
      affected.push(from)
    }
  }
  let mut changed = false
  for from in affected {
    match self.dependencies.get(from) {
      Some(inputs) => {
        self.dependencies[from] = inputs.filter(fn(input) { input != key })
        changed = true
      }
      None => ()
    }
  }
  if self.reverse_dependencies.contains(key) {
    self.reverse_dependencies.remove(key)
    changed = true
  }
  if changed {
    self.reactive.bump_dependency_revision()
  }
}

///|
fn CognitionStore::remove_dependency_record(
  self : CognitionStore,
  key : CognitionKey,
) -> Unit {
  match self.dependencies.get(key) {
    Some(old_inputs) => {
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
      self.dependencies.remove(key)
      self.reactive.bump_dependency_revision()
    }
    None => ()
  }
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
  self.reactive.bump_dependency_revision()
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
    PackedContext(query, max_items) =>
      self.recompute_packed_context(query, max_items)
    BudgetedContext(query, max_items, max_chars) =>
      self.recompute_budgeted_context(query, max_items, max_chars)
    TruncatedContext(query, max_items, max_chars) =>
      self.recompute_truncated_context(query, max_items, max_chars)
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
    Summary((self.provider.file_summary)(path, text)),
    [input],
  )
}

///|
fn CognitionStore::recompute_repo_summary(self : CognitionStore) -> Unit {
  self.ensure_file_summaries_for_known_texts()
  let summary_keys = self.known_file_summary_keys()
  let items : Array[String] = []
  for key in summary_keys {
    match self.values.get(key) {
      Some(Summary(value)) => items.push(value)
      _ => ()
    }
  }
  self.store_recomputed(
    RepoSummary,
    Summary((self.provider.repo_summary)(items.copy())),
    summary_keys,
  )
}

///|
fn CognitionStore::recompute_query_context(
  self : CognitionStore,
  query : String,
) -> Unit {
  if !self.values.contains(RepoSummary) || self.dirty.contains(RepoSummary) {
    self.recompute_repo_summary()
    self.dirty.remove(RepoSummary)
  }
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
fn CognitionStore::recompute_packed_context(
  self : CognitionStore,
  query : String,
  max_items : Int,
) -> Unit {
  let items : Array[ContextItem] = []
  let inputs : Array[CognitionKey] = [RepoSummary]
  self.build_context_candidates(query, items, inputs)
  self.store_recomputed(
    PackedContext(query, max_items),
    ContextItems(
      select_context_items(items, ContextPackOptions::new(max_items~)).items,
    ),
    inputs,
  )
}

///|
fn CognitionStore::recompute_budgeted_context(
  self : CognitionStore,
  query : String,
  max_items : Int,
  max_chars : Int,
) -> Unit {
  let items : Array[ContextItem] = []
  let inputs : Array[CognitionKey] = [RepoSummary]
  self.build_context_candidates(query, items, inputs)
  self.store_recomputed(
    BudgetedContext(query, max_items, max_chars),
    ContextItems(
      select_context_items(
        items,
        ContextPackOptions::new(max_items~, max_chars~),
      ).items,
    ),
    inputs,
  )
}

///|
fn CognitionStore::recompute_truncated_context(
  self : CognitionStore,
  query : String,
  max_items : Int,
  max_chars : Int,
) -> Unit {
  let items : Array[ContextItem] = []
  let inputs : Array[CognitionKey] = [RepoSummary]
  self.build_context_candidates(query, items, inputs)
  self.store_recomputed(
    TruncatedContext(query, max_items, max_chars),
    ContextItems(
      select_context_items(
        items,
        ContextPackOptions::new(max_items~, max_chars~, truncate_items=true),
      ).items,
    ),
    inputs,
  )
}

///|
fn CognitionStore::build_context_candidates(
  self : CognitionStore,
  query : String,
  items : Array[ContextItem],
  inputs : Array[CognitionKey],
) -> Unit {
  if !self.values.contains(RepoSummary) || self.dirty.contains(RepoSummary) {
    self.recompute_repo_summary()
    self.dirty.remove(RepoSummary)
  }
  self.push_context_item(
    items,
    RepoSummary,
    reason="workspace overview for query: \{query}",
  )
  for summary_key in self.selected_file_summary_keys(query) {
    inputs.push(summary_key)
    self.push_context_item(
      items,
      summary_key,
      reason=(self.ranker.reason_summary)(query, summary_key),
    )
  }
}

///|
fn CognitionStore::push_context_item(
  self : CognitionStore,
  items : Array[ContextItem],
  source : CognitionKey,
  reason~ : String,
) -> Unit {
  match self.values.get(source) {
    Some(Summary(payload)) =>
      items.push({
        source,
        source_revision: self.revisions.get(source).unwrap_or(Revision(0)),
        payload,
        reason,
      })
    Some(Text(payload)) =>
      items.push({
        source,
        source_revision: self.revisions.get(source).unwrap_or(Revision(0)),
        payload,
        reason,
      })
    Some(ContextBundle(lines)) =>
      items.push({
        source,
        source_revision: self.revisions.get(source).unwrap_or(Revision(0)),
        payload: lines.join("\n"),
        reason,
      })
    Some(ContextItems(context_items)) =>
      items.push({
        source,
        source_revision: self.revisions.get(source).unwrap_or(Revision(0)),
        payload: context_items.map(fn(item) { item.payload }).join("\n"),
        reason,
      })
    None => ()
  }
}

///|
fn select_context_items(
  candidates : Array[ContextItem],
  options : ContextPackOptions,
) -> ContextPackSelection {
  match options.max_chars {
    Some(max_chars) =>
      select_context_items_with_char_budget(candidates, options, max_chars)
    None => {
      let items = select_context_items_by_count(candidates, options.max_items)
      { items, stats: context_pack_stats(candidates.length(), items, 0) }
    }
  }
}

///|
fn select_context_items_by_count(
  items : Array[ContextItem],
  max_items : Int,
) -> Array[ContextItem] {
  if max_items <= 0 {
    []
  } else if items.length() <= max_items {
    items.copy()
  } else {
    let selected : Array[ContextItem] = []
    for i in 0..<max_items {
      selected.push(items[i])
    }
    selected
  }
}

///|
fn select_context_items_with_char_budget(
  items : Array[ContextItem],
  options : ContextPackOptions,
  max_chars : Int,
) -> ContextPackSelection {
  if options.max_items <= 0 || max_chars <= 0 {
    { items: [], stats: context_pack_stats(items.length(), [], 0) }
  } else {
    let selected : Array[ContextItem] = []
    let mut used_chars = 0
    let mut truncated_items = 0
    for item in items {
      if selected.length() >= options.max_items {
        break
      }
      let remaining_chars = max_chars - used_chars
      let item_chars = item.payload.length()
      if item_chars <= remaining_chars {
        selected.push(item)
        used_chars += item_chars
      } else if options.truncate_items && remaining_chars > 0 {
        selected.push(truncate_context_item(item, remaining_chars))
        truncated_items += 1
        break
      }
    }
    {
      items: selected,
      stats: context_pack_stats(items.length(), selected, truncated_items),
    }
  }
}

///|
fn truncate_context_item(item : ContextItem, max_chars : Int) -> ContextItem {
  {
    source: item.source,
    source_revision: item.source_revision,
    payload: safe_prefix_by_code_units(item.payload, max_chars),
    reason: item.reason + "; truncated",
  }
}

///|
fn safe_prefix_by_code_units(text : String, max_units : Int) -> String {
  let chunks : Array[String] = []
  let mut used_units = 0
  for ch in text {
    let chunk = "\{ch}"
    let next_units = used_units + chunk.length()
    if next_units > max_units {
      break
    }
    chunks.push(chunk)
    used_units = next_units
  }
  chunks.join("")
}

///|
fn context_pack_stats(
  candidate_count : Int,
  items : Array[ContextItem],
  truncated_items : Int,
) -> ContextPackStats {
  let mut payload_chars = 0
  for item in items {
    payload_chars += item.payload.length()
  }
  {
    selected_items: items.length(),
    skipped_items: candidate_count - items.length(),
    truncated_items,
    payload_chars,
  }
}

///|
fn CognitionStore::ensure_file_summaries_for_known_texts(
  self : CognitionStore,
) -> Unit {
  for path in self.known_files() {
    let summary_key = FileSummary(path)
    if !self.values.contains(summary_key) || self.dirty.contains(summary_key) {
      self.recompute_file_summary(path)
      self.dirty.remove(summary_key)
    }
  }
}

///|
fn CognitionStore::selected_file_summary_keys(
  self : CognitionStore,
  query : String,
) -> Array[CognitionKey] {
  let keys = self.known_file_summary_keys()
  keys.sort_by(fn(a, b) {
    let score_a = (self.ranker.score_summary)(query, a)
    let score_b = (self.ranker.score_summary)(query, b)
    if score_a != score_b {
      score_b.compare(score_a)
    } else {
      a.compare(b)
    }
  })
  keys
}

///|
fn CognitionStore::known_file_summary_keys(
  self : CognitionStore,
) -> Array[CognitionKey] {
  let keys : Array[CognitionKey] = []
  for path in self.known_files() {
    let summary_key = FileSummary(path)
    if self.values.contains(summary_key) {
      keys.push(summary_key)
    }
  }
  keys
}

///|
fn CognitionValue::copy_value(self : CognitionValue) -> CognitionValue {
  match self {
    Text(value) => Text(value)
    Summary(value) => Summary(value)
    ContextBundle(items) => ContextBundle(items.copy())
    ContextItems(items) => ContextItems(items.copy())
  }
}
