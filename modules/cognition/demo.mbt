///|
/// Deterministic mini-demo for the first cognition runtime milestone.
pub fn demo_trace() -> Array[String] {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("let a = 1\n"))
  let _ = store.set_input(FileText("src/b.mbt"), Text("let b = 2\nlet c = 3\n"))
  let _ = store.compute(FileSummary("src/a.mbt"))
  let _ = store.compute(FileSummary("src/b.mbt"))
  let _ = store.compute(RepoSummary)
  let _ = store.compute(QueryContext("what changed?"))

  let _ = store.set_input(FileText("src/a.mbt"), Text("let a = 10\n"))
  let dirty_after_change = store.dirty_keys()
  let recomputed = store.recompute_dirty()
  let a_count = store.recompute_count(FileSummary("src/a.mbt"))
  let b_count = store.recompute_count(FileSummary("src/b.mbt"))
  [
    "dirty after src/a.mbt edit: \{format_key_list(dirty_after_change)}",
    "recomputed: \{format_key_list(recomputed)}",
    "FileSummary(src/a.mbt) count: \{a_count}",
    "FileSummary(src/b.mbt) count: \{b_count}",
  ]
}

///|
fn format_key_list(keys : Array[CognitionKey]) -> String {
  let labels : Array[String] = []
  for key in keys {
    labels.push(key.label())
  }
  labels.join(", ")
}
