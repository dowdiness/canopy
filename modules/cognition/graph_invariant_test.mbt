///|
priv enum GraphOp {
  PutA
  PutB
  RemoveA
  RemoveB
  ComputeQuery
  PackOne
  PackThree
  PackBudget
  RecomputeDirty
}

///|
test "graph invariants hold across edit remove and context packing scenario" {
  let store = CognitionStore::new()
  assert_graph_invariants(store, "initial")

  let _ = store.set_input(FileText("a.mbt"), Text("one"))
  assert_graph_invariants(store, "after add a")

  let _ = store.set_input(FileText("b.mbt"), Text("two"))
  assert_graph_invariants(store, "after add b")

  let _ = store.compute(QueryContext("what changed?"))
  assert_graph_invariants(store, "after query context")

  let _ = store.pack_context("what changed?", 3)
  assert_graph_invariants(store, "after packed context")

  let _ = store.set_input(FileText("a.mbt"), Text("one changed"))
  inspect(
    store.is_dirty(CognitionKey::PackedContext("what changed?", 3)),
    content="true",
  )
  assert_graph_invariants(store, "after edit a")

  let _ = store.recompute_dirty()
  assert_graph_invariants(store, "after recompute edit a")

  inspect(store.remove_file("b.mbt"), content="true")
  assert_graph_invariants(store, "after remove b before recompute")

  let _ = store.recompute_dirty()
  assert_graph_invariants(store, "after remove b recompute")
}

///|
test "generated graph operation sequences preserve invariants" {
  let sequence_length = 4
  for index in 0..<graph_sequence_count(sequence_length) {
    let store = CognitionStore::new()
    let sequence = graph_sequence_from_index(index, sequence_length)
    apply_graph_sequence(store, sequence, "sequence #\{index}")
  }
}

///|
fn apply_graph_sequence(
  store : CognitionStore,
  sequence : Array[GraphOp],
  label : String,
) -> Unit raise {
  assert_graph_invariants(store, "\{label} start")
  for step, op in sequence {
    apply_graph_op(store, op)
    assert_graph_invariants(
      store,
      "\{label} step \{step} \{graph_op_label(op)}",
    )
  }
}

///|
fn apply_graph_op(store : CognitionStore, op : GraphOp) -> Unit {
  match op {
    PutA => {
      let _ = store.set_input(FileText("a.mbt"), Text("content for a"))
      ()
    }
    PutB => {
      let _ = store.set_input(FileText("b.mbt"), Text("content for b"))
      ()
    }
    RemoveA => {
      let _ = store.remove_file("a.mbt")
      ()
    }
    RemoveB => {
      let _ = store.remove_file("b.mbt")
      ()
    }
    ComputeQuery => {
      let _ = store.compute(QueryContext("what changed?"))
      ()
    }
    PackOne => {
      let _ = store.pack_context("what changed?", 1)
      ()
    }
    PackThree => {
      let _ = store.pack_context("what changed?", 3)
      ()
    }
    PackBudget => {
      let _ = store.pack_context_with_budget("what changed?", 3, 80)
      ()
    }
    RecomputeDirty => {
      let _ = store.recompute_dirty()
      ()
    }
  }
}

///|
fn assert_graph_invariants(
  store : CognitionStore,
  label : String,
) -> Unit raise {
  let edges = store.dependency_edges()
  for edge in edges {
    if !graph_key_is_live(store, edge.from) {
      fail(
        "dead dependency source after \{label}: \{edge.from.label()} -> \{edge.input.label()}",
      )
    }
    if !graph_key_is_live(store, edge.input) {
      fail(
        "dead dependency input after \{label}: \{edge.from.label()} -> \{edge.input.label()}",
      )
    }
    if !store.dependencies_of(edge.from).contains(edge.input) {
      fail(
        "edge snapshot missing dependency map entry after \{label}: \{edge.from.label()} -> \{edge.input.label()}",
      )
    }
    if !store.dependents_of(edge.input).contains(edge.from) {
      fail(
        "edge snapshot missing reverse map entry after \{label}: \{edge.from.label()} -> \{edge.input.label()}",
      )
    }
  }
  for key in graph_candidate_keys() {
    for dependent in store.dependents_of(key) {
      if !store.dependencies_of(dependent).contains(key) {
        fail(
          "stale reverse dependency after \{label}: \{key.label()} <- \{dependent.label()}",
        )
      }
    }
  }
  for path in ["a.mbt", "b.mbt"] {
    if !store.known_files().contains(path) {
      assert_path_absent_from_graph(store, path, label)
    }
  }
}

