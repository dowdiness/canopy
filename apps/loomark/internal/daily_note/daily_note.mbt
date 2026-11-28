///|
/// The first line that makes a document the template for new daily notes.
pub const TEMPLATE_HEADING : String = "# Daily template"

///|
/// What Today opens for a date.
#derive(Eq, Debug)
pub(all) enum Today[K] {
  /// The most recently changed document whose first line is the date heading.
  Existing(K)
  /// The text of a new daily note.
  New(String)
}

///|
fn first_line(text : String) -> String {
  let line = match text.find("\n") {
    Some(end) => text.exact_view(end~)
    None => text.exact_view()
  }
  line.trim().to_owned()
}

///|
/// `documents` are most recently changed first. A new note copies the
/// template's text after its first line under the date heading.
pub fn[K] today(documents : ArrayView[(K, String)], date : String) -> Today[K] {
  let heading = "# " + date
  for document in documents {
    if first_line(document.1) == heading {
      return Existing(document.0)
    }
  }
  for document in documents {
    let (_, text) = document
    if first_line(text) == TEMPLATE_HEADING {
      let body = match text.find("\n") {
        Some(end) => text.exact_view(start=end).to_owned()
        None => "\n"
      }
      return New(heading + body)
    }
  }
  New(heading + "\n\n")
}

///|
pub extend Today with Eq::{equal, not_equal}

///|
pub extend Today with @moonbitlang/core/debug.Debug::{to_repr}
