///|
/// Whether the Text area dims around the writing group.
pub(all) enum WritingIntent {
  Reading
  Writing
  /// Tab was pressed; the next frame learns where focus landed.
  TabNavigation
}

///|
pub fn WritingIntent::settle(
  self : WritingIntent,
  focused~ : Bool,
) -> WritingIntent {
  match self {
    TabNavigation => if focused { Writing } else { Reading }
    Reading | Writing => self
  }
}
