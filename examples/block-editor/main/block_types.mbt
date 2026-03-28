///|
pub enum ListStyle {
  Bullet
  Numbered
  Todo
} derive(Eq, Show)

///|
pub enum BlockType {
  Paragraph
  Heading(Int) // level 1–6
  ListItem(ListStyle)
  Quote
  Code(String) // language, empty = plain
  Divider // no text content
  Raw // verbatim, no parsing
} derive(Eq, Show)

///|
/// Returns (type_str, extra_props) for JSON serialisation.
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
    "code" =>
      Code(
        match get("language") {
          Some(lang) => lang
          None => ""
        },
      )
    "divider" => Divider
    "raw" => Raw
    _ => Paragraph
  }
}
