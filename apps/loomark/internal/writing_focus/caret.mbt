///|
/// A collapsed caret in content coordinates; `y` is its line's centre.
pub(all) struct Caret {
  x : Double
  y : Double
  scroll_top : Double
}

///|
/// What moved the caret since its previous placement.
pub(all) enum CaretCause {
  /// The selection moved through unchanged text, as by arrow keys or a click.
  Navigation
  /// The text changed, as by typing, deletion, paste or Undo.
  Edit
  /// The layout was rebuilt, as after a resize or a font arriving.
  Reflow
}

///|
/// How a shown caret follows its next placement. Every new text position
/// restarts the blink cycle; only a scroll keeps it.
pub enum CaretMove {
  Still
  /// The text scrolled under an unmoved caret; the caret moves with it.
  Scroll
  /// A new text position reached by typing, reflow, or a move that scrolled.
  Jump
  /// Navigation through unchanged text, as by arrow keys or a click.
  Glide
}

///|
/// Only navigation through unchanged text glides; while typing the caret keeps
/// pace with each character, and scrolling or reflow move it with the text.
pub fn caret_move(
  previous : Caret,
  next : Caret,
  cause : CaretCause,
) -> CaretMove {
  let moved = previous.x != next.x || previous.y != next.y
  let scrolled = previous.scroll_top != next.scroll_top
  match (moved, scrolled, cause) {
    (false, false, _) => Still
    (false, true, _) => Scroll
    (true, false, Navigation) => Glide
    (true, _, _) => Jump
  }
}

///|
/// The end of the selection that the user is moving.
pub enum SelectionEnd {
  /// A collapsed selection in a focused, editable text area; the drawn caret
  /// stands in for the native one here.
  Collapsed(Int)
  /// Any other selection end, which keeps the native rendering.
  Endpoint(Int)
}

///|
/// During IME composition the browser reports the composition caret as a
/// collapsed selection, and a converted clause as a range.
pub fn selection_end(
  selection_start : Int,
  selection_end : Int,
  backward~ : Bool,
  editable_focus~ : Bool,
) -> SelectionEnd {
  if selection_start == selection_end && editable_focus {
    Collapsed(selection_start)
  } else if backward {
    Endpoint(selection_start)
  } else {
    Endpoint(selection_end)
  }
}

///|
/// A caret position measured in the mirror, in content coordinates.
pub(all) struct MeasuredCaret {
  offset : Int
  x : Double
  y : Double
}

///|
/// What the previous caret measurement knows about the current source text.
pub(all) enum CaretHistory {
  Unmeasured
  OtherText
  SameText(MeasuredCaret)
}

///|
pub enum CaretMeasure {
  /// The previous measurement still holds, as when scrolling.
  Cached(MeasuredCaret)
  Measure(CaretCause)
}

///|
/// Decides whether a caret at `offset` needs a layout read and what moved it
/// since the previous measurement.
pub fn caret_measure(history : CaretHistory, offset : Int) -> CaretMeasure {
  match history {
    SameText(measured) if measured.offset == offset => Cached(measured)
    Unmeasured => Measure(Reflow)
    OtherText => Measure(Edit)
    SameText(_) => Measure(Navigation)
  }
}

///|
/// Where the bar is drawn in the clipped layer. Like the native caret, it
/// stays inside the content box: a line-start caret shifts right, and a caret
/// after spaces hanging past a soft wrap stays at the right edge.
pub fn drawn_caret_x(
  x : Double,
  layer_width~ : Double,
  half_width~ : Double,
) -> Double {
  x.clamp(min=half_width, max=layer_width - half_width)
}
