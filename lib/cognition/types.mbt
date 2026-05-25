///|
/// Key for an input or derived cognition artifact.
pub(all) enum CognitionKey {
  FileText(String)
  FileSummary(String)
  RepoSummary
  QueryContext(String)
} derive(Debug, Eq, Hash, Compare)

///|
/// Stored value for a cognition artifact.
pub(all) enum CognitionValue {
  Text(String)
  Summary(String)
  ContextBundle(Array[String])
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
  }
}