///|
fn assert_path_absent_from_graph(
  store : CognitionStore,
  path : String,
  label : String,
) -> Unit raise {
  for edge in store.dependency_edges() {
    if graph_key_mentions_path(edge.from, path) ||
      graph_key_mentions_path(edge.input, path) {
      fail(
        "deleted path \{path} remains in edge after \{label}: \{edge.from.label()} -> \{edge.input.label()}",
      )
    }
  }
  let text_key = CognitionKey::FileText(path)
  let summary_key = CognitionKey::FileSummary(path)
  if store.get_value(text_key) is Some(_) {
    fail("deleted path \{path} still has FileText value after \{label}")
  }
  if store.get_value(summary_key) is Some(_) {
    fail("deleted path \{path} still has FileSummary value after \{label}")
  }
  if store.dependencies_of(text_key).length() != 0 {
    fail("deleted path \{path} still has FileText dependencies after \{label}")
  }
  if store.dependencies_of(summary_key).length() != 0 {
    fail(
      "deleted path \{path} still has FileSummary dependencies after \{label}",
    )
  }
  if store.dependents_of(text_key).length() != 0 {
    fail("deleted path \{path} still has FileText dependents after \{label}")
  }
  if store.dependents_of(summary_key).length() != 0 {
    fail("deleted path \{path} still has FileSummary dependents after \{label}")
  }
}

///|
fn graph_key_is_live(store : CognitionStore, key : CognitionKey) -> Bool {
  match key {
    FileText(path) =>
      store.known_files().contains(path) &&
      store.get_value(key) is Some(Text(_))
    FileSummary(path) =>
      store.known_files().contains(path) &&
      (store.get_value(key) is Some(Summary(_)) || store.is_dirty(key))
    RepoSummary =>
      store.get_value(key) is Some(Summary(_)) || store.is_dirty(key)
    QueryContext(_) =>
      store.get_value(key) is Some(ContextBundle(_)) || store.is_dirty(key)
    PackedContext(_, _) =>
      store.get_value(key) is Some(ContextItems(_)) || store.is_dirty(key)
    BudgetedContext(_, _, _) =>
      store.get_value(key) is Some(ContextItems(_)) || store.is_dirty(key)
    TruncatedContext(_, _, _) =>
      store.get_value(key) is Some(ContextItems(_)) || store.is_dirty(key)
  }
}

///|
fn graph_key_mentions_path(key : CognitionKey, path : String) -> Bool {
  match key {
    FileText(candidate) => candidate == path
    FileSummary(candidate) => candidate == path
    RepoSummary => false
    QueryContext(_) => false
    PackedContext(_, _) => false
    BudgetedContext(_, _, _) => false
    TruncatedContext(_, _, _) => false
  }
}

///|
fn graph_candidate_keys() -> Array[CognitionKey] {
  [
    FileText("a.mbt"),
    FileSummary("a.mbt"),
    FileText("b.mbt"),
    FileSummary("b.mbt"),
    RepoSummary,
    QueryContext("what changed?"),
    CognitionKey::PackedContext("what changed?", 1),
    CognitionKey::PackedContext("what changed?", 3),
    CognitionKey::BudgetedContext("what changed?", 3, 80),
    CognitionKey::TruncatedContext("what changed?", 3, 80),
  ]
}

///|
fn graph_sequence_from_index(index : Int, length : Int) -> Array[GraphOp] {
  let sequence : Array[GraphOp] = []
  let mut remaining = index
  for _ in 0..<length {
    sequence.push(graph_op_from_code(remaining % graph_op_count()))
    remaining = remaining / graph_op_count()
  }
  sequence
}

///|
fn graph_sequence_count(length : Int) -> Int {
  let mut count = 1
  for _ in 0..<length {
    count = count * graph_op_count()
  }
  count
}

///|
fn graph_op_count() -> Int {
  9
}

///|
fn graph_op_from_code(code : Int) -> GraphOp {
  match code {
    0 => PutA
    1 => PutB
    2 => RemoveA
    3 => RemoveB
    4 => ComputeQuery
    5 => PackOne
    6 => PackThree
    7 => PackBudget
    _ => RecomputeDirty
  }
}

///|
fn graph_op_label(op : GraphOp) -> String {
  match op {
    PutA => "PutA"
    PutB => "PutB"
    RemoveA => "RemoveA"
    RemoveB => "RemoveB"
    ComputeQuery => "ComputeQuery"
    PackOne => "PackOne"
    PackThree => "PackThree"
    PackBudget => "PackBudget"
    RecomputeDirty => "RecomputeDirty"
  }
}
