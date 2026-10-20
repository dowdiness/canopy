///|
/// An immutable UTF-16 line index. It knows no Markdown or presentation policy.
pub struct TextLines {
  priv text : String
  priv lines : ArrayView[String]
  priv starts : ArrayView[Int]
}

///|
fn index_lines(text : String, lines : ArrayView[String]) -> TextLines {
  let starts : Array[Int] = []
  lines.fold(init=0, (offset, line) => {
    starts.push(offset)
    offset + line.length() + 1
  })
  |> ignore
  { text, lines, starts: starts[:], }
}

///|
pub fn TextLines::TextLines(text : String) -> TextLines {
  let lines = text.split("\n").map(line => line.to_owned()).to_array()
  index_lines(text, lines[:])
}

///|
pub fn TextLines::text(self : TextLines) -> String {
  self.text
}

///|
pub fn TextLines::lines(self : TextLines) -> ArrayView[String] {
  self.lines
}

///|
fn TextLines::line_at(self : TextLines, offset : Int) -> Int {
  match self.starts.binary_search(offset) {
    Ok(index) => index
    Err(index) => index - 1
  }
}

///|
pub struct TextPosition {
  line : Int
  column : Int
}

///|
/// Offsets must belong to this text, including its end. An invalid offset is
/// a caller error, not a request for the closest line.
pub fn TextLines::position(self : TextLines, offset : Int) -> TextPosition {
  guard 0 <= offset && offset <= self.text.length() else {
    abort("offset outside source text")
  }
  let line = self.line_at(offset)
  { line, column: offset - self.starts[line], }
}
