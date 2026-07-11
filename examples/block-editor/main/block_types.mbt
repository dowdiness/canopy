///|
pub enum ListStyle {
  Bullet
  Numbered
  Todo
} derive(Eq, Debug)

///|
pub impl Show for ListStyle with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub enum BlockType {
  Paragraph
  Heading(Int) // level 1–6
  ListItem(ListStyle)
  Quote
  Code(String) // language, empty = plain
  Divider // no text content
  Raw // verbatim, no parsing
} derive(Eq, Debug)

///|
pub impl Show for BlockType with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// The type identifier string (e.g. "paragraph", "heading").
/// Cheap: no allocation, just returns a static string.
pub fn block_type_name(t : BlockType) -> String {
  match t {
    Paragraph => "paragraph"
    Heading(_) => "heading"
    ListItem(_) => "list_item"
    Quote => "quote"
    Code(_) => "code"
    Divider => "divider"
    Raw => "raw"
  }
}

///|
/// Returns (type_str, extra_props) for property storage.
/// Allocates a Map — use `block_type_name` when only the name is needed.
pub fn block_type_to_string(t : BlockType) -> (String, Map[String, String]) {
  match t {
    Paragraph => ("paragraph", {})
    Heading(n) => ("heading", { "level": n.to_string() })
    ListItem(Bullet) => ("list_item", { "list_style": "bullet" })
    ListItem(Numbered) => ("list_item", { "list_style": "numbered" })
    ListItem(Todo) => ("list_item", { "list_style": "todo" })
    Quote => ("quote", {})
    Code(lang) => ("code", { "language": lang })
    Divider => ("divider", {})
    Raw => ("raw", {})
  }
}

///|
/// Inverse — reads "type" string + prop getter.
pub fn block_type_from_props(
  type_str : String,
  get : (String) -> String?,
) -> BlockType {
  match type_str {
    "heading" =>
      Heading(
        match get("level") {
          Some("2") => 2
          Some("3") => 3
          Some("4") => 4
          Some("5") => 5
          Some("6") => 6
          _ => 1
        },
      )
    "list_item" =>
      match get("list_style") {
        Some("numbered") => ListItem(Numbered)
        Some("todo") => ListItem(Todo)
        _ => ListItem(Bullet)
      }
    "quote" => Quote
    "code" => Code(get("language").unwrap_or(""))
    "divider" => Divider
    "raw" => Raw
    _ => Paragraph
  }
}
