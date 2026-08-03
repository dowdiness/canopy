///|
/// Key for an input or derived cognition artifact.
pub(all) enum CognitionKey {
  FileText(String)
  FileSummary(String)
  RepoSummary
  QueryContext(String)
  PackedContext(String, Int)
  BudgetedContext(String, Int, Int)
  TruncatedContext(String, Int, Int)
} derive(Debug, Eq, Hash, Compare)

///|
/// Deterministic, synchronous provider for deriving cognition summaries.
///
/// Providers produce values only. They must not own or mutate graph state; the
/// store remains responsible for copying values, revisions, dependencies, dirty
/// state, and artifact lifetime.
pub(all) struct CognitionProvider {
  file_summary : (String, String) -> String
  repo_summary : (Array[String]) -> String
}

///|
/// Stored value for a cognition artifact.
pub(all) enum CognitionValue {
  Text(String)
  Summary(String)
  ContextBundle(Array[String])
  ContextItems(Array[ContextItem])
} derive(Debug, Eq)

///|
/// One provenance-bearing item selected for an AI context bundle.
pub(all) struct ContextItem {
  source : CognitionKey
  source_revision : Revision
  payload : String
  reason : String
} derive(Debug, Eq)

///|
/// Deterministic policy for ranking and explaining context candidates.
pub(all) struct ContextRanker {
  score_summary : (String, CognitionKey) -> Int
  reason_summary : (String, CognitionKey) -> String
}

///|
/// Options for deterministic context packing.
pub(all) struct ContextPackOptions {
  max_items : Int
  max_chars : Int?
  truncate_items : Bool
} derive(Debug, Eq)

///|
/// Deterministic telemetry for one context packing operation.
pub(all) struct ContextPackStats {
  selected_items : Int
  skipped_items : Int
  truncated_items : Int
  payload_chars : Int
} derive(Debug, Eq)

///|
/// Create context packing options.
pub fn ContextPackOptions::new(
  max_items~ : Int,
  max_chars? : Int,
  truncate_items? : Bool = false,
) -> ContextPackOptions {
  { max_items, max_chars, truncate_items }
}

///|
/// Monotonic store-local revision. The first stored value receives revision 1.
pub struct Revision(Int) derive(Debug, Eq, Hash, Compare)

///|
pub fn Revision::to_int(self : Revision) -> Int {
  let Revision(n) = self
  n
}

///|
/// Directed edge from a derived artifact to one input artifact it reads.
pub(all) struct Dependency {
  from : CognitionKey
  input : CognitionKey
} derive(Debug, Eq)

///|
pub fn CognitionKey::label(self : CognitionKey) -> String {
  match self {
    FileText(path) => "FileText(\{path})"
    FileSummary(path) => "FileSummary(\{path})"
    RepoSummary => "RepoSummary"
    QueryContext(query) => "QueryContext(\{query})"
    PackedContext(query, max_items) => "PackedContext(\{query}, \{max_items})"
    BudgetedContext(query, max_items, max_chars) =>
      "BudgetedContext(\{query}, \{max_items}, \{max_chars})"
    TruncatedContext(query, max_items, max_chars) =>
      "TruncatedContext(\{query}, \{max_items}, \{max_chars})"
  }
}
