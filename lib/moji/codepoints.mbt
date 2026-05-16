// Named codepoint constants.
//
// See `README.md` § "Named codepoint constants" for the inclusion rule.
// Adding a new constant requires citing the rule.

///|
/// U+200B ZERO WIDTH SPACE. Exposed as a named constant because canopy's
/// markdown editor consumes this exact scalar as its empty-paragraph
/// sentinel role. Today the literal is hardcoded across
/// `lang/markdown/edits/compute_markdown_edit.mbt` and
/// `lang/markdown/companion/markdown_companion.mbt`; the follow-up
/// canopy package `lang/markdown/sentinel/` will alias this constant
/// and route all consumers through it (plan:
/// `docs/plans/2026-05-16-moji-zwsp-consolidation.md`).
pub const ZERO_WIDTH_SPACE : String = "\u{200B}"
