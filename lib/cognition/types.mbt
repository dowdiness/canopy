///|
/// Key for an input or derived cognition artifact.
pub(all) enum CognitionKey {
  FileText(String)
  FileSummary(String)
  RepoSummary
  QueryContext(String)
  PackedContext(String, Int)
  BudgetedContext(String, Int, Int)
} derive(Debug, Eq, Hash, Compare)

///|
/// Deterministic provider for deriving cognition summaries.
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
  }
}
