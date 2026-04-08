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
pub impl Show for Role with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
