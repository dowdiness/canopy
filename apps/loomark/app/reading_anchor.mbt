///|
fn EditorMode::kind(self : Self) -> @editor.Mode {
  match self {
    Text => Text
    Preview => Preview
    Split(..) => Split
  }
}

///|
/// The pane the user is reading in this mode.
fn EditorMode::reading_pane(self : Self) -> ScrollPane {
  match self {
    Text => TextPane
    Preview => PreviewPane
    Split(reading~) => reading
  }
}

///|
/// Split opens reading the pane the user came from.
fn EditorMode::chosen(self : Self, kind : @editor.Mode) -> EditorMode {
  match kind {
    Text => Text
    Preview => Preview
    Split => Split(reading=self.reading_pane())
  }
}

///|
/// The only pane on screen is always the one being read.
fn EditorMode::engaged(self : Self, pane : ScrollPane) -> EditorMode {
  match self {
    Split(..) => Split(reading=pane)
    mode => mode
  }
}
