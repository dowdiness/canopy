// Role-name layer for canopy's markdown empty-paragraph sentinel.
//
// The literal codepoint identity (U+200B) lives in `@moji.ZERO_WIDTH_SPACE`.
// This package names the editor-policy role: "the codepoint we insert to
// keep an empty paragraph visible and editable inside a markdown buffer."
// Feature packages should consume `EMPTY_PARAGRAPH_SENTINEL` /
// `is_empty_paragraph_text` rather than the raw literal.

///|
/// Codepoint inserted into the markdown buffer to make an otherwise-empty
/// paragraph visible and editable. Aliases `@moji.ZERO_WIDTH_SPACE`.
pub const EMPTY_PARAGRAPH_SENTINEL : String = @moji.ZERO_WIDTH_SPACE

///|
/// True when `s` is exactly the sentinel codepoint and nothing else.
///
/// Intentionally narrow today: legitimate user text containing the sentinel
/// character alongside other content returns `false`. To broaden the rule
/// to "any default-ignorable-only paragraph" (catching paste of ZWNJ, BOM,
/// etc.), iterate codepoints and consult
/// `@moji.is_default_ignorable_code_point`.
pub fn is_empty_paragraph_text(s : String) -> Bool {
  s == EMPTY_PARAGRAPH_SENTINEL
}
