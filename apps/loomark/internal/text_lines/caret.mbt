///|
/// The glyph whose edge marks a caret in a line of text.
pub enum CaretGlyph {
  EmptyLine
  Before(start~ : Int, end~ : Int)
  After(start~ : Int, end~ : Int)
}

///|
/// Selection offsets are UTF-16 code units, so a glyph spans both halves of a
/// surrogate pair.
pub fn caret_glyph(line : String, column : Int) -> CaretGlyph {
  let length = line.length()
  let unit = index => line.code_unit_at(index).to_int()
  if length == 0 {
    EmptyLine
  } else if column < length {
    let pair = column + 1 < length &&
      unit(column) >= 0xD800 &&
      unit(column) <= 0xDBFF
    Before(start=column, end=if pair { column + 2 } else { column + 1 })
  } else {
    let pair = column >= 2 &&
      unit(column - 1) >= 0xDC00 &&
      unit(column - 1) <= 0xDFFF
    After(start=if pair { column - 2 } else { column - 1 }, end=column)
  }
}
