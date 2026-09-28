///|
/// Structural role of a block in a Markdown document.
///
/// Determined by syntactic position (symbolic annotator) or
/// semantic analysis (LLM annotator, future).
pub(all) enum Role {
  Abstract
  SectionIntro
  CodeExplanation
  KeyPoints
  Unclassified
} derive(Eq, Debug)

///|
pub impl Show for Role with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend Role with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Role with Eq::{equal, not_equal}

///|
pub extend Role with Show::{output, to_string}
