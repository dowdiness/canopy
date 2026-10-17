///|
/// Font shorthand of Text's Japanese face.
pub const WRITING_FACE : String = "1em \"IBM Plex Sans JP\""

///|
/// A character in the Japanese faces' unicode ranges, which makes loading a
/// face pick its file.
pub const JAPANESE_SAMPLE : String = "あ"

///|
/// Font shorthands whose files Preview's text needs: paragraphs use the
/// regular face and headings the bold one.
pub fn reading_faces() -> Array[String] {
  ["1em \"BIZ UDMincho\"", "bold 1em \"BIZ UDMincho\""]
}

///|
/// Each character of `text` once, in order of first appearance. Loading fonts
/// scans the text it is given, so a long document passes its alphabet instead.
pub fn distinct_characters(text : String) -> String {
  let seen : Set[Char] = Set([])
  let characters = StringBuilder()
  for c in text {
    if !seen.contains(c) {
      seen.add(c)
      characters.write_char(c)
    }
  }
  characters.to_string()
}
