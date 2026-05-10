// Codepoint -> Word_Break property lookups.
//
// Tables are generated from Unicode 15.1 `WordBreakProperty.txt` into
// `property_tables.mbt`.

///|
pub enum WB {
  WbOther
  WbCR
  WbLF
  WbNewline
  WbExtend
  WbZWJ
  WbFormat
  WbRI
  WbKatakana
  WbHebrewLetter
  WbALetter
  WbSingleQuote
  WbDoubleQuote
  WbMidNumLet
  WbMidLetter
  WbMidNum
  WbNumeric
  WbExtendNumLet
  WbWSegSpace
} derive(Eq)

///|
/// `Word_Break` property of a codepoint.
///
/// Returns `WbOther` for codepoints not in any `WordBreakProperty` range.
pub fn wb_of(cp : Int) -> WB {
  if in_range_table(table_wb_cr, cp) {
    return WbCR
  }
  if in_range_table(table_wb_lf, cp) {
    return WbLF
  }
  if in_range_table(table_wb_zwj, cp) {
    return WbZWJ
  }
  if in_range_table(table_wb_newline, cp) {
    return WbNewline
  }
  if in_range_table(table_wb_extend, cp) {
    return WbExtend
  }
  if in_range_table(table_wb_format, cp) {
    return WbFormat
  }
  if in_range_table(table_wb_regional_indicator, cp) {
    return WbRI
  }
  if in_range_table(table_wb_katakana, cp) {
    return WbKatakana
  }
  if in_range_table(table_wb_hebrew_letter, cp) {
    return WbHebrewLetter
  }
  if in_range_table(table_wb_aletter, cp) {
    return WbALetter
  }
  if in_range_table(table_wb_single_quote, cp) {
    return WbSingleQuote
  }
  if in_range_table(table_wb_double_quote, cp) {
    return WbDoubleQuote
  }
  if in_range_table(table_wb_midnumlet, cp) {
    return WbMidNumLet
  }
  if in_range_table(table_wb_midletter, cp) {
    return WbMidLetter
  }
  if in_range_table(table_wb_midnum, cp) {
    return WbMidNum
  }
  if in_range_table(table_wb_numeric, cp) {
    return WbNumeric
  }
  if in_range_table(table_wb_extendnumlet, cp) {
    return WbExtendNumLet
  }
  if in_range_table(table_wb_wsegspace, cp) {
    return WbWSegSpace
  }
  WbOther
}
