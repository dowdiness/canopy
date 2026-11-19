///|
/// Key for an input or derived cognition artifact.
#derive(Debug, Eq, Hash, Compare)
pub(all) enum CognitionKey {
  FileText(String)
  FileSummary(String)
  RepoSummary
  QueryContext(String)
  PackedContext(String, Int32)
  BudgetedContext(String, Int32, Int32)
  TruncatedContext(String, Int32, Int32)
}

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
#derive(Debug, Eq)
pub(all) enum CognitionValue {
  Text(String)
  Summary(String)
  ContextBundle(Array[String])
  ContextItems(Array[ContextItem])
}

///|
/// One provenance-bearing item selected for an AI context bundle.
#derive(Debug, Eq)
pub(all) struct ContextItem {
  source : CognitionKey
  source_revision : Revision
  payload : String
  reason : String
}

///|
/// Deterministic policy for ranking and explaining context candidates.
pub(all) struct ContextRanker {
  score_summary : (String, CognitionKey) -> Int32
  reason_summary : (String, CognitionKey) -> String
}

///|
/// Options for deterministic context packing.
#derive(Debug, Eq)
pub(all) struct ContextPackOptions {
  max_items : Int32
  max_chars : Int32?
  truncate_items : Bool
}

///|
/// Deterministic telemetry for one context packing operation.
#derive(Debug, Eq)
pub(all) struct ContextPackStats {
  selected_items : Int32
  skipped_items : Int32
  truncated_items : Int32
  payload_chars : Int32
}

///|
/// Create context packing options.
pub fn ContextPackOptions::new(
  max_items~ : Int32,
  max_chars? : Int32,
  truncate_items~ : Bool = false,
) -> ContextPackOptions {
  { max_items, max_chars, truncate_items, }
}

///|
/// Monotonic store-local revision. The first stored value receives revision 1.
#derive(Debug, Eq, Hash, Compare)
pub struct Revision(Int32)

///|
pub fn Revision::to_int(self : Revision) -> Int32 {
  let Revision(n) = self
  n
}

///|
/// Directed edge from a derived artifact to one input artifact it reads.
#derive(Debug, Eq)
pub(all) struct Dependency {
  from : CognitionKey
  input : CognitionKey
}

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

///|
pub extend CognitionKey with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CognitionKey with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
pub extend CognitionKey with Eq::{equal, not_equal}

///|
pub extend CognitionKey with Hash::{hash, hash_combine}

///|
pub extend CognitionValue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CognitionValue with Eq::{equal, not_equal}

///|
pub extend ContextItem with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ContextItem with Eq::{equal, not_equal}

///|
pub extend ContextPackOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ContextPackOptions with Eq::{equal, not_equal}

///|
pub extend ContextPackStats with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ContextPackStats with Eq::{equal, not_equal}

///|
pub extend Dependency with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Dependency with Eq::{equal, not_equal}

///|
pub extend Revision with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Revision with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
pub extend Revision with Eq::{equal, not_equal}

///|
pub extend Revision with Hash::{hash, hash_combine}
